# Auth integration — Same Here + AuthFeature

What is wired, what you still have to do, and where to go next.

Companion docs: `docs/supabase-integration.md` (schema and seeding),
`../AuthFeature/README.md` (the package), `../AuthFeature/REVIEW.md` (what was
fixed in it).

---

## Why guests

Same Here asks people to share a thought. A sign-up form in front of that ask is
where most first-time visitors leave — and the ones who leave are exactly the
data the app is trying to collect. A guest account removes it: one tap, a real
`auth.uid()`, and they are writing. The ask for an email moves to *after* they
have something worth keeping.

The cost is honest and the UI states it: a guest lives only in this device's
Keychain. Reinstall, or switch phones, and they are gone.

---

## 1. You do this once (Xcode, ~1 minute)

1. **Fill in the credentials.** `Config/Secrets.xcconfig` already exists (it's
   git-ignored; `Config/Secrets.example.xcconfig` is the committed template).
   Replace the two placeholder values:

   ```
   SUPABASE_HOST = abcdefghijkl.supabase.co     ← no https://, see the file header
   SUPABASE_ANON_KEY = eyJhbGciOi...
   ```

   Both are in the dashboard under **Project Settings → Data API**. Use the
   **anon / publishable** key. The `service_role` key must never go in the app —
   it bypasses row level security.

2. **Point the project at it.** In Xcode: select the **SameHere** project (the
   blue icon, not the target) → **Info** tab → **Configurations** → expand both
   **Debug** and **Release** and set the project's configuration file to
   **Secrets**.

   If `Secrets` isn't in the dropdown, drag `Config/Secrets.xcconfig` into the
   Project navigator first — **uncheck "Add to targets"**, so it stays out of the
   app bundle.

3. **Clean and run** (⇧⌘K, then ⌘R).

If step 2 is missed the app doesn't crash or fail silently — it shows a
"Not configured yet" screen naming the missing key and these steps.

### Why the host is stored without `https://`

In an xcconfig, `//` starts a comment. `SUPABASE_URL = https://abc.supabase.co`
silently truncates to `https:`, and every request 404s against nothing. Storing
the bare host sidesteps it; `SupabaseConfig` puts the scheme back. There's a
`SUPABASE_URL` escape hatch (with the `$()` trick) documented in the xcconfig
header for local or self-hosted Supabase.

---

## 2. Supabase dashboard

- **Authentication → Providers → Anonymous sign-ins → on.** Without it every
  guest tap fails with "Guest sign-in is not available right now."
- **Authentication → Providers → Email → on.** "Confirm email" either way:
  - off → sign-up and guest upgrade complete immediately;
  - on → the register screen shows "check your inbox", and an upgrading guest
    stays a guest until they click the link. Both are handled.
- **Attack protection → Captcha → off** (the package doesn't send a captcha
  token with the anonymous sign-in).

## 3. Database

Run `supabase/auth_guests.sql` in the SQL editor, after `supabase/schema.sql`.
It adds `profiles.is_guest`, and — the part that matters — **the UPDATE trigger
that `schema.sql` is missing**: the existing trigger creates a profile when a
user is inserted, but nothing reacts when a guest later attaches an email, so
without it a converted user keeps their `Anon-3f9a2c` name and empty email
forever.

No RLS policy needs to change. A guest is an ordinary user as far as
`auth.uid()` is concerned.

---

## 4. What the code does now

```
SameHereApp
└── RootView                        ← the gate; switches on AppCoordinator.phase
    ├── .launching       LaunchView
    ├── .misconfigured   StatusView  ("Not configured yet" + the fix)
    ├── .unreachable     StatusView  ("Your account is still on this device")
    ├── .signedOut       AuthFlowView          [AuthFeature]
    └── .signedIn        SHTabView
                           .environment(services)     ← AppServices
                           .environment(coordinator)  ← AppCoordinator
```

| File | Job |
|---|---|
| `App/AppCoordinator.swift` | What the app is showing. Owns the graph, restores the session at launch. |
| `App/AppServices.swift` | The composition root: config → auth service → auth coordinator → client → repositories. |
| `App/RootView.swift` | The gate, plus the launch and failure screens. |
| `Data/Config/SupabaseConfig.swift` | Info.plist → `SupabaseAuthConfiguration`, with an error that explains itself. |
| `Data/Network/SupabaseClient.swift` | PostgREST. Fresh token per request. |
| `Data/Providers/ThoughtsRepository.swift` | `fetchThoughts`, `fetchMyThoughts`, `vote`. |
| `Data/Models/ThoughtDTO.swift` | Wire shapes, kept off the domain models. |
| `Modules/Account/` | Account menu, guarded sign-out, guest-upgrade sheet. |
| `Modules/Shared/GuestBanner.swift` | The "save your account" nudge on My Thoughts. |

### On coordinators — the thing worth not getting wrong

You asked whether to write a coordinator for login. There is already one:
`AuthFeature.AuthCoordinator` owns the auth route, the session, and builds both
view models. Writing a second one in the app would be duplicating it.

What the app actually needed was one level *above* that — a thing that decides
whether the auth flow or `SHTabView` is on screen, and that owns the objects
which only exist once. That's `AppCoordinator` + `AppServices`. Two coordinators
total, with a clean split:

- `AuthCoordinator` — **the login flow**: which auth screen, what session came out.
- `AppCoordinator` — **the app**: configuration, launch, and the gate.

### And the one I'd push back on

> "come back and start with the SHTabView and **pass the session**"

Pass the *services*, not the session. An `AuthSession` is a snapshot whose access
token lives about an hour. A view model that captures one at sign-in works
perfectly for your whole development session and starts handing real users 401s
an hour in — the worst kind of bug, because it never reproduces at your desk.

So `SupabaseClient` asks for a token per request:

```swift
tokenProvider: { try await authService.validAccessToken() }
```

`validAccessToken()` returns the cached token when it's healthy, refreshes when
it isn't, and collapses concurrent callers into one refresh.

The session is still right there for identity and display — `services.session`,
`services.currentUser`, `services.isGuest` — which is all a view should want from
it.

---

## 5. Swapping the view models onto real data

The repository is wired and ready; `HomeViewModel` and `MyThoughtsViewModel` are
still on `MockThoughs`. When you're ready, the change is small. `HomeViewModel`:

```swift
@Observable
final class HomeViewModel {
    var thoughts: [Thought] = []
    var loadError: String?

    private let repository: ThoughtsRepository
    private let currentUserID: UUID

    init(repository: ThoughtsRepository, currentUserID: UUID) {
        self.repository = repository
        self.currentUserID = currentUserID
    }

    func loadData() async {
        do { thoughts = try await repository.fetchThoughts() }
        catch { loadError = error.localizedDescription }
    }

    func answerItem(_ thought: Thought, option: UUID) async {
        do {
            try await repository.vote(thoughtID: thought.id, optionID: option, userID: currentUserID)
        } catch SupabaseRequestError.duplicate {
            // Already voted — the unique constraint doing its job. Not an error.
        } catch {
            loadError = error.localizedDescription
        }
        thoughts.removeAll { $0.id == thought.id }
    }
}
```

`HomeView` currently does `@StateObject private var viewModel = HomeViewModel()`,
which can't see the environment at init. Two options:

```swift
// Simplest: build it where the environment is available.
struct HomeView: View {
    @Environment(AppServices.self) private var services
    @State private var viewModel: HomeViewModel?

    var body: some View {
        content
            .task {
                if viewModel == nil, let user = services.currentUser {
                    viewModel = HomeViewModel(repository: services.thoughts, currentUserID: user.id)
                }
                await viewModel?.loadData()
            }
    }
}
```

```swift
// Or keep @State and inject once, since SHTabView already has the services:
Tab("Home", systemImage: "house") {
    HomeView(viewModel: HomeViewModel(repository: services.thoughts,
                                      currentUserID: services.currentUser!.id))
}
```

Keep `MockThoughs` for previews either way.

Still to write when you need them: `createThought(message:topic:options:)` (insert
the thought, then its options — `CreateThoughSheet.saveIdea()` is the stub waiting
for it) and topic filtering.

---

## 6. Two rules the UI has to keep

- **Never sign a guest out silently.** `AccountMenu` asks first and offers
  "Save my account instead". Any new sign-out path needs the same guard; there is
  no credential to come back with.
- **Don't promise the upgrade landed until it has.** With email confirmation on,
  `linkAccount` returns a session that is *still* a guest until the link is
  clicked. `UpgradeAccountSheet` only dismisses when `isGuest` flips.

---

## 7. Checklist

- [ ] `Config/Secrets.xcconfig` filled in
- [ ] Project → Info → Configurations set to **Secrets** for Debug **and** Release
- [ ] Anonymous sign-ins enabled in the dashboard
- [ ] `supabase/schema.sql` applied
- [ ] `supabase/auth_guests.sql` applied
- [ ] Clean build folder, run — you should land on the login screen with
      "Continue as guest"
- [ ] Sign in as a guest, quit, relaunch — you should land straight in `SHTabView`
- [ ] `purge_abandoned_guests` scheduled (optional)

## 8. Known loose end

`Modules/Shared/BadgeIconView.swift` draws `Image("hand")`, and there's no `hand`
image set in `Assets.xcassets` — so it renders as an empty circle. The launch and
auth screens use the package's badge with an SF Symbol instead. Add the asset and
swap them over when the artwork is ready.
