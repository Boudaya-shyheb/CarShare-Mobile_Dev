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

## Notifications (migration V26)

Every step of a match tells the other person, in the app (no email). Rows live in
`lost_and_found_notifications` (user, type, report, handover, title, body, `read_at`, `created_at`).

| Type | When | Who is told |
| --- | --- | --- |
| `MATCH_FOUND` | A new report meets an open report of the opposite type on the same trip, from another person, in the same category (and the same colour when both gave one; "Other" never matches) | both reporters |
| `MATCH_CONFIRMED` | someone presses "Confirm match" (the handover is created) | the other reporter |
| `MEETING_ARRANGED` | the meeting point and time are saved | the other reporter, with the place and time |
| `ITEM_RETURNED` | the finder enters the right code | both |
| `NOT_MY_ITEM` | someone calls the match off | the other reporter |

Endpoints (all under `/api/lost-and-found/notifications`, caller only): `GET` the list (newest first),
`GET /unread-count`, `POST /{id}/read`, `POST /read-all`. Reading them is not blocked for a suspended
account; creating reports and handovers still is.

In the app the Home bell opens one **Notifications** page with a chip per source, *Support* (the
existing page, unchanged) and *Lost & Found*. The bell's badge is the sum of both unread counts. Tapping a
Lost & Found notification marks it read and opens that report, on its match or handover screen. "Mark all
as read" clears both sources. The page refreshes when it opens, on pull-to-refresh, when the app returns
to the foreground and every 15 seconds while it is open.

## Photos and on-device labelling

**Labelling.** In the report form, "Add photo" offers the camera or the gallery. The picture is labelled on
the phone with ML Kit image labelling (the model ships inside the app: no network, nothing leaves the
phone). The best matching label is shown as a chip, "Looks like: Phone (87%)"; tapping it selects that
category. The person can always pick another one, or ignore the chip. Only labels at 50% or more count.
The mapping is one small file, `lib/services/photo_category_mapper.dart`:

| Category | ML Kit labels that select it |
| --- | --- |
| Phone | mobile phone, phone, smartphone, cell phone, telephone, communication device |
| Bag | bag, backpack, handbag, luggage, suitcase, briefcase, tote, satchel, purse, duffel |
| Wallet | wallet, coin purse, billfold |
| Keys | key, keys, keychain, key ring |
| Glasses | glasses, sunglasses, eyewear, spectacles, goggles |
| Clothing | clothing, shirt, jacket, coat, dress, sweater, hoodie, scarf, hat, cap, glove, jeans, shoe, outerwear |
| Documents | document, paper, passport, book, card, notebook, envelope, receipt |

A label counts when it is one of those words or contains one as a whole word (so "Keyboard" is not Keys).
Labels that name no item ("Gadget", "Room") are ignored, and "Other" is never suggested: no chip is better
than a wrong one.

**Upload and storage.** The photo goes with the report as `multipart/form-data`
(`POST /api/lost-and-found/trips/{tripId}/reports`, parts `type`, `title`, `description`, `photo`).
JPG, PNG or WebP by content (not by name), 2 MB at most; the file is stored under a random name in
`backend/public/uploads/lost-and-found/` (git-ignored, `LOST_AND_FOUND_UPLOAD_DIRECTORY` to move it) and
the report keeps only its name and type (`photo_file_name`, `photo_content_type`). Reports expose
`hasPhoto`. `GET /api/lost-and-found/reports/{id}/photo` returns it to the report's own reporter, to the
reporter of a matching report (so the owner can recognise the item), to the participants of a handover on
it, and to admins. Anyone else gets 404, never a hint that a photo exists. It shows on the report card and
on both sides of the match page.
