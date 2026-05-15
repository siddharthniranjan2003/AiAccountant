import 'dart:io';
import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../core/models.dart';
import '../core/seed_data.dart';
import '../core/palette.dart';
import '../services/api_client.dart';
import '../widgets/screen_frame.dart';
import '../widgets/app_top_tabs.dart';
import '../widgets/report_list_item.dart';
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

  Future<File> _cacheFile(String reportId) async {
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory('${dir.path}/reports');
    if (!await folder.exists()) await folder.create();
    return File('${folder.path}/$reportId.csv');
  }

  Future<void> _openReport(ReportCategory category) async {
    setState(() => _loadingCategoryKey = category.key);

    List<List<String>> rows;
    List<String> columnLabels;
    List<double> columnWidths;
    String footerTrailing;

    try {
      if (category.reportId != null) {
        final file = await _cacheFile(category.reportId!);
        final String csvText;

        if (await file.exists()) {
          csvText = await file.readAsString();
        } else {
          csvText = await ApiClient.getRaw(
            '/api/sync/reorder-levels/${category.reportId}',
            query: {
              'company_name': 'K V ENTERPRISES',
              'format': 'csv',
            },
          );
          await file.writeAsString(csvText);
        }

        final parsed = const CsvToListConverter(eol: '\n').convert(csvText);
        if (parsed.isEmpty) {
          columnLabels = [];
          rows = [];
          columnWidths = [42];
          footerTrailing = '';
        } else {
          columnLabels = parsed[0].map((e) => e.toString()).toList();
          rows = parsed
              .skip(1)
              .where((r) => r.any((c) => c.toString().isNotEmpty))
              .map((r) => r.map((e) => e.toString()).toList())
              .toList();
          columnWidths = [
            42.0,
            240.0, // stock_item_name — widest column
            ...List.filled(columnLabels.length - 1, 96.0),
          ];
          footerTrailing = '${rows.length} rows';
        }
      } else {
        columnLabels = const ['stock_item', 'sales_6m', 'pur_1m', 'stock_qty', 'stock_₹', 'scenario'];
        columnWidths = const [42, 220, 88, 88, 96, 96, 140];
        rows = category.rows;
        footerTrailing = category.footerSum.isEmpty ? '' : 'Σ ${category.footerSum}';
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingCategoryKey = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load report: $e')),
        );
      }
      return;
    }

    if (!mounted) return;
    setState(() => _loadingCategoryKey = null);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return AppSpreadsheetSheet(
          fileName: '/${category.key}.csv',
          toolbarItems: const ['File', 'Edit', 'View', 'Filter', 'Σ'],
          columnLabels: columnLabels,
          columnWidths: columnWidths,
          rows: rows,
          footerLeading: category.footerMeta,
          footerTrailing: footerTrailing,
          onShare: category.reportId == null
              ? null
              : () async {
                  final file = await _cacheFile(category.reportId!);
                  if (await file.exists()) {
                    await Share.shareXFiles(
                      [XFile(file.path)],
                      subject: '${category.key}.csv',
                    );
                  }
                },
          trailingAction: OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppPalette.ink,
              side: const BorderSide(color: AppPalette.ink, width: 1.3),
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
            labels: const ['Insights', 'Chat'],
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
                  : const Center(
                      key: ValueKey('chat'),
                      child: Text(
                        'Coming Soon',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppPalette.muted,
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
