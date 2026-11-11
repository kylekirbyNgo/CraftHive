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
