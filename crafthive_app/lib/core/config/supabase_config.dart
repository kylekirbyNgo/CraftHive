/// Connection details for the group's Supabase project.
///
/// The anon (publishable) key is meant to be inside the app: it only allows
/// what the row-level security policies in database/02_logic_and_security.sql
/// permit. Never put the service_role key here.
abstract final class SupabaseConfig {
  static const url = 'https://cylnldryczotoagaxwvw.supabase.co';
  static const anonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImN5bG5sZHJ5Y3pvdG9hZ2F4d3Z3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTQzMTQ3NDYsImV4cCI6MjEwOTg5MDc0Nn0.m4B1dpV_xVkwE9CR0gfWaKkVBiJgfzLza0dfkMzWPUU';

  static bool get isSet => url.startsWith('https://') && anonKey.length > 20;
}
