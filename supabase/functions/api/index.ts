// =============================================================================
// CraftHive REST API v1 (Supabase Edge Function "api")
//
// One function that gives the app resource-based endpoints, as designed in the
// ITCC 14 API Design Document (section 3.2):
//
//   /api/v1/categories                         GET
//   /api/v1/stores                             GET POST      /stores/{storeId}  GET PATCH
//   /api/v1/stores/{storeId}/products          GET
//   /api/v1/products                           GET POST      /products/{productId}  GET PUT PATCH DELETE
//   /api/v1/products/{productId}/reviews       GET
//   /api/v1/orders                             GET POST      /orders/{orderId}  GET PATCH
//   /api/v1/orders/{orderId}/history           GET
//   /api/v1/orders/{orderId}/payments          GET POST      /payments/{paymentId}  PATCH
//   /api/v1/orders/{orderId}/receipt-scans     POST
//   /api/v1/orders/{orderId}/reviews           POST
//   /api/v1/custom-requests                    GET POST      /custom-requests/{requestId}  GET PATCH
//   /api/v1/custom-requests/{requestId}/images POST
//   /api/v1/custom-requests/{requestId}/quotes GET POST      /quotes/{quoteId}  PATCH
//   /api/v1/reviews/{reviewId}                 PATCH DELETE
//
// The business rules stay in the database functions (database/04 and 15); this
// function checks the input, calls them with the caller's own login token (so
// row-level security still applies) and turns the result into JSON with proper
// status codes:
//   200 OK · 201 Created (+ Location) · 204 No Content · 400 bad JSON or wrong type
//   401 not logged in · 403 not allowed · 404 not found · 405 wrong method
//   409 clashes with existing data · 413 receipt too large · 422 breaks a rule
//   500 server error · 502 receipt reader down
// Every error has the same shape: { "error": { "code", "message", "field"? } }
//
// Deploy: Supabase → Edge Functions → Deploy a new function → name it "api" →
// paste this file → turn OFF "Enforce JWT verification" (the caller is checked
// below, and GET /categories works without logging in).
// Needs database/15_rest_api.sql to be run first.
// =============================================================================

import { createClient } from "jsr:@supabase/supabase-js@2";

// deno-lint-ignore no-explicit-any
type Json = Record<string, any>;
type Method = "GET" | "POST" | "PUT" | "PATCH" | "DELETE";

const BASE = "/api/v1";
const ENV = (name: string): string => (globalThis as Json).Deno?.env.get(name) ?? "";
const SUPABASE_URL = () => ENV("SUPABASE_URL");

const CORS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, PUT, PATCH, DELETE, OPTIONS",
  "Access-Control-Expose-Headers": "Location",
};

// -----------------------------------------------------------------------------
// Errors and responses
// -----------------------------------------------------------------------------
export class ApiError extends Error {
  constructor(public status: number, public code: string, message: string, public field?: string) {
    super(message);
  }
}

function send(status: number, body?: unknown, headers: Record<string, string> = {}): Response {
  if (status === 204) return new Response(null, { status, headers: { ...CORS, ...headers } });
  return new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json", ...headers } });
}
const ok = (body: unknown) => send(200, body);
const created = (path: string, body: unknown) => send(201, body, { Location: BASE + path });
const noContent = () => send(204);

function errorResponse(e: ApiError, extra: Record<string, string> = {}): Response {
  const error: Json = { code: e.code, message: e.message };
  if (e.field) error.field = e.field;
  return send(e.status, { error }, extra);
}

const CODE_FOR_STATUS: Record<number, string> = {
  400: "BAD_REQUEST", 401: "UNAUTHORIZED", 403: "FORBIDDEN", 404: "NOT_FOUND",
  409: "CONFLICT", 413: "PAYLOAD_TOO_LARGE", 422: "RULE_VIOLATION", 502: "BAD_GATEWAY",
};

/** A more specific code for messages the app may want to react to. */
function codeForMessage(status: number, message: string): string {
  const m = message.toLowerCase();
  if (m.includes("reference number was already used")) return "DUPLICATE_REFERENCE";
  if (m.includes("screenshot was already uploaded")) return "DUPLICATE_RECEIPT";
  if (m.includes("already sent a payment proof")) return "PROOF_ALREADY_SENT";
  if (m.includes("left in stock")) return "OUT_OF_STOCK";
  if (m.includes("fully booked")) return "FULLY_BOOKED";
  if (m.includes("quote is no longer open")) return "QUOTE_CLOSED";
  if (m.includes("cannot change this order to") || m.includes("an order cannot go from")) return "INVALID_STATUS_CHANGE";
  return CODE_FOR_STATUS[status] ?? "ERROR";
}

/** Which request field a database message is about, so the app can highlight it. */
function fieldForMessage(message: string): string | undefined {
  const m = message.toLowerCase();
  if (m.includes("reference number")) return "referenceNumber";
  if (m.includes("receipt screenshot")) return "proofImageHash";
  if (m.includes("quantity") || m.includes("left in stock")) return "quantity";
  if (m.includes("amount you paid")) return "amountPaid";
  if (m.includes("price")) return "price";
  if (m.includes("ready date") || m.includes("fully booked")) return "readyBy";
  if (m.includes("describe your request")) return "description";
  if (m.includes("budget")) return "budget";
  if (m.includes("date after today")) return "neededBy";
  if (m.includes("tell the buyer why")) return "reason";
  if (m.includes("photos")) return "imagePaths";
  return undefined;
}

/**
 * Database error → API error. database/15_rest_api.sql gives each rule its own
 * SQLSTATE 'PTxyz' (xyz = the HTTP status); the rest are standard PostgreSQL codes.
 */
export function dbError(e: { code?: string; message?: string; details?: string | null }): ApiError {
  const code = e.code ?? "";
  const message = e.message ?? "Something went wrong.";
  if (/^PT\d{3}$/.test(code)) {
    const status = Number(code.slice(2));
    return new ApiError(status, codeForMessage(status, message), message, fieldForMessage(message));
  }
  switch (code) {
    case "23505": { // unique_violation
      const all = `${message} ${e.details ?? ""}`;
      if (all.includes("reference_number")) return new ApiError(409, "DUPLICATE_REFERENCE", "This reference number was already used for another payment.", "referenceNumber");
      if (all.includes("proof_image_hash")) return new ApiError(409, "DUPLICATE_RECEIPT", "This receipt screenshot was already uploaded before.", "proofImageHash");
      if (all.includes("review")) return new ApiError(409, "ALREADY_REVIEWED", "You already reviewed this item.");
      if (all.includes("store_seller_id")) return new ApiError(409, "STORE_EXISTS", "You already have a store.");
      return new ApiError(409, "DUPLICATE", "This was already saved.");
    }
    case "23514": // check_violation
      return new ApiError(422, "RULE_VIOLATION", "A value is outside the allowed range.");
    case "23503": // foreign_key_violation
      return message.includes("still referenced")
        ? new ApiError(409, "IN_USE", "This is still used by other records.")
        : new ApiError(422, "RULE_VIOLATION", "The request refers to something that does not exist.");
    case "22P02": case "22007": case "22008": case "22003":
      return new ApiError(400, "BAD_REQUEST", "A value has the wrong format.");
    case "42501":
      return new ApiError(403, "FORBIDDEN", "You are not allowed to do this.");
    case "PGRST116":
      return new ApiError(404, "NOT_FOUND", "Not found.");
    case "P0001": // functions not converted to PT codes yet
      return new ApiError(422, "RULE_VIOLATION", message, fieldForMessage(message));
  }
  console.error("Unexpected database error:", JSON.stringify(e));
  return new ApiError(500, "INTERNAL_ERROR", "Something went wrong on the server. Please try again.");
}

// -----------------------------------------------------------------------------
// Request context: path parameters, query string, body, logged-in user
// -----------------------------------------------------------------------------
type ClientFactory = (url: string, key: string, token: string | null) => Json;
let clientFactory: ClientFactory = (url, key, token) =>
  createClient(url, key, {
    global: { headers: token ? { Authorization: `Bearer ${token}` } : {} },
    auth: { persistSession: false, autoRefreshToken: false },
  }) as unknown as Json;
/** For tests: replace the Supabase client. */
export function setClientFactory(f: ClientFactory) {
  clientFactory = f;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export class Ctx {
  readonly token: string | null;
  private _db: Json | null = null;
  private _uid: string | null = null;
  private _body: Json | null = null;

  constructor(readonly req: Request, readonly url: URL, readonly params: Record<string, string>) {
    const auth = req.headers.get("Authorization") ?? "";
    const token = auth.replace(/^Bearer\s+/i, "").trim();
    const anon = ENV("SUPABASE_ANON_KEY") || (req.headers.get("apikey") ?? "");
    // The anon key alone is not a login.
    this.token = token && token !== anon ? token : null;
  }

  /** Supabase client that acts as the caller (their token, so RLS applies). */
  get db(): Json {
    if (!this._db) {
      const key = ENV("SUPABASE_ANON_KEY") || (this.req.headers.get("apikey") ?? "");
      this._db = clientFactory(SUPABASE_URL(), key, this.token);
    }
    return this._db;
  }

  /** The logged-in user's id, or 401. */
  async userId(): Promise<string> {
    if (this._uid) return this._uid;
    if (!this.token) throw new ApiError(401, "UNAUTHORIZED", "Please log in again.");
    const { data, error } = await this.db.auth.getUser(this.token);
    if (error || !data?.user) throw new ApiError(401, "UNAUTHORIZED", "Please log in again.");
    this._uid = data.user.id as string;
    return this._uid;
  }

  /** A path parameter that must be a UUID (400 otherwise). */
  id(name: string): string {
    const v = this.params[name];
    if (!UUID.test(v)) throw new ApiError(400, "BAD_REQUEST", `${name} must be a UUID.`, name);
    return v.toLowerCase();
  }

  query(name: string): string | null {
    const v = this.url.searchParams.get(name);
    return v === null || v.trim() === "" ? null : v.trim();
  }

  async body(): Promise<Json> {
    if (this._body) return this._body;
    let parsed: unknown;
    try {
      const text = await this.req.text();
      parsed = text.trim() === "" ? {} : JSON.parse(text);
    } catch {
      throw new ApiError(400, "BAD_REQUEST", "The request body must be valid JSON.");
    }
    if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) {
      throw new ApiError(400, "BAD_REQUEST", "The request body must be a JSON object.");
    }
    this._body = parsed as Json;
    return this._body;
  }

  /** Reads the body and rejects fields the endpoint does not know. */
  async input(allowed: string[]): Promise<Input> {
    return new Input(await this.body(), allowed);
  }
}

// -----------------------------------------------------------------------------
// Input validation: wrong type → 400, missing or out of range → 422
// -----------------------------------------------------------------------------
type Rule = { required?: boolean; min?: number; max?: number };

export class Input {
  constructor(readonly raw: Json, allowed: string[]) {
    for (const k of Object.keys(raw)) {
      if (!allowed.includes(k)) throw new ApiError(400, "UNKNOWN_FIELD", `Unknown field "${k}". Allowed: ${allowed.join(", ")}.`, k);
    }
  }

  has(k: string): boolean {
    return this.raw[k] !== undefined;
  }

  private missing(k: string, r: Rule): undefined {
    if (r.required) throw new ApiError(422, "VALIDATION_FAILED", `${k} is required.`, k);
    return undefined;
  }

  str(k: string, r: Rule = {}): string | undefined {
    const v = this.raw[k];
    if (v === undefined || v === null) return this.missing(k, r);
    if (typeof v !== "string") throw new ApiError(400, "BAD_REQUEST", `${k} must be text.`, k);
    const t = v.trim();
    if (t === "" ) return this.missing(k, r) ?? (r.required ? undefined : "");
    if (r.min !== undefined && t.length < r.min) throw new ApiError(422, "VALIDATION_FAILED", `${k} must be at least ${r.min} characters.`, k);
    if (r.max !== undefined && t.length > r.max) throw new ApiError(422, "VALIDATION_FAILED", `${k} must be at most ${r.max} characters.`, k);
    return t;
  }

  num(k: string, r: Rule = {}): number | undefined {
    const v = this.raw[k];
    if (v === undefined || v === null) return this.missing(k, r);
    if (typeof v !== "number" || !Number.isFinite(v)) throw new ApiError(400, "BAD_REQUEST", `${k} must be a number.`, k);
    if (r.min !== undefined && v < r.min) throw new ApiError(422, "VALIDATION_FAILED", `${k} must be at least ${r.min}.`, k);
    if (r.max !== undefined && v > r.max) throw new ApiError(422, "VALIDATION_FAILED", `${k} must be at most ${r.max}.`, k);
    return v;
  }

  int(k: string, r: Rule = {}): number | undefined {
    const v = this.raw[k];
    if (v !== undefined && v !== null && (typeof v !== "number" || !Number.isInteger(v))) {
      throw new ApiError(400, "BAD_REQUEST", `${k} must be a whole number.`, k);
    }
    return this.num(k, r);
  }

  bool(k: string, r: Rule = {}): boolean | undefined {
    const v = this.raw[k];
    if (v === undefined || v === null) return this.missing(k, r);
    if (typeof v !== "boolean") throw new ApiError(400, "BAD_REQUEST", `${k} must be true or false.`, k);
    return v;
  }

  uuid(k: string, r: Rule = {}): string | undefined {
    const v = this.str(k, r);
    if (v === undefined || v === "") return v === "" ? this.missing(k, r) : v;
    if (!UUID.test(v)) throw new ApiError(400, "BAD_REQUEST", `${k} must be a UUID.`, k);
    return v.toLowerCase();
  }

  /** A calendar date written as YYYY-MM-DD. */
  date(k: string, r: Rule = {}): string | undefined {
    const v = this.str(k, r);
    if (v === undefined || v === "") return v === "" ? this.missing(k, r) : v;
    if (!/^\d{4}-\d{2}-\d{2}$/.test(v) || Number.isNaN(Date.parse(v))) {
      throw new ApiError(400, "BAD_REQUEST", `${k} must be a date like 2026-12-18.`, k);
    }
    return v;
  }

  oneOf<T extends string>(k: string, values: readonly T[], r: Rule = {}): T | undefined {
    const v = this.str(k, r);
    if (v === undefined || v === "") return v === "" ? this.missing(k, r) : undefined;
    if (!values.includes(v as T)) throw new ApiError(422, "VALIDATION_FAILED", `${k} must be one of: ${values.join(", ")}.`, k);
    return v as T;
  }

  strList(k: string, r: Rule & { itemMax?: number } = {}): string[] | undefined {
    const v = this.raw[k];
    if (v === undefined || v === null) return this.missing(k, r);
    if (!Array.isArray(v) || v.some((x) => typeof x !== "string")) throw new ApiError(400, "BAD_REQUEST", `${k} must be a list of text.`, k);
    const items = (v as string[]).map((x) => x.trim()).filter((x) => x !== "");
    if (r.max !== undefined && items.length > r.max) throw new ApiError(422, "VALIDATION_FAILED", `${k} can have at most ${r.max} items.`, k);
    if (r.itemMax !== undefined && items.some((x) => x.length > r.itemMax!)) {
      throw new ApiError(422, "VALIDATION_FAILED", `Each item in ${k} must be at most ${r.itemMax} characters.`, k);
    }
    return items;
  }
}

// -----------------------------------------------------------------------------
// Small helpers
// -----------------------------------------------------------------------------
/** Runs a Supabase query and throws the mapped error if it failed. */
async function q<T = Json>(p: PromiseLike<{ data: unknown; error: Json | null }>): Promise<T> {
  const { data, error } = await p;
  if (error) throw dbError(error);
  return data as T;
}

async function rpc<T = unknown>(c: Ctx, fn: string, args: Json = {}): Promise<T> {
  return q<T>(c.db.rpc(fn, args));
}

const camelKey = (k: string) => k.replace(/_([a-z0-9])/g, (_, ch: string) => ch.toUpperCase());
/** snake_case keys from the database → camelCase keys in the API. */
export function camel(v: unknown): unknown {
  if (Array.isArray(v)) return v.map(camel);
  if (v && typeof v === "object") {
    return Object.fromEntries(Object.entries(v as Json).map(([k, x]) => [camelKey(k), camel(x)]));
  }
  return v;
}

const num = (v: unknown): number | null => (v === null || v === undefined ? null : Number(v));
type Link = { href: string; method?: Method; body?: Json };
const link = (path: string, method?: Method, body?: Json): Link => {
  const l: Link = { href: BASE + path };
  if (method) l.method = method;
  if (body) l.body = body;
  return l;
};

function publicUrl(bucket: string, path: string | null | undefined): string | null {
  if (!path) return null;
  if (path.startsWith("http")) return path;
  return `${SUPABASE_URL()}/storage/v1/object/public/${bucket}/${path.split("/").map(encodeURIComponent).join("/")}`;
}

// -----------------------------------------------------------------------------
// Representations (what each resource looks like in JSON)
// -----------------------------------------------------------------------------
export function categoryOut(r: Json) {
  return {
    categoryId: r.category_id,
    name: r.category_name,
    description: r.description ?? null,
    _links: { self: link(`/categories/${r.category_id}`), products: link(`/products?category=${r.category_id}`) },
  };
}

export function storeOut(r: Json, me: string | null) {
  return {
    storeId: r.store_id,
    sellerId: r.seller_id,
    name: r.store_name,
    description: r.store_description ?? null,
    city: r.city ?? null,
    rating: num(r.rating) ?? 0,
    itemsSold: num(r.items_sold_count) ?? 0,
    verificationStatus: r.verification_status ?? "unverified",
    isVerified: r.verification_status === "verified",
    avatarPath: r.avatar_path ?? null,
    avatarUrl: publicUrl("avatars", r.avatar_path),
    latitude: num(r.latitude),
    longitude: num(r.longitude),
    isArchived: r.is_archived === true,
    isMine: me !== null && r.seller_id === me,
    _links: { self: link(`/stores/${r.store_id}`), products: link(`/stores/${r.store_id}/products`) },
  };
}

const listingStatus = (r: Json) => (r.is_archived ? "archived" : r.is_draft ? "draft" : "active");

export function productOut(r: Json) {
  const paths = ((r.image_paths as string[] | null) ?? []).filter(Boolean);
  const status = listingStatus(r);
  const links: Json = {
    self: link(`/products/${r.product_id}`),
    store: link(`/stores/${r.store_id}`),
    reviews: link(`/products/${r.product_id}/reviews`),
  };
  if (status === "active") {
    links.order = link("/orders", "POST", { productId: r.product_id, quantity: 1 });
    if (r.has_custom_option) links.customRequest = link("/custom-requests", "POST", { productId: r.product_id });
  }
  return {
    productId: r.product_id,
    storeId: r.store_id,
    categoryId: r.category_id,
    title: r.title,
    description: r.description ?? null,
    price: num(r.price),
    stockQuantity: num(r.stock_quantity) ?? 0,
    leadTimeDays: num(r.lead_time_days) ?? 0,
    acceptsCustomOrders: r.has_custom_option === true,
    status,
    createdAt: r.created_at ?? null,
    rating: num(r.rating) ?? 0,
    reviewCount: num(r.review_count) ?? 0,
    soldCount: num(r.sold_count) ?? 0,
    imagePaths: paths,
    imageUrls: paths.map((p) => publicUrl("product-images", p)),
    customOptions: (r.custom_options as string[] | null) ?? [],
    _links: links,
  };
}

/**
 * An order from my_orders(), with links to what the caller can do next
 * (Richardson level 3): the buttons the app shows come from these links.
 */
export function orderOut(raw: Json) {
  const o = camel(raw) as Json;
  o.totalAmount = num(o.totalAmount);
  o.currency = "PHP";
  o.items = o.productId ? [{ productId: o.productId, title: o.productTitle, quantity: o.quantity }] : [];
  if (o.payment) o.payment.amountPaid = num(o.payment.amountPaid);
  const id = o.orderId as string;
  const buying = o.side === "buying";
  const pay = o.payment as Json | null;
  const links: Json = {
    self: link(`/orders/${id}`),
    history: link(`/orders/${id}/history`),
    payments: link(`/orders/${id}/payments`),
  };
  const status = o.status as string;
  if (status === "pending") {
    if (buying && (!pay || pay.status === "rejected")) {
      links.pay = link(`/orders/${id}/payments`, "POST");
      links.scanReceipt = link(`/orders/${id}/receipt-scans`, "POST");
    }
    if (!pay || pay.status !== "verified") links.cancel = link(`/orders/${id}`, "PATCH", { status: "cancelled" });
    if (!buying && pay?.status === "submitted") {
      links.verifyPayment = link(`/orders/${id}/payments/${pay.paymentId}`, "PATCH", { status: "verified" });
      links.rejectPayment = link(`/orders/${id}/payments/${pay.paymentId}`, "PATCH", { status: "rejected", reason: "" });
    }
  }
  if (!buying && status === "confirmed") links.startProduction = link(`/orders/${id}`, "PATCH", { status: "in_production" });
  if (!buying && (status === "confirmed" || status === "in_production")) links.ship = link(`/orders/${id}`, "PATCH", { status: "shipped" });
  if (!buying && status === "shipped") links.markDelivered = link(`/orders/${id}`, "PATCH", { status: "delivered" });
  if (buying && (status === "shipped" || status === "delivered")) links.confirmReceipt = link(`/orders/${id}`, "PATCH", { status: "completed" });
  if (buying && (status === "delivered" || status === "completed") && !o.reviewed) {
    links.review = link(`/orders/${id}/reviews`, "POST", { productId: o.productId, rating: 5 });
  }
  o._links = links;
  return o;
}

export function customRequestOut(raw: Json) {
  const r = camel(raw) as Json;
  r.budget = num(r.budget);
  for (const quote of (r.quotes as Json[]) ?? []) quote.offeredPrice = num(quote.offeredPrice);
  const id = r.requestId as string;
  const buying = r.side === "buying";
  const open = r.status === "pending" || r.status === "quoted";
  const links: Json = { self: link(`/custom-requests/${id}`), quotes: link(`/custom-requests/${id}/quotes`) };
  if (open && buying) links.cancel = link(`/custom-requests/${id}`, "PATCH", { status: "cancelled" });
  if (open && !buying) {
    links.sendQuote = link(`/custom-requests/${id}/quotes`, "POST");
    links.decline = link(`/custom-requests/${id}`, "PATCH", { status: "declined", reason: "" });
  }
  const latest = ((r.quotes as Json[]) ?? []).at(-1);
  if (buying && r.status === "quoted" && latest?.status === "sent") {
    links.acceptQuote = link(`/custom-requests/${id}/quotes/${latest.quoteId}`, "PATCH", { status: "accepted" });
    links.requestChanges = link(`/custom-requests/${id}/quotes/${latest.quoteId}`, "PATCH", { status: "changes_requested", note: "" });
  }
  if (buying && open) links.addImage = link(`/custom-requests/${id}/images`, "POST");
  r._links = links;
  return r;
}

export function paymentOut(p: Json) {
  return {
    paymentId: p.payment_id,
    orderId: p.order_id,
    referenceNumber: p.reference_number,
    amountPaid: num(p.amount_paid),
    status: p.status,
    proofImagePath: p.proof_image_path,
    verifiedAt: p.verified_at ?? null,
    _links: { self: link(`/orders/${p.order_id}/payments/${p.payment_id}`), order: link(`/orders/${p.order_id}`) },
  };
}

export function quoteOut(row: Json) {
  const x = camel(row) as Json;
  x.offeredPrice = num(x.offeredPrice);
  x._links = {
    self: link(`/custom-requests/${row.request_id}/quotes/${row.quote_id}`),
    request: link(`/custom-requests/${row.request_id}`),
  };
  return x;
}

export function reviewOut(row: Json) {
  const x = camel(row) as Json;
  x._links = { self: link(`/reviews/${row.review_id}`), product: link(`/products/${row.product_id}`), order: link(`/orders/${row.order_id}`) };
  return x;
}

// -----------------------------------------------------------------------------
// Router
// -----------------------------------------------------------------------------
type Handler = (c: Ctx) => Promise<Response>;
type Route = { method: Method; pattern: string; re: RegExp; keys: string[]; handler: Handler };
const routes: Route[] = [];

function route(method: Method, pattern: string, handler: Handler) {
  const keys: string[] = [];
  const re = new RegExp("^" + pattern.replace(/:(\w+)/g, (_, k: string) => {
    keys.push(k);
    return "([^/]+)";
  }) + "/?$");
  routes.push({ method, pattern, re, keys, handler });
}

/** Entry point, also used by the tests. */
export async function handle(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });
  try {
    const url = new URL(req.url);
    // Supabase passes /api/v1/... (or /functions/v1/api/v1/... when called locally).
    const at = url.pathname.indexOf(BASE);
    if (at < 0) throw new ApiError(404, "NOT_FOUND", `Endpoints start with ${BASE}.`);
    const path = url.pathname.slice(at + BASE.length) || "/";
    const matching = routes.filter((r) => r.re.test(path));
    if (matching.length === 0) throw new ApiError(404, "NOT_FOUND", `No endpoint at ${BASE}${path}.`);
    const r = matching.find((m) => m.method === req.method);
    if (!r) {
      const allow = [...new Set(matching.map((m) => m.method))].join(", ");
      return errorResponse(new ApiError(405, "METHOD_NOT_ALLOWED", `Use ${allow} on ${BASE}${path}.`), { Allow: allow });
    }
    const values = path.match(r.re)!.slice(1).map(decodeURIComponent);
    const params = Object.fromEntries(r.keys.map((k, i) => [k, values[i]]));
    return await r.handler(new Ctx(req, url, params));
  } catch (e) {
    if (e instanceof ApiError) return errorResponse(e);
    console.error(e);
    return errorResponse(new ApiError(500, "INTERNAL_ERROR", "Something went wrong on the server. Please try again."));
  }
}

// -----------------------------------------------------------------------------
// Index: the entry point lists the resources (start here when exploring)
// -----------------------------------------------------------------------------
route("GET", "/", async () =>
  ok({
    name: "CraftHive REST API",
    version: "v1",
    _links: {
      categories: link("/categories"),
      stores: link("/stores"),
      products: link("/products"),
      orders: link("/orders"),
      customRequests: link("/custom-requests"),
    },
  }));

// -----------------------------------------------------------------------------
// Categories (read-only; maintained by administrators). No login needed.
// -----------------------------------------------------------------------------
route("GET", "/categories", async (c) => {
  const rows = await q<Json[]>(c.db.from("category").select("category_id, category_name, description").order("category_name"));
  return ok(rows.map(categoryOut));
});

route("GET", "/categories/:categoryId", async (c) => {
  const row = await q<Json | null>(
    c.db.from("category").select("category_id, category_name, description").eq("category_id", c.id("categoryId")).maybeSingle(),
  );
  if (!row) throw new ApiError(404, "NOT_FOUND", "Category not found.");
  return ok(categoryOut(row));
});

// -----------------------------------------------------------------------------
// Stores
// -----------------------------------------------------------------------------
async function storeCard(c: Ctx, storeId: string): Promise<Json> {
  const row = await q<Json | null>(c.db.from("store_card").select("*").eq("store_id", storeId).maybeSingle());
  if (!row) throw new ApiError(404, "NOT_FOUND", "Store not found.");
  return row;
}

/** The store, checked to belong to the caller: 404 if missing, 403 if someone else's. */
async function ownStore(c: Ctx, storeId: string): Promise<Json> {
  const me = await c.userId();
  const row = await q<Json | null>(c.db.from("store").select("store_id, seller_id").eq("store_id", storeId).maybeSingle());
  if (!row) throw new ApiError(404, "NOT_FOUND", "Store not found.");
  if (row.seller_id !== me) throw new ApiError(403, "FORBIDDEN", "Only the store owner can change this store.");
  return row;
}

route("GET", "/stores", async (c) => {
  const me = await c.userId();
  let query = c.db.from("store_card").select("*").or(`is_archived.eq.false,seller_id.eq.${me}`).order("store_name");
  const city = c.query("city");
  if (city) query = query.ilike("city", `%${city.replace(/[%_,()]/g, "")}%`);
  const rows = await q<Json[]>(query);
  return ok(rows.map((r) => storeOut(r, me)));
});

route("GET", "/stores/:storeId", async (c) => {
  const me = await c.userId();
  return ok(storeOut(await storeCard(c, c.id("storeId")), me));
});

const STORE_FIELDS: Record<string, string> = {
  name: "store_name", description: "store_description", address: "address", city: "city",
  postalCode: "postal_code", weeklyCapacity: "weekly_capacity", latitude: "latitude", longitude: "longitude",
};

function storeRow(i: Input, full: boolean): Json {
  const row: Json = {};
  const put = (k: string, v: unknown) => {
    if (v !== undefined) row[STORE_FIELDS[k]] = v === "" ? null : v;
  };
  put("name", i.str("name", { required: full, min: 2, max: 100 }));
  put("description", i.str("description", { max: 500 }));
  put("address", i.str("address", { required: full, min: 3, max: 255 }));
  put("city", i.str("city", { required: full, min: 2, max: 100 }));
  const postal = i.str("postalCode", { required: full });
  if (postal !== undefined && !/^\d{4}$/.test(postal)) throw new ApiError(422, "VALIDATION_FAILED", "postalCode must be 4 digits.", "postalCode");
  put("postalCode", postal);
  put("weeklyCapacity", i.int("weeklyCapacity", { required: full, min: 1, max: 500 }));
  put("latitude", i.num("latitude", { min: -90, max: 90 }));
  put("longitude", i.num("longitude", { min: -180, max: 180 }));
  return row;
}

route("POST", "/stores", async (c) => {
  const me = await c.userId();
  const row = storeRow(await c.input(Object.keys(STORE_FIELDS)), true);
  const existing = await q<Json | null>(c.db.from("store").select("store_id").eq("seller_id", me).maybeSingle());
  if (existing) throw new ApiError(409, "STORE_EXISTS", "You already have a store.");
  // Opening a store makes the user a seller (unverified until a Verified Maker review).
  const seller = await q<Json | null>(c.db.from("seller").select("user_id").eq("user_id", me).maybeSingle());
  if (!seller) await q(c.db.from("seller").insert({ user_id: me }));
  const saved = await q<Json>(c.db.from("store").insert({ ...row, seller_id: me }).select("store_id").single());
  return created(`/stores/${saved.store_id}`, storeOut(await storeCard(c, saved.store_id), me));
});

route("PATCH", "/stores/:storeId", async (c) => {
  const storeId = c.id("storeId");
  const me = await c.userId();
  const row = storeRow(await c.input(Object.keys(STORE_FIELDS)), false);
  await ownStore(c, storeId);
  if (Object.keys(row).length === 0) throw new ApiError(422, "VALIDATION_FAILED", "Send at least one field to change.");
  await q(c.db.from("store").update(row).eq("store_id", storeId));
  return ok(storeOut(await storeCard(c, storeId), me));
});

route("GET", "/stores/:storeId/products", async (c) => {
  const storeId = c.id("storeId");
  const me = await c.userId();
  const store = await storeCard(c, storeId);
  let query = c.db.from("product_card").select("*").eq("store_id", storeId).order("created_at", { ascending: false });
  // Owners also see their drafts and archived listings.
  if (store.seller_id !== me) query = query.eq("is_draft", false).eq("is_archived", false);
  const rows = await q<Json[]>(query);
  return ok(rows.map(productOut));
});

// -----------------------------------------------------------------------------
// Products (listings)
// -----------------------------------------------------------------------------
async function productCard(c: Ctx, productId: string): Promise<Json> {
  const row = await q<Json | null>(c.db.from("product_card").select("*").eq("product_id", productId).maybeSingle());
  if (!row) throw new ApiError(404, "NOT_FOUND", "Product not found.");
  return row;
}

/** The listing, checked to belong to the caller's store. */
async function ownProduct(c: Ctx, productId: string): Promise<Json> {
  const me = await c.userId();
  const row = await q<Json | null>(c.db.from("product").select("product_id, store_id, is_draft").eq("product_id", productId).maybeSingle());
  if (!row) throw new ApiError(404, "NOT_FOUND", "Product not found.");
  const store = await q<Json | null>(c.db.from("store").select("seller_id").eq("store_id", row.store_id).maybeSingle());
  if (store?.seller_id !== me) throw new ApiError(403, "FORBIDDEN", "Only the seller can change this listing.");
  return row;
}

const LISTING_FIELDS = [
  "categoryId", "title", "description", "price", "stockQuantity", "leadTimeDays",
  "acceptsCustomOrders", "status", "imagePaths", "customOptions",
];

/** The listing JSON passed to save_listing() (database/15_rest_api.sql). */
function listingInput(i: Input): Json {
  return {
    categoryId: i.uuid("categoryId", { required: true }),
    title: i.str("title", { required: true, min: 3, max: 100 }),
    description: i.str("description", { max: 1000 }) ?? null,
    price: i.num("price", { required: true, min: 0.01, max: 1_000_000 }),
    stockQuantity: i.int("stockQuantity", { required: true, min: 0, max: 100_000 }),
    leadTimeDays: i.int("leadTimeDays", { required: true, min: 1, max: 365 }),
    acceptsCustomOrders: i.bool("acceptsCustomOrders") ?? false,
    status: i.oneOf("status", ["draft", "active", "archived"] as const) ?? "active",
    imagePaths: i.strList("imagePaths", { max: 5, itemMax: 255 }) ?? [],
    customOptions: i.strList("customOptions", { max: 20, itemMax: 50 }) ?? [],
  };
}

route("GET", "/products", async (c) => {
  await c.userId();
  let query = c.db.from("product_card").select("*").eq("is_draft", false).eq("is_archived", false);
  const category = c.query("category");
  if (category) {
    if (!UUID.test(category)) throw new ApiError(400, "BAD_REQUEST", "category must be a UUID.", "category");
    query = query.eq("category_id", category);
  }
  const storeId = c.query("storeId");
  if (storeId) {
    if (!UUID.test(storeId)) throw new ApiError(400, "BAD_REQUEST", "storeId must be a UUID.", "storeId");
    query = query.eq("store_id", storeId);
  }
  for (const [name, op] of [["minPrice", "gte"], ["maxPrice", "lte"]] as const) {
    const v = c.query(name);
    if (v === null) continue;
    if (!/^\d+(\.\d+)?$/.test(v)) throw new ApiError(400, "BAD_REQUEST", `${name} must be a number.`, name);
    query = query[op]("price", Number(v));
  }
  const text = c.query("q");
  if (text) query = query.ilike("title", `%${text.replace(/[%_,()]/g, "")}%`);
  const rows = await q<Json[]>(query.order("created_at", { ascending: false }));
  return ok(rows.map(productOut));
});

route("GET", "/products/:productId", async (c) => {
  await c.userId();
  return ok(productOut(await productCard(c, c.id("productId"))));
});

route("POST", "/products", async (c) => {
  await c.userId();
  const listing = listingInput(await c.input(LISTING_FIELDS));
  if (listing.status === "archived") throw new ApiError(422, "VALIDATION_FAILED", "A new listing is draft or active.", "status");
  const productId = await rpc<string>(c, "save_listing", { p_product_id: null, p_listing: listing });
  return created(`/products/${productId}`, productOut(await productCard(c, productId)));
});

route("PUT", "/products/:productId", async (c) => {
  const productId = c.id("productId");
  const listing = listingInput(await c.input(LISTING_FIELDS));
  await ownProduct(c, productId);
  await rpc(c, "save_listing", { p_product_id: productId, p_listing: listing });
  return ok(productOut(await productCard(c, productId)));
});

route("PATCH", "/products/:productId", async (c) => {
  const productId = c.id("productId");
  const i = await c.input(LISTING_FIELDS.filter((f) => f !== "imagePaths" && f !== "customOptions"));
  const row: Json = {};
  const put = (col: string, v: unknown) => {
    if (v !== undefined) row[col] = v;
  };
  put("category_id", i.uuid("categoryId"));
  put("title", i.str("title", { min: 3, max: 100 }));
  if (i.has("description")) row.description = i.str("description", { max: 1000 }) || null;
  put("price", i.num("price", { min: 0.01, max: 1_000_000 }));
  put("stock_quantity", i.int("stockQuantity", { min: 0, max: 100_000 }));
  put("lead_time_days", i.int("leadTimeDays", { min: 1, max: 365 }));
  put("has_custom_option", i.bool("acceptsCustomOrders"));
  const status = i.oneOf("status", ["draft", "active", "archived"] as const);
  if (status) {
    row.is_draft = status === "draft";
    row.is_archived = status === "archived";
  }
  if (Object.keys(row).length === 0) {
    throw new ApiError(422, "VALIDATION_FAILED", "Send at least one field to change. Photos and options are changed with PUT.");
  }
  await ownProduct(c, productId);
  await q(c.db.from("product").update(row).eq("product_id", productId));
  return ok(productOut(await productCard(c, productId)));
});

route("DELETE", "/products/:productId", async (c) => {
  const productId = c.id("productId");
  const p = await ownProduct(c, productId);
  if (!p.is_draft) {
    throw new ApiError(409, "NOT_A_DRAFT", "Only drafts can be deleted. Archive a published listing instead (PATCH with status \"archived\").");
  }
  const [orders, requests] = await Promise.all([
    q<Json[]>(c.db.from("order_item").select("order_item_id").eq("product_id", productId).limit(1)),
    q<Json[]>(c.db.from("custom_request").select("request_id").eq("product_id", productId).limit(1)),
  ]);
  if (orders.length || requests.length) throw new ApiError(409, "IN_USE", "This listing has orders or requests, so it cannot be deleted. Archive it instead.");
  const images = await q<Json[]>(c.db.from("product_image").select("image_path").eq("product_id", productId));
  await q(c.db.from("product").delete().eq("product_id", productId));
  // The photo files are removed too; a failure here does not undo the delete.
  const files = images.map((r) => r.image_path as string).filter((p) => !p.startsWith("http"));
  if (files.length) {
    const { error } = await c.db.storage.from("product-images").remove(files);
    if (error) console.error("Photo clean-up failed:", error.message);
  }
  return noContent();
});

route("GET", "/products/:productId/reviews", async (c) => {
  const productId = c.id("productId");
  await c.userId();
  await productCard(c, productId);
  const rows = await q<Json[]>(
    c.db.from("review").select("review_id, order_id, product_id, rating, comment, created_at")
      .eq("product_id", productId).order("created_at", { ascending: false }),
  );
  return ok(rows.map(reviewOut));
});

// -----------------------------------------------------------------------------
// Orders
// -----------------------------------------------------------------------------
async function myOrders(c: Ctx): Promise<Json[]> {
  await c.userId();
  return (await rpc<Json[] | null>(c, "my_orders")) ?? [];
}

async function findOrder(c: Ctx, match: (o: Json) => boolean): Promise<Json> {
  const order = (await myOrders(c)).find(match);
  if (!order) throw new ApiError(404, "NOT_FOUND", "Order not found.");
  return order;
}

/** 404 unless the caller is the buyer or the seller of this order. */
async function visibleOrder(c: Ctx, orderId: string): Promise<Json> {
  await c.userId();
  const row = await q<Json | null>(c.db.from("orders").select("order_id, buyer_id, status").eq("order_id", orderId).maybeSingle());
  if (!row) throw new ApiError(404, "NOT_FOUND", "Order not found.");
  return row;
}

route("GET", "/orders", async (c) => {
  const role = c.query("role");
  if (role && role !== "buyer" && role !== "seller") throw new ApiError(400, "BAD_REQUEST", "role must be buyer or seller.", "role");
  const status = c.query("status");
  let rows = await myOrders(c);
  if (role) rows = rows.filter((o) => o.side === (role === "buyer" ? "buying" : "selling"));
  if (status) rows = rows.filter((o) => o.status === status);
  return ok(rows.map(orderOut));
});

route("GET", "/orders/:orderId", async (c) => {
  const id = c.id("orderId");
  return ok(orderOut(await findOrder(c, (o) => o.order_id === id)));
});

route("POST", "/orders", async (c) => {
  await c.userId();
  const i = await c.input(["productId", "quantity"]);
  const productId = i.uuid("productId", { required: true });
  const quantity = i.int("quantity", { required: true })!;
  if (quantity < 1 || quantity > 99) throw new ApiError(422, "VALIDATION_FAILED", "Choose a quantity from 1 to 99.", "quantity");
  const number = await rpc<string>(c, "place_order", { p_product_id: productId, p_quantity: quantity });
  const order = await findOrder(c, (o) => o.order_number === number);
  return created(`/orders/${order.order_id}`, orderOut(order));
});

const ORDER_STATUSES = ["in_production", "shipped", "delivered", "completed", "cancelled"] as const;

route("PATCH", "/orders/:orderId", async (c) => {
  const id = c.id("orderId");
  const i = await c.input(["status", "note"]);
  const status = i.oneOf("status", ORDER_STATUSES, { required: true });
  const note = i.str("note", { max: 500 }) || null;
  await visibleOrder(c, id);
  await rpc(c, "set_order_status", { p_order_id: id, p_status: status, p_note: note });
  return ok(orderOut(await findOrder(c, (o) => o.order_id === id)));
});

route("GET", "/orders/:orderId/history", async (c) => {
  const id = c.id("orderId");
  await visibleOrder(c, id);
  const rows = await q<Json[]>(
    c.db.from("order_status_history").select("history_id, from_status, to_status, note, photo_path, changed_at")
      .eq("order_id", id).order("changed_at"),
  );
  return ok(rows.map((r) => camel(r)));
});

// -----------------------------------------------------------------------------
// Payments (nested under an order)
// -----------------------------------------------------------------------------
const PAYMENT_COLUMNS = "payment_id, order_id, reference_number, amount_paid, status, proof_image_path, verified_at";

route("GET", "/orders/:orderId/payments", async (c) => {
  const id = c.id("orderId");
  await visibleOrder(c, id);
  const rows = await q<Json[]>(c.db.from("payment").select(PAYMENT_COLUMNS).eq("order_id", id));
  return ok(rows.map(paymentOut));
});

route("POST", "/orders/:orderId/payments", async (c) => {
  const id = c.id("orderId");
  const me = await c.userId();
  const i = await c.input(["referenceNumber", "amountPaid", "proofImagePath", "proofImageHash"]);
  const reference = i.str("referenceNumber", { required: true })!.replace(/\s/g, "").toUpperCase();
  if (!/^[A-Z0-9-]{6,50}$/.test(reference)) {
    throw new ApiError(422, "VALIDATION_FAILED", "Enter the reference number from your receipt (6 to 50 letters or digits).", "referenceNumber");
  }
  const amount = i.num("amountPaid", { required: true, min: 0.01, max: 10_000_000 });
  const path = i.str("proofImagePath", { required: true, max: 255 })!;
  if (!path.startsWith(`${me}/${id}/`)) {
    throw new ApiError(422, "VALIDATION_FAILED", `Upload the receipt to private-files/${me}/${id}/ first.`, "proofImagePath");
  }
  const hash = i.str("proofImageHash", { required: true })!.toLowerCase();
  if (!/^[0-9a-f]{64}$/.test(hash)) throw new ApiError(400, "BAD_REQUEST", "proofImageHash must be a SHA-256 hash (64 hex characters).", "proofImageHash");
  await visibleOrder(c, id);
  await rpc(c, "submit_payment", { p_order_id: id, p_reference: reference, p_proof_path: path, p_proof_hash: hash, p_amount: amount });
  const row = await q<Json>(c.db.from("payment").select(PAYMENT_COLUMNS).eq("order_id", id).eq("reference_number", reference).single());
  return created(`/orders/${id}/payments/${row.payment_id}`, paymentOut(row));
});

route("PATCH", "/orders/:orderId/payments/:paymentId", async (c) => {
  const id = c.id("orderId");
  const paymentId = c.id("paymentId");
  const i = await c.input(["status", "reason"]);
  const status = i.oneOf("status", ["verified", "rejected"] as const, { required: true });
  const reason = i.str("reason", { max: 500 }) || null;
  if (status === "rejected" && !reason) throw new ApiError(422, "VALIDATION_FAILED", "Tell the buyer why the payment was rejected.", "reason");
  await visibleOrder(c, id);
  const pay = await q<Json | null>(c.db.from("payment").select("payment_id, status").eq("payment_id", paymentId).eq("order_id", id).maybeSingle());
  if (!pay) throw new ApiError(404, "NOT_FOUND", "Payment not found.");
  if (pay.status !== "submitted") throw new ApiError(409, "ALREADY_CHECKED", `This payment proof was already ${pay.status}.`);
  await rpc(c, "review_payment", { p_order_id: id, p_accept: status === "verified", p_reason: reason });
  const row = await q<Json>(c.db.from("payment").select(PAYMENT_COLUMNS).eq("payment_id", paymentId).single());
  return ok(paymentOut(row));
});

/**
 * Reads a receipt screenshot by forwarding it to the scan-receipt Edge Function
 * (OCR.space). Nothing is saved, so this returns 200, not 201.
 */
route("POST", "/orders/:orderId/receipt-scans", async (c) => {
  const id = c.id("orderId");
  await c.userId();
  const i = await c.input(["image", "mime", "hash"]);
  const image = i.str("image", { required: true })!;
  if (image.length * 0.75 > 1_000_000) {
    throw new ApiError(413, "PAYLOAD_TOO_LARGE", "The screenshot is too large to read. Type the reference number instead.", "image");
  }
  const mime = i.oneOf("mime", ["image/jpeg", "image/png", "image/webp"] as const) ?? "image/jpeg";
  const hash = i.str("hash");
  const res = await fetch(`${SUPABASE_URL()}/functions/v1/scan-receipt`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${c.token}`,
      apikey: ENV("SUPABASE_ANON_KEY") || (c.req.headers.get("apikey") ?? ""),
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ orderId: id, image, mime, hash }),
  });
  const data = await res.json().catch(() => ({})) as Json;
  if (!res.ok) {
    const message = typeof data.error === "string" ? data.error : "The receipt could not be read. Type the reference number instead.";
    const status = res.status >= 500 ? 502 : res.status;
    throw new ApiError(status, status === 502 ? "OCR_UNAVAILABLE" : CODE_FOR_STATUS[status] ?? "ERROR", message);
  }
  return ok(data);
});

// -----------------------------------------------------------------------------
// Reviews
// -----------------------------------------------------------------------------
const REVIEW_COLUMNS = "review_id, order_id, product_id, rating, comment, created_at";

route("POST", "/orders/:orderId/reviews", async (c) => {
  const id = c.id("orderId");
  const i = await c.input(["productId", "rating", "comment"]);
  const rating = i.int("rating", { required: true, min: 1, max: 5 });
  const comment = i.str("comment", { max: 1000 }) || null;
  const order = await findOrder(c, (o) => o.order_id === id);
  if (order.side !== "buying") throw new ApiError(403, "FORBIDDEN", "Only the buyer can review this order.");
  if (order.status !== "delivered" && order.status !== "completed") {
    throw new ApiError(422, "RULE_VIOLATION", "You can review an order only after it is delivered.");
  }
  const productId = i.uuid("productId") ?? order.product_id;
  const row = await q<Json>(
    c.db.from("review").insert({ order_id: id, product_id: productId, rating, comment }).select(REVIEW_COLUMNS).single(),
  );
  return created(`/reviews/${row.review_id}`, reviewOut(row));
});

route("PATCH", "/reviews/:reviewId", async (c) => {
  const id = c.id("reviewId");
  await c.userId();
  const i = await c.input(["rating", "comment"]);
  const row: Json = {};
  const rating = i.int("rating", { min: 1, max: 5 });
  if (rating !== undefined) row.rating = rating;
  if (i.has("comment")) row.comment = i.str("comment", { max: 1000 }) || null;
  if (Object.keys(row).length === 0) throw new ApiError(422, "VALIDATION_FAILED", "Send rating or comment to change.");
  const found = await q<Json | null>(c.db.from("review").select("review_id").eq("review_id", id).maybeSingle());
  if (!found) throw new ApiError(404, "NOT_FOUND", "Review not found.");
  const updated = await q<Json[]>(c.db.from("review").update(row).eq("review_id", id).select(REVIEW_COLUMNS));
  if (updated.length === 0) throw new ApiError(403, "FORBIDDEN", "You can only edit your own review.");
  return ok(reviewOut(updated[0]));
});

route("DELETE", "/reviews/:reviewId", async (c) => {
  const id = c.id("reviewId");
  await c.userId();
  const found = await q<Json | null>(c.db.from("review").select("review_id").eq("review_id", id).maybeSingle());
  if (!found) throw new ApiError(404, "NOT_FOUND", "Review not found.");
  const deleted = await q<Json[]>(c.db.from("review").delete().eq("review_id", id).select("review_id"));
  if (deleted.length === 0) throw new ApiError(403, "FORBIDDEN", "You can only delete your own review.");
  return noContent();
});

// -----------------------------------------------------------------------------
// Custom requests
// -----------------------------------------------------------------------------
async function myRequests(c: Ctx): Promise<Json[]> {
  await c.userId();
  return (await rpc<Json[] | null>(c, "my_custom_requests")) ?? [];
}

async function findRequest(c: Ctx, id: string): Promise<Json> {
  const r = (await myRequests(c)).find((x) => x.request_id === id);
  if (!r) throw new ApiError(404, "NOT_FOUND", "Request not found.");
  return r;
}

route("GET", "/custom-requests", async (c) => {
  const role = c.query("role");
  if (role && role !== "buyer" && role !== "seller") throw new ApiError(400, "BAD_REQUEST", "role must be buyer or seller.", "role");
  let rows = await myRequests(c);
  if (role) rows = rows.filter((r) => r.side === (role === "buyer" ? "buying" : "selling"));
  const status = c.query("status");
  if (status) rows = rows.filter((r) => r.status === status);
  return ok(rows.map(customRequestOut));
});

route("GET", "/custom-requests/:requestId", async (c) => ok(customRequestOut(await findRequest(c, c.id("requestId")))));

route("POST", "/custom-requests", async (c) => {
  await c.userId();
  const i = await c.input(["productId", "description", "quantity", "budget", "neededBy", "options"]);
  const args = {
    p_product_id: i.uuid("productId", { required: true }),
    p_description: i.str("description", { required: true, min: 10, max: 500 }),
    p_quantity: i.int("quantity", { required: true, min: 1, max: 999 }),
    p_budget: i.num("budget", { min: 0.01, max: 10_000_000 }) ?? null,
    p_needed_by: i.date("neededBy", { required: true }),
    p_options: i.strList("options", { max: 20, itemMax: 50 }) ?? [],
  };
  const saved = await rpc<Json>(c, "submit_custom_request", args);
  const request = await findRequest(c, saved.request_id);
  return created(`/custom-requests/${saved.request_id}`, customRequestOut(request));
});

route("PATCH", "/custom-requests/:requestId", async (c) => {
  const id = c.id("requestId");
  const i = await c.input(["status", "reason"]);
  const status = i.oneOf("status", ["cancelled", "declined"] as const, { required: true });
  const reason = i.str("reason", { max: 500 });
  await findRequest(c, id);
  if (status === "cancelled") {
    await rpc(c, "cancel_custom_request", { p_request_id: id });
  } else {
    if (!reason || reason.length < 3) throw new ApiError(422, "VALIDATION_FAILED", "Tell the buyer why you are declining.", "reason");
    await rpc(c, "decline_custom_request", { p_request_id: id, p_reason: reason });
  }
  return ok(customRequestOut(await findRequest(c, id)));
});

/** Attach a reference photo already uploaded to private-files/{buyerId}/{requestId}/. */
route("POST", "/custom-requests/:requestId/images", async (c) => {
  const id = c.id("requestId");
  const me = await c.userId();
  const i = await c.input(["imagePath"]);
  const path = i.str("imagePath", { required: true, max: 255 })!;
  if (!path.startsWith(`${me}/${id}/`)) {
    throw new ApiError(422, "VALIDATION_FAILED", `Upload the photo to private-files/${me}/${id}/ first.`, "imagePath");
  }
  const request = await findRequest(c, id);
  if (request.side !== "buying") throw new ApiError(403, "FORBIDDEN", "Only the buyer can add reference photos.");
  await q(c.db.from("custom_request_image").insert({ request_id: id, image_path: path }));
  return created(`/custom-requests/${id}`, { requestId: id, imagePath: path, _links: { request: link(`/custom-requests/${id}`) } });
});

// -----------------------------------------------------------------------------
// Quotes (nested under a custom request)
// -----------------------------------------------------------------------------
const QUOTE_COLUMNS = "quote_id, request_id, version_no, offered_price, estimated_completion_date, message, decline_reason, status, created_at";

route("GET", "/custom-requests/:requestId/quotes", async (c) => {
  const id = c.id("requestId");
  await findRequest(c, id);
  const rows = await q<Json[]>(c.db.from("quote").select(QUOTE_COLUMNS).eq("request_id", id).order("version_no"));
  return ok(rows.map(quoteOut));
});

route("POST", "/custom-requests/:requestId/quotes", async (c) => {
  const id = c.id("requestId");
  const i = await c.input(["price", "readyBy", "message"]);
  const price = i.num("price", { required: true, min: 0.01, max: 10_000_000 });
  const readyBy = i.date("readyBy", { required: true });
  const message = i.str("message", { max: 500 }) || null;
  const request = await findRequest(c, id);
  if (request.side !== "selling") throw new ApiError(403, "FORBIDDEN", "Only the seller can send a quote.");
  await rpc(c, "send_quote", { p_request_id: id, p_price: price, p_ready_by: readyBy, p_message: message });
  const row = await q<Json>(c.db.from("quote").select(QUOTE_COLUMNS).eq("request_id", id).order("version_no", { ascending: false }).limit(1).single());
  return created(`/custom-requests/${id}/quotes/${row.quote_id}`, quoteOut(row));
});

route("PATCH", "/custom-requests/:requestId/quotes/:quoteId", async (c) => {
  const id = c.id("requestId");
  const quoteId = c.id("quoteId");
  const i = await c.input(["status", "note"]);
  // "rejected" is accepted as another word for asking the seller for changes.
  const status = i.oneOf("status", ["accepted", "changes_requested", "rejected"] as const, { required: true });
  const note = i.str("note", { max: 500 }) || null;
  const request = await findRequest(c, id);
  if (!((request.quotes as Json[]) ?? []).some((x) => x.quote_id === quoteId)) throw new ApiError(404, "NOT_FOUND", "Quote not found.");
  if (request.side !== "buying") throw new ApiError(403, "FORBIDDEN", "Only the buyer can answer a quote.");
  const orderNumber = await rpc<string | null>(c, "respond_to_quote", { p_quote_id: quoteId, p_accept: status === "accepted", p_note: note });
  const row = await q<Json>(c.db.from("quote").select(QUOTE_COLUMNS).eq("quote_id", quoteId).single());
  const body = quoteOut(row) as Json;
  if (orderNumber) {
    const order = await findOrder(c, (o) => o.order_number === orderNumber);
    body.order = { orderId: order.order_id, orderNumber, _links: { self: link(`/orders/${order.order_id}`) } };
  }
  return ok(body);
});

// -----------------------------------------------------------------------------
// Start the server (only inside Supabase / Deno; the tests call handle() directly)
// -----------------------------------------------------------------------------
const deno = (globalThis as Json).Deno;
if (deno?.serve && !deno.env.get("CRAFTHIVE_API_TEST")) deno.serve(handle);
