# Handoff — 2026-06-15 — Serial send-queue + the "count won't climb" reality

Continues `handoff_2026-06-14_scan_loading_indicators.md`. Branch:
**`feature/scan-loading-indicators`**. This doc covers everything since the last
compact: the count-badge + 4-quarter-timer redesign, the discovery that the parse
backend is a **single serial worker**, the pivot from concurrent → **serial
send-queue**, and the still-open problem (**the count badge structurally can't
exceed 1** under one-at-a-time scanning).

---

## 0. TL;DR of where we are
- **Committed & pushed:** `4cccbef` — the *concurrent* version (count badge +
  4-quarter timer, auto-modal dropped, fire-and-forget parse). This is the last
  commit on the branch and is on `origin`.
- **Uncommitted (working tree, on top of `4cccbef`):** the **serial send-queue**
  rewrite. Only **2 files** differ from HEAD:
  - `lib/features/shell/app_shell.dart` (~89 ins / 66 del)
  - `lib/data/push_queue_service.dart` (revert of an `onInserted` hook)
  - `queue_loading_tile.dart` and `queue_screen.dart` are **unchanged from
    `4cccbef`** (the count badge + timer UI is already committed).
- **Status:** `flutter analyze` clean on all touched files. **Not committed.**
- **Open problem (diagnosed, not fixed):** the count badge stays at **1** in real
  use. Root cause is *not a bug* — see §4.

---

## 1. What the user asked for (this stretch)
1. Redesign the "Processing…" row: **remove the spinner**; add a **count badge**
   (circle with a number = how many PDFs are in the pipeline) to the right of the
   text, and a **4-quarter, 1-minute timer ring** (15s per quarter, escalating
   colours) on the far right.
2. **The user's real behaviour (stated explicitly, late):** they scan and send
   PDFs **sequentially** — scan a purchase → send, scan another → send, scan a
   sale → send. **Not parallel.** The purpose is purely to **improve the UI/UX
   around sequential sending**, NOT to enable concurrency. (I wrongly chased
   concurrency for most of the session; the user corrected this.)

---

## 2. The key discovery — the parse backend is a SINGLE SERIAL WORKER
The original app opened a blocking modal on every scan. I removed it (to let the
count climb), which let parse requests **overlap**. That produced the toast
**"A purchase document couldn't be processed."** on the 2nd purchase.

I reproduced the exact app call (`_parseDocument`: `POST` raw PDF bytes,
`Content-Type: application/pdf`) against the **testing** purchase endpoint
`https://tallybridge-parsing-828647628834.asia-south1.run.app/docstrange?purchase=all&source=runpod`
using the sample `D:\Downloads\image sample\emkay.pdf` (83 KB):

- **1 request alone** → `HTTP 200`, clean JSON, `inference_seconds ≈ 11.2`. Parses
  EMKAY TOOLS LIMITED, invoice GN25Y-32738, total ₹3,99,653. ✅
- **2 concurrent requests** → **both hung the full 290s, 0 bytes, HTTP 000** (no
  status at all) — and **stalled the runpod queue, which the user had to purge.** ❌

**Conclusion:** the backend serializes on one worker. Concurrent requests stall
until the connection drops. The "couldn't be processed" toast was the 2nd
request's **dropped/timed-out HTTP reply** — *the work still completed and the row
still landed via realtime*. It was never a bad document; it was accidental
concurrency that my modal-removal introduced.

> Don't run more concurrent tests against the live backend — it stalls their
> queue. If the exact client exception string is ever needed, read the
> `debugPrint('Parse failed (Purchase): …')` line from a real `flutter run`.

---

## 3. What was implemented now — client-side SERIAL send-queue (max-in-flight = 1)
Approved plan: `C:\Users\panka\.claude\plans\abstract-painting-whistle.md`.
Industry framing: a **client-side FIFO work queue with a single-worker dispatcher
(leaky-bucket / max-in-flight = 1)**; count badge = **queue depth / backlog**;
timer = **in-flight latency**; rows still arrive **event-driven (Supabase realtime
/ CDC)**.

### `lib/features/shell/app_shell.dart` (the only real change)
- State: `final List<_ScanJob> _queue = []` + `bool _dispatching = false`.
- `_ScanJob` now carries dispatch inputs: `type, pdfPath, url, enqueuedAt`.
- Per-tab getters read `_queue`:
  - `_loadingCountFor(type)` = count of that type in `_queue` (waiting + in-flight).
  - `_oldestStartFor(type)` = earliest `enqueuedAt` of that type → timer ring.
- `_uploadAndShowResult` → **`_enqueueScan(pdfPath, type:)`**: snackbar + append a
  `_ScanJob` + `_pumpQueue()`. **Does not send immediately.** (`imageBytes` param
  and its capture block deleted — the modal that used it is gone.)
- **`_pumpQueue()`** — the single-worker dispatcher (the core):
  ```dart
  Future<void> _pumpQueue() async {
    if (_dispatching || _queue.isEmpty || !mounted) return;
    _dispatching = true;
    final job = _queue.first;                      // head stays in queue while sending
    try {
      await _parseDocument(job.pdfPath, job.url)
          .timeout(const Duration(seconds: 60));
    } catch (e) {
      debugPrint('Parse failed (${job.type.label}): $e');
    } finally {
      _dispatching = false;
      if (mounted) setState(() => _queue.remove(job));
      _pumpQueue();                                // next, serially
    }
  }
  ```
- Kept the hardened `_parseDocument` (status-code check → `_ParseException` +
  `_bodySnippet`) — useful diagnostic logs; errors are now rare (no contention).
- **Removed** `_trackScanJob`, `_removeJob`, `_resolveJobForType`, the false-error
  toast, and the `onInserted:` wiring.

### `lib/data/push_queue_service.dart`
- Reverted the session's `onInserted` callback. Realtime is back to feeding durable
  `QueueRowTile` rows only (`rowToEntry`), unchanged from its original role.

### Unchanged (already in `4cccbef`)
- `queue_loading_tile.dart` — stateful row: "Processing…" (no spinner) + count
  badge (`_CountBadge`) + 4-quarter ring (`_QuarterTimerPainter`, green→amber→
  orange→red, 15s/quarter, own 1s ticker).
- `queue_screen.dart` — renders one loading row from `loadingCount` +
  `oldestLoadingStart` above the day-groups.

### Behaviour this achieves
Sends now go to the backend **strictly one at a time** → **no overlap, no stall,
no false toast.** This *fixed the real bug.* Rows land in order via realtime.

---

## 4. OPEN PROBLEM — the count badge structurally stays at 1 (diagnosed, not fixed)
User's latest report: *"the counter did not increase."* This is **not a code bug.**

- Count = number of `_ScanJob`s in `_queue` **at the same instant** (per type).
- An item **enters** on scan-complete, **leaves** when its parse finishes (~11–15s).
- For count ≥ 2, item #2 must enter **while #1 is still parsing** — i.e. you must
  finish scanning #2 within ~11s of #1.
- But **scanning one PDF** (open camera → ML Kit → capture/import → confirm) takes
  **about the same ~10–20s** as one parse. So by the time #2 is enqueued, #1 has
  already finished and left the queue. **The two never coexist → depth stays 1.**

This is a **rate-matched producer/consumer**: you *produce* (scan) at ≈ the same
rate you *consume* (parse), so **no backlog accumulates** and the badge can't
climb. The serial queue fixed the error class but did **not** change *when* an item
leaves the queue, so it can't manufacture a backlog that isn't there.

**The count would only exceed 1 if items entered faster than ~11s each** — e.g.
rapidly importing several already-saved PDFs back-to-back (faster than parse), a
much slower backend, or a different ingestion model. One-photo-at-a-time scanning
will not do it.

**This is the decision point for the next chat:** the count badge, as specified,
doesn't reflect anything meaningful in the user's actual sequential single-scan
workflow. Options to discuss with the user (NOT yet chosen):
1. **Drop the count**, keep just "Processing…" + the timer for the one in flight
   (honest for sequential use).
2. **Multi-PDF import** (ML Kit `isGalleryImport: true` or a file picker) so a
   user can enqueue many at once → real backlog → count climbs. Bigger change.
3. **Redefine the count** to mean something else (e.g. total sent today / a session
   counter) — needs the user's intent.
4. Accept count is usually 1 and move on.

Last thing said to the user: offered to "look at what it would take to make the
count meaningful given this reality." **Awaiting their direction.**

---

## 5. Exact git state (verified)
- HEAD = `4cccbef` (pushed to `origin/feature/scan-loading-indicators`).
- Uncommitted vs HEAD: **`app_shell.dart`** (serial-queue rewrite) and
  **`push_queue_service.dart`** (onInserted revert). Nothing else from this work.
- The tree also has a **large pile of pre-existing uncommitted changes** unrelated
  to this feature (backend deletions, ~20 other `lib/` files, `pubspec.yaml`,
  `android/app/build.gradle.kts`, and untracked `lib/core/config.dart`,
  `.env_clinet`, `env/`, `.firebase*`, handoff docs). **Do NOT sweep these into a
  commit** — `config.dart`/`.env_clinet`/`env/` look like secrets/config. Commit
  only the two feature files when the time comes.

---

## 6. How to test (when ready)
- `flutter analyze lib/features/shell/app_shell.dart lib/data/push_queue_service.dart` → clean.
- APK: `flutter build apk --flavor staging --dart-define-from-file=env/testing.json`.
- Reproduce the parse call directly (DON'T do concurrent — it stalls the queue):
  ```bash
  curl -sS -X POST -H "Content-Type: application/pdf" \
    --data-binary "@/d/Downloads/image sample/emkay.pdf" \
    "https://tallybridge-parsing-828647628834.asia-south1.run.app/docstrange?purchase=all&source=runpod"
  ```
  Expect `HTTP 200`, `"ok": true`, ~11s.

---

## 7. Carried constraints (still in force)
- Publishable/anon keys only in `config.dart`/env — **never a service-role key**;
  RLS required. `config.dart` defaults = **testing** env (`yynuuysvjeipawzfbeme`).
- Supabase MCP treated **read-only**; DB writes need explicit per-migration confirm.
- Push always sets `narration='Replara AI'`; purchase vendors = Sundry Creditors,
  sale customers = Sundry Debtors.
- Live client-data Supabase = `ztugwhevemibdrzqafyw` (deployment flavor); testing =
  `yynuuysvjeipawzfbeme`. Web hosting = Firebase `aiaccountant-b60ed` (prod).
- **No `job.id` correlation** between a scan's HTTP response and its realtime row
  (the known gap). Not needed for the serial queue, but it's why we can't exactly
  match a send to its row.

---

## 8. The one-line summary for the next chat
The serial send-queue (max-in-flight = 1) is **built, analyze-clean, uncommitted**,
and it **fixed the concurrency/stall/false-toast bug**. The remaining issue —
*"the count won't go above 1"* — is **structural, not a bug** (scan rate ≈ parse
rate → no backlog). **Next step is a product decision** with the user on what the
count should mean (see §4), before any more code.
