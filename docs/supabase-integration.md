# Supabase integration plan — Same Here

## What's in this repo now

- `supabase/schema.sql` — the full schema: `profiles`, `thoughts`, `options`, `answers`, plus two views (`option_results`, `my_answers`). Run it once in the Supabase SQL editor (or as a migration) on a fresh project.
- `scripts/seed_thoughts.py` — loads AI-generated question JSON (the format your prompt already produces) and inserts it as `thoughts` + `options` rows, using the service role key so it bypasses RLS. Run this from your machine or CI, never from the app.
- `scripts/seed_data/` — drop the JSON files your AI prompt generates here (e.g. `tecnologia.json`, `salud.json`, one file per topic run), then `python scripts/seed_thoughts.py scripts/seed_data/`.

## How the schema maps to your Swift models

| Swift | Supabase | Notes |
|---|---|---|
| `User` (`id`, `name`, `email`) | `profiles` | `id` is the same UUID as `auth.users.id`. A row is created automatically by a trigger the first time someone signs in (see below), so the app never inserts into `profiles` directly. |
| `Thought` (`id`, `user`, `message`, `options`, `topic`) | `thoughts` + joined `options` | `author_id` is nullable and left `NULL` for AI-seeded thoughts (`is_ai_generated = true`) — there's no fake "system" user. |
| `OptionItem` (`id`, `title`, `counter`) | `option_results` (view over `options` + `answers`) | `counter` = `seed_votes` (from the AI JSON's `votes`) **+** real votes cast in `answers`. Always read from `option_results`, not the raw `options` table, so percentages include real users' votes. |

## Auth: anonymous by default

Per your choice, every install signs in anonymously via Supabase Auth (`supabase.auth.signInAnonymously()`), no email/password screen for first users. That gives every device a stable `auth.uid()` immediately, which is what `thoughts.author_id`, `answers.user_id` and RLS all key off. A `handle_new_user` trigger creates the matching `profiles` row automatically, with a placeholder name like `Anon-3f9a2c`. You can let users set a real `name` later (update their own `profiles` row — RLS already allows it) without changing anything else in the schema, and later upgrade an anonymous session to email/password with `supabase.auth.updateUser()` if you add real accounts.

## Voting: one real vote per user per thought

`answers` has a `unique (thought_id, user_id)` constraint, so a second insert for the same thought fails — catch that in the client as "already voted" (e.g. to keep `ThoughView`'s `selected` state showing what they picked instead of retrying). `option_results.votes` is `seed_votes + count(answers)`, so `OptionRowView`'s percentage math (`option.counter / total`) keeps working unchanged once `counter` is fed from that view.

## Suggested next steps in the iOS app

The repo already has empty `Data/Network`, `Data/Local` and `Data/Providers` folders that look set up for exactly this:

1. **Add the Supabase Swift SDK** (`supabase-swift`) via SPM, and put the client in `Data/Network/SupabaseClient.swift` — a singleton configured with your project URL + **anon** key (never the service role key) from an untracked `Config.xcconfig` or plist, not hardcoded.
2. **Sign in anonymously on launch** — call it once from `SameHereApp` (or a small bootstrap step before `SHTabView` appears) and stash the session; `supabase-swift` persists it across launches automatically.
3. **DTOs** in `Data/Models` (e.g. `ThoughtDTO`, `OptionResultDTO`, `ProfileDTO`) that decode the snake_case columns, plus small mapping functions to your existing `Thought` / `OptionItem` / `User` structs so the UI layer (`HomeView`, `ThoughView`, `OptionRowView`) doesn't need to change at all.
4. **A `ThoughtsRepository`** in `Data/Providers` with something like `fetchThoughts(topic:)`, `createThought(message:topic:options:)`, `vote(thoughtId:optionId:)`, `fetchMyThoughts()` — then swap `MockThoughs.getMockData()` for it in `HomeViewModel.loadData()` and `MyThoughtsViewModel.loadData()` / `createThought()`.
5. **`vote(thoughtId:optionId:)`** should catch the unique-constraint error from `answers` and treat it as "already answered" rather than a hard failure.

Happy to build any of these Swift pieces next — just say which one to start with.
