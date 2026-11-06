# CarShare API

Spring Boot REST API for CarShare user management. It stores profiles, account preferences, emergency contacts, sanctions, hashed passwords, revocable sessions, and single-use password reset codes in PostgreSQL (Neon). Firebase is not used.

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

Sessions are opaque random bearer tokens. Only SHA-256 hashes of session and reset tokens are stored in Neon; passwords use BCrypt. The Flutter app stores its bearer token in Android secure storage.

Five failed sign-in attempts lock that account for 15 minutes. Phone numbers are normalized and unique. Sanction points expire after 90 days; account status is recalculated nightly (3 points: warning; 6: 7-day suspension; 9: 30-day suspension; 12: ban). Suspended or banned users can still sign in to view their account history. The Support module should create sanctions; this module exposes the user's read-only sanction history.

Admin accounts must be promoted manually by the database administrator after the admin role migration has run. The mobile sign-up flow never accepts the `ADMIN` role.
