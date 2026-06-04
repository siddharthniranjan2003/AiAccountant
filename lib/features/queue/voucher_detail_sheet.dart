import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/palette.dart';
import '../../core/utils.dart';
import '../../data/customers_cache.dart';
import '../../data/stock_items_cache.dart';

// ── View mode enum ────────────────────────────────────────────────────────────

enum _VdsViewMode { image, summary }

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
const double _kQtyColW = 64;
const double _kDiscColW = 52;
const double _kRateColW = 88;
const double _kAmountColW = 96;
const double _kDeleteColW = 40;
// Column widths + the row's horizontal padding (12*2) and container border
// (~1.2*2) so the inner Row gets the full column width without overflowing.
const double _kItemsTableW =
    _kItemColW + _kQtyColW + _kDiscColW + _kRateColW + _kAmountColW + _kDeleteColW + 27;

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
  }) : assert(payload != null || pendingPayload != null,
            'Provide either a resolved payload or a pendingPayload future');

  /// Resolved voucher payload (Supabase entries, or a re-opened local scan).
  final Map<String, dynamic>? payload;

  /// In-flight parse for a freshly scanned document. When set, the sheet opens
  /// immediately (showing the image) and fills Summary once it resolves.
  final Future<Map<String, dynamic>>? pendingPayload;

  final bool initialIsEditing;
  final List<Map<String, dynamic>>? initialEditableItems;
  final void Function(bool isEditing, List<Map<String, dynamic>> items)? onEditStateChanged;
  final Uint8List? imageBytes;

  /// When provided, a red "Discard" button shows at the bottom of the sheet.
  /// Confirming it calls this and pops; the queue screen drops the row locally
  /// only (no Supabase write), so a refresh re-fetches and shows it again.
  final VoidCallback? onDiscard;

  @override
  State<VoucherDetailSheet> createState() => _VoucherDetailSheetState();
}

class _VoucherDetailSheetState extends State<VoucherDetailSheet> {
  Map<String, dynamic>? _payload;
  bool _loading = false;
  String? _loadError;
  late String _status;
  bool _isSubmitting = false;
  bool _isEditing = false;
  String? _editablePartyName;
  // Captured once on first edit entry; never mutated so comparisons always
  // reference the true server/original values for this sheet session.
  String? _originalPartyName;
  List<String>? _originalItemNames;
  Map<String, dynamic>? _originalPayload;
  List<Map<String, dynamic>> _editableItems = [];
  // Editable copies of the Charges block (ledger rows + discount + total).
  // Populated when edit mode is entered; mutated in place while typing.
  List<Map<String, dynamic>> _editableLedgers = [];
  double? _editableDiscount;
  double? _editableTotal;
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

  bool get _isSale {
    final vt = (_p['voucher_type'] as String? ?? '').toUpperCase();
    if (vt.isNotEmpty) return vt.contains('SALE');
    return _p.containsKey('sale_voucher_payload');
  }

  // True when the party name currently shown differs from the original captured
  // at first edit entry. Stays true across save cycles.
  bool get _partyNameWasChanged {
    if (!_isSale || _originalPartyName == null) return false;
    final current = _editablePartyName ??
        _p['party_name'] as String? ??
        _voucher?['party_name'] as String? ??
        _voucher?['party_ledger_name'] as String? ??
        _header?['vendor_name'] as String? ?? '—';
    return current != _originalPartyName;
  }

  // True when every item in the current view differs from the name it had when
  // the sheet was first opened. Checks _editableItems during edit mode and
  // _payloadItems in view mode so it stays correct across save cycles.
  bool get _allItemsDifferentFromOriginal {
    final origNames = _originalItemNames;
    if (origNames == null || origNames.isEmpty) return true;
    final currentItems = _isEditing ? _editableItems : _payloadItems;
    for (var i = 0; i < origNames.length; i++) {
      if (i >= currentItems.length) continue; // item deleted — counts as changed
      final currentName = currentItems[i]['stock_item_name'] as String? ?? '';
      if (currentName == origNames[i]) return false;
    }
    return true;
  }

  static const _activateUrl =
      'https://tallybridge-backend-xx3yz3b3kq-el.a.run.app/api/sync/push-queue/activate';
  static const _apiKey = 'sb_publishable_c2Cov2CT8hxOd1FFEo_yaA_6nEt8_Nl';

  @override
  void initState() {
    super.initState();
    _isEditing = widget.initialIsEditing;
    if (widget.initialIsEditing && widget.initialEditableItems != null && widget.initialEditableItems!.isNotEmpty) {
      _editableItems = widget.initialEditableItems!
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }

    if (widget.payload != null) {
      _status = widget.payload!['__status'] as String? ?? 'pending';
      _applyPayload(widget.payload!);
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

  // Decide which tabs to show. Email-sourced entries have no scanned image,
  // so they get [Summary]; OCR/camera entries get [Image, Summary].
  void _applyPayload(Map<String, dynamic> p, {bool preserveViewMode = false}) {
    _payload = p;
    final rowId = p['__row_id'] as String? ?? '';
    if (rowId.isNotEmpty) _subscribeToStatus(rowId);

    final sourcePayload = p['__source_payload'] as Map<String, dynamic>?;
    final isEmail = sourcePayload?['fetched_from'] == 'email';
    final hasImage = !isEmail && widget.imageBytes != null;
    final keep = preserveViewMode ? _viewMode : null;
    _availableModes = [
      if (hasImage) _VdsViewMode.image,
      _VdsViewMode.summary,
    ];
    _viewMode = (keep != null && _availableModes.contains(keep)) ? keep : _availableModes.first;
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
    widget.onEditStateChanged?.call(_isEditing, List.of(_editableItems));
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  void _toggleEdit() {
    if (!_isEditing && StockItemsCache.instance.isLoading) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Loading of stock items in process, please wait'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    final items = _payloadItems;
    setState(() {
      if (!_isEditing) {
        // Entering edit mode — capture originals once for the lifetime of the sheet
        _editablePartyName = null;
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
        final charges = _computeCharges();
        _editableLedgers =
            charges.breakdown.map((e) => Map<String, dynamic>.from(e)).toList();
        _editableDiscount = charges.discount;
        _editableTotal = charges.total;
      } else {
        // Saving — write all edits back into the local payload so that
        // _payloadItems and party_name reflect the saved state immediately.
        if (_payload != null) {
          final updated = Map<String, dynamic>.from(_payload!);
          if (_editablePartyName != null) {
            updated['party_name'] = _editablePartyName;
          }
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
          _payload = updated;
        }
        _editablePartyName = null;
      }
      _isEditing = !_isEditing;
    });
    _notifyEditState();
  }

  // Discards every edit (items + charges) and leaves edit mode, restoring the
  // original parsed values. Since edit mode is off afterwards, the Revert
  // button hides until Edit is tapped again.
  void _revert() {
    setState(() {
      _isEditing = false;
      _editablePartyName = null;
      _editableItems = [];
      _editableLedgers = [];
      _editableDiscount = null;
      _editableTotal = null;
      if (_originalPayload != null) {
        _payload = Map<String, dynamic>.from(_originalPayload!);
      }
    });
    _notifyEditState();
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
        _payloadItems.fold<double>(
            0, (sum, it) => sum + ((it['discount'] as num?)?.toDouble() ?? 0));
    final inventoryLedgerName = voucher?['inventory_ledger_name'] as String?;
    return (
      breakdown: breakdown,
      total: total,
      discount: discount,
      invLedger: inventoryLedgerName,
    );
  }

  // Asks for confirmation before pushing to Tally. "Yes" runs the original
  // activate flow; "Cancel" just dismisses the dialog and stays on the sheet.
  Future<void> _confirmAndActivate() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const _PushConfirmDialog(),
    );
    if (confirmed == true && mounted) {
      await _activate();
    }
  }

  // Confirms then discards: removes the row from the queue locally only (no
  // Supabase write), so a refresh re-fetches and shows it again.
  Future<void> _confirmAndDiscard() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const _DiscardConfirmDialog(),
    );
    if (confirmed == true && mounted) {
      widget.onDiscard?.call();
      Navigator.of(context).pop();
    }
  }

  Future<void> _activate() async {
    final rowId = _p['__row_id'] as String? ?? '';
    if (rowId.isEmpty) return;

    setState(() => _isSubmitting = true);
    try {
      final response = await http.post(
        Uri.parse(_activateUrl),
        headers: {'Content-Type': 'application/json', 'x-api-key': _apiKey},
        body: jsonEncode({'job_id': rowId}),
      );

      if (!mounted) return;
      if (response.statusCode >= 200 && response.statusCode < 300) {
        _isEditing = false;
        _notifyEditState();
        Navigator.of(context).pop();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed (${response.statusCode}): ${response.body}')),
        );
        setState(() => _isSubmitting = false);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      setState(() => _isSubmitting = false);
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
            final newStatus = payload.newRecord['status'] as String? ?? _status;
            setState(() => _status = newStatus);
          },
        )
        .subscribe();
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
    final voucherNumber =
        _p['voucher_number'] as String? ??
        voucher?['voucher_number'] as String? ??
        header?['invoice_number'] as String? ?? '—';
    final date = formatDate(_p['date'] as String? ??
        voucher?['date'] as String? ??
        header?['invoice_date'] as String?);
    final narration = _p['narration'] as String? ?? voucher?['narration'] as String?;
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
    final discount =
        _isEditing ? (_editableDiscount ?? charges.discount) : charges.discount;

    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      height: screenHeight * 0.88,
      decoration: const BoxDecoration(
        color: AppPalette.sheet,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
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
                      if (_isEditing && _isSale && !_loading)
                        GestureDetector(
                          onTap: () async {
                            if (CustomersCache.instance.isLoading) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Please wait, customer list is still downloading…'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                              return;
                            }
                            final selected = await showModalBottomSheet<Customer>(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder: (_) => const _CustomerPickerSheet(),
                            );
                            if (selected != null && mounted) {
                              setState(() => _editablePartyName = selected.name);
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
                              const Icon(Icons.arrow_drop_down, size: 22, color: AppPalette.muted),
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
                              onPressed: null,
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
                          ],
                        ),
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
          // Only show the Image/Summary switcher when there's an image to
          // switch to. Push-queue entries have no scanned image, so the lone
          // "Summary" pill is pointless and is hidden.
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
              _VdsViewMode.summary => _loading
                  ? _buildLoadingBody(context)
                  : _loadError != null
                      ? _buildErrorBody(context)
                      : _buildSummaryView(
                          context,
                          partyName: partyName,
                          voucherNumber: voucherNumber,
                          date: date,
                          reference: reference,
                          narration: narration,
                          total: total,
                          discount: discount,
                          breakdownEntries: breakdownEntries,
                          inventoryLedgerName: inventoryLedgerName,
                          items: items,
                          sourceItems: sourceItems,
                        ),
            },
          ),
          if (!_loading || widget.onDiscard != null)
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
                          label: const Text('Discard'),
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
                    if (!_loading)
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
    final isRate = inventoryLedgerName != null && name != inventoryLedgerName;
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

  Widget _buildImageView(BuildContext context) {
    final bytes = widget.imageBytes;
    if (bytes == null) {
      return Center(
        child: Text(
          'No image available',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppPalette.muted),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 5,
          child: SizedBox.expand(
            child: Image.memory(bytes, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryView(
    BuildContext context, {
    required String partyName,
    required String voucherNumber,
    required String date,
    required String? reference,
    required String? narration,
    required double total,
    required double discount,
    required List<Map<String, dynamic>> breakdownEntries,
    required String? inventoryLedgerName,
    required List<Map<String, dynamic>> items,
    required List<Map<String, dynamic>> sourceItems,
  }) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Container(
          decoration: BoxDecoration(
            color: AppPalette.gridHeader,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppPalette.line, width: 1.2),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            children: [
              _SheetHeaderRow('Vendor', partyName),
              _SheetHeaderRow('Invoice #', voucherNumber),
              _SheetHeaderRow('Date', date),
              if (reference != null && reference != voucherNumber)
                _SheetHeaderRow('Reference', reference),
              if (narration != null) _SheetHeaderRow('Narration', narration),
              _SheetHeaderRow('Total', formatCurrency(total), bold: true),
            ],
          ),
        ),
        if (items.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            'Items',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: _kItemsTableW,
              child: Column(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: AppPalette.gridHeader,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                      border: Border.all(color: AppPalette.line, width: 1.2),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: const Row(
                      children: [
                        SizedBox(width: _kItemColW, child: Text('Item', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12))),
                        _SheetColHeader('Qty', width: _kQtyColW),
                        _SheetColHeader('Disc', width: _kDiscColW),
                        _SheetColHeader('Rate', width: _kRateColW),
                        _SheetColHeader('Amount', width: _kAmountColW),
                        SizedBox(width: _kDeleteColW),
                      ],
                    ),
                  ),
          Container(
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: AppPalette.line, width: 1.2),
                right: BorderSide(color: AppPalette.line, width: 1.2),
                bottom: BorderSide(color: AppPalette.line, width: 1.2),
              ),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
            ),
            child: Column(children: [
              for (var i = 0; i < items.length; i++)
                _SheetItemRow(
                  item: i < _editableItems.length ? _editableItems[i] : items[i],
                  source: i < sourceItems.length ? sourceItems[i]['source'] as String? : null,
                  score: i < sourceItems.length ? sourceItems[i]['score'] as String? : null,
                  isEditing: _isEditing,
                  partyName: partyName,
                  isSale: _isSale,
                  isEdited: () {
                    final currentName = i < _editableItems.length
                        ? (_editableItems[i]['stock_item_name'] as String? ?? '')
                        : (items[i]['stock_item_name'] as String? ?? '');
                    final origName = (_originalItemNames != null && i < _originalItemNames!.length)
                        ? _originalItemNames![i]
                        : (items[i]['stock_item_name'] as String? ?? '');
                    return currentName != origName;
                  }(),
                  onStockItemSelected: (selected) {
                    setState(() {
                      if (i < _editableItems.length) {
                        _editableItems[i]['stock_item_name'] = selected.name;
                        _editableItems[i]['rate'] = selected.rate;
                        _editableItems[i]['discount_pct'] = selected.discountPct;
                        final qty = (_editableItems[i]['quantity'] as num?)?.toDouble() ?? 0;
                        final gross = qty * selected.rate;
                        final discount = gross * selected.discountPct / 100;
                        _editableItems[i]['amount'] = gross - discount;
                      }
                    });
                    _notifyEditState();
                  },
                  onItemChanged: _notifyEditState,
                  onDelete: () {
                    setState(() => _editableItems.removeAt(i));
                    _notifyEditState();
                  },
                ),
            ]),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (breakdownEntries.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            'Charges',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: AppPalette.gridHeader,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppPalette.line, width: 1.2),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              children: [
                for (final entry in breakdownEntries)
                  if (_isEditing)
                    _SheetEditableRow(
                      label: entry['ledger_name'] as String? ?? '—',
                      initial: (entry['amount'] as num?)?.toDouble().abs() ?? 0,
                      isPercent: inventoryLedgerName != null &&
                          entry['ledger_name'] != inventoryLedgerName,
                      onChanged: (v) => entry['amount'] = v,
                    )
                  else
                    _SheetHeaderRow(
                      entry['ledger_name'] as String? ?? '—',
                      _chargeValue(entry, inventoryLedgerName),
                    ),
                if (_isEditing)
                  _SheetEditableRow(
                    label: 'Discount',
                    initial: discount,
                    onChanged: (v) => _editableDiscount = v,
                  )
                else
                  _SheetHeaderRow('Discount', formatCurrency(discount)),
                const Divider(height: 16),
                if (_isEditing)
                  _SheetEditableRow(
                    label: 'Total',
                    initial: total,
                    bold: true,
                    onChanged: (v) => _editableTotal = v,
                  )
                else
                  _SheetHeaderRow('Total', formatCurrency(total), bold: true),
              ],
            ),
          ),
        ],
      ],
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
  const _SheetHeaderRow(this.label, this.value, {this.bold = false});
  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppPalette.muted)),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                    color: bold ? AppPalette.ink : AppPalette.inkSoft,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

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

/// Compact right-aligned numeric field used for the editable Qty/Disc/Rate/
/// Amount cells in the items table. Mutates via [onChanged]; uses an
/// uncontrolled [initialValue] so the cursor isn't reset between keystrokes.
class _EditableNumCell extends StatelessWidget {
  const _EditableNumCell({
    super.key,
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
  Widget build(BuildContext context) {
    final text = initial % 1 == 0 ? initial.toInt().toString() : initial.toString();
    return SizedBox(
      width: width,
      child: TextFormField(
        initialValue: text,
        textAlign: TextAlign.right,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppPalette.ink,
              fontWeight: FontWeight.w600,
            ),
        decoration: InputDecoration(
          isDense: true,
          suffixText: suffix,
          suffixStyle: const TextStyle(fontSize: 10, color: AppPalette.muted),
          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          // Unfocused cells get a dull border; the focused cell pops with a
          // bold dark border so the box being edited is obvious.
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: AppPalette.line.withValues(alpha: 0.3), width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppPalette.ink, width: 1.8),
          ),
        ),
        onChanged: (v) {
          final parsed = double.tryParse(v.trim());
          if (parsed != null) onChanged(parsed);
        },
      ),
    );
  }
}

/// Editable variant of [_SheetHeaderRow] for the Charges block (ledger rows,
/// Discount, Total). Shows a ₹ or % affix to match the read-only display.
class _SheetEditableRow extends StatelessWidget {
  const _SheetEditableRow({
    required this.label,
    required this.initial,
    required this.onChanged,
    this.isPercent = false,
    this.bold = false,
  });
  final String label;
  final double initial;
  final ValueChanged<double> onChanged;
  final bool isPercent;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final text = initial % 1 == 0 ? initial.toInt().toString() : initial.toString();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppPalette.muted)),
          ),
          Expanded(
            child: TextFormField(
              initialValue: text,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                    color: AppPalette.ink,
                  ),
              decoration: InputDecoration(
                isDense: true,
                prefixText: isPercent ? null : '₹',
                suffixText: isPercent ? '%' : null,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: AppPalette.line.withValues(alpha: 0.3), width: 1),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppPalette.ink, width: 1.8),
                ),
              ),
              onChanged: (v) {
                final parsed = double.tryParse(v.trim());
                if (parsed != null) onChanged(parsed);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetItemRow extends StatelessWidget {
  const _SheetItemRow({
    required this.item,
    this.source,
    this.score,
    this.isEditing = false,
    this.isEdited = false,
    this.onStockItemSelected,
    this.onItemChanged,
    this.onDelete,
    this.partyName,
    this.isSale = false,
  });
  final Map<String, dynamic> item;
  final String? source;
  final String? score;
  final bool isEditing;
  final bool isEdited;
  final void Function(StockItem)? onStockItemSelected;
  final String? partyName;
  final bool isSale;
  // Called after a numeric field (Qty/Disc/Rate/Amount) is typed so the parent
  // can persist the edited snapshot. The item map is mutated in place.
  final VoidCallback? onItemChanged;
  final VoidCallback? onDelete;

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
    // purchase response instead gives a rupee `discount` per item, so derive
    // the percentage from discount/amount. Round to drop float noise (3.0000…).
    final discPct = (item['discount_pct'] as num?)?.toDouble();
    final discAmt = (item['discount'] as num?)?.toDouble();
    final discValue = discPct ??
        ((discAmt != null && amount != 0) ? discAmt / amount * 100 : 0.0);
    final disc = double.parse(discValue.toStringAsFixed(2));

    final isPurchaseMatching = source == 'Purchase_Matching';
    final isAlgorithm = source == 'Matching_Algorithem';
    final scoreVal = _parseScore(score);

    Color nameColor;
    String? statusLabel;

    if (isPurchaseMatching) {
      nameColor = AppPalette.muted;
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
      nameColor = const Color(0xFF7C3AED);
      statusLabel = 'Item Edited';
    }

    return Container(
      decoration: BoxDecoration(border: Border(top: BorderSide(color: AppPalette.line.withValues(alpha: 0.6)))),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: _kItemColW,
            child: isEditing
                      ? GestureDetector(
                          onTap: () async {
                            String? warnMessage;
                            if (isPurchaseMatching) {
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
                              ),
                            );
                            if (selected != null) onStockItemSelected?.call(selected);
                          },
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      name,
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                            color: nameColor,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ),
                                  const Icon(Icons.arrow_drop_down, size: 18, color: AppPalette.muted),
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
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: nameColor,
                                    fontWeight: FontWeight.w600,
                                  ),
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
              ? _EditableNumCell(
                  width: _kQtyColW,
                  initial: qty,
                  suffix: unit.isNotEmpty ? unit : null,
                  onChanged: (v) {
                    item[item.containsKey('qty') ? 'qty' : 'quantity'] = v;
                    onItemChanged?.call();
                  },
                )
              : SizedBox(
                  width: _kQtyColW,
                  child: Text(
                    '${qty % 1 == 0 ? qty.toInt() : qty} $unit'.trim(),
                    textAlign: TextAlign.right,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppPalette.inkSoft),
                  ),
                ),
          isEditing
              ? _EditableNumCell(
                  key: ValueKey('disc_$disc'),
                  width: _kDiscColW,
                  initial: disc,
                  suffix: '%',
                  onChanged: (v) {
                    item['discount_pct'] = v;
                    onItemChanged?.call();
                  },
                )
              : SizedBox(
                  width: _kDiscColW,
                  child: Text('${disc % 1 == 0 ? disc.toInt() : disc}%', textAlign: TextAlign.right, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppPalette.inkSoft)),
                ),
          isEditing
              ? _EditableNumCell(
                  // Re-key on value so picking a stock item (which updates rate
                  // via setState) refreshes the field instead of showing stale.
                  key: ValueKey('rate_$rate'),
                  width: _kRateColW,
                  initial: rate,
                  onChanged: (v) {
                    item['rate'] = v;
                    onItemChanged?.call();
                  },
                )
              : SizedBox(
                  width: _kRateColW,
                  child: Text(formatCurrency(rate), textAlign: TextAlign.right, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppPalette.inkSoft)),
                ),
          isEditing
              ? _EditableNumCell(
                  key: ValueKey('amount_$amount'),
                  width: _kAmountColW,
                  initial: amount,
                  onChanged: (v) {
                    item['amount'] = v;
                    onItemChanged?.call();
                  },
                )
              : SizedBox(
                  width: _kAmountColW,
                  child: Text(formatCurrency(amount), textAlign: TextAlign.right, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: AppPalette.inkSoft)),
                ),
          SizedBox(
            width: _kDeleteColW,
            child: GestureDetector(
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

// ── Customer picker sheet (sale party name) ───────────────────────────────────

class _CustomerPickerSheet extends StatefulWidget {
  const _CustomerPickerSheet();

  @override
  State<_CustomerPickerSheet> createState() => _CustomerPickerSheetState();
}

class _CustomerPickerSheetState extends State<_CustomerPickerSheet> {
  final _controller = TextEditingController();
  late List<Customer> _filtered;

  @override
  void initState() {
    super.initState();
    _filtered = CustomersCache.instance.items;
    _controller.addListener(_onSearch);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onSearch() {
    final query = _controller.text.toLowerCase();
    setState(() {
      _filtered = query.isEmpty
          ? CustomersCache.instance.items
          : CustomersCache.instance.items
              .where((c) => c.name.toLowerCase().contains(query))
              .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.72,
      decoration: const BoxDecoration(
        color: AppPalette.sheet,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(color: AppPalette.line, borderRadius: BorderRadius.circular(99)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: TextField(
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Search customers…',
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
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: _filtered.length,
              separatorBuilder: (_, idx) => Divider(height: 1, color: AppPalette.line.withValues(alpha: 0.5)),
              itemBuilder: (ctx, i) {
                final c = _filtered[i];
                return InkWell(
                  onTap: () => Navigator.of(context).pop(c),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Text(c.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
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

// ── Stock item picker sheet ───────────────────────────────────────────────────

class _StockItemPickerSheet extends StatefulWidget {
  const _StockItemPickerSheet({this.changingFrom, this.partyName, this.isSale = false});
  final String? changingFrom;
  final String? partyName;
  final bool isSale;

  @override
  State<_StockItemPickerSheet> createState() => _StockItemPickerSheetState();
}

class _StockItemPickerSheetState extends State<_StockItemPickerSheet> {
  final _controller = TextEditingController();
  List<StockItem> _allItems = [];
  List<StockItem> _filtered = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onSearch);
    if (widget.isSale && widget.partyName != null) {
      _fetchSaleItems();
    } else {
      _allItems = StockItemsCache.instance.items;
      _filtered = _allItems;
    }
  }

  Future<void> _fetchSaleItems() async {
    setState(() => _loading = true);
    try {
      final response = await Supabase.instance.client
          .rpc('get_sale_items_for_party', params: {'p_party_name': widget.partyName});
      final items = (response as List)
          .cast<Map<String, dynamic>>()
          .map(StockItem.fromSaleRow)
          .toList();
      if (!mounted) return;
      setState(() {
        _allItems = items;
        _filtered = items;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _allItems = StockItemsCache.instance.items;
        _filtered = _allItems;
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onSearch() {
    final query = _controller.text.toLowerCase();
    setState(() {
      _filtered = query.isEmpty
          ? _allItems
          : _allItems.where((s) => s.name.toLowerCase().contains(query)).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.72,
      decoration: const BoxDecoration(
        color: AppPalette.sheet,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(color: AppPalette.line, borderRadius: BorderRadius.circular(99)),
          ),
          if (widget.changingFrom != null) ...[
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
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
                ],
              ),
            ),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
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
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: _filtered.length,
                    separatorBuilder: (_, i2) => Divider(height: 1, color: AppPalette.line.withValues(alpha: 0.5)),
                    itemBuilder: (ctx, i) {
                      final s = _filtered[i];
                      return InkWell(
                        onTap: () => Navigator.of(context).pop(s),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(s.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                    if (s.groupName.isNotEmpty)
                                      Text(s.groupName, style: const TextStyle(fontSize: 11, color: AppPalette.muted)),
                                  ],
                                ),
                              ),
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

class _PushConfirmDialog extends StatelessWidget {
  const _PushConfirmDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
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
                      side: const BorderSide(color: AppPalette.line, width: 1.4),
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

// ── Discard confirmation dialog ───────────────────────────────────────────────

class _DiscardConfirmDialog extends StatelessWidget {
  const _DiscardConfirmDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Are you sure you want to discard this invoice?',
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
                      side: const BorderSide(color: AppPalette.line, width: 1.4),
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
                    child: const Text('Discard'),
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
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
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
