# CraftHive REST API v1 — setup and testing guide

CraftHive now has its own REST API: one Supabase Edge Function named `api` that sits between the
Flutter app and the database. The app no longer calls tables and database functions by name
(`/rest/v1/rpc/place_order`); it calls resources (`POST /api/v1/orders`).

```
Flutter app ──HTTP + JSON──▶  api Edge Function  ──▶  database functions (place_order, submit_payment…)  ──▶  PostgreSQL
              /api/v1/...      (checks input,          (the business rules, unchanged)
                                picks the status code)
```

Base URL: `https://cylnldryczotoagaxwvw.supabase.co/functions/v1/api/v1`

## What was added or changed

| File | What it is |
| --- | --- |
| `supabase/functions/api/index.ts` | **The API.** Router, input checks, error codes, links. One file, pasted into the dashboard. |
| `database/15_rest_api.sql` | Gives each database error its own code (PT401, PT403, PT404, PT409, PT422) so the API can return the right HTTP status; adds `save_listing()` so a listing saves in one transaction; lets buyers edit and delete their own reviews. |
| `crafthive_app/lib/data/api/api_client.dart` | **New.** The app's HTTP client for the API (adds the login token, reads errors). |
| `crafthive_app/lib/data/repositories/order_repository.dart`, `custom_order_repository.dart`, `listing_repository.dart`, `catalog_repository.dart`, `receipt_scanner.dart` | Now call the API instead of tables and RPCs. Photo uploads still go straight to Supabase Storage. |
| `admin_`, `chat_`, `dispute_`, `report_`, `verification_repository.dart` | One line each: also understand the new PT error codes. |
| `crafthive_app/pubspec.yaml` | Adds the `http` package (already in `pubspec.lock`, version 1.6.0). |
| `supabase/functions/api/CraftHive_API.postman_collection.json` | All 37 requests, ready to import into Postman. |

## Deploy in this order

**1. Database** — Supabase → SQL Editor → New query → paste all of `database/15_rest_api.sql` → Run.
It should say *Success. No rows returned*. It is safe to run again.

**2. The API** — Supabase → Edge Functions → Deploy a new function → Via Editor.
- Name it exactly `api`.
- Replace the sample code with all of `supabase/functions/api/index.ts` → Deploy.
- Open the function's settings and turn **off** "Enforce JWT Verification" (like `scan-receipt`).
  The function checks the login itself, and `GET /categories` works without logging in.
- Quick check: open `https://cylnldryczotoagaxwvw.supabase.co/functions/v1/api/v1/categories`
  in a browser. You should see the categories as JSON.

**3. The app** — pull the branch, then in `crafthive_app/`:
```
flutter pub get
flutter run -d chrome     (or your phone)
```

Between steps 1 and 3, an older copy of the app still works, but some error messages become the
generic "Something went wrong" until the new app is installed.

## Test it

**Postman:** Import → `CraftHive_API.postman_collection.json` → open the collection's
*Variables* → fill in `email` and `password` of a test account → run **0. Log in** (it saves the
token) → run any request. Requests that create something save the new id for the next ones, so
running *List products* then *Place order* works without copying ids.

Good requests for the class demo:

| Request | Shows |
| --- | --- |
| Place order (201) | `201 Created`, a `Location` header, and `_links` (pay, cancel) |
| Place order — quantity 0 (422) | `422` with `{"error": {"code": "VALIDATION_FAILED", "field": "quantity"}}` |
| Place order — wrong type (400) | `400` when `quantity` is `"two"` |
| Submit payment proof twice | `409` `DUPLICATE_REFERENCE` |
| *List categories* with the method changed to DELETE | `405 Method Not Allowed` with an `Allow: GET` header |

**Chrome:** run the app with `flutter run -d chrome`, press F12 → Network → filter `api/v1`.
Before, placing an order showed `POST /rest/v1/rpc/place_order → 200`.
Now it shows `POST /functions/v1/api/v1/orders → 201`.

## Endpoints

| Resource | Endpoints |
| --- | --- |
| Index | `GET /` lists the resources with links |
| Categories | `GET /categories`, `GET /categories/{categoryId}` |
| Stores | `GET /stores`, `GET /stores/{storeId}`, `POST /stores`, `PATCH /stores/{storeId}`, `GET /stores/{storeId}/products` |
| Products | `GET /products?category=&q=&minPrice=&maxPrice=`, `GET /products/{productId}`, `POST /products`, `PUT /products/{productId}`, `PATCH /products/{productId}`, `DELETE /products/{productId}` (drafts only) |
| Orders | `GET /orders?role=buyer\|seller`, `GET /orders/{orderId}`, `POST /orders`, `PATCH /orders/{orderId}`, `GET /orders/{orderId}/history` |
| Payments | `GET /orders/{orderId}/payments`, `POST /orders/{orderId}/payments`, `PATCH /orders/{orderId}/payments/{paymentId}`, `POST /orders/{orderId}/receipt-scans` |
| Reviews | `GET /products/{productId}/reviews`, `POST /orders/{orderId}/reviews`, `PATCH /reviews/{reviewId}`, `DELETE /reviews/{reviewId}` |
| Custom requests | `GET /custom-requests`, `GET /custom-requests/{requestId}`, `POST /custom-requests`, `PATCH /custom-requests/{requestId}`, `POST /custom-requests/{requestId}/images` |
| Quotes | `GET /custom-requests/{requestId}/quotes`, `POST /custom-requests/{requestId}/quotes`, `PATCH /custom-requests/{requestId}/quotes/{quoteId}` |

Every endpoint except `GET /` and the two category endpoints needs `Authorization: Bearer <access token>`.

## Small differences from the paper (update the paper to match)

- **Added** `POST /custom-requests/{requestId}/images` (attach a reference photo) and `GET /`
  (the index). The Reviews endpoints are included too, so you can add them back to 3.2.
- **Quote answers** use `"status": "accepted"` or `"changes_requested"` (`"rejected"` also works).
- **Logging in:** only categories are public; stores and products need a login, because of RLS.
- **Example 1's response** in 3.3 has more fields in the real API (`side`, `counterpart`,
  `history`, `payment`…). After the first real order, copy the actual response into the paper.
- **3.5 Richardson level:** now true for the finished API. Orders and custom requests return
  `_links` that change with the status (a paid order loses `cancel` and gains `ship`).

## If something goes wrong

| You see | Fix |
| --- | --- |
| `404 Requested function was not found` | The function is not deployed or is not named exactly `api`. |
| `401` on `GET /categories` without logging in | "Enforce JWT Verification" is still on; turn it off. |
| `401` on other requests | The token is missing or expired: run *0. Log in* again (Postman) or log out and in (app). |
| `500` when saving a listing | `database/15_rest_api.sql` was not run. |
| Errors show "Something went wrong" in the old app | Expected until the new app is installed (see step 3). |

**To undo:** delete the `api` function, run `database/04_orders_and_custom_orders.sql` again (this
brings back the old P0001 error codes), and switch the app back to the previous commit.

## How it was checked

- `database/15_rest_api.sql` was run twice on a local PostgreSQL with `01`, `02` and `04`, then a
  test of every error path (each comes back with the expected PT code), `save_listing()` saving and
  replacing photos and options, RLS blocking another user, and the new review policies.
- `index.ts` passes the TypeScript compiler in strict mode, and 62 behaviour tests ran against an
  in-memory stand-in for Supabase (routing, validation, status codes, links, error mapping).
- The Dart changes were reviewed by hand but **not compiled** (no Flutter SDK was available).
  Run `flutter analyze` after `flutter pub get` and fix anything it reports.
