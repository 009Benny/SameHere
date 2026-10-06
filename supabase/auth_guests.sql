-- ============================================================
-- Same Here — guest accounts, follow-up migration to schema.sql
--
-- Run AFTER supabase/schema.sql. Safe to re-run.
--
-- Why this exists: schema.sql creates a profile row when an auth user is
-- inserted, which covers a guest signing in for the first time. Nothing yet
-- reacts when that same user later attaches an email and password
-- (AuthFeature's `linkAccount`, GoTrue's `PUT /auth/v1/user`) — that is an
-- UPDATE on auth.users, not an INSERT, so the profile would keep its
-- "Anon-3f9a2c" name and empty email forever.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Mark guests on the profile, so the client can nudge them
--    without decoding the JWT.
-- ------------------------------------------------------------
alter table public.profiles
  add column if not exists is_guest boolean not null default false;

create index if not exists profiles_is_guest_idx
  on public.profiles (is_guest) where is_guest;

-- ------------------------------------------------------------
-- 2. Create the profile, now recording whether the user is a guest.
--    Replaces the version in schema.sql.
-- ------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, name, email, is_guest)
  values (
    new.id,
    coalesce(
      nullif(new.raw_user_meta_data ->> 'full_name', ''),
      nullif(new.raw_user_meta_data ->> 'name', ''),
      'Anon-' || substr(new.id::text, 1, 6)
    ),
    new.email,
    coalesce(new.is_anonymous, false)
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ------------------------------------------------------------
-- 3. Keep the profile in step when a guest upgrades.
--
--    Fires on the UPDATE that `linkAccount` produces: the email arrives, the
--    name arrives in user_metadata, and is_anonymous flips to false. The user
--    id never changes, so their thoughts, options and answers are untouched —
--    which is the entire point of upgrading rather than re-registering.
-- ------------------------------------------------------------
create or replace function public.handle_user_updated()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  update public.profiles p
  set
    email = coalesce(new.email, p.email),
    is_guest = coalesce(new.is_anonymous, false),
    -- Only overwrite the placeholder name; never clobber a name the user chose.
    name = case
             when p.name like 'Anon-%'
               then coalesce(
                      nullif(new.raw_user_meta_data ->> 'full_name', ''),
                      nullif(new.raw_user_meta_data ->> 'name', ''),
                      p.name
                    )
             else p.name
           end
  where p.id = new.id;
  return new;
end;
$$;

drop trigger if exists on_auth_user_updated on auth.users;
create trigger on_auth_user_updated
  after update on auth.users
  for each row
  when (
    old.email is distinct from new.email
    or old.is_anonymous is distinct from new.is_anonymous
    or old.raw_user_meta_data is distinct from new.raw_user_meta_data
  )
  execute function public.handle_user_updated();

-- ------------------------------------------------------------
-- 4. Backfill anything created before this migration.
-- ------------------------------------------------------------
update public.profiles p
set is_guest = coalesce(u.is_anonymous, false),
    email = coalesce(u.email, p.email)
from auth.users u
where u.id = p.id
  and (p.is_guest is distinct from coalesce(u.is_anonymous, false)
       or p.email is distinct from coalesce(u.email, p.email));

-- ------------------------------------------------------------
-- 5. Housekeeping: abandoned guests.
--
--    A guest who opened the app once and never came back is a row that will
--    never be reachable again (their refresh token died with the install).
--    Deleting the ones with no content keeps auth.users honest; the cascade
--    on profiles handles the rest.
--
--    Call it from a scheduled job (Supabase → Integrations → Cron), e.g.
--      select public.purge_abandoned_guests(90);
--    Not exposed to the client: it runs as the postgres role.
-- ------------------------------------------------------------
create or replace function public.purge_abandoned_guests(older_than_days integer default 90)
returns integer
language plpgsql
security definer set search_path = public
as $$
declare
  deleted integer;
begin
  with doomed as (
    delete from auth.users u
    where u.is_anonymous is true
      and u.created_at < now() - make_interval(days => older_than_days)
      and not exists (select 1 from public.thoughts t where t.author_id = u.id)
      and not exists (select 1 from public.answers a where a.user_id = u.id)
    returning 1
  )
  select count(*) into deleted from doomed;
  return deleted;
end;
$$;

revoke all on function public.purge_abandoned_guests(integer) from public, anon, authenticated;

-- ------------------------------------------------------------
-- 6. Optional: keep guests from creating thoughts.
--
--    Same Here wants the opposite — a guest who can write is a guest worth
--    converting — so this is left commented out. Uncomment only if guest
--    content turns out to be a spam problem.
-- ------------------------------------------------------------
-- drop policy if exists "Users can create their own thoughts" on public.thoughts;
-- create policy "Saved accounts can create thoughts"
--   on public.thoughts for insert
--   with check (
--     auth.uid() = author_id
--     and coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) is false
--   );
