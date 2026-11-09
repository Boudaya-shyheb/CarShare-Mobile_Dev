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
> Every endpoint of that module — request and response JSON, who may call it, error codes, and the
> order of calls for a full trip — is in [docs/reservation-api.md](docs/reservation-api.md), with a
> Postman collection beside it at `docs/CarShare-Reservation.postman_collection.json`.


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

## 7. How to verify Flutter work

Do not ask the user to test a screen. Build it, put it on the phone, look at it, drive it, and
compare it with the mockup before reporting. Every command below is run from the repository root.

### 7.1 Backend

```powershell
$env:GRADLE_USER_HOME = 'D:\carshare-build\gradle-home'
$env:JAVA_TOOL_OPTIONS = ''
.\backend\run-local.ps1
```

Run it in the background and wait for `Started CarShareApiApplication` in its output before
touching the app. **Stop it at the end of the session.** `GRADLE_USER_HOME` must point at D:
because C: has little room left; never free space by deleting things.

### 7.2 Phone

Samsung SM A165F over USB (`RF8YA066Y4M`).

```bash
adb devices
adb reverse tcp:8081 tcp:8081
```

- `adb reverse` has to be re-run **after every reconnect** (unplug, reboot, adb restart), or the
  app reaches nothing on 8081 and every call fails with a connection error.
- **Clear `JAVA_TOOL_OPTIONS` before building.** The repo lives at
  `C:\Users\YASSINE JOMNI\Documents\stage-ete\pi mobile\CarShare-Mobile_Dev`; the space in
  `YASSINE JOMNI` breaks an unquoted `-Djava.io.tmpdir=<path>` (which is what
  `run-android-phone.ps1` sets), so use `.\run-phone-me.ps1` or the manual sequence instead.
- `PUB_CACHE` is `D:\flutter-pub-cache` while the repo is on C:. Kotlin's incremental compiler cannot
  relate paths across drives (`Could not close incremental caches`), so
  `D:\carshare-build\gradle-home\gradle.properties` (outside the repo) holds
  `kotlin.incremental=false`. A fresh machine needs the same line in its own `GRADLE_USER_HOME`.
- `flutter test` runs from the repo root; the old `D:\carshare-test` copy and the `subst` trick are
  no longer needed now that the path has no apostrophe.

### 7.3 Build, install, launch

```bash
flutter build apk --debug --dart-define=CARSHARE_API_BASE_URL=http://127.0.0.1:8081/api
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb shell am start -n com.example.carshare/.MainActivity
```

`127.0.0.1:8081` works on the phone only because of the `adb reverse` above; the default
`10.0.2.2` is the emulator's host alias and is wrong for a real device.

### 7.4 See the screen

```bash
adb exec-out screencap -p > .dart_tool/shots/<name>.png
```

Then **open the PNG and look at it** — a command that exits 0 is not evidence a screen is right.
`.dart_tool/` is already git-ignored, so screenshots stay out of the repository. Give each shot a
name that says what it shows (`07-home-passenger.png`), and let a screen settle (animation, map
tiles, a network call) before capturing it.

### 7.5 Interact

```bash
adb shell uiautomator dump /sdcard/ui.xml && adb shell cat /sdcard/ui.xml   # find bounds
adb shell input tap <x> <y>
adb shell input text "Sousse"
adb shell input swipe <x1> <y1> <x2> <y2> <ms>
adb shell input keyevent 4        # back
```

Read the real bounds out of the dump rather than guessing coordinates from a screenshot, and
wait for the screen to settle between a tap and the next dump or capture.

### 7.6 Test accounts

Two accounts on the Neon dev branch, one `DRIVER` and one `PASSENGER`, created with
`POST /api/auth/signup`. Their emails and passwords live in `.dart_tool/test-accounts.json`
(git-ignored, and never echoed into the transcript or a commit).

The phone holds one side of a trip; play the other side with `curl` and that account's bearer
token — the driver publishes and accepts while the phone is the passenger, for instance. To
switch the phone to the other account, `adb shell pm clear com.example.carshare` (the app has no
sign-out control outside the admin screen).

### 7.7 Compare with the mockup

Every screen has a file in `docs/mockups/` whose name starts with the screen number
(`04 · Home – Search`, `05 · Matching Results`, …). Open the mockup next to the screenshot and
fix the visible differences before reporting. A difference kept on purpose gets said out loud,
with the reason.

### 7.8 Never

- Never read, print or modify `.env.local` or `.neon`.
- Never run `dart format` on `lib/` as a whole — only on the files of the module being worked on.
- Never commit or push; the user commits.

## 8. Git

- Never commit `.env.local`, `.neon`, build output, or `.dart_tool/`.
- Commit messages: `feat: …`, `fix: …`, short and in English (matching `feat: complete user
  management module`).
- Work on a feature branch; do not commit or push unless asked.
