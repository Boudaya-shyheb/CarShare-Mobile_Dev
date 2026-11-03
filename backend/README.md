# CarShare API

Spring Boot REST API for the existing CarShare account flow. It stores user profiles, hashed passwords, revocable sessions, and one-time password reset tokens in PostgreSQL (Neon is supported). The API does not connect to Firebase.

## Requirements

- JDK 17 or newer
- A Neon PostgreSQL database
- A network connection to download Gradle dependencies on the first build

The Gradle wrapper files are included in this folder. After linking the repository to Neon with `neon link`, Neon stores the pooled and direct PostgreSQL URLs in the ignored root `.env.local` file. Start the API from PowerShell with:

```powershell
.\run-local.ps1
```

The script converts Neon’s PostgreSQL URLs to JDBC format in memory, uses the pooled URL for API traffic and the direct URL for Flyway, and does not print credentials. Both `.env.local` and `.neon` are ignored by Git. Flyway creates the account, session, and reset-token tables on first API startup; Hibernate checks the schema without modifying it.

If you are not using the Neon CLI, set `DATABASE_URL`, `DATABASE_URL_UNPOOLED`, `DATABASE_USERNAME`, and `DATABASE_PASSWORD` in the process environment before starting `.\gradlew.bat bootRun`. Use JDBC URLs with `sslmode=require` and never commit credentials.

## Password recovery email

Configure these environment variables from your SMTP provider before using **Forgot password?**:

```powershell
$env:MAIL_HOST = 'YOUR_SMTP_HOST'
$env:MAIL_PORT = '587'
$env:MAIL_USERNAME = 'YOUR_SMTP_USERNAME'
$env:MAIL_PASSWORD = 'YOUR_SMTP_PASSWORD'
$env:MAIL_FROM = 'YOUR_VERIFIED_SENDER_ADDRESS'
$env:PUBLIC_API_URL = 'https://YOUR_PUBLIC_API_HOST'
```

Without a real SMTP configuration, sign up, sign in, profile lookup, and sign out work, but password recovery returns a clear setup error. `PUBLIC_API_URL` must be reachable by the recipient's device; for local-only development, `http://localhost:8081` works only on the machine running the API.

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
- `POST /api/auth/forgot-password` sends a one-time reset link
- `POST /api/auth/reset-password` changes the password and revokes all sessions
- `GET /api/users/me` returns the signed-in user's profile

Sessions are opaque random bearer tokens. Only SHA-256 hashes of session and reset tokens are stored in Neon; passwords use BCrypt. The Flutter app stores its bearer token in Android secure storage.
