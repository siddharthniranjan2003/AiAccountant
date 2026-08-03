import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/palette.dart';
import '../../core/config.dart';
import '../../core/error_reporter.dart';
import '../../core/indian_states.dart';
import '../../core/utils.dart';
import '../../data/customers_cache.dart';
import '../../data/vendors_cache.dart';
import '../../data/sale_pricing.dart';
import '../../data/stock_items_cache.dart';
import '../../services/api_client.dart';
import '../../services/stock_info_launcher.dart';
import '../../shared/customer_picker_sheet.dart';
import '../../shared/picker_sheet.dart';
import '../../shared/responsive.dart';
import '../stock/stock_item_create_sheet.dart';

// ── View mode enum ────────────────────────────────────────────────────────────

enum _VdsViewMode { image, summary }

// Why a queue row is a duplicate, in the same precedence as its label
// (queue_row_tile). Carries the confirm-dialog message shown before opening or
// pushing such a row. `none` = not a duplicate (no confirmation).
enum DuplicateKind { none, alreadyExistsInTally, alreadyExistsInQueue, alreadyPushed }

extension DuplicateKindMessage on DuplicateKind {
  // The text before the comma in the confirm prompts; empty for `none`.
  String get baseMessage => switch (this) {
        DuplicateKind.none => '',
        DuplicateKind.alreadyExistsInTally => 'This Invoice Already Exists In TallyPrime',
        DuplicateKind.alreadyExistsInQueue => 'This Invoice Already Exists in queue',
        DuplicateKind.alreadyPushed => 'This Invoice Is Already Pushed',
      };
}

// Lets the scanned-image scroll views be panned by click-and-drag with a mouse
// or trackpad (Flutter web only enables touch drag by default), so a zoomed-in
// document can be moved around to read any corner.
class _DragScrollBehavior extends MaterialScrollBehavior {
  const _DragScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
}

extension on _VdsViewMode {
  String get label => switch (this) {
        _VdsViewMode.image => 'Image',
        _VdsViewMode.summary => 'Summary',
      };
}

// Fixed column widths for the items table. The table is horizontally
// scrollable, so each numeric column gets enough room to never wrap to a new
// line; the Item column keeps a comfortable width and wraps long names.
const double _kItemColW = 150;
// Numeric columns are scaled up 40% on web to match the 1.4× web text (main.dart),
// so the bigger numbers don't overflow their cells.
const double _kQtyColW = kIsWeb ? 64 * 1.4 : 64;
const double _kDiscColW = kIsWeb ? 52 * 1.4 : 52;
const double _kRateColW = kIsWeb ? 88 * 1.4 : 88;
// List Price = Qty · Rate (gross, before discount). UI-only column derived at
// render time; never stored or pushed. Sized like the Taxable value column
// since it holds the same magnitude of numbers (often larger — no discount).
const double _kListPriceColW = kIsWeb ? 96 * 1.4 : 96;
const double _kAmountColW = kIsWeb ? 96 * 1.4 : 96;
const double _kDeleteColW = 40;
// Insets for the borderless Charges block so its amounts line up directly
// beneath the items table's "Taxable value" column. Item rows have, to the
// right of that column, the delete column plus the row's 12px horizontal
// padding and the table's 1.2px border; the left inset is that same padding +
// border so the charge labels start under the item content.
const double _kChargesLeftInset = 12 + 1.2;
const double _kChargesRightInset = _kDeleteColW + 12 + 1.2;
// Leading serial-number ("#") column, shown for both sale and purchase.
const double _kSerialColW = 30;
// Number of header fields that take part in the Enter-to-move chain ahead of
// the item rows: Invoice # (order 0) and Narration (order 1). Date is skipped
// (it's a tap-to-open calendar, not a typeable field). Each item row then takes
// 5 ordered stops — Item, Qty, Disc, Rate, Amount — starting at this offset.
const int _kHeaderFocusCount = 2;
const int _kCellsPerItemRow = 5;
// Column widths + the row's horizontal padding (12*2) and container border
// (~1.2*2) so the inner Row gets the full column width without overflowing.
const double _kItemsTableW =
    _kSerialColW + _kItemColW + _kQtyColW + _kRateColW + _kDiscColW + _kListPriceColW + _kAmountColW + _kDeleteColW + 27;

// Wide (desktop/pane) layouts let the Item column flex to fill all the slack
// so the numeric columns sit at the right edge — that puts the Taxable value
// column directly above the Charges amounts. Phones keep it fixed and scroll
// the table horizontally.
Widget _itemCell(bool wide, Widget child) =>
    wide ? Expanded(child: child) : SizedBox(width: _kItemColW, child: child);

// Small ⓘ button shown inline just right of an item's name. Opens the item's
// Stock Info (Purchase/Sale history) in a new browser tab. Always available,
// including the read-only History view.
Widget _infoIconButton(BuildContext context, String itemName,
        {String? partyName, bool isSale = false}) =>
    MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Party is only meaningful for a sale (the customer) — pass it so the
        // Stock Info window can scope its Sale panel to this customer + item.
        onTap: () => StockInfoLauncher.open(
          itemName: itemName,
          partyName: isSale ? partyName : null,
        ),
        child: const Padding(
          padding: EdgeInsets.only(left: 4, right: 2),
          child: Icon(Icons.info_outline_rounded, size: 16, color: AppPalette.pen),
        ),
      ),
    );

// On web the sheet is as wide as the browser, so the summary body is capped and
// centered instead of stretching edge-to-edge; phones get full width.
const double _kSheetContentMaxW = kIsWeb ? 1080 : 800;
Widget _centerOnWide(bool wide, Widget child) => wide
    ? Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _kSheetContentMaxW),
          child: child,
        ),
      )
    : child;

class VoucherDetailSheet extends StatefulWidget {
  const VoucherDetailSheet({
    super.key,
    this.payload,
    this.pendingPayload,
    this.initialIsEditing = false,
    this.initialEditableItems,
    this.onEditStateChanged,
    this.imageBytes,
    this.onDiscard,
    this.onPushed,
    this.readOnly = false,
    this.duplicateKind = DuplicateKind.none,
  }) : assert(payload != null || pendingPayload != null,
            'Provide either a resolved payload or a pendingPayload future');

  /// Resolved voucher payload (Supabase entries, or a re-opened local scan).
  final Map<String, dynamic>? payload;

  /// In-flight parse for a freshly scanned document. When set, the sheet opens
  /// immediately (showing the image) and fills Summary once it resolves.
  final Future<Map<String, dynamic>>? pendingPayload;

  final bool initialIsEditing;
  final List<Map<String, dynamic>>? initialEditableItems;
  // Reports the current edit state on every toggle/add/revert. `everSaved` is
  // true once edits have been saved back to the row this session (and false
  // again after a Revert), so the queue can tell a saved row from a viewed one.
  final void Function(bool isEditing, List<Map<String, dynamic>> items, bool everSaved)? onEditStateChanged;
  final Uint8List? imageBytes;

  /// When provided, a red "Discard" button shows at the bottom of the sheet.
  /// Confirming it calls this and pops; the queue screen drops the row locally
  /// only (no Supabase write), so a refresh re-fetches and shows it again.
  final VoidCallback? onDiscard;

  /// Called after a successful Push to Tally so the queue can re-fetch from
  /// Supabase (mirrors a manual page reload) and show the row in its new
  /// push_now state instead of relying on the realtime event, which can drop
  /// the row mid-transition.
  final VoidCallback? onPushed;

  /// Hides the Edit/Add/Revert and Push-to-Tally actions (used by History,
  /// where pushed vouchers are view-only).
  final bool readOnly;

  /// When this voucher is a duplicate (opened from a flagged queue row), the
  /// Push-to-Tally confirm shows a kind-specific warning instead of the generic
  /// prompt. `none` keeps the normal confirm.
  final DuplicateKind duplicateKind;

  @override
  State<VoucherDetailSheet> createState() => _VoucherDetailSheetState();
}

class _VoucherDetailSheetState extends State<VoucherDetailSheet> {
  Map<String, dynamic>? _payload;
  bool _loading = false;
  String? _loadError;
  late String _status;
  // Push outcome surfaced as a "Push Details" block once a row is pushed/failed:
  // when the desktop pushed it (push_queue.pushed_at) and the error if it failed.
  String? _pushedAt;
  String? _errorMessage;
  bool _isSubmitting = false;
  // True between a successful activate POST and the TallyPrime result arriving
  // over realtime (tally_response / status). While set, the sheet stays open in
  // a "pushing…" state; the result modal is shown when the row goes terminal.
  bool _awaitingPushResult = false;
  bool _isEditing = false;
  // Image pane controls (two-pane/web layout): whether the scanned image is
  // shown, and its zoom factor driven by the on-image zoom in/out buttons.
  bool _showImage = true;
  double _imageScale = 1.0;
  // True once edits have been saved back to the row in this sheet session;
  // reset by Revert. Surfaced to the queue so it can tag the row "invoice edited".
  bool _everSaved = false;
  String? _editablePartyName;
  // Editable header fields (Invoice # / Date / Narration). Date is ISO yyyy-MM-dd.
  String? _editableVoucherNumber;
  String? _editableDate;
  String? _editableNarration;
  // Captured once on first edit entry; never mutated so comparisons always
  // reference the true server/original values for this sheet session.
  String? _originalPartyName;
  List<String>? _originalItemNames;
  Map<String, dynamic>? _originalPayload;
  // Rows the user explicitly dealt with this session, by index: re-picked from
  // the item dropdown, or had qty/rate/disc/amount edited. Counts as editing the
  // line even when the name is untouched — on a line the matcher already got
  // right there is nothing to change it TO, so a name diff alone can never
  // register it. Kept in step with inserts/deletes below; cleared by Revert.
  final Set<int> _touchedRows = {};
  List<Map<String, dynamic>> _editableItems = [];
  // Editable copies of the Charges block (ledger rows + discount + total).
  // Populated when edit mode is entered; mutated in place while typing.
  List<Map<String, dynamic>> _editableLedgers = [];
  double? _editableDiscount;
  double? _editableTotal;
  // Tax ratios derived once on edit entry: ledger_name → amount/gstSale.
  // Used to scale CGST/SGST proportionally when item amounts change.
  Map<String, double> _taxRatios = {};
  String? _inventoryLedgerName;
  // The sale party's state, read from ledgers.state — the same column the parsing
  // service reads to pick CGST+SGST vs IGST. null while loading, '' when the ledger
  // has none recorded (which books CGST+SGST, matching handler.py's fallback).
  String? _partyState;
  bool _partyStateLoading = false;
  // The ledger's state for the current party as loaded — the baseline both for
  // "did the user change it?" (gates the Save write) and for what Revert restores.
  // Re-captured whenever the party changes, so it always tracks the row we'd write.
  String? _originalPartyState;
  // True only once a Save has actually written a changed state to ledgers. Revert
  // reads it to know whether a rollback write is owed (mirrors _everSaved).
  bool _ledgerStateWasWritten = false;
  RealtimeChannel? _channel;
  late _VdsViewMode _viewMode;
  late List<_VdsViewMode> _availableModes;

  // ── Shape-agnostic accessors ───────────────────────────────────────────────
  // Supabase entries are flat ({party_name, items, ledger_entries}); local scan
  // responses nest data under parsed/ocr.header + matched_items.
  Map<String, dynamic> get _p => _payload ?? const {};
  Map<String, dynamic>? get _header =>
      ((_p['parsed'] ?? _p['ocr']) as Map?)?['header'] as Map<String, dynamic>?;
  // voucher_payload lives at the top level (docstrange/purchase) or nested
  // under tally_payload (older vlm shape). Freshly-scanned sales return it as
  // sale_voucher_payload instead.
  Map<String, dynamic>? get _voucher =>
      (_p['voucher_payload'] as Map?)?.cast<String, dynamic>() ??
      (_p['sale_voucher_payload'] as Map?)?.cast<String, dynamic>() ??
      (_p['tally_payload'] as Map?)?['voucher_payload'] as Map<String, dynamic>?;
  List<Map<String, dynamic>> get _payloadItems =>
      (_voucher?['items'] as List?)?.cast<Map<String, dynamic>>() ??
      (_p['matched_items'] as List?)?.cast<Map<String, dynamic>>() ??
      (_p['items'] as List?)?.cast<Map<String, dynamic>>() ??
      const [];

  // Supabase row id this voucher belongs to (null for seed / fresh-scan rows).
  String? get _imageRowId {
    final id = _p['__row_id'] as String?;
    return (id != null && id.isNotEmpty) ? id : null;
  }

  // Number of scanned page images the backend stored for this row, read from
  // source_payload.scan.pages. 0 when none (email-sourced or pre-feature rows).
  int get _scanPageCount {
    final sp = _p['__source_payload'];
    final scan = sp is Map ? sp['scan'] : null;
    final pages = scan is Map ? scan['pages'] : null;
    if (pages is int) return pages;
    if (pages is num) return pages.toInt();
    return 0;
  }

  bool get _hasStoredImages => _imageRowId != null && _scanPageCount > 0;

  bool get _isSale {
    final vt = (_p['voucher_type'] as String? ?? '').toUpperCase();
    if (vt.isNotEmpty) return vt.contains('SALE');
    return _p.containsKey('sale_voucher_payload');
  }

  // Party name currently shown in the sheet (edited value wins, else payload).
  String get _currentPartyName =>
      _editablePartyName ??
      _p['party_name'] as String? ??
      _voucher?['party_name'] as String? ??
      _voucher?['party_ledger_name'] as String? ??
      _header?['vendor_name'] as String? ??
      '—';

  // True when the party name currently shown differs from the original captured
  // at first edit entry. Stays true across save cycles.
  bool get _partyNameWasChanged {
    if (_originalPartyName == null) return false;
    final current = _editablePartyName ??
        _p['party_name'] as String? ??
        _voucher?['party_name'] as String? ??
        _voucher?['party_ledger_name'] as String? ??
        _header?['vendor_name'] as String? ?? '—';
    return current != _originalPartyName;
  }

  // True when every item in the current view was dealt with since the sheet was
  // first opened: renamed away from its original, or explicitly touched
  // (_touchedRows — a same-item re-pick or a numeric edit, which a name diff
  // can't see). Checks _editableItems during edit mode and _payloadItems in
  // view mode so it stays correct across save cycles.
  bool get _allItemsDifferentFromOriginal {
    final origNames = _originalItemNames;
    if (origNames == null || origNames.isEmpty) return true;
    final currentItems = _isEditing ? _editableItems : _payloadItems;
    for (var i = 0; i < origNames.length; i++) {
      if (i >= currentItems.length) continue; // item deleted — counts as changed
      if (_touchedRows.contains(i)) continue; // explicitly dealt with this session
      final currentName = currentItems[i]['stock_item_name'] as String? ?? '';
      if (currentName == origNames[i]) return false;
    }
    return true;
  }

  static const _activateUrl = Config.activateUrl;
  static const _apiKey = Config.activateApiKey;
  // Every Push to Tally overwrites the voucher narration with this fixed value.
  static const _pushNarration = 'Replara AI';

  @override
  void initState() {
    super.initState();
    _isEditing = widget.initialIsEditing;

    if (widget.payload != null) {
      _status = widget.payload!['__status'] as String? ?? 'pending';
      _pushedAt = widget.payload!['__pushed_at'] as String?;
      _errorMessage = widget.payload!['__error_message'] as String?;
      _applyPayload(widget.payload!);
      // Open editable rows straight into edit mode so the sheet is ready to edit
      // without tapping Edit first. Only pending rows are editable; once queued
      // for push (push_now/pushed) or failed, the sheet stays read-only — same
      // gate as _toggleEdit.
      if (_status == 'pending') _isEditing = true;
      // Seed the edit session from the payload — same as tapping Edit — so the
      // items show even after a reload wiped the in-memory edit stash. If that
      // stash survived (same session), its in-progress items take precedence.
      if (_isEditing) {
        _seedEditSession();
        if (widget.initialEditableItems != null &&
            widget.initialEditableItems!.isNotEmpty) {
          _editableItems = widget.initialEditableItems!
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      }
    } else {
      // Freshly scanned: show the image immediately while the parse is in flight.
      _status = 'processing';
      _loading = true;
      _availableModes = [
        if (widget.imageBytes != null) _VdsViewMode.image,
        _VdsViewMode.summary,
      ];
      _viewMode = _availableModes.first;
      widget.pendingPayload!.then(_onPendingResolved).catchError(_onPendingError);
    }
  }

  // Decide which tabs to show. Entries with a scanned image get [Image, Summary];
  // those without (e.g. pre-feature rows) get [Summary].
  void _applyPayload(Map<String, dynamic> p, {bool preserveViewMode = false}) {
    _payload = p;
    _hydrateRawOcr();
    final rowId = p['__row_id'] as String? ?? '';
    if (rowId.isNotEmpty) _subscribeToStatus(rowId);

    // Show the Image tab when there's a local fresh-scan image OR scanned pages
    // were stored in GCS for this row (source_payload.scan.pages > 0). Email-sourced
    // invoices now carry scanned pages too, so they get the Image tab like camera scans.
    final hasImage = widget.imageBytes != null || _hasStoredImages;
    final keep = preserveViewMode ? _viewMode : null;
    _availableModes = [
      if (hasImage) _VdsViewMode.image,
      _VdsViewMode.summary,
    ];
    _viewMode = (keep != null && _availableModes.contains(keep)) ? keep : _availableModes.first;

    // Resolve the sale party's state for the GST-head row. Async and fail-soft —
    // the sheet renders immediately and the row fills in when it lands.
    _loadPartyState();
  }

  // Copies each line's OCR text from source_payload onto the voucher item itself.
  // The two lists are index-aligned exactly as the parser wrote them, but the editor
  // can insert and delete lines, so pairing by index is only sound before any edit.
  // Once copied, raw_ocr rides the item through renames/inserts/deletes, and saving
  // persists it (the app writes voucher_payload to push_queue directly, so nothing
  // strips it) — which is why a re-opened, already-edited row must not be re-paired.
  // Bail out entirely on any length mismatch rather than risk learning a wrong pair.
  void _hydrateRawOcr() {
    final items = _payloadItems;
    if (items.isEmpty) return;
    if (items.any((it) => ((it['raw_ocr'] as String?) ?? '').isNotEmpty)) return;

    final sourcePayload = _p['source_payload'] ?? _p['__source_payload'];
    final sourceItems = (sourcePayload is Map ? sourcePayload['items'] : null) as List?;
    if (sourceItems == null || sourceItems.length != items.length) return;

    for (var i = 0; i < items.length; i++) {
      final source = sourceItems[i];
      final rawOcr = source is Map ? (source['raw_ocr'] as String?) ?? '' : '';
      if (rawOcr.isNotEmpty) items[i]['raw_ocr'] = rawOcr;
    }
  }

  void _onPendingResolved(Map<String, dynamic> p) {
    if (!mounted) return;
    final dup = p['duplicacy'];
    final isDuplicate = dup == true ||
        (dup is Map &&
            (dup['is_duplicate'] == true || dup['invoice_exists'] == true));
    if (isDuplicate) {
      final rootCtx = Navigator.of(context, rootNavigator: true).context;
      Navigator.of(context).pop();
      showDialog<void>(context: rootCtx, builder: (_) => const _DuplicatePurchaseDialog());
      return;
    }
    setState(() {
      _loading = false;
      _status = p['__status'] as String? ?? 'pending';
      _pushedAt = p['__pushed_at'] as String?;
      _errorMessage = p['__error_message'] as String?;
      _applyPayload(p, preserveViewMode: true);
    });
  }

  void _onPendingError(Object e, StackTrace st) {
    if (!mounted) return;
    setState(() {
      _loading = false;
      _loadError = '$e';
    });
  }

  void _notifyEditState() {
    widget.onEditStateChanged?.call(_isEditing, List.of(_editableItems), _everSaved);
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  // Enters edit mode: captures the originals snapshot (once per sheet lifetime)
  // and seeds the editable copies of the items and charges from _payloadItems.
  // Pure field mutation — callers (the Edit toggle, and initState when the sheet
  // opens straight into edit mode after a reload) supply their own setState
  // context, so this must not call setState itself.
  void _seedEditSession() {
    final items = _payloadItems;
    // Entering edit mode — capture originals once for the lifetime of the sheet
    _editablePartyName = null;
    _editableVoucherNumber = null;
    _editableDate = null;
    _editableNarration = null;
    if (_originalPartyName == null) {
      _originalPartyName = _p['party_name'] as String? ??
          _voucher?['party_name'] as String? ??
          _voucher?['party_ledger_name'] as String? ??
          _header?['vendor_name'] as String?;
      _originalItemNames =
          items.map((e) => e['stock_item_name'] as String? ?? '').toList();
      _originalPayload = _payload != null ? Map<String, dynamic>.from(_payload!) : null;
    }
    _editableItems = items.map((e) => Map<String, dynamic>.from(e)).toList();
    // Many purchase rows store the discount baked into `amount` with no
    // discount_pct field (rate·qty ≠ amount). Derive and seed discount_pct
    // so the Disc cell, _recalcAmount, and the Charges discount all agree.
    // Full precision (unrounded) so _recalcAmount reproduces the original
    // amount exactly when qty/rate are unchanged. No-op when present.
    for (final it in _editableItems) {
      if (it['discount_pct'] != null) continue;
      final q = (it['quantity'] as num?)?.toDouble() ??
          (it['qty'] as num?)?.toDouble() ?? 0;
      final r = (it['rate'] as num?)?.toDouble() ?? 0;
      final a = (it['amount'] as num?)?.toDouble() ?? 0;
      final gross = q * r;
      if (gross > 0) {
        it['discount_pct'] = ((1 - a / gross) * 100).clamp(0.0, 100.0);
      }
    }
    final charges = _computeCharges();
    _editableLedgers =
        charges.breakdown.map((e) => Map<String, dynamic>.from(e)).toList();
    _editableDiscount = charges.discount;
    _editableTotal = charges.total;
    _inventoryLedgerName = charges.invLedger;
    _taxRatios = {};
    if (charges.invLedger != null) {
      final gstSaleEntry = charges.breakdown.where(
        (e) => e['ledger_name'] == charges.invLedger).firstOrNull;
      final originalGstSale =
          (gstSaleEntry?['amount'] as num?)?.toDouble().abs() ?? 0;
      if (originalGstSale > 0) {
        for (final entry in charges.breakdown) {
          final name = entry['ledger_name'] as String? ?? '';
          if (name != charges.invLedger) {
            final amount = (entry['amount'] as num?)?.toDouble().abs() ?? 0;
            _taxRatios[name] = amount / originalGstSale;
          }
        }
      }
    }
  }

  void _toggleEdit() {
    // Only pending rows are editable; once tallybridge owns the row
    // (push_now / pushed) its payload must not change underneath it.
    if (!_isEditing && _status != 'pending') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This voucher is already queued for push and can\'t be edited.'),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }
    if (!_isEditing && StockItemsCache.instance.isLoading) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Loading of stock items in process, please wait'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    setState(() {
      if (!_isEditing) {
        _seedEditSession();
      } else {
        // Saving — write all edits back into the local payload so that
        // _payloadItems and party_name reflect the saved state immediately.
        if (_payload != null) {
          final updated = Map<String, dynamic>.from(_payload!);
          if (_editablePartyName != null) {
            updated['party_name'] = _editablePartyName;
          }
          if (_editableVoucherNumber != null) {
            updated['voucher_number'] = _editableVoucherNumber;
          }
          if (_editableDate != null) updated['date'] = _editableDate;
          if (_editableNarration != null) updated['narration'] = _editableNarration;
          if (_editableItems.isNotEmpty) {
            if (updated['voucher_payload'] is Map) {
              final vp = Map<String, dynamic>.from(updated['voucher_payload'] as Map);
              vp['items'] = List<Map<String, dynamic>>.from(_editableItems);
              updated['voucher_payload'] = vp;
            } else if ((updated['tally_payload'] as Map?)?['voucher_payload'] is Map) {
              final tp = Map<String, dynamic>.from(updated['tally_payload'] as Map);
              final vp = Map<String, dynamic>.from(tp['voucher_payload'] as Map);
              vp['items'] = List<Map<String, dynamic>>.from(_editableItems);
              tp['voucher_payload'] = vp;
              updated['tally_payload'] = tp;
            } else if (updated.containsKey('matched_items')) {
              updated['matched_items'] = List<Map<String, dynamic>>.from(_editableItems);
            } else {
              updated['items'] = List<Map<String, dynamic>>.from(_editableItems);
            }
          }
          // Write the recomputed charges back too, so ledger_entries and
          // discount_total reflect the edited items (not just party/items).
          _writeChargesBack(updated);
          _payload = updated;
          _persistEditsToSupabase(updated);
          _everSaved = true;
          // Save is the single commit point for the party's state too. Gated on a
          // real change so re-saving never rewrites the ledger with its own value.
          // _originalPartyState is deliberately NOT advanced here — Revert needs
          // the pre-edit original to restore.
          if (_partyState != null && _partyState != (_originalPartyState ?? '')) {
            _persistPartyState(_partyState!);
            _ledgerStateWasWritten = true;
          }
        }
        _editablePartyName = null;
        _editableVoucherNumber = null;
        _editableDate = null;
        _editableNarration = null;
      }
      _isEditing = !_isEditing;
    });
    _notifyEditState();
  }


  // Discards every edit (items + charges) and leaves edit mode, restoring the
  // original parsed values. Since edit mode is off afterwards, the Revert
  // button hides until Edit is tapped again.
  void _revert() {
    // Whether this session actually changed the server payload (the only thing a
    // revert needs to undo). Captured before setState clears it below.
    final didSave = _everSaved;
    setState(() {
      _isEditing = false;
      _everSaved = false;
      _editablePartyName = null;
      _editableVoucherNumber = null;
      _editableDate = null;
      _editableNarration = null;
      _editableItems = [];
      _editableLedgers = [];
      _editableDiscount = null;
      _editableTotal = null;
      _taxRatios = {};
      _inventoryLedgerName = null;
      _touchedRows.clear();
      // Put the State row back to the value the ledger held before this session.
      _partyState = _originalPartyState;
      if (_originalPayload != null) {
        _payload = Map<String, dynamic>.from(_originalPayload!);
      }
    });
    _notifyEditState();
    // Undo the ledger write too, on the same principle as the payload write below:
    // only when a Save actually changed it. A pick that was never saved wrote
    // nothing, so there is nothing to restore.
    if (_ledgerStateWasWritten && _originalPartyState != null) {
      _persistPartyState(_originalPartyState!);
      _ledgerStateWasWritten = false;
    }
    // Only write to the server when a Save actually changed the payload this
    // session — that's the only thing a revert needs to undo. When nothing was
    // saved the DB row is already the original, so rewriting voucher_payload is a
    // no-op that only makes the backend re-touch the row's status; the queue's
    // status-filtered refresh then briefly drops the row, making it vanish and
    // reappear. Skip the write and just confirm the (UI-only) revert.
    if (didSave && _originalPayload != null) {
      _persistEditsToSupabase(_originalPayload!, successMessage: 'Reverted to original.');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reverted to original.'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  // _touchedRows is index-keyed, so inserting or deleting a line shifts every
  // following row's index; slide the marks along or they land on neighbouring
  // rows — which could unblock a push on lines nobody reviewed.
  void _touchedAfterInsert(int at) {
    final shifted = <int>{for (final j in _touchedRows) j >= at ? j + 1 : j};
    _touchedRows
      ..clear()
      ..addAll(shifted)
      ..add(at); // the inserted line is a deliberate pick
  }

  void _touchedAfterDelete(int at) {
    final shifted = <int>{
      for (final j in _touchedRows)
        if (j != at) j > at ? j - 1 : j,
    };
    _touchedRows
      ..clear()
      ..addAll(shifted);
  }

  // Adds a new line to the voucher. Opens the stock picker (sale → party-aware
  // history; purchase → catalog) and inserts the chosen item into _editableItems
  // (qty defaults to 1), then rescales the Charges block. Persists on Save.
  // `at` places the line at that index (used by the between-rows insert dividers
  // to match the paper invoice order); null appends to the end (toolbar "Add").
  Future<void> _addItem({int? at}) async {
    // Adding a line is an edit, so enter edit mode first if we aren't already.
    // _toggleEdit captures the originals snapshot and seeds the editable copies,
    // and enforces the pending/loading guards (it stays in view mode if blocked).
    if (!_isEditing) {
      _toggleEdit();
      if (!_isEditing) return;
    }
    final partyName = _editablePartyName ??
        _p['party_name'] as String? ??
        _voucher?['party_name'] as String? ??
        _voucher?['party_ledger_name'] as String? ??
        _header?['vendor_name'] as String?;
    final selected = await showModalBottomSheet<StockItem>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _StockItemPickerSheet(
        partyName: partyName,
        isSale: _isSale,
        voucherItemNames: _editableItems
            .map((it) => (it['stock_item_name'] as String?) ?? '')
            .toList(),
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      const qty = 1.0;
      final gross = qty * selected.rate;
      final discount = gross * selected.discountPct / 100;
      // The pushed voucher / Tally XML should carry the stock master's unit.
      // Prefer the picked item's own unit; the party-specific RPC may omit it,
      // so fall back to the catalog cache by name, then to NOS as a last resort.
      final unit = selected.unit.isNotEmpty
          ? selected.unit
          : StockItemsCache.instance.unitFor(selected.name);
      final newItem = {
        'stock_item_name': selected.name,
        'quantity': qty,
        'rate': selected.rate,
        'discount_pct': selected.discountPct,
        'amount': gross - discount,
        'unit': unit.isNotEmpty ? unit : 'NOS',
        'godown_name': 'Main Location',
        // Carry the same nullable keys every parsed item has, so the persisted
        // items array stays homogeneous and the Tally push can't hit a missing
        // key on an added/inserted line.
        'batch_name': null,
        'destination_godown_name': null,
        // Local-only provenance (stripped before the voucher_payload write, then
        // written to source_payload) so a reviewed line records where its rate
        // and discount actually came from.
        if (_isSale) '__rate_source': selected.source,
        if (_isSale) '__discount_source': selected.discountSource,
      };
      // Clamp the insert index defensively; null (toolbar Add) appends.
      if (at != null && at >= 0 && at <= _editableItems.length) {
        _editableItems.insert(at, newItem);
        _touchedAfterInsert(at);
      } else {
        _editableItems.add(newItem);
        _touchedRows.add(_editableItems.length - 1);
      }
    });
    _recomputeChargesFromItems();
    _notifyEditState();
  }

  // Header "Create New Item": creates a stock master in TallyPrime only. It does
  // not add a line to this voucher (that is what Add does, which can create from
  // inside its picker and then append the result). The created item lands in
  // StockItemsCache, so a later Add finds it without waiting for the next sync.
  Future<void> _createStockItem() => showStockItemCreateSheet(context);

  // Opens a calendar for the Date field and stores the pick as ISO yyyy-MM-dd.
  Future<void> _pickDate(BuildContext context, String? rawDate) async {
    final initial = DateTime.tryParse(rawDate ?? '') ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    final iso = '${picked.year.toString().padLeft(4, '0')}-'
        '${picked.month.toString().padLeft(2, '0')}-'
        '${picked.day.toString().padLeft(2, '0')}';
    setState(() => _editableDate = iso);
  }

  // ── Party state → GST head ────────────────────────────────────────────────
  // The sale tax head is chosen from the party's ledgers.state. The app reads
  // that column directly rather than via CustomersCache: the cache holds only
  // "Sundry Debtors", but the parser matches parties from vouchers.party_name in
  // any group (TRADERS, MANUFACTURER_*, …), so the cache would miss them.
  // ledgers.name is unique, so limit(1) is exact.

  static const _gstLedgerNames = {'CGST', 'SGST', 'IGST'};

  Future<void> _loadPartyState() async {
    if (!_isSale) return;
    final party = _currentPartyName;
    if (party.isEmpty || party == '—') return;
    setState(() => _partyStateLoading = true);
    try {
      final rows = await Supabase.instance.client
          .from('ledgers')
          .select('state')
          .eq('name', party)
          .limit(1);
      final list = (rows as List).cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        // '' (no state recorded) and "no ledger row" are the same thing here:
        // unknown, which books CGST+SGST. Distinct from null = still loading.
        _partyState = list.isEmpty ? '' : (list.first['state'] as String? ?? '');
        // Whatever the ledger says right now is the baseline: Save writes only if
        // the user moves away from it, and Revert restores back to it.
        _originalPartyState = _partyState;
        _partyStateLoading = false;
      });
    } catch (e, st) {
      reportHandledError('supabase.ledgers.state.fetch', e, stackTrace: st);
      if (!mounted) return;
      setState(() {
        _partyState = '';
        _originalPartyState = '';
        _partyStateLoading = false;
      });
    }
  }

  // Rebuilds the GST rows from [state]. Unlike _recomputeChargesFromItems (which
  // scales existing rows by _taxRatios), this REPLACES them: switching between
  // intra- and inter-state changes which ledgers exist, not just their amounts.
  // Rates mirror handler.py's SALE_GST_RATE / SALE_IGST_RATE so the app and the
  // parser agree to the paisa.
  void _applyStateToTaxRows(String state) {
    if (_editableLedgers.isEmpty || _inventoryLedgerName == null) return;
    final taxable = _editableLedgers
            .where((e) => e['ledger_name'] == _inventoryLedgerName)
            .map((e) => (e['amount'] as num?)?.toDouble().abs() ?? 0)
            .firstOrNull ??
        0;

    final rebuilt = <Map<String, dynamic>>[
      // Everything that isn't a GST row survives untouched (the taxable row and
      // any other charge line).
      for (final e in _editableLedgers)
        if (!_gstLedgerNames.contains(e['ledger_name'])) e,
    ];
    if (isIntraState(state)) {
      final half = double.parse((taxable * 0.09).toStringAsFixed(2));
      if (half > 0) {
        rebuilt.add({'ledger_name': 'CGST', 'amount': half, 'is_deemed_positive': false});
        rebuilt.add({'ledger_name': 'SGST', 'amount': half, 'is_deemed_positive': false});
      }
    } else {
      final full = double.parse((taxable * 0.18).toStringAsFixed(2));
      if (full > 0) {
        rebuilt.add({'ledger_name': 'IGST', 'amount': full, 'is_deemed_positive': false});
      }
    }

    setState(() {
      _editableLedgers = rebuilt;
      // Re-derive the ratios so a later qty/rate edit scales the NEW rows.
      _taxRatios = {};
      if (taxable > 0) {
        for (final e in rebuilt) {
          final name = e['ledger_name'] as String? ?? '';
          if (name != _inventoryLedgerName) {
            _taxRatios[name] = ((e['amount'] as num?)?.toDouble().abs() ?? 0) / taxable;
          }
        }
      }
      _editableTotal = rebuilt.fold<double>(
          0, (sum, e) => sum + ((e['amount'] as num?)?.toDouble().abs() ?? 0));
    });
  }

  // The customer's state, shown as a tappable value between the taxable subtotal
  // and the tax rows. Reads "Select state" when the ledger has none recorded —
  // that case still bills CGST+SGST, so the prompt is an invitation, not an error.
  Widget _buildPartyStateRow() {
    final state = _partyState ?? '';
    final loading = _partyStateLoading && _partyState == null;
    // Editable only in edit mode, like every other field. On an already-pushed
    // voucher the tax rows can't change, so offering the picker there would be a
    // half-action: it could move the ledger but never the voucher.
    final canPick = _isEditing && !loading;
    final label = loading
        ? 'Loading…'
        : (state.isEmpty ? (canPick ? 'Select state' : '—') : state);
    final labelStyle = Theme.of(context).textTheme.bodySmall;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text('State',
                style: labelStyle?.copyWith(color: AppPalette.muted)),
          ),
          InkWell(
            onTap: canPick ? _pickPartyState : null,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: labelStyle?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: state.isEmpty ? AppPalette.muted : AppPalette.inkSoft,
                    ),
                  ),
                  if (canPick) ...[
                    const SizedBox(width: 2),
                    Icon(Icons.arrow_drop_down, size: 18, color: AppPalette.muted),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Opens the state picker and applies the pick to the tax rows on screen only.
  // Nothing is written to Supabase here — Save persists both the voucher's GST and
  // ledgers.state, so a pick followed by Revert leaves the database untouched.
  Future<void> _pickPartyState() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PickerSheet<String>(
        items: kIndianStates,
        labelOf: (s) => s,
        searchHint: 'Search states…',
        selected: (_partyState ?? '').isEmpty ? null : _partyState,
      ),
    );
    if (picked == null || !mounted) return;
    // Re-picking the same state is a no-op: nothing to recompute, nothing to write.
    if (picked == _partyState) return;
    setState(() => _partyState = picked);
    _applyStateToTaxRows(picked);
  }

  // Writes [state] onto the party's ledgers row. Called from Save (with the newly
  // picked state) and from Revert (with the original, to undo it) — never on pick.
  // Fail-soft: the voucher edit is the important part, so a rejected write only
  // warns.
  // NOTE: the Tally master sync upserts whole ledger rows (backend sync.ts), so
  // this is overwritten on the next sync unless the state is fixed in Tally too.
  Future<void> _persistPartyState(String state) async {
    final party = _currentPartyName;
    if (party.isEmpty || party == '—') return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await Supabase.instance.client
          .from('ledgers')
          .update({'state': state}).eq('name', party);
    } catch (e, st) {
      reportHandledError('supabase.ledgers.state.update', e, stackTrace: st);
      messenger.showSnackBar(
        SnackBar(
          content: Text('Couldn\'t save the state to $party: $e'),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  void _recomputeChargesFromItems() {
    if (_editableLedgers.isEmpty || _inventoryLedgerName == null) return;
    final newGstSale = _editableItems.fold<double>(
        0, (sum, item) => sum + ((item['amount'] as num?)?.toDouble() ?? 0));
    final newDiscount = _editableItems.fold<double>(0, (sum, item) {
      final qty = (item['quantity'] as num?)?.toDouble() ??
          (item['qty'] as num?)?.toDouble() ?? 0;
      final rate = (item['rate'] as num?)?.toDouble() ?? 0;
      final discPct = (item['discount_pct'] as num?)?.toDouble() ?? 0;
      return sum + (qty * rate * discPct / 100);
    });
    setState(() {
      for (final entry in _editableLedgers) {
        final name = entry['ledger_name'] as String? ?? '';
        if (name == _inventoryLedgerName) {
          entry['amount'] = newGstSale;
        } else if (_taxRatios.containsKey(name)) {
          entry['amount'] = newGstSale * _taxRatios[name]!;
        }
      }
      _editableDiscount = newDiscount;
      _editableTotal = _editableLedgers.fold<double>(
          0, (sum, e) => sum + ((e['amount'] as num?)?.toDouble().abs() ?? 0));
    });
  }

  // Writes the recomputed charges (ledger_entries + discount_total) back into
  // the given flat payload. Matches ledgers by name; the party entry (largest
  // abs amount) takes the new total. Each entry's original sign is preserved.
  void _writeChargesBack(Map<String, dynamic> target) {
    if (_editableLedgers.isEmpty) return;
    final ledgerEntries =
        (target['ledger_entries'] as List?)?.cast<Map<String, dynamic>>();
    if (ledgerEntries == null || ledgerEntries.isEmpty) return;

    final partyEntry = ledgerEntries.reduce((a, b) =>
        ((a['amount'] as num).abs() >= (b['amount'] as num).abs() ? a : b));

    final editedByName = {
      for (final e in _editableLedgers) e['ledger_name'] as String? ?? '': e,
    };

    final rebuilt = ledgerEntries.map((entry) {
      final updated = Map<String, dynamic>.from(entry);
      final originalAmount = (entry['amount'] as num?)?.toDouble() ?? 0;
      final sign = originalAmount < 0 ? -1 : 1;
      if (identical(entry, partyEntry)) {
        updated['amount'] = (_editableTotal ?? originalAmount.abs()) * sign;
        // The party line is matched by ledger_name == party_name, so a vendor
        // change must rename it too — otherwise the pushed voucher posts against
        // the old vendor ledger.
        final newParty = _editablePartyName?.trim();
        if (newParty != null && newParty.isNotEmpty) {
          updated['ledger_name'] = newParty;
        }
      } else {
        final name = entry['ledger_name'] as String? ?? '';
        final edited = editedByName[name];
        if (edited != null) {
          final newAmount = (edited['amount'] as num?)?.toDouble().abs() ?? originalAmount.abs();
          updated['amount'] = newAmount * sign;
        }
      }
      return updated;
    }).toList();

    // A state change swaps which GST ledgers exist (CGST+SGST ↔ IGST), so the
    // 1:1 map above isn't enough on its own: it would keep rows the new head
    // doesn't have and miss ones it does. Drop any GST row no longer present in
    // _editableLedgers, then append the ones that were added. Non-GST rows are
    // left entirely to the mapping above.
    final editedGstNames = {
      for (final e in _editableLedgers)
        if (_gstLedgerNames.contains(e['ledger_name'])) e['ledger_name'] as String,
    };
    rebuilt.removeWhere((e) =>
        !identical(e, partyEntry) &&
        _gstLedgerNames.contains(e['ledger_name']) &&
        !editedGstNames.contains(e['ledger_name']));
    final presentNames = rebuilt.map((e) => e['ledger_name']).toSet();
    for (final e in _editableLedgers) {
      final name = e['ledger_name'] as String? ?? '';
      if (_gstLedgerNames.contains(name) && !presentNames.contains(name)) {
        // Tax ledgers are credits on a sale, same sign convention handler.py uses.
        rebuilt.add({
          'ledger_name': name,
          'amount': (e['amount'] as num?)?.toDouble().abs() ?? 0,
          'is_deemed_positive': false,
        });
      }
    }

    target['ledger_entries'] = rebuilt;
    if (_editableDiscount != null) {
      target['discount_total'] = _editableDiscount;
    }
  }

  // Pushes the edited voucher_payload back to the push_queue row. Only touches
  // rows still in 'pending' (a row already flipped to push_now/pushed by
  // tallybridge is left alone). Fire-and-forget with a confirm/warn snackbar.
  Future<void> _persistEditsToSupabase(
    Map<String, dynamic> updated, {
    String successMessage = 'Changes saved.',
  }) async {
    final rowId = updated['__row_id'] as String? ?? '';
    if (rowId.isEmpty) return; // seed / fresh-scan rows have no Supabase row
    final messenger = ScaffoldMessenger.of(context);
    // ORDER MATTERS. Map.from is a shallow copy, so cleanPayload shares its item
    // maps with `updated` (and with _editableItems). _stripItemLocalKeys mutates
    // those shared maps, deleting __rate_source/__discount_source — so the
    // provenance has to be read out BEFORE the strip runs, or it is always gone
    // and every line silently falls back to its previous rate_source.
    final sourcePayload = _rebuiltSourcePayload(updated);
    final cleanPayload = Map<String, dynamic>.from(updated)
      ..removeWhere((k, _) => k.startsWith('__'));
    _stripItemLocalKeys(cleanPayload);
    final update = <String, dynamic>{'voucher_payload': cleanPayload};
    if (sourcePayload != null) update['source_payload'] = sourcePayload;
    try {
      final rows = await Supabase.instance.client
          .from('push_queue')
          .update(update)
          .eq('id', rowId)
          .eq('status', 'pending')
          .select('id');
      messenger.showSnackBar(
        SnackBar(
          content: Text((rows as List).isNotEmpty
              ? successMessage
              : 'Couldn\'t save — this voucher may already be queued for push.'),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e, st) {
      reportHandledError('supabase.push_queue.update', e,
          stackTrace: st, context: {'row_id': rowId});
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Couldn\'t save changes. Please try again.'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  // Drops the local-only `__rate_source` / `__discount_source` keys from every
  // items array in the payload. They exist so a re-priced line can carry its
  // provenance as far as the save; they belong in source_payload, not in the
  // voucher the backend pushes to Tally (whose normalizer would drop them
  // anyway, but storing them would still muddy the stored JSON).
  void _stripItemLocalKeys(Map<String, dynamic> payload) {
    void clean(Object? list) {
      if (list is! List) return;
      for (final item in list) {
        if (item is Map) item.removeWhere((k, _) => k.toString().startsWith('__'));
      }
    }

    clean(payload['items']);
    clean(payload['matched_items']);
    for (final key in ['voucher_payload', 'sale_voucher_payload']) {
      final vp = payload[key];
      if (vp is Map) clean(vp['items']);
    }
    final tp = payload['tally_payload'];
    if (tp is Map && tp['voucher_payload'] is Map) {
      clean((tp['voucher_payload'] as Map)['items']);
    }
  }

  // The items array inside an arbitrary payload map, resolved in the same order
  // as the _voucher / _payloadItems getters. Those read the live _p; this takes
  // the map explicitly so it also works for the payload being persisted.
  List<Map<String, dynamic>> _itemsOf(Map<String, dynamic> payload) {
    final voucher = (payload['voucher_payload'] as Map?)?.cast<String, dynamic>() ??
        (payload['sale_voucher_payload'] as Map?)?.cast<String, dynamic>() ??
        (payload['tally_payload'] as Map?)?['voucher_payload'] as Map<String, dynamic>?;
    return (voucher?['items'] as List?)?.cast<Map<String, dynamic>>() ??
        (payload['matched_items'] as List?)?.cast<Map<String, dynamic>>() ??
        (payload['items'] as List?)?.cast<Map<String, dynamic>>() ??
        const [];
  }

  // Rebuilds source_payload so its per-item provenance matches the numbers now
  // on the voucher. Returns null when there is nothing to write.
  //
  // Reads the items out of the payload being persisted rather than out of
  // _editableItems: Revert clears _editableItems and then persists
  // _originalPayload, so keying off widget state wrote an empty items array and
  // wiped the whole voucher's provenance. Sourcing from the payload means Save
  // sees the edits and Revert sees the original, which is what each one wants.
  //
  // Two things are deliberately preserved rather than regenerated:
  //   * `source` / `score` for lines whose stock_item_name is unchanged — those
  //     came from the OCR matcher and the app has no way to recompute them.
  //   * every non-`items` key, notably `scan`, which carries the page count the
  //     app needs to offer the Image button.
  Map<String, dynamic>? _rebuiltSourcePayload(Map<String, dynamic> updated) {
    if (!_isSale) return null;
    final sourceItems = _itemsOf(updated);
    // Nothing to describe — leave whatever provenance the row already has rather
    // than replacing it with an empty array.
    if (sourceItems.isEmpty) return null;
    final existing = updated['__source_payload'] ?? updated['source_payload'];
    final prior = <String, Map<String, dynamic>>{};
    if (existing is Map && existing['items'] is List) {
      for (final it in existing['items'] as List) {
        if (it is Map) {
          final name = (it['stock_item_name'] as String? ?? '').trim();
          if (name.isNotEmpty) prior[name] = Map<String, dynamic>.from(it);
        }
      }
    }

    final items = <Map<String, dynamic>>[];
    for (final item in sourceItems) {
      final name = (item['stock_item_name'] as String? ?? '').trim();
      final was = prior[name];
      final qty = (item['quantity'] as num?)?.toDouble() ??
          (item['qty'] as num?)?.toDouble() ??
          0;
      items.add({
        'stock_item_name': name,
        'quantity': qty,
        'rate': (item['rate'] as num?)?.toDouble() ?? 0,
        'amount': (item['amount'] as num?)?.toDouble() ?? 0,
        'discount_pct': (item['discount_pct'] as num?)?.toDouble() ?? 0,
        'unit': item['unit'],
        'godown_name': item['godown_name'],
        // Matcher provenance survives only while the item identity does.
        'source': was?['source'] ?? 'User_Edited',
        if (was?['score'] != null) 'score': was!['score'],
        // A line the user never re-picked keeps whatever the backend stamped.
        'rate_source':
            item['__rate_source'] as String? ?? was?['rate_source'] ?? 'none',
        'discount_source': item['__discount_source'] as String? ??
            was?['discount_source'] ??
            'none',
      });
    }

    final out = <String, dynamic>{};
    if (existing is Map) {
      out.addAll(Map<String, dynamic>.from(existing)..remove('items'));
    }
    out['items'] = items;
    return out;
  }

  // Derives the Charges block: the non-party ledger rows, the invoice total,
  // the discount, and which ledger is the inventory (rupee) one. Used by both
  // build() and _toggleEdit() so seeding the editable copies stays in sync.
  ({
    List<Map<String, dynamic>> breakdown,
    double total,
    double discount,
    String? invLedger,
  }) _computeCharges() {
    final voucher = _voucher;
    final header = _header;
    final ledgerEntries =
        (_p['ledger_entries'] as List?)?.cast<Map<String, dynamic>>() ??
        (voucher?['ledger_entries'] as List?)?.cast<Map<String, dynamic>>() ??
        [];
    final partyEntry = ledgerEntries.isNotEmpty
        ? ledgerEntries.reduce((a, b) =>
            ((a['amount'] as num).abs() >= (b['amount'] as num).abs() ? a : b))
        : null;
    final taxEntries =
        (header?['tax_entries'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final total = (partyEntry?['amount'] as num?)?.toDouble().abs() ??
        (header?['invoice_total'] as num?)?.toDouble() ??
        0.0;
    final breakdown = partyEntry == null
        ? (ledgerEntries.isNotEmpty ? ledgerEntries : taxEntries)
        : ledgerEntries.where((e) => e != partyEntry).toList();
    final discount = (_p['discount_total'] as num?)?.toDouble() ??
        (voucher?['discount_total'] as num?)?.toDouble() ??
        _payloadItems.fold<double>(0, (sum, it) {
          // Prefer an explicit rupee discount; otherwise derive the discount
          // baked into amount (qty·rate − amount), so rows without any discount
          // field still report the real total.
          final dsc = (it['discount'] as num?)?.toDouble();
          if (dsc != null) return sum + dsc;
          final q = (it['quantity'] as num?)?.toDouble() ??
              (it['qty'] as num?)?.toDouble() ?? 0;
          final r = (it['rate'] as num?)?.toDouble() ?? 0;
          final a = (it['amount'] as num?)?.toDouble() ?? 0;
          final implied = q * r - a;
          return sum + (implied > 0 ? implied : 0);
        });
    final inventoryLedgerName =
        voucher?['inventory_ledger_name'] as String? ??
        _p['inventory_ledger_name'] as String?;
    return (
      breakdown: breakdown,
      total: total,
      discount: discount,
      invLedger: inventoryLedgerName,
    );
  }

  // Enter on the Total field (end of the Enter-to-move chain) pushes to Tally.
  // Mirrors the Push To Tally button: same submitting/blocked guards.
  void _submitFromTotal() {
    if (_isSubmitting) return;
    final pushBlocked = _partyNameWasChanged && !_allItemsDifferentFromOriginal;
    if (pushBlocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Party Name is Changed!!\nChange all the items'),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }
    _confirmAndActivate();
  }

  // Asks for confirmation before pushing to Tally. "Yes" runs the original
  // activate flow; "Cancel" just dismisses the dialog and stays on the sheet.
  // When edit mode is on, the edits aren't saved yet, so we warn and — on OK —
  // save first (which persists to Supabase) and then push.
  Future<void> _confirmAndActivate() async {
    if (_isEditing) {
      // While editing, pushing is blocked: prompt the user to Save first. OK
      // just dismisses the dialog (no save, no push); the user must hit Save,
      // after which Push To Tally follows the normal (non-editing) flow below.
      await showDialog<void>(
        context: context,
        builder: (_) => const _SaveBeforePushDialog(),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => widget.duplicateKind == DuplicateKind.none
          ? const _PushConfirmDialog()
          : DuplicateActionDialog(
              message:
                  '${widget.duplicateKind.baseMessage}, Are you sure you want to push'),
    );
    if (confirmed != true || !mounted) return;

    // Guard: catalog still downloading — can't validate reliably. Mirror the
    // existing edit-gate message and abort (the user retries once it's loaded).
    if (StockItemsCache.instance.isLoading) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Loading of stock items in process, please wait'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    // Validate every line against the cached stock catalog before pushing, so a
    // missing item is caught here instead of failing the whole push in Tally.
    // Item name lives on `stock_item_name`.
    final names = _payloadItems
        .map((it) => (it['stock_item_name'] as String? ?? '').trim())
        .where((n) => n.isNotEmpty)
        .toList();

    final valid = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _StockValidationDialog(itemNames: names),
    );
    if (valid == true && mounted) {
      await _activate();
    }
    // valid != true → missing items; the dialog already told the user which
    // ones. Stay in view mode (no auto-edit); the user edits, saves and pushes
    // again, which re-runs this check.
  }

  // Confirms then deletes the push_queue row from Supabase. Removes it locally
  // and closes the sheet immediately; the realtime DELETE event keeps every
  // other client in sync. Seed / fresh-scan rows (no __row_id) are dropped
  // locally only.
  Future<void> _confirmAndDiscard() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const _DiscardConfirmDialog(),
    );
    if (confirmed != true || !mounted) return;

    final rowId = _p['__row_id'] as String? ?? '';
    final messenger = ScaffoldMessenger.of(context);

    widget.onDiscard?.call();
    Navigator.of(context).pop();

    if (rowId.isEmpty) return;

    try {
      await Supabase.instance.client.from('push_queue').delete().eq('id', rowId);
      messenger.showSnackBar(
        const SnackBar(content: Text('Deleted.'), duration: Duration(seconds: 2)),
      );
    } catch (e, st) {
      reportHandledError('supabase.push_queue.delete', e,
          stackTrace: st, context: {'row_id': rowId});
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Couldn\'t delete. Please try again.'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _activate() async {
    final rowId = _p['__row_id'] as String? ?? '';
    if (rowId.isEmpty) return;

    final requestId = ApiClient.newRequestId();
    setState(() => _isSubmitting = true);
    try {
      // Every push overwrites the narration with the fixed value, persisted to
      // the push_queue row before activating so tallybridge reads the new value.
      final clean = Map<String, dynamic>.from(_payload ?? {})
        ..removeWhere((k, _) => k.startsWith('__'));
      _stripItemLocalKeys(clean);
      clean['narration'] = _pushNarration;
      await Supabase.instance.client
          .from('push_queue')
          .update({'voucher_payload': clean})
          .eq('id', rowId);
      if (mounted) _payload?['narration'] = _pushNarration;

      final response = await ApiClient.client.post(
        Uri.parse(_activateUrl),
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': _apiKey,
          'x-request-id': requestId,
        },
        body: jsonEncode({'job_id': rowId}),
      );

      if (!mounted) return;
      if (response.statusCode >= 200 && response.statusCode < 300) {
        _isEditing = false;
        _notifyEditState();
        // Teach the audit trail from the voucher the user just committed. Purchase
        // only, and fire-and-forget: a failure to learn must never fail the push.
        if (!_isSale) _recordPurchaseAuditTrail(clean);
        // The POST only queues the push; the actual TallyPrime result (created /
        // errors in tally_response, or status pushed/failed) arrives later over
        // realtime. Stay open in a "pushing…" state until _subscribeToStatus
        // sees the terminal row and shows the result modal. Keep _isSubmitting
        // true so the button keeps its spinner.
        setState(() => _awaitingPushResult = true);
        // Guard the race where the terminal update already arrived before this
        // POST returned: if the row is already terminal, resolve now.
        if (_status == 'pushed' || _status == 'failed') {
          _handlePushResult({
            'status': _status,
            'pushed_at': _pushedAt,
            'error_message': _errorMessage,
          });
        }
      } else {
        ApiClient.reportFailure(
          'POST',
          '/api/sync/push-queue/activate',
          requestId,
          status: response.statusCode,
          body: response.body,
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed (${response.statusCode}): ${response.body}')),
        );
        setState(() => _isSubmitting = false);
      }
    } catch (e, st) {
      ApiClient.reportFailure(
        'POST',
        '/api/sync/push-queue/activate',
        requestId,
        error: e,
        stack: st,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      setState(() => _isSubmitting = false);
    }
  }

  // Appends one (raw_ocr -> actual_item) row per line of the voucher just pushed, so
  // the next scan of the same OCR text resolves straight to the item the user chose —
  // ahead of the curated Purchase_Matching table and the vendor rules. Every line is
  // recorded, not just corrected ones: what was pushed to Tally is what is true.
  // Lines the user added by hand carry no raw_ocr and so teach nothing.
  //
  // The OCR text is stored verbatim so the trail stays human-readable; the parser
  // canonicalizes (collapse whitespace, lowercase) when it reads the trail, so
  // matching is case-insensitive regardless of how a vendor path cased this line.
  Future<void> _recordPurchaseAuditTrail(Map<String, dynamic> pushedPayload) async {
    final items = (pushedPayload['items'] as List?)?.cast<Map<String, dynamic>>() ??
        ((pushedPayload['voucher_payload'] as Map?)?['items'] as List?)
            ?.cast<Map<String, dynamic>>() ??
        const <Map<String, dynamic>>[];

    final rows = <Map<String, String>>[];
    for (final item in items) {
      final rawOcr = ((item['raw_ocr'] as String?) ?? '').trim();
      final actualItem = ((item['stock_item_name'] as String?) ?? '').trim();
      if (rawOcr.isEmpty || actualItem.isEmpty) continue;
      rows.add({'raw_ocr': rawOcr, 'actual_item': actualItem});
    }
    if (rows.isEmpty) return;

    try {
      await Supabase.instance.client.from('Audit_Trail_Purchase').insert(rows);
    } catch (e, st) {
      reportHandledError('supabase.audit_trail_purchase.insert', e,
          stackTrace: st, context: {'row_count': rows.length});
    }
  }

  void _subscribeToStatus(String rowId) {
    _channel = Supabase.instance.client
        .channel('vd_status_$rowId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'push_queue',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: rowId,
          ),
          callback: (payload) {
            if (!mounted) return;
            final rec = payload.newRecord;
            final newStatus = rec['status'] as String? ?? _status;
            setState(() {
              _status = newStatus;
              _pushedAt = rec['pushed_at'] as String? ?? _pushedAt;
              _errorMessage = rec['error_message'] as String? ?? _errorMessage;
            });
            if (_awaitingPushResult) _handlePushResult(rec);
          },
        )
        .subscribe();
  }

  // Called for each realtime row update while a push is in flight. Reads the
  // TallyPrime outcome — tally_response.created/errors, falling back to status
  // (pushed/failed) — and once the row goes terminal, closes the sheet and shows
  // the success or failure modal (sale only). push_now / transient states are
  // ignored so we keep waiting. error_message carries the Tally failure reason.
  void _handlePushResult(Map<String, dynamic> rec) {
    final status = rec['status'] as String? ?? _status;
    final tally = rec['tally_response'];
    final tallyMap = tally is Map ? tally : null;
    final created = (tallyMap?['created'] as num?)?.toInt();
    final errors = (tallyMap?['errors'] as num?)?.toInt();

    final success = status == 'pushed' || (created != null && created >= 1);
    final failed = status == 'failed' ||
        (created == 0 && errors != null && errors >= 1);
    if (!success && !failed) return; // still pending / push_now — keep waiting

    _awaitingPushResult = false;

    // Capture everything before pop() disposes this State.
    final isSale = _isSale;
    final customer = _currentPartyName;
    final amount = _computeCharges().total;
    final pushedAt =
        DateTime.tryParse(rec['pushed_at'] as String? ?? '')?.toLocal() ??
            DateTime.now();
    final errMsg = (rec['error_message'] as String?)?.trim();
    final rootCtx = Navigator.of(context, rootNavigator: true).context;
    // The bottom sheet's route — its `popped` future completes only after the
    // sheet has fully slid away, so we can show the result modal afterwards
    // instead of stacking it on top of the still-closing sheet.
    final sheetRoute = ModalRoute.of(context);

    // Re-fetch the queue (pushed rows drop to History; failed rows stay).
    widget.onPushed?.call();
    Navigator.of(context).pop();

    if (!isSale) return;

    void showResultDialog() {
      if (!rootCtx.mounted) return;
      showDialog<void>(
        context: rootCtx,
        builder: (_) => success
            ? _SalePushedDialog(
                customerName: customer,
                amount: amount,
                pushedAt: pushedAt,
              )
            : _SalePushFailedDialog(
                customerName: customer,
                errorMessage:
                    (errMsg == null || errMsg.isEmpty) ? 'Push to Tally failed.' : errMsg,
              ),
      );
    }

    // Wait for the sheet to finish closing before showing the modal; fall back
    // to showing it immediately if the route is somehow unavailable.
    if (sheetRoute != null) {
      sheetRoute.popped.then((_) => showResultDialog());
    } else {
      showResultDialog();
    }
  }

  // "Push Details" block shown in the header once a voucher is pushed/failed
  // (History rows, or a failed row still in the queue). Date/Time from
  // push_queue.pushed_at; Status shows the error_message when it failed.
  Widget _buildPushDetails(BuildContext context) {
    final dt = DateTime.tryParse(_pushedAt ?? '')?.toLocal();
    const months = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final dateStr = dt != null ? '${dt.day} ${months[dt.month]} ${dt.year}' : '—';
    final timeStr = dt != null
        ? '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}'
        : '—';
    final err = _errorMessage?.trim() ?? '';
    final statusText = _status == 'pushed'
        ? 'Pushed'
        : (err.isNotEmpty ? 'Failed — $err' : 'Failed');
    final labelStyle = Theme.of(context)
        .textTheme
        .bodySmall
        ?.copyWith(color: AppPalette.muted, fontWeight: FontWeight.w500);
    final valueStyle = Theme.of(context)
        .textTheme
        .bodySmall
        ?.copyWith(color: AppPalette.ink, fontWeight: FontWeight.w600);
    Widget row(String k, String v, {Color? color}) => Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 54, child: Text(k, style: labelStyle)),
              Expanded(
                child: Text(v, style: color != null ? valueStyle?.copyWith(color: color) : valueStyle),
              ),
            ],
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Push Details',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(fontWeight: FontWeight.w800, color: AppPalette.ink)),
        row('Date', dateStr),
        row('Time', timeStr),
        row('Status', statusText, color: _statusColor(_status)),
      ],
    );
  }

  static Color _statusColor(String status) {
    switch (status) {
      case 'pushed': return const Color(0xFF166534);
      case 'failed': return AppPalette.accent;
      default: return const Color(0xFFB45309);
    }
  }

  static Color _statusBg(String status) {
    switch (status) {
      case 'pushed': return const Color(0xFFBBF7D0);
      case 'failed': return const Color(0xFFFFE4E1);
      default: return const Color(0xFFFEF3C7);
    }
  }

  @override
  Widget build(BuildContext context) {
    final header = _header;
    final voucher = _voucher;
    final partyName = _editablePartyName ??
        _p['party_name'] as String? ??
        voucher?['party_name'] as String? ??
        voucher?['party_ledger_name'] as String? ??
        header?['vendor_name'] as String? ?? '—';
    final voucherNumber = _editableVoucherNumber ??
        _p['voucher_number'] as String? ??
        voucher?['voucher_number'] as String? ??
        header?['invoice_number'] as String? ?? '—';
    final rawDate = _editableDate ??
        _p['date'] as String? ??
        voucher?['date'] as String? ??
        header?['invoice_date'] as String?;
    final date = formatDate(rawDate);
    final narration = _editableNarration ??
        _p['narration'] as String? ??
        voucher?['narration'] as String?;
    final reference = _p['reference'] as String? ?? voucher?['reference'] as String?;

    final items = _payloadItems;
    final sourceItems = (((_p['source_payload'] ?? _p['__source_payload'])
                as Map<String, dynamic>?)?['items'] as List?)
            ?.cast<Map<String, dynamic>>() ??
        items;
    final charges = _computeCharges();
    // The purchase/inventory ledger holds a rupee amount; the remaining tax
    // ledgers (IGST/CGST/SGST…) carry rate percentages, so render those as %.
    final inventoryLedgerName = charges.invLedger;
    // While editing, the Charges block reads from the editable copies so typed
    // values survive rebuilds; otherwise it reflects the parsed payload.
    final breakdownEntries = _isEditing ? _editableLedgers : charges.breakdown;
    final total = _isEditing ? (_editableTotal ?? charges.total) : charges.total;

    final screenSize = MediaQuery.of(context).size;
    // On wide screens (web/desktop) show the image and summary side by side (no
    // toggle); phones keep the Image/Summary tab switcher. The sheet is sized to
    // ~90% width at the showModalBottomSheet call site (Material otherwise caps
    // modal width), and to 90% height here.
    final wide = context.isWideScreen;
    final hasImageMode = _availableModes.contains(_VdsViewMode.image);
    final twoPane = wide && hasImageMode;

    // Built per-context so the two-pane layout can render the summary for the
    // PANE width (via a scoped MediaQuery) rather than the whole window — that
    // keeps the items table sized to (and scrolling within) the pane.
    Widget buildSummary(BuildContext ctx) => _loading
        ? _buildLoadingBody(ctx)
        : _loadError != null
            ? _buildErrorBody(ctx)
            : _buildSummaryView(
                ctx,
                partyName: partyName,
                voucherNumber: voucherNumber,
                date: date,
                rawDate: rawDate,
                reference: reference,
                narration: narration,
                total: total,
                breakdownEntries: breakdownEntries,
                inventoryLedgerName: inventoryLedgerName,
                items: items,
                sourceItems: sourceItems,
              );

    return Container(
      width: double.infinity,
      height: screenSize.height * 0.9,
      decoration: BoxDecoration(
        color: AppPalette.sheet,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 56,
            height: 4,
            decoration: BoxDecoration(color: AppPalette.line, borderRadius: BorderRadius.circular(99)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_isEditing && !_loading)
                        GestureDetector(
                          onTap: () async {
                            // Sale → customers (Sundry Debtors); purchase →
                            // vendors (Sundry Creditors).
                            final loading = _isSale
                                ? CustomersCache.instance.isLoading
                                : VendorsCache.instance.isLoading;
                            if (loading) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(_isSale
                                      ? 'Please wait, customer list is still downloading…'
                                      : 'Please wait, vendor list is still downloading…'),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                              return;
                            }
                            final selected = await showModalBottomSheet<Customer>(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder: (_) => CustomerPickerSheet(
                                items: _isSale
                                    ? CustomersCache.instance.items
                                    : VendorsCache.instance.items,
                                searchHint: _isSale
                                    ? 'Search customers…'
                                    : 'Search vendors…',
                              ),
                            );
                            if (selected != null && mounted) {
                              setState(() => _editablePartyName = selected.name);
                              // A different customer can mean a different state,
                              // so re-resolve it and re-derive the GST head —
                              // otherwise the voucher keeps the old party's split.
                              await _loadPartyState();
                              if (_isEditing && _partyState != null) {
                                _applyStateToTaxRows(_partyState!);
                              }
                            }
                          },
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  partyName,
                                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(Icons.arrow_drop_down, size: 22, color: AppPalette.muted),
                            ],
                          ),
                        )
                      else
                        Text(
                          _loading ? 'Processing…' : partyName,
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      Text(
                        _loading ? 'Reading your document…' : '$voucherNumber · $date',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppPalette.muted),
                      ),
                      if (!_loading) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: _statusBg(_status),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: RichText(
                            text: TextSpan(
                              style: const TextStyle(fontSize: 12),
                              children: [
                                TextSpan(
                                  text: 'Status: ',
                                  style: TextStyle(color: AppPalette.muted, fontWeight: FontWeight.w500),
                                ),
                                TextSpan(
                                  text: _status,
                                  style: TextStyle(color: _statusColor(_status), fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (_status == 'pushed' || _status == 'failed') ...[
                          const SizedBox(height: 10),
                          _buildPushDetails(context),
                        ],
                        if (widget.pendingPayload == null && !widget.readOnly) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            FilledButton(
                              onPressed: _toggleEdit,
                              style: FilledButton.styleFrom(
                                backgroundColor: _isEditing ? const Color(0xFFB45309) : const Color(0xFFFEF3C7),
                                foregroundColor: _isEditing ? Colors.white : const Color(0xFFB45309),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                              ),
                              child: Text(_isEditing ? 'Save' : 'Edit'),
                            ),
                            const SizedBox(width: 8),
                            FilledButton.icon(
                              onPressed: _addItem,
                              icon: const Icon(Icons.add_rounded, size: 16),
                              label: const Text('Add'),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFFDBEAFE),
                                foregroundColor: const Color(0xFF1D4ED8),
                                disabledBackgroundColor: const Color(0xFFDBEAFE),
                                disabledForegroundColor: const Color(0xFF1D4ED8),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                              ),
                            ),
                            // Image show/hide toggle (two-pane/web only). On by
                            // default; turning it off collapses the image pane so
                            // the summary uses the full width.
                            if (twoPane) ...[
                              const SizedBox(width: 12),
                              Icon(
                                _showImage ? Icons.image_rounded : Icons.hide_image_rounded,
                                size: 16,
                                color: _showImage ? const Color(0xFF1D4ED8) : AppPalette.muted,
                              ),
                              Transform.scale(
                                scale: 0.8,
                                child: Switch(
                                  value: _showImage,
                                  activeThumbColor: const Color(0xFF1D4ED8),
                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  onChanged: (v) => setState(() => _showImage = v),
                                ),
                              ),
                            ],
                            // Revert appears only while editing; it discards all
                            // edits back to the original parsed values and exits
                            // edit mode, so it disappears once tapped.
                            if (_isEditing) ...[
                              const SizedBox(width: 8),
                              FilledButton(
                                onPressed: _revert,
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFFFFE4E1),
                                  foregroundColor: const Color(0xFFDC2626),
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                  textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                ),
                                child: const Text('Revert'),
                              ),
                            ],
                            const SizedBox(width: 8),
                            // Creates a stock master in TallyPrime without
                            // touching this voucher (unlike Add, which appends a
                            // line). Same sheet the picker's "Create new stock
                            // item" row opens, so it needs no edit mode.
                            FilledButton.icon(
                              onPressed: _createStockItem,
                              icon: const Icon(Icons.add_circle_outline_rounded, size: 16),
                              label: const Text('Create New Item'),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFFDCFCE7),
                                foregroundColor: const Color(0xFF15803D),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                        ], // pendingPayload == null
                      ],
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Wide screens: image (left) and summary (right) side by side, no
          // switcher. Narrow screens: keep the Image/Summary toggle (only shown
          // when there's actually an image to switch to).
          if (twoPane)
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_showImage) ...[
                    Expanded(flex: 5, child: _buildImageView(context)),
                    const VerticalDivider(width: 1),
                  ],
                  Expanded(
                    flex: 6,
                    child: LayoutBuilder(
                      builder: (paneCtx, paneConstraints) {
                        final mq = MediaQuery.of(paneCtx);
                        // Report the pane's own width to the summary subtree so it
                        // decides wide-vs-scroll against the pane, not the window.
                        // When the pane is wide the items table fills it with a
                        // flexing Item column (no overflow — it shrinks to fit),
                        // putting Taxable value directly above the Charges amounts.
                        return MediaQuery(
                          data: mq.copyWith(
                            size: Size(paneConstraints.maxWidth, mq.size.height),
                          ),
                          child: Builder(builder: buildSummary),
                        );
                      },
                    ),
                  ),
                ],
              ),
            )
          else ...[
            if (_availableModes.length > 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: _TabPill(
                  modes: _availableModes,
                  selected: _viewMode,
                  onChanged: (m) => setState(() => _viewMode = m),
                ),
              ),
            Expanded(
              child: switch (_viewMode) {
                _VdsViewMode.image => _buildImageView(context),
                _VdsViewMode.summary => buildSummary(context),
              },
            ),
          ],
          if (widget.onDiscard != null ||
              (!_loading && widget.pendingPayload == null && !widget.readOnly))
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    if (widget.onDiscard != null) ...[
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _confirmAndDiscard,
                          icon: const Icon(Icons.delete_outline_rounded, size: 18),
                          label: const Text('Delete'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppPalette.accent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            textStyle: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    if (!_loading && widget.pendingPayload == null && !widget.readOnly)
                      Builder(builder: (context) {
                        final pushBlocked = _partyNameWasChanged && !_allItemsDifferentFromOriginal;
                        return Expanded(
                          child: FilledButton.icon(
                            onPressed: _isSubmitting
                                ? null
                                : pushBlocked
                                    ? () {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Party Name is Changed!!\nChange all the items',
                                            ),
                                            duration: Duration(seconds: 3),
                                          ),
                                        );
                                      }
                                    : _confirmAndActivate,
                            icon: _isSubmitting
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Icons.cloud_upload_rounded, size: 18),
                            label: const Text('Push To Tally'),
                            style: FilledButton.styleFrom(
                              backgroundColor: pushBlocked
                                  ? const Color(0xFF16A34A).withValues(alpha: 0.45)
                                  : const Color(0xFF16A34A),
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: const Color(0xFF16A34A).withValues(alpha: 0.5),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              textStyle: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        );
                      }),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // A Charges line is the purchase amount (₹) when it's the inventory ledger;
  // every other ledger (IGST/CGST/SGST…) is a tax rate, shown as a percentage.
  String _chargeValue(Map<String, dynamic> entry, String? inventoryLedgerName) {
    final amount = (entry['amount'] as num?)?.toDouble().abs() ?? 0;
    final name = entry['ledger_name'] as String?;
    final isRate = inventoryLedgerName != null && name != inventoryLedgerName && amount < 100;
    if (isRate) {
      return '${amount % 1 == 0 ? amount.toInt() : amount}%';
    }
    return formatCurrency(amount);
  }

  // ── Tab body builders ─────────────────────────────────────────────────────

  Widget _buildLoadingBody(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 34,
            height: 34,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(height: 16),
          Text(
            'Reading your document…',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppPalette.muted),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBody(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 44, color: AppPalette.accent),
            const SizedBox(height: 14),
            Text(
              'Could not process this document.\n$_loadError',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppPalette.muted),
            ),
          ],
        ),
      ),
    );
  }

  void _setImageScale(double s) =>
      setState(() => _imageScale = s.clamp(1.0, 4.0));

  // Zoom in/out buttons overlaid at the top-right of the image pane. Drives the
  // shared _imageScale used by both the fresh-scan and stored-image renderers.
  Widget _zoomControls() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppPalette.line),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: _imageScale <= 1.0 ? null : () => _setImageScale(_imageScale - 0.5),
            icon: const Icon(Icons.zoom_out_rounded),
            iconSize: 20,
            visualDensity: VisualDensity.compact,
            tooltip: 'Zoom out',
          ),
          IconButton(
            onPressed: _imageScale >= 4.0 ? null : () => _setImageScale(_imageScale + 0.5),
            icon: const Icon(Icons.zoom_in_rounded),
            iconSize: 20,
            visualDensity: VisualDensity.compact,
            tooltip: 'Zoom in',
          ),
        ],
      ),
    );
  }

  Widget _buildImageView(BuildContext context) {
    // A freshly scanned voucher carries its image locally; show it directly.
    final bytes = widget.imageBytes;
    Widget? content;
    if (bytes != null) {
      content = Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, c) => SingleChildScrollView(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(
                  bytes,
                  fit: BoxFit.fitWidth,
                  width: c.maxWidth * _imageScale,
                ),
              ),
            ),
          ),
        ),
      );
    } else {
      // Queue/history rows: the scanned pages live in GCS, served by the backend.
      final rowId = _imageRowId;
      if (rowId != null && _scanPageCount > 0) {
        content = _StoredInvoiceImages(
          rowId: rowId,
          pageCount: _scanPageCount,
          scale: _imageScale,
        );
      }
    }
    if (content == null) {
      return Center(
        child: Text(
          'No image available',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppPalette.muted),
        ),
      );
    }
    return Stack(
      children: [
        Positioned.fill(
          child: ScrollConfiguration(
            behavior: const _DragScrollBehavior(),
            child: content,
          ),
        ),
        Positioned(top: 20, right: 20, child: _zoomControls()),
      ],
    );
  }

  Widget _buildSummaryView(
    BuildContext context, {
    required String partyName,
    required String voucherNumber,
    required String date,
    required String? rawDate,
    required String? reference,
    required String? narration,
    required double total,
    required List<Map<String, dynamic>> breakdownEntries,
    required String? inventoryLedgerName,
    required List<Map<String, dynamic>> items,
    required List<Map<String, dynamic>> sourceItems,
  }) {
    // While editing, render the working copy so newly added rows show up;
    // in view mode show the resolved payload items.
    final displayItems = _isEditing ? _editableItems : items;
    // On desktop the body is capped and centered (see _centerOnWide); on phones
    // it fills the width and the item table scrolls horizontally.
    final wide = context.isWideScreen;
    // Charges fields are ordered right after the last item row's cells, so
    // Enter flows Amount(last) → GST Sale → CGST → … → Discount → Total.
    final chargesOrderBase =
        _kHeaderFocusCount + displayItems.length * _kCellsPerItemRow;
    // Build the major blocks once, then arrange them into slivers below so the
    // items column header can be pinned while the rows scroll under it.
    final vendorCard = Container(
      decoration: BoxDecoration(
        color: AppPalette.gridHeader,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppPalette.line, width: 1.2),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        children: [
          _SheetHeaderRow('Vendor', partyName),
          if (_isEditing)
            FocusTraversalOrder(
              order: const NumericFocusOrder(0),
              child: _SheetEditableTextRow(
                label: 'Invoice #',
                initial: voucherNumber == '—' ? '' : voucherNumber,
                // Keyboard-first entry starts here on desktop/web so Enter walks
                // Invoice # → Narration → items. Skipped on phones to avoid
                // popping the keyboard the moment edit mode opens.
                autofocus: wide,
                onChanged: (v) => _editableVoucherNumber = v,
              ),
            )
          else
            _SheetHeaderRow('Invoice #', voucherNumber),
          if (_isEditing)
            _SheetEditableTextRow(
              label: 'Date',
              initial: date == '—' ? '' : date,
              onTap: () => _pickDate(context, rawDate),
              icon: Icons.calendar_today_rounded,
            )
          else
            _SheetHeaderRow('Date', date),
          if (reference != null && reference != voucherNumber)
            _SheetHeaderRow('Reference', reference),
          if (_isEditing)
            FocusTraversalOrder(
              order: const NumericFocusOrder(1),
              child: _SheetEditableTextRow(
                label: 'Narration',
                initial: narration ?? '',
                onChanged: (v) => _editableNarration = v,
              ),
            )
          else if (narration != null)
            _SheetHeaderRow('Narration', narration),
          _SheetHeaderRow('Total', formatCurrency(total), bold: true),
        ],
      ),
    );

    final itemsHeader = Container(
      decoration: BoxDecoration(
        color: AppPalette.gridHeader,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        border: Border.all(color: AppPalette.line, width: 1.2),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          const SizedBox(
              width: _kSerialColW,
              child: Text('#', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12))),
          // Mirror _itemCell: flex on wide so the numeric headers align with the
          // right-edge columns; fixed width when the table scrolls on phones.
          if (wide)
            const Expanded(
                child: Text('Items', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)))
          else
            const SizedBox(
                width: _kItemColW,
                child: Text('Items', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12))),
          const _SheetColHeader('Qty', width: _kQtyColW),
          const _SheetColHeader('Rate', width: _kRateColW),
          const _SheetColHeader('Disc', width: _kDiscColW),
          const _SheetColHeader('List price', width: _kListPriceColW),
          const _SheetColHeader('Taxable value', width: _kAmountColW),
          const SizedBox(width: _kDeleteColW),
        ],
      ),
    );

    final itemsBody = Container(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: AppPalette.line, width: 1.2),
          right: BorderSide(color: AppPalette.line, width: 1.2),
          bottom: BorderSide(color: AppPalette.line, width: 1.2),
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
      ),
      child: Column(children: [
        for (var i = 0; i < displayItems.length; i++) ...[
          // Insert-between affordance: hovering the gap above a row reveals an
          // "Insert item here" bar that opens the picker and slots the choice at
          // this index, so a line the parse missed can be placed to match the
          // paper order instead of only appending via the toolbar "Add".
          if (_isEditing && !widget.readOnly)
            _InsertItemDivider(wide: wide, onTap: () => _addItem(at: i)),
          _SheetItemRow(
            item: displayItems[i],
            serialNumber: i + 1,
            wide: wide,
            source: i < sourceItems.length ? sourceItems[i]['source'] as String? : null,
            score: i < sourceItems.length ? sourceItems[i]['score'] as String? : null,
            rateSource: i < sourceItems.length ? sourceItems[i]['rate_source'] as String? : null,
            isEditing: _isEditing,
            partyName: partyName,
            isSale: _isSale,
            voucherItemNames: displayItems
                .map((it) => (it['stock_item_name'] as String?) ?? '')
                .toList(),
            showDelete: !widget.readOnly,
            orderBase: _kHeaderFocusCount + i * _kCellsPerItemRow,
            isEdited: () {
              final orig = _originalItemNames;
              if (orig == null) return false;
              // Rows added during this edit session sit beyond the captured
              // originals — treat them as edited (new).
              if (i >= orig.length) return true;
              // An explicit touch (same-item re-pick, numeric edit) counts even
              // though the name comparison below can't see it.
              if (_touchedRows.contains(i)) return true;
              final currentName = displayItems[i]['stock_item_name'] as String? ?? '';
              return currentName != orig[i];
            }(),
            onStockItemSelected: (selected) {
              setState(() {
                if (i < _editableItems.length) {
                  _touchedRows.add(i);
                  _editableItems[i]['stock_item_name'] = selected.name;
                  // Switch the unit to the NEW item's unit — keeping the old
                  // item's unit (e.g. KIT) makes Tally reject the line, since the
                  // qty unit must match the stock item's base unit. Prefer the
                  // picked unit; fall back to the catalog by name, then NOS.
                  final newUnit = selected.unit.isNotEmpty
                      ? selected.unit
                      : StockItemsCache.instance.unitFor(selected.name);
                  _editableItems[i]['unit'] = newUnit.isNotEmpty ? newUnit : 'NOS';
                  // Purchase: the vendor invoice is the source of truth for
                  // pricing, so swapping the matched stock item only corrects the
                  // item identity — keep the original rate / discount / amount.
                  // Sale: the rate comes from the price list, so adopt the picked
                  // item's rate + discount and rescale the amount.
                  if (_isSale) {
                    _editableItems[i]['rate'] = selected.rate;
                    _editableItems[i]['discount_pct'] = selected.discountPct;
                    // Local-only; moves to source_payload on save.
                    _editableItems[i]['__rate_source'] = selected.source;
                    _editableItems[i]['__discount_source'] =
                        selected.discountSource;
                    // Purchase items key quantity as `qty`, sales as `quantity`
                    // — read whichever exists (mirrors _SheetItemRow / recompute).
                    final qty = (_editableItems[i]['qty'] as num?)?.toDouble() ??
                        (_editableItems[i]['quantity'] as num?)?.toDouble() ?? 0;
                    final gross = qty * selected.rate;
                    final discount = gross * selected.discountPct / 100;
                    _editableItems[i]['amount'] = gross - discount;
                  }
                }
              });
              _recomputeChargesFromItems();
              _notifyEditState();
            },
            onItemChanged: () {
              // A qty/rate/disc/amount edit deals with the line as much as a
              // re-pick does (the row mutates the item in place before calling).
              setState(() => _touchedRows.add(i));
              _recomputeChargesFromItems();
              _notifyEditState();
            },
            onDelete: () {
              setState(() {
                _editableItems.removeAt(i);
                _touchedAfterDelete(i);
              });
              _recomputeChargesFromItems();
              _notifyEditState();
            },
          ),
        ],
      ]),
    );

    // Charges rows in display order: the taxable subtotal (the inventory/GST
    // Sale·Purchase ledger) first, then the GST tax rows. The taxable row sits
    // directly beneath the "Taxable value" column as its subtotal, so it carries
    // no label; each GST row is prefixed "Add:" in invoice style. The Discount
    // line is intentionally dropped (it's already baked into the taxable value).
    final taxableEntry = inventoryLedgerName != null
        ? breakdownEntries
            .where((e) => e['ledger_name'] == inventoryLedgerName)
            .firstOrNull
        // No named inventory ledger: the taxable subtotal is the largest row.
        : (breakdownEntries.isNotEmpty
            ? breakdownEntries.reduce((a, b) =>
                ((a['amount'] as num).abs() >= (b['amount'] as num).abs() ? a : b))
            : null);
    final orderedCharges = [
      ?taxableEntry,
      ...breakdownEntries.where((e) => !identical(e, taxableEntry)),
    ];

    // Borderless: the amounts sit in a column beneath "Taxable value" rather
    // than inside a boxed card (see _kChargesRightInset).
    final chargesCard = Padding(
      padding: const EdgeInsets.only(
        left: _kChargesLeftInset,
        right: _kChargesRightInset,
      ),
      child: Column(
        children: [
          for (final (ci, entry) in orderedCharges.indexed) ...[
            if (_isEditing)
              FocusTraversalOrder(
                order: NumericFocusOrder((chargesOrderBase + ci).toDouble()),
                child: _SheetEditableRow(
                  key: ValueKey('ledger_${entry['ledger_name']}_${entry['amount']}'),
                  label: identical(entry, taxableEntry)
                      ? ''
                      : 'Add: ${entry['ledger_name'] as String? ?? '—'}',
                  initial: (entry['amount'] as num?)?.toDouble().abs() ?? 0,
                  isPercent: inventoryLedgerName != null &&
                      entry['ledger_name'] != inventoryLedgerName &&
                      ((entry['amount'] as num?)?.toDouble().abs() ?? 0) < 100,
                  valueRight: true,
                  labelExpands: true,
                  onChanged: (v) => entry['amount'] = v,
                ),
              )
            else
              _SheetHeaderRow(
                identical(entry, taxableEntry)
                    ? ''
                    : 'Add: ${entry['ledger_name'] as String? ?? '—'}',
                _chargeValue(entry, inventoryLedgerName),
                valueRight: true,
                labelExpands: true,
              ),
            // The GST-head selector sits directly beneath the taxable subtotal and
            // above the tax rows it decides, so the cause reads above the effect.
            if (_isSale && identical(entry, taxableEntry)) _buildPartyStateRow(),
          ],
          const Divider(height: 16),
          if (_isEditing)
            FocusTraversalOrder(
              order: NumericFocusOrder(
                  (chargesOrderBase + orderedCharges.length).toDouble()),
              child: _SheetEditableRow(
                key: ValueKey('total_$total'),
                label: 'Total Value',
                initial: total,
                bold: true,
                valueRight: true,
                labelExpands: true,
                onChanged: (v) => _editableTotal = v,
                // Last field in the Enter-to-move chain: the final Enter pushes
                // to Tally (mirrors the Push To Tally button, guards included).
                onSubmitted: _submitFromTotal,
              ),
            )
          else
            _SheetHeaderRow('Total Value', formatCurrency(total), bold: true, valueRight: true, labelExpands: true),
        ],
      ),
    );

    final titleStyle = Theme.of(context)
        .textTheme
        .titleMedium
        ?.copyWith(fontWeight: FontWeight.w800);

    return FocusTraversalGroup(
      // Explicit (ordered) traversal so Enter walks every numeric cell in
      // sequence — the geometry-based default skipped narrow columns (Disc).
      policy: OrderedTraversalPolicy(),
      child: _centerOnWide(
        wide,
        CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    vendorCard,
                    if (displayItems.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      Text('Items', style: titleStyle),
                      const SizedBox(height: 10),
                    ],
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Items table. On wide the header sits inline above the body
                    // (both stretch to the pane); on narrow they share one
                    // horizontal scroll view so their columns stay aligned.
                    if (displayItems.isNotEmpty)
                      wide
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [itemsHeader, itemsBody],
                            )
                          : SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: SizedBox(
                                width: _kItemsTableW,
                                child: Column(children: [itemsHeader, itemsBody]),
                              ),
                            ),
                    if (breakdownEntries.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      chargesCard,
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

}

// ── Tab pill selector ─────────────────────────────────────────────────────────

class _TabPill extends StatelessWidget {
  const _TabPill({
    required this.modes,
    required this.selected,
    required this.onChanged,
  });
  final List<_VdsViewMode> modes;
  final _VdsViewMode selected;
  final ValueChanged<_VdsViewMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final segmentWidth = constraints.maxWidth / modes.length;
        final selectedIndex = modes.indexOf(selected);
        return SizedBox(
          height: 38,
          child: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppPalette.gridHeader,
                    borderRadius: BorderRadius.circular(19),
                    border: Border.all(color: AppPalette.line, width: 1.2),
                  ),
                ),
              ),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                left: segmentWidth * selectedIndex,
                top: 0,
                bottom: 0,
                width: segmentWidth,
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppPalette.ink,
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
              Row(
                children: [
                  for (final mode in modes)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onChanged(mode),
                        child: Center(
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 180),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: mode == selected ? Colors.white : AppPalette.inkSoft,
                            ),
                            child: Text(mode.label),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SheetHeaderRow extends StatelessWidget {
  const _SheetHeaderRow(this.label, this.value,
      {this.bold = false, this.valueRight = false, this.labelExpands = false});
  final String label;
  final String value;
  final bool bold;
  // Right-aligns the value under the items table's right column. Used by the
  // Charges block so amounts sit in a column beneath "Taxable value".
  final bool valueRight;
  // Charges rows: let the label take the full available width on a single line
  // (ellipsis only if truly too narrow) instead of the fixed 90px column that
  // wraps long names like "Add: CARTAGE INWARD". The amount stays at the right.
  final bool labelExpands;

  @override
  Widget build(BuildContext context) {
    final labelStyle = Theme.of(context).textTheme.bodySmall?.copyWith(color: AppPalette.muted);
    final valueStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
          color: bold ? AppPalette.ink : AppPalette.inkSoft,
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: labelExpands
            ? [
                Expanded(
                  child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: labelStyle),
                ),
                const SizedBox(width: 8),
                Text(value, textAlign: TextAlign.right, style: valueStyle),
              ]
            : [
                SizedBox(width: 90, child: Text(label, style: labelStyle)),
                Expanded(
                  child: Text(
                    value,
                    textAlign: valueRight ? TextAlign.right : TextAlign.left,
                    style: valueStyle,
                  ),
                ),
              ],
      ),
    );
  }
}

/// Compact right-aligned numeric field for the editable Qty/Disc/Rate/Amount
/// cells. Uncontrolled [initial] so the cursor isn't reset between keystrokes.
class _EditableNumCell extends StatefulWidget {
  const _EditableNumCell({
    required this.width,
    required this.initial,
    required this.onChanged,
    this.suffix,
  });
  final double width;
  final double initial;
  final ValueChanged<double> onChanged;
  final String? suffix;

  @override
  State<_EditableNumCell> createState() => _EditableNumCellState();
}

class _EditableNumCellState extends State<_EditableNumCell> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  static String _format(double v) =>
      v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(2);

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _format(widget.initial));
    _focusNode = FocusNode();
    // Select the whole value when the field gains focus (via Enter-advance or a
    // mouse click) so the user can immediately type over it, TallyPrime-style.
    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        _controller.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _controller.text.length,
        );
      }
    });
  }

  @override
  void didUpdateWidget(_EditableNumCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only rewrite the field when the value changed from OUTSIDE (e.g. a
    // stock-item pick rewrote rate/amount). If the new value already matches
    // what the user just typed, leave the controller — and the cursor — alone
    // so typing isn't interrupted. (This replaces the old value-based ValueKey,
    // which recreated the field on every keystroke and dropped focus.)
    if (widget.initial != oldWidget.initial &&
        double.tryParse(_controller.text.trim()) != widget.initial) {
      _controller.text = _format(widget.initial);
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      child: TextFormField(
        controller: _controller,
        focusNode: _focusNode,
        textAlign: TextAlign.right,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textInputAction: TextInputAction.next,
        // Suppress TextField's built-in "next" advance so Enter doesn't jump
        // TWICE (its default + our handler), which would skip every other cell.
        onEditingComplete: () {},
        // Enter advances exactly one cell, in the explicit order set by the
        // FocusTraversalOrder wrappers: Item→Qty→Disc→Rate→Amount→next row's
        // Item… (the delete button is a GestureDetector, so it's skipped).
        onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppPalette.ink, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          isDense: true,
          suffixText: widget.suffix,
          suffixStyle: TextStyle(fontSize: 10, color: AppPalette.muted),
          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppPalette.line.withValues(alpha: 0.3), width: 1)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppPalette.ink, width: 1.8)),
        ),
        onChanged: (v) {
          final parsed = double.tryParse(v.trim());
          if (parsed != null) widget.onChanged(parsed);
        },
      ),
    );
  }
}

/// Editable numeric Charges row (ledger / discount / total). Shows ₹ or %.
class _SheetEditableRow extends StatelessWidget {
  const _SheetEditableRow({
    super.key,
    required this.label,
    required this.initial,
    required this.onChanged,
    this.isPercent = false,
    this.bold = false,
    this.valueRight = false,
    this.onSubmitted,
    this.labelExpands = false,
  });
  final String label;
  final double initial;
  final ValueChanged<double> onChanged;
  final bool isPercent;
  final bool bold;
  // Right-aligns the field's text so editable charge amounts line up in the
  // same column as their read-only counterparts (beneath "Taxable value").
  final bool valueRight;
  // When set, Enter runs this instead of advancing focus. Used by the last
  // Charges field (Total) so the final Enter triggers Push to Tally.
  final VoidCallback? onSubmitted;
  // Charges rows: label takes the available width on one line (ellipsis if too
  // narrow) and the field is fixed-width on the right, so long ledger names like
  // "Add: CARTAGE INWARD" don't wrap. See _SheetHeaderRow.labelExpands.
  final bool labelExpands;

  @override
  Widget build(BuildContext context) {
    final text = initial % 1 == 0 ? initial.toInt().toString() : initial.toStringAsFixed(2);
    final field = TextFormField(
      initialValue: text,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: TextInputAction.next,
      // Suppress the built-in "next" advance so Enter moves only one
      // field (otherwise the default + our handler jump twice).
      onEditingComplete: () {},
      // Enter advances one Charges field at a time, continuing the
      // items-table chain: GST Sale → CGST → SGST → … → Discount → Total.
      // The last field (Total) overrides this to push to Tally instead.
      onFieldSubmitted: (_) => onSubmitted != null
          ? onSubmitted!()
          : FocusScope.of(context).nextFocus(),
      textAlign: valueRight ? TextAlign.right : TextAlign.left,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: bold ? FontWeight.w800 : FontWeight.w600, color: AppPalette.ink),
      decoration: InputDecoration(
        isDense: true,
        prefixText: isPercent ? null : '₹',
        suffixText: isPercent ? '%' : null,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppPalette.line.withValues(alpha: 0.3), width: 1)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppPalette.ink, width: 1.8)),
      ),
      onChanged: (v) {
        final parsed = double.tryParse(v.trim());
        if (parsed != null) onChanged(parsed);
      },
    );
    final labelText = Text(label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppPalette.muted));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: labelExpands
            ? [
                Expanded(child: labelText),
                const SizedBox(width: 8),
                SizedBox(width: 150, child: field),
              ]
            : [
                SizedBox(width: 90, child: labelText),
                Expanded(child: field),
              ],
      ),
    );
  }
}

/// Editable text Header row (Invoice # / Narration). When [onTap] is set the
/// field is read-only and tapping triggers it (used by the Date calendar).
class _SheetEditableTextRow extends StatelessWidget {
  const _SheetEditableTextRow({
    required this.label,
    required this.initial,
    this.onChanged,
    this.onTap,
    this.icon,
    this.autofocus = false,
  });
  final String label;
  final String initial;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final decoration = InputDecoration(
      isDense: true,
      suffixIcon: icon == null ? null : Icon(icon, size: 16, color: AppPalette.muted),
      suffixIconConstraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppPalette.line.withValues(alpha: 0.3), width: 1)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppPalette.ink, width: 1.8)),
    );
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(color: AppPalette.ink, fontWeight: FontWeight.w600);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 90, child: Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppPalette.muted))),
          Expanded(
            child: onTap != null
                ? GestureDetector(
                    onTap: onTap,
                    child: InputDecorator(
                      decoration: decoration,
                      child: Text(initial.isEmpty ? '—' : initial, style: style),
                    ),
                  )
                : TextFormField(
                    initialValue: initial,
                    autofocus: autofocus,
                    style: style,
                    decoration: decoration,
                    textInputAction: TextInputAction.next,
                    // Suppress the built-in "next" so Enter advances exactly one
                    // field (header → header → first item), matching the cells.
                    onEditingComplete: () {},
                    onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
                    onChanged: onChanged,
                  ),
          ),
        ],
      ),
    );
  }
}

// Pins the items column header at the top of the scroll view while rows scroll
// under it. Fixed extent (min == max) so it stays put without resizing.
class _SheetColHeader extends StatelessWidget {
  const _SheetColHeader(this.label, {required this.width});
  final String label;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Text(label, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
    );
  }
}

// Thin insert-between affordance rendered above each item row in edit mode.
// On desktop the bar stays invisible until the pointer hovers the gap, then a
// blue line + "Insert item here" pill fades in (mirrors the queue "Add" accent).
// On phones there is no hover, so the pill shows faintly to stay discoverable.
// Tapping opens the stock picker and inserts the choice at this row's index.
class _InsertItemDivider extends StatefulWidget {
  const _InsertItemDivider({required this.wide, required this.onTap});
  final bool wide;
  final VoidCallback onTap;

  @override
  State<_InsertItemDivider> createState() => _InsertItemDividerState();
}

class _InsertItemDividerState extends State<_InsertItemDivider> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF1D4ED8);
    // Phones can't hover: keep the pill faintly visible so the gap is findable.
    final restingOpacity = widget.wide ? 0.0 : 0.5;
    final active = _hover || !widget.wide;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: SizedBox(
          height: 20,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  height: 1.5,
                  color: _hover ? accent.withValues(alpha: 0.5) : Colors.transparent,
                ),
              ),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 120),
                opacity: _hover ? 1.0 : restingOpacity,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  decoration: BoxDecoration(
                    color: active ? accent : accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_rounded,
                          size: 13, color: active ? Colors.white : accent),
                      const SizedBox(width: 3),
                      Text(
                        'Insert item here',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: active ? Colors.white : accent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetItemRow extends StatelessWidget {
  const _SheetItemRow({
    required this.item,
    this.serialNumber = 0,
    this.wide = false,
    this.source,
    this.score,
    this.rateSource,
    this.isEditing = false,
    this.isEdited = false,
    this.onStockItemSelected,
    this.onItemChanged,
    this.onDelete,
    this.partyName,
    this.isSale = false,
    this.voucherItemNames = const [],
    this.orderBase = 0,
    this.showDelete = true,
  });
  final Map<String, dynamic> item;
  final int serialNumber;
  final bool wide;
  final String? source;
  final String? score;
  // source_payload rate provenance for this line: 'same_party' | 'different_party'
  // | 'none'. Drives the sale-only "New Item" flag ("Y" when different_party).
  final String? rateSource;
  final bool isEditing;
  final bool isEdited;
  // History opens the sheet read-only; the per-row delete button is hidden
  // there (you can't delete a pushed voucher's lines).
  final bool showDelete;
  // Base focus-traversal order for this row's five stops: Item name (orderBase),
  // then Qty/Disc/Rate/Amount (orderBase+1..4). Lets Enter walk every cell in
  // sequence, including the item-name field.
  final int orderBase;
  final void Function(StockItem)? onStockItemSelected;
  // Called after a numeric cell (Qty/Disc/Rate/Amount) is edited; the item map
  // is mutated in place, so the parent recomputes charges and persists.
  final VoidCallback? onItemChanged;
  final String? partyName;
  final bool isSale;
  // Names of all lines on this voucher, forwarded to the picker so its sale
  // tier-2 fallback can price+flag items this party never sold.
  final List<String> voucherItemNames;
  final VoidCallback? onDelete;

  // Recomputes this line's amount from qty·rate·(1−disc%/100) so the Charges
  // block (which sums item amounts) rescales when Qty/Disc/Rate are edited
  // inline. Runs for sale and purchase; relies on discount_pct being present
  // (purchase rows without one are seeded at edit entry in _toggleEdit).
  // Mirrors the formula in _addItem / onStockItemSelected.
  void _recalcAmount() {
    final q = (item['qty'] as num?)?.toDouble() ??
        (item['quantity'] as num?)?.toDouble() ?? 0;
    final r = (item['rate'] as num?)?.toDouble() ?? 0;
    final d = (item['discount_pct'] as num?)?.toDouble() ?? 0;
    item['amount'] = q * r * (1 - d / 100);
  }

  static double? _parseScore(String? s) {
    if (s == null || s.isEmpty) return null;
    return double.tryParse(s.replaceAll('%', '').trim());
  }

  static Color _darken(Color color, {int shades = 3}) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness((hsl.lightness - shades * 0.08).clamp(0.0, 1.0))
        .toColor();
  }

  @override
  Widget build(BuildContext context) {
    final name = item['stock_item_name'] as String? ?? '—';
    final qty = (item['qty'] as num?)?.toDouble() ?? (item['quantity'] as num?)?.toDouble() ?? 0;
    final rate = (item['rate'] as num?)?.toDouble() ?? 0;
    final amount = (item['amount'] as num?)?.toDouble() ?? 0;
    final unit = item['unit'] as String? ?? '';
    // Discount %: stored rows carry discount_pct directly; the docstrange
    // purchase response instead gives a rupee `discount` per item. Many purchase
    // rows carry neither and bake the discount into `amount` (rate·qty ≠ amount),
    // so derive the percentage from 1 − amount/(qty·rate). Round to drop float
    // noise (3.0000…).
    final discPct = (item['discount_pct'] as num?)?.toDouble();
    final discAmt = (item['discount'] as num?)?.toDouble();
    final gross = qty * rate;
    final discValue = discPct ??
        ((discAmt != null && amount != 0)
            ? discAmt / amount * 100
            : (gross > 0 ? ((1 - amount / gross) * 100).clamp(0.0, 100.0) : 0.0));
    final disc = double.parse(discValue.toStringAsFixed(2));

    // A user's own committed correction, replayed from Audit_Trail_Purchase — the
    // strongest signal, so it takes precedence over the curated table and the matcher.
    final isAuditTrail = source == 'Audit_Trail';
    final isPurchaseMatching = source == 'Purchase_Matching';
    final isAlgorithm = source == 'Matching_Algorithem';
    final scoreVal = _parseScore(score);

    Color nameColor;
    String? statusLabel;

    if (isAuditTrail) {
      nameColor = const Color(0xFF16A34A);
      statusLabel = 'Taken from Audit Trail';
    } else if (isPurchaseMatching) {
      nameColor = const Color(0xFF16A34A);
      statusLabel = 'No need to edit, Historical Data';
    } else if (isAlgorithm && scoreVal != null) {
      if (scoreVal >= 90) {
        nameColor = const Color(0xFF16A34A);
        statusLabel = 'Confirmed match No need to edit';
      } else {
        nameColor = const Color(0xFFDC2626);
        statusLabel = 'Needs Attention !!';
      }
    } else {
      nameColor = AppPalette.pen;
      statusLabel = null;
    }

    if (isEdited) {
      nameColor = const Color(0xFF16A34A);
      statusLabel = 'Item Edited';
    }

    // Opens the stock-item picker (with the confidence/historical warning where
    // applicable). Triggered by tapping the item name, or by pressing the Down
    // arrow while the item field is focused via Enter-to-move.
    Future<void> openPicker() async {
      String? warnMessage;
      if (isAuditTrail) {
        warnMessage = 'Are you sure you want to edit this item? It was taken from the Audit Trail.';
      } else if (isPurchaseMatching) {
        warnMessage = 'Are you sure you want to edit this item, Its taken from historical Data';
      } else if (isAlgorithm && scoreVal != null && scoreVal >= 90) {
        warnMessage = 'Are you sure you want to edit this item, I have high confidence on this item';
      }

      if (warnMessage != null) {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            content: Text(
              warnMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.4),
            ),
            actionsAlignment: MainAxisAlignment.spaceEvenly,
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                style: TextButton.styleFrom(foregroundColor: AppPalette.muted),
                child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
              TextButton(
                // Autofocused so Enter (after Down opened this dialog via
                // Enter-to-move) activates OK without a mouse click.
                autofocus: true,
                onPressed: () => Navigator.of(ctx).pop(true),
                style: TextButton.styleFrom(foregroundColor: AppPalette.accent),
                child: const Text('OK', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        );
        if (ok != true) return;
        if (!context.mounted) return;
      }

      final selected = await showModalBottomSheet<StockItem>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _StockItemPickerSheet(
          changingFrom: name,
          partyName: partyName,
          isSale: isSale,
          voucherItemNames: voucherItemNames,
        ),
      );
      if (selected != null) onStockItemSelected?.call(selected);
    }

    return Container(
      decoration: BoxDecoration(border: Border(top: BorderSide(color: AppPalette.line.withValues(alpha: 0.6)))),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: _kSerialColW,
            child: Text(
              '$serialNumber',
              style: TextStyle(fontSize: 12, color: AppPalette.muted, fontWeight: FontWeight.w600),
            ),
          ),
          _itemCell(
            wide,
            isEditing
                      ? FocusTraversalOrder(
                          order: NumericFocusOrder(orderBase.toDouble()),
                          child: Focus(
                            // Enter (from the field before) lands here; Enter
                            // again advances to Qty, Down arrow opens the picker.
                            onKeyEvent: (node, event) {
                              if (event is! KeyDownEvent) {
                                return KeyEventResult.ignored;
                              }
                              final key = event.logicalKey;
                              if (key == LogicalKeyboardKey.arrowDown) {
                                openPicker();
                                return KeyEventResult.handled;
                              }
                              if (key == LogicalKeyboardKey.enter ||
                                  key == LogicalKeyboardKey.numpadEnter) {
                                node.nextFocus();
                                return KeyEventResult.handled;
                              }
                              return KeyEventResult.ignored;
                            },
                            child: Builder(
                              builder: (ctx) {
                                final focused = Focus.of(ctx).hasFocus;
                                return GestureDetector(
                                  onTap: openPicker,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: focused
                                            ? AppPalette.ink
                                            : Colors.transparent,
                                        width: 1.4,
                                      ),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 4, vertical: 2),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Flexible(
                                              child: Text(
                                                name,
                                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                      color: nameColor,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                              ),
                                            ),
                                            Icon(Icons.arrow_drop_down, size: 18, color: AppPalette.muted),
                                            _infoIconButton(context, name, partyName: partyName, isSale: isSale),
                                          ],
                                        ),
                                        if (statusLabel != null) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            statusLabel,
                                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                  color: _darken(nameColor),
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    name,
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          color: nameColor,
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                ),
                                _infoIconButton(context, name, partyName: partyName, isSale: isSale),
                              ],
                            ),
                            if (statusLabel != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                statusLabel,
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: _darken(nameColor),
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500,
                                    ),
                              ),
                            ],
                          ],
                        ),
          ),
          isEditing
              ? FocusTraversalOrder(
                  order: NumericFocusOrder((orderBase + 1).toDouble()),
                  child: _EditableNumCell(
                    width: _kQtyColW,
                    initial: qty,
                    suffix: unit.isNotEmpty ? unit : null,
                    onChanged: (v) {
                      item[item.containsKey('qty') ? 'qty' : 'quantity'] = v;
                      _recalcAmount();
                      onItemChanged?.call();
                    },
                  ),
                )
              : SizedBox(
                  width: _kQtyColW,
                  child: Text(
                    '${qty % 1 == 0 ? qty.toInt() : qty} $unit'.trim(),
                    textAlign: TextAlign.right,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppPalette.inkSoft),
                  ),
                ),
          // Rate then Disc, matching the column order (Qty · Rate · Disc).
          isEditing
              ? FocusTraversalOrder(
                  order: NumericFocusOrder((orderBase + 2).toDouble()),
                  child: _EditableNumCell(
                    width: _kRateColW,
                    initial: rate,
                    onChanged: (v) {
                      item['rate'] = v;
                      _recalcAmount();
                      onItemChanged?.call();
                    },
                  ),
                )
              : SizedBox(
                  width: _kRateColW,
                  child: Text(formatCurrency(rate), textAlign: TextAlign.right, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppPalette.inkSoft)),
                ),
          isEditing
              ? FocusTraversalOrder(
                  order: NumericFocusOrder((orderBase + 3).toDouble()),
                  child: _EditableNumCell(
                    width: _kDiscColW,
                    initial: disc,
                    suffix: '%',
                    onChanged: (v) {
                      item['discount_pct'] = v;
                      _recalcAmount();
                      onItemChanged?.call();
                    },
                  ),
                )
              : SizedBox(
                  width: _kDiscColW,
                  child: Text('${disc % 1 == 0 ? disc.toInt() : disc}%', textAlign: TextAlign.right, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppPalette.inkSoft)),
                ),
          // List price = Qty · Rate (gross, before discount). Display-only — it
          // recomputes live as Qty/Rate are edited but is never written back.
          SizedBox(
            width: _kListPriceColW,
            child: Text(formatCurrency(gross), textAlign: TextAlign.right, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppPalette.inkSoft)),
          ),
          isEditing
              ? FocusTraversalOrder(
                  order: NumericFocusOrder((orderBase + 4).toDouble()),
                  child: _EditableNumCell(
                    width: _kAmountColW,
                    initial: amount,
                    onChanged: (v) {
                      item['amount'] = v;
                      onItemChanged?.call();
                    },
                  ),
                )
              : SizedBox(
                  width: _kAmountColW,
                  child: Text(formatCurrency(amount), textAlign: TextAlign.right, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: AppPalette.inkSoft)),
                ),
          SizedBox(
            width: _kDeleteColW,
            child: !showDelete
                ? null
                : GestureDetector(
              onTap: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    content: Text(
                      'Are you sure you want to delete $name?',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.4),
                    ),
                    actionsAlignment: MainAxisAlignment.spaceEvenly,
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        style: TextButton.styleFrom(foregroundColor: AppPalette.muted),
                        child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        style: TextButton.styleFrom(foregroundColor: AppPalette.accent),
                        child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                );
                // ignore: use_build_context_synchronously
                if (confirmed == true && context.mounted) onDelete?.call();
              },
              child: Padding(
                padding: const EdgeInsets.only(left: 6, top: 1),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppPalette.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.delete_outline_rounded, size: 18, color: AppPalette.accent),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Stock item picker sheet ───────────────────────────────────────────────────

class _StockItemPickerSheet extends StatefulWidget {
  const _StockItemPickerSheet({
    this.changingFrom,
    this.partyName,
    this.isSale = false,
    this.voucherItemNames = const [],
  });
  final String? changingFrom;
  final String? partyName;
  final bool isSale;
  // Item names already on this voucher. Sale tier-2 fallback: any of these the
  // party never traded gets a borrowed rate from another party, flagged "new".
  final List<String> voucherItemNames;

  @override
  State<_StockItemPickerSheet> createState() => _StockItemPickerSheetState();
}

class _StockItemPickerSheetState extends State<_StockItemPickerSheet> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  // Keyboard navigation: index of the highlighted row. Down/Up move it, Enter
  // selects it. Reset to 0 whenever the filtered list changes.
  int _highlighted = 0;
  final Map<int, GlobalKey> _itemKeys = {};
  List<StockItem> _allItems = [];
  List<StockItem> _filtered = [];
  // Starts true so the first frame shows a spinner until the deferred initial
  // load (see initState) populates the list.
  bool _loading = true;
  // false → party-specific items (this party's history + sale tier-2 fallback);
  // true ("All items") → the full stock catalog from cache.
  // Defaults to All items everywhere. For a sale, the rate/discount is resolved
  // from sale history when an item is picked (see _selectItem), not from the
  // catalog, so the catalog is the right place to start browsing. With a party
  // present the toggle can still be flipped off to see that party's list.
  // Invariant: this always describes what _allItems holds — every path that
  // loads the catalog sets it true.
  late bool _showAll = true;
  // Bumped by every _load(). A party fetch carries the value it started with and
  // drops its result if it no longer matches, so a slow response can't overwrite
  // the list the toggle has since switched to.
  int _loadGen = 0;
  // Set when the party fetch failed and the catalog was shown instead, so the
  // sheet can say why the list isn't party-filtered. Shown inline rather than as
  // a snackbar, which would be hidden behind this modal sheet.
  bool _partyLoadFailed = false;

  // True while a catalog pick's historical rate is being resolved (see
  // _selectItem). Shows the list's loading spinner during the async gap so the
  // rows are replaced and can't be re-tapped mid-lookup.
  bool _selecting = false;

  // The party to query, or null when there is none. The edit path passes the
  // sheet's '—' display placeholder rather than null (see _buildSummaryView),
  // which would otherwise reach the query and match no voucher.
  String? get _party {
    final p = widget.partyName?.trim();
    return (p == null || p.isEmpty || p == '—') ? null : p;
  }

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onSearch);
    // Defer the first load to after the initial frame. Sale opens on the async
    // party fetch; kicking it off during initState can leave the list showing
    // nothing until the user toggles. Post-frame guarantees the fetch's
    // setState lands on a mounted, already-built widget.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  void _load() {
    final gen = ++_loadGen; // invalidates any party fetch still in flight
    if (_showAll || _party == null) {
      setState(() {
        // Showing the catalog, so the toggle must read "All items" — otherwise a
        // party-less voucher shows 13k items under a toggle that claims to be
        // filtered by party.
        _showAll = true;
        _allItems = StockItemsCache.instance.items;
        _applyFilter();
        _loading = false;
      });
    } else {
      // Sale → items sold to this customer; purchase → items bought from this
      // vendor (party-specific RPCs).
      _fetchPartyItems(gen);
    }
  }

  Future<void> _fetchPartyItems(int gen) async {
    setState(() {
      _loading = true;
      _partyLoadFailed = false; // a retry starts clean
    });
    // The get_{sale,purchase}_items_for_party RPCs match on
    // voucher_items.party_name, which the sync leaves null — so they return
    // nothing for every party. Query the line items directly instead and resolve
    // the party (and sale/purchase) through the parent voucher via an inner-join
    // embed. Purchase lists every occurrence with its per-invoice rate (no dedup).
    //
    // Sale uses this query ONLY to decide which items appear in the list — the
    // shortlist of what this customer actually buys. The rate and discount shown
    // against each come from resolveSalePricing (the same rule the backend uses),
    // not from these rows, so the badge matches what picking the row produces.
    final typeMatch = widget.isSale ? '%sale%' : '%purchase%';
    try {
      // PostgREST caps a single response at 1000 rows, so page through every
      // matching line item with .range(). A high-volume party can have several
      // thousand lines; without paging the picker would silently stop at 1000.
      // Ordered by id (unique → total order) so the pages are stable and don't
      // overlap or skip rows; display order is the date sort applied below.
      const pageSize = 1000;
      final rows = <Map<String, dynamic>>[];
      var from = 0;
      while (true) {
        final page = await Supabase.instance.client
            .from('voucher_items')
            .select(
                'stock_item_name, rate, unit, discount_pct, vouchers!inner(date, party_name, voucher_type)')
            .eq('vouchers.party_name', _party!)
            .ilike('vouchers.voucher_type', typeMatch)
            .order('id', ascending: true)
            .range(from, from + pageSize - 1);
        final batch = (page as List).cast<Map<String, dynamic>>();
        rows.addAll(batch);
        if (batch.length < pageSize) break;
        from += pageSize;
      }
      // Most recent first (by parent voucher date), so the newest invoices'
      // lines appear at the top of the list.
      rows.sort((a, b) {
        final da = (a['vouchers'] as Map?)?['date'] as String? ?? '';
        final db = (b['vouchers'] as Map?)?['date'] as String? ?? '';
        return db.compareTo(da);
      });
      final items = <StockItem>[];
      if (widget.isSale) {
        // List membership: everything this party has bought, in date-desc order,
        // plus this voucher's own lines (which they may never have bought — those
        // used to need a tier-2 fetch each; the global rate RPC now covers them).
        final names = <String>[];
        final seen = <String>{};
        for (final row in rows) {
          final name = row['stock_item_name'] as String? ?? '';
          if (name.isEmpty || !seen.add(name)) continue;
          names.add(name);
        }
        for (final n in widget.voucherItemNames.map((n) => n.trim())) {
          if (n.isEmpty || n == 'NO MATCH' || !seen.add(n)) continue;
          names.add(n);
        }
        // Two RPCs for the whole list, however long it is.
        final priced = await resolveSalePricing(party: _party, itemNames: names);
        for (final name in names) {
          final p = priced[name] ?? SalePricing.none;
          items.add(StockItem(
            name: name,
            groupName: '',
            rate: p.rate,
            unit: StockItemsCache.instance.unitFor(name),
            discountPct: p.discountPct,
            source: p.rateSource,
            discountSource: p.discountSource,
            // voucher_items has no part_code; pull it from the catalog cache.
            partCode: StockItemsCache.instance.partCodeFor(name),
          ));
        }
      } else {
        // Purchase: unchanged — every occurrence, with its per-invoice rate.
        for (final row in rows) {
          final name = row['stock_item_name'] as String? ?? '';
          if (name.isEmpty) continue;
          items.add(StockItem(
            name: name,
            groupName: '',
            rate: (row['rate'] as num?)?.toDouble() ?? 0.0,
            unit: row['unit'] as String? ?? '',
            discountPct: (row['discount_pct'] as num?)?.toDouble() ?? 0.0,
            source: 'same_party',
            // voucher_items has no part_code; pull it from the catalog cache.
            partCode: StockItemsCache.instance.partCodeFor(name),
          ));
        }
      }
      if (!mounted || gen != _loadGen) return;
      setState(() {
        _allItems = items;
        _applyFilter();
        _loading = false;
      });
    } catch (e, st) {
      reportHandledError('supabase.picker.party_items', e, stackTrace: st);
      if (!mounted || gen != _loadGen) return;
      setState(() {
        // Falling back to the catalog, so flip the toggle to match it. Leaving it
        // off would silently show all 13k items as if they were this party's.
        _showAll = true;
        _partyLoadFailed = true;
        _allItems = StockItemsCache.instance.items;
        _applyFilter();
        _loading = false;
      });
    }
  }

  // (The tier-2 per-item fallback that used to live here is gone: the rate RPC
  // is already party-agnostic, so an item this party never bought is covered by
  // the same batch call as everything else. It also ordered by created_at, the
  // sync-insertion time — the bug fixed backend-side in 53014c9.)

  // A sale pick from the catalog ("All items") adopts its rate/discount from
  // sale history, not the catalog price. Party-scoped picks (source already
  // 'same_party'/'different_party') and purchase picks carry the right rate, so
  // they pop straight through. Resolves, then closes the sheet with the result.
  Future<void> _selectItem(StockItem s) async {
    if (_selecting) return;
    if (!widget.isSale || s.source.isNotEmpty) {
      Navigator.of(context).pop(s);
      return;
    }
    setState(() => _selecting = true);
    final resolved = await _resolveSaleRate(s);
    if (!mounted) return;
    Navigator.of(context).pop(resolved);
  }

  // Resolves one item through the shared rule (see lib/data/sale_pricing.dart):
  // rate = latest GST SALE to ANYONE, discount = latest GST SALE to THIS party.
  // A missing or failed lookup collapses to 0 — never the catalog rate the user
  // is moving away from.
  Future<StockItem> _resolveSaleRate(StockItem s) async {
    final priced = await resolveSalePricing(party: _party, itemNames: [s.name]);
    return _stockItemWithRate(s, priced[s.name] ?? SalePricing.none);
  }

  // StockItem is a const model with no copyWith — build the enriched copy with
  // the resolved rate/discount/sources, keeping the row's identity fields.
  //
  // Unit comes from the stock master rather than the historical voucher line:
  // the RPCs are pricing-only, and the master is the canonical unit anyway.
  StockItem _stockItemWithRate(StockItem s, SalePricing p) {
    final unit = s.unit.trim().isNotEmpty
        ? s.unit
        : StockItemsCache.instance.unitFor(s.name);
    return StockItem(
      name: s.name,
      groupName: s.groupName,
      rate: p.rate,
      unit: unit,
      discountPct: p.discountPct,
      source: p.rateSource,
      discountSource: p.discountSource,
      partCode: s.partCode,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onSearch() => setState(_applyFilter);

  // Filters _allItems by the current search text into _filtered. Call in setState.
  // Space-insensitive: "hsstap" matches "HSS TAP 12 X 1.75 SET TOTEM".
  void _applyFilter() {
    final query = searchKey(_controller.text);
    _filtered = query.isEmpty
        ? _allItems
        : _allItems
            .where((s) =>
                searchKey(s.name).contains(query) ||
                searchKey(s.partCode).contains(query))
            .toList();
    // A new result set invalidates the old highlight position.
    _highlighted = 0;
  }

  GlobalKey _keyFor(int i) => _itemKeys.putIfAbsent(i, () => GlobalKey());

  // Moves the highlight by [delta] (clamped) and scrolls it into view. The
  // search field keeps focus so the user can keep typing.
  void _moveHighlight(int delta) {
    if (_filtered.isEmpty) return;
    setState(() {
      _highlighted = (_highlighted + delta).clamp(0, _filtered.length - 1);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _itemKeys[_highlighted]?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx,
            alignment: 0.5, duration: const Duration(milliseconds: 120));
      }
    });
  }

  // Down/Up move the highlight, Enter selects it. Returns handled so these keys
  // don't reach the text field (cursor moves / submit).
  KeyEventResult _onSearchKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      _moveHighlight(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _moveHighlight(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      if (_filtered.isNotEmpty) {
        _selectItem(_filtered[_highlighted]);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.72,
      decoration: BoxDecoration(
        color: AppPalette.sheet,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(color: AppPalette.line, borderRadius: BorderRadius.circular(99)),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
            child: Row(
              children: [
                if (widget.changingFrom != null) ...[
                  Text(
                    'Changing From : ',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppPalette.muted,
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                  Expanded(
                    child: Text(
                      widget.changingFrom!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppPalette.ink,
                            fontWeight: FontWeight.w700,
                          ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ] else
                  const Spacer(),
                const SizedBox(width: 8),
                Text(
                  'count : ${_filtered.length}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppPalette.muted,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(width: 12),
                Text(
                  'All items',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _showAll ? AppPalette.ink : AppPalette.muted,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                Switch(
                  value: _showAll,
                  // Inert while a fetch is in flight (the list can't match the
                  // toggle mid-flight), and when there is no party to filter by
                  // — switching would have no other list to show.
                  onChanged: (_loading || _party == null)
                      ? null
                      : (v) {
                          setState(() => _showAll = v);
                          _load();
                        },
                ),
              ],
            ),
          ),
          if (_partyLoadFailed)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "Couldn't load this party's items — showing all items",
                  style: TextStyle(
                      fontSize: 11,
                      color: const Color(0xFFDC2626),
                      fontWeight: FontWeight.w700),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            // Intercepts Down/Up/Enter before the text field handles them, so
            // the user can navigate the list without leaving the search box.
            child: Focus(
              onKeyEvent: _onSearchKey,
              child: TextField(
                controller: _controller,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Search stock items…',
                  hintStyle: const TextStyle(fontSize: 13),
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  suffixIcon: _controller.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 18),
                          onPressed: _controller.clear,
                        )
                      : null,
                  filled: true,
                  fillColor: AppPalette.gridHeader,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  isDense: true,
                ),
              ),
            ),
          ),
          // Create a brand-new stock item in TallyPrime when the catalog doesn't
          // have it (prefills the current search text). The created item is
          // returned as this picker's result so the line uses it immediately.
          InkWell(
            onTap: () async {
              final created = await showStockItemCreateSheet(
                context,
                initialName: _controller.text.trim(),
              );
              if (created != null && context.mounted) {
                Navigator.of(context).pop(created);
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.add_circle_outline_rounded,
                      size: 18, color: AppPalette.accent),
                  const SizedBox(width: 8),
                  Text(
                    _controller.text.trim().isEmpty
                        ? 'Create new stock item'
                        : 'Create "${_controller.text.trim()}" as new item',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppPalette.accent,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: AppPalette.line.withValues(alpha: 0.5)),
          Expanded(
            child: _loading || _selecting
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : ListView.separated(
                    controller: _scrollController,
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: _filtered.length,
                    separatorBuilder: (_, i2) => Divider(height: 1, color: AppPalette.line.withValues(alpha: 0.5)),
                    itemBuilder: (ctx, i) {
                      final s = _filtered[i];
                      return InkWell(
                        key: _keyFor(i),
                        onTap: () => _selectItem(s),
                        child: Container(
                          color: i == _highlighted
                              ? AppPalette.ink.withValues(alpha: 0.06)
                              : null,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(s.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                    if (s.partCode.isNotEmpty)
                                      Text(s.partCode, style: TextStyle(fontSize: 11, color: AppPalette.muted, fontWeight: FontWeight.w600)),
                                    if (s.groupName.isNotEmpty)
                                      Text(s.groupName, style: TextStyle(fontSize: 11, color: AppPalette.muted)),
                                    // "New to this party" is now about the
                                    // DISCOUNT, not the rate. Rate is party-
                                    // agnostic, so 'different_party' is the normal
                                    // case even for items this customer buys
                                    // weekly — it only means the newest sale
                                    // anywhere happened to be to someone else.
                                    // What the reviewer needs to know is that no
                                    // discount applies, which is what drives the
                                    // price up.
                                    if (s.discountSource == 'none' && s.source != 'none')
                                      const Text('New to this party · no discount',
                                          style: TextStyle(fontSize: 11, color: Color(0xFFDC2626), fontWeight: FontWeight.w700)),
                                    if (s.source == 'none')
                                      const Text('Never sold · no rate on record',
                                          style: TextStyle(fontSize: 11, color: Color(0xFFDC2626), fontWeight: FontWeight.w700)),
                                  ],
                                ),
                              ),
                              // Show a rate only when one was actually resolved.
                              // Catalog rows (source == '', the "All items" view)
                              // would show the misleading master price, and
                              // 'none' rows have no price at all — printing 0.00
                              // there reads as "this item is free".
                              if (s.source == 'same_party' || s.source == 'different_party')
                                Text(
                                  formatCurrency(s.rate),
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppPalette.inkSoft),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Push-to-Tally confirmation dialog ─────────────────────────────────────────

// ── Stock-item validation (runs after "Yes", before the actual push) ──────────
// Shows a "Stock Items Validation Check" spinner, then verifies every invoice
// line exists in the cached stock catalog. Pops `true` when all items exist
// (caller proceeds to push); on any miss it lists the offending names and pops
// `false` on OK (caller does not push).
class _StockValidationDialog extends StatefulWidget {
  const _StockValidationDialog({required this.itemNames});

  final List<String> itemNames;

  @override
  State<_StockValidationDialog> createState() => _StockValidationDialogState();
}

class _StockValidationDialogState extends State<_StockValidationDialog> {
  bool _checking = true;
  List<String> _missing = const [];

  @override
  void initState() {
    super.initState();
    _runCheck();
  }

  Future<void> _runCheck() async {
    // Brief delay so the "checking" state is actually visible for this
    // otherwise-instant in-memory lookup.
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;

    final cache = StockItemsCache.instance;
    // Fail-open: an empty catalog means the fetch never succeeded, so we can't
    // validate. Don't strand the user — proceed to push (same as before).
    if (cache.items.isEmpty) {
      Navigator.of(context).pop(true);
      return;
    }

    final missing = <String>[];
    final seen = <String>{};
    for (final raw in widget.itemNames) {
      if (!cache.exists(raw) && seen.add(raw.trim().toLowerCase())) {
        missing.add(raw);
      }
    }

    if (missing.isEmpty) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _checking = false;
        _missing = missing;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _DialogFrame(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
        child: _checking ? _buildChecking(context) : _buildMissing(context),
      ),
    );
  }

  Widget _buildChecking(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 40,
          height: 40,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            valueColor: AlwaysStoppedAnimation<Color>(AppPalette.accent),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Stock Items Validation Check',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
        ),
      ],
    );
  }

  Widget _buildMissing(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.error_outline_rounded, size: 44, color: AppPalette.accent),
        const SizedBox(height: 16),
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final name in _missing) ...[
                  Text(
                    'This Item \'$name\' does not Exist, Please edit',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppPalette.accent,
                          height: 1.4,
                        ),
                  ),
                  const SizedBox(height: 8),
                  // Create the missing item in TallyPrime right here, then
                  // re-run the check — once every name exists the dialog pops
                  // true and the push proceeds.
                  OutlinedButton.icon(
                    onPressed: () async {
                      final created =
                          await showStockItemCreateSheet(context, initialName: name);
                      if (created != null && mounted) {
                        setState(() => _checking = true);
                        _runCheck();
                      }
                    },
                    icon: const Icon(Icons.add_circle_outline_rounded, size: 16),
                    label: const Text('Create in Tally'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppPalette.accent,
                      textStyle: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(false),
          style: FilledButton.styleFrom(
            backgroundColor: AppPalette.accent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
          child: const Text('OK'),
        ),
      ],
    );
  }
}

// Yes/Cancel confirm shown before opening or pushing a duplicate voucher. The
// full prompt (e.g. "This Invoice Is Already Pushed, Are you sure you want to
// open it") is passed in; returns true on Yes, false/null on Cancel. Styled to
// match _PushConfirmDialog.
class DuplicateActionDialog extends StatelessWidget {
  const DuplicateActionDialog({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return _DialogFrame(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.4,
                  ),
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppPalette.inkSoft,
                      side: BorderSide(color: AppPalette.line, width: 1.4),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      textStyle: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppPalette.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      textStyle: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    child: const Text('Yes'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PushConfirmDialog extends StatelessWidget {
  const _PushConfirmDialog();

  @override
  Widget build(BuildContext context) {
    return _DialogFrame(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Are You Sure You Want To Push This invoice to Tally Prime',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.4,
                  ),
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppPalette.inkSoft,
                      side: BorderSide(color: AppPalette.line, width: 1.4),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      textStyle: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppPalette.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      textStyle: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    child: const Text('Yes'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Save-before-push notice (shown when pushing with edit mode still on) ───────

class _SaveBeforePushDialog extends StatelessWidget {
  const _SaveBeforePushDialog();

  @override
  Widget build(BuildContext context) {
    return _DialogFrame(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Kindly Save the invoice before pushing to tally',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.4,
                  ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                style: FilledButton.styleFrom(
                  backgroundColor: AppPalette.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  textStyle: const TextStyle(fontWeight: FontWeight.w700),
                ),
                child: const Text('OK'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Sale-pushed confirmation modal ────────────────────────────────────────────
// Shown after a sale voucher is successfully pushed to Tally: customer, amount
// and the push date/time.

class _SalePushedDialog extends StatelessWidget {
  const _SalePushedDialog({
    required this.customerName,
    required this.amount,
    required this.pushedAt,
  });

  final String customerName;
  final double amount;
  final DateTime pushedAt;

  String get _dateTime {
    final d = pushedAt;
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final hour12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final hh = hour12.toString().padLeft(2, '0');
    final min = d.minute.toString().padLeft(2, '0');
    final ampm = d.hour < 12 ? 'AM' : 'PM';
    return '$dd/$mm/${d.year}, $hh:$min $ampm';
  }

  @override
  Widget build(BuildContext context) {
    return _DialogFrame(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.check_circle_rounded, size: 48, color: Color(0xFF16A34A)),
            const SizedBox(height: 16),
            Text(
              'Pushed to Tally',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 20),
            _SalePushedRow(label: 'Customer Name', value: customerName),
            const SizedBox(height: 12),
            _SalePushedRow(label: 'Amount', value: formatCurrency(amount)),
            const SizedBox(height: 12),
            _SalePushedRow(label: 'Date and Time', value: _dateTime),
            const SizedBox(height: 28),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              style: FilledButton.styleFrom(
                backgroundColor: AppPalette.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                textStyle: const TextStyle(fontWeight: FontWeight.w700),
              ),
              child: const Text('OK'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SalePushedRow extends StatelessWidget {
  const _SalePushedRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppPalette.inkSoft,
                ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
      ],
    );
  }
}

// ── Sale push-failed modal ────────────────────────────────────────────────────
// Shown when a sale push comes back with created:0 / errors (or status failed):
// a cross sign, the customer, and the Tally error message.

class _SalePushFailedDialog extends StatelessWidget {
  const _SalePushFailedDialog({
    required this.customerName,
    required this.errorMessage,
  });

  final String customerName;
  final String errorMessage;

  @override
  Widget build(BuildContext context) {
    return _DialogFrame(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.cancel_rounded, size: 48, color: AppPalette.accent),
            const SizedBox(height: 16),
            Text(
              'Not Pushed to Tally',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 20),
            _SalePushedRow(label: 'Customer Name', value: customerName),
            const SizedBox(height: 12),
            _SalePushedRow(label: 'Error', value: errorMessage),
            const SizedBox(height: 28),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              style: FilledButton.styleFrom(
                backgroundColor: AppPalette.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                textStyle: const TextStyle(fontWeight: FontWeight.w700),
              ),
              child: const Text('OK'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Discard confirmation dialog ───────────────────────────────────────────────

class _DiscardConfirmDialog extends StatelessWidget {
  const _DiscardConfirmDialog();

  @override
  Widget build(BuildContext context) {
    return _DialogFrame(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Are you sure You want to delete this Invoice',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.4,
                  ),
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppPalette.inkSoft,
                      side: BorderSide(color: AppPalette.line, width: 1.4),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      textStyle: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppPalette.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      textStyle: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    child: const Text('Yes'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Duplicate purchase dialog ─────────────────────────────────────────────────

class _DuplicatePurchaseDialog extends StatelessWidget {
  const _DuplicatePurchaseDialog();

  @override
  Widget build(BuildContext context) {
    return _DialogFrame(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: Color(0xFFFFE4E1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close_rounded, color: Color(0xFFDC2626), size: 36),
            ),
            const SizedBox(height: 20),
            Text(
              'Sorry, this purchase has already been pushed',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.4,
                  ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFFFE4E1),
                  foregroundColor: const Color(0xFFDC2626),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  textStyle: const TextStyle(fontWeight: FontWeight.w700),
                ),
                child: const Text('OK'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Caps dialog width so confirmation dialogs read as a centered card on web
// instead of stretching into a full-width band. On phones the inset padding
// keeps them narrower than 420, so this only kicks in on wide screens.
class _DialogFrame extends StatelessWidget {
  const _DialogFrame({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: child,
      ),
    );
  }
}

// Document-style viewer for the scanned invoice pages stored in GCS: every page
// is stacked top-to-bottom in one scroll, so a multi-page invoice is read by
// scrolling (no slider). Each page is fetched lazily from the backend
// (`/api/sync/push-queue/{rowId}/image/{n}`) with the app's Firebase auth and
// cached so scrolling back doesn't re-download.
class _StoredInvoiceImages extends StatefulWidget {
  const _StoredInvoiceImages({
    required this.rowId,
    required this.pageCount,
    this.scale = 1.0,
  });

  final String rowId;
  final int pageCount;
  // Zoom factor from the image pane's zoom buttons; 1.0 fits the pane width,
  // larger widens each page and reveals a horizontal scroll.
  final double scale;

  @override
  State<_StoredInvoiceImages> createState() => _StoredInvoiceImagesState();
}

class _StoredInvoiceImagesState extends State<_StoredInvoiceImages> {
  final Map<int, Future<Uint8List>> _pageFutures = {};

  Future<Uint8List> _loadPage(int page) {
    return _pageFutures.putIfAbsent(
      page,
      () => ApiClient.getBytes('/api/sync/push-queue/${widget.rowId}/image/$page'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final multiPage = widget.pageCount > 1;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: widget.pageCount,
      itemBuilder: (context, page) {
        return Padding(
          padding: EdgeInsets.only(bottom: page == widget.pageCount - 1 ? 0 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (multiPage)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    'Page ${page + 1} of ${widget.pageCount}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppPalette.muted,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              FutureBuilder<Uint8List>(
                future: _loadPage(page),
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return Container(
                      height: 360,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppPalette.gridHeader,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppPalette.line, width: 1),
                      ),
                      child: const SizedBox(
                        width: 30,
                        height: 30,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                    );
                  }
                  if (snapshot.hasError || snapshot.data == null) {
                    return Container(
                      height: 120,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppPalette.gridHeader,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppPalette.line, width: 1),
                      ),
                      child: Text(
                        'Couldn\'t load this page.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppPalette.muted),
                      ),
                    );
                  }
                  return LayoutBuilder(
                    builder: (context, c) => SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(
                          snapshot.data!,
                          fit: BoxFit.fitWidth,
                          width: c.maxWidth * widget.scale,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
