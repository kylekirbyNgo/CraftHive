-- =============================================================================
-- CraftHive – 09: Fix profile photo upload
--
-- Uploading a profile photo failed with "new row violates row-level security
-- policy". Supabase Storage needs a SELECT policy on the user's own files to
-- replace or delete them, and the avatars bucket had none. The app no longer
-- replaces files (each photo gets a new name), and this policy lets it delete
-- the old photo after a new one is saved. The avatars bucket stays public, so
-- everyone can still see profile photos through their public links.
--
-- Run once in the Supabase SQL editor, after 01–08.
-- =============================================================================

drop policy if exists "avatars: read own" on storage.objects;
create policy "avatars: read own" on storage.objects for select to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);
