-- ============================================================
-- Same Here — user-generated content safety (App Store guideline 1.2)
-- Run after schema.sql, auth_guests.sql, grants.sql and delete_account.sql.
-- Safe to re-run.
--
--   1. banned_terms     — words a thought or option may not contain
--   2. reports          — "report this thought"; 3 reports hide it for everyone
--   3. blocks           — "block this person"; the app hides their thoughts
--   4. terms_accepted_at on profiles — the community rules each account agreed to
-- ============================================================


-- ------------------------------------------------------------
-- 0. Hidden thoughts
--    A thought hidden by moderation disappears for everyone except its author.
-- ------------------------------------------------------------
alter table public.thoughts add column if not exists hidden_at timestamptz;

drop policy if exists "Thoughts are publicly readable" on public.thoughts;
drop policy if exists "Visible thoughts are readable" on public.thoughts;
create policy "Visible thoughts are readable"
  on public.thoughts for select
  using (hidden_at is null or author_id = auth.uid());

-- Authors may edit their text, never un-hide a thought or relabel it.
revoke update on public.thoughts from authenticated;
grant update (message, topic) on public.thoughts to authenticated;


-- ------------------------------------------------------------
-- 1. Objectionable content filter
--    Enforced in the database, so it holds even for a client that skips the
--    app. Whole-word, case-insensitive match. Add terms with:
--      insert into public.banned_terms (term) values ('...') on conflict do nothing;
-- ------------------------------------------------------------
create table if not exists public.banned_terms (
  term text primary key check (term = lower(term) and length(term) > 1)
);
-- RLS on with no policies: clients can't read or edit the list.
alter table public.banned_terms enable row level security;

insert into public.banned_terms (term) values
  -- English
  ('fuck'), ('fucking'), ('motherfucker'), ('shit'), ('bitch'), ('cunt'),
  ('asshole'), ('dick'), ('pussy'), ('whore'), ('slut'), ('faggot'),
  ('nigger'), ('nigga'), ('retard'), ('rape'),
  -- Spanish
  ('puta'), ('puto'), ('putas'), ('putos'), ('pendejo'), ('pendeja'),
  ('verga'), ('chinga'), ('chingada'), ('chingar'), ('mierda'), ('culero'),
  ('culera'), ('cabrón'), ('cabron'), ('marica'), ('maricón'), ('maricon'),
  ('joto'), ('zorra'), ('coño'), ('violación'), ('violacion')
on conflict do nothing;

create or replace function public.contains_banned_term(content text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.banned_terms b
    where content ~* ('\m' || b.term || '\M')
  );
$$;

create or replace function public.reject_banned_terms()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  content text;
begin
  -- Separate branches, not one CASE: PL/pgSQL prepares a whole expression at
  -- once, so a CASE naming both new.message and new.title fails on either
  -- table with 'record "new" has no field ...'.
  if tg_table_name = 'thoughts' then
    content := new.message;
  else
    content := new.title;
  end if;

  if public.contains_banned_term(content) then
    -- 23514 = check_violation; the app maps it to a friendly message.
    raise exception 'objectionable_content' using errcode = '23514';
  end if;
  return new;
end;
$$;

drop trigger if exists thoughts_reject_banned_terms on public.thoughts;
create trigger thoughts_reject_banned_terms
  before insert or update of message on public.thoughts
  for each row execute function public.reject_banned_terms();

drop trigger if exists options_reject_banned_terms on public.options;
create trigger options_reject_banned_terms
  before insert or update of title on public.options
  for each row execute function public.reject_banned_terms();


-- ------------------------------------------------------------
-- 2. Reports
--    One report per person per thought. Review them in the dashboard
--    (Table Editor → reports, newest first) at least once a day — App Review
--    expects reported content to be acted on promptly.
-- ------------------------------------------------------------
create table if not exists public.reports (
  id uuid primary key default gen_random_uuid(),
  thought_id uuid not null references public.thoughts (id) on delete cascade,
  reporter_id uuid not null references public.profiles (id) on delete cascade,
  reason text not null check (reason in ('offensive', 'spam', 'sexual', 'harassment', 'other')),
  created_at timestamptz not null default now(),
  unique (thought_id, reporter_id)
);

create index if not exists reports_thought_idx on public.reports (thought_id);

alter table public.reports enable row level security;

drop policy if exists "Users can report as themselves" on public.reports;
create policy "Users can report as themselves"
  on public.reports for insert
  with check (reporter_id = auth.uid());

-- Only your own reports, so the feed can skip what you reported.
drop policy if exists "Users can see their own reports" on public.reports;
create policy "Users can see their own reports"
  on public.reports for select
  using (reporter_id = auth.uid());

grant select, insert on public.reports to authenticated;

-- Three different people reporting a thought hides it for everyone until
-- you review it (clear hidden_at in the dashboard to restore it).
create or replace function public.hide_reported_thought()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if (select count(*) from public.reports where thought_id = new.thought_id) >= 3 then
    update public.thoughts
       set hidden_at = coalesce(hidden_at, now())
     where id = new.thought_id;
  end if;
  return new;
end;
$$;

drop trigger if exists reports_hide_thought on public.reports;
create trigger reports_hide_thought
  after insert on public.reports
  for each row execute function public.hide_reported_thought();


-- ------------------------------------------------------------
-- 3. Blocks
-- ------------------------------------------------------------
create table if not exists public.blocks (
  blocker_id uuid not null references public.profiles (id) on delete cascade,
  blocked_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);

alter table public.blocks enable row level security;

drop policy if exists "Users manage their own blocks" on public.blocks;
create policy "Users manage their own blocks"
  on public.blocks for all
  using (blocker_id = auth.uid())
  with check (blocker_id = auth.uid());

grant select, insert, delete on public.blocks to authenticated;


-- ------------------------------------------------------------
-- 4. Community rules acceptance
-- ------------------------------------------------------------
alter table public.profiles add column if not exists terms_accepted_at timestamptz;
