-- ============================================================
-- Same Here — push notifications (daily / weekly "new questions" digest)
-- Run after schema.sql, auth_guests.sql, grants.sql, delete_account.sql,
-- moderation.sql, privacy.sql and guest_restrictions.sql. Safe to re-run.
--
--   1. device_tokens          — one row per iPhone that opted in
--   2. register_device_token  — the app saves / moves its token here
--   3. new_thoughts_by_topic  — what the digest Edge Function counts
--
-- Scheduling the digest lives in push_schedule.sql (run it once the Edge
-- Function `send-digest` is deployed).
-- ============================================================


-- ------------------------------------------------------------
-- 1. device_tokens
--    The token is the key, not the user: one iPhone = one row. When someone
--    signs into another account on the same phone, the row moves to it.
--    Deleting an account (or purging a guest) removes its rows through the
--    cascade from profiles.
-- ------------------------------------------------------------
create table if not exists public.device_tokens (
  token       text primary key,
  user_id     uuid not null references public.profiles (id) on delete cascade,
  -- Debug builds talk to APNs sandbox; TestFlight / App Store to production.
  environment text not null check (environment in ('sandbox', 'production')),
  -- Language the digest is written in.
  locale      text not null default 'es' check (locale in ('es', 'en')),
  frequency   text not null default 'weekly' check (frequency in ('daily', 'weekly', 'off')),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index if not exists device_tokens_user_idx on public.device_tokens (user_id);
create index if not exists device_tokens_frequency_idx on public.device_tokens (frequency);

alter table public.device_tokens enable row level security;

-- Users see and remove only their own rows. Inserts and updates go through
-- register_device_token() below, never directly.
drop policy if exists "Users read their own device tokens" on public.device_tokens;
create policy "Users read their own device tokens"
  on public.device_tokens for select
  using (auth.uid() = user_id);

drop policy if exists "Users delete their own device tokens" on public.device_tokens;
create policy "Users delete their own device tokens"
  on public.device_tokens for delete
  using (auth.uid() = user_id);

revoke all on public.device_tokens from anon, authenticated;
grant select, delete on public.device_tokens to authenticated;


-- ------------------------------------------------------------
-- 2. register_device_token
--    Insert-or-move. security definer because the row may currently belong
--    to another account (same iPhone, different sign-in), which RLS would
--    not let the caller update. It only ever assigns the row to the caller.
-- ------------------------------------------------------------
create or replace function public.register_device_token(
  p_token       text,
  p_environment text,
  p_locale      text,
  p_frequency   text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
begin
  if me is null then
    raise exception 'Not signed in' using errcode = '42501';
  end if;
  if p_token !~ '^[0-9a-f]{32,200}$' then
    raise exception 'Invalid device token' using errcode = '22023';
  end if;

  insert into public.device_tokens (token, user_id, environment, locale, frequency, updated_at)
  values (p_token, me, p_environment, p_locale, p_frequency, now())
  on conflict (token) do update
    set user_id     = me,
        environment = excluded.environment,
        locale      = excluded.locale,
        frequency   = excluded.frequency,
        updated_at  = now();
end;
$$;

revoke all on function public.register_device_token(text, text, text, text) from public, anon;
grant execute on function public.register_device_token(text, text, text, text) to authenticated;


-- ------------------------------------------------------------
-- 3. new_thoughts_by_topic
--    Visible thoughts created since `since`, counted per topic. Only the
--    Edge Function (service role) calls it.
-- ------------------------------------------------------------
create or replace function public.new_thoughts_by_topic(since timestamptz)
returns table (topic text, total bigint)
language sql
stable
security definer
set search_path = public
as $$
  select t.topic, count(*) as total
  from public.thoughts t
  where t.created_at >= since
    and t.hidden_at is null
  group by t.topic
  order by total desc, t.topic;
$$;

revoke all on function public.new_thoughts_by_topic(timestamptz) from public, anon, authenticated;
grant execute on function public.new_thoughts_by_topic(timestamptz) to service_role;


-- Make the API pick up the new table and functions.
notify pgrst, 'reload schema';
