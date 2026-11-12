# Lost & Found: the handover

How a lost item goes from "reported" to "returned", and why the last part lives on the server.

## The flow

1. **Report.** The owner reports a LOST item and the finder a FOUND item on the same trip
   (`POST /api/lost-and-found/trips/{id}/reports`). Only the trip's driver and its confirmed
   passengers may report. The category is the report's title and the colour is a line in its
   description.
2. **Match (on the phone).** Each phone loads the reports of its trips and matches them: same
   trip, opposite type, a different person, same category, and the same colour when both gave one.
   The server does not match; it keeps the reports and the handover.
3. **Confirm the match.** Either person presses "Confirm match": `POST /handovers` creates the
   handover (status `PROPOSED`). If the other person already did, they get the same one back.
4. **Arrange.** Either side sets a meeting point and time (`PUT /handovers/{id}/arrange`). The
   first call creates a 4-digit code on the server (`SecureRandom`) and moves the handover to
   `ARRANGED`. Both people now see the same meeting point and time.
5. **Return.** The owner reads the code from their screen and gives it to the finder in person.
   The finder types it (`POST /handovers/{id}/verify`). A right code sets the handover to
   `COMPLETED` and resolves **both** reports in one transaction, so both phones show "Returned".
6. **Not my item.** Either side can call the match off (`POST /handovers/{id}/reject`): status
   `CANCELLED`, both reports stay open, and neither phone offers that pair again.

## The table: `lost_and_found_handovers` (migration V19)

| Column | Meaning |
| --- | --- |
| `id`, `trip_id` | the handover and its trip |
| `lost_report_id`, `found_report_id` | the matched pair (never the same report) |
| `status` | `PROPOSED`, `ARRANGED`, `COMPLETED` or `CANCELLED` |
| `meeting_point`, `meeting_time` | free text both sides read (120 and 80 characters) |
| `code` | 4 digits, set on the first arrange |
| `failed_attempts` | wrong codes typed so far; the handover locks at 5 |
| `created_by`, `created_at`, `updated_at` | who started it and when |

Two partial unique indexes allow only one live (`PROPOSED` or `ARRANGED`) handover per report,
whichever side of the pair the report is on. Finished and cancelled rows stay as history.

## Endpoints

All under `/api/lost-and-found`, all need a signed-in user, and all refuse (403) anyone who is not
one of the two reporters.

| Call | Who | Result |
| --- | --- | --- |
| `POST /handovers` `{lostReportId, foundReportId}` | either reporter | 201, the handover. 400 if the pair is not one lost and one found report on the same trip from two people; 409 if a report is closed or already in another handover. Asking again for a live pair returns it. |
| `PUT /handovers/{id}/arrange` `{meetingPoint, meetingTime}` | either | the handover, now `ARRANGED` |
| `GET /handovers/mine` | any user | the user's handovers, each seen from their side |
| `POST /handovers/{id}/verify` `{code}` | **the finder only** | `COMPLETED` and both reports `RESOLVED`; 400 `wrong_code` (tries left); 423 `handover_locked` after 5 |
| `POST /handovers/{id}/reject` | either | `CANCELLED` |

Every view carries the status, meeting point and time, the other person's name, and the finder's
`attemptsLeft`. The `code` field is filled **only for the owner of the lost item**.

## Why the code is on the server

When the code was made and kept on the owner's phone, the finder's phone could not check it, so
the "handover" was two unconnected screens: each person saw only their own meeting point, and
closing one report did nothing to the other.

With the code on the server, the owner is the only one who is ever sent it, so the finder cannot
read it from the API or the screen and has to get it from the owner in person. The server checks
it, counts wrong tries (and keeps counting after the error is returned), locks after five, and
closes both reports together. The two people see one status, one meeting point, and one end.
