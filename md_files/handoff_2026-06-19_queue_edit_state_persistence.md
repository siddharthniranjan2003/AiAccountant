# Handoff — Persist the queue edit tag (`edit_state`) + fix the flash-then-vanish

Date: 2026-06-19
Branch: `feature/scan-loading-indicators`
Follows: `handoff_2026-06-19_queue_edit_markers_and_float.md` (read that first — it
introduced the `under edit` / `invoice edited` tags + float-to-top as a **local-only**
overlay). This session made that tag **persisted** and then fixed a display bug.

## Goal of this session

Two parts, in order:

1. **Persist** the queue edit lifecycle tag. Before this session the tag
   (`under edit` / `invoice edited`) was a local-only render overlay (`_editMarkers`
   in the queue screen): lost on reload, invisible to other clients. The
   `created_at` bump and the saved voucher edits already persisted; only the **tag**
   did not. Make the tag survive a cold start and show on every client.
2. **Fix a regression the user then reported:** on the editing device the tag would
   flash for a split second and vanish (and was gone after switching tabs), while the
   web view kept showing it correctly.

## Part 1 — Persist the tag in `push_queue.edit_state`

### Design decision: dedicated column, no backend code change

I traced the full parsing → backend → `push_queue` interaction (parsing source at
`D:\Desktop\TallyBridge\parsing`, backend at `D:\Desktop\TallyBridge\backend`):

- **Parsing never writes Supabase directly** — `handler.py` POSTs
  `queue_request_payload` to the backend (`post_to_push_queue`).
- **Backend (`backend/src/routes/sync.ts`) does exactly four `push_queue` ops, all
  targeted column updates / a scoped INSERT:**
  - enqueue: `INSERT {id, company_id, voucher_payload, source_payload, status:'pending', ...}` (omits `edit_state` → defaults NULL),
  - activate: `update({status:'push_now', error_message:null})`,
  - pull batch: `select(...)` (read only),
  - push result: `update({status, error_message, tally_response, pushed_at})`.
  - None do a full-row replace.

⇒ A new nullable `edit_state` column is **never clobbered** by the backend, and the
client can write it directly (same as it already writes `created_at` and
`voucher_payload`). **No backend/parsing code change was required** — only the schema.

### DB migration (REQUIRED — must run before/with the app change)

New file `backend/supabase_push_queue_edit_state.sql`:

```sql
ALTER TABLE push_queue
  ADD COLUMN IF NOT EXISTS edit_state TEXT
  CHECK (edit_state IS NULL OR edit_state IN ('under_edit', 'edited'));
```

- Run in the Supabase SQL Editor on project **`yynuuysvjeipawzfbeme`** (the live
  client DB). The Supabase MCP was disconnected this session, so I could not apply it
  programmatically — it must be run manually. **It is a hard prerequisite:**
  `refresh()`'s select now names `edit_state`, so the column must exist or the queue
  load errors out (swallowed → empty queue).
- `backend/full_schema.sql` was also updated to include the column in the canonical
  `push_queue` CREATE (for new environments). (Note: an unrelated `stock_items.part_code`
  column also appeared in that file from a separate edit — leave it.)

### Flutter changes for persistence

- **`lib/core/models.dart`** — `QueueEditState` is now an **enhanced enum** that
  serializes itself:
  - `String? get dbValue` → `none`⇒`null`, `underEdit`⇒`'under_edit'`, `edited`⇒`'edited'`.
  - `static QueueEditState fromDb(String? raw)` → inverse.
  - Updated the doc comment (it is no longer "local-only / not stored in Supabase").
- **`lib/data/push_queue_service.dart`**:
  - `refresh()` select gained `, edit_state`.
  - `rowToEntry` sets `editState: QueueEditState.fromDb(row['edit_state'] as String?)`.
- **`lib/features/queue/queue_screen.dart`**:
  - `_bumpCreatedAt` → renamed/extended to **`_persistEditState(entry, state, {required bool bump})`**:
    writes `{edit_state: state.dbValue}` and, when `bump`, also
    `created_at = now (UTC ISO)` — one targeted update.
  - `.then` (sheet close) outcomes:
    - Case 1 (`wasEditing`): stash items, overlay `underEdit`, `_persistEditState(underEdit, bump:true)`.
    - Case 2 (`everSaved`): drop stash, overlay `edited`, `_persistEditState(edited, bump:true)`.
    - Revert (else): drop stash, remove overlay, and if the row was tagged when opened
      (`marker != none`) `_persistEditState(none, bump:false)` to clear the column server-side.
  - `_openVoucherDetailSheet` now seeds the session trackers from **`entry.editState`**
    (the persisted value, already reflected through the overlay) instead of reading
    `_editMarkers` directly.
  - The `_editMarkers` overlay is **kept**, now only as instant pre-realtime feedback.
    It never writes the row list (`onRowsChanged`), so the single-writer invariant and
    the disappearance-bug fix from the prior handoff still hold.

## Part 2 — The flash-then-vanish bug + fix

### Symptom

Tap Edit → close the sheet → "under edit" (greyed) appears for a split second then
disappears; gone after switching Sale/Purchase tabs. **The web view kept showing it.**

### Diagnosis

The persisted value was correct (that's why web, which reads via PostgREST on
load/refresh, kept it). The bug was on the **editing device only**:

1. Optimistic overlay shows the tag instantly (the flash).
2. `_persistEditState` writes `{edit_state, created_at}` → triggers a realtime UPDATE.
3. **Supabase Realtime's column cache lags an `ALTER TABLE ADD COLUMN`**, so the echo
   for that update comes back **without** `edit_state`. `rowToEntry` reads it as
   `none` and overwrites the durable in-memory row's `editState`.
4. The tag now lives only in the ephemeral overlay → next list rebuild / tab switch
   drops it. Web, reading the real column, still shows it.

(The realtime cache lag is transient — it self-heals once Realtime refreshes its
schema on reconnect — but we make the client robust regardless.)

### Fix (two targeted changes)

- **`lib/data/push_queue_service.dart`** — in the realtime **UPDATE** handler, when the
  payload doesn't carry the column, keep the editState already in hand instead of
  letting `none` wipe the tag:
  ```dart
  if (exists && !row.containsKey('edit_state')) {
    final prior = _entries.firstWhere((e) => e.id == entryId);
    updated = updated.copyWith(editState: prior.editState);
  }
  ```
  Realtime echoes are no longer authoritative for the tag.
- **`lib/features/queue/queue_screen.dart`** — after persisting (cases 1, 2, and the
  revert-clear), reconcile from the server so the tag lands durably, not overlay-only:
  ```dart
  if (changed && mounted) await widget.onRefresh();
  ```
  `widget.onRefresh` = `PushQueueService.refresh()` (PostgREST), which reliably returns
  `edit_state`. It's the canonical single-writer reader, so it does **not** reintroduce
  the old two-writer disappearance race.

Net effect: the **persisted column is the single source of truth on the editing device
too**, seeded by PostgREST (`refresh()`) and protected from lossy realtime echoes; the
overlay is just the instant flash.

## Deploy / rebuild notes (last thing discussed)

- The fix is in shared `lib/` Dart code, so **both** the web build and the mobile build
  pick it up on rebuild.
- **The device that does the editing must run the rebuilt code.** Rebuilding only the
  web app fixes editing-on-web; if editing also happens from the mobile build, rebuild
  that too — otherwise that editor keeps the old lossy-echo behavior.
- No DB step beyond the migration (already applied — web showed the tag, which proves it).
- Passive cross-device timing (not a bug): a tag set on device A appears on a passively
  watching device B at B's next refresh (load / pull-to-refresh / resume), not
  necessarily the instant of the edit, until Realtime's column cache catches up.

## Status

- `flutter analyze lib`: **clean** (no issues) after every change.
- **Not yet verified on-device** (no device run this session). Recommended manual check:
  edit a queued voucher → close → confirm the tag stays and the row floats to Today →
  switch Sale/Purchase tabs → tag persists → cold-restart the app → tag still there.
- Confirm `created_at` is writable on the live table (no trigger overriding it) — the
  schema shows none, and `DEFAULT now()` only applies on INSERT, but it was never
  confirmed on-device (carried over from the prior handoff's caveat).

## Files touched this session

App (`D:\Desktop\Ai_Accountant\aiaccountant`):
- `lib/core/models.dart`
- `lib/data/push_queue_service.dart`
- `lib/features/queue/queue_screen.dart`

Backend repo (`D:\Desktop\TallyBridge\backend`):
- `supabase_push_queue_edit_state.sql` (**new** — the migration to run)
- `full_schema.sql` (canonical `push_queue` CREATE updated)

Memory (`…/memory/`):
- `queue-edit-state-persisted.md` (new) + `MEMORY.md` pointer

## Key context for the next chat

- Live client Supabase project: **`yynuuysvjeipawzfbeme`**. Web hosting: Firebase
  `aiaccountant-b60ed`.
- Parsing source: `D:\Desktop\TallyBridge\parsing` (not in this repo). Backend:
  `D:\Desktop\TallyBridge\backend`.
- Queue rows come from `push_queue` via `PushQueueService` (realtime INSERT/UPDATE/DELETE
  + `refresh()`), sorted newest-first by `created_at`. Pushed rows leave the queue
  (move to History); pending/push_now/failed stay visible.
- The queue's edit tag and the float-to-top are intentionally coupled to one
  `_persistEditState` update (tag + `created_at` bump together).
