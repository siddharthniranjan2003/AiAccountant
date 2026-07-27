import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/palette.dart';
import '../core/utils.dart';

/// Searchable bottom-sheet picker over an arbitrary list. Shows a search field
/// above the rows and pops the tapped item.
///
/// Generic so the same sheet backs the party picker (customers / vendors) and the
/// state picker. [labelOf] supplies both the displayed text and the search text.
class PickerSheet<T> extends StatefulWidget {
  const PickerSheet({
    super.key,
    required this.items,
    required this.labelOf,
    required this.searchHint,
    this.selected,
  });

  final List<T> items;
  final String Function(T) labelOf;
  final String searchHint;

  /// Currently chosen item, marked with a tick and highlighted on open so the
  /// sheet opens on the existing value rather than the top of the list.
  final T? selected;

  @override
  State<PickerSheet<T>> createState() => _PickerSheetState<T>();
}

class _PickerSheetState<T> extends State<PickerSheet<T>> {
  final _controller = TextEditingController();
  late List<T> _filtered;
  // Keyboard navigation: index of the highlighted row. Down/Up move it, Enter
  // selects it. Reset to 0 whenever the filtered list changes.
  int _highlighted = 0;
  final Map<int, GlobalKey> _itemKeys = {};

  @override
  void initState() {
    super.initState();
    _filtered = widget.items;
    // Open on the current value so Enter re-picks it rather than jumping to the
    // alphabetically-first entry.
    if (widget.selected != null) {
      final at = _filtered.indexWhere((e) => e == widget.selected);
      if (at >= 0) _highlighted = at;
    }
    _controller.addListener(_onSearch);
    if (_highlighted > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToHighlight());
    }
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
              .where((e) => searchKey(widget.labelOf(e)).contains(query))
              .toList();
      // A new result set invalidates the old highlight position.
      _highlighted = 0;
    });
  }

  void _select(T item) => Navigator.of(context).pop(item);

  GlobalKey _keyFor(int i) => _itemKeys.putIfAbsent(i, () => GlobalKey());

  void _scrollToHighlight() {
    final ctx = _itemKeys[_highlighted]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx,
          alignment: 0.5, duration: const Duration(milliseconds: 120));
    }
  }

  // Moves the highlight by [delta] (clamped) and scrolls it into view. The
  // search field keeps focus so the user can keep typing.
  void _moveHighlight(int delta) {
    if (_filtered.isEmpty) return;
    setState(() {
      _highlighted = (_highlighted + delta).clamp(0, _filtered.length - 1);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToHighlight());
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
                final item = _filtered[i];
                final isSelected = widget.selected != null && item == widget.selected;
                return InkWell(
                  key: _keyFor(i),
                  onTap: () => _select(item),
                  child: Container(
                    color: i == _highlighted
                        ? AppPalette.ink.withValues(alpha: 0.06)
                        : null,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(widget.labelOf(item),
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        ),
                        if (isSelected)
                          const Icon(Icons.check_rounded, size: 18, color: AppPalette.ink),
                      ],
                    ),
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
