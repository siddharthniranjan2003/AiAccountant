# Two websites from one Flutter app — design

Date: 2026-08-07
Branch: `update/edit_and_add_rate-disc_ui_updated`

## Goal

Ship two web apps from this single codebase, differing only in which screens are
reachable:

| Site | Nav (in order) | Lands on | URL |
| --- | --- | --- | --- |
| **ops** | Queue, History, Profile | Queue | `aiaccountant-b60ed.web.app` (the existing URL) |
| **rate** | Rate, Report, Profile | Rate | `aiaccountant-rate.web.app` (new Hosting site) |

The Android app and `flutter run` are unaffected: with no site flag the app is
exactly what it is today (Camera, Queue, History, Report, Profile).

## Decisions

These were settled during brainstorming; they are the reason the design looks
the way it does.

1. **Build-time flag**, not runtime hostname detection. A `SITE` dart-define
   alongside the existing `--dart-define-from-file` mechanism, so which site a
   bundle is is fixed at compile time rather than guessed from the URL.

   Note what this does *not* buy: every screen is still compiled into both
   bundles. `_screenFor` in `app_shell.dart` switches over all six destinations
   regardless of site, so `ReportScreen` and the rest stay reachable from the
   tree and survive tree-shaking. The sites differ in what is *navigable*, not
   in what ships. Treat neither site as a security boundary.
2. **Rate is a real in-app screen** on site `rate` — the stock-item search
   rendered inside the shell, not the standalone popup window.
3. **Site `ops` keeps the popup**. The Stock Info cube in the Queue tab bar and
   the ⓘ on voucher item rows still open the reusable `#/stock-info` window
   there, because that lookup happens *while* editing a voucher and benefits
   from a second window.
4. **The `#/stock-info` deep link keeps rendering the bare standalone page** on
   both sites. `main.dart` does not change.
5. **Android unchanged** — the APK keeps every destination.
6. **Same login, same data.** Both sites use the same Firebase auth and the same
   Supabase project. Only reachable screens differ.
7. **Profile sits last** on both sites.
8. **One nav order per site**, shared by the phone bottom bar and the desktop
   rail. This changes the current desktop rail order (today: Queue, Rate,
   Camera, Report, Profile, History) to follow the destination list.
9. **Different browser tab title per site**; nothing else differs visually.
10. **Two Hosting sites in one Firebase project** (`aiaccountant-b60ed`), via
    Hosting targets.
11. **Deploy scripts build with no env file**, exactly like `build_test.ps1`
    does today, so the live sites keep pointing at whatever `config.dart`
    defaults to. Choosing a real prod env is a separate problem — `env/prod.json`
    still carries a `_PROD_PENDING_CONFIRM` placeholder backend.

## Architecture

### The problem being solved

Today the nav is index-based and positionally coupled across three files:
`bottomNavItems` in `core/constants.dart`, the `IndexedStack` children in
`features/shell/app_shell.dart`, and hardcoded `_item(3)` / `_item(4)` calls in
`shared/app_side_nav.dart`. Restoring the Report tab on 2026-08-07 shifted
Profile from index 3 to 4 and required hand-editing the rail and two tests.

Two sites with different nav sets make those indices differ per build, so the
coupling has to go.

### Named destinations

New file `lib/core/site_config.dart`:

```dart
enum AppDestination { camera, queue, history, report, profile, rate }

@immutable
class SiteConfig {
  const SiteConfig({
    required this.title,
    required this.destinations,
    required this.home,
  });

  /// Browser tab title / app title.
  final String title;

  /// Ordered — this IS the nav order, for both the bottom bar and the rail.
  final List<AppDestination> destinations;

  /// Where the app opens. Must be present in [destinations].
  final AppDestination home;

  static const full = SiteConfig(
    title: 'AI Accountant',
    destinations: [
      AppDestination.camera,
      AppDestination.queue,
      AppDestination.history,
      AppDestination.report,
      AppDestination.profile,
    ],
    home: AppDestination.queue,
  );

  static const ops = SiteConfig(
    title: 'AI Accountant — Queue',
    destinations: [
      AppDestination.queue,
      AppDestination.history,
      AppDestination.profile,
    ],
    home: AppDestination.queue,
  );

  static const rate = SiteConfig(
    title: 'AI Accountant — Rate',
    destinations: [
      AppDestination.rate,
      AppDestination.report,
      AppDestination.profile,
    ],
    home: AppDestination.rate,
  );

  static const _flag = String.fromEnvironment('SITE', defaultValue: 'full');

  static SiteConfig get current => switch (_flag) {
    'ops' => ops,
    'rate' => rate,
    _ => full,
  };
}
```

An unrecognised or absent `SITE` resolves to `full`, so a bare build is today's
app. `full` keeps Camera because Android needs it; `ops` omits it because that
site is web-only and the bottom bar already hides Camera on web.

### What an "index" means afterwards

`currentIndex` stays an `int`, but it is now strictly a position in
`SiteConfig.current.destinations`. Screens (Queue, History, Report, Profile,
Camera) keep their `int currentIndex` / `ValueChanged<int> onNavSelected`
signatures and stay ignorant of what the number means — they only forward it to
`ScreenFrame`. This keeps the change confined to the shell and the two nav bars.

### Injecting the config for tests

`SiteConfig.current` is resolved from a compile-time define, so a test process
cannot vary it. `AppBottomNav` and `AppSideNav` therefore take an optional
`SiteConfig site` parameter defaulting to `SiteConfig.current`. Tests pass a
config explicitly; production code never does.

`AccountantShell` does *not* get the same seam, and `ScreenFrame` does not
forward one. The shell can't be pumped in a test at all (it reaches Firebase and
Supabase on construction), so the parameter would be config no test could use.
The nav bars are where site-dependent layout actually lives and where the
regressions happened, so that is where the seam is.

## File-by-file changes

### `lib/core/site_config.dart` (new)
As above.

### `lib/core/models.dart`
`BottomNavItemData` gains an optional icon *widget* so Rate can reuse the
existing `StockCubeIcon` (a `CustomPaint`, not an `IconData`):

```dart
const BottomNavItemData({required this.label, this.icon, this.iconBuilder})
  : assert(icon != null || iconBuilder != null);
```

### `lib/core/constants.dart`
- `bottomNavItems` (the positional const list) is replaced by
  `const Map<AppDestination, BottomNavItemData> navItemFor`, covering all six
  destinations including `rate` (label `Rate`, the stock cube icon).
- `kCameraNavIndex` and `kQueueNavIndex` are deleted. Nothing needs a fixed
  index once destinations are named.
- The "positionally aligned / uncommenting here REQUIRES uncommenting there"
  comments are deleted with them — they no longer describe reality.

### `lib/features/shell/app_shell.dart`
- `_currentIndex` initialises to
  `SiteConfig.current.destinations.indexOf(SiteConfig.current.home)`.
- `_onNavSelected` routes to the scanner when
  `destinations[index] == AppDestination.camera` instead of comparing to
  `kCameraNavIndex`.
- The hand-written `IndexedStack` children list becomes
  `destinations.map(_screenFor).toList()`, where `_screenFor` is a `switch` over
  `AppDestination` returning the existing screen widgets with their existing
  arguments. `rate` returns the embedded `StockInfoScreen` (below).
- Because `full` and `ops` never include `rate`, and `rate` never includes
  `queue`, the per-screen service wiring (push queue, scan jobs) is only
  constructed for destinations that exist on the current site.

### `lib/shared/app_bottom_nav.dart`
Iterates `SiteConfig.current.destinations`, looking labels/icons up in
`navItemFor`. Keeps the existing "hide Camera on web" guard.

### `lib/shared/app_side_nav.dart`
- Iterates the same destination list; the hardcoded `_item(3)` / `_item(4)` and
  the comment block explaining the hardcoding are deleted.
- `_StockInfoNavAction` (the popup launcher labelled "Rate") is rendered
  immediately after Queue **only when `rate` is not in the site's destinations**
  — so `full` and `ops` keep today's popup and `rate` doesn't get a duplicate
  entry beside its real Rate tab.
- Camera stays hidden on web via the existing `if (!kIsWeb)` guard.

### `lib/features/stock/stock_info_screen.dart`
Gains optional `currentIndex` + `onNavSelected`. Its `build` currently returns
`Scaffold(body: SafeArea(Padding(Column(...))))`; the `Column` is extracted to a
local and wrapped in either the existing `Scaffold` (deep-link / popup path, both
params null) or `ScreenFrame` (embedded path). No other behaviour changes: the
search bar, the item panels, the party chip and the hashchange retarget listener
are untouched.

Note: on site `rate` the screen lives in the shell's `IndexedStack` from boot, so
its hashchange listener is alive for the session. That is harmless — nothing on
that site mutates the URL fragment.

### `lib/main.dart`
`MaterialApp.title` becomes `SiteConfig.current.title`. The `#/stock-info` route
check is unchanged. `web/index.html`'s static `<title>` is left generic; it is
only visible for the moment before Flutter boots.

### Hosting
- One-time: `firebase hosting:sites:create aiaccountant-rate`.
- `.firebaserc` gains a `targets` block under project `aiaccountant-b60ed`
  mapping `ops` → `aiaccountant-b60ed` and `rate` → `aiaccountant-rate`.
- `firebase.json`'s `hosting` object becomes a two-element array, each element
  carrying `target` plus the current `public` / `ignore` / `rewrites` /
  `headers` values verbatim.

### Build scripts
Two new PowerShell scripts modelled on `build_test.ps1`:

```powershell
# build_ops.ps1
$ErrorActionPreference = 'Stop'
flutter build web --release --dart-define=SITE=ops
if ($?) { firebase deploy --only hosting:ops --project aiaccountant-b60ed }
```

`build_rate.ps1` is the same with `SITE=rate` and `--only hosting:rate`. Both
builds write to `build/web`, so each script must build and deploy in sequence and
the two must never run concurrently — a comment in each script says so.

`build_test.ps1` keeps building the full app with no `SITE` flag, but its deploy
line moves from `--only hosting` to `--only hosting:ops`: once `firebase.json`
holds two targets, the bare form would push one bundle to *both* sites.

## Testing

- **`test/site_config_test.dart` (new)** — each site's destination list and
  order is exactly as specified; `home` is a member of `destinations`; an
  unknown `SITE` value resolves to `full`.
- **`test/app_bottom_nav_test.dart`** — reworked to assert the rendered labels
  per site rather than one hardcoded five-tab list, and that a tap reports the
  position within that site's list.
- **`test/app_side_nav_test.dart` (new)** — the rail renders the site's
  destinations in order, and the Rate popup action appears only on sites where
  `rate` is not a destination.
- Existing tests must stay green. `test/widget_test.dart` is already failing on
  `master` (it pumps `AccountantApp`, which reads `FirebaseAuth.instance`) and is
  explicitly out of scope.

Site-parameterised widget tests rely on the optional `SiteConfig` parameter
described under *Injecting the config for tests*.

## Out of scope

- Choosing real production backend/Supabase targets for the deployed sites
  (`env/prod.json` remains unconfirmed).
- Fixing `test/widget_test.dart`.
- Any change to auth, Supabase schema, queue/history/report screen internals, or
  the Purchase/Sale tabs restored earlier today.
- Custom domains for either site.

## Risks

- **Desktop rail order changes** for the existing app (`full`): History moves
  above Profile and the rail follows the bottom-bar order. Accepted deliberately.
- **`firebase.json` becoming an array** changes deploy invocation: bare
  `firebase deploy --only hosting` will no longer be unambiguous, so any muscle
  memory or CI using it must move to `hosting:ops` / `hosting:rate`.
- **A new Hosting site is an outward-facing, billable resource.** Creating
  `aiaccountant-rate` needs explicit go-ahead before it is run.
