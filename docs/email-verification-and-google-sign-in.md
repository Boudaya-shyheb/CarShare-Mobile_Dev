# Email verification and Google sign-in

## Email verification (Abstract API)

At sign-up, and when someone changes their email in their profile, the backend asks Abstract API
(Email Reputation, `https://emailreputation.abstractapi.com/v1/`, `GET ?api_key=…&email=…`) whether the
address can be written to. It runs only on the server; the key never reaches the app.

| Answer | Result |
| --- | --- |
| not well formed (`is_format_valid` false) | 400 `email_invalid` |
| disposable (`email_quality.is_disposable`) | 400 `email_disposable` |
| `email_deliverability.status` = `undeliverable` | 400 `email_undeliverable` |
| `unknown`, risky, anything else | accepted, logged (domain only) |

A refusal carries `suggestion` (the provider's `suggested_correction`, e.g. `test@gmail.com` for
`test@gmial.com`) when there is one. The app shows the message under the email field and a
"Did you mean …?" button that fills the suggestion in.

The check is a courtesy, never a gate. With no key, a provider that takes more than 3 s, a rejected key,
used-up quota (403/422), rate limiting (429), a server error or an answer that cannot be read, the check is
skipped and sign-up goes on, with one warning in the log per kind of problem. Definitive answers are
cached for 24 hours per address. The older Email Validation answer shape (`deliverability`,
`is_valid_format.value`, `autocorrect`) is read too, so `ABSTRACT_EMAIL_API_URL` may point at that API.
The provider is asked last, after every other sign-up check has passed, so a credit is only spent on an
otherwise acceptable sign-up. Google sign-in skips it: Google has already verified the address.

Setup: put `ABSTRACT_EMAIL_API_KEY=…` in `.env.local` (`run-local.ps1` loads it). Startup logs
`Email verification: enabled` or `disabled`. Free plans allow one request per second.
Tests use a mocked HTTP server only; no test calls the real API.

## Google sign-in

The Google button on Sign In appears only in a build made with
`--dart-define=GOOGLE_SERVER_CLIENT_ID=<web client id>`. Both phone scripts read that value from
`.env.local` and pass it (`run-android-phone.ps1`, `run-phone-me.ps1`); the backend reads the same name
from `.env.local` to check the ID token's audience.

In Google Cloud Console, the Android side needs an OAuth client of type **Android** with package
`com.example.carshare` and the **SHA-1 of the keystore that signs the build**. For debug builds:

```powershell
keytool -list -v -keystore "$env:USERPROFILE\.android\debug.keystore" -alias androiddebugkey -storepass android -keypass android
```

Without the right SHA-1 Google answers error 10 / `DEVELOPER_ERROR`; the app then shows "Google sign-in is
misconfigured…". That is a console setting, not a code problem. A Web OAuth client provides the
`GOOGLE_SERVER_CLIENT_ID`.
