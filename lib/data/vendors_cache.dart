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
      final response = await Supabase.instance.client
          .from('ledgers')
          .select('name, group_name, state')
          .eq('group_name', 'Sundry Creditors');
      items = (response as List)
          .cast<Map<String, dynamic>>()
          .map(Customer.fromRow)
          .toList();
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
