import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/constants.dart';
import '../../core/palette.dart';
import '../../core/utils.dart';
import '../../data/customers_cache.dart';
import '../../data/stock_items_cache.dart';
import '../../shared/customer_picker_sheet.dart';

/// A single Purchase/Sale history line, formatted for display.
class _Txn {
  const _Txn({
    required this.date,
    required this.party,
    required this.qty,
    required this.rate,
    required this.disc,
    required this.amount,
    this.latest = false,
  });

  final String date;
  final String party;
  final String qty;
  final String rate;
  final String disc;
  final String amount;
  final bool latest;

  /// Builds a display row from a raw `voucher_items` row. `date` and
  /// `party_name` come from the parent voucher — the `...vouchers!inner(…)`
  /// spread in [_select] flattens them into top-level keys, so they read the
  /// same as any line column. `amount` is stored signed (purchases negative,
  /// sales positive), so we show its magnitude.
  factory _Txn.fromRow(Map<String, dynamic> row, {bool latest = false}) {
    final qty = (row['quantity'] as num?)?.toDouble() ?? 0;
    final rate = (row['rate'] as num?)?.toDouble() ?? 0;
    final disc = (row['discount_pct'] as num?)?.toDouble();
    // Fall back to qty·rate·(1−disc%) if the stored amount is ever missing.
    final rawAmount = (row['amount'] as num?)?.toDouble() ??
        qty * rate * (1 - (disc ?? 0) / 100);
    final unit = (row['unit'] as String? ?? '').trim();
    final party = (row['party_name'] as String? ?? '').trim();
    return _Txn(
      date: formatShortDate(row['date'] as String?),
      party: party.isEmpty ? '—' : party,
      qty: unit.isEmpty ? _trimNum(qty) : '${_trimNum(qty)} $unit',
      rate: formatDecimal(rate),
      disc: disc == null ? '—' : '${_trimNum(disc)}%',
      amount: '₹${formatDecimal(rawAmount.abs())}',
      latest: latest,
    );
  }
}

/// Formats a quantity/percent, dropping a trailing ".0" (20.0 → "20",
/// 2.5 → "2.5").
String _trimNum(num n) =>
    n == n.roundToDouble() ? n.toStringAsFixed(0) : n.toString();

/// Standalone Stock Info page — opens in its own browser tab from the ⓘ on a
/// voucher item row and shows the item's Purchase & Sale history from Supabase.
///
/// When [partyName] is set (the ⓘ was clicked on a *sale* invoice) the Sale
/// panel is scoped to that customer + this item and shows the customer as a
/// header. Otherwise both panels are item-scoped (e.g. opened from a purchase
/// invoice, or a direct link).
class StockInfoScreen extends StatefulWidget {
  const StockInfoScreen({super.key, required this.itemName, this.partyName});

  final String itemName;
  final String? partyName;

  @override
  State<StockInfoScreen> createState() => _StockInfoScreenState();
}

class _StockInfoScreenState extends State<StockInfoScreen> {
  // date, party_name and voucher_type all come from the parent voucher, never
  // from the line. voucher_items carries unmaintained copies of the three: they
  // are NULL on every row synced since 2026-07-20, so a line-sourced date sorts
  // the newest invoices to the bottom and .limit(5) hides them entirely.
  // The `...` spread flattens the embed into top-level keys, so rows keep
  // deserializing exactly as before (see _Txn.fromRow).
  // `!inner` is load-bearing — it applies both the voucher_type and the
  // party_name filter. Drop it and PostgREST still returns 200, but silently
  // stops filtering and the panel shows every party's lines.
  static const _select =
      'stock_item_name, quantity, rate, unit, discount_pct, amount, '
      '...vouchers!inner(date, party_name, voucher_type)';

  // null = still loading; non-null = loaded (may be empty). *Error holds a
  // message when the query threw, so each panel fails independently.
  List<_Txn>? _purchases;
  List<_Txn>? _sales;
  String? _purchaseError;
  String? _saleError;

  // The stock item currently shown; changes when the user picks one via search.
  late String _item;

  // The customer the Sale panel can be scoped to. Starts as the invoice's
  // customer (URL param); replaced by picks from the customer sheet, cleared
  // by the chip's ×.
  String _party = '';
  bool get _hasParty => _party.isNotEmpty && _party != '—';
  // True while the Sale panel is filtered to the customer; the user can toggle
  // it off (tap the chip) or remove it entirely (× on the chip).
  late bool _partyActive;
  bool get _partyScoped => _partyActive && _hasParty;

  @override
  void initState() {
    super.initState();
    _item = widget.itemName.trim();
    _party = (widget.partyName ?? '').trim();
    _partyActive = _hasParty;
    // Warm the catalog for the search bar's space-insensitive matching. This
    // standalone tab skips AuthGate, so the auth-driven cache fetch may never
    // have run here. Fire-and-forget: until it lands, search falls back to the
    // server ilike query.
    final stockCache = StockItemsCache.instance;
    if (stockCache.items.isEmpty && !stockCache.isLoading) {
      stockCache.fetch();
    }
    if (_item.isEmpty) {
      _purchases = const [];
      _sales = const [];
      return;
    }
    _loadPurchases();
    _loadSales();
  }

  Future<void> _loadPurchases() async {
    try {
      final res = await Supabase.instance.client
          .from('voucher_items')
          .select(_select)
          .eq('stock_item_name', _item)
          .ilike('vouchers.voucher_type', '%purchase%')
          // Sort on the embedded column via the 'vouchers(date)' string form.
          // NOT .order('date', referencedTable: 'vouchers') — that emits
          // `vouchers.order=`, which sorts *inside* the embed and leaves the top
          // level unsorted: HTTP 200, wrong five rows. id breaks date ties so
          // the .limit(5) window (and the `latest` badge on row 0) is stable.
          .order('vouchers(date)', ascending: false)
          .order('id', ascending: true)
          .limit(5);
      if (!mounted) return;
      setState(() => _purchases = _toTxns(res));
    } catch (_) {
      if (!mounted) return;
      setState(() => _purchaseError = "Couldn't load purchase history.");
    }
  }

  Future<void> _loadSales() async {
    try {
      var query = Supabase.instance.client
          .from('voucher_items')
          .select(_select)
          .eq('stock_item_name', _item)
          .ilike('vouchers.voucher_type', '%sale%');
      // From a sale invoice: narrow to this customer's history for this item.
      if (_partyScoped) {
        query = query.eq('vouchers.party_name', _party);
      }
      // Embedded-column sort + id tiebreak — see the note in _loadPurchases.
      final res = await query
          .order('vouchers(date)', ascending: false)
          .order('id', ascending: true)
          .limit(5);
      if (!mounted) return;
      setState(() => _sales = _toTxns(res));
    } catch (_) {
      if (!mounted) return;
      setState(() => _saleError = "Couldn't load sale history.");
    }
  }

  // Toggle the customer filter on/off and reload the Sale panel. Active = this
  // customer's sales of the item; inactive = all sales of the item (like Purchase).
  void _toggleParty() {
    setState(() {
      _partyActive = !_partyActive;
      _sales = null;
      _saleError = null;
    });
    _loadSales();
  }

  // Remove the customer chip entirely — the Sale panel goes item-scoped and the
  // chip disappears (stays gone across item picks).
  void _removeParty() {
    setState(() {
      _party = '';
      _sales = null;
      _saleError = null;
    });
    _loadSales();
  }

  // Guards _pickParty against re-entry while the customer list downloads.
  bool _pickingParty = false;

  // Open the customer picker sheet; the pick REPLACES the current filter and
  // applies it immediately.
  Future<void> _pickParty() async {
    if (_pickingParty) return;
    // This standalone tab skips AuthGate, so the auth-driven cache fetch may
    // never have run here — download the customer list on first use.
    final cache = CustomersCache.instance;
    if (cache.items.isEmpty) {
      if (cache.isLoading) return;
      _pickingParty = true;
      try {
        await cache.fetch();
      } finally {
        _pickingParty = false;
      }
      if (!mounted) return;
      if (cache.items.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't load the customer list.")),
        );
        return;
      }
    }
    final selected = await showModalBottomSheet<Customer>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CustomerPickerSheet(
        items: cache.items,
        searchHint: 'Search customers…',
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _party = selected.name;
      _partyActive = true;
      _sales = null;
      _saleError = null;
    });
    _loadSales();
  }

  // A stock item was picked from the search dropdown: reload both panels for it.
  // The customer chip state (active / inactive / removed) carries over.
  void _selectItem(String name) {
    final picked = name.trim();
    if (picked.isEmpty || picked == _item) return;
    setState(() {
      _item = picked;
      _purchases = null;
      _sales = null;
      _purchaseError = null;
      _saleError = null;
    });
    _loadPurchases();
    _loadSales();
  }

  // Search cleared (× in the search bar): no item selected, empty panels.
  void _clearAll() {
    setState(() {
      _item = '';
      _purchases = const [];
      _sales = const [];
      _purchaseError = null;
      _saleError = null;
    });
  }

  List<_Txn> _toTxns(List<dynamic> rows) => [
        for (var i = 0; i < rows.length; i++)
          _Txn.fromRow(Map<String, dynamic>.from(rows[i] as Map), latest: i == 0),
      ];

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= kDesktopBreakpoint;
    final name = _item.isEmpty ? 'Stock item' : _item;

    final purchase = _HistoryPanel(
      title: 'Purchase',
      dotColor: const Color(0xFFB9C8DF),
      saleTint: false,
      rows: _purchases,
      error: _purchaseError,
      summaryVerb: 'Last purchased on',
      emptyMessage: 'No purchase history for this item.',
      showParty: true,
    );
    final sale = _HistoryPanel(
      title: 'Sale',
      dotColor: AppPalette.accent2,
      saleTint: true,
      rows: _sales,
      error: _saleError,
      summaryVerb: 'Last sold on',
      emptyMessage: _partyScoped
          ? 'No sales of this item to $_party yet.'
          : 'No sale history for this item.',
      showParty: !_partyScoped,
      partyToggleName: (_hasParty && _item.isNotEmpty) ? _party : null,
      partyActive: _partyScoped,
      onToggleParty: _toggleParty,
      onRemoveParty: _removeParty,
      onPickParty: _item.isNotEmpty ? _pickParty : null,
    );

    return Scaffold(
      backgroundColor: AppPalette.sheet,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              _SearchBar(
                initialItem: _item,
                onSelect: _selectItem,
                onClear: _clearAll,
              ),
              // Selected item name, shown right below the search bar.
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 14, 4, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: 'Name: ',
                          style: TextStyle(color: AppPalette.muted),
                        ),
                        TextSpan(
                          text: name,
                          style: TextStyle(color: AppPalette.ink),
                        ),
                      ],
                    ),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
              // Panels fill the rest of the screen. On wide screens they sit
              // side-by-side and each scrolls on its own; on narrow screens they
              // stack into a single scroll view.
              Expanded(
                child: _item.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'Search a stock item above to see its '
                            'Purchase & Sale history.',
                            textAlign: TextAlign.center,
                            style:
                                Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      color: AppPalette.muted,
                                    ),
                          ),
                        ),
                      )
                    : wide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: SingleChildScrollView(child: purchase),
                              ),
                              Container(width: 1, color: AppPalette.line),
                              Expanded(
                                  child: SingleChildScrollView(child: sale)),
                            ],
                          )
                        : SingleChildScrollView(
                            child: Column(
                              children: [
                                purchase,
                                Container(height: 1, color: AppPalette.line),
                                sale,
                              ],
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Top search bar — a type-ahead over the `stock_items` catalog. Picking a
/// result loads that item's panels ([onSelect]); the trailing × clears the
/// field and both panels ([onClear]).
class _SearchBar extends StatefulWidget {
  const _SearchBar({
    required this.initialItem,
    required this.onSelect,
    required this.onClear,
  });

  final String initialItem;
  final ValueChanged<String> onSelect;
  final VoidCallback onClear;

  @override
  State<_SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends State<_SearchBar> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialItem);
  final FocusNode _focusNode = FocusNode();

  // Debounce: each keystroke bumps the token; only the latest one runs a query.
  int _token = 0;
  List<String> _lastOptions = const [];
  // True while a search is genuinely waiting (catalog download or server
  // fallback); shows a spinner in the field. Not set for instant cache hits.
  bool _searching = false;
  // Global position of a pointer-down on an option row — lets us tell a tap
  // from a scroll drag in optionsViewBuilder (web arena swallows InkWell taps).
  Offset? _downPos;
  // Keyboard navigation: GlobalKeys per option row, used to scroll the
  // highlighted row into view. RawAutocomplete tracks the highlighted index
  // itself (see AutocompleteHighlightedOption.of below); this just remembers
  // the last value seen so a real change can be detected and scrolled to.
  final Map<int, GlobalKey> _optionKeys = {};
  int _lastHighlighted = 0;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<Iterable<String>> _search(TextEditingValue value) async {
    final q = value.text.trim();
    if (q.length < 2) return const <String>[];
    final token = ++_token;
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (token != _token) return _lastOptions; // superseded — skip the query
    // Space-insensitive match over the catalog cache ("hsstap" finds
    // "HSS TAP …"), which ilike can't do. The cache is name-sorted, so taking
    // the first 20 mirrors the server query's order('name').limit(20).
    // Right after the window opens the catalog may still be downloading; wait
    // for it here (RawAutocomplete won't re-run this builder on its own, so
    // falling back would leave a no-space query empty forever). The token
    // guard drops this wait when a newer keystroke supersedes it.
    try {
      var catalog = StockItemsCache.instance.items;
      if (catalog.isEmpty && StockItemsCache.instance.isLoading) {
        _setSearching(true);
        while (catalog.isEmpty && StockItemsCache.instance.isLoading) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          if (token != _token) return _lastOptions;
          catalog = StockItemsCache.instance.items;
        }
      }
      if (catalog.isNotEmpty) {
        final key = searchKey(q);
        _lastOptions = [
          for (final item in catalog)
            if (searchKey(item.name).contains(key)) item.name,
        ].take(20).toList();
        return _lastOptions;
      }
      // Catalog fetch failed (done loading, still empty): fall back to the
      // server query — exact-substring matches only.
      _setSearching(true);
      try {
        final res = await Supabase.instance.client
            .from('stock_items')
            .select('name')
            .ilike('name', '%$q%')
            .order('name')
            .limit(20);
        if (token != _token) return _lastOptions;
        _lastOptions = [
          for (final r in (res as List)) (r as Map)['name'] as String,
        ];
        return _lastOptions;
      } catch (_) {
        return _lastOptions;
      }
    } finally {
      // Only the latest search may clear the spinner — an older superseded one
      // finishing late must not hide it while the new search is still waiting.
      if (token == _token) _setSearching(false);
    }
  }

  void _setSearching(bool v) {
    if (!mounted || _searching == v) return;
    setState(() => _searching = v);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppPalette.line)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final fieldWidth = constraints.maxWidth;
          return RawAutocomplete<String>(
            textEditingController: _controller,
            focusNode: _focusNode,
            optionsBuilder: _search,
            displayStringForOption: (o) => o,
            onSelected: (name) {
              widget.onSelect(name);
              _focusNode.unfocus();
            },
            fieldViewBuilder:
                (context, controller, focusNode, onFieldSubmitted) {
              return ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, value, _) {
                  return TextField(
                    controller: controller,
                    focusNode: focusNode,
                    // Opened without an item (Rate rail / tab-bar): the first
                    // action is always a search, so be ready to type.
                    autofocus: widget.initialItem.isEmpty,
                    onSubmitted: (_) => onFieldSubmitted(),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      suffixIcon: (value.text.isEmpty && !_searching)
                          ? null
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_searching)
                                  const Padding(
                                    padding: EdgeInsets.only(right: 4),
                                    child: SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    ),
                                  ),
                                if (value.text.isNotEmpty)
                                  IconButton(
                                    icon: const Icon(Icons.close_rounded,
                                        size: 18),
                                    splashRadius: 18,
                                    tooltip: 'Clear',
                                    onPressed: () {
                                      controller.clear();
                                      widget.onClear();
                                      focusNode.unfocus();
                                    },
                                  ),
                              ],
                            ),
                      suffixIconConstraints:
                          const BoxConstraints(minWidth: 40, minHeight: 40),
                      filled: true,
                      fillColor: AppPalette.gridHeader,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 12),
                      isDense: true,
                    ),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  );
                },
              );
            },
            optionsViewBuilder: (context, onSelected, options) {
              final items = options.toList();
              // RawAutocomplete already tracks Down/Up navigation on the field
              // (installed via Shortcuts on the fieldView) — read the index it's
              // highlighting so this view can show it and keep it in scroll view.
              final highlighted = AutocompleteHighlightedOption.of(context);
              if (highlighted != _lastHighlighted) {
                _lastHighlighted = highlighted;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  final ctx = _optionKeys[highlighted]?.currentContext;
                  if (ctx != null) {
                    Scrollable.ensureVisible(ctx,
                        alignment: 0.5,
                        duration: const Duration(milliseconds: 120));
                  }
                });
              }
              return TextFieldTapRegion(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    elevation: 4,
                    borderRadius: BorderRadius.circular(12),
                    child: ConstrainedBox(
                      constraints:
                          BoxConstraints(maxHeight: 320, maxWidth: fieldWidth),
                      child: ListView.builder(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        itemCount: items.length,
                        itemBuilder: (context, i) {
                          final name = items[i];
                          // On Flutter web the scrollable's gesture arena can
                          // swallow the InkWell's onTap inside this overlay, so
                          // detect the tap from raw pointer events: select on
                          // pointer-up only when it barely moved (a real tap,
                          // not a scroll drag).
                          return Listener(
                            onPointerDown: (e) => _downPos = e.position,
                            onPointerUp: (e) {
                              final d = _downPos;
                              _downPos = null;
                              if (d != null &&
                                  (e.position - d).distance < 18) {
                                onSelected(name);
                              }
                            },
                            child: InkWell(
                              onTap: () => onSelected(name),
                              child: Container(
                                key: _optionKeys.putIfAbsent(
                                    i, () => GlobalKey()),
                                color: i == highlighted
                                    ? AppPalette.ink.withValues(alpha: 0.06)
                                    : null,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 11),
                                child: Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        color: AppPalette.ink,
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// One side (Purchase or Sale) — header, last-purchased/sold summary, and the
/// history table (or a loading / empty / error state in its place).
class _HistoryPanel extends StatelessWidget {
  const _HistoryPanel({
    required this.title,
    required this.dotColor,
    required this.saleTint,
    required this.rows,
    required this.error,
    required this.summaryVerb,
    required this.emptyMessage,
    required this.showParty,
    this.partyToggleName,
    this.partyActive = false,
    this.onToggleParty,
    this.onRemoveParty,
    this.onPickParty,
  });

  final String title;
  final Color dotColor;
  final bool saleTint;
  final List<_Txn>? rows; // null while loading
  final String? error; // non-null when the query failed
  final String summaryVerb;
  final String emptyMessage;
  // Whether to render the PARTY NAME column. Hidden when the panel is scoped to
  // a single party (shown in [partyHeader] instead).
  final bool showParty;
  // When set, the Sale panel shows a customer filter toggle above the table.
  final String? partyToggleName;
  final bool partyActive;
  final VoidCallback? onToggleParty;
  final VoidCallback? onRemoveParty;
  // Opens the customer picker sheet — the pick replaces the filter. Shown as a
  // button beside the chip, or alone when no filter is set.
  final VoidCallback? onPickParty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loaded = rows;
    final hasRows = loaded != null && loaded.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header + summary line
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 15, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: dotColor,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    title.toUpperCase(),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: AppPalette.inkSoft,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const Spacer(),
                  if (loaded != null)
                    Text(
                      '${loaded.length} ${loaded.length == 1 ? 'entry' : 'entries'}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppPalette.muted,
                      ),
                    ),
                ],
              ),
              if (hasRows) ...[
                const SizedBox(height: 8),
                Text(
                  '$summaryVerb ${loaded.first.date}'
                  '  ·  ${loaded.first.qty} @ ₹${loaded.first.rate}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppPalette.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              // Customer filter toggle — active by default (scopes the Sale
              // panel to this customer); tap to show all sales of the item.
              // The add button beside it opens the customer picker; a pick
              // replaces the filter (or adds one when none is set).
              if (partyToggleName != null || onPickParty != null) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    if (partyToggleName != null)
                      Flexible(
                        child: _PartyToggle(
                          name: partyToggleName!,
                          active: partyActive,
                          onToggle: onToggleParty,
                          onRemove: onRemoveParty,
                        ),
                      ),
                    if (partyToggleName != null && onPickParty != null)
                      const SizedBox(width: 8),
                    if (onPickParty != null)
                      _PartyPickButton(
                        onTap: onPickParty!,
                        hasParty: partyToggleName != null,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        _body(theme),
      ],
    );
  }

  Widget _body(ThemeData theme) {
    if (error != null) return _message(theme, error!);
    final loaded = rows;
    if (loaded == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (loaded.isEmpty) return _message(theme, emptyMessage);
    return Column(
      children: [
        _TxnHeaderRow(showParty: showParty),
        for (final t in loaded)
          _TxnRow(txn: t, saleTint: saleTint, showParty: showParty),
      ],
    );
  }

  Widget _message(ThemeData theme, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
        child: Text(
          text,
          style: theme.textTheme.bodySmall?.copyWith(color: AppPalette.muted),
        ),
      );
}

/// The invoice's customer, drawn as a filter toggle above the Sale table.
/// Active (default) scopes the panel to this customer; tapping [onToggle] flips
/// it off to show all sales of the item — and back on again.
class _PartyToggle extends StatelessWidget {
  const _PartyToggle({
    required this.name,
    required this.active,
    this.onToggle,
    this.onRemove,
  });
  final String name;
  final bool active;
  final VoidCallback? onToggle;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final fg = active ? AppPalette.ink : AppPalette.muted;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onToggle,
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 7, 8, 7),
          decoration: BoxDecoration(
            color: active
                ? AppPalette.accent2.withValues(alpha: 0.20)
                : AppPalette.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: active ? AppPalette.accent2 : AppPalette.line,
              width: active ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(active ? Icons.filter_alt : Icons.filter_alt_off,
                  size: 15, color: fg),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: fg,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                ),
              ),
              // Remove the customer filter entirely. Nested gesture so its tap
              // wins over the chip body's toggle.
              if (onRemove != null) ...[
                const SizedBox(width: 6),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onRemove,
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(Icons.close_rounded, size: 15, color: fg),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens the customer picker sheet. Icon-only beside the chip (replace); with
/// an "Add customer" label when no filter is set.
class _PartyPickButton extends StatelessWidget {
  const _PartyPickButton({required this.onTap, required this.hasParty});
  final VoidCallback onTap;
  final bool hasParty;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: hasParty ? 'Replace customer filter' : 'Filter by customer',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            decoration: BoxDecoration(
              color: AppPalette.card,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppPalette.line),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.person_add_alt_1,
                    size: 15, color: AppPalette.inkSoft),
                if (!hasParty) ...[
                  const SizedBox(width: 6),
                  Text(
                    'Add customer',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppPalette.inkSoft,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                        ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Shared column layout for the history table.
const double _kDateW = 78;
const double _kQtyW = 62;
const double _kRateW = 78;
const double _kDiscW = 54;
const double _kAmtW = 104;

class _TxnHeaderRow extends StatelessWidget {
  const _TxnHeaderRow({required this.showParty});
  final bool showParty;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: AppPalette.muted,
      fontWeight: FontWeight.w800,
      fontSize: 10,
    );
    return Container(
      color: AppPalette.gridHeader,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: _kDateW,
            child: Text('DATE', style: s),
          ),
          // Kept as an Expanded even when hidden so the numeric columns stay
          // aligned with the other panel.
          Expanded(child: Text(showParty ? 'PARTY NAME' : '', style: s)),
          SizedBox(
            width: _kQtyW,
            child: Text('QTY', style: s, textAlign: TextAlign.right),
          ),
          SizedBox(
            width: _kRateW,
            child: Text('RATE', style: s, textAlign: TextAlign.right),
          ),
          SizedBox(
            width: _kDiscW,
            child: Text('DISC %', style: s, textAlign: TextAlign.right),
          ),
          SizedBox(
            width: _kAmtW,
            child: Text('AMOUNT', style: s, textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }
}

class _TxnRow extends StatelessWidget {
  const _TxnRow({
    required this.txn,
    required this.saleTint,
    required this.showParty,
  });
  final _Txn txn;
  final bool saleTint;
  final bool showParty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final numStyle = theme.textTheme.bodySmall?.copyWith(
      color: AppPalette.inkSoft,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final amt = theme.textTheme.bodySmall?.copyWith(
      fontWeight: FontWeight.w800,
      color: saleTint ? AppPalette.success : AppPalette.inkSoft,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Container(
      decoration: BoxDecoration(
        color: txn.latest
            ? AppPalette.accent2.withValues(alpha: 0.13)
            : Colors.transparent,
        border: Border(bottom: BorderSide(color: AppPalette.line)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: _kDateW,
            child: Text(
              txn.date,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppPalette.inkSoft,
              ),
            ),
          ),
          // Party name (+ LATEST badge) when shown; otherwise the middle cell
          // just carries the LATEST badge so columns stay aligned.
          Expanded(
            child: showParty
                ? Row(
                    children: [
                      Flexible(
                        child: Text(
                          txn.party,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppPalette.ink,
                          ),
                        ),
                      ),
                      if (txn.latest) ...[
                        const SizedBox(width: 6),
                        const _LatestBadge(),
                      ],
                    ],
                  )
                : Align(
                    alignment: Alignment.centerLeft,
                    child: txn.latest
                        ? const _LatestBadge()
                        : const SizedBox.shrink(),
                  ),
          ),
          SizedBox(
            width: _kQtyW,
            child: Text(txn.qty, style: numStyle, textAlign: TextAlign.right),
          ),
          SizedBox(
            width: _kRateW,
            child: Text(txn.rate, style: numStyle, textAlign: TextAlign.right),
          ),
          SizedBox(
            width: _kDiscW,
            child: Text(txn.disc, style: numStyle, textAlign: TextAlign.right),
          ),
          SizedBox(
            width: _kAmtW,
            child: Text(txn.amount, style: amt, textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }
}

/// Small "LATEST" pill flagging the most recent row in a panel.
class _LatestBadge extends StatelessWidget {
  const _LatestBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: AppPalette.accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: AppPalette.accent.withValues(alpha: 0.35)),
      ),
      child: Text(
        'LATEST',
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
          color: AppPalette.accent,
        ),
      ),
    );
  }
}
