import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  Future<void> fetch() async {
    isLoading = true;
    try {
      final response = await Supabase.instance.client
          .from('ledgers')
          .select('name, group_name, state')
          .eq('group_name', 'Sundry Debtors');
      items = (response as List)
          .cast<Map<String, dynamic>>()
          .map(Customer.fromRow)
          .toList();
    } catch (e) {
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
