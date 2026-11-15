// =============================================================================
// CraftHive – firebase-bridge (Supabase Edge Function)
//
// Connects Supabase (accounts, orders, quotes: the source of truth) with
// Firebase (chat, presence, notifications, push). One function with three
// actions, so it can be deployed from the Supabase dashboard as a single file:
//
//   { "action": "token" }                         app → Firebase custom token
//   { "action": "chat_push", chatId, messageId }  app → push for a new chat message
//   { "action": "db_event", table, type, ... }    Postgres trigger (pg_net) → notification
//
// Secrets (Supabase → Edge Functions → Secrets):
//   FIREBASE_SERVICE_ACCOUNT  the whole JSON key file of a Firebase service account
//   DB_EVENTS_SECRET          any long random text; the same value is saved in Vault
//                             for database/05_firebase.sql
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are provided by Supabase.
//
// Deploy with "Verify JWT" turned OFF: the app's calls are checked below with
// the user's Supabase access token, and database calls with DB_EVENTS_SECRET.
// =============================================================================

import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";

// -----------------------------------------------------------------------------
// Small helpers
// -----------------------------------------------------------------------------
type Json = Record<string, unknown>;

class HttpError extends Error {
  constructor(public status: number, message: string) {
    super(message);
  }
}

// The app also runs in a browser (flutter run -d chrome), which asks first with
// an OPTIONS request and needs these headers on every answer.
const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } });
}

function env(name: string): string {
  const v = Deno.env.get(name);
  if (!v) throw new HttpError(500, `Missing secret ${name}.`);
  return v;
}

const peso = (n: unknown) =>
  "₱" + Number(n ?? 0).toLocaleString("en-PH", { minimumFractionDigits: 0, maximumFractionDigits: 2 });

const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
/** "2026-12-18" → "Dec 18" */
function shortDate(d: unknown): string {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(d ?? ""));
  return m ? `${MONTHS[Number(m[2]) - 1]} ${Number(m[3])}` : String(d ?? "");
}

const clip = (s: string, n: number) => (s.length > n ? s.slice(0, n - 1).trimEnd() + "…" : s);

// -----------------------------------------------------------------------------
// Google service-account auth (RS256 JWTs signed with Web Crypto)
// -----------------------------------------------------------------------------
interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
}

let _sa: ServiceAccount | null = null;
function serviceAccount(): ServiceAccount {
  if (_sa) return _sa;
  let parsed: ServiceAccount;
  try {
    parsed = JSON.parse(env("FIREBASE_SERVICE_ACCOUNT"));
  } catch (_) {
    throw new HttpError(500, "FIREBASE_SERVICE_ACCOUNT is not valid JSON. Paste the whole key file.");
  }
  if (!parsed.project_id || !parsed.client_email || !parsed.private_key) {
    throw new HttpError(500, "FIREBASE_SERVICE_ACCOUNT is missing project_id, client_email or private_key.");
  }
  _sa = parsed;
  return parsed;
}

const b64url = (bytes: Uint8Array) =>
  btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const b64urlText = (s: string) => b64url(new TextEncoder().encode(s));

let _key: CryptoKey | null = null;
async function signingKey(): Promise<CryptoKey> {
  if (_key) return _key;
  const pem = serviceAccount().private_key.replace(/\\n/g, "\n");
  const body = pem.replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\s/g, "");
  const der = Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
  _key = await crypto.subtle.importKey("pkcs8", der, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  return _key;
}

export async function signJwt(payload: Json): Promise<string> {
  const head = b64urlText(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const body = b64urlText(JSON.stringify(payload));
  const sig = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", await signingKey(), new TextEncoder().encode(`${head}.${body}`));
  return `${head}.${body}.${b64url(new Uint8Array(sig))}`;
}

/** Firebase Auth custom token: the app signs in with it, and request.auth.uid becomes [uid]. */
async function customToken(uid: string): Promise<string> {
  const sa = serviceAccount();
  const now = Math.floor(Date.now() / 1000);
  return signJwt({
    iss: sa.client_email,
    sub: sa.client_email,
    aud: "https://identitytoolkit.googleapis.com/google.identity.identitytoolkit.v1.IdentityToolkit",
    iat: now,
    exp: now + 3600,
    uid,
  });
}

let _access: { token: string; exp: number } | null = null;
/** OAuth token for Firestore and FCM. Calls made with it skip the security rules. */
async function accessToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (_access && _access.exp - 60 > now) return _access.token;
  const sa = serviceAccount();
  const assertion = await signJwt({
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/datastore https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  });
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion }),
  });
  if (!res.ok) throw new HttpError(500, `Google sign-in failed: ${await res.text()}`);
  const data = await res.json();
  _access = { token: data.access_token, exp: now + Number(data.expires_in ?? 3600) };
  return _access.token;
}

// -----------------------------------------------------------------------------
// Firestore REST
// -----------------------------------------------------------------------------
const dbRoot = () => `projects/${serviceAccount().project_id}/databases/(default)/documents`;
const docName = (path: string) => `${dbRoot()}/${path}`;

type FsValue = Json;

export function toValue(v: unknown): FsValue {
  if (v === null || v === undefined) return { nullValue: null };
  if (v instanceof Date) return { timestampValue: v.toISOString() };
  if (typeof v === "boolean") return { booleanValue: v };
  if (typeof v === "number") return Number.isInteger(v) ? { integerValue: String(v) } : { doubleValue: v };
  if (typeof v === "string") return { stringValue: v };
  if (Array.isArray(v)) return { arrayValue: { values: v.map(toValue) } };
  return { mapValue: { fields: toFields(v as Json) } };
}

export function toFields(o: Json): Record<string, FsValue> {
  const out: Record<string, FsValue> = {};
  for (const [k, v] of Object.entries(o)) if (v !== undefined) out[k] = toValue(v);
  return out;
}

export function fromValue(v: FsValue): unknown {
  if ("nullValue" in v) return null;
  if ("booleanValue" in v) return v.booleanValue;
  if ("integerValue" in v) return Number(v.integerValue);
  if ("doubleValue" in v) return v.doubleValue;
  if ("stringValue" in v) return v.stringValue;
  if ("timestampValue" in v) return v.timestampValue;
  if ("arrayValue" in v) return (((v.arrayValue as Json).values as FsValue[]) ?? []).map(fromValue);
  if ("mapValue" in v) return fromFields(((v.mapValue as Json).fields as Record<string, FsValue>) ?? {});
  return null;
}

export function fromFields(f: Record<string, FsValue>): Json {
  const out: Json = {};
  for (const [k, v] of Object.entries(f)) out[k] = fromValue(v);
  return out;
}

/** Field path segment; Supabase IDs contain "-", so they need backticks. */
export const seg = (s: string) => (/^[A-Za-z_][A-Za-z_0-9]*$/.test(s) ? s : "`" + s.replace(/`/g, "\\`") + "`");

async function fs(method: string, url: string, body?: unknown): Promise<Response> {
  return fetch(`https://firestore.googleapis.com/v1/${url}`, {
    method,
    headers: { Authorization: `Bearer ${await accessToken()}`, "Content-Type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
}

async function getDoc(path: string): Promise<Json | null> {
  const res = await fs("GET", docName(path));
  if (res.status === 404) return null;
  if (!res.ok) throw new HttpError(500, `Firestore read failed: ${await res.text()}`);
  const doc = await res.json();
  return fromFields(doc.fields ?? {});
}

async function commit(writes: Json[]): Promise<void> {
  const res = await fs("POST", `projects/${serviceAccount().project_id}/databases/(default)/documents:commit`, { writes });
  if (!res.ok) throw new HttpError(500, `Firestore write failed: ${await res.text()}`);
}

/** Firestore-style auto ID (20 letters and digits). */
function autoId(): string {
  const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
  const bytes = crypto.getRandomValues(new Uint8Array(20));
  return Array.from(bytes, (b) => chars[b % chars.length]).join("");
}

// -----------------------------------------------------------------------------
// Push (FCM HTTP v1). Device tokens are kept in Firestore users/{uid}.fcmTokens.
// -----------------------------------------------------------------------------
interface Push {
  title: string;
  body: string;
  /** Screen to open when the notification is tapped, e.g. /order/CH-2026-000012 */
  route: string;
  type: string;
  /** Notifications with the same tag replace each other (one per chat). */
  tag?: string;
}

async function sendPush(uid: string, p: Push): Promise<number> {
  const user = await getDoc(`users/${uid}`);
  const tokens = ((user?.fcmTokens as string[] | undefined) ?? []).filter((t) => typeof t === "string" && t.length > 0);
  if (tokens.length === 0) return 0;
  const dead: string[] = [];
  let sent = 0;
  for (const token of tokens) {
    const res = await fetch(`https://fcm.googleapis.com/v1/projects/${serviceAccount().project_id}/messages:send`, {
      method: "POST",
      headers: { Authorization: `Bearer ${await accessToken()}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        message: {
          token,
          notification: { title: p.title, body: p.body },
          data: { route: p.route, type: p.type },
          android: { priority: "HIGH", notification: { tag: p.tag } },
        },
      }),
    });
    if (res.ok) {
      sent++;
    } else {
      const text = await res.text();
      // The app was uninstalled or the token expired: forget it.
      if (res.status === 404 || text.includes("UNREGISTERED") || text.includes("registration-token-not-registered")) dead.push(token);
      else console.error("FCM send failed", res.status, text);
    }
  }
  if (dead.length > 0) {
    await commit([{
      transform: {
        document: docName(`users/${uid}`),
        fieldTransforms: [{ fieldPath: "fcmTokens", removeAllFromArray: { values: dead.map(toValue) } }],
      },
    }]);
  }
  return sent;
}

// -----------------------------------------------------------------------------
// Notifications list (Firestore notifications/{uid}/items) + push
// -----------------------------------------------------------------------------
type NoticeType = "quote" | "payment" | "request" | "shipping" | "review" | "order";

interface Notice {
  type: NoticeType;
  title: string;
  body: string;
  /** "order" (refId = order number), "request" (refId = request number) or "chat" (refId = chat ID) */
  refType: "order" | "request" | "chat";
  refId: string;
}

const routeFor = (n: Notice) =>
  n.refType === "order" ? `/order/${n.refId}` : n.refType === "request" ? `/request/${n.refId}` : `/chat/${n.refId}`;

async function notify(uid: string | null | undefined, n: Notice): Promise<void> {
  if (!uid) return;
  const expireAt = new Date(Date.now() + 90 * 24 * 3600 * 1000); // TTL policy can delete old ones
  await commit([{
    update: {
      name: docName(`notifications/${uid}/items/${autoId()}`),
      fields: toFields({ ...n, read: false, expireAt }),
    },
    currentDocument: { exists: false },
    updateTransforms: [{ fieldPath: "createdAt", setToServerValue: "REQUEST_TIME" }],
  }]);
  try {
    await sendPush(uid, { title: n.title, body: n.body, route: routeFor(n), type: n.type });
  } catch (e) {
    // The notification is saved even when the push fails; the app shows it next time.
    console.error("push failed", e);
  }
}

// -----------------------------------------------------------------------------
// Chat (Firestore chats/{buyerUid}_{storeId}) written by the server:
// custom-request notes, quote cards and order updates.
// -----------------------------------------------------------------------------
interface Party {
  buyerId: string;
  buyerName: string;
  storeId: string;
  storeName: string;
  sellerId: string;
}

export const chatIdFor = (buyerId: string, storeId: string) => `${buyerId}_${storeId}`;

interface ChatPost {
  /** Message document: type "system" or "quote" plus its fields. */
  message: Json;
  preview: string;
  /** Short status under the chat in the Messages list. */
  tag?: { label: string; tone: string };
  /** Extra chat fields such as productId, requestId, orderNumber. */
  extra?: Json;
  /** Who gets an unread count for this message. */
  unreadFor?: string[];
}

async function postToChat(p: Party, post: ChatPost): Promise<string> {
  const chatId = chatIdFor(p.buyerId, p.storeId);
  const chatFields: Json = {
    participantUids: [p.buyerId, p.sellerId],
    buyerUid: p.buyerId,
    sellerUid: p.sellerId,
    storeId: p.storeId,
    buyerName: p.buyerName,
    storeName: p.storeName,
    lastMessage: post.preview,
    lastSenderUid: null,
    ...(post.tag ? { tagLabel: post.tag.label, tagTone: post.tag.tone } : {}),
    ...(post.extra ?? {}),
  };
  await commit([
    {
      // Creates the chat if it does not exist yet; otherwise changes only these fields.
      update: { name: docName(`chats/${chatId}`), fields: toFields(chatFields) },
      updateMask: { fieldPaths: Object.keys(chatFields).map(seg) },
      updateTransforms: [
        { fieldPath: "lastMessageAt", setToServerValue: "REQUEST_TIME" },
        ...(post.unreadFor ?? []).map((uid) => ({ fieldPath: `unread.${seg(uid)}`, increment: { integerValue: "1" } })),
      ],
    },
    {
      update: {
        name: docName(`chats/${chatId}/messages/${autoId()}`),
        fields: toFields({ senderUid: null, text: "", ...post.message }),
      },
      currentDocument: { exists: false },
      updateTransforms: [{ fieldPath: "createdAt", setToServerValue: "REQUEST_TIME" }],
    },
  ]);
  return chatId;
}

// -----------------------------------------------------------------------------
// Supabase (service role) lookups
// -----------------------------------------------------------------------------
let _admin: SupabaseClient | null = null;
function admin(): SupabaseClient {
  if (_admin) return _admin;
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? env("SERVICE_ROLE_KEY");
  _admin = createClient(env("SUPABASE_URL"), key, { auth: { persistSession: false, autoRefreshToken: false } });
  return _admin;
}

async function one(table: string, columns: string, column: string, value: unknown): Promise<Json | null> {
  const { data, error } = await admin().from(table).select(columns).eq(column, value).limit(1).maybeSingle();
  if (error) throw new HttpError(500, `${table}: ${error.message}`);
  return data as Json | null;
}

async function partyFor(buyerId: string, storeId: string): Promise<Party> {
  const [store, buyer] = await Promise.all([
    one("store", "store_id, store_name, seller_id", "store_id", storeId),
    one("users", "user_id, full_name, username", "user_id", buyerId),
  ]);
  if (!store) throw new HttpError(404, "Store not found.");
  return {
    buyerId,
    buyerName: String(buyer?.full_name ?? buyer?.username ?? "A buyer"),
    storeId,
    storeName: String(store.store_name),
    sellerId: String(store.seller_id),
  };
}

interface OrderInfo extends Party {
  orderId: string;
  number: string;
  total: number;
  quoteId: string | null;
  title: string;
  quantity: number;
  productId: string | null;
}

async function orderInfo(orderId: string): Promise<OrderInfo> {
  const o = await one("orders", "order_id, order_number, buyer_id, store_id, quote_id, total_amount", "order_id", orderId);
  if (!o) throw new HttpError(404, "Order not found.");
  const item = await one("order_item", "product_id, quantity", "order_id", orderId);
  const product = item ? await one("product", "product_id, title", "product_id", item.product_id) : null;
  return {
    ...(await partyFor(String(o.buyer_id), String(o.store_id))),
    orderId,
    number: String(o.order_number),
    total: Number(o.total_amount),
    quoteId: (o.quote_id as string | null) ?? null,
    title: String(product?.title ?? "your item"),
    quantity: Number(item?.quantity ?? 1),
    productId: (item?.product_id as string | undefined) ?? null,
  };
}

interface RequestInfo extends Party {
  requestId: string;
  code: string;
  title: string;
  productId: string;
  quantity: number;
  neededBy: string;
}

async function requestInfo(requestId: string): Promise<RequestInfo> {
  const r = await one("custom_request", "request_id, request_number, buyer_id, product_id, quantity, needed_by_date", "request_id", requestId);
  if (!r) throw new HttpError(404, "Request not found.");
  const p = await one("product", "product_id, title, store_id", "product_id", r.product_id);
  if (!p) throw new HttpError(404, "Product not found.");
  return {
    ...(await partyFor(String(r.buyer_id), String(p.store_id))),
    requestId,
    code: String(r.request_number),
    title: String(p.title),
    productId: String(p.product_id),
    quantity: Number(r.quantity),
    neededBy: String(r.needed_by_date),
  };
}

const system = (text: string) => ({ type: "system", text });

// -----------------------------------------------------------------------------
// Database events (sent by the triggers in database/05_firebase.sql)
// -----------------------------------------------------------------------------
interface DbEvent {
  table: string;
  type: "INSERT" | "UPDATE";
  record: Json;
  old_record: Json | null;
}

async function onCustomRequest(e: DbEvent) {
  const r = e.record;
  const info = await requestInfo(String(r.request_id));
  const extra = { productId: info.productId, requestId: info.requestId, requestCode: info.code };

  if (e.type === "INSERT") {
    await postToChat(info, {
      message: system(`Custom request ${info.code} · ${info.title} × ${info.quantity}, needed by ${shortDate(info.neededBy)}`),
      preview: `Custom request ${info.code}`,
      tag: { label: "Custom · Needs reply", tone: "warning" },
      extra,
      unreadFor: [info.sellerId],
    });
    await notify(info.sellerId, {
      type: "request",
      title: "New custom request",
      body: `${info.buyerName} asked for a custom ${info.title} (${info.code}). Send a quote or decline.`,
      refType: "request",
      refId: info.code,
    });
    return;
  }
  if (e.old_record?.status !== "cancelled" && r.status === "cancelled") {
    await postToChat(info, {
      message: system(`${info.buyerName} cancelled request ${info.code}`),
      preview: `Request ${info.code} cancelled`,
      tag: { label: "Custom · Cancelled", tone: "neutral" },
      extra,
    });
    await notify(info.sellerId, {
      type: "request",
      title: "Request cancelled",
      body: `${info.buyerName} cancelled custom request ${info.code}.`,
      refType: "request",
      refId: info.code,
    });
  }
}

async function onQuote(e: DbEvent) {
  const q = e.record;
  const info = await requestInfo(String(q.request_id));
  const extra = { productId: info.productId, requestId: info.requestId, requestCode: info.code };
  const before = e.old_record?.status;

  if (e.type === "INSERT" && q.status === "sent") {
    await postToChat(info, {
      message: {
        type: "quote",
        text: String(q.message ?? ""),
        quoteId: String(q.quote_id),
        requestId: info.requestId,
        requestCode: info.code,
        item: `${info.title}${info.quantity > 1 ? ` × ${info.quantity}` : ""}`,
        price: Number(q.offered_price),
        readyBy: String(q.estimated_completion_date),
        version: Number(q.version_no),
      },
      preview: `Quote: ${peso(q.offered_price)} for ${info.title}`,
      tag: { label: "Custom · Quoted", tone: "info" },
      extra,
      unreadFor: [info.buyerId],
    });
    await notify(info.buyerId, {
      type: "quote",
      title: `New quote from ${info.storeName}`,
      body: `${peso(q.offered_price)} for ${info.title}, ready by ${shortDate(q.estimated_completion_date)}. Accept it or ask for changes.`,
      refType: "request",
      refId: info.code,
    });
    return;
  }
  if (e.type === "INSERT" && q.status === "declined") {
    const reason = String(q.decline_reason ?? "").trim();
    await postToChat(info, {
      message: system(`${info.storeName} declined request ${info.code}${reason ? `: ${reason}` : ""}`),
      preview: `Request ${info.code} declined`,
      tag: { label: "Custom · Declined", tone: "error" },
      extra,
      unreadFor: [info.buyerId],
    });
    await notify(info.buyerId, {
      type: "request",
      title: "Request declined",
      body: `${info.storeName} declined ${info.code}${reason ? `: ${clip(reason, 120)}` : "."}`,
      refType: "request",
      refId: info.code,
    });
    return;
  }
  if (e.type === "UPDATE" && before === "sent" && q.status === "accepted") {
    const order = await one("orders", "order_id, order_number", "quote_id", q.quote_id);
    const number = String(order?.order_number ?? "");
    await postToChat(info, {
      message: system(`Quote v${q.version_no} accepted · order ${number} is waiting for payment`),
      preview: `Quote accepted · ${number}`,
      tag: { label: "Custom · Accepted", tone: "success" },
      extra: { ...extra, orderId: order?.order_id ?? null, orderNumber: number || null },
    });
    await notify(info.sellerId, {
      type: "quote",
      title: "Quote accepted",
      body: `${info.buyerName} accepted your ${peso(q.offered_price)} quote for ${info.code}. Order ${number} is waiting for their payment.`,
      refType: number ? "order" : "request",
      refId: number || info.code,
    });
    return;
  }
  if (e.type === "UPDATE" && before === "sent" && q.status === "changes_requested") {
    const note = String(q.decline_reason ?? "").trim();
    await postToChat(info, {
      message: system(`${info.buyerName} asked for changes on quote v${q.version_no}${note ? `: ${note}` : ""}`),
      preview: "Changes requested",
      tag: { label: "Custom · Needs reply", tone: "warning" },
      extra,
      unreadFor: [info.sellerId],
    });
    await notify(info.sellerId, {
      type: "quote",
      title: "Changes requested",
      body: `${info.buyerName} asked for changes on ${info.code}${note ? `: ${clip(note, 120)}` : ". Send a new quote."}`,
      refType: "request",
      refId: info.code,
    });
  }
}

async function onOrderHistory(e: DbEvent) {
  const h = e.record;
  const from = (h.from_status as string | null) ?? null;
  const to = String(h.to_status);
  // Rows without a status change are payment notes, handled by onPayment.
  // "confirmed" always follows a verified payment, also handled by onPayment.
  if (from === to || to === "confirmed") return;

  const o = await orderInfo(String(h.order_id));
  const by = (h.changed_by as string | null) ?? null;
  const extra = { orderId: o.orderId, orderNumber: o.number, ...(o.productId ? { productId: o.productId } : {}) };

  if (from === null) {
    // A custom order starts when a quote is accepted; onQuote already said so.
    if (o.quoteId) return;
    await postToChat(o, {
      message: system(`Order ${o.number} placed · ${o.quantity}× ${o.title} · ${peso(o.total)}`),
      preview: `Order ${o.number} placed`,
      tag: { label: "Order · Awaiting payment", tone: "warning" },
      extra,
      unreadFor: [o.sellerId],
    });
    await notify(o.sellerId, {
      type: "order",
      title: "New order",
      body: `${o.buyerName} ordered ${o.quantity}× ${o.title} (${o.number}). Wait for their payment proof.`,
      refType: "order",
      refId: o.number,
    });
    return;
  }

  const toBuyer = (n: Omit<Notice, "refType" | "refId">) => notify(o.buyerId, { ...n, refType: "order", refId: o.number });
  const toSeller = (n: Omit<Notice, "refType" | "refId">) => notify(o.sellerId, { ...n, refType: "order", refId: o.number });
  const note = (text: string, label: string, tone: string, unreadFor: string[]) =>
    postToChat(o, { message: system(text), preview: text, tag: { label, tone }, extra, unreadFor });

  switch (to) {
    case "in_production":
      await note(`${o.storeName} started making order ${o.number}`, "Order · In production", "seller", [o.buyerId]);
      await toBuyer({ type: "order", title: "Your order is being made", body: `${o.storeName} started making ${o.title} (${o.number}).` });
      break;
    case "shipped":
      await note(`Order ${o.number} is on the way`, "Order · Shipped", "info", [o.buyerId]);
      await toBuyer({ type: "shipping", title: "Your order is on the way", body: `${o.storeName} sent ${o.number}. Confirm when you receive it.` });
      break;
    case "delivered":
      await note(`${o.storeName} marked order ${o.number} as delivered`, "Order · Delivered", "info", [o.buyerId]);
      await toBuyer({ type: "shipping", title: "Order delivered", body: `${o.storeName} marked ${o.number} as delivered. Confirm that you received it.` });
      break;
    case "completed":
      await note(`${o.buyerName} received order ${o.number}`, "Order · Completed", "success", [o.sellerId]);
      await toSeller({ type: "order", title: "Order completed", body: `${o.buyerName} confirmed they received ${o.number}.` });
      break;
    case "cancelled":
      if (by === null) {
        // Cancelled by the reservation timer (release_expired_reservations).
        await note(`Order ${o.number} was cancelled: no payment before the reservation ended`, "Order · Cancelled", "error", []);
        const body = `${o.number} was cancelled because the payment proof did not arrive in time.`;
        await toBuyer({ type: "order", title: "Reservation expired", body });
        await toSeller({ type: "order", title: "Reservation expired", body });
      } else {
        const byBuyer = by === o.buyerId;
        const other = byBuyer ? o.sellerId : o.buyerId;
        await note(`Order ${o.number} was cancelled by the ${byBuyer ? "buyer" : "seller"}`, "Order · Cancelled", "error", [other]);
        await notify(other, {
          type: "order",
          title: "Order cancelled",
          body: `${o.number} was cancelled by ${byBuyer ? o.buyerName : o.storeName}.`,
          refType: "order",
          refId: o.number,
        });
      }
      break;
  }
}

async function onPayment(e: DbEvent) {
  const p = e.record;
  const before = e.old_record?.status;
  const o = await orderInfo(String(p.order_id));
  const extra = { orderId: o.orderId, orderNumber: o.number };

  if (e.type === "INSERT") {
    await postToChat(o, {
      message: system(`Payment proof sent for ${o.number} · ${peso(p.amount_paid)} · ref ${p.reference_number}`),
      preview: "Payment sent",
      tag: { label: "Payment sent", tone: "info" },
      extra,
      unreadFor: [o.sellerId],
    });
    await notify(o.sellerId, {
      type: "payment",
      title: "Payment proof received",
      body: `${o.buyerName} sent ${peso(p.amount_paid)} for ${o.number} (ref ${p.reference_number}). Check and confirm it.`,
      refType: "order",
      refId: o.number,
    });
    return;
  }
  if (before === "submitted" && p.status === "verified") {
    await postToChat(o, {
      message: system(`${o.storeName} confirmed the payment for ${o.number}`),
      preview: "Payment confirmed",
      tag: { label: "Order · Confirmed", tone: "success" },
      extra,
      unreadFor: [o.buyerId],
    });
    await notify(o.buyerId, {
      type: "payment",
      title: "Payment confirmed",
      body: `${o.storeName} confirmed your payment for ${o.number}. Your order is confirmed.`,
      refType: "order",
      refId: o.number,
    });
    return;
  }
  if (before === "submitted" && p.status === "rejected") {
    // review_payment saves the reason as an order history note.
    const { data } = await admin()
      .from("order_status_history")
      .select("note, changed_at")
      .eq("order_id", o.orderId)
      .like("note", "Payment proof rejected:%")
      .order("changed_at", { ascending: false })
      .limit(1);
    const rows = (data ?? []) as Json[];
    const reason = String(rows[0]?.note ?? "").replace(/^Payment proof rejected:\s*/, "");
    await postToChat(o, {
      message: system(`${o.storeName} could not confirm the payment for ${o.number}${reason ? `: ${reason}` : ""}`),
      preview: "Payment rejected",
      tag: { label: "Payment rejected", tone: "error" },
      extra,
      unreadFor: [o.buyerId],
    });
    await notify(o.buyerId, {
      type: "payment",
      title: "Payment rejected",
      body: `${o.storeName} could not confirm your payment for ${o.number}${reason ? `: ${clip(reason, 100)}` : ""}. Upload a new proof.`,
      refType: "order",
      refId: o.number,
    });
  }
}

async function onReview(e: DbEvent) {
  const r = e.record;
  const o = await orderInfo(String(r.order_id));
  const stars = "★".repeat(Number(r.rating)) + "☆".repeat(5 - Number(r.rating));
  const comment = String(r.comment ?? "").trim();
  await notify(o.sellerId, {
    type: "review",
    title: "New review",
    body: `${o.buyerName} rated ${o.title} ${stars}${comment ? `: "${clip(comment, 100)}"` : ""}`,
    refType: "order",
    refId: o.number,
  });
}

async function handleDbEvent(req: Request, body: Json): Promise<Response> {
  if (req.headers.get("x-crafthive-secret") !== env("DB_EVENTS_SECRET")) throw new HttpError(401, "Wrong secret.");
  const e = body as unknown as DbEvent;
  switch (e.table) {
    case "custom_request":
      await onCustomRequest(e);
      break;
    case "quote":
      await onQuote(e);
      break;
    case "order_status_history":
      await onOrderHistory(e);
      break;
    case "payment":
      await onPayment(e);
      break;
    case "review":
      await onReview(e);
      break;
    case "__firebase_check": {
      // Setup check: signs in to Google with the service account and reads one
      // document. Returns only the project ID, never any key data.
      await accessToken();
      await getDoc("users/__setup_check");
      return json({ ok: true, firebaseProject: serviceAccount().project_id });
    }
    default:
      return json({ ok: true, skipped: e.table });
  }
  return json({ ok: true });
}

// -----------------------------------------------------------------------------
// App calls (signed-in user)
// -----------------------------------------------------------------------------
async function caller(req: Request): Promise<string> {
  const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!jwt) throw new HttpError(401, "Please log in again.");
  const { data, error } = await admin().auth.getUser(jwt);
  if (error || !data.user) throw new HttpError(401, "Please log in again.");
  return data.user.id;
}

async function handleToken(req: Request): Promise<Response> {
  const uid = await caller(req);
  return json({ token: await customToken(uid) });
}

/** Push for a chat message the caller just sent (chat messages are not added to the notification list). */
async function handleChatPush(req: Request, body: Json): Promise<Response> {
  const uid = await caller(req);
  const chatId = String(body.chatId ?? "");
  const messageId = String(body.messageId ?? "");
  if (!/^[A-Za-z0-9_-]{1,200}$/.test(chatId) || !/^[A-Za-z0-9]{1,100}$/.test(messageId)) throw new HttpError(400, "Bad chat or message ID.");
  const [chat, message] = await Promise.all([getDoc(`chats/${chatId}`), getDoc(`chats/${chatId}/messages/${messageId}`)]);
  if (!chat || !message) throw new HttpError(404, "Message not found.");
  const participants = (chat.participantUids as string[]) ?? [];
  if (message.senderUid !== uid || !participants.includes(uid)) throw new HttpError(403, "Not your message.");
  const to = participants.find((p) => p !== uid);
  if (!to) return json({ sent: 0 });
  const fromName = uid === chat.buyerUid ? String(chat.buyerName ?? "A buyer") : String(chat.storeName ?? "A maker");
  const sent = await sendPush(to, {
    title: fromName,
    body: message.type === "photo" ? "📷 Sent a photo" : clip(String(message.text ?? ""), 140),
    route: `/chat/${chatId}`,
    type: "message",
    tag: chatId,
  });
  return json({ sent });
}

// -----------------------------------------------------------------------------
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "Use POST." }, 405);
  try {
    const body = (await req.json().catch(() => ({}))) as Json;
    switch (body.action) {
      case "token":
        return await handleToken(req);
      case "chat_push":
        return await handleChatPush(req, body);
      case "db_event":
        return await handleDbEvent(req, body);
      default:
        return json({ error: "Unknown action." }, 400);
    }
  } catch (e) {
    const status = e instanceof HttpError ? e.status : 500;
    console.error(e);
    return json({ error: e instanceof Error ? e.message : String(e) }, status);
  }
});
