import 'models.dart';

const List<QueueEntry> seedQueueEntries = [
  QueueEntry(
    id: 'sale_abc',
    type: TransactionType.sale,
    party: 'ABC Traders',
    amount: 100,
    dayLabel: 'Today',
    timeLabel: '10:14',
    checked: true,
  ),
  QueueEntry(
    id: 'sale_def',
    type: TransactionType.sale,
    party: 'Delta Fasteners',
    amount: 200,
    dayLabel: 'Today',
    timeLabel: '11:02',
    checked: true,
  ),
  QueueEntry(
    id: 'sale_xyz',
    type: TransactionType.sale,
    party: 'XYZ Mart',
    amount: 300,
    dayLabel: 'Yesterday',
    timeLabel: '17:48',
  ),
  QueueEntry(
    id: 'sale_mno',
    type: TransactionType.sale,
    party: 'MNO Supply',
    amount: 450,
    dayLabel: 'Yesterday',
    timeLabel: '14:21',
  ),
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
    description:
        'Items at risk of lost sales. Reorder immediately or within days. Highest revenue impact.',
    rows: [
      ['Allen Bolt 10×100', '188', '34', '9', '₹14,580', 'Reorder now'],
      ['AG-4 6mm Bear', '122', '20', '6', '₹8,960', '3 day cover'],
      ['Adjustable Wrench', '48', '11', '2', '₹3,220', 'Stockout risk'],
      ['Aerosol-OS', '74', '18', '5', '₹5,410', 'Cash tied, moving'],
    ],
    footerMeta: '2,140 rows · sorted by ₹ impact',
    footerSum: '₹32,170',
  ),
  ReportCategory(
    key: 'hero_sku_health',
    emoji: '🏆',
    description:
        'Top-performing items driving revenue. Protect at all costs. Never let them stock out.',
    rows: [
      ['Cutting Disc G80', '342', '44', '31', '₹48,920', 'Healthy'],
      ['Hex Bolt Pack', '301', '51', '22', '₹32,410', 'Watch lead time'],
      ['Industrial Drill Bit', '228', '29', '17', '₹24,800', 'Healthy'],
      ['Bearing Kit Pro', '174', '19', '11', '₹18,320', 'Watch demand'],
    ],
    footerMeta: '482 rows · sorted by sales velocity',
    footerSum: '₹124,450',
  ),
  ReportCategory(
    key: 'dead_capital',
    emoji: '💀',
    description:
        'Capital locked with zero or negative returns. Liquidate, write off, or audit. Sort by ₹ value.',
    rows: [
      ['Legacy Washer 14mm', '0', '15', '182', '₹12,640', 'No sales'],
      ['Drill Stand Basic', '2', '7', '44', '₹9,460', 'Exit candidate'],
      ['Masking Tape XL', '1', '6', '51', '₹4,920', 'Slow mover'],
      ['Bracket Set L', '0', '8', '27', '₹3,410', 'Audit lot'],
    ],
    footerMeta: '191 rows · sorted by dead capital',
    footerSum: '₹30,430',
  ),
  ReportCategory(
    key: 'buying_mistakes',
    emoji: '⚠️',
    description:
        'Purchasing happened without sales justification. Stop the bleed. Review buyer decisions.',
    rows: [
      ['Ceramic Wheel Red', '1', '12', '71', '₹10,220', 'No demand match'],
      ['Glue Cartridge X', '3', '19', '88', '₹7,740', 'Overbought'],
      ['Saw Blade 14"', '4', '14', '33', '₹6,590', 'Weak turns'],
      ['Dust Mask Bulk', '2', '18', '62', '₹5,860', 'Review policy'],
    ],
    footerMeta: '87 rows · sorted by mismatch score',
    footerSum: '₹30,410',
  ),
  ReportCategory(
    key: 'wind_down',
    emoji: '🪟',
    description:
        'Items clearing out by intent or neglect. Track days-to-clear. Recommit or exit cleanly.',
    rows: [
      ['Valve Spanner 9"', '14', '0', '8', '₹2,940', 'Clear in 12 days'],
      ['Allen Key Mini', '8', '0', '5', '₹820', 'Last batch'],
      ['Fast Cure Resin', '6', '0', '11', '₹1,630', 'Watch expiry'],
      ['Panel Clip Black', '5', '0', '7', '₹640', 'Clear channel'],
    ],
    footerMeta: '53 rows · sorted by exit timeline',
    footerSum: '₹6,030',
  ),
  ReportCategory(
    key: 'risk_watch',
    emoji: '👀',
    description:
        'Needs monitoring but not emergency action. Seasonal demand check. Cash flow exposure.',
    rows: [
      ['Monsoon Sealant', '28', '6', '14', '₹3,900', 'Seasonal'],
      ['Tile Spacer', '37', '8', '22', '₹2,810', 'Margin drift'],
      ['Paint Roller Pro', '24', '5', '9', '₹1,580', 'Demand noisy'],
      ['Protective Gloves', '61', '12', '31', '₹5,260', 'Watch price'],
    ],
    footerMeta: '612 rows · monitoring set',
    footerSum: '₹13,550',
  ),
  ReportCategory(
    key: 'full_portfolio_health',
    emoji: '📊',
    description:
        'Complete sorted view. Health score 1–100. Sort ascending to find worst items first.',
    rows: [
      ['Allen Bolt 10×100', '188', '34', '9', '₹14,580', '91'],
      ['Legacy Washer 14mm', '0', '15', '182', '₹12,640', '18'],
      ['Cutting Disc G80', '342', '44', '31', '₹48,920', '95'],
      ['Glue Cartridge X', '3', '19', '88', '₹7,740', '29'],
    ],
    footerMeta: '4,802 rows · all items ranked',
    footerSum: '₹83,880',
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
