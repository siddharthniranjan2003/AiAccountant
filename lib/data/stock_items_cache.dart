import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class StockItem {
  const StockItem({
    required this.name,
    required this.groupName,
    required this.rate,
    this.discountPct = 0.0,
    this.source = '',
  });

  final String name;
  final String groupName;
  final double rate;
  final double discountPct;
  // 'same_party' | 'different_party' | '' (catalog)
  final String source;

  static StockItem fromRow(Map<String, dynamic> row) => StockItem(
        name: row['name'] as String? ?? '',
        groupName: row['group_name'] as String? ?? '',
        rate: double.tryParse((row['rate'] ?? '0').toString()) ?? 0.0,
      );

  static StockItem fromSaleRow(Map<String, dynamic> row) => StockItem(
        name: row['stock_item_name'] as String? ?? '',
        groupName: row['source'] == 'different_party' ? 'Other vendors' : '',
        rate: (row['rate'] as num?)?.toDouble() ?? 0.0,
        discountPct: (row['discount_pct'] as num?)?.toDouble() ?? 0.0,
        source: row['source'] as String? ?? '',
      );
}

class StockItemsCache {
  StockItemsCache._();
  static final StockItemsCache instance = StockItemsCache._();

  List<StockItem> items = [];
  bool isLoading = false;

  static GlobalKey<ScaffoldMessengerState>? scaffoldKey;

  Future<void> fetch() async {
    isLoading = true;
    try {
      final response = await Supabase.instance.client
          .from('stock_items')
          .select('name, group_name, rate');
      items = (response as List)
          .cast<Map<String, dynamic>>()
          .map(StockItem.fromRow)
          .toList();
    } catch (e) {
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
