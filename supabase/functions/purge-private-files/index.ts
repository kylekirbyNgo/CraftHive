// CraftHive – deletes private files that are due (Data Privacy Act, RA 10173).
//
// Seller ID images are queued 30 days after the admin's decision, and replaced
// ID or portfolio photos right away (database/11_verified_maker.sql). This
// function deletes the queued files from the private-files bucket, then marks
// them purged so the database forgets the ID path.
//
// Deploy:  supabase functions deploy purge-private-files --no-verify-jwt
// Secret:  supabase secrets set CRON_SECRET=<long random value>
// Run daily with the pg_cron schedule at the end of 11_verified_maker.sql.
import { createClient } from "jsr:@supabase/supabase-js@2";

const BUCKET = "private-files";
const BATCH = 100;

Deno.serve(async (req) => {
  const secret = Deno.env.get("CRON_SECRET");
  if (!secret || req.headers.get("x-cron-secret") !== secret) {
    return new Response("Forbidden", { status: 403 });
  }

  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false },
  });

  const { data: due, error } = await db.rpc("due_private_files", { p_limit: 500 });
  if (error) return Response.json({ error: error.message }, { status: 500 });

  const paths = (due as string[] | null) ?? [];
  let purged = 0;
  const failed: string[] = [];

  for (let i = 0; i < paths.length; i += BATCH) {
    const batch = paths.slice(i, i + BATCH);
    const { error: removeError } = await db.storage.from(BUCKET).remove(batch);
    if (removeError) {
      // Leave them queued; the next run tries again.
      failed.push(...batch);
      continue;
    }
    // remove() also succeeds for files that were already gone, which is what we want.
    const { data: n, error: markError } = await db.rpc("mark_private_files_purged", { p_paths: batch });
    if (markError) failed.push(...batch);
    else purged += (n as number) ?? 0;
  }

  return Response.json({ due: paths.length, purged, failed: failed.length });
});
