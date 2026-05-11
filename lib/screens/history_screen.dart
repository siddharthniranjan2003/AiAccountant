import 'package:flutter/material.dart';
import '../core/models.dart';
import '../core/seed_data.dart';
import '../widgets/screen_frame.dart';
import '../widgets/app_top_tabs.dart';
import '../widgets/history_card.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({
    super.key,
    required this.currentIndex,
    required this.onNavSelected,
  });

  final int currentIndex;
  final ValueChanged<int> onNavSelected;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  int _filterIndex = 0;

  @override
  Widget build(BuildContext context) {
    final visibleItems = switch (_filterIndex) {
      0 => seedHistoryEntries,
      1 => seedHistoryEntries
          .where((entry) => entry.type == TransactionType.sale)
          .toList(),
      _ => seedHistoryEntries
          .where((entry) => entry.type == TransactionType.purchase)
          .toList(),
    };

    final grouped = <String, List<HistoryEntry>>{};
    for (final entry in visibleItems) {
      grouped
          .putIfAbsent(entry.monthLabel, () => <HistoryEntry>[])
          .add(entry);
    }

    return ScreenFrame(
      currentIndex: widget.currentIndex,
      onNavSelected: widget.onNavSelected,
      body: Column(
        children: [
          AppTopTabs(
            labels: const ['All', 'Sale', 'Purchase'],
            selectedIndex: _filterIndex,
            onSelected: (index) {
              setState(() {
                _filterIndex = index;
              });
            },
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
              children: [
                for (final group in grouped.entries) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(2, 6, 2, 8),
                    child: Text(
                      group.key,
                      style:
                          Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontStyle: FontStyle.italic,
                                fontWeight: FontWeight.w800,
                              ),
                    ),
                  ),
                  for (final entry in group.value) ...[
                    HistoryCard(entry: entry),
                    const SizedBox(height: 8),
                  ],
                  const SizedBox(height: 4),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
