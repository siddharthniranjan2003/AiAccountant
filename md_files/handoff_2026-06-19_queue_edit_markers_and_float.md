# Handoff — Queue edit lifecycle: "under edit" / "invoice edited" tags + float-to-top

Date: 2026-06-19
Branch: `feature/scan-loading-indicators`

## Goal of this session

In the Queue screen, give an edited voucher a visible lifecycle marker and re-sort
it to the top when the user touches it in the detail bottom sheet.

Two cases were requested:

1. **Closed mid-edit** (sheet was in Edit mode when dismissed) → bump the row's
   `created_at` to now (so newest-first sort floats it to the top) and show
   **"under edit"** below the party name + time. Row stays **greyed/dimmed**.
2. **Edited and saved** (Save tapped in the sheet) → bump `created_at` again and
   show **"invoice edited"** below party name + time. Row renders at **normal**
   opacity (it's ready to push, just tagged).

A third implicit case: edited then **Reverted** → no tag (back to original).
And: just **viewed** (no edit) → row untouched, no bump, prior tag preserved.

## What the queue looked like before

- `QueueEntry.isBeingEdited` (bool) flagged a single "being edited" state; the row
  greyed out. It was set purely locally on sheet close, with **no Supabase write**,
  so it never raced with realtime.
- Queue rows come from Supabase `push_queue` via `PushQueueService` (realtime
  INSERT/UPDATE/DELETE + `refresh()`), sorted newest-first by `created_at`
  (`QueueEntry.sortKey` = `created_at` epoch millis).
- The shell (`app_shell.dart`) holds `_supabaseEntries`; realtime rebuilds them via
  `_onSupabaseEntriesChanged`, which preserves local-only `checked`/`status` across
  rebuilds. Local mutations go through `_onRowsChanged`.

## Final design (after a mid-session bug + fix — read this, not the first attempt)

### 1. Model — `lib/core/models.dart`
- Replaced `bool isBeingEdited` with `enum QueueEditState { none, underEdit, edited }`
  and field `QueueEntry.editState` (+ `copyWith`).

### 2. Detail sheet — `lib/features/queue/voucher_detail_sheet.dart`
- Added `bool _everSaved` — set **true** in the Save branch of `_toggleEdit`, reset
  **false** in `_revert` (a revert returns the row to original, so it's no longer
  "edited").
- Extended the callback signature to report it:
  `onEditStateChanged(bool isEditing, List<Map> items, bool everSaved)`.
  Called from `_notifyEditState()` on every toggle / add / revert.
- (History opens this sheet read-only and does **not** pass the callback, so the
  signature change is safe.)

### 3. Queue screen — `lib/features/queue/queue_screen.dart` (KEY FILE)
- **`_editMarkers` (`Map<String rowId, QueueEditState>`) is the source of truth for
  the tag.** It is applied as a **render-time overlay** in `_visibleRows`
  (`entry.copyWith(editState: marker)`), and is **never written back through
  `onRowsChanged`**.
- On sheet close (`.then`), session trackers decide the outcome:
  - trackers seeded from `_editMarkers[entry.id]` (so view-only close = no change);
    `touched` flips true on the first `onEditStateChanged`.
  - `!touched` → return (leave row + prior tag as-is).
  - `wasEditing` → Case 1: stash items in `_savedEdits`, `setState` marker =
    `underEdit`, `await _bumpCreatedAt`.
  - `everSaved` → Case 2: drop `_savedEdits`, `setState` marker = `edited`,
    `await _bumpCreatedAt`.
  - else → reverted: drop `_savedEdits`, `setState` remove marker.
- `_bumpCreatedAt(entry)` writes `created_at = now (UTC ISO)` to the `push_queue`
  row (guarded on `__row_id`; seed rows are no-ops). The realtime UPDATE this
  triggers re-sorts the row to the top; the overlay re-applies the tag on top.
- Re-opening an `underEdit` row restores `_savedEdits[id]` via
  `initialIsEditing` / `initialEditableItems`.
- `_discardEntry` clears both `_savedEdits` and `_editMarkers` for the id.
- The old `_updateEntry` helper was **removed** (no longer used).
- Added `import 'package:supabase_flutter/supabase_flutter.dart';`.

### 4. Row tile — `lib/features/queue/queue_row_tile.dart`
- `isUnderEdit = entry.editState == QueueEditState.underEdit`.
- Opacity dims (0.56) only for `underEdit` (or non-pending / duplicate); `edited`
  stays 1.0. Party name muted for `pushed || underEdit`.
- New sub-label block below time: `"under edit"` (muted) / `"invoice edited"`
  (pen-blue) when `editState != none`.

### 5. Shell — `lib/features/shell/app_shell.dart`
- **No edit-tag logic here.** An earlier attempt added `editState` preservation to
  `_onSupabaseEntriesChanged`; that was **reverted** because the tag now lives in
  the queue's `_editMarkers` overlay, not on the realtime-rebuilt entry.
- NOTE: the user separately added a `WidgetsBindingObserver` to this file
  (`didChangeAppLifecycleState` → on resume call `_scanService.resync()` +
  `_pushQueueService.refresh()` to catch realtime missed while backgrounded), and
  changed `ScannerMode.base` → `ScannerMode.full`. **Leave those — unrelated to
  this task, intentional.**

## The bug that was found and fixed mid-session (important context)

**Symptom:** clicking Edit then closing the sheet *sometimes* made the whole
invoice **disappear** from the queue (intermittent; hit the large BALAJI invoice).

**Root cause:** the first implementation set the tag via a local `_updateEntry` →
`onRowsChanged` write **in addition to** the `created_at` bump. That created **two
async writers of `_supabaseEntries`**:
- realtime UPDATE (from the bump) → `_onSupabaseEntriesChanged` rebuilds the list,
- local `_updateEntry` → `_onRowsChanged` rebuilds the list from the queue's
  `widget.rows`.

The `.then` callback runs as a microtask after `await`, **before the next frame**,
so `widget.rows` was a **stale pre-bump snapshot**. The two full-list rebuilds
clobbered each other and, depending on realtime timing, dropped the edited row. The
old code never hit this because close-while-editing did no Supabase write (single
writer).

**Fix:** decoupled row movement from the tag — `created_at` bump stays on the
realtime path (sole writer of `_supabaseEntries`); the tag became the render-time
`_editMarkers` overlay (never re-writes the list). No second writer → no clobber →
no disappearance.

## Assumptions / caveats to verify

- **`created_at` is assumed writable** (no DB trigger/policy overriding it). If the
  write silently no-ops, the row won't re-sort. Worth a quick check against the live
  `push_queue` table (client project `yynuuysvjeipawzfbeme`).
- Bumping `created_at` also changes the row's **displayed time label** (it derives
  from `created_at`) — accepted side effect of wanting the sort to update.
- Stale entries can linger in `_editMarkers` after a row is pushed (leaves the
  queue); harmless because the overlay only applies to rows present in `widget.rows`.

## Status

- `flutter analyze` on all touched files: **clean** (no issues).
- Not yet verified on-device that the disappearance is gone for the heavy invoice,
  and that the `created_at` write actually persists. Recommend manual retry of the
  BALAJI close-mid-edit case + confirm the row floats to Today with its tag.

## Files touched this session

- `lib/core/models.dart`
- `lib/features/queue/voucher_detail_sheet.dart`
- `lib/features/queue/queue_screen.dart`
- `lib/features/queue/queue_row_tile.dart`
- `lib/features/shell/app_shell.dart` (edit-tag preservation added then reverted;
  unrelated lifecycle/observer + ScannerMode changes are the user's, keep them)
