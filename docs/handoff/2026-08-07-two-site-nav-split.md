# Handoff — two websites from one Flutter app (2026-08-07)

Read this first if you are picking up where the previous session left off. The
full design rationale lives in
`docs/superpowers/specs/2026-08-07-two-site-nav-split-design.md`; this file is
the state of play.

## What was asked for

Two web apps from this single codebase, differing only in which screens are
reachable:

| Site | Nav (in order) | Lands on | URL |
| --- | --- | --- | --- |
| **ops** (website 1) | Queue, History, Profile | Queue | https://aiaccountant-b60ed.web.app |
| **rate** (website 2) | Rate, Report, Profile | Rate | https://aiaccountant-rate.web.app |

## Status: done and live

Both sites are built, deployed and verified (the deployed `main.dart.js` hashes
differ, and website 2's matches a local `SITE=rate` build byte for byte).

Everything below is committed on branch `feat/two-site-nav-split`, branched from
`update/edit_and_add_rate-disc_ui_updated`. Nothing is merged to `master`.

## How it works

`lib/core/site_config.dart` is the whole mechanism:

- `enum AppDestination { camera, queue, history, report, profile, rate }`
- `SiteConfig` = a title, an ordered `List<AppDestination>`, and a `home`.
- Three configs: `full` (everything — Android, `flutter run`, bare web builds),
  `ops`, `rate`.
- Chosen at build time by `--dart-define=SITE=ops|rate`. An absent or
  unrecognised value resolves to `full`, so a typo ships the whole app rather
  than a blank one.

Everything else derives from that list: `app_shell`'s `IndexedStack` children
(`_screenFor`), `AppBottomNav`, and `AppSideNav` all iterate
`SiteConfig.current.destinations`. An "index" anywhere in nav code means a
position in that list and nothing more.

**This gates navigation, not compilation.** `_screenFor` switches over all six
destinations regardless of site, so every screen is still in both bundles.
Neither site is a security boundary — auth and Supabase RLS are, and both sites
share the same Firebase auth and the same Supabase project.

### Why the enum exists

The nav used to be index-based and positionally coupled across three files
(`constants.dart`'s `bottomNavItems`, `app_shell`'s `IndexedStack`,
`app_side_nav`'s hardcoded `_item(3)` / `_item(4)`). Restoring the Report tab
shifted Profile from 3 to 4 and silently broke the rail and two tests. Two sites
with different screen sets made that unmaintainable. `kCameraNavIndex`,
`kQueueNavIndex` and `bottomNavItems` are gone; `navItemFor` (a destination →
label/icon map) replaces the list.

### Rate on website 2

`StockInfoScreen` takes optional `currentIndex` + `onNavSelected`. With them it
wraps its existing body in `ScreenFrame`; without them it keeps its own
`Scaffold` and behaves exactly as the standalone page. The `#/stock-info?item=…`
deep link still renders that bare standalone page on both sites, so `main.dart`
routing is unchanged.

## Build and deploy

```powershell
.\build_ops.ps1     # website 1 → aiaccountant-b60ed.web.app
.\build_rate.ps1    # website 2 → aiaccountant-rate.web.app
.\build_test.ps1    # the FULL app (no SITE flag) → the ops target
```

Both site builds write to `build/web`, so each script builds *then* deploys and
the two must never run concurrently.

Hosting is two targets in one Firebase project (`aiaccountant-b60ed`), mapped in
`.firebaserc`: `ops` → `aiaccountant-b60ed`, `rate` → `aiaccountant-rate`.
`firebase.json`'s `hosting` is now an **array**, so a bare
`firebase deploy --only hosting` would push one bundle to both sites — always
name the target (`hosting:ops` / `hosting:rate`). `build_test.ps1` was updated
for this.

## Also changed this session (same branch)

Two things restored before the split work, both of which the split depends on:

1. **Purchase/Sale** uncommented everywhere — Queue tabs, History tabs, the
   camera capture picker, and `app_shell`'s `_activeQueueType` (which drives the
   scan badge).
2. **Report nav** restored — `constants.dart`, `app_shell`'s stack, the rail.
   Website 2 needs Report reachable.

Then, after seeing site 1 live, **both standalone Stock Info launchers were
removed**: the `Rate` entry in the desktop rail and the cube button at the
top-right of the Queue tab bar. Stock info is reached from the ⓘ inside a
voucher's items. This removal is global, so the Android/`full` build lost the
tab-bar cube too.

## Known issues / open items

- **`test/widget_test.dart` fails and has since before this work.** It pumps
  `AccountantApp`, which reads `FirebaseAuth.instance`. Left alone deliberately.
  The suite is 69 passed / 1 failed; that 1 is this.
- **Both sites build with no env file**, matching `build_test.ps1`, so they ship
  `lib/core/config.dart`'s defaults — the **testing** Supabase project. Same as
  the live site before this work. `env/prod.json` still carries a
  `_PROD_PENDING_CONFIRM` placeholder backend, so promoting either site to a
  real prod environment is unfinished business.
- **Website 2's live bundle is one commit behind.** The launcher removal did not
  change anything it renders (no Queue screen; its rail showed Rate as a real
  destination), so it was not redeployed. Run `.\build_rate.ps1` to resync.
- **`AppTopTabs.trailing`** now has no callers. Harmless, but it is dead API.
- **`AccountantShell` has no `SiteConfig` test seam** (`AppBottomNav` and
  `AppSideNav` do, via an optional `site` parameter). The shell cannot be pumped
  in a test at all — it reaches Firebase and Supabase on construction — so the
  parameter would be config no test could use.

## Where things are

| Concern | File |
| --- | --- |
| Site definitions | `lib/core/site_config.dart` |
| Nav labels/icons | `lib/core/constants.dart` (`navItemFor`) |
| Screen wiring | `lib/features/shell/app_shell.dart` (`_screenFor`) |
| Nav bars | `lib/shared/app_bottom_nav.dart`, `lib/shared/app_side_nav.dart` |
| Rate screen | `lib/features/stock/stock_info_screen.dart` |
| Hosting | `firebase.json`, `.firebaserc` |
| Deploy | `build_ops.ps1`, `build_rate.ps1`, `build_test.ps1` |
| Tests | `test/site_config_test.dart`, `test/app_bottom_nav_test.dart`, `test/app_side_nav_test.dart` |
| Design rationale | `docs/superpowers/specs/2026-08-07-two-site-nav-split-design.md` |

## Adding or moving a screen

Edit the destination list in `lib/core/site_config.dart`, add a `navItemFor`
entry if the destination is new, and add a `_screenFor` case. Nothing else needs
touching — that is the point of the refactor. `test/site_config_test.dart` pins
each site's list, so update it in the same change.
