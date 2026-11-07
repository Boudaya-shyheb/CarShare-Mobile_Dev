# CLAUDE.md — CarShare

Flutter (Android) client + Spring Boot REST API + PostgreSQL on Neon (Flyway migrations).
Firebase is not used by the current code.

```text
lib/ (Flutter)  →  /api (Spring Boot, port 8081 local)  →  PostgreSQL (Neon)
```

Modules are owned per student. The existing code covers **user management** (auth, profile,
photo, preferences, emergency contacts, status/sanctions, admin list). Follow its conventions
exactly when adding a new module — do not refactor another module's files.

> **Reservation module:** the agreed functional rules (state machine, match score,
> reservation and tracking rules, screen list) live in [docs/reservation-spec.md](docs/reservation-spec.md).
> Read it before changing anything under `com.carshare.api.reservation` or the reservation screens.


---

## 1. Secrets — non-negotiable

- **Never print, echo, cat, log or commit** `.env.local`, `.neon`, or any credential
  (`DATABASE_URL`, `DATABASE_PASSWORD`, `MAIL_PASSWORD`, tokens).
- Never paste secret values into code, migrations, README, commit messages or tickets.
- Config is read from the environment only: `application.yml` reads `${DATABASE_URL}` etc. and
  imports `optional:file:../.env.local[.properties]`. New config follows the same pattern.
- `backend/run-local.ps1` converts Neon URLs to JDBC in memory and must stay silent about values.

> ⚠️ `.env.local` and `.neon` are currently **tracked** in git history and pushed to `origin`
> despite the `.gitignore` rule (`.gitignore` does not apply to already-tracked files).
> Treat those credentials as compromised: rotate the Neon password / SMTP password, then
> `git rm --cached .env.local .neon`. Do not add them back.

---

## 2. Repository layout

```text
lib/
  main.dart                 app bootstrap only
  app.dart                  MaterialApp, theme, routes, auth gate
  navigation.dart           carShareNavigatorKey
  theme.dart                carShareTheme + colour constants
  models/<entity>.dart      one model class per entity
  services/<module>_service.dart
  services/api_client.dart  shared HTTP client (do not duplicate)
  services/local_database.dart  sqflite cache
  pages/<name>_page.dart    one screen per file
  widgets/<name>.dart       shared widgets (CarShareTextField, PrimaryButton)

backend/src/main/java/com/carshare/api/
  common/                   ApiException, ApiExceptionHandler
  security/                 SecurityConfig, SessionPrincipal, TokenAuthenticationFilter, TokenUtil
  auth/                     AuthController, AuthService, AuthDtos, session + reset entities
  users/                    entities, repositories, UserAccountService, controllers
  <module>/                 NEW module → its own package here
backend/src/main/resources/db/migration/V<n>__<snake_case>.sql
```

A new module gets **one Java package** `com.carshare.api.<module>` holding its entities,
repositories, DTO holder, service and controller. Do not scatter module classes into `users/`
or `auth/`.

---

## 3. Backend conventions

### Package & class naming
- Entity: `Trip`, `Booking` — plain JPA class, no Lombok (not a dependency).
- Repository: `TripRepository extends JpaRepository<Trip, UUID>`.
- Service: `@Service` + constructor injection (no field `@Autowired`).
- Controller: `@RestController` + `@RequestMapping("/api/...")`, constructor injection.
- DTOs: a single `final` holder class with a private constructor and nested `record`s,
  e.g. `TripDtos` mirroring `AuthDtos`. Static `from(entity)` factories live on the record.

### Entities
```java
@Entity
@Table(name = "trips")
public class Trip {
    @Id @GeneratedValue @UuidGenerator private UUID id;          // or UUID.randomUUID() in ctor
    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "driver_id", nullable = false) private AppUser driver;
    @Column(name = "seats_total", nullable = false) private int seatsTotal;
    @Enumerated(EnumType.STRING) @Column(nullable = false, length = 16) private TripStatus status;
    @Column(name = "created_at", nullable = false) private Instant createdAt;

    protected Trip() { }                                          // JPA
    public Trip(AppUser driver, ...) { ... }                      // real constructor
    @PrePersist void setCreatedAt() { if (createdAt == null) createdAt = Instant.now(); }
    // getters only; mutation through intent-named methods
    public void cancel() { ... }
}
```
Rules: `UUID` primary keys; `Instant` for all timestamps (UTC, `TIMESTAMPTZ` in SQL);
explicit `@Column(name = ..., nullable = ..., length = ...)` matching the migration;
`fetch = FetchType.LAZY` on every association; no public setters — expose intent methods
(`updateProfile`, `recordFailedSignIn`, `cancel`); enums stored as `EnumType.STRING`.

### Repositories
Spring Data derived queries with the underscore path style used in this repo:
`findByUser_IdOrderByIssuedAtDesc(UUID userId)`, `findByIdAndUser_Id(UUID id, UUID userId)`.
Use `@Query` (JPQL) with `@Param` for aggregates; `nativeQuery = true` only when Postgres
features are needed (as in `existsByNormalizedPhone`). `@EntityGraph` to avoid lazy-loading
traps in filters.

### The signed-in user
`TokenAuthenticationFilter` resolves the `Authorization: Bearer <token>` header, looks up a
non-expired `auth_sessions` row by SHA-256 hash, and puts a
`SessionPrincipal(UUID userId, String tokenHash)` in the security context with authority
`ROLE_<USERROLE>`. Controllers therefore never take a user id from the request body or path:

```java
@GetMapping("/trips/mine")
public List<TripDtos.Trip> myTrips(@AuthenticationPrincipal SessionPrincipal principal) {
    return tripService.listForDriver(principal.userId());
}
```

Services take `UUID userId` as their first parameter and re-check ownership themselves —
`findByIdAndUser_Id(...)` or an explicit check — then throw `ApiException` 404/403. Never trust
a client-sent owner id. Every route except the explicitly permitted ones in `SecurityConfig` is
authenticated (`anyRequest().authenticated()`); `/api/admin/**` needs `ROLE_ADMIN`. New public
routes must be added to `SecurityConfig` deliberately — the reservation module has none.

### Validation & DTO style
Request records carry Jakarta validation annotations; controllers use `@Valid @RequestBody`.
Reuse the existing patterns: `@NotBlank`, `@Size(max = …)`, `@Email`, `@Pattern`,
and for this module `@Positive`, `@Min`, `@Future`, `@DecimalMin/@DecimalMax`.
Response records are flat, with `UUID` ids and `Instant` timestamps; Jackson serializes
`Instant` as ISO-8601, which `DateTime.parse` reads on the Flutter side.
Business rules that validation cannot express (seat count vs. bookings, overlapping trips,
date in the past, status transitions) belong in the service and throw `ApiException`.

### Errors
Never return an ad-hoc error body or let a raw exception escape. Throw:

```java
throw new ApiException(HttpStatus.NOT_FOUND, "trip_not_found", "This trip is no longer available.");
```

`ApiExceptionHandler` (`@RestControllerAdvice`) turns it into RFC-7807 `ProblemDetail` with a
`code` property; it also maps `MethodArgumentNotValidException` → 400 `validation_error`,
`DataIntegrityViolationException` → 409, `DataAccessException`/`MailException` → 503.
`code` is `snake_case`; `message` is a short, user-facing English sentence (it is shown in a
SnackBar) and must never leak SQL, stack traces or internal ids.

### Transactions
`@Transactional(readOnly = true)` on reads, `@Transactional` on writes, at the **service**
level (never on controllers). Entities loaded inside a write transaction are dirty-checked —
no explicit `save()` needed for updates (see `updateEmergencyContact`). `open-in-view` is
false, so map to DTOs inside the transaction. Use `@Transactional(noRollbackFor = ApiException.class)`
only when a failure must still persist a counter, as in `signIn`.

### Seat/booking concurrency
Booking seats is a read-then-write race. Guard it in the database, not only in Java: a
`CHECK`/unique constraint plus either a `SELECT … FOR UPDATE` (`@Lock(PESSIMISTIC_WRITE)`)
on the trip row or an atomic `UPDATE trips SET seats_available = seats_available - :n
WHERE id = :id AND seats_available >= :n` and a 409 when 0 rows change.

---

## 4. Flyway migrations

- **Never edit an applied migration.** Always add a new file `V<n>__<snake_case>.sql`,
  `<n>` = next free integer (current highest: `V6`).
- Hibernate stays on `ddl-auto: validate` — the migration is the schema source of truth and
  the entity must match it exactly (names, nullability, lengths). Never change `ddl-auto`.
- Never fix the database by hand to work around a migration.
- Test a new migration on your own Neon development branch first, never on a shared or
  production branch.
- SQL style used here: uppercase keywords, `UUID PRIMARY KEY`, `TIMESTAMPTZ NOT NULL DEFAULT
  CURRENT_TIMESTAMP`, `REFERENCES app_users(id) ON DELETE CASCADE`, `CHECK (... IN (...))` for
  enum columns, named indexes `ix_<table>_<cols>`, named constraints `uq_…` / `ck_…`.
- Add an index for every column combination the module queries by
  (`ix_trips_departure_time`, `ix_bookings_trip_id`, …).

---

## 5. Flutter conventions

### Course rules (mandatory)
- **`StatelessWidget` by default.** Use `StatefulWidget` + `setState` only when the screen owns
  mutable state (form controllers, loading flags, a future that must be re-created).
- **`ListView.builder`** (or `.separated`) for any list that can grow. A fixed handful of rows
  may use `ListView(children: …)`.
- **Every form** = `Form` + `GlobalKey<FormState>` + `TextFormField` with `validator`s, submitted
  through `if (!_formKey.currentState!.validate()) return;`. Use the shared
  `CarShareTextField` wrapper rather than a raw `TextFormField`.
- **`InkWell`** for custom tappable surfaces (with `borderRadius`), not `GestureDetector`.
- **One model class per entity** in `lib/models/`, with `factory X.fromJson(Map<String, dynamic>)`
  and `Map<String, dynamic> toJson()`.
- **One service class per module** in `lib/services/`, singleton:
  `ModuleService._(); static final instance = ModuleService._();`
- **`FutureBuilder`** for loading / error / data — check
  `snapshot.connectionState == ConnectionState.waiting`, then `snapshot.hasError`, then data.

### Models
```dart
class Trip {
  const Trip({required this.id, required this.departureTime, this.notes});
  final String id;                 // UUID as String
  final DateTime departureTime;
  final String? notes;

  factory Trip.fromJson(Map<String, dynamic> json) => Trip(
    id: json['id'] as String,
    departureTime: DateTime.parse(json['departureTime'] as String),
    notes: json['notes'] as String?,
  );

  Map<String, dynamic> toJson() => { 'departureTime': departureTime.toIso8601String(), 'notes': notes };
}
```
`const` constructor, `final` fields, explicit casts, `?? default` for optional server fields,
`DateTime.parse` / `toIso8601String()` for `Instant`. If the model is cached in sqflite, add
`fromMap`/`toMap` with `snake_case` keys (see `UserProfile`).

### Services
Never call `http` directly from a page or a service — go through `ApiClient.instance`:

```dart
class TripService {
  TripService._();
  static final instance = TripService._();
  final ApiClient _api = ApiClient.instance;

  Future<List<Trip>> search(TripSearch query) async =>
      (await _api.getList('/trips?from=${...}')).map(Trip.fromJson).toList(growable: false);

  Future<Trip> publish(Trip draft) async =>
      Trip.fromJson(await _api.post('/trips', draft.toJson()));
}
```

`ApiClient` (`lib/services/api_client.dart`) already handles: base URL
(`--dart-define=CARSHARE_API_BASE_URL`, default `http://10.0.2.2:8081/api`), the bearer token
from `flutter_secure_storage`, JSON encode/decode, 15 s timeouts, and converting every failure
into `ApiException(message, statusCode, code)` with a friendly message. Paths passed to it are
relative and start with `/` (`'/trips'`). Use `get` / `getList` / `post` / `put` / `delete`;
add a new method to `ApiClient` only for a genuinely new transport need (e.g. multipart),
following `uploadPhoto`.

### Pages
One screen per file in `lib/pages/`, `<Name>Page`, `static const routeName = '/kebab-case'`
when the page is registered in `app.dart` routes; otherwise push a `MaterialPageRoute`.
Private sub-widgets (`_TripCard`, `_SeatPicker`) live at the bottom of the same file with a
leading underscore. Layout idiom used throughout: `Scaffold` → `AppBar` → `SafeArea` →
`Center` → `ConstrainedBox(maxWidth: 500–520)` → `SingleChildScrollView(padding: EdgeInsets…)`
→ `Column(crossAxisAlignment: CrossAxisAlignment.start)`, with `const SizedBox(height: 12–22)`
as spacing. Expression-bodied `build` (`Widget build(BuildContext context) => Scaffold(...)`)
matching the existing files.

Async handlers:
```dart
Future<void> _submit() async {
  if (!_formKey.currentState!.validate()) return;
  setState(() => _loading = true);
  try {
    await TripService.instance.publish(...);
    if (mounted) Navigator.of(context).pop(true);
  } catch (error) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(authErrorMessage(error))));
    }
  } finally {
    if (mounted) setState(() => _loading = false);
  }
}
```
Always guard `context` use after an `await` with `mounted` / `context.mounted`. Dispose every
`TextEditingController` in `dispose()`. Show errors as a `SnackBar` with
`authErrorMessage(error)` (it unwraps `ApiException`). Submit buttons use `PrimaryButton` with
`loading: _loading`.

### Theme & colours
Import `../theme.dart` and use the constants; do not hardcode the hex of the brand colour.

| Role | Constant | Hex |
| --- | --- | --- |
| Main / brand | `carShareGreen` | `#059669` |
| Success | | `#10B981` |
| Warning | | `#F59E0B` |
| Danger | | `#EF4444` |
| Brand tint (chips, badges) | | `#D1FAE5` |
| Border | | `#DCE4E9` |
| Secondary text | | `#718096` |

Add new status colours as named `const Color` in `lib/theme.dart` (e.g. `carShareSuccess`,
`carShareWarning`, `carShareDanger`) rather than repeating literals. Field decoration comes
from `carShareTheme.inputDecorationTheme` (14 px radius) — don't re-style inputs per page.
Material 3 is on; text styles come from `Theme.of(context).textTheme.…copyWith(fontWeight: …)`.

### State
No state-management package. Shared state uses `ValueNotifier` + `ValueListenableBuilder`
(see `AuthService.currentUser` / `isRestoringSession` and `_AuthenticationGate`). The signed-in
user is read from `AuthService.instance.currentUser.value` — never fetch `/users/me` again just
to know who is signed in.

### Dependencies
`pubspec.yaml` currently has: `app_links`, `flutter_secure_storage`, `http`, `path`, `sqflite`,
`image_picker`, `http_parser`. Maps and live tracking will need new packages — add them with a
caret version, run `flutter pub get`, and mention the Android manifest/permission changes
(location) in the same change.

---

## 6. Checks before saying a change is done

```powershell
flutter analyze
flutter build apk --debug
```

```powershell
Set-Location .\backend ; .\gradlew.bat build
```

Run the API with `.\backend\run-local.ps1` (port 8081, loads `.env.local`), then
`flutter run` (emulator) or `.\run-android-phone.ps1` (USB phone, forwards 8081).
Note: the root `README.md` still says port 8080 in places; the real local port is **8081**,
as in `backend/README.md` and `ApiClient.baseUrl`.

## 7. Git

- Never commit `.env.local`, `.neon`, build output, or `.dart_tool/`.
- Commit messages: `feat: …`, `fix: …`, short and in English (matching `feat: complete user
  management module`).
- Work on a feature branch; do not commit or push unless asked.
