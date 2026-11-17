// CraftHive – staff accounts (ADMIN table, outside the USER hierarchy).
//
// Only a signed-in superadmin may call this. Adding and removing sign-in
// accounts needs the Supabase Auth admin API (service role), which the app
// must never hold, so it lives here.
//
//   { "action": "invite", email, firstName, lastName, role }
//       Creates a staff sign-in (no marketplace profile), adds the ADMIN row and
//       emails a "choose your password" link (the app's reset-password screen).
//   { "action": "deactivate", adminId } / { "action": "reactivate", adminId }
//       Blocks (or unblocks) the staff sign-in and sets admin.is_active. The row
//       is kept so their name stays on the decisions they made.
//
// Deploy:  supabase functions deploy admin-accounts
// Secret (optional): RESET_REDIRECT, default ph.crafthive.app://reset-password
import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";

type Json = Record<string, unknown>;

class HttpError extends Error {
  constructor(public status: number, message: string) {
    super(message);
  }
}

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } });

let _admin: SupabaseClient | null = null;
function admin(): SupabaseClient {
  _admin ??= createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
  return _admin;
}

/** The calling staff member; refuses anyone who is not a superadmin. */
async function superadmin(req: Request): Promise<{ adminId: string; uid: string }> {
  const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!jwt) throw new HttpError(401, "Please log in again.");
  const { data, error } = await admin().auth.getUser(jwt);
  if (error || !data.user) throw new HttpError(401, "Please log in again.");
  const { data: row } = await admin().from("admin").select("admin_id, role").eq("auth_uid", data.user.id).eq("is_active", true).maybeSingle();
  if (!row || row.role !== "superadmin") throw new HttpError(403, "Only a superadmin can manage staff accounts.");
  return { adminId: String(row.admin_id), uid: data.user.id };
}

const EMAIL = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;
const NAME = /^[\p{L} .'-]{1,50}$/u;

async function invite(body: Json): Promise<Response> {
  const email = String(body.email ?? "").trim().toLowerCase();
  const firstName = String(body.firstName ?? "").trim();
  const lastName = String(body.lastName ?? "").trim();
  const role = String(body.role ?? "moderator");
  if (!EMAIL.test(email) || email.length > 100) throw new HttpError(400, "Enter a valid email address.");
  if (!NAME.test(firstName) || !NAME.test(lastName)) throw new HttpError(400, "Enter the staff member's first and last name.");
  if (role !== "moderator" && role !== "superadmin") throw new HttpError(400, "Unknown role.");

  // Staff accounts are separate from marketplace accounts (Milestone II, assumption 4).
  const [{ data: member }, { data: staff }] = await Promise.all([
    admin().from("users").select("user_id").eq("email", email).maybeSingle(),
    admin().from("admin").select("admin_id").eq("email", email).maybeSingle(),
  ]);
  if (staff) throw new HttpError(409, "This email is already a staff account.");
  if (member) throw new HttpError(409, "This email belongs to a marketplace account. Use a separate work email for staff.");

  const created = await admin().auth.admin.createUser({ email, email_confirm: true, user_metadata: { role_hint: "admin" } });
  if (created.error || !created.data.user) {
    throw new HttpError(409, created.error?.message.includes("already") ? "This email already has a sign-in. Use another email." : "Could not create the account.");
  }
  const uid = created.data.user.id;
  const { error: insertError } = await admin().from("admin").insert({ auth_uid: uid, first_name: firstName, last_name: lastName, email, role });
  if (insertError) {
    await admin().auth.admin.deleteUser(uid); // keep sign-ins and staff rows in step
    throw new HttpError(500, "Could not add the staff member.");
  }
  // They choose their own password from the emailed link; nobody else ever sees it.
  const redirectTo = Deno.env.get("RESET_REDIRECT") ?? "ph.crafthive.app://reset-password";
  const { error: mailError } = await admin().auth.resetPasswordForEmail(email, { redirectTo });
  return json({ ok: true, emailed: !mailError });
}

async function setActive(body: Json, me: { adminId: string }, active: boolean): Promise<Response> {
  const adminId = String(body.adminId ?? "");
  if (adminId === me.adminId) throw new HttpError(400, "You can't deactivate your own account.");
  const { data: row } = await admin().from("admin").select("admin_id, auth_uid, role, is_active").eq("admin_id", adminId).maybeSingle();
  if (!row) throw new HttpError(404, "Staff member not found.");
  if (!active && row.role === "superadmin") {
    const { count } = await admin().from("admin").select("admin_id", { count: "exact", head: true }).eq("role", "superadmin").eq("is_active", true);
    if ((count ?? 0) <= 1) throw new HttpError(400, "CraftHive needs at least one superadmin.");
  }
  // "none" lifts the block; a long ban keeps a former staff member signed out.
  const { error } = await admin().auth.admin.updateUserById(String(row.auth_uid), { ban_duration: active ? "none" : "876000h" });
  if (error) throw new HttpError(500, "Could not update the sign-in.");
  const { error: rowError } = await admin().from("admin").update({ is_active: active }).eq("admin_id", adminId);
  if (rowError) throw new HttpError(500, "Could not update the staff member.");
  return json({ ok: true });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  try {
    const me = await superadmin(req);
    const body = (await req.json().catch(() => ({}))) as Json;
    switch (body.action) {
      case "invite":
        return await invite(body);
      case "deactivate":
        return await setActive(body, me, false);
      case "reactivate":
        return await setActive(body, me, true);
      default:
        throw new HttpError(400, "Unknown action.");
    }
  } catch (e) {
    if (e instanceof HttpError) return json({ error: e.message }, e.status);
    console.error(e);
    return json({ error: "Something went wrong. Try again." }, 500);
  }
});
