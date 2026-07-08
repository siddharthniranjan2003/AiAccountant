import 'dart:io';
import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/models.dart';
import '../../data/seed_data.dart';
import '../../core/palette.dart';
import '../../services/api_client.dart';
import '../../shared/screen_frame.dart';
import '../../shared/app_top_tabs.dart';
import '../../shared/spreadsheet_sheet.dart';
import 'report_list_item.dart';

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

  // Today as yyyy-MM-dd, used to invalidate the cache once per day.
  String _todayStamp() {
    final now = DateTime.now();
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '${now.year}-$m-$d';
  }

  // Formats a yyyy-MM-dd stamp as e.g. "3 Jul 2026" for display.
  String _prettyDate(String stamp) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final parts = stamp.split('-');
    if (parts.length != 3) return stamp;
    final month = int.tryParse(parts[1]) ?? 0;
    final day = int.tryParse(parts[2]) ?? 0;
    if (month < 1 || month > 12) return stamp;
    return '$day ${months[month - 1]} ${parts[0]}';
  }

  // Returns the report CSV and the date it was cached. Served from cache when
  // it was fetched today, otherwise re-downloaded and re-cached with today's
  // date stamp. The CSV body lives in a file on native and in
  // shared_preferences on web (where path_provider has no implementation); the
  // date stamp always lives in shared_preferences so the same expiry logic
  // works on both.
  Future<({String csv, String date})> _loadReportCsv(String reportId) async {
    final prefs = await SharedPreferences.getInstance();
    final today = _todayStamp();
    final dateKey = 'report_cache_date_$reportId';
    final csvKey = 'report_cache_csv_$reportId';

    Future<String> fetch() => ApiClient.getRaw(
          '/api/sync/reorder-levels/$reportId',
          query: {'company_name': 'K V ENTERPRISES', 'format': 'csv'},
        );

    if (prefs.getString(dateKey) == today) {
      if (kIsWeb) {
        final cached = prefs.getString(csvKey);
        if (cached != null) return (csv: cached, date: today);
      } else {
        final file = await _cacheFile(reportId);
        if (await file.exists()) {
          return (csv: await file.readAsString(), date: today);
        }
      }
    }

    final csvText = await fetch();
    if (kIsWeb) {
      await prefs.setString(csvKey, csvText);
    } else {
      await (await _cacheFile(reportId)).writeAsString(csvText);
    }
    await prefs.setString(dateKey, today);
    return (csv: csvText, date: today);
  }

  Future<void> _openReport(ReportCategory category) async {
    setState(() => _loadingCategoryKey = category.key);

    List<List<String>> rows;
    List<String> columnLabels;
    List<double> columnWidths;
    String footerTrailing;
    int? sumColumnIndex;
    String? cachedDate;

    try {
      if (category.reportId != null) {
        final cached = await _loadReportCsv(category.reportId!);
        cachedDate = _prettyDate(cached.date);

        final parsed = const CsvToListConverter(eol: '\n').convert(cached.csv);
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
            240.0,
            ...List.filled(columnLabels.length - 1, 96.0),
          ];
          footerTrailing = '${rows.length} rows';
          final idx = columnLabels.indexOf('closing_stock_amount');
          sumColumnIndex = idx >= 0 ? idx : null;
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to load report: $e')));
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
          cachedDate: cachedDate,
          toolbarItems: const ['File', 'Edit', 'View', 'Filter', 'Σ'],
          columnLabels: columnLabels,
          columnWidths: columnWidths,
          rows: rows,
          footerLeading: category.footerMeta,
          footerTrailing: footerTrailing,
          sumColumnIndex: sumColumnIndex,
          footerLeadingLabel: 'Sorted By Closing stock amount',
          countUnit: sumColumnIndex != null ? 'Items' : 'rows',
          // File-share relies on the on-disk cache, which doesn't exist on web.
          onShare: (category.reportId == null || kIsWeb)
              ? null
              : () async {
                  final file = await _cacheFile(category.reportId!);
                  if (await file.exists()) {
                    await Share.shareXFiles([XFile(file.path)], subject: '${category.key}.csv');
                  }
                },
          trailingAction: OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppPalette.ink,
              side: const BorderSide(color: AppPalette.ink, width: 1.3),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
            onSelected: (index) => setState(() => _tabIndex = index),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: _tabIndex == 0
                  ? ListView.separated(
                      key: const ValueKey('insights'),
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
                      itemCount: seedReportCategories.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 2),
                      itemBuilder: (context, index) {
                        final category = seedReportCategories[index];
                        return ReportListItem(
                          category: category,
                          isLoading: _loadingCategoryKey == category.key,
                          onTap: () => _openReport(category),
                        );
                      },
                    )
                  : Center(
                      key: const ValueKey('chat'),
                      child: Text('Coming Soon.....', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppPalette.muted)),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
