# CraftHive – Firebase setup (messaging and notifications)

Do this once for the group. It takes about 30 minutes. Only **one** person makes
the Firebase project; everyone else just pulls the code.

## How it fits together

| Part | Where | What it does |
|---|---|---|
| Login | Supabase Auth (unchanged) | Sign up, log in, password reset |
| Firebase sign-in | Edge Function `firebase-bridge` → Firebase custom token | Signs the same user in to Firebase. The Firebase uid **is** the Supabase user ID, so the rules can protect each chat |
| Chat | Firestore `chats/{buyerUid}_{storeId}` and `/messages` | One chat per buyer and store. Live messages, unread counts, "Seen" |
| Online and typing | Realtime Database `/status/{uid}`, `/typing/{chatId}/{uid}` | Green dot, "typing…". Goes offline by itself when the phone disconnects |
| Notification list | Firestore `notifications/{uid}/items` | The bell screen |
| Push | Firebase Cloud Messaging | Phone notifications. Tokens are kept in Firestore `users/{uid}.fcmTokens` |
| Order and quote events | Postgres triggers (`05_firebase.sql`) → pg_net → `firebase-bridge` | After an order, payment, quote, request or review is **saved in Postgres**, the function writes the notification, sends the push, and posts quote cards and order updates into the chat |

Postgres stays the source of truth (Milestone II, assumption 15). A failed
notification never blocks an order.

Files added:

```
database/05_firebase.sql                      triggers + chat_target()
supabase/functions/firebase-bridge/index.ts   the Edge Function (one file)
firebase/firestore.rules                      Firestore security rules
firebase/database.rules.json                  Realtime Database rules
crafthive_app/lib/core/config/firebase_config.dart   ← you fill this in
crafthive_app/lib/data/repositories/chat_repository.dart
crafthive_app/lib/data/repositories/presence_repository.dart
crafthive_app/lib/data/repositories/notification_repository.dart
crafthive_app/lib/data/repositories/firebase_session.dart
crafthive_app/lib/shared/widgets/realtime_scope.dart
crafthive_app/test/messaging_test.dart
```

Until `firebase_config.dart` is filled in, the app still runs and shows the old
sample chats, so nothing breaks while you set this up.

---

## 1. Get the code ready

In PowerShell, inside `CraftHive-repo`:

```
git pull origin Development
cd crafthive_app
powershell -ExecutionPolicy Bypass -File .\setup.ps1
```

`setup.ps1` creates the `android` folder if you don't have it, adds the
notification permission for Android 13+, and runs `flutter pub get`.

## 2. Create the Firebase project

1. Go to <https://console.firebase.google.com> → **Create a project**.
2. Name it, for example `crafthive-group9`. You can turn Google Analytics **off**.
3. On the project home, click the **Android** icon (Add app):
   - **Android package name:** `ph.crafthive.crafthive`
     (check `applicationId` in `crafthive_app/android/app/build.gradle.kts` if unsure)
   - Nickname: `CraftHive`
   - Click **Register app**. You can download `google-services.json` to read the
     values from, but **don't** add it to the project, and skip the Gradle steps.
     The app starts Firebase from `firebase_config.dart` instead.

## 3. Fill in `firebase_config.dart`

Open `crafthive_app/lib/core/config/firebase_config.dart`. Copy the values from
**Project settings** (gear icon) → **General**:

| Field | Where to find it |
|---|---|
| `apiKey` | "Web API key" at the top (or `api_key.current_key` in google-services.json) |
| `appId` | Your apps → the Android app → "App ID" (`1:…:android:…`) |
| `messagingSenderId` | "Project number" |
| `projectId` | "Project ID" |
| `databaseUrl` | Fill in after step 4c |

## 4. Turn on the Firebase services

**a. Authentication.** Build → **Authentication** → **Get started**. You don't
need to enable any sign-in method, because custom tokens work without one.

**b. Firestore.** Build → **Firestore Database** → **Create database**
- Location: **asia-southeast1 (Singapore)**
- Start in **production mode**
- Open the **Rules** tab, replace everything with the contents of
  `firebase/firestore.rules`, and click **Publish**.

**c. Realtime Database.** Build → **Realtime Database** → **Create database**
- Location: **Singapore (asia-southeast1)**
- Start in **locked mode**
- Copy the URL shown above the data
  (`https://…-default-rtdb.asia-southeast1.firebasedatabase.app`) into `databaseUrl`
- Open the **Rules** tab, paste `firebase/database.rules.json`, and click **Publish**.

**d. Cloud Messaging.** Project settings → **Cloud Messaging**. Check that
"Firebase Cloud Messaging API (V1)" says **Enabled**. It is on by default.

**e. (Optional) Auto-delete old notifications.** In the Google Cloud console,
Firestore → TTL policies, add a policy on collection group `items`, field
`expireAt`. Each notification already gets an `expireAt` 90 days ahead.

## 5. Make a service account key

Project settings → **Service accounts** → **Generate new private key** →
**Generate key**. A `.json` file downloads.

> ⚠️ This file is a password for the whole Firebase project. **Never** put it in
> the repo, in the app or in a screenshot. It only goes into Supabase secrets.

## 6. Deploy the Edge Function (Supabase dashboard)

1. Supabase dashboard → project **CraftHive** → **Edge Functions** →
   **Deploy a new function** → **Via Editor**.
2. Name: `firebase-bridge`. Delete the sample code, paste the whole of
   `supabase/functions/firebase-bridge/index.ts`, and click **Deploy**.
3. Open the function → **Details**, turn **Enforce JWT verification OFF**, and save.
   The function checks the user's login itself. The database triggers call it
   with a secret instead of a login.
4. Edge Functions → **Secrets** → add two secrets:
   - `FIREBASE_SERVICE_ACCOUNT`: open the key file from step 5 in Notepad, and
     paste **all** of it (from `{` to `}`)
   - `DB_EVENTS_SECRET`: any long random text. In PowerShell,
     `[guid]::NewGuid().ToString() + [guid]::NewGuid().ToString()` makes one. Keep
     it for step 7.

## 7. Run the SQL (Supabase SQL editor)

1. Paste and run `database/05_firebase.sql`. If it says pg_net is not available,
   go to Database → **Extensions**, turn on **pg_net**, and run it again.
2. Then run this, with your secret from step 6:

```sql
select vault.create_secret('https://cylnldryczotoagaxwvw.supabase.co/functions/v1/firebase-bridge', 'db_events_url');
select vault.create_secret('PASTE-THE-DB_EVENTS_SECRET-HERE', 'db_events_secret');
```

To change one later: `select vault.update_secret((select id from vault.secrets where name = 'db_events_secret'), 'new value');`

## 8. Run it

```
cd crafthive_app
flutter pub get
flutter run
```

Use a real phone, or an emulator image **with Google Play** (push needs Google
Play services). On Android 13+ the app asks to allow notifications: tap **Allow**.

---

## Checking that it works

Use two accounts on two devices: a phone and an emulator, or two phones. Account
B needs a store with a listing that accepts custom orders.

| # | Do this | You should see |
|---|---|---|
| 1 | A opens B's store → **Message** | Chat opens. B sees it under Messages → Selling |
| 2 | A sends "hello" | It appears on B's phone right away. B's Messages badge goes up. B gets a push if the app is in the background |
| 3 | B opens the chat | A's message shows "Seen". A sees B as **Online** (green dot) |
| 4 | B types without sending | A sees "typing…" |
| 5 | A sends a custom request | B gets "New custom request" (bell + push). A note appears in the chat |
| 6 | B sends a quote | A gets "New quote", and a quote card appears in the chat |
| 7 | A taps **Confirm order** on the card | B gets "Quote accepted". The order is created |
| 8 | A uploads a payment proof / B confirms it | B gets "Payment proof received" / A gets "Payment confirmed" |
| 9 | B marks it shipped, A confirms receipt, A reviews | A gets "on the way". B gets "Order completed" and "New review" |
| 10 | Tap any push while the app is closed | The app opens on that order, request or chat |
| 11 | Turn off A's Wi-Fi | Within about a minute A shows offline on B's phone |

Automated tests: `flutter test` (see `test/messaging_test.dart`, TC-M01…TC-M06
and TC-N01…TC-N04).

## When something goes wrong

| Problem | Look here |
|---|---|
| Messages shows "Chats could not load" | The Edge Function isn't deployed, JWT verification is still on, or `FIREBASE_SERVICE_ACCOUNT` is wrong. Edge Functions → firebase-bridge → **Logs** |
| Chats load but you get "Your chat session expired" | Firestore rules not published (step 4b) |
| No notification after an order or quote | SQL editor: `select status_code, content from net._http_response order by created desc limit 10;`. 401 means the two secrets don't match. No rows means the Vault secrets are missing |
| Notifications appear in the bell but no push | Notification permission is off, or the emulator has no Google Play |
| Build error about `minSdk` | In `android/app/build.gradle.kts` set `minSdk = 24` |
| Still seeing the old sample chats | `firebase_config.dart` is not filled in, or `databaseUrl` doesn't start with `https://` |
