# Reservation module — functional specification

Owner: reservation module (trip publishing, search + matching, reservations, maps, live trip
tracking). These rules come from the project specification and are binding for every step.
Package: `com.carshare.api.reservation`. Tables: `trips`, `reservations`, `trip_events`,
`gps_points`. General code conventions live in [../CLAUDE.md](../CLAUDE.md).

## Technology decisions

| Concern | Decision |
| --- | --- |
| Maps | `flutter_map` + OpenStreetMap tiles (no API key) |
| Geocoding / place search | Nominatim |
| Routing / distance | OSRM |
| Live tracking transport | HTTP polling — **no** websockets |

## Trips

Columns beyond the obvious ones:

- `vehicle_id UUID NULL` — the Vehicles module adds the foreign key later; until then it is a
  plain nullable UUID with a SQL comment saying so.
- `instant_booking BOOLEAN NOT NULL DEFAULT FALSE`
- `cancel_reason` — set when the trip moves to `CANCELLED`.
- `distance_m`, `duration_s` — nullable, filled from OSRM when a route is known.
- `confirmed_seats` — number of seats held by `CONFIRMED` reservations. Maintained by the
  reservation step; it is what makes a trip "locked" (see below).

### State machine

`TripStatus.allowedNext()` is the single source of truth:

```text
SCHEDULED        → DRIVER_EN_ROUTE | CANCELLED
DRIVER_EN_ROUTE  → DRIVER_ARRIVED  | CANCELLED
DRIVER_ARRIVED   → PICKED_UP
PICKED_UP        → IN_PROGRESS
IN_PROGRESS      → COMPLETED
COMPLETED        → (final)
CANCELLED        → (final)
```

Every status change goes through **one** service method, which checks `allowedNext()` and writes
a `trip_events` row (`type`, `actor_id`, `lat`, `lng`, `created_at`). Nothing else may assign a
status. An illegal transition is a `409` `invalid_trip_transition`.

### Publishing and editing

- Only a user with role `DRIVER` whose account status is not `SUSPENDED` or `BANNED` can publish.
- Departure time must be in the future; 1–8 seats; price per seat >= 0.
- A trip may only be edited while `SCHEDULED`, and only by its driver.
- Once the trip has a `CONFIRMED` reservation (`confirmed_seats > 0`) it is **locked**: time,
  route (labels and coordinates) and price can no longer change. Notes, instant booking and
  raising the seat count stay editable. Violations are `409` `trip_locked`.
- Cancelling requires a reason and is only possible from `SCHEDULED` or `DRIVER_EN_ROUTE`.

## Search and matching

Results are ordered by a **match score out of 100**, not by departure time:

| Component | Points | Scale |
| --- | --- | --- |
| Pickup distance | 35 | full at 0 m, linear down to 0 at 2 km |
| Drop-off distance | 25 | full at 0 m, linear down to 0 at 2 km |
| Time gap | 25 | full at 0 min, linear down to 0 at 60 min |
| Driver reliability | 15 | **fixed 15 for now** — TODO plug in rating + punctuality |

Filters: score `>= 50`; status `SCHEDULED` only; enough `seats_available`; never the searcher's
own trips. Keep the bounding-box pre-filter in SQL followed by a haversine distance in Java.
`sort=cheapest|earliest` overrides the score ordering.

## Reservations

Statuses: `PENDING`, `CONFIRMED`, `REFUSED`, `CANCELLED`, `NO_SHOW`, `COMPLETED`. `PENDING` and
`CONFIRMED` are the **active** statuses: they hold a seat and block an overlapping booking.

- `instant_booking = true` → the reservation is `CONFIRMED` immediately; otherwise it stays
  `PENDING` until the driver accepts.
- A `@Scheduled` job auto-refuses a `PENDING` reservation after **2 h** without an answer, or
  **30 min** before departure, whichever comes first, with `cancel_reason = 'no_answer'`.
- Rules: no booking your own trip; the trip must be `SCHEDULED` and still in the future; no two
  active reservations overlapping in time; suspended or banned users cannot book.
- Seat holding keeps the atomic decrement — `UPDATE … WHERE seats_available >= :n`, `409`
  `seats_unavailable` when no row changes — so two passengers can never take the same seat.
  Seats are held the moment the seat is **requested**, not when it is accepted, and released on
  `REFUSED`, `CANCELLED` and auto-refusal.
- `trips.confirmed_seats` goes up when a reservation becomes `CONFIRMED` and down when a confirmed
  one is cancelled. It is the edit lock from the publishing rules above.
- Passenger cancellation is free until **2 h** before departure; later it is still allowed but
  stored with `late_cancellation = true`. Exactly 2 h before is still free.
- When the driver cancels the trip, every active reservation on it becomes `CANCELLED` with
  `cancel_reason = 'trip_cancelled'` and `late_cancellation = false`, and all seats are released.

### Overlap rule

A trip occupies the window `[departure_time, departure_time + duration_s)`, falling back to
**2 h** when OSRM gave no `duration_s`. A booking is refused `409` `overlapping_reservation` when
that window intersects the window of any trip the passenger already holds an active reservation
on. Windows that merely touch — one trip arriving exactly as the next leaves — do not overlap.
Re-booking a trip the passenger already holds is the same rule applied to itself, so it needs no
separate check.

### Pickup code

Each reservation gets a **4-digit pickup code** from `SecureRandom`, stored **in plain text**
(`CHAR(4)`).

> Changed from the original plan, which stored only a hash. The driver has to read the code the
> passenger shows them and type it in, so the server must be able to show it to the passenger; a
> hash would only hide it from a database reader, not from anyone who can call the API as that
> passenger. The protection that matters is who may read it, and that is enforced in the DTOs:
> the code is returned **only** to the passenger who owns the reservation, and **only** once the
> reservation is `CONFIRMED`. The driver-facing record has no pickup code field at all.

`pickup_code_attempts` counts wrong codes typed by the driver; the cap of **3** is enforced by the
service at check-in time (step 6), not by a database constraint.

## Live tracking

- The driver sends positions from `DRIVER_EN_ROUTE` until `COMPLETED` — not only during
  `IN_PROGRESS`. Confirmed passengers poll the latest position every **5 s**.
- Every position is stored in `gps_points` (`trip_id`, `lat`, `lng`, `speed_mps`, `recorded_at`)
  so the trip can be replayed. `recorded_at` is the phone's own clock, which is what keeps an
  offline buffer in order; `created_at` is when the server received it.
- `trips` also carries `last_lat`, `last_lng`, `last_position_at` — a copy of the newest kept
  position, so the live view is one row read rather than a sort over every point.

### Sending positions

One request carries **1–50** points, so the app can flush a buffer after a dead spot. The batch
is sorted by `recorded_at` server-side rather than trusted.

A point is kept only when it is at least **2 s** newer than the last point kept. That single rule
covers both filters: anything at or before the trip's `last_position_at` is already too old, and
anything bunched up behind a kept point is dropped. A point outside 1–50, or with a missing or
impossible coordinate, is `400` `invalid_positions` — the whole batch is refused, not trimmed.

The geofences and the deviation check run **per kept point, in time order**, not only on the last
one. A buffer flushed after a dead spot can cross a geofence part-way through, and checking only
its newest point would leave the trip stuck one status behind.

### Automatic transitions

All of them go through the one `changeStatus` method, with the triggering position on the event.

| Trigger | From | To |
| --- | --- | --- |
| Within **100 m** of the pickup point | `DRIVER_EN_ROUTE` | `DRIVER_ARRIVED` |
| Every confirmed passenger aboard or `NO_SHOW`, at least one aboard | `DRIVER_ARRIVED` | `PICKED_UP` |
| Within **100 m** of the drop-off point | `IN_PROGRESS` | `COMPLETED` |

The driver starts the ride themselves (`PICKED_UP` → `IN_PROGRESS`) through the status endpoint.
On completion every checked-in reservation becomes `COMPLETED`.

`DRIVER_ARRIVED` → `PICKED_UP` is also a legal manual transition, but the status endpoint refuses
it with `409` `passengers_not_boarded` while any `CONFIRMED` reservation is neither checked in nor
`NO_SHOW`. Otherwise a driver could set off by hand and leave those reservations `CONFIRMED` for
ever, since completion only closes checked-in ones. The automatic transition above is unaffected:
it has already proved everybody is settled, and it does not go through that endpoint.

### Check-in

The driver submits the code the passenger shows them, only while the trip is `DRIVER_ARRIVED` and
only for a `CONFIRMED` reservation that has not checked in. A wrong code raises
`pickup_code_attempts` and answers `400` `wrong_pickup_code` naming the tries left; the third
wrong code writes a `CHECK_IN_FAILED` event and answers `409` `pickup_code_locked`, as does every
attempt after that. The right code sets `checked_in_at` and writes `CHECK_IN`.

> The attempt counter has to survive the failure, so check-in runs with
> `noRollbackFor = ApiException.class` — the same reason the auth module uses it for failed
> sign-ins. Without it, the rollback would hand the driver unlimited guesses.

### No-show

Allowed once the trip has been `DRIVER_ARRIVED` for **5 min**, measured from the latest
`DRIVER_ARRIVED` trip event against the injected `Clock`; exactly 5:00 is allowed, 4:59 is `409`
`no_show_too_early`. The reservation becomes `NO_SHOW` and both `seats_available` and
`confirmed_seats` are released with the atomic updates from step 5.

### Deviation

Only while `IN_PROGRESS`, and only when `route_polyline` is set — with no planned route the check
is skipped rather than guessed. The distance is measured to the route's **segments**, not just its
vertices, after decoding the Google encoded polyline. Over **300 m** sets `deviating = true` and
writes `DEVIATION`; coming back under sets it false and writes `DEVIATION_RESOLVED`. Nothing is
written while the state is unchanged, so a long detour raises one alert rather than one per fix.

### The live view

`GET /api/trips/{id}/live` answers the driver, or a passenger whose reservation on the trip is
`CONFIRMED` **or `COMPLETED`**; anyone else gets `404`. `COMPLETED` is in that list because the
drop-off geofence completes the trip and the reservation in the same request — without it the
passenger's next poll would answer `404` instead of showing them the trip they just finished. It reports `tripStatus`, the last position, the current `target`
(`PICKUP` before `PICKED_UP`, `DROPOFF` after), `distanceToTargetM` as a haversine,
`etaSeconds` as that distance over the last known speed with a floor of **8.3 m/s** (~30 km/h,
so a stopped car still gives a usable number), `deviating`, and for a passenger their own
reservation status and whether they are aboard.

## Flutter screens (follow the Figma mockups)

- Bottom navigation bar: **Home, Trips, Live, Profile**.
- Home: map plus the "Where to today?" search sheet.
- Results list showing the match percentage.
- Trip details with a seat stepper.
- My trips with **Upcoming / Past / Cancelled** tabs.
- Live tracking screen with the status stepper.
- Pickup check-in screen with QR code and the 4-digit code.

## Step order

1. `V7` migration, `Trip` / `TripEvent` entities, `TripStatus`
2. Trip publishing: DTOs, service, controller, transition + publish/edit/cancel tests
3. Search + matching (match score above)
4. `V8` migration, `Reservation` entity
5. Reservation flow (instant booking, auto-refuse job, pickup codes, atomic seats)
6. `V9` migration, `gps_points`, live tracking, geofences, check-in, no-show, deviation
7. Flutter models + `ReservationService`
8. Flutter publish / search / details / my-trips screens + bottom navigation
9. Maps (`flutter_map`, Nominatim, OSRM) and the live tracking screen
10. Trip completion screen: replay of `gps_points` plus the event log
11. Ratings: 1–5 stars, once per side, only after `COMPLETED`, editable for 24 h
