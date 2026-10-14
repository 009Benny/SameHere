-- ============================================================
-- Same Here — what guests can't do (run LAST, after privacy.sql)
-- Safe to run more than once.
--
-- Guests (Supabase anonymous users) can read and vote. They can NOT:
--   1. create thoughts  (and so can't add options either: those policies
--                        already require owning the thought)
--   2. report thoughts
--   3. block people
--
-- The app already stops them with a "Sign in to continue" alert. This is the
-- same rule on the server, so it holds for anyone calling the API directly
-- with a guest token. A blocked insert fails with 42501, which the app shows
-- as "You don't have permission to do that."
--
-- How a guest is recognised: the `is_anonymous` claim in the JWT. It is set by
-- Supabase Auth itself, so the client can't fake it, and it flips to false as
-- soon as the guest attaches an email (the upgrade) and gets a new token.
-- ============================================================


-- ------------------------------------------------------------
-- 0. One helper, so the three policies read the same.
--    `is not true` rather than `= false`: a token without the claim counts as
--    a saved account, never as a guest.
-- ------------------------------------------------------------
create or replace function public.is_saved_account()
returns boolean
language sql
stable
set search_path = public
as $$
  select coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) is not true;
$$;

grant execute on function public.is_saved_account() to authenticated;


-- ------------------------------------------------------------
-- 1. Thoughts — replaces schema.sql's "Users can create their own thoughts".
-- ------------------------------------------------------------
drop policy if exists "Users can create their own thoughts" on public.thoughts;
drop policy if exists "Saved accounts can create thoughts" on public.thoughts;
create policy "Saved accounts can create thoughts"
  on public.thoughts for insert
  with check (
    auth.uid() = author_id
    and public.is_saved_account()
  );


-- ------------------------------------------------------------
-- 2. Reports — replaces moderation.sql's "Users can report as themselves".
--    Reading your own reports is unchanged.
-- ------------------------------------------------------------
drop policy if exists "Users can report as themselves" on public.reports;
drop policy if exists "Saved accounts can report as themselves" on public.reports;
create policy "Saved accounts can report as themselves"
  on public.reports for insert
  with check (
    reporter_id = auth.uid()
    and public.is_saved_account()
  );


-- ------------------------------------------------------------
-- 3. Blocks — moderation.sql had one "for all" policy. Split it so reading
--    and removing your own blocks stays open to everyone, and only creating
--    one needs a saved account.
-- ------------------------------------------------------------
drop policy if exists "Users manage their own blocks" on public.blocks;

drop policy if exists "Users can see their own blocks" on public.blocks;
create policy "Users can see their own blocks"
  on public.blocks for select
  using (blocker_id = auth.uid());

drop policy if exists "Users can remove their own blocks" on public.blocks;
create policy "Users can remove their own blocks"
  on public.blocks for delete
  using (blocker_id = auth.uid());

drop policy if exists "Saved accounts can block" on public.blocks;
create policy "Saved accounts can block"
  on public.blocks for insert
  with check (
    blocker_id = auth.uid()
    and public.is_saved_account()
  );


-- ------------------------------------------------------------
-- Check — should list the four new policies:
--   select tablename, policyname, cmd from pg_policies
--    where schemaname = 'public' and tablename in ('thoughts','reports','blocks')
--    order by tablename, cmd;
-- ------------------------------------------------------------
