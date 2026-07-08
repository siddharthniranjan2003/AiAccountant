import '../core/models.dart';

const List<QueueEntry> seedQueueEntries = [
  QueueEntry(
    id: 'purchase_krishna',
    type: TransactionType.purchase,
    party: 'Krishna Steels',
    amount: 980,
    dayLabel: 'Today',
    timeLabel: '09:40',
    checked: true,
  ),
  QueueEntry(
    id: 'purchase_gupta',
    type: TransactionType.purchase,
    party: 'Gupta Tools',
    amount: 1240,
    dayLabel: 'Today',
    timeLabel: '12:26',
  ),
  QueueEntry(
    id: 'purchase_anchor',
    type: TransactionType.purchase,
    party: 'Anchor Components',
    amount: 575,
    dayLabel: 'Yesterday',
    timeLabel: '16:05',
  ),
  QueueEntry(
    id: 'purchase_metro',
    type: TransactionType.purchase,
    party: 'Metro Bearings',
    amount: 860,
    dayLabel: 'Yesterday',
    timeLabel: '14:55',
  ),
];

const List<HistoryEntry> seedHistoryEntries = [
  HistoryEntry(
    party: 'ABC Traders',
    type: TransactionType.sale,
    amount: 100,
    dateLabel: '05 May',
    monthLabel: 'May 2026',
  ),
  HistoryEntry(
    party: 'Delta Fasteners',
    type: TransactionType.purchase,
    amount: 200,
    dateLabel: '04 May',
    monthLabel: 'May 2026',
  ),
  HistoryEntry(
    party: 'XYZ Mart',
    type: TransactionType.sale,
    amount: 300,
    dateLabel: '04 May',
    monthLabel: 'May 2026',
  ),
  HistoryEntry(
    party: 'MNO Supply',
    type: TransactionType.purchase,
    amount: 450,
    dateLabel: '02 May',
    monthLabel: 'May 2026',
  ),
  HistoryEntry(
    party: 'Prime Hardware',
    type: TransactionType.sale,
    amount: 520,
    dateLabel: '28 Apr',
    monthLabel: 'April 2026',
  ),
];

const List<ReportCategory> seedReportCategories = [
  ReportCategory(
    key: 'act_now',
    emoji: '🚨',
    description: 'Items at risk of lost sales. Reorder immediately or within days. Highest revenue impact.',
    rows: [],
    footerMeta: 'Live data · sorted by ₹ impact',
    footerSum: '',
    reportId: 'R1',
  ),
  ReportCategory(
    key: 'hero_sku_health',
    emoji: '🏆',
    description: 'Top-performing items driving revenue. Protect at all costs. Never let them stock out.',
    rows: [],
    footerMeta: 'Live data · sorted by sales velocity',
    footerSum: '',
    reportId: 'R2',
  ),
  ReportCategory(
    key: 'dead_capital',
    emoji: '💀',
    description: 'Capital locked with zero or negative returns. Liquidate, write off, or audit. Sort by ₹ value.',
    rows: [],
    footerMeta: 'Live data · sorted by dead capital',
    footerSum: '',
    reportId: 'R3',
  ),
  ReportCategory(
    key: 'buying_mistakes',
    emoji: '⚠️',
    description: 'Purchasing happened without sales justification. Stop the bleed. Review buyer decisions.',
    rows: [],
    footerMeta: 'Live data · sorted by mismatch score',
    footerSum: '',
    reportId: 'R4',
  ),
  ReportCategory(
    key: 'wind_down',
    emoji: '🪟',
    description: 'Items clearing out by intent or neglect. Track days-to-clear. Recommit or exit cleanly.',
    rows: [],
    footerMeta: 'Live data · sorted by exit timeline',
    footerSum: '',
    reportId: 'R5',
  ),
  ReportCategory(
    key: 'risk_watch',
    emoji: '👀',
    description: 'Needs monitoring but not emergency action. Seasonal demand check. Cash flow exposure.',
    rows: [],
    footerMeta: 'Live data · monitoring set',
    footerSum: '',
    reportId: 'R6',
  ),
  ReportCategory(
    key: 'full_portfolio_health',
    emoji: '📊',
    description: 'Complete sorted view. Health score 1–100. Sort ascending to find worst items first.',
    rows: [],
    footerMeta: 'Live data · all items ranked',
    footerSum: '',
    reportId: 'R7',
  ),
];

List<List<String>> buildChallanRows(String party) {
  final partyCode = party.split(' ').first.toUpperCase();
  return [
    ['$partyCode Bolt 10×100', '7318', '12', '8.50', '18', '120.36'],
    ['AG-4 6mm Bear', '6804', '25', '14.20', '18', '418.90'],
    ['Adjustable Wrench 12"', '8204', '3', '340.00', '18', '1,203.60'],
    ['Alkon Disc 5" G80', '6804', '10', '22.00', '18', '259.60'],
    ['Aerosol-OS', '3808', '6', '85.00', '18', '601.80'],
    ['', '', '', '', '', ''],
    ['', '', '', '', '', ''],
    ['', '', '', '', '', ''],
  ];
}
