# Reservation module — API reference

Every endpoint of `com.carshare.api.reservation`: trips, search, reservations and live tracking.
Written for the Flutter work and for anyone integrating against the module. The functional rules
behind these endpoints are in [reservation-spec.md](reservation-spec.md); code conventions are in
[../CLAUDE.md](../CLAUDE.md).

- Base URL: `http://localhost:8081/api` locally. The Flutter client reads it from
  `--dart-define=CARSHARE_API_BASE_URL` and defaults to `http://10.0.2.2:8081/api` (the Android
  emulator's route to the host).
- **Every endpoint here needs a bearer token.** The module adds no public routes.
  `Authorization: Bearer <accessToken>`, from `POST /api/auth/signin`.
- Timestamps are ISO-8601 UTC instants (`2026-11-20T07:30:00Z`), which `DateTime.parse` reads.
  Ids are UUID strings. Money is a JSON number with two decimals.
- A Postman collection covering the whole flow is at
  [CarShare-Reservation.postman_collection.json](CarShare-Reservation.postman_collection.json).

## Errors

Every failure is an RFC-7807 `ProblemDetail` with an extra `code` property. Match on `code`, never
on `detail` — the detail text is user-facing English meant for a SnackBar and may be reworded.

```json
{
  "type": "about:blank",
  "title": "Conflict",
  "status": 409,
  "detail": "Those seats have just been taken.",
  "instance": "/api/trips/4f1c.../reservations",
  "code": "seats_unavailable"
}
```

On the Flutter side `ApiClient` already turns this into
`ApiException(message, statusCode, code)`, and `authErrorMessage(error)` unwraps it for display.

### Every code this module returns

| `code` | Status | Means |
| --- | --- | --- |
| `validation_error` | 400 | A request body failed its Jakarta annotations |
| `invalid_coordinates` | 400 | A latitude or longitude is out of range |
| `same_origin_and_destination` | 400 | Pickup and drop-off are the same point |
| `invalid_search` | 400 | A search parameter is missing, unparseable, or out of range |
| `invalid_status` | 400 | The admin trips list was asked for a status that does not exist |
| `invalid_positions` | 400 | A position batch is empty, over 50, or holds a bad point |
| `wrong_pickup_code` | 400 | The code did not match; the detail names the tries left |
| `own_trip` | 400 | You cannot book a seat on a trip you are driving |
| `cancel_reason_required` | 400 | A cancellation needs a reason |
| `vehicle_required` | 400 | A trip needs the vehicle it will be driven with |
| `trip_seats_exceed_vehicle_capacity` | 400 | More seats offered than the vehicle has |
| `invalid_trip_scope` | 400 | `scope` is not upcoming, past or cancelled |
| `invalid_reservation_scope` | 400 | Same, for the reservation list |
| `account_not_found` | 401 | The signed-in account no longer exists |
| `driver_role_required` | 403 | Only a driver account can publish |
| `account_banned` | 403 | The account is BANNED: refused on every route, and at sign-in |
| `account_suspended` | 403 | The account is SUSPENDED and the suspension has not ended; the body carries `statusUntil` |
| `license_not_verified` | 403 | The driver licence is missing, waiting for review, or rejected; the message says which |
| `license_expired` | 403 | The licence expires before the trip's departure day |
| `trip_not_found` | 404 | No such trip — **also what a non-owner gets** |
| `vehicle_not_found` | 404 | The vehicle is not yours (never a hint that it exists), or the trip has none on record |
| `reservation_not_found` | 404 | No such reservation, or it is not yours |
| `vehicle_not_approved` | 409 | CarShare support has not approved the vehicle (pending or rejected) |
| `vehicle_not_available` | 409 | The vehicle is reported or inactive |
| `vehicle_in_use` | 409 | Deleting a vehicle that is on a trip that has not finished |
| `trip_not_editable` | 409 | The trip is no longer SCHEDULED |
| `trip_locked` | 409 | A confirmed reservation froze the time, route and price |
| `seats_below_reserved` | 409 | The new seat count is under the seats already confirmed |
| `invalid_trip_transition` | 409 | The state machine forbids that status change |
| `trip_not_bookable` | 409 | The trip is not SCHEDULED, or has already left |
| `overlapping_reservation` | 409 | You hold a reservation on a trip at that time |
| `seats_unavailable` | 409 | Someone took those seats first |
| `invalid_reservation_state` | 409 | The reservation's status forbids that action |
| `trip_not_tracking` | 409 | The trip is not in a status that allows this tracking call |
| `already_checked_in` | 409 | That passenger is already aboard |
| `pickup_code_locked` | 409 | Three wrong codes; check-in is closed |
| `no_show_too_early` | 409 | The driver has not waited five minutes yet |
| `passengers_not_boarded` | 409 | A confirmed passenger is neither checked in nor a no-show |
| `service_unavailable` | 503 | The database or mail server is unreachable |

> **Known wart:** a `DataIntegrityViolationException` is mapped in the shared
> `common/ApiExceptionHandler` to 409 `email_already_in_use`, which would read oddly if the
> `uq_reservations_active_per_passenger` index ever fired. The overlap rule rejects a duplicate
> booking long before the index does, so this needs two genuinely simultaneous requests from one
> passenger for the same trip. Left alone because that handler belongs to the auth module.

## Statuses

### `TripStatus`

| Status | Means | Next |
| --- | --- | --- |
| `SCHEDULED` | Published, taking reservations | `DRIVER_EN_ROUTE`, `CANCELLED` |
| `DRIVER_EN_ROUTE` | Driving to the pickup point, sending positions | `DRIVER_ARRIVED`, `CANCELLED` |
| `DRIVER_ARRIVED` | Waiting at the pickup point, checking people in | `PICKED_UP` |
| `PICKED_UP` | Everybody aboard, not yet moving | `IN_PROGRESS` |
| `IN_PROGRESS` | On the way, deviation watched | `COMPLETED` |
| `COMPLETED` | Arrived — final | — |
| `CANCELLED` | Called off with a reason — final | — |

Reservations may only be created while `SCHEDULED`. Positions are accepted from
`DRIVER_EN_ROUTE` through `IN_PROGRESS`.

### `ReservationStatus`

| Status | Means | Holds a seat? |
| --- | --- | --- |
| `PENDING` | Waiting for the driver to answer | yes |
| `CONFIRMED` | Accepted, or booked on an instant-booking trip | yes, and counts toward the trip's edit lock |
| `REFUSED` | Turned down by the driver, or auto-refused unanswered | no |
| `CANCELLED` | Called off by the passenger, or by the driver cancelling the trip | no |
| `NO_SHOW` | Did not turn up at the pickup point | no |
| `COMPLETED` | Rode the trip to the end | no |

`PENDING` and `CONFIRMED` are the **active** statuses: they hold a seat and block an overlapping
booking.

## Trips

### `POST /api/trips` — publish

Allowed when **all** of these hold, checked in this order:

1. the account is a `DRIVER` (`driver_role_required`) and not `SUSPENDED` (`account_suspended`) or
   `BANNED` (`account_banned`);
2. the driver licence is `APPROVED` (`license_not_verified`) and does not expire before the
   departure day, Tunisian time (`license_expired`);
3. `vehicleId` is present (`vehicle_required`), belongs to the caller (`vehicle_not_found`), is
   `ACTIVE` (`vehicle_not_available`), is `APPROVED` (`vehicle_not_approved`), and has at least
   `seatsTotal` seats (`trip_seats_exceed_vehicle_capacity`).

→ **201**

```json
{
  "vehicleId": "0b7e2c1a-...",
  "originLabel": "Tunis Centre",
  "originLat": 36.8065,
  "originLng": 10.1815,
  "destinationLabel": "Sousse",
  "destinationLat": 35.8256,
  "destinationLng": 10.6360,
  "departureTime": "2026-11-21T07:30:00Z",
  "seatsTotal": 3,
  "pricePerSeat": 12.50,
  "instantBooking": false,
  "notes": "Meet by the station.",
  "distanceM": 140000,
  "durationS": 7200,
  "routePolyline": "_p~iF~ps|U_ulLnnqC_mqNvxq`@"
}
```

`departureTime` must be in the future, `seatsTotal` 1–8, `pricePerSeat` 0–9999.99, `notes` ≤ 500
chars, `routePolyline` ≤ 20000 chars. `vehicleId` is required for new trips. `notes`,
`distanceM`, `durationS` and `routePolyline` are optional. `routePolyline` is the Google encoded polyline of the planned route —
without it the deviation alert is skipped for the trip.

Response — `TripDetail`, the shape every trip write returns:

```json
{
  "id": "4f1c8f2a-...", "driverId": "9ab2...", "driverName": "Ahmed Ben Salah", "vehicleId": "0b7e2c1a-...",
  "originLabel": "Tunis Centre", "originLat": 36.8065, "originLng": 10.1815,
  "destinationLabel": "Sousse", "destinationLat": 35.8256, "destinationLng": 10.636,
  "departureTime": "2026-11-21T07:30:00Z",
  "seatsTotal": 3, "seatsAvailable": 3, "confirmedSeats": 0,
  "pricePerSeat": 12.50, "status": "SCHEDULED", "instantBooking": false, "locked": false,
  "notes": "Meet by the station.", "cancelReason": null,
  "distanceM": 140000, "durationS": 7200,
  "routePolyline": "_p~iF~ps|U_ulLnnqC_mqNvxq`@",
  "createdAt": "2026-11-20T22:10:00Z", "updatedAt": null
}
```

Errors: `driver_role_required`, `account_banned`, `account_suspended`, `license_not_verified`, `license_expired`,
`vehicle_required`, `vehicle_not_found`, `vehicle_not_available`, `vehicle_not_approved`,
`trip_seats_exceed_vehicle_capacity`, `invalid_coordinates`, `same_origin_and_destination`,
`validation_error`.

`trips.vehicle_id` is a foreign key to `vehicles(id)` (`ON DELETE SET NULL`, migration V24), so a
trip always points at a real vehicle. Trips published before V24 may have `null`.

### `GET /api/trips/mine` — the driver's own trips

`scope=upcoming` never lists a trip that is still `SCHEDULED` more than two hours after its
departure (see "Trips nobody started" below); a trip already under way stays.

`?scope=upcoming|past|cancelled`

Returns the caller's trips only. Omit `scope` for all of them. `upcoming` covers every status
before the trip finishes, `past` is `COMPLETED`, `cancelled` is `CANCELLED` — the three tabs of the
My trips screen. → array of `TripSummary`:

```json
[{
  "id": "4f1c...", "originLabel": "Tunis Centre", "destinationLabel": "Sousse",
  "departureTime": "2026-11-21T07:30:00Z", "seatsTotal": 3, "seatsAvailable": 1,
  "pricePerSeat": 12.50, "status": "SCHEDULED", "instantBooking": false,
  "distanceM": 140000, "durationS": 7200
}]
```

Errors: `invalid_trip_scope`.

### `GET /api/trips/search` — search and match

Any signed-in account. Query parameters:

| Parameter | Required | Notes |
| --- | --- | --- |
| `originLat`, `originLng` | yes | Where the passenger wants picking up |
| `destinationLat`, `destinationLng` | yes | Where they want dropping off |
| `departureTime` | yes | ISO instant; trips within ±3 h are considered |
| `seats` | no | 1–8, default 1 |
| `sort` | no | `best` (default), `cheapest`, `earliest` |

```
GET /api/trips/search?originLat=36.8065&originLng=10.1815
   &destinationLat=35.8256&destinationLng=10.636
   &departureTime=2026-11-21T07:30:00Z&seats=2&sort=best
```

Only trips that are `SCHEDULED`, still in the future, have enough free seats, are not the
caller's own, sit within 2 km of **both** ends, and score ≥ 50 come back — at most 50 of them.

```json
[{
  "tripId": "4f1c...", "driverId": "9ab2...", "driverName": "Ahmed Ben Salah",
  "originLabel": "Tunis Centre", "destinationLabel": "Sousse",
  "departureTime": "2026-11-21T07:30:00Z", "expectedArrival": "2026-11-21T09:30:00Z",
  "durationS": 7200, "seatsAvailable": 3,
  "pricePerSeat": 12.50, "instantBooking": false,
  "pickupDistanceM": 0, "dropoffDistanceM": 0, "timeGapMin": 0, "matchScore": 100
}]
```

`matchScore` is the percentage the results screen shows: 35 points for pickup distance, 25 for
drop-off distance, 25 for the time gap, 15 for driver reliability (flat for now).

`expectedArrival` is always present, so a result card can show "08:15 → 09:30" without opening
each trip. `durationS` is the route duration the driver published and is **null** when the trip
carries no route — in that case `expectedArrival` is the default two-hour window, and a client
that wants to distinguish a measured arrival from an assumed one checks `durationS`.

Errors: `invalid_search`, `invalid_coordinates`, `same_origin_and_destination`.

### `GET /api/trips/{tripId}` — one trip

Any signed-in account, so a passenger can open a search result. → `TripDetail`.
Errors: `trip_not_found`.

### `GET /api/trips/{tripId}/vehicle` — the car on a trip

Any signed-in account, so a passenger sees the car before booking. → **200**

```json
{
  "id": "0b7e2c1a-...", "brand": "Peugeot", "model": "208", "year": 2022, "color": "Black",
  "registrationNumber": "123 TU 4567", "seatsNumber": 4, "airConditioning": true, "hasPhoto": true
}
```

`registrationNumber` is filled only for the trip's driver and for passengers holding a confirmed
seat; everybody else gets `null`. `404 vehicle_not_found` for a trip published before V24.

### `GET /api/trips/{tripId}/vehicle/photo` — its photo

The vehicle's primary photo (or its first one) as image bytes, `Cache-Control: no-store`.
`404 vehicle_photo_not_found` when the vehicle has none.

### `PUT /api/trips/{tripId}` — edit

Trip owner, while `SCHEDULED`. Same body as publish. Once the trip has a confirmed reservation it
is **locked**: departure time, both labels and all four coordinates, and the price can no longer
change. Notes, instant booking and raising the seat count stay editable. → `TripDetail`.

Errors: `trip_not_found`, `trip_not_editable`, `trip_locked`, `seats_below_reserved`,
`invalid_coordinates`, `same_origin_and_destination`, `validation_error`.

### `POST /api/trips/{tripId}/cancel` — cancel

Trip owner, from `SCHEDULED` or `DRIVER_EN_ROUTE`. Releases every seat and closes every active
reservation on the trip with `cancel_reason` `trip_cancelled`.

```json
{ "reason": "Car broke down" }
```

→ `TripDetail` with `status` `CANCELLED` and `cancelReason` set.
Errors: `trip_not_found`, `invalid_trip_transition`, `validation_error`.

### `POST /api/trips/{tripId}/status` — move the trip along by hand

Trip owner. `CANCELLED` is refused here so a reason is always recorded — use the cancel endpoint.

```json
{ "status": "DRIVER_EN_ROUTE", "lat": 36.8065, "lng": 10.1815 }
```

`lat` and `lng` are optional and are stored on the event. In practice the app calls this twice:
once for `DRIVER_EN_ROUTE` when the driver sets out, and once for `IN_PROGRESS` when the ride
starts. `DRIVER_ARRIVED`, `PICKED_UP` and `COMPLETED` normally happen on their own — and a manual
`PICKED_UP` is refused while any confirmed passenger is neither checked in nor a no-show.

→ `TripDetail`. Errors: `trip_not_found`, `invalid_trip_transition`, `cancel_reason_required`,
`passengers_not_boarded`, `invalid_coordinates`.

### `GET /api/trips/{tripId}/events` — the audit trail

Trip owner. Every status change, reservation decision and tracking alert, oldest first.

```json
[{
  "id": "7c2e...", "type": "PUBLISHED", "actorId": "9ab2...",
  "lat": 36.8065, "lng": 10.1815, "detail": null, "createdAt": "2026-11-20T22:10:00Z"
}]
```

`type` is one of `PUBLISHED`, `UPDATED`, `DRIVER_EN_ROUTE`, `DRIVER_ARRIVED`, `PICKED_UP`,
`IN_PROGRESS`, `COMPLETED`, `CANCELLED`, `CHECK_IN`, `CHECK_IN_FAILED`, `NO_SHOW`, `DEVIATION`,
`DEVIATION_RESOLVED`, `RESERVATION_REQUESTED`, `RESERVATION_CONFIRMED`, `RESERVATION_REFUSED`,
`RESERVATION_CANCELLED`. `actorId` is null when nobody decided it — an auto-refusal, for instance.

Errors: `trip_not_found`.

### Trips nobody started

A trip still `SCHEDULED` more than **2 hours after its departure time** will not happen. Every
**10 minutes** a job (`TripExpiryJob` → `TripExpiryService`) moves each such trip to `CANCELLED`
through the state machine, with `cancelReason` = `Expired: the driver never started this trip.`
and a `CANCELLED` trip event with no actor. The seats are released and every active reservation
on the trip is cancelled (`TRIP_CANCELLED`). The "upcoming" lists (`GET /trips/mine?scope=upcoming`
and `GET /reservations/mine?scope=upcoming`) already hide such trips before the job has run.

## Reservations

### `POST /api/trips/{tripId}/reservations` — book a seat

Any signed-in account except the trip's driver, not `SUSPENDED` or `BANNED`. → **201**

```json
{ "seats": 2 }
```

Seats are held the moment they are requested. On an `instantBooking` trip the reservation comes
back `CONFIRMED` with its `pickupCode`; otherwise `PENDING` with `pickupCode` null.

```json
{
  "id": "e71a...",
  "trip": {
    "tripId": "4f1c...", "driverId": "9ab2...", "driverName": "Ahmed Ben Salah",
    "originLabel": "Tunis Centre", "destinationLabel": "Sousse",
    "departureTime": "2026-11-21T07:30:00Z", "expectedArrival": "2026-11-21T09:30:00Z",
    "pricePerSeat": 12.50, "tripStatus": "SCHEDULED", "distanceM": 140000, "durationS": 7200
  },
  "passengerId": "c413...", "seats": 2, "status": "PENDING",
  "pickupCode": null, "lateCancellation": false, "cancelReason": null,
  "decidedAt": null, "cancelledAt": null, "createdAt": "2026-11-20T22:20:00Z"
}
```

`trip` deliberately carries no seat counts — they move whenever anyone books. Read
`GET /api/trips/{tripId}` for live availability.

Errors: `own_trip`, `trip_not_bookable`, `account_banned`, `account_suspended`, `overlapping_reservation`,
`seats_unavailable`, `trip_not_found`, `validation_error`.

### `GET /api/reservations/mine` — the passenger's own reservations

`?scope=upcoming|past|cancelled`

The caller's own reservations, newest first. `upcoming` is `PENDING` + `CONFIRMED`, `past` is
`COMPLETED` + `NO_SHOW`, `cancelled` is `CANCELLED` + `REFUSED`. Omit `scope` for all.
→ array of the record above. `pickupCode` is filled in **only** on `CONFIRMED` rows, and only here
— it never appears in anything a driver can read.

Errors: `invalid_reservation_scope`.

### `GET /api/trips/{tripId}/reservations` — who booked

Trip owner only. → array of `PassengerView`, oldest first. No pickup code: the driver has to be
shown it by the passenger.

```json
[{
  "reservationId": "e71a...", "passengerId": "c413...", "passengerName": "Mouna Trabelsi",
  "seats": 2, "status": "PENDING", "lateCancellation": false, "cancelReason": null,
  "decidedAt": null, "cancelledAt": null, "createdAt": "2026-11-20T22:20:00Z"
}]
```

Errors: `trip_not_found`.

### `POST /api/reservations/{reservationId}/accept`
### `POST /api/reservations/{reservationId}/refuse`

Trip owner, while the reservation is `PENDING` and the trip still `SCHEDULED`. No body.
Accepting raises the trip's `confirmedSeats`, which locks it against time, route and price edits.
Refusing releases the held seats and stores `cancelReason` `refused_by_driver`.

→ `PassengerView` with the new `status` and `decidedAt`.
Errors: `reservation_not_found`, `trip_not_found`, `invalid_reservation_state`,
`trip_not_bookable`, `seats_unavailable`.

### `POST /api/reservations/{reservationId}/cancel`

The passenger who owns the reservation, while it is `PENDING` or `CONFIRMED`.

```json
{ "reason": "Plans changed" }
```

Free until exactly 2 h before departure; later it still works but comes back with
`lateCancellation: true`. → the passenger's own `ReservationDetail`.
Errors: `cancel_reason_required`, `reservation_not_found`, `invalid_reservation_state`.

### Auto-refusal

No endpoint. A `@Scheduled` job runs every minute and refuses any `PENDING` reservation that has
waited 2 h for an answer, or whose trip leaves within 30 minutes, with `cancelReason` `no_answer`.
The seats are released. The passenger sees it as a `REFUSED` row in the `cancelled` scope.

## Live tracking

### `POST /api/trips/{tripId}/positions`

Trip owner, while the trip is `DRIVER_EN_ROUTE`, `DRIVER_ARRIVED`, `PICKED_UP` or `IN_PROGRESS`.
One point while online, or a whole buffer after a dead spot: **1–50** points.

```json
{ "points": [
  { "lat": 36.8071, "lng": 10.1822, "speedMps": 11.4, "recordedAt": "2026-11-21T07:28:00Z" },
  { "lat": 36.8068, "lng": 10.1819, "speedMps": 6.2,  "recordedAt": "2026-11-21T07:28:04Z" }
] }
```

`speedMps` is optional. A point is kept only when it is at least 2 s newer than the last one kept,
so anything stale or bunched up is dropped silently — `lastPositionAt` in the response tells the
app how much of its buffer landed. A batch that is empty, over 50, or holds a bad coordinate is
refused whole with `invalid_positions`.

Each kept point may move the trip along on its own: within 100 m of the pickup point while
`DRIVER_EN_ROUTE` → `DRIVER_ARRIVED`; within 100 m of the drop-off while `IN_PROGRESS` →
`COMPLETED`, closing every checked-in reservation. While `IN_PROGRESS` with a `routePolyline` set,
more than 300 m off the route flips `deviating` on and writes `DEVIATION`; coming back under
writes `DEVIATION_RESOLVED`.

→ the same `LiveView` as below. Errors: `trip_not_found`, `trip_not_tracking`,
`invalid_positions`.

### `GET /api/trips/{tripId}/live`

The trip's driver, or a passenger whose reservation on it is `CONFIRMED` or `COMPLETED`. Anyone
else gets `trip_not_found`. Built to be polled every **5 s** — there are no websockets.

```json
{
  "tripStatus": "IN_PROGRESS",
  "lastLat": 36.1240, "lastLng": 10.4010, "lastPositionAt": "2026-11-21T08:12:00Z",
  "target": "DROPOFF", "distanceToTargetM": 34120, "etaSeconds": 1483,
  "deviating": false,
  "myReservationStatus": "CONFIRMED", "checkedIn": true
}
```

| Field | Notes |
| --- | --- |
| `target` | `PICKUP` until the passengers are aboard, then `DROPOFF` |
| `distanceToTargetM` | Straight-line metres from the last position to that target; null before the first position |
| `etaSeconds` | That distance over the last known speed, with a floor of 8.3 m/s (~30 km/h); null before the first position |
| `lastLat`, `lastLng`, `lastPositionAt` | null until the driver sends a position |
| `myReservationStatus`, `checkedIn` | null for the driver; the caller's own values for a passenger |

`COMPLETED` is accepted for the passenger because the drop-off geofence completes the trip and the
reservation in one request — without it the passenger's next poll would 404 instead of showing the
finished trip.

Errors: `trip_not_found`.

### `POST /api/reservations/{reservationId}/check-in`

Trip owner, while the trip is `DRIVER_ARRIVED` and the reservation is `CONFIRMED` and not yet
checked in. The driver types in the 4-digit code the passenger shows them.

```json
{ "code": "0472" }
```

A wrong code costs an attempt and returns `400 wrong_pickup_code`, whose `detail` names the tries
left ("That code is not right. 2 tries left."). The third wrong code writes a `CHECK_IN_FAILED`
event and returns `409 pickup_code_locked`, as does every attempt after it — including a correct
one. The right code stamps `checked_in_at` and writes `CHECK_IN`; if that was the last confirmed
passenger still to board, the trip moves to `PICKED_UP` by itself.

→ `PassengerView`. Errors: `reservation_not_found`, `trip_not_found`, `trip_not_tracking`,
`invalid_reservation_state`, `already_checked_in`, `wrong_pickup_code`, `pickup_code_locked`.

### `POST /api/reservations/{reservationId}/no-show`

Trip owner, once the trip has been `DRIVER_ARRIVED` for **5 minutes**, for a `CONFIRMED`
reservation that has not checked in. No body. The reservation becomes `NO_SHOW` and both the free
seats and the confirmed-seat count are released. If that was the last passenger being waited for,
the trip moves to `PICKED_UP`.

→ `PassengerView` with `status` `NO_SHOW`. Errors: `reservation_not_found`, `trip_not_found`,
`trip_not_tracking`, `invalid_reservation_state`, `already_checked_in`, `no_show_too_early`.

## The order of calls for a full trip

Two accounts: a driver and a passenger. `D` and `P` mark who calls.

| # | Who | Call | Leaves the trip at |
| --- | --- | --- | --- |
| 1 | D | `POST /auth/signin` | — |
| 2 | P | `POST /auth/signin` | — |
| 3 | D | `POST /trips` | `SCHEDULED` |
| 4 | P | `GET /trips/search?...` | `SCHEDULED` |
| 5 | P | `POST /trips/{tripId}/reservations` `{"seats":1}` | reservation `PENDING` |
| 6 | D | `GET /trips/{tripId}/reservations` | — |
| 7 | D | `POST /reservations/{id}/accept` | reservation `CONFIRMED`, trip locked |
| 8 | P | `GET /reservations/mine?scope=upcoming` | reveals `pickupCode` |
| 9 | D | `POST /trips/{tripId}/status` `{"status":"DRIVER_EN_ROUTE"}` | `DRIVER_EN_ROUTE` |
| 10 | D | `POST /trips/{tripId}/positions` — repeatedly | `DRIVER_EN_ROUTE` |
| 11 | P | `GET /trips/{tripId}/live` — every 5 s | — |
| 12 | D | a position within 100 m of the pickup point | `DRIVER_ARRIVED` *(automatic)* |
| 13 | D | `POST /reservations/{id}/check-in` `{"code":"0472"}` | `PICKED_UP` *(automatic, last passenger aboard)* |
| 14 | D | `POST /trips/{tripId}/status` `{"status":"IN_PROGRESS"}` | `IN_PROGRESS` |
| 15 | D | `POST /trips/{tripId}/positions` — repeatedly | `IN_PROGRESS`, deviation watched |
| 16 | D | a position within 100 m of the drop-off point | `COMPLETED`, reservation `COMPLETED` *(automatic)* |
| 17 | P | `GET /trips/{tripId}/live` | shows the finished trip |
| 18 | D | `GET /trips/{tripId}/events` | the whole audit trail |

Notes on the automatic steps:

- **12 and 16** need no call of their own: send positions and the geofence does it. If the driver
  never gets within 100 m, step 13 is still reachable only from `DRIVER_ARRIVED`, so the app
  should fall back to `POST /status` with `DRIVER_ARRIVED`.
- **13** moves the trip to `PICKED_UP` only when every confirmed passenger is aboard or marked a
  no-show, and at least one is aboard. With several passengers, repeat step 13 for each.
  `POST /status` with `PICKED_UP` is the manual fallback and is refused while anyone is still
  expected (`passengers_not_boarded`).
- On an `instantBooking` trip, steps 6 and 7 fall away: the reservation is `CONFIRMED` at step 5
  and the code is in that response.
- If the driver never answers, the auto-refuse job ends the reservation after 2 h, or 30 minutes
  before departure.

## Ratings

A rating is left after the trip is `COMPLETED`. The passenger rates the driver; the driver rates
each passenger who actually boarded. One rating per rater/rated pair per trip, changeable for
**24 hours** after it was left, then locked.

Whether somebody may rate at all is decided by what happened on the trip, never by a field in
the request: a passenger must hold a `COMPLETED` reservation **and** have been checked in. A
no-show, a refusal or a cancellation leaves nobody to rate and nobody to be rated.

### `POST /api/trips/{tripId}/ratings`

```json
{ "toUserId": "9ab2...", "stars": 5, "comment": "Smooth drive" }
```

`stars` is 1–5, `comment` is optional and at most 500 characters (blank is stored as null).
→ `RatingView`:

```json
{
  "id": "7c1d...", "tripId": "4f1c...", "fromUserId": "c1bd...", "toUserId": "9ab2...",
  "toUserName": "Ahmed Ben Salah", "stars": 5, "comment": "Smooth drive",
  "editable": true, "createdAt": "2026-11-21T10:02:00Z", "updatedAt": null
}
```

Errors: `trip_not_found` (also when the caller was not on the trip — a 404 so the route cannot
be used to probe other people's trips), `trip_not_completed`, `not_on_this_trip`,
`cannot_rate_yourself`, `already_rated`, `validation_error`.

### `PUT /api/trips/{tripId}/ratings/{toUserId}`

```json
{ "stars": 4, "comment": "Was a little harsh" }
```

→ the same `RatingView`. Errors: `rating_not_found`, `rating_locked` (the 24 h window closed),
`trip_not_found`, `trip_not_completed`, `validation_error`.

### `GET /api/trips/{tripId}/ratings/mine`

Everyone the caller may rate on this trip, and what they have already said. The completion
screen draws itself from this one call.

```json
{
  "tripId": "4f1c...", "tripCompleted": true,
  "parties": [
    { "userId": "9ab2...", "name": "Ahmed Ben Salah", "role": "DRIVER", "myRating": null }
  ]
}
```

A passenger gets one party (their driver); a driver gets one per passenger who boarded.
Errors: `trip_not_found`.

### Where ratings show up

A user's rating is the **mean of the last 50 ratings they received**, to one decimal, and is
`null` until somebody rates them. The count beside it is **every** rating they ever received,
not just the fifty the average used.

| Shape | Fields |
| --- | --- |
| `TripSearchResult` | `driverRating`, `driverRatingCount` |
| `TripDetail` | `driverRating`, `driverRatingCount` |
| `PassengerView` | `passengerRating`, `passengerRatingCount` |

The reliability component of the match score uses it:
`15 x (0.6 x rating/5 + 0.4 x punctuality)`, where punctuality is the share of the driver's
completed trips whose `DRIVER_ARRIVED` event landed within 5 minutes of the advertised
departure. A driver with neither figure scores **10** — a newcomer is not buried under
established drivers, nor placed above them. When only one of the two is known, that half stands
for the whole component.

### `GET /api/users/me/stats` — the figures on the Profile card

The signed-in user's own numbers, for the Trips / Rating / No-shows card on the Profile screen.
Any signed-in user may call it; it answers about the caller only (the id comes from the token,
never from the request) and changes nothing. The path sits beside the user module's
`/api/users/me/preferences`, `/photo`, `/sanctions` and `/emergency-contacts`; it is a separate
controller, `UserTripStatsController`, so neither module's routes move.

```json
{
  "tripsAsDriver": 5,
  "tripsAsPassenger": 18,
  "totalTrips": 23,
  "rating": 4.6,
  "ratingCount": 12,
  "noShows": 2,
  "reliability": 14
}
```

| Field | Meaning |
| --- | --- |
| `tripsAsDriver` | Trips the user drove to `COMPLETED` |
| `tripsAsPassenger` | Their reservations that ended `COMPLETED` |
| `totalTrips` | The two added together |
| `rating` | Mean of the last 50 ratings received, one decimal; `null` when nobody has rated them |
| `ratingCount` | Every rating received, not only the fifty the mean used |
| `noShows` | Reservations of theirs a driver marked `NO_SHOW` |
| `reliability` | The driver-reliability points the match score gives them, 0 to 15 (see above); 10 for a user with neither a rating nor a completed trip |

A user with no history gets zeros, `rating` `null` and `reliability` 10. Without a valid token the
answer is 403, as for every authenticated route.

### `GET /api/trips/{tripId}/track`

The whole driven trail, oldest first, for the replay on the completion screen. Open to the
driver, and to a passenger whose reservation is `COMPLETED` or `NO_SHOW`.

```json
[
  { "lat": 36.8071, "lng": 10.1822, "recordedAt": "2026-11-21T07:28:00Z" },
  { "lat": 36.8068, "lng": 10.1819, "recordedAt": "2026-11-21T07:28:04Z" }
]
```

Ordered by `recordedAt`, not by arrival, so a buffer sent late after a dead spot still sits in
the right place on the map. Errors: `trip_not_found`.

## Admin

Every route under `/api/admin/**` needs an account whose `app_users.role` is `ADMIN`. It is the same
rule that protects `GET /api/admin/users`: `SecurityConfig` lets the path through only for
`ROLE_ADMIN`, which the token filter builds from the role stored on the account. Anyone else,
signed in or not, gets **403**. The Flutter app sends admin accounts to the admin dashboard after
sign-in.

In development, an account is made an admin in SQL (there is no screen for it):

```sql
UPDATE app_users SET role = 'ADMIN' WHERE email = 'your-test-account@example.com';
```

Sign out and in again afterwards so the app reloads the role.

The admin trips screens use four routes. The list belongs to the admin operations screens
(`AdminOperationsController`); the other three belong to this module.

### `GET /api/admin/trips`

`?status=SCHEDULED&limit=50`, both optional. Trips ordered by departure, newest first.
`status` is any `TripStatus`, or `ALL` (the default); `limit` defaults to **100** and is kept
between 1 and 500.

```json
[{
  "id": "4f1c...", "driverId": "9ab2...", "driverName": "Ahmed Ben Salah",
  "origin": "Tunis Centre", "destination": "Sousse",
  "departureTime": "2026-11-21T07:30:00Z", "status": "SCHEDULED",
  "incidentReported": false, "vehicleId": null, "cancelReason": null,
  "createdAt": "2026-11-20T22:10:00Z"
}]
```

`incidentReported` is true while the trip is flagged as deviating from its route.
Errors: `invalid_status`.

### `GET /api/admin/trips/{tripId}`

The trip, everyone who booked it, and everything that happened to it.

```json
{
  "trip": { "...": "a TripDetail, exactly as GET /api/trips/{tripId} returns it" },
  "reservations": [{ "...": "PassengerView rows, oldest first, never with a pickup code" }],
  "events": [{ "...": "EventView rows, oldest first" }]
}
```

Errors: `trip_not_found`.

### `POST /api/admin/trips/{tripId}/cancel`

```json
{ "reason": "Reported by two riders" }
```

`reason` is required, 1 to 300 characters. It runs the driver's own cancel path, so the same rules
hold: only from `SCHEDULED` or `DRIVER_EN_ROUTE` (anything later is a `409`
`invalid_trip_transition`), every seat is released, and every active reservation is closed with
`cancel_reason` `trip_cancelled`. The `CANCELLED` event records the **admin's** id as `actorId` and
the reason as `detail`. → `TripDetail` with `status` `CANCELLED`.

Errors: `validation_error`, `trip_not_found`, `invalid_trip_transition`.

### `GET /api/admin/stats`

Every counter of the dashboard in one call.

```json
{
  "users": 12, "tripsTotal": 30, "tripsInProgress": 2, "tripsCompleted": 18,
  "tripsCancelled": 4, "reservations": 41, "lostAndFoundReports": 3
}
```

`tripsInProgress` counts the trips the driver has set off on and not finished: `DRIVER_EN_ROUTE`,
`DRIVER_ARRIVED`, `PICKED_UP` and `IN_PROGRESS`. `reservations` counts every reservation, whatever
its status.

## What the Vehicles module shows about trips

`GET /api/vehicles` and `GET /api/vehicles/{id}` carry three fields the app needs to pick a car
for a trip: `reviewStatus` (`PENDING`, `APPROVED`, `REJECTED`), `reviewReason`, and
`tripsCompleted` — how many trips the vehicle has **completed** ("Used in N trips"). The count
comes from `ReservationQueries.completedTripsByVehicle`. `DELETE /api/vehicles/{id}` answers
`409 vehicle_in_use` while the vehicle is on a trip that has not finished
(`ReservationQueries.vehicleHasUpcomingTrips`).

## Using the Reservation module from another module

Do not read or write our tables directly, and do not inject our repositories. Inject
**`com.carshare.api.reservation.ReservationQueries`**, a read-only service that answers in small
records — never JPA entities, whose lazy associations would fail once the transaction closes.

```java
@Service
public class VehicleService {
    private final ReservationQueries reservations;

    public VehicleService(ReservationQueries reservations) {
        this.reservations = reservations;
    }

    public void delete(UUID vehicleId) {
        if (reservations.vehicleHasUpcomingTrips(vehicleId)) {
            throw new ApiException(HttpStatus.CONFLICT, "vehicle_in_use",
                    "This car is booked for a trip that has not finished yet.");
        }
        // ...
    }
}
```

| Method | Answers |
| --- | --- |
| `tripFacts(tripId)` | `Optional<TripFacts>` — route, times, status, seats, vehicle |
| `participants(tripId)` | the driver, then every passenger who held a seat |
| `wasOnTrip(tripId, userId)` | the authorisation check: did this person drive it or ride it |
| `events(tripId)` | the audit trail, oldest first |
| `gpsTrack(tripId)` | every GPS fix, in `recordedAt` order |
| `vehicleHasUpcomingTrips(vehicleId)` | true while a trip using that car has not finished |

Three rules:

1. **Never write to our tables.** A module that needs a trip or a reservation changed calls the
   REST API like any other client, so the business rules actually run.
2. **Never return our entities** out of your own code either; copy what you need into your own
   record.
3. **Take the next free migration number after pulling `main`.** Flyway versions are global to
   the schema, so two students both adding `V11` is a merge conflict that only shows up when the
   app refuses to start.
