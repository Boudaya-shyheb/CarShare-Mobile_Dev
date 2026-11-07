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

Statuses: `PENDING`, `CONFIRMED`, `REFUSED`, `CANCELLED`, `NO_SHOW`, `COMPLETED`.

- `instant_booking = true` → the reservation is `CONFIRMED` immediately; otherwise it stays
  `PENDING` until the driver accepts.
- A `@Scheduled` job auto-refuses a `PENDING` reservation after **2 h** without an answer, or
  **30 min** before departure, whichever comes first.
- Rules: no booking your own trip; no two active reservations overlapping in time; suspended or
  banned users cannot book.
- Seat holding keeps the atomic decrement — `UPDATE … WHERE seats_available >= :n`, `409` when no
  row changes — so two passengers can never take the same seat.
- Passenger cancellation is free until **2 h** before departure; later it is still allowed but
  stored with `late_cancellation = true`.
- Each reservation gets a **4-digit pickup code**. Only a hash is stored, with an attempts
  counter capped at **3**.

## Live tracking

- The driver sends positions from `DRIVER_EN_ROUTE` until `COMPLETED` — not only during
  `IN_PROGRESS`. Confirmed passengers poll the latest position every **5 s**.
- Geofence **100 m** around the pickup point → `DRIVER_ARRIVED` automatically; around the
  drop-off point → `COMPLETED`.
- Pickup check-in: the driver submits the passenger's 4-digit code, allowed only while
  `DRIVER_ARRIVED` → `PICKED_UP`.
- No-show: after **5 min** in `DRIVER_ARRIVED` with no code, the driver can mark the reservation
  `NO_SHOW` and the seat is released.
- Deviation alert: more than **300 m** off the straight/planned route stores a `DEVIATION` event.
- Every position is stored in `gps_points` (`trip_id`, `lat`, `lng`, `speed`, `recorded_at`) so
  the trip can be replayed.

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
