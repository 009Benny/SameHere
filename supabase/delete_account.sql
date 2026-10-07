-- ============================================================
-- Same Here — in-app account deletion (App Store guideline 5.1.1(v))
-- Run after schema.sql, auth_guests.sql and grants.sql. Safe to re-run.
--
-- The app only holds the anon key, which cannot touch auth.users. This
-- function runs as its owner (security definer) and deletes exactly one
-- user: the one calling it, taken from the JWT via auth.uid(). There is
-- no parameter, so nobody can pass someone else's id.
--
-- What goes:
--   * their thoughts — deleted explicitly, because thoughts.author_id is
--     ON DELETE SET NULL and would otherwise linger as authorless posts
--     (their options and everyone's answers to them cascade)
--   * their auth user — which cascades to profiles, and from profiles to
--     their own answers (votes)
-- ============================================================

create or replace function public.delete_my_account()
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

  delete from public.thoughts where author_id = me;
  delete from auth.users where id = me;
end;
$$;

-- Callable by signed-in users (guests included), nobody else.
revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;
