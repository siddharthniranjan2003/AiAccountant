import 'package:flutter/material.dart';

import '../../core/palette.dart';
import '../../core/utils.dart';

class ScanResultSheet extends StatelessWidget {
  const ScanResultSheet({super.key, required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final header =
        (((data['parsed'] ?? data['ocr']) as Map?) ?? {})['header'] as Map<String, dynamic>? ?? {};
    final vendorName = header['vendor_name'] as String? ?? '—';
    final invoiceNumber = header['invoice_number'] as String? ?? '—';
    final invoiceDate = header['invoice_date'] as String? ?? '—';
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
                        vendorName,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        '$invoiceNumber · $invoiceDate',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppPalette.muted),
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
          Expanded(child: _InvoiceTab(data: data)),
        ],
      ),
    );
  }
}

class _InvoiceTab extends StatelessWidget {
  const _InvoiceTab({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final header =
        (((data['parsed'] ?? data['ocr']) as Map?) ?? {})['header'] as Map<String, dynamic>? ?? {};
    final items = (data['matched_items'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    final vendorName = header['vendor_name'] as String? ?? '—';
    final invoiceNumber = header['invoice_number'] as String? ?? '—';
    final invoiceDate = header['invoice_date'] as String? ?? '—';
    final invoiceTotal = (header['invoice_total'] as num?)?.toDouble() ?? 0.0;
    final discountPct = (header['discount_percent'] as num?)?.toDouble();
    final discountAmt = (header['discount_amount'] as num?)?.toDouble();
    final taxEntries =
        (header['tax_entries'] as List?)?.cast<Map<String, dynamic>>() ?? [];

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
              _HeaderRow('Vendor', vendorName),
              _HeaderRow('Invoice #', invoiceNumber),
              _HeaderRow('Date', invoiceDate),
              if (discountPct != null && discountAmt != null)
                _HeaderRow('Discount', '${discountPct.toStringAsFixed(0)}% · ${formatCurrency(discountAmt)}'),
              for (final tax in taxEntries)
                _HeaderRow(tax['ledger_name'] as String? ?? 'Tax', formatCurrency((tax['amount'] as num?)?.toDouble() ?? 0)),
              _HeaderRow('Total', formatCurrency(invoiceTotal), bold: true),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text('Line Items', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: AppPalette.gridHeader,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            border: Border.all(color: AppPalette.line, width: 1.2),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              const Expanded(flex: 5, child: Text('Item', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12))),
              _ColHeader('Qty', flex: 2),
              _ColHeader('Rate', flex: 3),
              _ColHeader('Amount', flex: 3),
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
          child: Column(children: [for (int i = 0; i < items.length; i++) _ItemRow(item: items[i])]),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              'Total  ${formatCurrency(invoiceTotal)}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800, color: AppPalette.inkSoft),
            ),
          ],
        ),
      ],
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow(this.label, this.value, {this.bold = false});
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

class _ColHeader extends StatelessWidget {
  const _ColHeader(this.label, {required this.flex});
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

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item});
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
          Expanded(flex: 5, child: Text(name, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppPalette.pen, fontWeight: FontWeight.w600))),
          Expanded(flex: 2, child: Text('${qty % 1 == 0 ? qty.toInt() : qty} $unit'.trim(), textAlign: TextAlign.right, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppPalette.inkSoft))),
          Expanded(flex: 3, child: Text(formatCurrency(rate), textAlign: TextAlign.right, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppPalette.inkSoft))),
          Expanded(flex: 3, child: Text(formatCurrency(amount), textAlign: TextAlign.right, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: AppPalette.inkSoft))),
        ],
      ),
    );
  }
}
