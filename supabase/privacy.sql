-- ============================================================
-- Same Here — privacy hardening (run LAST, after moderation.sql)
-- Safe to run more than once.
--
-- Closes two leaks that the privacy policy says do not exist:
--   1. Any signed-in user (even a guest) could read every profile's EMAIL.
--   2. Any signed-in user could read EVERY row of `answers`, i.e. who voted
--      for what.
--
-- Why two layers: RLS decides which ROWS you see, GRANT decides which COLUMNS
-- (and tables) you may touch. Profiles must stay readable by row — the feed
-- shows each author's name — so the fix there is at column level. Answers
-- have no reason to be readable by anyone but their owner, so that one is
-- fixed at row level.
-- ============================================================

-- ------------------------------------------------------------
-- 1. profiles: other people's names, never their emails.
--    A table-level SELECT grant overrides column grants, so remove it first.
-- ------------------------------------------------------------
revoke select, update on public.profiles from authenticated;

grant select (id, name, is_guest, created_at, terms_accepted_at)
  on public.profiles to authenticated;

-- Users may edit their name and record the rules acceptance — never `email`
-- or `is_guest`, which are maintained by the auth triggers.
grant update (name, terms_accepted_at) on public.profiles to authenticated;

-- ------------------------------------------------------------
-- 2. answers: only the owner reads their own votes.
--    Totals still work: `option_results` is a normal (owner-privileged) view,
--    so it counts every row and exposes only the numbers. `my_answers`
--    filters on auth.uid() already.
-- ------------------------------------------------------------
drop policy if exists "Answers are publicly readable" on public.answers;
drop policy if exists "Users can read their own answers" on public.answers;

create policy "Users can read their own answers"
  on public.answers for select
  using (auth.uid() = user_id);

-- Make PostgREST pick up the new privileges immediately.
notify pgrst, 'reload schema';

-- ------------------------------------------------------------
-- Verify (optional). Both should come back empty / false:
--   select column_name from information_schema.column_privileges
--    where table_name = 'profiles' and grantee = 'authenticated'
--      and privilege_type = 'SELECT' and column_name = 'email';
--   select policyname from pg_policies
--    where tablename = 'answers' and cmd = 'SELECT' and qual = 'true';
-- ------------------------------------------------------------
