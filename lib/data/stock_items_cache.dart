import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/error_reporter.dart';

class StockItem {
  const StockItem({
    required this.name,
    required this.groupName,
    required this.rate,
    this.unit = '',
    this.discountPct = 0.0,
    this.source = '',
    this.discountSource = '',
    this.partCode = '',
  });

  final String name;
  final String groupName;
  final double rate;
  // Tally base unit (e.g. 'Kgs','Pcs','NOS') from stock_items.unit; '' if unknown.
  final String unit;
  final double discountPct;
  // Where the RATE came from: 'same_party' | 'different_party' | 'none' | ''
  // (catalog, i.e. not yet resolved). Rate is party-agnostic, so 'same_party'
  // here only means the latest sale of the item happened to be to this party.
  final String source;
  // Where the DISCOUNT came from: 'same_party' | 'none' | '' (not yet resolved).
  // Distinct from [source] because the two are independent lookups and normally
  // resolve to different vouchers. Note discountPct 0.0 is ambiguous on its own —
  // 'same_party' means a real 0%, 'none' means this party has no history.
  final String discountSource;
  // Tally Part No. (== Mailing Name) from stock_items.part_code; '' if none.
  final String partCode;

  static StockItem fromRow(Map<String, dynamic> row) => StockItem(
        name: row['name'] as String? ?? '',
        groupName: row['group_name'] as String? ?? '',
        rate: double.tryParse((row['rate'] ?? '0').toString()) ?? 0.0,
        unit: row['unit'] as String? ?? '',
        partCode: row['part_code'] as String? ?? '',
      );
}

class StockItemsCache {
  StockItemsCache._();
  static final StockItemsCache instance = StockItemsCache._();

  List<StockItem> items = [];
  bool isLoading = false;

  static GlobalKey<ScaffoldMessengerState>? scaffoldKey;

  void clear() {
    items = [];
    isLoading = false;
  }

  // Tally base unit for a stock item by name (case-insensitive), '' if unknown.
  // Used to give a manually-added line the stock master's unit instead of 'NOS'.
  String unitFor(String name) {
    final target = name.trim().toLowerCase();
    if (target.isEmpty) return '';
    for (final item in items) {
      if (item.name.trim().toLowerCase() == target) return item.unit;
    }
    return '';
  }

  // True if a stock item with this name exists in the catalog (case-insensitive,
  // trimmed). Used to validate invoice lines before pushing to Tally.
  bool exists(String name) {
    final target = name.trim().toLowerCase();
    if (target.isEmpty) return false;
    for (final item in items) {
      if (item.name.trim().toLowerCase() == target) return true;
    }
    return false;
  }

  // Tally Part No. for a stock item by name (case-insensitive), '' if unknown.
  // Lets the party-specific picker path (sourced from voucher_items, which has
  // no part_code) still show/search the catalog's part code.
  String partCodeFor(String name) {
    final target = name.trim().toLowerCase();
    if (target.isEmpty) return '';
    for (final item in items) {
      if (item.name.trim().toLowerCase() == target) return item.partCode;
    }
    return '';
  }

  // Distinct, sorted stock-group names from the catalog. Tally errors on an
  // unknown PARENT group, so the create-item picker only offers these.
  List<String> groupNames() {
    final names = <String>{};
    for (final item in items) {
      final g = item.groupName.trim();
      if (g.isNotEmpty) names.add(g);
    }
    return names.toList()..sort();
  }

  // Distinct, sorted base units from the catalog (Tally errors on an unknown
  // BASEUNITS, so only existing units are offered).
  List<String> unitNames() {
    final names = <String>{};
    for (final item in items) {
      final u = item.unit.trim();
      if (u.isNotEmpty) names.add(u);
    }
    return names.toList()..sort();
  }

  // Optimistically append a just-created item so pickers and the pre-push
  // validation see it immediately, before the next Tally→cloud sync echoes it
  // into stock_items.
  void addLocal(StockItem item) {
    if (item.name.trim().isEmpty || exists(item.name)) return;
    items = [...items, item];
  }

  Future<void> fetch() async {
    isLoading = true;
    try {
      // PostgREST caps a single response at 1000 rows, so page through the whole
      // catalog (13k+ items) with .range(). Ordered by name for stable, non-
      // overlapping pages. Without this the picker (and unitFor/partCodeFor
      // lookups) only saw the first 1000 items.
      const pageSize = 1000;
      final all = <StockItem>[];
      var from = 0;
      while (true) {
        final page = await Supabase.instance.client
            .from('stock_items')
            .select('name, group_name, rate, unit, part_code')
            .order('name', ascending: true)
            .range(from, from + pageSize - 1);
        final rows = (page as List).cast<Map<String, dynamic>>();
        all.addAll(rows.map(StockItem.fromRow));
        if (rows.length < pageSize) break;
        from += pageSize;
      }
      items = all;
    } catch (e, st) {
      reportHandledError('supabase.stock_items.fetch', e, stackTrace: st);
      scaffoldKey?.currentState?.showSnackBar(
        SnackBar(
          content: Text('download failed $e'),
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      isLoading = false;
    }
  }
}
