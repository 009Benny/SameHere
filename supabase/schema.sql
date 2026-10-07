-- ============================================================
-- Same Here — Supabase schema
-- Run in the Supabase SQL editor, or as a migration
-- (supabase db push / supabase migration new same_here_init)
--
-- Maps to the existing Swift domain models:
--   User        -> public.profiles
--   Thought     -> public.thoughts
--   OptionItem  -> public.options  (+ public.option_results for live counts)
--
-- After this file: auth_guests.sql, then grants.sql (table privileges —
-- without them every API request fails with 42501 permission denied),
-- then delete_account.sql (in-app account deletion), then moderation.sql
-- (banned words, reports, blocks, community rules).
-- ============================================================

create extension if not exists "pgcrypto"; -- gen_random_uuid()

-- ============================================================
-- profiles: one row per auth user (works with Supabase anonymous auth)
-- ============================================================
create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  name text not null default 'Anonymous',
  email text,
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

create policy "Profiles are publicly readable"
  on public.profiles for select
  using (true);

create policy "Users can insert their own profile"
  on public.profiles for insert
  with check (auth.uid() = id);

create policy "Users can update their own profile"
  on public.profiles for update
  using (auth.uid() = id);

-- Auto-create a profile row whenever a new auth user (incl. anonymous) is created
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, name, email)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'name', 'Anon-' || substr(new.id::text, 1, 6)),
    new.email
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ============================================================
-- thoughts: the "Am I the only one who...?" questions/debates
-- author_id is NULL for AI-seeded content (is_ai_generated = true)
-- ============================================================
create table if not exists public.thoughts (
  id uuid primary key default gen_random_uuid(),
  author_id uuid references public.profiles (id) on delete set null,
  message text not null,
  topic text not null,
  source_link text,
  is_ai_generated boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists thoughts_topic_idx on public.thoughts (topic);
create index if not exists thoughts_author_idx on public.thoughts (author_id);

alter table public.thoughts enable row level security;

create policy "Thoughts are publicly readable"
  on public.thoughts for select
  using (true);

create policy "Users can create their own thoughts"
  on public.thoughts for insert
  with check (auth.uid() = author_id);

create policy "Users can update their own thoughts"
  on public.thoughts for update
  using (auth.uid() = author_id);

create policy "Users can delete their own thoughts"
  on public.thoughts for delete
  using (auth.uid() = author_id);

-- ============================================================
-- options: each answer choice for a thought (app enforces 2-6 per thought)
-- ============================================================
create table if not exists public.options (
  id uuid primary key default gen_random_uuid(),
  thought_id uuid not null references public.thoughts (id) on delete cascade,
  title text not null,
  position smallint not null default 0,
  seed_votes integer not null default 0,
  created_at timestamptz not null default now()
);

create index if not exists options_thought_idx on public.options (thought_id);

alter table public.options enable row level security;

create policy "Options are publicly readable"
  on public.options for select
  using (true);

create policy "Users can add options to their own thoughts"
  on public.options for insert
  with check (
    exists (
      select 1 from public.thoughts t
      where t.id = thought_id and t.author_id = auth.uid()
    )
  );

create policy "Users can edit options on their own thoughts"
  on public.options for update
  using (
    exists (
      select 1 from public.thoughts t
      where t.id = thought_id and t.author_id = auth.uid()
    )
  );

create policy "Users can delete options on their own thoughts"
  on public.options for delete
  using (
    exists (
      select 1 from public.thoughts t
      where t.id = thought_id and t.author_id = auth.uid()
    )
  );

-- ============================================================
-- answers: one real vote per user per thought
-- (on top of the AI-seeded `seed_votes` on each option)
-- ============================================================
create table if not exists public.answers (
  id uuid primary key default gen_random_uuid(),
  thought_id uuid not null references public.thoughts (id) on delete cascade,
  option_id uuid not null references public.options (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (thought_id, user_id) -- enforces "one vote per user per thought"
);

create index if not exists answers_option_idx on public.answers (option_id);
create index if not exists answers_user_idx on public.answers (user_id);

alter table public.answers enable row level security;

create policy "Answers are publicly readable"
  on public.answers for select
  using (true);

create policy "Users can vote as themselves"
  on public.answers for insert
  with check (auth.uid() = user_id);

create policy "Users can change their own vote"
  on public.answers for delete
  using (auth.uid() = user_id);

-- ============================================================
-- option_results: seed_votes + real votes, ready for OptionRowView
-- Query this (not `options` directly) to render counters/percentages.
-- ============================================================
create or replace view public.option_results as
select
  o.id as option_id,
  o.thought_id,
  o.title,
  o.position,
  o.seed_votes + count(a.id) as votes
from public.options o
left join public.answers a on a.option_id = o.id
group by o.id, o.thought_id, o.title, o.position, o.seed_votes
order by o.thought_id, o.position;

-- ============================================================
-- my_answers: lets the client know which thoughts the current user
-- already answered, so HomeView can skip them like a swiped card.
-- ============================================================
create or replace view public.my_answers as
select thought_id, option_id
from public.answers
where user_id = auth.uid();
