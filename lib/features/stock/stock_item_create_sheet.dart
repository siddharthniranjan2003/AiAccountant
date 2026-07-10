import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config.dart';
import '../../core/palette.dart';
import '../../data/stock_items_cache.dart';
import '../../services/api_client.dart';

/// Opens the create-stock-item bottom sheet. Returns the created [StockItem]
/// once TallyPrime confirms the create, or null if the user cancelled / the
/// push failed / the desktop stayed offline.
Future<StockItem?> showStockItemCreateSheet(
  BuildContext context, {
  String? initialName,
}) {
  return showModalBottomSheet<StockItem>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => StockItemCreateSheet(initialName: initialName),
  );
}

/// Creates a new stock item in TallyPrime through the existing push pipeline:
/// enqueue a push_queue job (voucher_payload.kind = "stock_item") via the
/// backend, activate it, then await the terminal pushed/failed status over the
/// same per-row realtime channel the voucher push uses. On success the item is
/// optimistically added to [StockItemsCache] so pickers and the pre-push
/// validation see it before the next Tally→cloud sync.
class StockItemCreateSheet extends StatefulWidget {
  const StockItemCreateSheet({super.key, this.initialName});

  final String? initialName;

  @override
  State<StockItemCreateSheet> createState() => _StockItemCreateSheetState();
}

class _StockItemCreateSheetState extends State<StockItemCreateSheet> {
  static const _gstRates = [5, 12, 18, 28];
  // How long to wait for the desktop poller (5s interval + push + ack) before
  // telling the user the item is queued but unconfirmed.
  static const _resultTimeout = Duration(seconds: 45);

  // Tally sorts item names by character code, so a lowercase name lands after
  // every uppercase one instead of among its alphabetical neighbours (typing
  // "t" in Tally's item list would never reach it). The whole catalog is
  // uppercase, so keep new items uppercase too — enforced on the initial value
  // and on every keystroke, so what the user sees is what Tally stores.
  static final _upperCase = TextInputFormatter.withFunction(
    (_, newValue) => newValue.copyWith(text: newValue.text.toUpperCase()),
  );

  late final TextEditingController _nameController =
      TextEditingController(text: (widget.initialName ?? '').toUpperCase());
  final _hsnController = TextEditingController();
  final _openingController = TextEditingController(text: '0');

  String _stockGroup = '';
  String _unit = 'NOS';
  bool _gstApplicable = true;
  int _gstRate = 18;

  bool _submitting = false;
  String? _error;

  RealtimeChannel? _channel;
  Completer<Map<String, dynamic>>? _result;

  @override
  void dispose() {
    _nameController.dispose();
    _hsnController.dispose();
    _openingController.dispose();
    _channel?.unsubscribe();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim().toUpperCase();
    if (name.isEmpty) {
      setState(() => _error = 'Item name is required');
      return;
    }
    if (StockItemsCache.instance.exists(name)) {
      setState(() => _error = 'An item with this name already exists');
      return;
    }
    final opening = double.tryParse(_openingController.text.trim().isEmpty
        ? '0'
        : _openingController.text.trim());
    if (opening == null || opening < 0) {
      setState(() => _error = 'Opening stock must be a non-negative number');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    final payload = <String, dynamic>{
      'kind': 'stock_item',
      'name': name,
      if (_stockGroup.isNotEmpty) 'stock_group': _stockGroup,
      'unit': _unit,
      'gst_applicable': _gstApplicable,
      if (_gstApplicable) 'gst_rate': _gstRate,
      if (_gstApplicable && _hsnController.text.trim().isNotEmpty)
        'hsn_code': _hsnController.text.trim(),
      'opening_qty': opening,
    };

    final requestId = ApiClient.newRequestId();
    final headers = {
      'Content-Type': 'application/json',
      'x-api-key': Config.activateApiKey,
      'x-request-id': requestId,
    };

    try {
      // 1. Enqueue (status pending). Company resolved server-side by name,
      //    the same way the parsing service enqueues scanned invoices.
      final enqueueRes = await ApiClient.client.post(
        Uri.parse(Config.pushQueueUrl).replace(
          queryParameters: {'company_name': Config.tallyCompanyName},
        ),
        headers: headers,
        body: jsonEncode({'voucher_payload': payload}),
      );
      if (enqueueRes.statusCode < 200 || enqueueRes.statusCode >= 300) {
        ApiClient.reportFailure('POST', '/api/sync/push-queue', requestId,
            status: enqueueRes.statusCode, body: enqueueRes.body);
        throw Exception('Enqueue failed (${enqueueRes.statusCode}): ${enqueueRes.body}');
      }
      final jobId =
          ((jsonDecode(enqueueRes.body) as Map)['job'] as Map?)?['id'] as String?;
      if (jobId == null || jobId.isEmpty) {
        throw Exception('Enqueue returned no job id');
      }

      // 2. Subscribe BEFORE activating so the terminal update can't be missed.
      _result = Completer<Map<String, dynamic>>();
      _channel = Supabase.instance.client
          .channel('stock_item_create_$jobId')
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'push_queue',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'id',
              value: jobId,
            ),
            callback: (change) {
              final rec = change.newRecord;
              final status = rec['status'] as String? ?? '';
              if ((status == 'pushed' || status == 'failed') &&
                  !(_result?.isCompleted ?? true)) {
                _result?.complete(rec);
              }
            },
          )
          .subscribe();

      // 3. Activate (pending → push_now); the desktop poller picks it up.
      final activateRes = await ApiClient.client.post(
        Uri.parse(Config.activateUrl),
        headers: headers,
        body: jsonEncode({'job_id': jobId}),
      );
      if (activateRes.statusCode < 200 || activateRes.statusCode >= 300) {
        ApiClient.reportFailure(
            'POST', '/api/sync/push-queue/activate', requestId,
            status: activateRes.statusCode, body: activateRes.body);
        throw Exception(
            'Activate failed (${activateRes.statusCode}): ${activateRes.body}');
      }

      // 4. Await the Tally result. Realtime UPDATE echoes can omit unchanged
      //    TOASTed jsonb columns, but status/error_message are plain columns and
      //    always present.
      final Map<String, dynamic> rec;
      try {
        rec = await _result!.future.timeout(_resultTimeout);
      } on TimeoutException {
        if (!mounted) return;
        setState(() {
          _submitting = false;
          _error =
              'Queued, but no confirmation from TallyBridge desktop yet — it may '
              'be offline. The item will be created when it reconnects.';
        });
        return;
      }
      if (!mounted) return;

      if (rec['status'] == 'pushed') {
        final created = StockItem(
          name: name,
          groupName: _stockGroup,
          rate: 0,
          unit: _unit,
        );
        StockItemsCache.instance.addLocal(created);
        // Confirm the create before closing, so the user sees which item landed
        // in Tally. Shown over the still-open sheet; the sheet closes on OK.
        await showDialog<void>(
          context: context,
          builder: (_) => _StockItemCreatedDialog(name: name),
        );
        if (!mounted) return;
        Navigator.of(context).pop(created);
      } else {
        final msg = (rec['error_message'] as String?)?.trim();
        setState(() {
          _submitting = false;
          _error = (msg == null || msg.isEmpty)
              ? 'TallyPrime rejected the item.'
              : msg;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = '$e';
      });
    } finally {
      _channel?.unsubscribe();
      _channel = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cache = StockItemsCache.instance;
    final groups = cache.groupNames();
    final units = cache.unitNames();
    if (!units.contains('NOS')) units.insert(0, 'NOS');

    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: BoxDecoration(
        color: AppPalette.sheet,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppPalette.line,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Create Stock Item',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                'Created directly in TallyPrime',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppPalette.muted),
              ),
              const SizedBox(height: 20),
              _label('Item name'),
              TextField(
                controller: _nameController,
                enabled: !_submitting,
                decoration: _fieldDecoration('e.g. BOSCH GWS 800 GRINDER'),
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [_upperCase],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _label('Stock group'),
                        DropdownButtonFormField<String>(
                          initialValue: _stockGroup.isEmpty ? null : _stockGroup,
                          isExpanded: true,
                          decoration: _fieldDecoration('Primary'),
                          hint: const Text('Primary',
                              style: TextStyle(fontSize: 13)),
                          items: [
                            const DropdownMenuItem(
                              value: '',
                              child: Text('Primary (no group)',
                                  style: TextStyle(fontSize: 13)),
                            ),
                            for (final g in groups)
                              DropdownMenuItem(
                                value: g,
                                child: Text(g,
                                    style: const TextStyle(fontSize: 13),
                                    overflow: TextOverflow.ellipsis),
                              ),
                          ],
                          onChanged: _submitting
                              ? null
                              : (v) => setState(() => _stockGroup = v ?? ''),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _label('Unit'),
                        DropdownButtonFormField<String>(
                          initialValue: units.contains(_unit) ? _unit : 'NOS',
                          isExpanded: true,
                          decoration: _fieldDecoration('NOS'),
                          items: [
                            for (final u in units)
                              DropdownMenuItem(
                                value: u,
                                child: Text(u,
                                    style: const TextStyle(fontSize: 13)),
                              ),
                          ],
                          onChanged: _submitting
                              ? null
                              : (v) => setState(() => _unit = v ?? 'NOS'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SwitchListTile(
                value: _gstApplicable,
                onChanged: _submitting
                    ? null
                    : (v) => setState(() => _gstApplicable = v),
                title: const Text('GST applicable',
                    style:
                        TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
              if (_gstApplicable) ...[
                const SizedBox(height: 6),
                _label('GST rate'),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final rate in _gstRates)
                      ChoiceChip(
                        label: Text('$rate%'),
                        selected: _gstRate == rate,
                        onSelected: _submitting
                            ? null
                            : (_) => setState(() => _gstRate = rate),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                _label('HSN code (optional)'),
                TextField(
                  controller: _hsnController,
                  enabled: !_submitting,
                  keyboardType: TextInputType.number,
                  decoration: _fieldDecoration('e.g. 82055990'),
                ),
              ],
              const SizedBox(height: 14),
              _label('Opening stock'),
              TextField(
                controller: _openingController,
                enabled: !_submitting,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: _fieldDecoration('0'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(
                  _error!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFFDC2626),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _submitting ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: AppPalette.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  textStyle: const TextStyle(fontWeight: FontWeight.w700),
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text('Create in Tally'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppPalette.muted,
          ),
        ),
      );

  InputDecoration _fieldDecoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 13),
        filled: true,
        fillColor: AppPalette.gridHeader,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        isDense: true,
      );
}

// Success confirmation shown once TallyPrime reports the item created. Mirrors
// the green-tick "Pushed to Tally" dialog used after a voucher push.
class _StockItemCreatedDialog extends StatelessWidget {
  const _StockItemCreatedDialog({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.check_circle_rounded,
                  size: 48, color: Color(0xFF16A34A)),
              const SizedBox(height: 16),
              Text(
                'Stock Item Created',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 12),
              Text(
                '"$name" has been created in TallyPrime.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppPalette.muted,
                      height: 1.4,
                    ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF16A34A),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  textStyle: const TextStyle(fontWeight: FontWeight.w700),
                ),
                child: const Text('OK'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
