# AI Accountant — Dev Handout (Session Summary)

Covers two consecutive sessions ending 2026-06-04. Use this as context for the next chat.

---

## Project Overview

Flutter app (Android) for a hardware trader. Scans invoices with ML Kit, pushes to Tally via a backend API. Key screens: Queue, History, Report, Profile. Backend: Supabase (`push_queue` table) + Cloud Run API (`tallybridge-backend-950406969086.asia-south1.run.app`).

---

## Files of Note

| File | Role |
|---|---|
| `lib/features/queue/voucher_detail_sheet.dart` | Bottom sheet for editing sale/purchase vouchers |
| `lib/features/queue/queue_row_tile.dart` | Single row in the queue list |
| `lib/features/queue/queue_table_header.dart` | Header row (#, Party, Amount) |
| `lib/features/queue/queue_screen.dart` | Queue list screen |
| `lib/features/history/history_screen.dart` | Pushed vouchers history |
| `lib/features/report/report_screen.dart` | Insights + Chat tab |
| `lib/data/customers_cache.dart` | Singleton — Sundry Debtors from `ledgers` table |
| `lib/data/stock_items_cache.dart` | Singleton — stock items (pre-existing) |
| `lib/services/api_client.dart` | HTTP client (base URL, Firebase auth header) |
| `lib/main.dart` | App entry — initialises Supabase, Firebase, both caches |

---

## Session 1 Work (VoucherDetailSheet + HistoryScreen)

### 1. Amount recalculation on stock item select
When a stock item is changed in edit mode the amount is recalculated:
`amount = (qty × rate) − discount`

### 2. Delete icon moved to end of each row
Previously inside the item name column. Now a dedicated 40 px column at the far right of the item table, with a confirm dialog before deleting.

### 3. Party name editing for Sale vouchers
- Tapping the party name header while in edit mode opens `_CustomerPickerSheet` (mirrors `_StockItemPickerSheet`).
- Customer list is `ledgers WHERE group_name = 'Sundry Debtors'` — fetched at app launch via `CustomersCache.instance.fetch()` called in `main.dart`.
- If still loading, a toast is shown.

### 4. Push to Tally blocking logic (Sale only)
Rule: **if party name was changed from original, ALL items must also be changed from original before Push to Tally is allowed.**

- `pushBlocked = _partyNameWasChanged && !_allItemsDifferentFromOriginal`
- Blocked state: button is greyed (alpha 0.45), tap shows toast: `"Party Name is Changed!!\nChange all the items"`
- Block persists across save cycles — originals are captured once on first Edit entry and never overwritten.

Key state vars (captured once at first Edit entry, never reset until Revert):
```dart
String? _originalPartyName;
List<String>? _originalItemNames;
Map<String, dynamic>? _originalPayload;  // full payload snapshot for Revert
```

### 5. "Item Edited" purple label
- Shows on each item row **both during edit mode and after saving** if that item differs from its original.
- Comparison uses `_originalItemNames[i]` (true original), NOT `_payloadItems` (which gets updated on Save).

### 6. "Changing From: …" in stock item picker
`_StockItemPickerSheet` accepts a `changingFrom` parameter. When set, shows:
```
Changing From : <original item name>
```
above the search bar.

### 7. Revert button
Fully restores all state to original across any number of save cycles:
- Clears `_isEditing`, `_editablePartyName`, `_editableItems`
- Resets `_payload` from `_originalPayload` snapshot

### 8. History screen — placeholder data removed
- Removed `seedHistoryEntries` import and `_saleHistory` getter.
- Renamed `_purchaseHistory` → `_history`.
- `voucher_type` field in `voucher_payload` drives `TransactionType`:
  - contains `"SALE"` → `TransactionType.sale`; else → `TransactionType.purchase`
- All tab, Sale tab, Purchase tab filters work off real Supabase `push_queue` rows with `status = 'pushed'`.

---

## Session 2 Work (Queue Row UI + API URL)

### 9. Time label moved below party name
`queue_row_tile.dart`: the `timeLabel` is now a second `Text` inside a `Column` under the party name. The separate "Time" column in the header (`queue_table_header.dart`) was removed.

### 10. Checkbox removed from Sale rows
Sale rows now show nothing in the trailing slot. Purchase rows still show the camera/email source icon (`_SourceIcon`). `onCheckboxTap` parameter and `InkCheckbox` import removed from `QueueRowTile`.

### 11. Amount at absolute right
`SizedBox(width: 100)` wrapper on the amount removed. The amount `Text` now sits naturally at the far right after the `Expanded` party column. For sale (no trailing icon) it reaches the absolute right edge. For purchase it precedes the 8 px gap + source icon. Header updated to match.

### 12. API base URL updated
`lib/services/api_client.dart`:
```
Old: https://tallybridge-h3do.onrender.com
New: https://tallybridge-backend-950406969086.asia-south1.run.app
```
All `ApiClient.get`, `ApiClient.getRaw`, `ApiClient.post` calls now hit the Cloud Run URL.

---

## Architecture Notes

### VoucherDetailSheet state lifecycle
```
First Edit entry
  └─ capture _originalPartyName, _originalItemNames, _originalPayload (once, never again)

Save (staying in edit mode → _isEditing = false)
  └─ write _editableItems + _editablePartyName back into _payload
  └─ clear _editablePartyName (NOT _originalPartyName)

Re-enter Edit
  └─ originals already captured → skip

Revert
  └─ restore _payload from _originalPayload
  └─ clear all _editable* vars, _isEditing = false
  └─ originals remain (for comparison if user edits again)
```

### `_isSale` detection
```dart
bool get _isSale {
  final vt = (_p['voucher_type'] as String? ?? '').toUpperCase();
  if (vt.isNotEmpty) return vt.contains('SALE');
  return _p.containsKey('sale_voucher_payload');
}
```

### CustomersCache (new singleton)
```dart
// lib/data/customers_cache.dart
class CustomersCache {
  static final instance = CustomersCache._();
  List<Customer> items = [];
  bool isLoading = false;
  Future<void> fetch() async { /* SELECT name,group_name,state FROM ledgers WHERE group_name='Sundry Debtors' */ }
}
```
Called in `main.dart` after `StockItemsCache.instance.fetch()`.

---

## Security Constraints (must stay in effect)
- `.env` — NEVER commit (`SUPABASE_URL`, `SUPABASE_SERVICE_KEY`, `API_KEY`, `FIREBASE_SERVICE_ACCOUNT_B64`)
- `android/app/google-services.json`, `lib/firebase_options.dart` — do NOT commit
- `android/key.properties`, `android/app/upload-keystore.jks` — gitignored, keystore stays local only
- Supabase service-role key must never ship in any client build; only anon/publishable key is safe client-side with RLS enabled
- Supabase MCP is installed `--read-only`

---

## Known / Pending
- Supabase persistence on Save (updating the `push_queue` row) — deferred, not yet implemented
- Duplicate rows in queue: a fresh scan produces a transient `*_scan_*` entry + the `supabase_<id>` realtime row — not deduped
- Image persistence plan exists at `.claude/plans/what-is-the-url-majestic-giraffe.md` — approved plan, not yet implemented: save scanned image to disk keyed by `push_queue` row id, load when opening that row from queue
- History screen: image tab not wired up (trivial via `InvoiceImageStore.load(rowId)` once image persistence is done)
- Report screen: insights list still uses `seedReportCategories` from `seed_data.dart` for the item list (only the API endpoint URL was updated; replacing seed items with real API-driven categories not done)
