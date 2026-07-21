import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  // Keyboard navigation: index of the highlighted row. Down/Up move it, Enter
  // selects it. Reset to 0 whenever the filtered list changes.
  int _highlighted = 0;
  final Map<int, GlobalKey> _itemKeys = {};

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
      // A new result set invalidates the old highlight position.
      _highlighted = 0;
    });
  }

  void _select(Customer c) => Navigator.of(context).pop(c);

  GlobalKey _keyFor(int i) => _itemKeys.putIfAbsent(i, () => GlobalKey());

  // Moves the highlight by [delta] (clamped) and scrolls it into view. The
  // search field keeps focus so the user can keep typing.
  void _moveHighlight(int delta) {
    if (_filtered.isEmpty) return;
    setState(() {
      _highlighted = (_highlighted + delta).clamp(0, _filtered.length - 1);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _itemKeys[_highlighted]?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx,
            alignment: 0.5, duration: const Duration(milliseconds: 120));
      }
    });
  }

  // Down/Up move the highlight, Enter selects it. Returns handled so these keys
  // don't reach the text field (cursor moves / submit).
  KeyEventResult _onSearchKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      _moveHighlight(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _moveHighlight(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (_filtered.isNotEmpty) {
        _select(_filtered[_highlighted]);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
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
            // Intercepts Down/Up/Enter before the text field handles them, so
            // the user can navigate the list without leaving the search box.
            child: Focus(
              onKeyEvent: _onSearchKey,
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
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: _filtered.length,
              separatorBuilder: (_, idx) => Divider(height: 1, color: AppPalette.line.withValues(alpha: 0.5)),
              itemBuilder: (ctx, i) {
                final c = _filtered[i];
                return InkWell(
                  key: _keyFor(i),
                  onTap: () => _select(c),
                  child: Container(
                    color: i == _highlighted
                        ? AppPalette.ink.withValues(alpha: 0.06)
                        : null,
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
