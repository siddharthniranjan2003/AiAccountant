import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/error_reporter.dart';

class Customer {
  const Customer({
    required this.name,
    required this.groupName,
    required this.state,
  });

  final String name;
  final String groupName;
  final String state;

  static Customer fromRow(Map<String, dynamic> row) => Customer(
        name: row['name'] as String? ?? '',
        groupName: row['group_name'] as String? ?? '',
        state: row['state'] as String? ?? '',
      );
}

class CustomersCache {
  CustomersCache._();
  static final CustomersCache instance = CustomersCache._();

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
      // PostgREST caps a single select at 1000 rows; Sundry Debtors can exceed
      // that, so page through with range() until a short page comes back.
      const pageSize = 1000;
      final rows = <Map<String, dynamic>>[];
      var from = 0;
      while (true) {
        final page = await Supabase.instance.client
            .from('ledgers')
            .select('name, group_name, state')
            .eq('group_name', 'Sundry Debtors')
            .order('name')
            .range(from, from + pageSize - 1);
        final batch = (page as List).cast<Map<String, dynamic>>();
        rows.addAll(batch);
        if (batch.length < pageSize) break;
        from += pageSize;
      }
      items = rows.map(Customer.fromRow).toList();
    } catch (e, st) {
      reportHandledError('supabase.customers.fetch', e, stackTrace: st);
      scaffoldKey?.currentState?.showSnackBar(
        SnackBar(
          content: Text('Customer list download failed: $e'),
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      isLoading = false;
    }
  }
}
