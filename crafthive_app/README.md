# CraftHive (Flutter app)

CraftHive is an Android marketplace for handmade and custom-made products. One account can both buy and sell.

This is the **Milestone 2 build**: the user interface. Every screen from the Milestone 1 design is implemented and can be navigated. The screens run on sample data (`lib/data/mock_data.dart`). Supabase (PostgreSQL) and Firebase are connected in Milestone 3.

## Run it

Requirements: Flutter 3.27 or newer (stable channel), Android Studio with an emulator or an Android phone with USB debugging on.

**1. One-time setup** (creates the `android/` and `web/` folders, adds the Internet permission, installs packages):

```bash
./setup.sh                                              # macOS / Linux
powershell -ExecutionPolicy Bypass -File .\setup.ps1     # Windows
```

**2. Run, test, build:**

```bash
flutter run                  # on a connected phone or emulator
flutter test                 # widget test: log in, then switch tabs
flutter build apk --release  # APK at build/app/outputs/flutter-apk/app-release.apk
flutter run -d chrome        # optional: run in the browser
```

**Demo login:** any username (for example `ana.makes`) with any password of 8 or more characters (for example `craftlover8`). Signing up also works and logs you in.

## Orders and custom orders (Milestone 3)

Orders and custom requests are saved in PostgreSQL through the functions in
`database/04_orders_and_custom_orders.sql`. **Run that file once in Supabase → SQL Editor**
(after 01 and 02). It adds:

- **Buy now** → `place_order`: reserves stock for 24 hours (made-to-order when out of stock);
  unpaid reservations are released by `release_expired_reservations`.
- **Payment proof** → `submit_payment`: receipt photo in the `private-files` bucket; reused reference
  numbers and receipt images (SHA-256) are rejected. The seller confirms or rejects it with `review_payment`.
- **Progress** → `set_order_status`: seller marks in production / shipped, buyer confirms receipt,
  either can cancel while unpaid. A trigger only allows valid status steps; every change is logged in
  `order_status_history`.
- **Custom request** → `submit_custom_request`; the seller answers with `send_quote` (new versions
  replace old ones) or `decline_custom_request`; the buyer uses `respond_to_quote` to accept (creates the
  order and books a weekly capacity slot) or ask for changes, or `cancel_custom_request`.
- `my_orders` and `my_custom_requests` return everything the screens show in one call each.

## Screens

| # | Screen | Route |
|---|--------|-------|
| 1 | Log in | `/login` |
| 2 | Sign up | `/signup` |
| – | Forgot password | `/forgot-password` |
| 3 | Home (Featured, Categories, Recent searches, More to explore) | `/home` |
| – | Search / category results + filter and sort sheets | `/search?q=&category=` |
| 4 | My store (profile, Sign out, listings, filter) | `/store` |
| – | Edit profile | `/store/edit` |
| – | Another maker's store (Message, Follow) | `/seller/:id` |
| 5 | Product details (gallery, Custom order, Buy now) | `/product/:id` |
| 6 | Custom order request | `/product/:id/custom` |
| 7 | Request sent (waiting for the seller) | `/request-sent/:code` |
| 8 | Chat (quote card: Confirm order / Ask for changes; seller: Send a quote) | `/chat/:id` |
| 9–10 | Messages with Buying and Selling tabs | `/messages` |
| 11 | New listing (Sell) and Edit listing | `/sell`, `/listing/:id/edit` |
| – | Checkout (Buy now: quantity, total, place order) | sheet on `/product/:id` |
| – | Orders (Buying / Selling, Custom requests shortcut) | `/orders` |
| – | Order details (timeline, payment proof upload/check, status actions, cancel, review) | `/order/:number` |
| – | Custom requests (Buying / Selling) | `/requests` |
| – | Request details (quotes, Send a quote / Decline, Accept / Ask for changes / Cancel) | `/request/:code` |
| – | Saved items | `/saved` |
| – | Notifications | `/notifications` |

**Navigation:** while signed out, only Log in, Sign up and Forgot password are reachable. After signing in, the app opens on Home with the bottom bar: **Home · Messages · Sell (+) · Orders · Saved**. Every other screen opens on top and has a back button. Signing out from My store returns to Log in.

## Project structure

```
lib/
  main.dart                     app entry, theme, router
  core/
    theme/app_colors.dart       Milestone 1 palette (olive moss = buyer, clay = seller)
    theme/app_theme.dart        Plus Jakarta Sans, spacing, radii, component themes
    router/app_router.dart      go_router: auth redirect, bottom-bar shell, all routes
    utils/format.dart           peso, date and time formatting
  data/
    models.dart                 Product, Seller, ChatThread, Order, …
    mock_data.dart              sample content (replaced by Supabase/Firebase in M3)
    providers.dart              Riverpod state: auth, catalog, saved, chats, orders, …
  shared/widgets/
    craft_icon*.dart            stroke icons from the mock-ups (flutter_svg)
    common.dart                 buttons, fields, chips, status pills, avatars, empty states
    product_widgets.dart        product cards, grid, photo placeholder, seller strip
    main_shell.dart             bottom navigation bar with the centre Sell button
  features/                     one folder per module (auth, home, product, custom_order,
                                messages, selling, store, orders, saved, notifications)
assets/
  images/logo.png               CraftHive logo
test/widget_test.dart
```

## Packages

`flutter_riverpod` (state), `go_router` (navigation), `flutter_svg` (icons) and `google_fonts` (Plus Jakarta Sans).

## Search

Search lives in `lib/data/search.dart` (matching and filters) and `lib/features/home/search_screen.dart` (UI).

- **Typo-tolerant matching** (`lib/core/utils/fuzzy.dart`): every word of the query has to match the
  title, store, category, description or custom options, either exactly, as the start of a word
  ("bouq"), inside a longer word, or with a few typos ("boquet", "candel", "keychian"). Words of 3
  letters or fewer must match exactly. "Best match" ranks title matches first.
- **Filters:** category, maximum price, accepts custom orders, in stock, **distance from your city**
  (10–300 km) and **delivered by** a date. "Nearest" sorting appears once a city is set; the city
  starts from the one on your profile.
- **Delivery estimate:** in stock = 1 day to pack, otherwise the listing's days to make (always for
  custom orders), plus courier days by distance (under 25 km: 1, 150 km: 2, 500 km: 3, farther or
  unknown: 5).
- **Store positions:** run `database/10_search_location.sql` once in Supabase → SQL Editor so the
  store cards include the store's coordinates (rounded to about 1 km). Without it, or for stores
  without coordinates, the centre of the store's city (`lib/core/utils/geo.dart`) is used.

## Verified Maker

Makers apply from **My store → Verified Maker**; CraftHive admins review them in the app.

- **Apply** (`lib/features/verification/verification_screen.dart`): type of government ID, a photo of
  it, 2–6 photos of their work, and consent under the Data Privacy Act of 2012. Files go to
  `private-files/{user_id}/verification/` (only the maker and admins can open them).
- **Review** (`lib/features/admin/admin_verification_screen.dart`): log in with an admin account
  (a row in the `admin` table, e.g. the one in `03_seed.sql`). Admins land on *Maker verification*
  (Waiting / Reviewed), open an application to see the ID and work photos, then **Approve** or
  **Not approved** with a reason the maker sees. Buyers and makers cannot open these screens.
- **Badge:** approved stores show the Verified Maker badge on the store card, product page and
  product cards.
- **ID deletion (RA 10173):** the ID photo is deleted **30 days after the decision**; files replaced
  by a new submission are deleted the next day the job runs. The app shows the maker the deletion date.

**Setup (once):**

1. Run `database/11_verified_maker.sql` in Supabase → SQL Editor. It adds the review functions and
   the deletion queue, and stops makers from changing their own verification status.
2. Deploy the deletion job (needs the Supabase CLI):
   ```
   supabase functions deploy purge-private-files --no-verify-jwt
   supabase secrets set CRON_SECRET=<a long random value>
   ```
3. Schedule it daily: enable `pg_net` (pg_cron is on since 08), add the Vault secrets `project_url` and
   `purge_cron_secret`, then run the `cron.schedule(...)` block at the end of `11_verified_maker.sql`.

Until step 2–3 are done, IDs are queued for deletion but not yet deleted.

## Disputes (Report a problem)

Either side of an order can report a problem once something has been paid
(Order details → **Report a problem**). A CraftHive admin reviews it.

- **Report** (`lib/features/disputes/report_problem_screen.dart`): what went wrong (a list for buyers
  and one for sellers), a description (at least 15 characters) and up to 5 photos. Photos go to
  `private-files/{user_id}/{order_id}/`, which the buyer, the seller and admins can open.
- **On the order:** the report card shows its status (Reported → Under review → Resolved / Closed),
  both sides' photos, and the admin's decision. Both sides can add photos while it is open. Each
  order has at most one open report.
- **Admin** (`lib/features/admin/admin_dispute_screen.dart`): the *Disputes* tab on the admin home lists
  open reports first. A case shows the order, accepted quote, payments with their proof, and all
  photos. The admin can **Start review**, **Resolve** or **Close without action**, writing a decision
  both sides see. The database saves the decision, its date and the admin who made it.
- **Notifications:** through `firebase-bridge`. The other side hears about a new report, and both
  sides hear when it is under review and when it is decided (also posted in their chat).

**Setup:** run `database/12_disputes.sql` in Supabase, then redeploy the bridge:
`supabase functions deploy firebase-bridge`.

## Admin accounts and dashboard

CraftHive staff sign in with the same Log in screen. Staff accounts live in the `admin` table, outside the marketplace `users` table, so they only see the admin screens.

- **Overview** (`lib/features/admin/admin_dashboard.dart`) shows:
  - makers waiting, with the oldest date
  - open disputes (new and under review)
  - decisions made this week
  - verified makers out of all stores
  - your own decisions
  - the ID-photo status (on file, being deleted this week, deleted in the last 30 days)

  It shows a red warning if any ID photo is past its 30-day deletion date, which means the daily purge job isn't running. Tap a card to jump to its tab.
- **Makers / Reviewed / Disputes** are the review queues from the Verified Maker and Disputes sections.
- **Staff** has two roles:
  - *Moderators* review makers and disputes.
  - *Superadmins* can also add staff (by work email; the person gets an email to choose their own password), change roles, and deactivate or reactivate staff.

  Deactivating blocks the sign-in but keeps the record, so the name stays on past decisions. CraftHive always keeps at least one active superadmin. A marketplace account's email can't be made a staff account.

**Setup:** run `database/13_admin_dashboard.sql`, then deploy the function:
`supabase functions deploy admin-accounts`. Add `ph.crafthive.app://reset-password` to
Authentication → URL Configuration → Redirect URLs, the same link that Forgot password uses.
The first superadmin comes from `03_seed.sql` (or insert one row into `admin` in the SQL editor).

## Reports (Milestone II, Information Needs)

Admins: **Reports** tab on the admin home, with all seven reports. Sellers: **My store → Store reports**, with the four reports about their own store (marked "store" below). Each report can be copied as CSV to paste into a spreadsheet.

| # | Report | Who | Built by |
|---|---|---|---|
| 1 | Store Directory | admins | `report_store_directory()` |
| 2 | Product Listing (by store / category) | admins, store | `report_product_listing()` |
| 3 | Search and Browse (term, filters, ready-by, trust score, distance) | admins | the app's own search + `store_trust_scores()` |
| 4 | Custom Request and Quote (quote versions in order) | admins, store | `report_custom_requests()` |
| 5 | Order and Payment (items and payments under each order) | admins, store | `report_orders()` |
| 6 | Seller Reliability (with trust score) | admins, store | `report_seller_reliability()` |
| 7 | Marketplace Activity (per category) | admins | `report_marketplace_activity()` |

**Seller trust score (0–100)** is made of:
- 30% on-time completion
- 25% average rating
- 20% completed orders vs cancelled orders
- 15% orders without disputes
- 10% Verified Maker

A part with no data yet counts as 0.7, so new stores start in the middle. The Search and Browse report uses the last 180 days. Period reports default to 90 days, and you can pick 30 days, 90 days, this year, or all time.

**Setup:** run `database/14_reports.sql` in Supabase.

## Sharing items and stores

The share buttons on an item page, on a store page, and **Share store** on My store open the phone's share sheet (`share_plus`) with a short message and a link that opens the app:

- `ph.crafthive.app://open/product/{product_id}`
- `ph.crafthive.app://open/store/{store_id}`

The message also gives the item name, price, store and city, so it is still useful in chat apps that don't make the link tappable. A link opened while signed out opens right after login. A link to your own store opens My store (`lib/shared/sharing.dart`, `lib/core/utils/share_links.dart`).

**Setup:** run `setup.ps1` (or `setup.sh`) again. It adds the `ph.crafthive.app://open` link to the Android manifest if it isn't there yet. Tappable web links (https) would need a CraftHive website domain with Android App Links; that isn't set up yet.
