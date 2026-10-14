-- ============================================================
-- Same Here — FULL RESET (destructive, irreversible)
--
-- Deletes everything the app created in Supabase:
--   * all tables, views, functions and triggers of Same Here
--   * all users (auth.users): guests and registered accounts
-- It does NOT touch Supabase's own schemas or your project settings
-- (Auth providers, SMTP, API keys stay as they are).
--
-- Then run, in this order:
--   schema.sql -> auth_guests.sql -> grants.sql -> delete_account.sql
--   -> moderation.sql -> privacy.sql
-- and re-seed with scripts/seed_thoughts.py.
--
-- Run it in the SQL Editor of the right project. Check the URL first.
-- ============================================================

begin;

-- 1. Triggers on Supabase's auth table (they live outside `public`, so
--    dropping the tables below would not remove them).
drop trigger if exists on_auth_user_created on auth.users;
drop trigger if exists on_auth_user_updated on auth.users;

-- 2. Views, then tables (CASCADE also removes their policies, indexes and
--    table triggers).
drop view  if exists public.my_answers      cascade;
drop view  if exists public.option_results  cascade;

drop table if exists public.reports      cascade;
drop table if exists public.blocks       cascade;
drop table if exists public.answers      cascade;
drop table if exists public.options      cascade;
drop table if exists public.thoughts     cascade;
drop table if exists public.banned_terms cascade;
drop table if exists public.profiles     cascade;

-- 3. Functions.
drop function if exists public.handle_new_user()                    cascade;
drop function if exists public.handle_user_updated()                cascade;
drop function if exists public.purge_abandoned_guests(integer)      cascade;
drop function if exists public.delete_my_account()                  cascade;
drop function if exists public.contains_banned_term(text)           cascade;
drop function if exists public.reject_banned_terms()                cascade;
drop function if exists public.hide_reported_thought()              cascade;

-- 4. Every user. Safe now: profiles (which referenced them) is gone.
delete from auth.users;

commit;

-- Make the API forget the old tables.
notify pgrst, 'reload schema';

-- Sanity check — should list nothing:
--   select table_name from information_schema.tables
--    where table_schema = 'public';
