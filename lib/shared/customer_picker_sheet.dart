import 'package:flutter/material.dart';

import '../data/customers_cache.dart';
import 'picker_sheet.dart';

/// Party picker bottom sheet (sale customers / purchase vendors). Shows a
/// search field over [items] and pops the tapped [Customer].
///
/// Thin wrapper over the generic [PickerSheet] so the party picker and the state
/// picker share one search/keyboard-navigation implementation.
class CustomerPickerSheet extends StatelessWidget {
  const CustomerPickerSheet({
    super.key,
    required this.items,
    required this.searchHint,
  });
  final List<Customer> items;
  final String searchHint;

  @override
  Widget build(BuildContext context) => PickerSheet<Customer>(
        items: items,
        labelOf: (c) => c.name,
        searchHint: searchHint,
      );
}
