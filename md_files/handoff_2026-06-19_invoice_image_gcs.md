# Handoff — 2026-06-19 — Scanned invoice image in Queue & History (GCS, mapped per push_queue row)

Feature built end-to-end this session. **Server side is LIVE & verified in BOTH envs (testing + deployment).** The only remaining work is shipping the **Flutter client build** (web/Android) so real users see the UI. Spans **three repos** + GCP infra. Nothing is committed (all working-tree changes).

---

## 0. TL;DR

After a sale/purchase scan you can now see the uploaded document in the Queue and History detail sheet. The scanned pages are stored in **Google Cloud Storage**, mapped to each invoice by the **`push_queue` row UUID**, and served back to the app through an **authenticated backend proxy** (private bucket).

- **Storage:** GCS, one **private** bucket per env. Folder name = the `push_queue` row id; objects are `{rowId}/page-{n}.jpg`.
- **Mapping:** no new DB column / FK. The backend **generates the row UUID before insert**, uploads images under that id, and stamps `source_payload.scan = { pages: N }` on the row.
- **Read:** app GETs `/api/sync/push-queue/:id/image/:page` with its Firebase token → backend streams the JPEG from GCS.
- **UI:** detail sheet is 90%×90% on web with a **two-pane** layout (image left / summary right, no toggle); phones keep the Image/Summary toggle. Image view = vertical document scroll of all pages.

---

## 1. How the request evolved (so the next chat has the why)

1. Initial ask: "we can't see the uploaded image/pdf in queue & history — show it." First plan was **on-device** persistence (there was a scaffolded-but-unused `lib/data/invoice_image_store.dart` + the sheet already had an Image/Summary tab).
2. User redirected: **store it in the backend, each image mapped to each invoice**, and use the app↔parsing↔backend interaction. → pivoted to server-side storage.
3. User chose **GCS** (both backend & parsing already run on GCP Cloud Run, so they get a keyless service-account identity). → final architecture below.
4. UI iterations on web: enlarge sheet → remove the Image/Summary slider → **side-by-side image+summary** → **make it responsive** (summary table was overflowing the pane).

Decisions locked via Q&A: **detail-view Image tab**, **all pages**, **backend uploads**, **backend-proxy read** (private bucket), **per-page JPEGs**, **two-pane on web / document vertical scroll**.

---

## 2. Architecture (the data flow)

```
App ──raw PDF──▶ tallybridge-parsing (Python, Cloud Run)
                   renders per-page JPEGs, builds voucher
                   forwards voucher + scanned_images_b64[]  (top-level)
                   ▼
                 tallybridge-backend (Node/Express, Cloud Run)  POST /api/sync/push-queue
                   rowId = randomUUID()                  (id known BEFORE insert)
                   INSERT push_queue { id, voucher_payload, source_payload:{…,scan:{pages}} }
                   upload each page → gs://<INVOICE_BUCKET>/{rowId}/page-{n}.jpg   (default compute SA)
                   ▼
        Supabase push_queue row  +  GCS objects   ── both keyed by rowId

App (Queue/History) ◀─realtime/fetch─ row carries source_payload.scan.pages + id
   open sheet → for n in 0..pages-1: GET /api/sync/push-queue/{rowId}/image/{n} (Firebase Bearer)
   backend verifies auth → streams gs://…/{rowId}/page-{n}.jpg → Image.memory(bytes)
```

- **parsing never touches Supabase or GCS** for this feature; it just forwards images to the backend.
- **backend is the only writer** to both the `push_queue` row and the invoice bucket → a single SA grant on the bucket sufficed.
- **Image bytes never touch Supabase** — only the tiny `scan.pages` marker lives on the row.

---

## 3. Code changes (all uncommitted)

### 3a. Backend — `D:\Desktop\TallyBridge\backend`
- **`package.json`** — added dep `@google-cloud/storage` (installed `^7.21.0`).
- **`src/db/gcs.ts`** — NEW. `Storage()` via Application Default Credentials (Cloud Run compute SA). Reads `process.env.INVOICE_BUCKET`. Exports:
  - `invoiceStorageEnabled` (bool — false when env unset → feature dark, queue still works)
  - `invoicePagePath(rowId, page)` → `"{rowId}/page-{page}.jpg"`
  - `uploadInvoicePages(rowId, Buffer[])` → `Promise.allSettled`, best-effort, logs failures, returns count
  - `invoicePageExists(rowId, page)`, `invoicePageReadStream(rowId, page)`
- **`src/routes/sync.ts`**:
  - imports: `randomUUID` from `crypto`; the gcs helpers.
  - **POST `/push-queue`** (existing route): reads top-level `rawBody.scanned_images_b64` (filtered `string[]`); `rowId = randomUUID()`; `pageCount = invoiceStorageEnabled ? len : 0`; merges `source_payload` with `scan:{pages}`; INSERT now passes explicit `id: rowId`; after insert, `Buffer.from(b64,'base64')` → `uploadInvoicePages` inside a try/catch (**non-fatal** — a storage failure must not fail the enqueue).
  - **NEW GET `/push-queue/:id/image/:page`**: `requireApiKey`; validates id+page; `invoicePageExists` → 404; sets `Content-Type: image/jpeg` + Cache-Control; pipes `invoicePageReadStream` to the response.
- **Env var needed at runtime:** `INVOICE_BUCKET`. Dockerfile already `npm install` + `npm run build`. `tsc` build clean.
- Note: Express body limit is **100mb** (`index.ts`, `TB_JSON_BODY_LIMIT`), so base64 images through the backend are safe. Supabase client uses the **service-role** key.

### 3b. Parsing — `D:\Desktop\TallyBridge\parsing\server\handler.py`
- Added const `INVOICE_IMAGE_DPI = int(env_value("INVOICE_IMAGE_DPI", "150"))`.
- Added helper `scanned_pages_b64(file_bytes) -> list[str]` (right after `render_pdf_bytes_to_jpeg_pages`): PDF → per-page JPEGs at 150 DPI; single image → one entry; else `[]`. base64-encodes. `try/except` returns `[]` (**non-fatal** — never blocks the push).
- **Purchase** push site (docstrange `source=runpod` branch, just before `post_to_push_queue`): `queue_request_payload["scanned_images_b64"] = scanned_pages_b64(file_bytes)`.
- **Sale** push site (`type=sale&push=queue`, just before `post_to_push_queue`): `queue_request_payload["scanned_images_b64"] = scanned_pages_b64(body)`.
- No new env for parsing (it forwards base64; the backend does the GCS upload). Entry point `n8n_minicpm_server.py` delegates to `server.handler.main`. `py_compile` clean.

### 3c. App (Flutter) — `D:\Desktop\Ai_Accountant\aiaccountant`
- **`lib/services/api_client.dart`** — `import 'dart:typed_data'`; added `getBytes(path) -> Future<Uint8List>` (GET, strips Content-Type, returns `res.bodyBytes`; sends Firebase Bearer + x-api-key via existing `_headers()`).
- **`lib/features/queue/voucher_detail_sheet.dart`** (the bulk):
  - import `api_client.dart`.
  - getters: `_imageRowId` (← `_p['__row_id']`), `_scanPageCount` (← `_p['__source_payload'].scan.pages`), `_hasStoredImages`.
  - `_applyPayload`: `hasImage = !isEmail && (widget.imageBytes != null || _hasStoredImages)` → shows the Image tab/pane.
  - `build()`: sheet height **0.9** (was 0.88); `wide = context.isWideScreen` (kDesktopBreakpoint=900); `twoPane = wide && hasImageMode`; pre-built `Widget buildSummary(ctx)` closure (loading/error/`_buildSummaryView`). **Two-pane body**: `Row[ Expanded(flex5, _buildImageView) | VerticalDivider | Expanded(flex6, LayoutBuilder→scoped MediaQuery reporting sub-880 width→ buildSummary) ]`. The scoped MediaQuery forces the summary into its **compact, horizontally-scrolling** items table so it fits the pane (responsive fix). **Narrow path** keeps `_TabPill` + the `switch(_viewMode)`.
  - `_buildImageView`: local `imageBytes` → single image; else `rowId+pages>0` → `_StoredInvoiceImages`.
  - `_StoredInvoiceImages` (rewritten from a swipe `PageView` to a **vertical `ListView`**): all pages stacked, each labeled "Page n of N", `FutureBuilder` per page → `ApiClient.getBytes('/api/sync/push-queue/$rowId/image/$page')`, cached in `_pageFutures`, `Image.memory(fitWidth)`, loading/error placeholder boxes.
- **`lib/features/queue/queue_screen.dart`** — `_openVoucherDetailSheet`: added `constraints: BoxConstraints(maxWidth: screenWidth >= 900 ? screenWidth*0.9 : double.infinity)` on `showModalBottomSheet` (lifts Material's default ~640px modal cap so the sheet reaches ~90% on web).
- **`lib/features/history/history_screen.dart`** — added `source_payload` to the `.select(...)`; `_openSheet` passes `'__source_payload': _parsePayload(row['source_payload'])`; same `constraints` on `showModalBottomSheet`.
- `flutter analyze` clean on all changed files.
- Note: `lib/data/invoice_image_store.dart` is pre-existing **dead code** (on-device store) — left untouched, NOT used by this feature.

---

## 4. Infra (DONE in both envs)

GCP envs (see also memory `gcp-environments-tallybridge`):
- **testing**: account `testing.riplara@gmail.com`, project `tally-bridge-testing-env` (828647628834), compute SA `828647628834-compute@developer.gserviceaccount.com`. App `config.dart` defaults point here.
- **deployment (prod)**: account `deployment.riplara@gmail.com`, project `tally-bridge-deployment-env` (822222628942), compute SA `822222628942-compute@developer.gserviceaccount.com`.

Per env, run (the commands that were executed):
```bash
ACCT=<env account>; PROJ=<env project>; SA=<env compute SA>; REGION=asia-south1
BUCKET=<project>-invoice-scans     # tally-bridge-testing-env-invoice-scans / tally-bridge-deployment-env-invoice-scans

gcloud storage buckets create gs://$BUCKET --account "$ACCT" --project "$PROJ" \
  --location $REGION --uniform-bucket-level-access --public-access-prevention

gcloud storage buckets add-iam-policy-binding gs://$BUCKET --account "$ACCT" --project "$PROJ" \
  --member "serviceAccount:$SA" --role roles/storage.objectAdmin

# from D:\Desktop\TallyBridge\backend  — NOTE --update-env-vars (NOT --set-env-vars; preserves existing vars)
gcloud run deploy tallybridge-backend --source . --account "$ACCT" --project "$PROJ" --region $REGION \
  --update-env-vars INVOICE_BUCKET=$BUCKET --quiet

# from D:\Desktop\TallyBridge\parsing
gcloud run deploy tallybridge-parsing --source . --account "$ACCT" --project "$PROJ" --region $REGION --quiet
```
Deployed revisions: testing `tallybridge-backend-00004-h8c` / `tallybridge-parsing-00006-2lh`; deployment `tallybridge-backend-00003-ql9` / `tallybridge-parsing-00004-q9m`. All serving 100% traffic. `INVOICE_BUCKET` confirmed set; image route returns 401 unauth (registered + gated) in both.

**Do NOT confuse buckets:** `run-sources-tally-bridge-*-asia-south1` is Cloud Run's **auto build-source** bucket (zipped deploy artifacts under `services/tallybridge-backend|parsing/`) — unrelated to invoices, ignore it. The invoice images live only in `*-invoice-scans`.

---

## 5. Verified end-to-end (live parse tests)

Single sequential curls (raw PDF, `Content-Type: application/pdf`) — concurrent requests can stall the RunPod queue, single is safe.

| Env | Doc | Row id (pending) | Pages in GCS |
|---|---|---|---|
| testing | purchase `cp.pdf` | `4c12a5f8-5bd8-4a80-ab20-c4fd63574b09` | 2 (page-0,1) |
| testing | sale `balaji_sale.pdf` | `da4e4b49-f9b7-4e66-b4a2-af8fdf11ad31` | 1 |
| deployment | purchase `cp.pdf` | `f1c13965-9cfb-4567-9bf7-d137a2775b65` | 2 |
| deployment | sale `balaji_sale.pdf` | `6b0ac27f-6aa6-476e-b01b-ed2de354b052` | 1 |

All page objects are valid JPEGs (`ffd8ffe0`) under `{rowId}/page-N.jpg`. Endpoints:
- purchase: `https://tallybridge-parsing-<num>.asia-south1.run.app/docstrange?purchase=all&source=runpod`
- sale: `https://tallybridge-parsing-<num>.asia-south1.run.app/?type=sale&push=queue`

The sale parse response **does** carry the id at `queue_response.body.job.id` (the old "sale-response-needs-job-id" note is moot here — the backend owns the id→image mapping regardless).

**These 4 `pending` test rows still exist** (2 testing, 2 deployment) — user said they'll delete them via the sheet's Delete button. They won't push to Tally unless activated.

---

## 6. What's LEFT (next chat starts here)

1. **Ship the Flutter client** — the UI changes aren't in any deployed client build yet. Build web (→ Firebase hosting `aiaccountant-b60ed`) and/or Android, pointed at the right env. **Open question:** which env file the prod web build uses (`env/deployment.json` vs `env/prod.json`). Pre-feature vouchers won't have images (they predate the GCS upload); new scans will.
2. **Delete the 4 test rows** (CP, BALAJI in each env).
3. Optional: drop an `INVOICE_IMAGES.md` in the backend/parsing repos for posterity.

---

## 7. Gotchas / facts the next chat shouldn't re-derive

- `requireApiKey` (backend `src/middleware/auth.ts`) checks the **Firebase Bearer FIRST**, then x-api-key. The app's `getBytes` sends both; it authorizes via the Bearer, so the `mrpApiKey` ≠ `API_KEY` mismatch is irrelevant.
- The mapping is **convention-based**: row UUID = GCS folder; `source_payload.scan.pages` = count. No schema migration; `source_payload` (jsonb) already flows to the app via realtime.
- Backend generates the UUID (`randomUUID()`) **before** insert so the upload path equals the row id exactly — no fuzzy correlation.
- `gcloud run deploy` from source builds via Cloud Build (Dockerfiles exist in both repos). Native Windows `python.exe`/`gcloud` choke on MSYS `/tmp` paths — pass Windows paths (`C:/Users/.../Temp/...`) to the venv python `.venv-ocrvl/Scripts/python.exe`.
- Supabase MCP token only reaches the OLD project `ztugwhevemibdrzqafyw`, NOT the live testing/deployment projects — verify via parse response + `gcloud storage ls`, not MCP.
- Parsing render DPI for storage is 150 (`INVOICE_IMAGE_DPI`), separate from OCR DPIs (200 sale / 300 purchase).

Related memory: `invoice-image-gcs-feature`, `gcp-environments-tallybridge`. Carried constraints still in force: push always sets `narration='Replara AI'`; purchase vendors = Sundry Creditors, sale customers = Sundry Debtors; publishable/anon keys only client-side; never commit secrets.
