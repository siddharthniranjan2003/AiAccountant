import 'package:flutter/material.dart';

import '../core/palette.dart';
import '../core/utils.dart';
import '../data/customers_cache.dart';

/// Party picker bottom sheet (sale customers / purchase vendors). Shows a
/// search field over [items] and pops the tapped [Customer].
class CustomerPickerSheet extends StatefulWidget {
  const CustomerPickerSheet({
    super.key,
    required this.items,
    required this.searchHint,
  });
  final List<Customer> items;
  final String searchHint;

  @override
  State<CustomerPickerSheet> createState() => _CustomerPickerSheetState();
}

class _CustomerPickerSheetState extends State<CustomerPickerSheet> {
  final _controller = TextEditingController();
  late List<Customer> _filtered;

  @override
  void initState() {
    super.initState();
    _filtered = widget.items;
    _controller.addListener(_onSearch);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onSearch() {
    // Space-insensitive: "haryanahw" matches "HARYANA H/W & MILL STORE".
    final query = searchKey(_controller.text);
    setState(() {
      _filtered = query.isEmpty
          ? widget.items
          : widget.items
              .where((c) => searchKey(c.name).contains(query))
              .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.72,
      decoration: BoxDecoration(
        color: AppPalette.sheet,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(color: AppPalette.line, borderRadius: BorderRadius.circular(99)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: TextField(
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(
                hintText: widget.searchHint,
                hintStyle: const TextStyle(fontSize: 13),
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: _controller.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        onPressed: _controller.clear,
                      )
                    : null,
                filled: true,
                fillColor: AppPalette.gridHeader,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                isDense: true,
              ),
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: _filtered.length,
              separatorBuilder: (_, idx) => Divider(height: 1, color: AppPalette.line.withValues(alpha: 0.5)),
              itemBuilder: (ctx, i) {
                final c = _filtered[i];
                return InkWell(
                  onTap: () => Navigator.of(context).pop(c),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Text(c.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
