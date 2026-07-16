import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/error_reporter.dart';
import 'customers_cache.dart';

// Purchase vendors = ledgers in the "Sundry Creditors" group (mirrors
// CustomersCache, which loads "Sundry Debtors" for sale). Reuses the Customer
// model since both are plain ledger rows (name/group_name/state).
class VendorsCache {
  VendorsCache._();
  static final VendorsCache instance = VendorsCache._();

  List<Customer> items = [];
  bool isLoading = false;

  static GlobalKey<ScaffoldMessengerState>? scaffoldKey;

  void clear() {
    items = [];
    isLoading = false;
  }

  Future<void> fetch() async {
    isLoading = true;
    try {
      // PostgREST caps a single select at 1000 rows; page through with range()
      // so large creditor lists load fully (mirrors CustomersCache).
      const pageSize = 1000;
      final rows = <Map<String, dynamic>>[];
      var from = 0;
      while (true) {
        final page = await Supabase.instance.client
            .from('ledgers')
            .select('name, group_name, state')
            .eq('group_name', 'Sundry Creditors')
            .order('name')
            .range(from, from + pageSize - 1);
        final batch = (page as List).cast<Map<String, dynamic>>();
        rows.addAll(batch);
        if (batch.length < pageSize) break;
        from += pageSize;
      }
      items = rows.map(Customer.fromRow).toList();
    } catch (e, st) {
      reportHandledError('supabase.vendors.fetch', e, stackTrace: st);
      scaffoldKey?.currentState?.showSnackBar(
        SnackBar(
          content: Text('Vendor list download failed: $e'),
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      isLoading = false;
    }
  }
}
