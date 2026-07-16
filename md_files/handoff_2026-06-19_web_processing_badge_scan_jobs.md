# Handoff — 2026-06-19 — Web "Processing…" badge via shared `scan_jobs` realtime (+ job_id close, lifecycle resync)

Branch: **`feature/scan-loading-indicators`**. All Flutter changes are **uncommitted** in
the working tree. Parsing + migration changes live in the **separate** repo
`D:\Desktop\TallyBridge` (parsing) and were authored there.

---

## 0. TL;DR
- **Goal:** the "Processing…" badge (count + clock-pie timer) that worked on the Android
  app must ALSO show on the **web** version, driven by realtime. **Mobile is the only
  producer** (it's the only thing that scans/uploads); **web is a pure observer**.
- **Why it didn't work on web before:** the badge's +1 was a **local-only** event on the
  scanning device. Web had no way to learn a scan started (no DB row exists until parsing
  finishes ~105s later).
- **Fix (built):** a shared **`scan_jobs`** table mirrored over Supabase realtime. Mobile
  inserts a row on scan-send (badge +1 on every client); the **parsing service deletes the
  row by `job_id`** when it inserts the `push_queue` invoice row (badge −1 on every client).
  Both mobile + web are pure subscribers. **`job_id` close was chosen** (robust): exact
  correlation, survives the phone going offline.
- **Status:** built + **deployed to BOTH testing and deployment** (migrations applied,
  parsing services redeployed). **Testing e2e-verified on device.** Deployment realtime
  confirmed working.
- **A late client-only fix** (lifecycle resync on foreground) is **implemented + analyze-clean
  but NOT yet rebuilt/shipped** — see §6.

---

## 1. The architecture (the whole point)

```
        MOBILE (producer)                              WEB (pure observer)
              │                                              │
  scan ──► INSERT scan_jobs{type}  ──┐                       │
           (badge +1)                ├── Supabase realtime ──┤  badge from
           row.id = job_id           │   INSERT / DELETE     │  count(scan_jobs)
           │                         │                       │  timer from oldest
  parse POST  ...?...&job_id=<id> ───┼──► PARSING service     │  created_at
  (mobile, dart:io, ~105s)          │    (handler.py):        │
           │                         │    OCR → push_queue ───┼──► push_queue INSERT
           │                         │    INSERT, then        │     (the invoice row)
           │                         │    DELETE scan_jobs    │
           ▼                         │    WHERE id=job_id ────┘  (badge -1 everywhere)
   badge reflects scan_jobs ◄────────┘
```

- **+1** mobile inserts a `scan_jobs` row the instant a scan is sent → realtime INSERT echo
  → badge climbs on the phone AND every open web session.
- **−1** the parsing service deletes the row by `id = job_id` right after it inserts the
  `push_queue` invoice row → realtime DELETE echo → badge drains everywhere. **No client
  decrements.**
- **Safety:** clients ignore `scan_jobs` rows older than **300s** (TTL sweep), so a missed
  DELETE can't wedge the badge forever.
- The badge/pie UI (`queue_loading_tile.dart`, `queue_screen.dart`) is **unchanged** — it
  just gets `count` + `oldestStart` fed from the shared subscription on both platforms.

---

## 2. Files changed — Flutter (`aiaccountant`, branch `feature/scan-loading-indicators`)

- **NEW `lib/data/scan_jobs_service.dart`** — process-level singleton `ScanJobsService`.
  Subscribes to `scan_jobs` realtime (INSERT/DELETE). API: `countFor(type)`,
  `oldestStartFor(type)`, `startScan(type) → Future<String? jobId>` (mobile insert, optimistic
  local add deduped by id), `subscribe()` (idempotent channel; **always `_refresh()`s first**
  so a recreated shell catches up), `resync()` (re-fetch). 300s sweep `Timer.periodic`. **No
  `dart:io`, no HTTP** → compiles + runs on web.
- **NEW `lib/data/scan_uploader.dart`** — mobile-only top-level `sendScanToParser(pdfPath, url)`
  (the `dart:io` `File.readAsBytes` + `http.post` parse POST, `Content-Type: application/pdf`,
  300s timeout, fire-and-forget). Top-level so it survives shell recreation.
- **DELETED `lib/data/scan_inflight_service.dart`** — superseded by the two files above
  (was the old local-count + HTTP service).
- **`lib/features/shell/app_shell.dart`**
  - Uses `ScanJobsService.instance` (was `ScanInFlightService`).
  - `_enqueueScan` is now async: `jobId = await _scanService.startScan(type)`, append
    `&job_id=$jobId` to the parse URL, `unawaited(sendScanToParser(pdfPath, url))`.
  - `initState`: `_scanService.subscribe()` + `addListener`; removed the old
    `onRowInserted → notifyInvoiceArrived` wiring.
  - **Lifecycle resync (§6):** `with WidgetsBindingObserver`; `addObserver`/`removeObserver`;
    `didChangeAppLifecycleState(resumed)` → `_scanService.resync()` + `_pushQueueService.refresh()`.
- **`lib/data/push_queue_service.dart`** — removed the now-orphaned `onRowInserted`
  callback (field, ctor param, and the `.call` in the INSERT handler). The INSERT/UPDATE/
  DELETE realtime handlers and `refresh()` are otherwise unchanged.

`flutter analyze lib` → **No issues found!** `flutter build web` → **√ Built build\web**
(verified before AND after these changes — see §5).

## 3. Files changed — parsing (`D:\Desktop\TallyBridge\parsing`)

- **`server/handler.py`**
  - New helper `delete_scan_job(job_id)` (next to `_supabase_session`): UUID-validates
    `job_id`, then `DELETE {SUPABASE_URL}/rest/v1/scan_jobs?id=eq.<job_id>` with the service
    key (`SUPABASE_KEY`, bypasses RLS). Best-effort (all exceptions swallowed → falls back to
    the client 300s TTL). No-op if no `job_id` (older app builds / direct callers).
  - `do_POST`: reads `job_id = optional_query_string(self.path, "job_id")` near the top.
  - Calls `delete_scan_job(job_id)` right after each **successful** `post_to_push_queue`
    (purchase path ~line 2015, sale path ~line 2141).
  - Entry point `n8n_minicpm_server.py` → `from server.handler import main` (so this is what
    ships). `python -m py_compile server/handler.py` → OK.

## 4. Migration — Supabase (`D:\Desktop\TallyBridge\backend\supabase_scan_jobs.sql`, NEW)

```sql
create table if not exists scan_jobs (
  id uuid primary key default gen_random_uuid(),
  type text not null check (type in ('sale','purchase')),
  created_at timestamptz not null default now()
);
create index if not exists idx_scan_jobs_created_at on scan_jobs(created_at desc);
alter table scan_jobs enable row level security;
-- mirrors push_queue's permissive single policy (all roles): anon reads/inserts,
-- service-keyed parsing deletes
create policy "scan_jobs full access" on scan_jobs for all using (true) with check (true);
alter publication supabase_realtime add table scan_jobs;  -- wrapped in a duplicate_object guard
```
Single-tenant per project (no `company_id`), mirroring `push_queue`. Row `id` IS the `job_id`.

---

## 5. Deployments done (all VERIFIED)

| Env | Supabase (migration) | Parsing Cloud Run | Status |
|---|---|---|---|
| **testing** | `yynuuysvjeipawzfbeme` ✅ applied | `tallybridge-parsing` proj `tally-bridge-testing-env` (828647628834) → rev **`…-00007-67d`**, `SUPABASE_URL=yynuuysvjeipawzfbeme`, healthy ✅ | **e2e-verified on device** |
| **deployment** | `ztugwhevemibdrzqafyw` ✅ applied | `tallybridge-parsing` proj `tally-bridge-deployment-env` (822222628942) → rev **`…-00005-774`**, `SUPABASE_URL=ztugwhevemibdrzqafyw`, healthy ✅ | realtime confirmed working |

**Deploy command used (source-based, env preserved — DO NOT pass `--env-vars-file`):**
```
gcloud run deploy tallybridge-parsing --source "D:/Desktop/TallyBridge/parsing" \
  --region asia-south1 --project <PROJ> --account <ACCT>
```
Both deploys auto-routed 100% traffic to the new revision.

### GCP / env facts (verify before any future redeploy)
- **testing**: gcloud config `testing-riplara`, account `testing.riplara@gmail.com`, project
  `tally-bridge-testing-env` (828647628834).
- **deployment**: config `deployment-riplara`, account `deployment.riplara@gmail.com`,
  project `tally-bridge-deployment-env` (822222628942). (This was the active config; I passed
  explicit `--project`/`--account` so it didn't matter.)
- **§5d — `parsing.env.yaml` is STALE / WRONG**: it points `SUPABASE_URL` →
  `ztugwhevemibdrzqafyw` and push-queue → backend `950406969086`. **Never deploy parsing with
  `--env-vars-file parsing.env.yaml`** — it would point the service at the wrong DB/backend.
  The LIVE services already have correct env vars (set at an earlier deploy); `--source`-only
  preserves them. `.env` is NOT bundled (`.gcloudignore` excludes it; creds come from Cloud
  Run env vars).
- **Web build compiles fine** despite bare `dart:io` imports (`report_screen`,
  `invoice_image_store`, `camera_screen`). `dart:io` only throws at runtime if a web code path
  calls `File`, which scan/capture never do. So **no "web hygiene" work was needed** (an early
  wrong assumption that I disproved by actually running `flutter build web`).
- **Supabase tenancy**: single-company per project. Client auth = **Firebase** (not Supabase),
  so Supabase access is **anon-key only**; `push_queue` RLS is permissive (`FOR ALL USING
  (true)`, all roles). `scan_jobs` mirrors that.
- The deployment Supabase `ztugwhevemibdrzqafyw` = **"rohan.psom@gmail.com's Project"**. The
  user briefly had a DIFFERENT project open in the SQL editor (`niranjansiddharth0@gmail.com`,
  org `xvdvwrrdeohzoexxdbuc`, labelled "main PRODUCTION") — that is **NOT** the deployment DB.
  The migration must go to `ztugwhevemibdrzqafyw` (user applied it there correctly).
- **Supabase MCP**: connected to an account that can `list_projects` (sees `ztugwhevemibdrzqafyw`)
  but `execute_sql` is **permission-denied** (list-level only). Can't run SQL via MCP.

---

## 6. Bugs found during testing + the resync fix

Two symptoms, **one root cause**: Supabase `postgres_changes` does **not replay events missed
while a client's socket is suspended** (backgrounded app / hidden-or-idle web tab), and nothing
re-synced on resume.
1. **EMKAY invoice needed a manual refresh on deployment web** (but appeared live on mobile).
   The badge's `scan_jobs` INSERT fires instantly (socket alive); the `push_queue` INSERT fires
   ~105s later, by which time a backgrounded/idle web tab had missed it. (Earlier mis-diagnosed
   as a publication gap, then a two-channel race — **both wrong**; the user's "Network tab shows
   nothing" screenshot confirmed the suspended-socket cause.)
2. **Badge persists on mobile when the app is backgrounded** even after `scan_jobs` emptied —
   same cause (missed DELETE).

**FIX (client-only — implemented, `flutter analyze` clean, NOT yet rebuilt/shipped):**
- `scan_jobs_service.dart`: `subscribe()` now **always `_refresh()`s first** (recreated shell
  catches up); added `resync()`.
- `app_shell.dart`: `WidgetsBindingObserver` → `didChangeAppLifecycleState(resumed)` re-syncs
  `scan_jobs` (clears a stuck badge) + refreshes `push_queue` (catches a missed invoice INSERT).
- Shared code → fixes **Android** (the reported bug; paused→resumed always fires) AND **web**
  (tab re-focus). **Web caveat:** a tab that stays *visible* but idle won't fire `resumed`, so
  that edge still leans on the 300s TTL sweep. The 300s sweep remains the universal backstop.

---

## 7. Outstanding / next steps
1. **Ship the §6 resync fix** — client-only, no migration/redeploy. Rebuild + reinstall the
   APK (`flutter build apk --flavor staging --dart-define-from-file=env/testing.json`) and
   rebuild/redeploy web. **Not yet done.**
2. **Commit the Flutter feature files** (uncommitted on `feature/scan-loading-indicators`) —
   ONLY these; do NOT sweep the large unrelated uncommitted pile:
   - `lib/data/scan_jobs_service.dart` (new)
   - `lib/data/scan_uploader.dart` (new)
   - `lib/data/scan_inflight_service.dart` (deleted)
   - `lib/features/shell/app_shell.dart`
   - `lib/data/push_queue_service.dart`
   (`handler.py` + `supabase_scan_jobs.sql` are in the separate `TallyBridge` repo.)
3. **`prod` flavor** (`env/prod.json` → parsing project `366926737745`, Supabase
   `yynuuysvjeipawzfbeme`): parsing service **NOT redeployed**; there is **no gcloud config**
   for that project. Its Supabase is already migrated (same as testing). If `prod` is live, its
   parsing service needs the same `--source` redeploy + an `SUPABASE_URL` check.
4. **Clean up the stale `parsing.env.yaml`** (fix or delete) so nobody redeploys with it.
5. **Optional web hardening**: visible-but-idle-tab realtime staleness (periodic resync or
   explicit reconnect) — currently relies on the 300s TTL.

## 8. Constraints still in force
- Commit only the feature files; never the secrets/config pile.
- Publishable/anon keys only in client config; never a service-role key; RLS required.
- Supabase MCP read-only (and `execute_sql` is denied anyway); DB writes need explicit confirm.
- **Before any Cloud Run redeploy/traffic/billing change: show the command and wait for OK.**
  Don't print secret env values. After redeploy, confirm traffic is on `--to-latest`.
- Push always sets `narration='Replara AI'`; purchase vendors = Sundry Creditors, sale
  customers = Sundry Debtors.
- Do NOT run concurrent test requests against the live parse backend (can stall RunPod).

## 9. One-line for the next chat
The shared-`scan_jobs` realtime badge is **built, deployed to testing + deployment, and
verified**; the only un-shipped piece is the **client-only lifecycle-resync fix** (§6) — rebuild
the app to ship it — plus **committing the 5 Flutter files** (§7).
