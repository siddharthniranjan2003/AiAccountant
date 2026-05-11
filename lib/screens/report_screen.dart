import 'package:flutter/material.dart';
import '../core/models.dart';
import '../core/seed_data.dart';
import '../core/palette.dart';
import '../widgets/screen_frame.dart';
import '../widgets/app_top_tabs.dart';
import '../widgets/report_list_item.dart';
import '../widgets/export_card.dart';
import '../widgets/spreadsheet_sheet.dart';

class ReportScreen extends StatefulWidget {
  const ReportScreen({
    super.key,
    required this.currentIndex,
    required this.onNavSelected,
  });

  final int currentIndex;
  final ValueChanged<int> onNavSelected;

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  int _tabIndex = 0;
  String? _loadingCategoryKey;

  Future<void> _openReport(ReportCategory category) async {
    setState(() {
      _loadingCategoryKey = category.key;
    });

    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;

    setState(() {
      _loadingCategoryKey = null;
    });

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return AppSpreadsheetSheet(
          fileName: '/${category.key}.csv',
          toolbarItems: const ['File', 'Edit', 'View', 'Filter', 'Σ'],
          columnLabels: const [
            'stock_item',
            'sales_6m',
            'pur_1m',
            'stock_qty',
            'stock_₹',
            'scenario',
          ],
          columnWidths: const [42, 220, 88, 88, 96, 96, 140],
          rows: category.rows,
          footerLeading: category.footerMeta,
          footerTrailing: 'Σ ${category.footerSum}',
          trailingAction: OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppPalette.ink,
              side:
                  const BorderSide(color: AppPalette.ink, width: 1.3),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text('Close'),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ScreenFrame(
      currentIndex: widget.currentIndex,
      onNavSelected: widget.onNavSelected,
      body: Column(
        children: [
          AppTopTabs(
            labels: const ['Insights', 'Export'],
            selectedIndex: _tabIndex,
            onSelected: (index) {
              setState(() {
                _tabIndex = index;
              });
            },
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: _tabIndex == 0
                  ? ListView.separated(
                      key: const ValueKey('insights'),
                      padding:
                          const EdgeInsets.fromLTRB(12, 10, 12, 16),
                      itemCount: seedReportCategories.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: 2),
                      itemBuilder: (context, index) {
                        final category = seedReportCategories[index];
                        return ReportListItem(
                          category: category,
                          isLoading:
                              _loadingCategoryKey == category.key,
                          onTap: () => _openReport(category),
                        );
                      },
                    )
                  : ListView(
                      key: const ValueKey('exports'),
                      padding:
                          const EdgeInsets.fromLTRB(12, 12, 12, 16),
                      children: const [
                        ExportCard(
                          title: 'Monthly CSV pack',
                          subtitle:
                              'Bundle sales, purchases, and inventory deltas for a clean handoff to finance.',
                          icon: Icons.file_open_outlined,
                        ),
                        SizedBox(height: 10),
                        ExportCard(
                          title: 'GST workbook',
                          subtitle:
                              'Ready-to-review tax summary laid out as a workbook with filing checkpoints.',
                          icon: Icons.receipt_long_outlined,
                        ),
                        SizedBox(height: 10),
                        ExportCard(
                          title: 'Ledger snapshot',
                          subtitle:
                              'Structured export for external accountants and reconciliation workflows.',
                          icon: Icons.table_chart_outlined,
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
