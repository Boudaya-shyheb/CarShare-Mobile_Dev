# CarShare mobile app index

Last indexed: 2026-11-12 (current working tree, including uncommitted files)

## System overview

CarShare is a Flutter application backed by a Spring Boot REST API and PostgreSQL/Neon.
The mobile client owns presentation, device capabilities, local buffering, and the current
session token. Business rules, authorization, and durable data live in the backend.

```text
Flutter UI -> service singletons -> ApiClient -> /api REST endpoints
    |                                   |
    +-> device location / maps          +-> Spring services -> JPA -> PostgreSQL
    +-> secure token storage
    +-> SQLite GPS queue and support cache
```

Primary technology:

- Flutter / Dart 3.13, Material UI
- Spring Boot 4.1, Java 17, Spring Security and Spring Data JPA
- PostgreSQL on Neon, schema managed by Flyway
- OpenStreetMap tiles, Nominatim geocoding, and OSRM routing
- Bearer sessions stored in `flutter_secure_storage`
- Offline GPS buffering with `sqflite`

## Startup and navigation

| Concern | Entry point | Notes |
| --- | --- | --- |
| Process bootstrap | `lib/main.dart` | Initializes deep links, starts the app, and restores the session asynchronously. |
| Root widget | `lib/app.dart` | Creates `MaterialApp`, applies the theme, and hosts the authentication gate. |
| Global navigation | `lib/navigation.dart` | Exposes `carShareNavigatorKey`, used by deep links and app-level navigation. |
| Signed-out flow | `WelcomePage` -> `SignInPage` / `SignUpPage` | Password reset is opened from sign-in or a deep link. |
| Signed-in user flow | `MainShell` | Four persistent tabs: Home, Trips, Live, Profile. |
| Signed-in admin flow | `AdminDashboardPage` | Admins bypass the regular four-tab shell. |

The authentication gate listens to `AuthService.isRestoringSession` and
`AuthService.currentUser`. A restored user is routed by role: `admin` goes to the admin
dashboard; all other roles go to `MainShell`.

`MainShell` keeps its pages alive with an `IndexedStack`. Cross-screen tab changes use the
global `carShareShellTab` notifier, while `carShareLiveTripId` identifies the trip the Live
tab should display.

## Client layout

```text
lib/
  main.dart, app.dart       bootstrap and authentication gate
  navigation.dart           global navigator key
  theme.dart                shared Material theme and color tokens
  data/                     static catalogs used by forms
  models/                   REST/domain data objects and JSON mapping
  services/                 HTTP, auth, domain APIs, device services, local persistence
  pages/                    screens; reservation and support have subdirectories
  widgets/                  reusable visual components
```

Current client inventory: 78 Dart files, including 15 model files, 12 service files, 32 page
files, 14 shared widget files, and 5 data/bootstrap/theme files.

## Feature ownership

| Feature | Screens | Client services and models | Backend package |
| --- | --- | --- | --- |
| Authentication and account | `welcome`, `sign_in`, `sign_up`, `reset_password`, `profile` | `AuthService`, `ApiClient`, `UserProfile` | `auth`, `security`, `users` |
| User preferences and safety | `preferences`, `emergency_contacts`, `sanctions` | `UserManagementService`, `UserPreferences`, `UserSanction` | `users` |
| Vehicles | `my_vehicles`, `vehicle_details`, `vehicle_form` | `VehicleService`, `Vehicle`, `VehicleRegistration`, `vehicle_catalog` | `vehicles` |
| Trip search and publishing | `reservation/home_search`, `place_search`, `search_results`, `publish_trip`, `trip_details` | `ReservationService`, `GeoService`, `LocationService`, `Trip`, `Place`, `TripSearchResult` | `reservation` |
| Booking and trip management | `reservation/my_trips`, `driver_trip`, `check_in_dialog` | `ReservationService`, `Trip`, `Reservation`, `TripEvent` | `reservation` |
| Live tracking | `reservation/live`, `live_driver`, `live_passenger`, `trip_completed` | `TrackingService`, `ReservationService`, `LocalDatabase`, `LiveView`, `Rating` | `reservation` |
| Support | `support/support`, `report_problem`, `ticket_details`, `support_notifications`, `admin_support_ticket_details` | `SupportService`, `SupportLocalDatabase`, `SupportTicket`, `SupportCategory`, `SupportTicketDetails`, `SupportNotification`, `SupportReportTarget`, `SupportEvidenceSection` | `support` |
| Lost and found | `lost_and_found` | `ApiClient`, `LocalDatabase` | `lostandfound` |
| Administration | `admin_dashboard`, `admin_users`, `admin_operations` | `ApiClient`, `AuthService` | `admin`, `users` |

## Service layer

All major services are singletons. Pages should call them instead of constructing their own
HTTP clients.

| Service | Responsibility |
| --- | --- |
| `ApiClient` | Base URL, JSON requests, multipart uploads, bearer token attachment, timeouts, and API error conversion. Default base URL is `http://10.0.2.2:8081/api`; override with `CARSHARE_API_BASE_URL`. |
| `AuthService` | Session restoration, sign-up/sign-in/sign-out, social auth, password reset, profile updates, and the current-user notifiers. |
| `ReservationService` | Trips, search, bookings, status transitions, live views, check-in/no-show, tracks, and ratings. |
| `TrackingService` | Captures driver positions, buffers them locally, and uploads batches of at most 50 points every four seconds. |
| `VehicleService` | Vehicle CRUD, default selection, and photo upload/delete/primary selection. |
| `UserManagementService` | Preferences, sanctions, and emergency contacts. |
| `SupportService` | Support categories and tickets, report targets, details, evidence, statements, contestations, in-app notifications, and offline ticket/category caching and drafts. |
| `GeoService` | Public geocoding and routing requests. |
| `LocationService` | Device permission handling and current location, with Tunis as the fallback map location. |
| `DeepLinkService` | Receives app links and opens pending password-reset navigation after startup. |
| `LocalDatabase` | SQLite storage for queued GPS points and lost-and-found local state. |

## Data and state

- REST payloads are mapped by plain Dart classes in `lib/models`; timestamps use
  `DateTime.parse` against backend ISO-8601 values.
- Authentication state is held in `ValueNotifier`s on `AuthService`; the app does not use a
  third-party state-management package.
- Most screen state is local `State` plus service calls.
- The session token is the only authentication credential persisted on-device and is stored
  with `flutter_secure_storage`.
- Driver GPS samples survive transient network failures in SQLite and are removed only after
  successful upload. Support categories, ticket lists, and a per-user ticket draft are also
  persisted locally by `SupportLocalDatabase`.
- Support persistence is isolated in `carshare_support.db`. It contains
  `cached_support_tickets`, `cached_support_categories`, and `support_ticket_drafts`; ticket
  rows are partitioned by authenticated user ID.

## Backend map

The backend is under `backend/src/main/java/com/carshare/api`:

| Package | Responsibility |
| --- | --- |
| `auth` | Credentials, social identity, sessions, password-reset codes, reset mail. |
| `security` | Bearer-token filter, authorization rules, token hashing, authenticated principal. |
| `users` | Profile, preferences, contacts, sanctions, user administration. |
| `vehicles` | Vehicle ownership, review state, and photo storage. |
| `reservation` | Trips, matching, reservations, tracking, check-in, ratings, reputation, scheduled refusal. |
| `support` | Ticket categories and lifecycle, evidence, statements, decisions, contestations, status history, and credibility scores. |
| `lostandfound` | Trip-linked lost/found reports and resolution. |
| `admin` | Cross-module operational views and admin actions. |
| `common` | Structured API errors and global exception handling. |

The database schema is built by 20 ordered migrations in
`backend/src/main/resources/db/migration`. Hibernate runs with `ddl-auto: validate`; schema
changes therefore require a new migration.

## API surface by client module

- Auth/account: `/auth/*`, `/users/me`, `/users/me/photo`
- User settings: `/users/me/preferences`, `/users/me/sanctions`,
  `/users/me/emergency-contacts/*`
- Vehicles: `/vehicles/*`
- Trips: `/trips`, `/trips/mine`, `/trips/search`, `/trips/{id}/*`
- Reservations: `/trips/{id}/reservations`, `/reservations/mine`,
  `/reservations/{id}/*`
- Live tracking: `/trips/{id}/positions`, `/trips/{id}/live`, `/trips/{id}/track`
- Ratings: `/trips/{id}/ratings/*`
- Support: `/support/categories`, `/support/tickets/*` (report targets, ticket evidence,
  statements, decisions/history, and contestations), `/support/notifications/*`
- Lost and found: `/lost-and-found/*`
- Administration: `/admin/*`

Every route is authenticated except the routes deliberately permitted in `SecurityConfig`.
`/api/admin/**` requires the admin role. Backend controllers derive the acting user from the
authenticated session rather than accepting an owner ID from the client.

The support module also has admin ticket/category endpoints. Its mobile client supports
category/ticket caching and draft recovery using a separate SQLite database. The current
ticket detail flow reads status history, evidence, statements, and decisions, and exposes
photo upload, statement submission, and decision contestation when the ticket state allows
them. Trip-linked tickets are visible to their opener, the reported user, and the eligible
driver/passenger participants; they all read the same evidence collection for that ticket.
When a trip has several passengers, the driver chooses the exact passenger/reservation being
reported. The reported party can add its own statement and evidence before admin review, and
both parties receive in-app Support notifications as the case progresses.

`lib/widgets/support_evidence_section.dart` provides the reusable evidence picker and the
validated photo-selection helper used by the report and ticket-detail screens. Android also
implements the `carshare.support/document_picker` method channel. The current live ticket
flow accepts photos of at most 5 MB, uploads them as authenticated multipart evidence, and
shows an authenticated thumbnail with a full-screen preview.

The admin Support list opens `AdminSupportTicketDetailsPage`. That case-review screen shows
the ticket context, opener, trip/reservation links, priority, attributed evidence, statements, status
history, decisions, and contestations, then exposes the valid status/decision actions. Its
backend aggregate and evidence-file routes are under `/api/admin/support/tickets/{ticketId}`.

Lost & Found remains a separate module and route. Support can reference an eligible trip
directly, so coupling Lost & Found into ticket processing is not required.

## Verification and tests

The repository currently contains 4 Flutter test files and 15 backend test files. Client
tests cover vehicle and support ticket models, tracking buffering, and the Support-page
refresh regression. Backend tests cover support models/evidence storage and reservation
behavior; reservation coverage includes matching, geo calculations, pickup codes, trip
windows/status, reservations, tracking, and ratings.

Use these checks from the repository root:

```powershell
flutter analyze
flutter test
flutter build apk --debug
Set-Location backend
.\gradlew.bat test
```

Local development:

```powershell
# Terminal 1, repository root
.\backend\run-local.ps1

# Terminal 2, Android emulator
flutter run

# Or a physical Android phone over USB
.\run-android-phone.ps1
```

## Important implementation notes

- `application.yml` defaults the backend to port 8080, but `backend/run-local.ps1` sets port
  8081 when `PORT` is unset. The Flutter client's default is `http://10.0.2.2:8081/api`.
  The root `README.md` has stale setup instructions that still describe port 8080 in places.
- `README.md` opens with an older feature-scope statement saying trips and geolocation are not
  included, but the repository now contains a complete reservation and live-tracking module.
- `HomePage` is an older standalone page; authenticated non-admin users currently enter
  `MainShell` and its `HomeSearchPage`.
- Support screens use `SupportService`; some admin screens still call `ApiClient` directly.
- `AdminOperationsPage` manages Support through `/admin/support/tickets` and delegates full
  case review and resolution actions to `AdminSupportTicketDetailsPage`.
- `lost_and_found_page.dart` is a large feature file with UI, local models, and data access in
  one place; changes there have a wider regression surface than its filename suggests.

## Deeper references

- `README.md`: setup, supported user journeys, and troubleshooting
- `CLAUDE.md`: repository conventions and required verification
- `docs/reservation-spec.md`: reservation rules and state transitions
- `docs/reservation-api.md`: reservation endpoint contracts and example sequence
- `docs/mockups/`: numbered reservation UI references
