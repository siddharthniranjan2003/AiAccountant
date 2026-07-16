# AI Accountant — Dev Handout (session ending 2026-06-08)

Context handoff for a fresh chat. Covers everything since the last git commit.

**Last commit:** `711fd3c` "Add sale item picker with party-specific history, queue UI cleanup, and Cloud Run backend" (2026-06-04). Everything below is **uncommitted** working-tree state (nothing has been committed since).

---

## 0. App + deployment basics
- Flutter app (Android + Web) for a hardware trader. Scans invoices → parses → pushes vouchers to Tally via backend. Screens: Queue, History, Camera/scan, Report, Profile.
- **Web hosting:** Firebase project `aiaccountant-b60ed`, serves `build/web`.
  - Deploy: `flutter build web --release` then `firebase deploy --only hosting --project aiaccountant-b60ed`.
  - Live URL: **https://aiaccountant-b60ed.web.app**
  - `firebase.json` sets `no-cache` on index.html/bootstrap/sw/main.dart.js, BUT Flutter's **service worker still caches** — after a deploy you often must hard-refresh (Ctrl+Shift+R twice) or DevTools → Application → unregister SW + clear site data. (This bit us: a deploy looked "not updated" but was just SW cache.)

## 1. TWO Supabase projects — CRITICAL
| | ref | `voucher_items` shape | Notes |
|---|---|---|---|
| "my supabase" (dev) | `yynuuysvjeipawzfbeme` | **DENORMALIZED** — `party_name`,`voucher_type`,`date` are ON each item row | publishable key `sb_publishable_c2Cov2CT8hxOd1FFEo_yaA_6nEt8_Nl` |
| "client supabase" | `ztugwhevemibdrzqafyw` | **NORMALIZED** — those fields live only in the `vouchers` table (join `voucher_items.voucher_id = vouchers.id`); on item rows they're null/absent | publishable key `sb_publishable_IRsM8wDF6w9OyiPegwB2cw_a9aqW9lt` |

**The app currently points at the CLIENT project** (`ztugwhevemibdrzqafyw`) — see `lib/core/config.dart`. (It was flipped between the two during the session; current state = client.)

Other tables both have: `push_queue`, `stock_items`, `ledgers`, `vouchers`. `ledgers.group_name`: `'Sundry Debtors'` = sale customers, `'Sundry Creditors'` = purchase vendors.

## 2. Supabase DB functions (item pickers)
`get_sale_items_for_party(p_party_name text)` and `get_purchase_items_for_party(p_party_name text)`.
Both return `TABLE(stock_item_name, rate, discount_pct, source)` — that party's **previously transacted** items only (`source` always `'same_party'`), `rate>0`, `DISTINCT ON (stock_item_name)` latest by date. Sale filters `voucher_type ILIKE '%SALE%'`, purchase `ILIKE '%PURCHASE%'`. Match party with `lower(party_name)=lower(p_party_name)`.

- **Denormalized version** (apply on `yynuuysvjeipawzfbeme`): reads `vi.party_name/vi.voucher_type/vi.date` directly. Index: `idx_voucher_items_party_item_date` on `(lower(party_name), stock_item_name, date DESC)`.
- **Normalized version** (apply on client `ztugwhevemibdrzqafyw`): `JOIN vouchers v ON v.id=vi.voucher_id`, read `v.party_name/v.voucher_type/v.date`, `ORDER BY vi.stock_item_name, v.date DESC`. Indexes: `idx_vouchers_party_lower` on `vouchers(lower(party_name))`, `idx_voucher_items_voucher_id` on `voucher_items(voucher_id)`.

**History/why:** these RPCs replaced an earlier slow function whose "fallback to all other parties" full-scan timed out (Postgres `57014`) for big-history parties → app silently fell back to the `stock_items` catalog (showing ₹0 catalog items). Now scoped to one party + indexed = fast.

**STATUS of DB functions:**
- `yynuuysvjeipawzfbeme`: both sale + purchase functions applied & verified fast (via MCP). ✅
- `ztugwhevemibdrzqafyw` (client, the live target): MCP has **no permission** there — must be applied by the user in the client SQL editor. **Verify both join versions + the two indexes exist on the client**, else pickers error/fall back. ⬜

## 3. App changes this session (key files)
**`lib/features/queue/voucher_detail_sheet.dart`** (the big one):
- Item picker `_StockItemPickerSheet`: sale → `get_sale_items_for_party`, purchase → `get_purchase_items_for_party` (party-specific). Added an **"All items" toggle** (right of the "Changing From" row): OFF = party items; ON = full `StockItemsCache` catalog. Works for both types; search preserved across toggle.
- Editable **vendor** name for purchase (not just sale): sale uses `CustomersCache` (Sundry Debtors), purchase uses **new `VendorsCache`** (Sundry Creditors). "party changed ⇒ all items must change before Push" rule applies to both.
- Full voucher editing re-enabled: **Invoice # / Date (calendar picker) / Narration / items / Qty / Disc / Rate / Amount / Charges (GST Sale, CGST, SGST, IGST, discount, total)** — editable for both types; saved into `push_queue.voucher_payload` (only when `status='pending'`).
- **Add item** works for both types. **Delete** = hard-delete the push_queue row (Yes/Cancel dialog "Are you sure You want to delete this Invoice"). **Revert** restores originals AND writes them back to Supabase.
- **Push to Tally** always overrides `voucher_payload.narration = 'Replara AI'` (const `_pushNarration`) in Supabase before calling the activate endpoint.
- History opens the sheet **read-only** (`readOnly` flag hides Edit/Add/Push).

**`lib/main.dart`:** auth gate via `StreamBuilder(FirebaseAuth.authStateChanges())` (fixes web-refresh logout / session persistence); wrapped app in **`SelectionArea`** (web text selectable/copyable); Supabase init reads from `Config`.

**`lib/features/auth/login_screen.dart`:** phone-OTP only (removed email/password, the email/phone slider, WhatsApp checkbox, Google/Apple buttons, "create account").

**`lib/features/shell/app_shell.dart`:** scan results show **only in the bottom sheet** — never inserted into the queue (queue is fed solely by Supabase realtime). Removed `_localPurchaseEntries`.

**`lib/features/queue/queue_screen.dart` + `queue_row_tile.dart` + `data/push_queue_service.dart`:** queue row now reflects the **real `push_queue.status`** (`pending`/`push_now`→"pushing…"/`failed`→"failed"/`pushed`→leaves queue); `failed` kept visible (`isActiveStatus` includes it); removed the fake 2s `_processSingleEntry` "Done" flow + toast infra.

**`lib/data/vendors_cache.dart`** (NEW): `VendorsCache` = `ledgers` where `group_name='Sundry Creditors'`, fetched at launch in `main.dart` (alongside `StockItemsCache`, `CustomersCache`).

**`lib/core/config.dart`** (NEW): single source of truth for all URLs + keys (Supabase, main backend, activate endpoint, parse URLs). All call sites (`main.dart`, `services/api_client.dart`, `voucher_detail_sheet.dart`, `app_shell.dart`) reference `Config.*`. **Currently set to the client project** (`ztugwhevemibdrzqafyw` + `IRsM8` key).

## 4. Outbound network calls (inventory)
- **Supabase** (`Config.supabaseUrl`): catalog/customer/vendor caches at launch; queue + history reads & realtime channels; voucher update/delete; narration update on push; picker RPCs.
- **Firebase Auth:** phone `verifyPhoneNumber` (SMS OTP), `signInWithCredential`, `authStateChanges`, `signOut`, `getIdToken`.
- **Cloud Run #1 — main backend** `tallybridge-backend-950406969086.asia-south1.run.app` via `ApiClient` (`x-api-key: Config.backendApiKey` + Firebase Bearer). Only used by **Report screen** (`/api/sync/reorder-levels/<id>`).
- **Cloud Run #2 — activate** `tallybridge-backend-xx3yz3b3kq-el.a.run.app/api/sync/push-queue/activate` (Push to Tally; POST `{job_id}`, `x-api-key: Config.activateApiKey`). NOTE: **different host** than #1.
- **Cloud Run #3 — parsing** `tallybridge-parsing-950406969086.asia-south1.run.app` — PDF upload in `app_shell.dart _parseDocument` (sale `/?type=sale&push=queue`, purchase `/docstrange?purchase=all&source=runpod`). **NO auth header** (only `Content-Type: application/pdf`). (User considered adding `x-api-key`=`Config.activateApiKey` but reverted it.)
- **Google Fonts CDN** (runtime font fetch), **ML Kit doc scanner** model (first scan, Android).

## 5. Outstanding / watch-outs
- ⬜ **Apply both join-version RPCs + 2 indexes on the client `ztugwhevemibdrzqafyw`** (app points there now). Verify via REST/anon: `POST /rest/v1/rpc/get_sale_items_for_party {p_party_name}`.
- Parsing PDF upload is **unauthenticated**.
- Two different backend hosts (activate vs main API) — confirm intentional.
- ₹0 items only appear now in the picker's **"All items"** mode = genuine `stock_items.rate=0` data (data cleanup, not a bug).
- **Nothing committed since `711fd3c`** — 17 modified files + new files (`config.dart`, `vendors_cache.dart`, `firebase.json`, `.firebaserc`, etc.). Consider committing.
- PIN-based app lock was discussed but NOT built (Firebase has no PIN auth; would be a local app-lock over the persisted session).

## 6. How to verify quickly
- `flutter analyze` → currently clean.
- Sale/purchase picker: open an item edit → toggle "All items" off = that party's items, on = full catalog.
- After any deploy, hard-refresh / clear the service worker to avoid stale build.
