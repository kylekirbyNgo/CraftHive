// =============================================================================
// CraftHive – scan-receipt (Supabase Edge Function)
//
// Reads a payment receipt screenshot (GCash, Maya, bank / InstaPay) with the
// OCR.space API and returns what the app needs to fill in the payment form:
//   • the reference number and the amount on the receipt,
//   • whether that reference or screenshot was already used (PAYMENT table),
//   • whether the amount matches the order total.
// The buyer still confirms or corrects the values; submit_payment() in
// 04_orders_and_custom_orders.sql keeps rejecting duplicates when saving.
// Nothing here proves the money arrived: the seller confirms that in their own
// GCash or bank app, as before.
//
// Request (POST, signed-in buyer):
//   { "orderId": "<uuid>", "image": "<base64 JPEG/PNG, at most 1 MB>", "mime": "image/jpeg", "hash": "<sha256 of the original file>" }
//
// Secrets: OCR_SPACE_API_KEY (free key from https://ocr.space/ocrapi/freekey).
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are provided by Supabase.
// Deploy with "Verify JWT" OFF; the caller is checked below.
// =============================================================================

import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";

type Json = Record<string, unknown>;

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

class HttpError extends Error {
  constructor(public status: number, message: string) {
    super(message);
  }
}

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } });

function env(name: string): string {
  const v = Deno.env.get(name);
  if (!v) throw new HttpError(500, `Missing secret ${name}.`);
  return v;
}

// -----------------------------------------------------------------------------
// Reading the receipt text (pure functions, tested without the internet)
// -----------------------------------------------------------------------------
const MONTH = /^(jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*$/i;

/** Labels that come right before a reference number on PH receipts. Earlier = preferred. */
const LABELS: RegExp[] = [
  /\bref(?:erence)?\s*\.?\s*(?:number|num|no|id|code|#)?\s*\.?\s*[:#]?\s*/i, // Ref No. / Reference ID / Reference Number
  /\btransaction\s*(?:no|id|number|ref)\s*\.?\s*[:#]?\s*/i,
  /\b(?:trace|confirmation|invoice)\s*(?:no|number|id)?\s*\.?\s*[:#]?\s*/i,
];

/** Turns "5012 345 678901 Nov 15" into "5012345678901": keeps the groups that look like a code. */
export function cleanReference(raw: string): string | null {
  const tokens: string[] = [];
  for (const t of raw.trim().split(/\s+/)) {
    if (!/^[A-Za-z0-9-]+$/.test(t)) break;
    if (MONTH.test(t)) break; // date after the number
    if (!/\d/.test(t) && tokens.length > 0) break; // a word after the number
    if (!/\d/.test(t) && t.length > 3) return null; // the label itself was a word ("Reference Details")
    tokens.push(t);
    if (tokens.join("").length >= 30) break;
  }
  const ref = tokens.join("").replace(/^-+|-+$/g, "").toUpperCase();
  // Same rule as submit_payment(): 6 to 50 letters, digits or dashes, with at least one digit.
  return /^[A-Z0-9-]{6,50}$/.test(ref) && /\d/.test(ref) ? ref : null;
}

/** Reference numbers found in the receipt text, best first. */
export function extractReferences(text: string): string[] {
  const lines = text.replace(/\r/g, "").split("\n").map((l) => l.replace(/\t/g, " ").trim()).filter(Boolean);
  const found: string[] = [];
  const add = (r: string | null) => {
    if (r && !found.includes(r)) found.push(r);
  };
  for (const label of LABELS) {
    lines.forEach((line, i) => {
      const m = label.exec(line);
      if (!m) return;
      const after = line.slice(m.index + m[0].length);
      // The value is on the same line, or on the next one (some layouts).
      add(cleanReference(after) ?? (i + 1 < lines.length ? cleanReference(lines[i + 1]) : null));
    });
  }
  // GCash format without a readable label: 4-3-6 digits (13 in all).
  for (const m of text.matchAll(/\b(\d{4})\s?(\d{3})\s?(\d{6})\b/g)) add(m[1] + m[2] + m[3]);
  return found;
}

const toNumber = (s: string) => Number(s.replace(/,/g, ""));

/** The amount paid, read from "Total Amount Sent ₱900.00", "Amount PHP 1,050.00", etc. */
export function extractAmount(text: string): number | null {
  const lines = text.replace(/\r/g, "").split("\n").map((l) => l.replace(/\t/g, " "));
  const money = /(?:₱|PHP|Php|php|P)?\s?(\d{1,3}(?:,\d{3})+(?:\.\d{2})?|\d+\.\d{2})/;
  // 1. A line with "total" and "amount", then any line with "amount".
  for (const want of [/total\s*amount|amount\s*(?:sent|paid|transferred)|total/i, /amount/i]) {
    for (let i = 0; i < lines.length; i++) {
      if (!want.test(lines[i])) continue;
      const m = money.exec(lines[i].replace(want, " ")) ?? (i + 1 < lines.length ? money.exec(lines[i + 1]) : null);
      if (m && toNumber(m[1]) > 0) return toNumber(m[1]);
    }
  }
  // 2. Otherwise the largest peso amount on the receipt.
  const all = [...text.matchAll(/(?:₱|PHP|Php)\s?(\d{1,3}(?:,\d{3})*(?:\.\d{2})?)/g)].map((m) => toNumber(m[1])).filter((n) => n > 0);
  return all.length ? Math.max(...all) : null;
}

export function detectProvider(text: string): "gcash" | "maya" | "bank" | null {
  const t = text.toLowerCase();
  if (t.includes("gcash")) return "gcash";
  if (/\b(pay)?maya\b/.test(t)) return "maya";
  if (/instapay|pesonet|\bbdo\b|\bbpi\b|metrobank|landbank|unionbank|security bank|rcbc|chinabank|pnb\b|gotyme|seabank|cimb/.test(t)) return "bank";
  return null;
}

// -----------------------------------------------------------------------------
// OCR.space
// -----------------------------------------------------------------------------
async function ocr(base64: string, mime: string): Promise<string> {
  const form = new FormData();
  form.append("base64Image", `data:${mime};base64,${base64}`);
  form.append("language", "eng");
  form.append("OCREngine", "2"); // better with numbers and receipt layouts
  form.append("scale", "true");
  form.append("isTable", "true"); // keeps "label  value" on one line
  form.append("detectOrientation", "true");
  const res = await fetch("https://api.ocr.space/parse/image", {
    method: "POST",
    headers: { apikey: env("OCR_SPACE_API_KEY") },
    body: form,
  });
  if (!res.ok) throw new HttpError(502, `The receipt reader is busy (HTTP ${res.status}). Type the reference number instead.`);
  const data = await res.json() as Json;
  if (data.IsErroredOnProcessing) {
    const msg = Array.isArray(data.ErrorMessage) ? data.ErrorMessage.join(" ") : String(data.ErrorMessage ?? "");
    console.error("OCR.space error:", msg);
    throw new HttpError(502, "The receipt could not be read. Type the reference number instead.");
  }
  const results = (data.ParsedResults as Json[] | undefined) ?? [];
  return results.map((r) => String(r.ParsedText ?? "")).join("\n");
}

// -----------------------------------------------------------------------------
let _admin: SupabaseClient | null = null;
function admin(): SupabaseClient {
  if (_admin) return _admin;
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? env("SERVICE_ROLE_KEY");
  _admin = createClient(env("SUPABASE_URL"), key, { auth: { persistSession: false, autoRefreshToken: false } });
  return _admin;
}

async function caller(req: Request): Promise<string> {
  const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!jwt) throw new HttpError(401, "Please log in again.");
  const { data, error } = await admin().auth.getUser(jwt);
  if (error || !data.user) throw new HttpError(401, "Please log in again.");
  return data.user.id;
}

async function scan(req: Request): Promise<Response> {
  const uid = await caller(req);
  const body = (await req.json().catch(() => ({}))) as Json;
  const orderId = String(body.orderId ?? "");
  const image = String(body.image ?? "").replace(/^data:[^,]+,/, "");
  const mime = /^image\/(jpeg|png|webp)$/.test(String(body.mime)) ? String(body.mime) : "image/jpeg";
  const hash = /^[0-9a-f]{64}$/.test(String(body.hash ?? "")) ? String(body.hash) : null;
  if (!/^[0-9a-f-]{36}$/.test(orderId)) throw new HttpError(400, "Missing order.");
  if (!image) throw new HttpError(400, "Missing image.");
  if (image.length * 0.75 > 1_000_000) throw new HttpError(413, "The screenshot is too large to read. Type the reference number instead.");

  // Only the buyer of the order may scan receipts for it.
  const { data: row, error } = await admin()
    .from("orders").select("order_id, buyer_id, total_amount, status").eq("order_id", orderId).maybeSingle();
  if (error) throw new HttpError(500, error.message);
  const order = row as Json | null;
  if (!order || order.buyer_id !== uid) throw new HttpError(404, "Order not found.");

  // The screenshot itself was uploaded before (same check as submit_payment, earlier).
  let screenshotUsed = false;
  if (hash) {
    const { data } = await admin().from("payment").select("payment_id").eq("proof_image_hash", hash).limit(1);
    screenshotUsed = ((data ?? []) as unknown[]).length > 0;
  }

  const text = await ocr(image, mime);
  const references = extractReferences(text);
  const reference = references[0] ?? null;
  const amount = extractAmount(text);
  const total = Number(order.total_amount);

  let referenceUsed = false;
  if (reference) {
    const { data } = await admin().from("payment").select("payment_id").eq("reference_number", reference).limit(1);
    referenceUsed = ((data ?? []) as unknown[]).length > 0;
  }

  return json({
    reference,
    candidates: references.slice(0, 3),
    amount,
    orderTotal: total,
    amountMatches: amount == null ? null : Math.abs(amount - total) < 0.01,
    referenceUsed,
    screenshotUsed,
    provider: detectProvider(text),
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "Use POST." }, 405);
  try {
    return await scan(req);
  } catch (e) {
    const status = e instanceof HttpError ? e.status : 500;
    console.error(e);
    return json({ error: e instanceof HttpError ? e.message : "The receipt could not be read. Type the reference number instead." }, status);
  }
});
