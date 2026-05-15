import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/palette.dart';
import '../../core/utils.dart';

class VoucherDetailSheet extends StatefulWidget {
  const VoucherDetailSheet({super.key, required this.payload});

  final Map<String, dynamic> payload;

  @override
  State<VoucherDetailSheet> createState() => _VoucherDetailSheetState();
}

class _VoucherDetailSheetState extends State<VoucherDetailSheet> {
  late String _status;
  bool _isSubmitting = false;
  RealtimeChannel? _channel;

  static const _activateUrl =
      'https://magnolia-universe-specimen.ngrok-free.dev/api/sync/push-queue/activate';
  static const _apiKey = 'sb_publishable_c2Cov2CT8hxOd1FFEo_yaA_6nEt8_Nl';

  @override
  void initState() {
    super.initState();
    _status = widget.payload['__status'] as String? ?? 'pending';
    final rowId = widget.payload['__row_id'] as String? ?? '';
    if (rowId.isNotEmpty) _subscribeToStatus(rowId);
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  Future<void> _activate() async {
    final rowId = widget.payload['__row_id'] as String? ?? '';
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
    final payload = widget.payload;
    final partyName = payload['party_name'] as String? ?? '—';
    final voucherNumber = payload['voucher_number'] as String? ?? '—';
    final date = payload['date'] as String? ?? '—';
    final narration = payload['narration'] as String?;
    final reference = payload['reference'] as String?;

    final items = (payload['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final ledgerEntries =
        (payload['ledger_entries'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    final partyEntry = ledgerEntries.isNotEmpty
        ? ledgerEntries.reduce((a, b) =>
            ((a['amount'] as num).abs() >= (b['amount'] as num).abs() ? a : b))
        : null;
    final total = (partyEntry?['amount'] as num?)?.toDouble().abs() ?? 0.0;
    final breakdownEntries =
        partyEntry == null ? ledgerEntries : ledgerEntries.where((e) => e != partyEntry).toList();

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
                      Text(
                        partyName,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        '$voucherNumber · $date',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppPalette.muted),
                      ),
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
                      FilledButton(
                        onPressed: _isSubmitting ? null : _activate,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFBBF7D0),
                          foregroundColor: const Color(0xFF166534),
                          disabledBackgroundColor: const Color(0xFFBBF7D0).withValues(alpha: 0.5),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                        ),
                        child: _isSubmitting
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF166534)),
                              )
                            : const Text('Done'),
                      ),
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
          Expanded(
            child: ListView(
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
                  Text('Items', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  Container(
                    decoration: BoxDecoration(
                      color: AppPalette.gridHeader,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                      border: Border.all(color: AppPalette.line, width: 1.2),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: const Row(
                      children: [
                        Expanded(flex: 5, child: Text('Item', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12))),
                        _SheetColHeader('Qty', flex: 2),
                        _SheetColHeader('Rate', flex: 3),
                        _SheetColHeader('Amount', flex: 3),
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
                    child: Column(children: [for (final item in items) _SheetItemRow(item: item)]),
                  ),
                ],
                if (breakdownEntries.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text('Charges', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
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
                          _SheetHeaderRow(
                            entry['ledger_name'] as String? ?? '—',
                            formatCurrency((entry['amount'] as num?)?.toDouble().abs() ?? 0),
                          ),
                        const Divider(height: 16),
                        _SheetHeaderRow('Total', formatCurrency(total), bold: true),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
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
  const _SheetColHeader(this.label, {required this.flex});
  final String label;
  final int flex;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(label, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
    );
  }
}

class _SheetItemRow extends StatelessWidget {
  const _SheetItemRow({required this.item});
  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final name = item['stock_item_name'] as String? ?? '—';
    final qty = (item['quantity'] as num?)?.toDouble() ?? 0;
    final rate = (item['rate'] as num?)?.toDouble() ?? 0;
    final amount = (item['amount'] as num?)?.toDouble() ?? 0;
    final unit = item['unit'] as String? ?? '';

    return Container(
      decoration: BoxDecoration(border: Border(top: BorderSide(color: AppPalette.line.withValues(alpha: 0.6)))),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Text(name, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppPalette.pen, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '${qty % 1 == 0 ? qty.toInt() : qty} $unit'.trim(),
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppPalette.inkSoft),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(formatCurrency(rate), textAlign: TextAlign.right, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppPalette.inkSoft)),
          ),
          Expanded(
            flex: 3,
            child: Text(formatCurrency(amount), textAlign: TextAlign.right, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: AppPalette.inkSoft)),
          ),
        ],
      ),
    );
  }
}
