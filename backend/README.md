# CarShare API

Spring Boot REST API for CarShare user management and admin operations. It stores profiles, account preferences, emergency contacts, sanctions, hashed passwords, revocable sessions, and single-use password reset codes in PostgreSQL (Neon).

## Requirements

- JDK 17 or newer
- A Neon PostgreSQL database
- A network connection to download Gradle dependencies on the first build

The Gradle wrapper files are included in this folder. After linking the repository to Neon with `neon link`, Neon stores the pooled and direct PostgreSQL URLs in the ignored root `.env.local` file. Start the API from PowerShell with:

```powershell
.\run-local.ps1
```

The script converts Neon’s PostgreSQL URLs to JDBC format in memory, uses the pooled URL for API traffic and the direct URL for Flyway, and does not print credentials. Both `.env.local` and `.neon` are ignored by Git. Flyway applies the versioned migrations; Hibernate checks the schema without modifying it. Test new migrations on the team’s Neon development branch before using them on a shared or production branch.

If you are not using the Neon CLI, set `DATABASE_URL`, `DATABASE_URL_UNPOOLED`, `DATABASE_USERNAME`, and `DATABASE_PASSWORD` in the process environment before starting `.\gradlew.bat bootRun`. Use JDBC URLs with `sslmode=require` and never commit credentials.

## Password recovery email

Configure these variables from your SMTP provider in the root `.env.local` before using **Forgot password?**:

```powershell
$env:MAIL_HOST = 'YOUR_SMTP_HOST'
$env:MAIL_PORT = '587'
$env:MAIL_USERNAME = 'YOUR_SMTP_USERNAME'
$env:MAIL_PASSWORD = 'YOUR_SMTP_PASSWORD'
$env:MAIL_FROM = 'YOUR_VERIFIED_SENDER_ADDRESS'
```

The reset email is multipart HTML/text and contains a six-digit code. The mobile app asks for the code, then the new password. Codes expire after 30 minutes and are invalidated after five incorrect attempts. SMTP settings are the `MAIL_*` values listed above.

For local testing on a physical Android phone, keep the phone connected by USB and start Flutter with `run-android-phone.ps1`; it forwards API port `8081` to the phone. The phone needs this connection while submitting the new password. On an emulator, use the normal emulator run configuration.

Without a real SMTP configuration, sign up, sign in, profile lookup, and sign out work, but password recovery returns a clear setup error. A public HTTPS deployment is needed only if reset links must work when the phone cannot reach the development API (for example, without USB forwarding).

## Flutter client

The Android emulator reaches the host machine's API at `http://10.0.2.2:8081/api`, which is the Flutter client's local default. The local backend script uses port `8081` to avoid conflicts with services that commonly occupy port `8080`. Start the backend with `.\run-local.ps1`, then run `..\run-android-phone.ps1` for a USB-connected phone; that script forwards port `8081` to the phone. For a hosted API, provide a reachable base URL:

```powershell
flutter run --dart-define=CARSHARE_API_BASE_URL=http://YOUR_COMPUTER_LAN_IP:8081/api
```

For a deployed API, use its HTTPS URL. The debug Android manifest allows cleartext HTTP only for local development; production should use HTTPS.

## API routes

- `POST /api/auth/signup` creates a user and session
- `POST /api/auth/signin` starts a session
- `POST /api/auth/signout` revokes the current session
- `POST /api/auth/forgot-password` sends a one-time six-digit reset code
- `POST /api/auth/reset-password` changes the password and revokes all sessions
- `GET /api/users/me` returns the signed-in user's profile
- `PUT /api/users/me` updates the signed-in user's profile
- `DELETE /api/users/me` deletes the account after password confirmation
- `GET/PUT /api/users/me/preferences` reads or saves user preferences
- `GET/POST/PUT/DELETE /api/users/me/emergency-contacts` manages emergency contacts
- `GET /api/users/me/sanctions` reads the signed-in user's sanction history
- `GET/POST/DELETE /api/users/me/photo` reads, uploads, or removes the signed-in user's photo
- `GET /api/admin/users` lists accounts for authenticated `ADMIN` users
- `PUT /api/admin/users/{userId}` updates a user's name, phone, email, and role
- `PUT /api/admin/users/{userId}/status` applies an admin status and reason
- `POST /api/auth/social/google` and `/api/auth/social/facebook` verify provider credentials and create CarShare sessions
- `GET /api/admin/vehicles` and `PUT /api/admin/vehicles/{vehicleId}/review` review vehicle details and photos
- `GET /api/admin/trips` and `/api/admin/reservations` read trip and reservation information without bypassing their state rules
- `GET /api/support/tickets` and `POST /api/support/tickets` manage the signed-in user's support requests
- `GET /api/admin/support-tickets` and `PUT /api/admin/support-tickets/{ticketId}` review and resolve support requests
- `GET /api/admin/lost-and-found` and `PUT /api/admin/lost-and-found/{reportId}/resolve` review lost-and-found reports
- `GET /api/admin/sanctions` and `POST /api/admin/users/{userId}/sanctions` manage reasoned user sanctions
- `GET/POST /api/vehicles` lists or creates the signed-in driver's vehicles
- `GET/PUT/DELETE /api/vehicles/{vehicleId}` reads, updates, or deletes an owned vehicle
- `POST /api/vehicles/{vehicleId}/default` selects the default vehicle
- `POST /api/vehicles/{vehicleId}/photos` uploads one vehicle photo
- `GET/DELETE /api/vehicles/{vehicleId}/photos/{photoId}` reads or removes an owned vehicle photo
- `POST /api/vehicles/{vehicleId}/photos/{photoId}/primary` selects the primary vehicle photo

Vehicle photos are stored as UUID-named files in `public/uploads/vehicles` by default; the database stores only filenames and MIME types. Set `VEHICLE_UPLOAD_DIRECTORY` to change the storage directory. Vehicle images must be valid JPEG, PNG, or WebP files no larger than 5 MB each, and a vehicle can have at most four photos.

Vehicles may include insurance and technical-inspection expiration dates. The mobile app shows an in-app warning within 30 days of expiration and an overdue state; no push notifications or document verification are performed. The first uploaded photo becomes primary by default, and deleting the primary photo promotes the oldest remaining photo.

Vehicle registration numbers support `123TU4567` and `RS123456`; spaces are accepted on input and removed for storage. The mobile make/model fields provide searchable suggestions for common vehicles, while still allowing drivers to enter a brand or model that is not suggested.

Trips, reservations, vehicle records and lost-and-found reports are stored by their feature services. Support tickets are stored separately and may reference a trip only when the requester participated in it. Admin trip and reservation endpoints are read-only so they cannot bypass those modules' transition rules.

Sessions are opaque random bearer tokens. Only SHA-256 hashes of session and reset tokens are stored in Neon; passwords use BCrypt. The Flutter app stores its bearer token in Android secure storage.

Five failed sign-in attempts lock that account for 15 minutes. Phone numbers are normalized and unique. Sanction points expire after 90 days; account status is recalculated nightly (3 points: warning; 6: 7-day suspension; 9: 30-day suspension; 12: ban). Suspended or banned users can still sign in to view their account history. The Support module should create sanctions; this module exposes the user's read-only sanction history.

The first admin account must be promoted manually in the database after the admin role migration has run. Admins can then manage user roles and account statuses in the app. The mobile sign-up flow never accepts the `ADMIN` role. Manual warnings and suspensions need an end date and reason; a ban has no automatic end date. When an admin restores an account to `ACTIVE`, the backend immediately recalculates its status from active sanctions. Expired manual warnings and suspensions return to the sanction-based status during the daily status job.

Google and Facebook login require provider configuration. Set `GOOGLE_SERVER_CLIENT_ID`, `FACEBOOK_APP_ID`, and `FACEBOOK_APP_SECRET` on the backend. The Google server client ID must also be passed to Flutter as `--dart-define=GOOGLE_SERVER_CLIENT_ID=...`; Android Facebook App ID and Client Token are passed by `run-android-phone.ps1` through environment variables. Do not place the Facebook App Secret in the mobile app. These flows cannot be tested until valid provider applications and credentials are configured.
