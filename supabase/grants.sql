-- ============================================================
-- Same Here — table privileges for the API roles
-- Run AFTER schema.sql and auth_guests.sql. Safe to run more than once.
--
-- Postgres checks two layers on every API request:
--   1. GRANT  — may this role run SELECT/INSERT/... on the table at all?
--   2. RLS    — which rows? (the policies in schema.sql)
-- schema.sql only defined layer 2, so every request failed with
-- "permission denied for table ..." (42501). These grants open layer 1
-- exactly as far as the RLS policies already allow — RLS still decides rows.
--
-- Roles:
--   service_role  — the seed script (scripts/seed_thoughts.py). Bypasses RLS.
--   authenticated — every signed-in app user, INCLUDING guests: Supabase
--                   anonymous sign-in issues an `authenticated` JWT.
--   anon          — no session at all. The app shows nothing before sign-in,
--                   so it gets nothing here.
-- ============================================================

-- Seed script / server-side tooling: full access.
grant usage on schema public to service_role;
grant all on all tables    in schema public to service_role;
grant all on all sequences in schema public to service_role;
-- Tables created later get the same, so the script keeps working.
alter default privileges in schema public grant all on tables    to service_role;
alter default privileges in schema public grant all on sequences to service_role;

-- App users (registered and guests). Mirrors the policies in schema.sql.
grant usage on schema public to authenticated;

grant select, insert, update         on public.profiles to authenticated;
grant select, insert, update, delete on public.thoughts to authenticated;
grant select, insert, update, delete on public.options  to authenticated;
grant select, insert, delete         on public.answers  to authenticated;

-- Read models the app queries (see docs/supabase-integration.md).
grant select on public.option_results to authenticated;
grant select on public.my_answers     to authenticated;
