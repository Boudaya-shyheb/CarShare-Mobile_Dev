# SQLite in the Reservation module

The phone keeps one SQLite file, `carshare.db`. The Reservation module adds three tables to it
in **version 5** and uses them for three visible features: recent searches, favourite places and
an offline copy of My trips. Packages: `sqflite` and `path` only (tests add `sqflite_common_ffi`).

| File | Role |
| --- | --- |
| `lib/services/local_database.dart` | Opens the database (`openDatabase`, `onCreate`, `onUpgrade`) and creates the tables |
| `lib/services/reservation_local_store.dart` | The CRUD methods (`insert`, `query`, `update`, `delete`), always filtered by `user_id` |
| `lib/models/recent_search.dart`, `favorite_place.dart`, `cached_trips.dart` | One small class per table, with `toMap()` / `fromMap()` |

## The tables

Every row carries the `user_id` of the signed-in user, so two accounts on one phone never see each other's data.

| Table | Columns | Rule |
| --- | --- | --- |
| `recent_searches` | `id`, `user_id`, `origin_label`, `origin_lat`, `origin_lng`, `dest_label`, `dest_lat`, `dest_lng`, `searched_at` | Max 10 per user (oldest deleted). Same origin + destination again only updates `searched_at` |
| `favorite_places` | `id`, `user_id`, `name`, `label`, `lat`, `lng`, `created_at` | `name` is "Home", "Work"...; `label` is the address |
| `cached_trips` | `user_id`, `kind`, `scope`, `json`, `cached_at` | `kind` is `driver` or `passenger`. One row per user + kind + scope, replaced on every load |

`cached_trips` has one column more than the first plan, `scope` (`upcoming`, `past`, `cancelled`): My trips has three tabs and each tab is a different list, so each needs its own row.

## Which screen uses what

| Screen | What it does with SQLite |
| --- | --- |
| Home (`home_search_page.dart`) | Saves each search; shows the last 5 under the search card (tap = search again, bin = delete, "Clear" = delete all); shows favourites as chips (tap = use as pick-up or destination, long-press = rename or delete) |
| Place search (`place_search_page.dart`) | The star on a result asks for a name in a dialog (a `Form` with a validator) and saves the place |
| My places (`my_places_page.dart`, "Manage" on Home) | Lists all favourites with rename and delete |
| My trips (`my_trips_page.dart`) | After each successful load, saves the API's JSON. If the server cannot be reached, shows the saved copy with the banner "Offline: showing data from ..." |

## Upgrade from version 4 to 5

```text
onCreate  (fresh install)   -> all tables, including the three new ones
onUpgrade (oldVersion < 5)  -> createReservationTables(db)   only the three new tables
```

`createReservationTables` uses `CREATE TABLE IF NOT EXISTS`, so running it twice is harmless. `user_profiles`, `pending_gps_points` and `lost_and_found_drafts` are not touched, and existing rows stay (a test checks this).

## 2-minute demo

1. **Recent searches.** Sign in as a passenger. On Home choose Sousse to Monastir and press Search, then go back: the route appears under "Recent searches". Search it again: still one row. Search two other routes, then tap a recent one: the form fills and the search runs. Delete one with the bin, then press "Clear".
2. **Favourites.** On Home tap FROM, type "Sousse" and tap the star on a result. Press Save with the name empty (error), then type "Home" and save. Back on Home, the chip "Home" is there. Tap it and choose "Use as destination". Long-press it to rename or delete. Press "Manage" to open My places and rename or delete from the list.
3. **Offline My trips.** Open the Trips tab and visit Upcoming, Past and Cancelled while online. Turn on **airplane mode** and pull down to refresh: the list stays and the banner "Offline: showing data from ..." appears. Turn airplane mode off and refresh: the banner disappears.

## Tests

`flutter test test/reservation_local_store_test.dart` runs 14 tests on a desktop SQLite (`sqflite_common_ffi`): recent searches (order, duplicates, the max-10 rule, delete, clear, per-user), favourites (add, rename, delete), the trips cache (save, load, replace) and the version 4 to 5 upgrade.
