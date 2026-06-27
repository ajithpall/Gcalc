import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../models/trade_calculation.dart';
import '../models/pnl_record.dart';
import '../services/journal_service.dart';

class RecordScreen extends StatefulWidget {
  const RecordScreen({super.key});

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final JournalService _journalService = JournalService();

  List<PnlRecord> _records = [];
  bool _isLoading = true;

  // ─── Record Book filter: 'all' | 'closed' | 'open' ───────────
  String _recordFilter = 'all';

  final _currencyFormat =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
  final _dateFormat = DateFormat('dd MMM yyyy');

  // ─── Form state ───────────────────────────────────────────────
  final _stockController = TextEditingController();
  final _buyController = TextEditingController();
  final _sellController = TextEditingController();
  final _qtyController = TextEditingController();

  String _exchange = 'NSE';
  TradeType _tradeType = TradeType.intraday;
  TradeType _foSubType = TradeType.futures;
  DateTime _tradeDate = DateTime.now();
  DateTime? _sellDate;
  CalculationResult? _preview;

  // ─── Open position close-mode state ──────────────────────────
  PnlRecord? _selectedOpenPosition; // set when user picks from autocomplete

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _journalService.addListener(_onJournalChanged);
    _loadRecords();
    _buyController.addListener(_recalculate);
    _sellController.addListener(_recalculate);
    _qtyController.addListener(_recalculate);
  }

  @override
  void dispose() {
    _journalService.removeListener(_onJournalChanged);
    _tabController.dispose();
    _stockController.dispose();
    _buyController.dispose();
    _sellController.dispose();
    _qtyController.dispose();
    super.dispose();
  }

  void _onJournalChanged() {
    _loadRecords(silent: true);
  }

  Future<void> _loadRecords({bool silent = false}) async {
    if (!silent) {
      setState(() => _isLoading = true);
    }
    final records = await _journalService.loadPnlRecords();
    if (mounted) {
      setState(() {
        _records = records;
        _isLoading = false;
      });
    }
  }

  void _recalculate() {
    final b = double.tryParse(_buyController.text) ?? 0.0;
    final s = double.tryParse(_sellController.text) ?? 0.0;
    final q = int.tryParse(_qtyController.text) ?? 0;

    // For delivery: sell is optional — only preview when sell is filled
    if (b > 0 && s > 0 && q > 0) {
      setState(() => _preview = calculateGrowwCharges(
          type: _tradeType,
          buyPrice: b,
          sellPrice: s,
          quantity: q,
          isNSE: _exchange == 'NSE'));
    } else {
      setState(() => _preview = null);
    }
  }

  /// Called when user picks an open position from the autocomplete.
  void _selectOpenPosition(PnlRecord record) {
    setState(() {
      _selectedOpenPosition = record;
      _stockController.text = record.stockName;
      _buyController.text = record.buyPrice.toString();
      _qtyController.text = record.quantity.toString();
      _tradeDate = record.date;
      _exchange = record.exchange;
      _sellController.clear();
      _preview = null;
    });
  }

  void _clearOpenPositionSelection() {
    setState(() {
      _selectedOpenPosition = null;
      _stockController.clear();
      _buyController.clear();
      _qtyController.clear();
      _sellController.clear();
      _tradeDate = DateTime.now();
      _preview = null;
    });
  }

  Future<void> _saveRecord() async {
    final stockName = _stockController.text.trim();
    final b = double.tryParse(_buyController.text) ?? 0.0;
    final q = int.tryParse(_qtyController.text) ?? 0;
    final s = double.tryParse(_sellController.text);

    // Validate mandatory fields
    if (stockName.isEmpty || b <= 0 || q <= 0) {
      _showSnack('Please fill Stock Name, Buy Price and Quantity.', isError: true);
      return;
    }

    // Non-delivery: sell is mandatory
    if (_tradeType != TradeType.delivery && (s == null || s <= 0)) {
      _showSnack('Please enter a valid Sell Price.', isError: true);
      return;
    }

    List<PnlRecord> updated;

    if (_tradeType == TradeType.delivery && (s == null || s <= 0)) {
      // ── OPEN delivery position (no sell yet) ──────────────────
      final record = PnlRecord.openPosition(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        buyDate: _tradeDate,
        exchange: _exchange,
        stockName: stockName,
        quantity: q,
        buyPrice: b,
      );
      updated = await _journalService.addPnlRecord(record);
      _showSnack('${record.stockName} logged as OPEN holding.', isOpen: true);
    } else if (_tradeType == TradeType.delivery &&
        _selectedOpenPosition != null &&
        s != null &&
        s > 0) {
      // ── Closing an existing open delivery position ────────────
      final effectiveSellDate = _sellDate ?? DateTime.now();
      updated = await _journalService.closePnlPosition(
        id: _selectedOpenPosition!.id,
        sellPrice: s,
        sellDate: effectiveSellDate,
        isNSE: _exchange == 'NSE',
      );
      _showSnack('${_selectedOpenPosition!.stockName} position CLOSED!');
    } else {
      // ── Normal CLOSED trade (any type, or delivery with sell) ──
      if (_preview == null) return;
      final record = PnlRecord.fromCalculation(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        date: _tradeDate,
        exchange: _exchange,
        stockName: stockName.isEmpty ? _tradeType.displayName : stockName,
        calc: _preview!,
        sellDate: _sellDate,
      );
      updated = await _journalService.addPnlRecord(record);
      _showSnack('${record.stockName} trade saved!');
    }

    setState(() => _records = updated);
    _clearFormFields();
  }

  void _clearFormFields() {
    _stockController.clear();
    _buyController.clear();
    _sellController.clear();
    _qtyController.clear();
    _tradeDate = DateTime.now();
    _sellDate = null;
    _preview = null;
    _selectedOpenPosition = null;
  }

  void _showSnack(String msg, {bool isError = false, bool isOpen = false}) {
    if (!mounted) return;
    final color = isError
        ? const Color(0xFFF43F5E)
        : isOpen
            ? const Color(0xFFF59E0B)
            : const Color(0xFF059669);
    final icon = isError
        ? Icons.error_outline
        : isOpen
            ? Icons.inventory_2_outlined
            : Icons.check_circle_outline;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          Icon(icon, color: Colors.white),
          const SizedBox(width: 8),
          Expanded(child: Text(msg)),
        ]),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _deleteRecord(String id) async {
    final updated = await _journalService.deletePnlRecord(id);
    setState(() => _records = updated);
  }

  // ─── Analytics helpers ────────────────────────────────────────

  List<PnlRecord> get _closedRecords =>
      _records.where((r) => r.status == PositionStatus.closed).toList();

  double get _totalNetPL =>
      _closedRecords.fold(0.0, (s, r) => s + r.netPL);
  double get _totalCharges =>
      _closedRecords.fold(0.0, (s, r) => s + r.totalCharges);
  int get _totalCount => _closedRecords.length;
  int get _openCount =>
      _records.where((r) => r.status == PositionStatus.open).length;
  double get _winRate {
    if (_closedRecords.isEmpty) return 0.0;
    return _closedRecords.where((r) => r.netPL > 0).length /
        _closedRecords.length *
        100;
  }

  List<PnlRecord> get _filteredRecords {
    switch (_recordFilter) {
      case 'closed':
        return _records.where((r) => r.status == PositionStatus.closed).toList();
      case 'open':
        return _records.where((r) => r.status == PositionStatus.open).toList();
      default:
        return _records;
    }
  }

  Map<String, double> get _monthlyPL {
    final map = <String, double>{};
    for (final r in _closedRecords) {
      final key = DateFormat('MMM yy').format(r.date);
      map[key] = (map[key] ?? 0) + r.netPL;
    }
    return map;
  }

  List<MapEntry<String, double>> get _topStocks {
    final map = <String, double>{};
    for (final r in _closedRecords) {
      map[r.stockName] = (map[r.stockName] ?? 0) + r.netPL;
    }
    final sorted = map.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(3).toList();
  }

  Map<TradeType, int> get _tradeTypeCount {
    final map = <TradeType, int>{};
    for (final r in _closedRecords) {
      map[r.tradeType] = (map[r.tradeType] ?? 0) + 1;
    }
    return map;
  }

  Map<TradeType, double> get _tradeTypePL {
    final map = <TradeType, double>{};
    for (final r in _closedRecords) {
      map[r.tradeType] = (map[r.tradeType] ?? 0) + r.netPL;
    }
    return map;
  }

  // ─── Build ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildTabBar(),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: Color(0xFF10B981)))
                  : TabBarView(
                      controller: _tabController,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        _buildBookRecordTab(),
                        _buildAnalyticsTab(),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Record Book',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -0.8,
                ),
              ),
              Row(
                children: [
                  Text(
                    '${_closedRecords.length} closed',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.5), fontSize: 13),
                  ),
                  if (_openCount > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$_openCount holding${_openCount > 1 ? 's' : ''}',
                        style: const TextStyle(
                            color: Color(0xFFF59E0B),
                            fontSize: 11,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF6366F1).withOpacity(0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.book_outlined,
                color: Color(0xFF6366F1), size: 22),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      height: 46,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          color: const Color(0xFF6366F1),
          borderRadius: BorderRadius.circular(10),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelStyle:
            const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        unselectedLabelStyle:
            const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white38,
        tabs: const [
          Tab(text: '📒  Book Record'),
          Tab(text: '📊  Analytics'),
        ],
      ),
    );
  }

  // ─── Book Record Tab ──────────────────────────────────────────

  Widget _buildBookRecordTab() {
    return RefreshIndicator(
      onRefresh: _loadRecords,
      color: const Color(0xFF10B981),
      backgroundColor: const Color(0xFF1E293B),
      child: SingleChildScrollView(
        physics:
            const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildEntryForm(),
            const SizedBox(height: 24),
            // ── Filter chips ──
            _buildRecordFilterChips(),
            const SizedBox(height: 14),
            if (_filteredRecords.isNotEmpty) ...[
              const Text(
                'TRADE RECORDS',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 12),
              ..._filteredRecords.map((r) => _buildRecordCard(r)),
            ] else
              _buildEmptyRecords(),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordFilterChips() {
    final filters = [
      ('all', 'All (${_records.length})', Icons.format_list_bulleted),
      ('closed', 'Closed (${_closedRecords.length})', Icons.check_circle_outline),
      ('open', 'Open Holdings ($_openCount)', Icons.inventory_2_outlined),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: filters.map((f) {
          final isSelected = _recordFilter == f.$1;
          final chipColor = f.$1 == 'open'
              ? const Color(0xFFF59E0B)
              : f.$1 == 'closed'
                  ? const Color(0xFF10B981)
                  : const Color(0xFF6366F1);
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => setState(() => _recordFilter = f.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? chipColor.withOpacity(0.15)
                      : const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected
                        ? chipColor.withOpacity(0.6)
                        : Colors.white.withOpacity(0.07),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(f.$3,
                        size: 13,
                        color: isSelected ? chipColor : Colors.white38),
                    const SizedBox(width: 6),
                    Text(
                      f.$2,
                      style: TextStyle(
                        color: isSelected ? chipColor : Colors.white38,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildEntryForm() {
    final isFO =
        _tradeType == TradeType.futures || _tradeType == TradeType.options;
    final isDelivery = _tradeType == TradeType.delivery;
    final isClosingMode = isDelivery && _selectedOpenPosition != null;
    final openPositions = _journalService.getOpenDeliveryPositions(_records);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isClosingMode
              ? const Color(0xFFF59E0B).withOpacity(0.5)
              : const Color(0xFF6366F1).withOpacity(0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isClosingMode
                    ? Icons.lock_open_outlined
                    : Icons.add_circle_outline,
                color: isClosingMode
                    ? const Color(0xFFF59E0B)
                    : const Color(0xFF6366F1),
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                isClosingMode
                    ? 'Close Position — ${_selectedOpenPosition!.stockName}'
                    : 'New Trade Entry',
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16),
              ),
              if (isClosingMode) ...[
                const Spacer(),
                GestureDetector(
                  onTap: _clearOpenPositionSelection,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.07),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('Clear',
                        style: TextStyle(
                            color: Colors.white38,
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 18),

          // ── Date picker (buy date) ──
          _buildSectionLabel('BUY DATE'),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _tradeDate,
                firstDate: DateTime(2020),
                lastDate: DateTime.now(),
                builder: (ctx, child) => Theme(
                  data: Theme.of(ctx).copyWith(
                    colorScheme: const ColorScheme.dark(
                      primary: Color(0xFF6366F1),
                      onPrimary: Colors.white,
                      surface: Color(0xFF1E293B),
                      onSurface: Colors.white,
                    ),
                  ),
                  child: child!,
                ),
              );
              if (picked != null) setState(() => _tradeDate = picked);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(12),
                border: isClosingMode
                    ? Border.all(
                        color: const Color(0xFFF59E0B).withOpacity(0.3))
                    : null,
              ),
              child: Row(
                children: [
                  Icon(Icons.calendar_today,
                      color: isClosingMode
                          ? const Color(0xFFF59E0B)
                          : const Color(0xFF6366F1),
                      size: 18),
                  const SizedBox(width: 12),
                  Text(
                    _dateFormat.format(_tradeDate),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  const Icon(Icons.edit_calendar_outlined,
                      color: Colors.white38, size: 16),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Exchange + Trade Type ──
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionLabel('EXCHANGE'),
                    const SizedBox(height: 8),
                    _buildToggle(
                      options: ['NSE', 'BSE'],
                      selected: _exchange,
                      color: const Color(0xFF6366F1),
                      onSelect: isClosingMode
                          ? (_) {}
                          : (v) => setState(() => _exchange = v),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionLabel('TRADE TYPE'),
                    const SizedBox(height: 8),
                    _buildTradeTypeSelector(isFO),
                  ],
                ),
              ),
            ],
          ),

          // F&O sub-selector
          if (isFO) ...[
            const SizedBox(height: 10),
            _buildToggle(
              options: ['Futures', 'Options'],
              selected:
                  _tradeType == TradeType.futures ? 'Futures' : 'Options',
              color: const Color(0xFF8B5CF6),
              onSelect: (v) {
                setState(() {
                  _tradeType =
                      v == 'Futures' ? TradeType.futures : TradeType.options;
                  _foSubType = _tradeType;
                  _recalculate();
                });
              },
            ),
          ],
          const SizedBox(height: 16),

          // ── Delivery: Open-position autocomplete search ──
          if (isDelivery && !isClosingMode && openPositions.isNotEmpty) ...[
            _buildSectionLabel('CLOSE AN OPEN POSITION?'),
            const SizedBox(height: 8),
            _buildOpenPositionAutocomplete(openPositions),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.info_outline,
                    color: Color(0xFFF59E0B), size: 12),
                const SizedBox(width: 4),
                Text(
                  'Search your open holdings to auto-fill buy details',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.4), fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],

          // ── Stock Name ──
          _buildSectionLabel(
              isClosingMode ? 'STOCK NAME (FROM OPEN POSITION)' : 'STOCK NAME'),
          const SizedBox(height: 8),
          _buildFormField(
            controller: _stockController,
            label: 'e.g., RELIANCE, NIFTY FUT',
            icon: Icons.show_chart,
            iconColor: const Color(0xFF10B981),
            caps: true,
            readOnly: isClosingMode,
          ),
          const SizedBox(height: 16),

          // ── Price & Qty row ──
          _buildSectionLabel('TRADE DETAILS'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildFormField(
                  controller: _buyController,
                  label: 'Buy Price ₹',
                  icon: Icons.arrow_downward,
                  iconColor: const Color(0xFF3B82F6),
                  isDecimal: true,
                  readOnly: isClosingMode,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildFormField(
                  controller: _sellController,
                  label: isDelivery ? 'Sell ₹ (opt.)' : 'Sell Price ₹',
                  icon: Icons.arrow_upward,
                  iconColor: isDelivery
                      ? const Color(0xFFF59E0B)
                      : const Color(0xFF8B5CF6),
                  isDecimal: true,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildFormField(
                  controller: _qtyController,
                  label: 'Qty',
                  icon: Icons.numbers,
                  iconColor: const Color(0xFFF59E0B),
                  readOnly: isClosingMode,
                ),
              ),
            ],
          ),

          // ── Delivery: optional sell date when sell is filled ──
          if (isDelivery) ...[
            const SizedBox(height: 12),
            _buildSectionLabel('SELL DATE (OPTIONAL — leave blank for today)'),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _sellDate ?? DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                  builder: (ctx, child) => Theme(
                    data: Theme.of(ctx).copyWith(
                      colorScheme: const ColorScheme.dark(
                        primary: Color(0xFFF59E0B),
                        onPrimary: Colors.white,
                        surface: Color(0xFF1E293B),
                        onSurface: Colors.white,
                      ),
                    ),
                    child: child!,
                  ),
                );
                if (picked != null) setState(() => _sellDate = picked);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: _sellDate != null
                          ? const Color(0xFFF59E0B).withOpacity(0.4)
                          : Colors.transparent),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.event_available,
                        color: Color(0xFFF59E0B), size: 16),
                    const SizedBox(width: 10),
                    Text(
                      _sellDate != null
                          ? _dateFormat.format(_sellDate!)
                          : 'Tap to set sell date (default: today)',
                      style: TextStyle(
                          color: _sellDate != null
                              ? Colors.white
                              : Colors.white38,
                          fontSize: 13,
                          fontWeight: _sellDate != null
                              ? FontWeight.w600
                              : FontWeight.normal),
                    ),
                    const Spacer(),
                    if (_sellDate != null)
                      GestureDetector(
                        onTap: () => setState(() => _sellDate = null),
                        child: const Icon(Icons.close,
                            color: Colors.white38, size: 14),
                      ),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 14),

          // ── Delivery open-position info banner ──
          if (isDelivery &&
              (double.tryParse(_sellController.text) == null ||
                  double.tryParse(_sellController.text) == 0)) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: const Color(0xFFF59E0B).withOpacity(0.25)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.inventory_2_outlined,
                      color: Color(0xFFF59E0B), size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Leave Sell Price blank to log as OPEN holding. Fill it to record a closed trade.',
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.6),
                          fontSize: 11,
                          height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],

          // ── Live preview ──
          if (_preview != null) ...[
            _buildChargesPreview(_preview!),
            const SizedBox(height: 14),
          ],

          // ── Save button ──
          _buildSaveButton(isDelivery, isClosingMode),
        ],
      ),
    );
  }

  Widget _buildOpenPositionAutocomplete(List<PnlRecord> openPositions) {
    return Autocomplete<PnlRecord>(
      optionsBuilder: (TextEditingValue textEditingValue) {
        if (textEditingValue.text.isEmpty) return openPositions;
        final query = textEditingValue.text.toLowerCase();
        return openPositions
            .where((r) => r.stockName.toLowerCase().contains(query))
            .toList();
      },
      displayStringForOption: (r) => r.stockName,
      onSelected: _selectOpenPosition,
      fieldViewBuilder:
          (context, textController, focusNode, onFieldSubmitted) {
        return TextField(
          controller: textController,
          focusNode: focusNode,
          style: const TextStyle(
              color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            labelText: 'Search open positions...',
            labelStyle:
                const TextStyle(color: Colors.white38, fontSize: 12),
            prefixIcon: const Icon(Icons.search,
                color: Color(0xFFF59E0B), size: 18),
            filled: true,
            fillColor: const Color(0xFF0F172A),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                  color: Color(0xFFF59E0B), width: 1.5),
            ),
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(14),
            elevation: 8,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView.builder(
                padding: const EdgeInsets.all(6),
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final record = options.elementAt(index);
                  return GestureDetector(
                    onTap: () => onSelected(record),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 4),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF59E0B).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.inventory_2_outlined,
                                color: Color(0xFFF59E0B), size: 14),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  record.stockName,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13),
                                ),
                                Text(
                                  'Qty: ${record.quantity} · Buy: ${_currencyFormat.format(record.buyPrice)} · ${_dateFormat.format(record.date)}',
                                  style: const TextStyle(
                                      color: Colors.white38, fontSize: 10),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.arrow_forward_ios,
                              color: Color(0xFFF59E0B), size: 12),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSaveButton(bool isDelivery, bool isClosingMode) {
    final sellText = _sellController.text;
    final hasSell = sellText.isNotEmpty &&
        (double.tryParse(sellText) ?? 0) > 0;
    final hasBasics = _stockController.text.trim().isNotEmpty &&
        (_buyController.text.isNotEmpty &&
            (double.tryParse(_buyController.text) ?? 0) > 0) &&
        (_qtyController.text.isNotEmpty &&
            (int.tryParse(_qtyController.text) ?? 0) > 0);

    // Delivery: enabled if basics filled (sell optional)
    // Non-delivery: enabled only if preview is ready
    final isEnabled = isDelivery ? hasBasics : (_preview != null);

    String buttonLabel;
    Color buttonColor;
    IconData buttonIcon;

    if (isClosingMode) {
      buttonLabel = hasSell ? 'Close Position & Save P&L' : 'Save (needs sell price)';
      buttonColor = hasSell
          ? const Color(0xFFF59E0B)
          : const Color(0xFF334155);
      buttonIcon = Icons.lock_outline;
    } else if (isDelivery && !hasSell) {
      buttonLabel = 'Save as OPEN Holding';
      buttonColor = hasBasics
          ? const Color(0xFFF59E0B)
          : const Color(0xFF334155);
      buttonIcon = Icons.inventory_2_outlined;
    } else {
      buttonLabel = 'Save Record';
      buttonColor = isEnabled
          ? const Color(0xFF6366F1)
          : const Color(0xFF334155);
      buttonIcon = Icons.save_alt_outlined;
    }

    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        icon: Icon(buttonIcon, color: Colors.white, size: 20),
        label: Text(
          buttonLabel,
          style: const TextStyle(
              fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: buttonColor,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
          elevation: isEnabled ? 8 : 0,
          shadowColor: buttonColor.withOpacity(0.4),
        ),
        onPressed: isEnabled ? _saveRecord : null,
      ),
    );
  }

  Widget _buildSectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white38,
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.1,
      ),
    );
  }

  Widget _buildToggle({
    required List<String> options,
    required String selected,
    required Color color,
    required void Function(String) onSelect,
  }) {
    return Container(
      height: 40,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: options.map((opt) {
          final sel = selected == opt;
          return Expanded(
            child: GestureDetector(
              onTap: () => onSelect(opt),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  color: sel ? color : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Text(
                  opt,
                  style: TextStyle(
                    color: sel ? Colors.white : Colors.white38,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTradeTypeSelector(bool isFO) {
    return Container(
      height: 40,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          _typeChip('INT', TradeType.intraday, const Color(0xFF10B981), isFO),
          _typeChip('DEL', TradeType.delivery, const Color(0xFF3B82F6), isFO),
          _typeChipFO(isFO),
        ],
      ),
    );
  }

  Widget _typeChip(String label, TradeType type, Color color, bool isFO) {
    final sel = !isFO && _tradeType == type;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _tradeType = type;
            _selectedOpenPosition = null;
            _recalculate();
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: sel ? color : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: sel ? Colors.white : Colors.white38,
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
          ),
        ),
      ),
    );
  }

  Widget _typeChipFO(bool isFO) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _tradeType = _foSubType;
            _selectedOpenPosition = null;
            _recalculate();
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: isFO ? const Color(0xFF8B5CF6) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Text(
            'F&O',
            style: TextStyle(
              color: isFO ? Colors.white : Colors.white38,
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFormField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required Color iconColor,
    bool isDecimal = false,
    bool caps = false,
    bool readOnly = false,
  }) {
    return TextField(
      controller: controller,
      readOnly: readOnly,
      keyboardType: isDecimal
          ? const TextInputType.numberWithOptions(decimal: true)
          : (caps ? TextInputType.text : TextInputType.number),
      textCapitalization:
          caps ? TextCapitalization.characters : TextCapitalization.none,
      style: TextStyle(
          color: readOnly ? Colors.white54 : Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white38, fontSize: 12),
        prefixIcon: Icon(icon,
            color: readOnly ? iconColor.withOpacity(0.5) : iconColor,
            size: 18),
        filled: true,
        fillColor: readOnly
            ? const Color(0xFF0F172A).withOpacity(0.5)
            : const Color(0xFF0F172A),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF6366F1), width: 1.5),
        ),
      ),
    );
  }

  Widget _buildChargesPreview(CalculationResult calc) {
    final isProfit = calc.netPL >= 0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isProfit
              ? const Color(0xFF10B981).withOpacity(0.3)
              : const Color(0xFFF43F5E).withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long_outlined,
                  color: Colors.white38, size: 14),
              const SizedBox(width: 6),
              const Text('CHARGES PREVIEW',
                  style: TextStyle(
                      color: Colors.white38,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _previewStat('Turnover', calc.turnover),
              _previewStat('Gross P&L', calc.grossPL,
                  color: calc.grossPL >= 0
                      ? const Color(0xFF10B981)
                      : const Color(0xFFF43F5E)),
              _previewStat('Charges', calc.totalCharges,
                  color: const Color(0xFFF59E0B)),
              _previewStat('Net P&L', calc.netPL,
                  color: isProfit
                      ? const Color(0xFF10B981)
                      : const Color(0xFFF43F5E),
                  bold: true),
            ],
          ),
          const Divider(color: Color(0xFF334155), height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              _chargePill('Brokerage', _currencyFormat.format(calc.growwCharges)),
              _chargePill('STT', _currencyFormat.format(calc.stt)),
              _chargePill('Exch.', _currencyFormat.format(calc.exchangeCharges)),
              _chargePill('SEBI', _currencyFormat.format(calc.sebiFees)),
              if (calc.dpCharges > 0)
                _chargePill('DP', _currencyFormat.format(calc.dpCharges)),
              _chargePill('Stamp', _currencyFormat.format(calc.stampDuty)),
              _chargePill('GST', _currencyFormat.format(calc.gst)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _previewStat(String label, double value,
      {Color? color, bool bold = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(color: Colors.white38, fontSize: 10)),
        const SizedBox(height: 3),
        Text(
          _currencyFormat.format(value),
          style: TextStyle(
            color: color ?? Colors.white70,
            fontWeight: bold ? FontWeight.w900 : FontWeight.bold,
            fontSize: bold ? 13 : 11,
          ),
        ),
      ],
    );
  }

  Widget _chargePill(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(8),
      ),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
                text: '$label: ',
                style: const TextStyle(color: Colors.white38, fontSize: 10)),
            TextSpan(
                text: value,
                style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                    fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteRecord(PnlRecord record) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Delete Trade', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Are you sure you want to delete this trade?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _deleteRecord(record.id);
              _showSnack('Trade record deleted.');
            },
            child: const Text(
              'Delete',
              style: TextStyle(color: Color(0xFFF43F5E), fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  void _openEditTradeDialog(PnlRecord record) {
    final editStockController = TextEditingController(text: record.stockName);
    final editQtyController = TextEditingController(text: record.quantity.toString());
    final editBuyController = TextEditingController(text: record.buyPrice.toString());
    final editSellController = TextEditingController(text: record.sellPrice?.toString() ?? '');

    String editExchange = record.exchange;
    TradeType editTradeType = record.tradeType;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 24.0,
                right: 24.0,
                top: 24.0,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24.0,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Edit Trade Record',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white60),
                          onPressed: () => Navigator.pop(sheetContext),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildSectionLabel('EXCHANGE'),
                              const SizedBox(height: 8),
                              _buildToggle(
                                options: const ['NSE', 'BSE'],
                                selected: editExchange,
                                color: const Color(0xFF6366F1),
                                onSelect: (v) => setModalState(() => editExchange = v),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildSectionLabel('SEGMENT'),
                              const SizedBox(height: 8),
                              DropdownButtonFormField<TradeType>(
                                value: editTradeType,
                                dropdownColor: const Color(0xFF1E293B),
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: const Color(0xFF0F172A),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                                items: TradeType.values.map((type) {
                                  return DropdownMenuItem<TradeType>(
                                    value: type,
                                    child: Text(type.displayName),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    setModalState(() => editTradeType = val);
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildSectionLabel('STOCK NAME'),
                    const SizedBox(height: 8),
                    _buildFormField(
                      controller: editStockController,
                      label: 'Stock Name',
                      icon: Icons.show_chart,
                      iconColor: const Color(0xFF10B981),
                      caps: true,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _buildFormField(
                            controller: editBuyController,
                            label: 'Buy Price ₹',
                            icon: Icons.arrow_downward,
                            iconColor: const Color(0xFF3B82F6),
                            isDecimal: true,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildFormField(
                            controller: editSellController,
                            label: editTradeType == TradeType.delivery ? 'Sell ₹ (opt.)' : 'Sell Price ₹',
                            icon: Icons.arrow_upward,
                            iconColor: editTradeType == TradeType.delivery
                                ? const Color(0xFFF59E0B)
                                : const Color(0xFF8B5CF6),
                            isDecimal: true,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildFormField(
                            controller: editQtyController,
                            label: 'Qty',
                            icon: Icons.numbers,
                            iconColor: const Color(0xFFF59E0B),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.save_alt_outlined, color: Colors.white, size: 20),
                        label: const Text(
                          'Save Changes',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6366F1),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 8,
                          shadowColor: const Color(0xFF6366F1).withOpacity(0.4),
                        ),
                        onPressed: () async {
                          final stockName = editStockController.text.trim();
                          final b = double.tryParse(editBuyController.text) ?? 0.0;
                          final q = int.tryParse(editQtyController.text) ?? 0;
                          final s = double.tryParse(editSellController.text);

                          if (stockName.isEmpty || b <= 0 || q <= 0) {
                            _showSnack('Please fill Stock Name, Buy Price and Quantity.', isError: true);
                            return;
                          }

                          if (editTradeType != TradeType.delivery && (s == null || s <= 0)) {
                            _showSnack('Please enter a valid Sell Price.', isError: true);
                            return;
                          }

                          PnlRecord updatedRecord;
                          if (editTradeType == TradeType.delivery && (s == null || s <= 0)) {
                            updatedRecord = PnlRecord(
                              id: record.id,
                              date: record.date,
                              exchange: editExchange,
                              stockName: stockName,
                              quantity: q,
                              buyPrice: b,
                              sellPrice: null,
                              sellDate: null,
                              tradeType: TradeType.delivery,
                              grossPL: 0.0,
                              totalCharges: 0.0,
                              netPL: 0.0,
                              status: PositionStatus.open,
                            );
                          } else {
                            final calc = calculateGrowwCharges(
                              type: editTradeType,
                              quantity: q,
                              buyPrice: b,
                              sellPrice: s ?? 0.0,
                              isNSE: editExchange == 'NSE',
                            );

                            updatedRecord = PnlRecord(
                              id: record.id,
                              date: record.date,
                              exchange: editExchange,
                              stockName: stockName,
                              quantity: q,
                              buyPrice: b,
                              sellPrice: s,
                              sellDate: record.sellDate ?? DateTime.now(),
                              tradeType: editTradeType,
                              grossPL: calc.grossPL,
                              totalCharges: calc.totalCharges,
                              netPL: calc.netPL,
                              status: PositionStatus.closed,
                            );
                          }

                          final navigator = Navigator.of(sheetContext);
                          final updatedList = await _journalService.updatePnlRecord(updatedRecord);
                          if (!mounted) return;
                          setState(() {
                            _records = updatedList;
                          });
                          navigator.pop();
                          _showSnack('Trade changes saved successfully!');
                        },
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPopupMenuButton(PnlRecord record) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, color: Colors.white70),
      color: const Color(0xFF1E293B),
      onSelected: (value) {
        if (value == 'edit') {
          _openEditTradeDialog(record);
        } else if (value == 'delete') {
          _confirmDeleteRecord(record);
        }
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        const PopupMenuItem<String>(
          value: 'edit',
          child: Text('Edit'),
        ),
        const PopupMenuItem<String>(
          value: 'delete',
          child: Text('Delete', style: TextStyle(color: Colors.red)),
        ),
      ],
    );
  }

  Widget _buildRecordCard(PnlRecord record) {
    final isOpen = record.status == PositionStatus.open;
    final isProfit = record.netPL >= 0;
    final cardColor = isOpen
        ? const Color(0xFFF59E0B)
        : isProfit
            ? const Color(0xFF10B981)
            : const Color(0xFFF43F5E);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cardColor.withOpacity(isOpen ? 0.4 : 0.15)),
        boxShadow: isOpen
            ? [
                BoxShadow(
                  color: const Color(0xFFF59E0B).withOpacity(0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                )
              ]
            : null,
      ),
      child: InkWell(
        onTap: () {
          showModalBottomSheet(
            context: context,
            backgroundColor: const Color(0xFF1A1F2C),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            builder: (context) => DetailedChargesModal(record: record),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: isOpen
            ? _buildOpenPositionCardContent(record)
            : _buildClosedPositionCardContent(record, isProfit, cardColor),
      ),
    );
  }

  Widget _buildOpenPositionCardContent(PnlRecord record) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row — responsive layout
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Left side: stock details with text safety
              Expanded(
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('HOLDING',
                          style: TextStyle(
                              color: Color(0xFFF59E0B),
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                              letterSpacing: 0.5)),
                    ),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 160),
                      child: Text(
                        record.stockName,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15),
                      ),
                    ),
                    _badge(record.exchange, const Color(0xFF6366F1)),
                    _badge('Delivery', const Color(0xFF3B82F6)),
                  ],
                ),
              ),
              // Right side: stays intact on all screen sizes
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildPopupMenuButton(record),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Buy details
          Wrap(
            spacing: 20,
            runSpacing: 8,
            children: [
              _recordDetail(
                  'Buy Price', _currencyFormat.format(record.buyPrice)),
              _recordDetail('Qty', record.quantity.toString()),
              _recordDetail('Buy Date', _dateFormat.format(record.date)),
            ],
          ),
          const SizedBox(height: 12),

          // Info + Close button
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withOpacity(0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: const Color(0xFFF59E0B).withOpacity(0.2)),
            ),
            child: Row(
              children: [
                const Icon(Icons.inventory_2_outlined,
                    color: Color(0xFFF59E0B), size: 14),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Un-sold position · No P&L realized yet',
                    style: TextStyle(color: Color(0xFFF59E0B), fontSize: 11),
                  ),
                ),
                GestureDetector(
                  onTap: () => _openClosePositionForm(record),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'SELL / CLOSE',
                      style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w800,
                          fontSize: 10,
                          letterSpacing: 0.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openClosePositionForm(PnlRecord record) {
    // Switch tab to book record, pre-select Delivery, select the open position
    _tabController.animateTo(0);
    setState(() {
      _tradeType = TradeType.delivery;
      _selectOpenPosition(record);
    });
    // Scroll to top
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          const Icon(Icons.arrow_upward, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Text('Enter sell price above to close ${record.stockName}'),
        ]),
        backgroundColor: const Color(0xFFF59E0B),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Widget _buildClosedPositionCardContent(
      PnlRecord record, bool isProfit, Color profitColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row — responsive layout
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Left side: stock name + badges with text safety
              Expanded(
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 160),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: profitColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          record.stockName,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                          style: TextStyle(
                              color: profitColor,
                              fontWeight: FontWeight.w800,
                              fontSize: 13),
                        ),
                      ),
                    ),
                    _badge(record.exchange, const Color(0xFF6366F1)),
                    _badge(_tradeTypeShort(record.tradeType), Colors.white24,
                        textColor: Colors.white54),
                  ],
                ),
              ),
              // Right side: date + menu — stays intact on all screen sizes
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _dateFormat.format(record.date),
                    style:
                        const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                  _buildPopupMenuButton(record),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _recordDetail('Buy', _currencyFormat.format(record.buyPrice)),
              _recordDetail(
                  'Sell', _currencyFormat.format(record.sellPrice ?? 0)),
              _recordDetail('Qty', record.quantity.toString()),
              if (record.sellDate != null)
                _recordDetail('Sold', _dateFormat.format(record.sellDate!)),
            ],
          ),
          const Divider(color: Color(0xFF334155), height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _plStat('Gross P&L', record.grossPL,
                  record.grossPL >= 0
                      ? const Color(0xFF10B981)
                      : const Color(0xFFF43F5E)),
              _plStat('Charges', record.totalCharges,
                  const Color(0xFFF59E0B)),
              _plStat('Net P&L', record.netPL, profitColor, big: true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _badge(String text, Color bg, {Color? textColor}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text,
          style: TextStyle(
              color: textColor ?? bg,
              fontSize: 10,
              fontWeight: FontWeight.bold)),
    );
  }

  Widget _recordDetail(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(color: Colors.white38, fontSize: 10)),
        Text(value,
            style: const TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.bold,
                fontSize: 12)),
      ],
    );
  }

  Widget _plStat(String label, double value, Color color,
      {bool big = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(color: Colors.white38, fontSize: 10)),
        const SizedBox(height: 2),
        Text(
          _currencyFormat.format(value),
          style: TextStyle(
            color: color,
            fontWeight: big ? FontWeight.w900 : FontWeight.bold,
            fontSize: big ? 14 : 12,
          ),
        ),
      ],
    );
  }

  String _tradeTypeShort(TradeType t) {
    switch (t) {
      case TradeType.intraday:
        return 'Intraday';
      case TradeType.delivery:
        return 'Delivery';
      case TradeType.futures:
        return 'Futures';
      case TradeType.options:
        return 'Options';
    }
  }

  Widget _buildEmptyRecords() {
    final isFilteredEmpty = _recordFilter != 'all' && _records.isNotEmpty;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40.0),
        child: Column(
          children: [
            Icon(
              isFilteredEmpty
                  ? Icons.filter_list_off
                  : Icons.note_add_outlined,
              size: 64,
              color: Colors.white.withOpacity(0.12),
            ),
            const SizedBox(height: 16),
            Text(
              isFilteredEmpty
                  ? 'No ${_recordFilter == 'open' ? 'open holdings' : 'closed transactions'}'
                  : 'No records yet',
              style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              isFilteredEmpty
                  ? 'Switch filter to All to see all records'
                  : 'Fill the form above and tap "Save Record"',
              style: TextStyle(
                  color: Colors.white.withOpacity(0.4), fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ─── Analytics Tab ────────────────────────────────────────────

  Widget _buildAnalyticsTab() {
    if (_records.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bar_chart_outlined,
                size: 72, color: Colors.white.withOpacity(0.12)),
            const SizedBox(height: 16),
            const Text('No data yet',
                style: TextStyle(
                    color: Colors.white70,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Add trades in Book Record to see analytics',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.4), fontSize: 13)),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_openCount > 0) _buildOpenHoldingsBanner(),
          const SizedBox(height: 16),
          _buildOverallBanner(),
          const SizedBox(height: 16),
          _buildStatsGrid(),
          const SizedBox(height: 20),
          _buildMonthlyChart(),
          const SizedBox(height: 20),
          _buildTopStocksSection(),
          const SizedBox(height: 20),
          _buildTradeTypeBreakdown(),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildOpenHoldingsBanner() {
    final openRecords =
        _records.where((r) => r.status == PositionStatus.open).toList();
    final totalBuyValue = openRecords.fold(
        0.0, (s, r) => s + r.buyPrice * r.quantity);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF92400E), Color(0xFFB45309)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF59E0B).withOpacity(0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.inventory_2_outlined,
              color: Color(0xFFFCD34D), size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$_openCount Open Holding${_openCount > 1 ? 's' : ''}',
                  style: const TextStyle(
                      color: Color(0xFFFCD34D),
                      fontWeight: FontWeight.w800,
                      fontSize: 15),
                ),
                Text(
                  'Total invested: ${_currencyFormat.format(totalBuyValue)}',
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () {
              setState(() => _recordFilter = 'open');
              _tabController.animateTo(0);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFFCD34D),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'VIEW',
                style: TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.w800,
                    fontSize: 11),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverallBanner() {
    final isProfit = _totalNetPL >= 0;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isProfit
              ? [const Color(0xFF059669), const Color(0xFF10B981)]
              : [const Color(0xFFBE185D), const Color(0xFFF43F5E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: (isProfit
                        ? const Color(0xFF10B981)
                        : const Color(0xFFF43F5E))
                    .withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -10,
            top: -10,
            child: Icon(
              isProfit ? Icons.trending_up : Icons.trending_down,
              size: 120,
              color: Colors.white.withOpacity(0.08),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Realized Net P&L',
                  style: TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 6),
              Text(
                (isProfit ? '+' : '') + _currencyFormat.format(_totalNetPL),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 36,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _bannerPill('$_totalCount closed', Icons.swap_horiz),
                  const SizedBox(width: 10),
                  _bannerPill(
                      '${_winRate.toStringAsFixed(1)}% win rate',
                      Icons.emoji_events_outlined),
                  const SizedBox(width: 10),
                  _bannerPill(
                      _currencyFormat.format(_totalCharges) + ' charges',
                      Icons.receipt_outlined),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bannerPill(String text, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.white),
          const SizedBox(width: 5),
          Text(text,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildStatsGrid() {
    final profitTrades = _closedRecords.where((r) => r.netPL > 0).length;
    final lossTrades = _closedRecords.where((r) => r.netPL <= 0).length;
    final avgPL = _totalCount > 0 ? _totalNetPL / _totalCount : 0.0;
    final bestTrade = _closedRecords.isNotEmpty
        ? _closedRecords.reduce((a, b) => a.netPL > b.netPL ? a : b)
        : null;

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.7,
      children: [
        _statCard('Total Trades', _totalCount.toString(),
            Icons.swap_horiz_rounded, const Color(0xFF6366F1)),
        _statCard('Win Rate', '${_winRate.toStringAsFixed(1)}%',
            Icons.emoji_events_outlined, const Color(0xFF10B981)),
        _statCard('Profit Trades', profitTrades.toString(),
            Icons.thumb_up_outlined, const Color(0xFF10B981)),
        _statCard('Loss Trades', lossTrades.toString(),
            Icons.thumb_down_outlined, const Color(0xFFF43F5E)),
        _statCard('Avg. Trade P&L', _currencyFormat.format(avgPL),
            Icons.calculate_outlined,
            avgPL >= 0 ? const Color(0xFF10B981) : const Color(0xFFF43F5E)),
        _statCard(
            'Best Trade',
            bestTrade != null ? _currencyFormat.format(bestTrade.netPL) : '₹0',
            Icons.star_outline_rounded,
            const Color(0xFFF59E0B)),
      ],
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: color, size: 20),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value,
                  style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w800,
                      fontSize: 16)),
              Text(label,
                  style: const TextStyle(
                      color: Colors.white38, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMonthlyChart() {
    final monthly = _monthlyPL;
    if (monthly.isEmpty) return const SizedBox.shrink();

    final keys = monthly.keys.toList();
    final values = monthly.values.toList();
    final maxAbs =
        values.map((v) => v.abs()).reduce((a, b) => a > b ? a : b);
    final maxY = maxAbs == 0 ? 1.0 : maxAbs * 1.3;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Monthly P&L',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16)),
          const SizedBox(height: 4),
          Text('Realized profit / loss per month',
              style: TextStyle(
                  color: Colors.white.withOpacity(0.4), fontSize: 12)),
          const SizedBox(height: 20),
          SizedBox(
            height: 180,
            child: BarChart(
              BarChartData(
                maxY: maxY,
                minY: -maxY,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (v) => FlLine(
                    color: Colors.white.withOpacity(0.06),
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx < 0 || idx >= keys.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            keys[idx],
                            style: const TextStyle(
                                color: Colors.white38,
                                fontSize: 9,
                                fontWeight: FontWeight.w600),
                          ),
                        );
                      },
                      reservedSize: 28,
                    ),
                  ),
                ),
                barGroups: List.generate(values.length, (i) {
                  final v = values[i];
                  final isP = v >= 0;
                  return BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: v,
                        width: 18,
                        borderRadius: isP
                            ? const BorderRadius.vertical(
                                top: Radius.circular(6))
                            : const BorderRadius.vertical(
                                bottom: Radius.circular(6)),
                        gradient: LinearGradient(
                          colors: isP
                              ? [
                                  const Color(0xFF059669),
                                  const Color(0xFF10B981)
                                ]
                              : [
                                  const Color(0xFFBE185D),
                                  const Color(0xFFF43F5E)
                                ],
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                        ),
                      ),
                    ],
                  );
                }),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => const Color(0xFF0F172A),
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      return BarTooltipItem(
                        _currencyFormat.format(rod.toY),
                        TextStyle(
                          color: rod.toY >= 0
                              ? const Color(0xFF10B981)
                              : const Color(0xFFF43F5E),
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopStocksSection() {
    final top = _topStocks;
    if (top.isEmpty) return const SizedBox.shrink();

    final maxVal =
        top.map((e) => e.value.abs()).reduce((a, b) => a > b ? a : b);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.star_rounded,
                  color: Color(0xFFF59E0B), size: 20),
              const SizedBox(width: 8),
              const Text('Most Profitable Stocks',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
            ],
          ),
          const SizedBox(height: 16),
          ...top.asMap().entries.map((entry) {
            final i = entry.key;
            final stock = entry.value;
            final isProfit = stock.value >= 0;
            final pct = maxVal > 0 ? stock.value.abs() / maxVal : 0.0;
            final medals = ['🥇', '🥈', '🥉'];

            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Text(medals[i],
                              style: const TextStyle(fontSize: 16)),
                          const SizedBox(width: 8),
                          Text(stock.key,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14)),
                        ],
                      ),
                      Text(
                        (isProfit ? '+' : '') +
                            _currencyFormat.format(stock.value),
                        style: TextStyle(
                          color: isProfit
                              ? const Color(0xFF10B981)
                              : const Color(0xFFF43F5E),
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: pct,
                      minHeight: 6,
                      backgroundColor: Colors.white.withOpacity(0.07),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isProfit
                            ? const Color(0xFF10B981)
                            : const Color(0xFFF43F5E),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildTradeTypeBreakdown() {
    final counts = _tradeTypeCount;
    final pls = _tradeTypePL;

    final types = [
      (TradeType.intraday, 'Intraday', const Color(0xFF10B981),
          Icons.flash_on_rounded),
      (TradeType.delivery, 'Delivery', const Color(0xFF3B82F6),
          Icons.inventory_2_outlined),
      (TradeType.futures, 'Futures', const Color(0xFF8B5CF6),
          Icons.candlestick_chart_outlined),
      (TradeType.options, 'Options', const Color(0xFFEC4899),
          Icons.auto_graph),
    ];

    final active = types.where((t) => (counts[t.$1] ?? 0) > 0).toList();
    if (active.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Trade Type Breakdown',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16)),
          const SizedBox(height: 16),
          ...active.map((t) {
            final count = counts[t.$1] ?? 0;
            final pl = pls[t.$1] ?? 0.0;
            final isProfit = pl >= 0;
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: t.$3.withOpacity(0.07),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: t.$3.withOpacity(0.15)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: t.$3.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(t.$4, color: t.$3, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.$2,
                            style: TextStyle(
                                color: t.$3,
                                fontWeight: FontWeight.bold,
                                fontSize: 14)),
                        Text('$count trade${count > 1 ? 's' : ''}',
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 11)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        (isProfit ? '+' : '') + _currencyFormat.format(pl),
                        style: TextStyle(
                          color: isProfit
                              ? const Color(0xFF10B981)
                              : const Color(0xFFF43F5E),
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      const Text('Net P&L',
                          style: TextStyle(
                              color: Colors.white38, fontSize: 10)),
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class DetailedChargesModal extends StatelessWidget {
  final PnlRecord record;

  const DetailedChargesModal({super.key, required this.record});

  @override
  Widget build(BuildContext context) {
    final currencyFormat =
        NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
    final isOpen = record.status == PositionStatus.open;

    final calc = calculateGrowwCharges(
      type: record.tradeType,
      quantity: record.quantity,
      buyPrice: record.buyPrice,
      sellPrice: record.sellPrice ?? 0.0,
      isNSE: record.exchange == 'NSE',
    );

    final double turnover = calc.turnover;
    final double grossPL = isOpen ? 0.0 : calc.grossPL;
    final double netPL = isOpen ? 0.0 : calc.netPL;
    final double totalCharges = calc.totalCharges;

    String brokerageNote() {
      switch (record.tradeType) {
        case TradeType.delivery:
        case TradeType.intraday:
        case TradeType.futures:
          return '0.05% or ₹20 per order (whichever is lower)';
        case TradeType.options:
          return 'Flat ₹20 per buy + ₹20 per sell';
      }
    }

    String sttNote() {
      switch (record.tradeType) {
        case TradeType.delivery:
          return '0.1% on both buy & sell';
        case TradeType.intraday:
          return '0.025% on sell side only';
        case TradeType.futures:
          return '0.05% on sell side only';
        case TradeType.options:
          return '0.15% on sell premium';
      }
    }

    String exchangeNote() {
      switch (record.tradeType) {
        case TradeType.delivery:
        case TradeType.intraday:
          return '0.00297% of turnover (NSE)';
        case TradeType.futures:
          return '0.00173% of turnover (NSE)';
        case TradeType.options:
          return '0.03503% of premium turnover';
      }
    }

    String stampNote() {
      switch (record.tradeType) {
        case TradeType.delivery:
          return '0.015% on buy side';
        case TradeType.intraday:
          return '0.003% on buy side';
        case TradeType.futures:
          return '0.002% on buy side';
        case TradeType.options:
          return '0.003% on buy side';
      }
    }

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1A1F2C),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.all(24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Detailed Charges Breakdown',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isOpen ? 'Open position · Charges calculated on buy' : 'Where your money goes',
                      style: TextStyle(
                          color: Colors.white70, fontSize: 11),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white60),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),

            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _summaryCell('Turnover', currencyFormat.format(turnover), Colors.white70),
                  _vDivider(),
                  _summaryCell(
                      'Gross P&L',
                      currencyFormat.format(grossPL),
                      isOpen
                          ? Colors.white70
                          : (grossPL >= 0 ? const Color(0xFF10B981) : const Color(0xFFF43F5E))),
                  _vDivider(),
                  _summaryCell('Total Charges', currencyFormat.format(totalCharges), const Color(0xFFF43F5E)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Divider(color: Color(0xFF334155)),
            const SizedBox(height: 12),

            _sectionLabel('BROKER CHARGES (GROWW)'),
            const SizedBox(height: 10),
            _chargeRow(
              label: 'Brokerage',
              sublabel: brokerageNote(),
              value: calc.growwCharges,
              icon: Icons.business_center_outlined,
              color: const Color(0xFF6366F1),
              currencyFormat: currencyFormat,
            ),
            const SizedBox(height: 12),
            const Divider(color: Color(0xFF334155)),
            const SizedBox(height: 12),

            _sectionLabel('REGULATORY & EXCHANGE CHARGES'),
            const SizedBox(height: 10),
            _chargeRow(
              label: 'STT',
              sublabel: sttNote(),
              value: calc.stt,
              icon: Icons.account_balance_outlined,
              color: const Color(0xFFF59E0B),
              currencyFormat: currencyFormat,
            ),
            const SizedBox(height: 10),
            _chargeRow(
              label: 'Exchange Transaction Charges',
              sublabel: exchangeNote(),
              value: calc.exchangeCharges,
              icon: Icons.sync_alt,
              color: const Color(0xFF3B82F6),
              currencyFormat: currencyFormat,
            ),
            const SizedBox(height: 10),
            _chargeRow(
              label: 'SEBI Turnover Fees',
              sublabel: '₹10 per crore turnover',
              value: calc.sebiFees,
              icon: Icons.gavel_outlined,
              color: const Color(0xFF10B981),
              currencyFormat: currencyFormat,
            ),
            if (calc.dpCharges > 0) ...[
              const SizedBox(height: 10),
              _chargeRow(
                label: 'DP Charges',
                sublabel: '₹18.29 (GST incl.) on sell',
                value: calc.dpCharges,
                icon: Icons.account_balance_wallet_outlined,
                color: const Color(0xFFF97316),
                currencyFormat: currencyFormat,
              ),
            ],
            const SizedBox(height: 10),
            _chargeRow(
              label: 'Stamp Duty',
              sublabel: stampNote(),
              value: calc.stampDuty,
              icon: Icons.local_post_office_outlined,
              color: const Color(0xFFEC4899),
              currencyFormat: currencyFormat,
            ),
            const SizedBox(height: 10),
            _chargeRow(
              label: 'GST',
              sublabel: '18% on brokerage + exchange + SEBI',
              value: calc.gst,
              icon: Icons.receipt_outlined,
              color: const Color(0xFF8B5CF6),
              currencyFormat: currencyFormat,
            ),
            const SizedBox(height: 16),
            const Divider(color: Color(0xFF334155)),
            const SizedBox(height: 14),

            _totalChargesRow(isOpen, netPL, currencyFormat),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white38,
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.1,
      ),
    );
  }

  Widget _summaryCell(String label, String value, Color valueColor) {
    return Expanded(
      child: Column(
        children: [
          Text(label,
              style: const TextStyle(color: Colors.white38, fontSize: 10),
              textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  color: valueColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 12),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget _vDivider() {
    return Container(
        width: 1, height: 32, color: Colors.white.withValues(alpha: 0.08));
  }

  Widget _chargeRow({
    required String label,
    required String sublabel,
    required double value,
    required IconData icon,
    required Color color,
    required NumberFormat currencyFormat,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
              Text(sublabel,
                  style: const TextStyle(
                      color: Colors.white38, fontSize: 10)),
            ],
          ),
        ),
        Text(
          currencyFormat.format(value),
          style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 13),
        ),
      ],
    );
  }

  Widget _totalChargesRow(bool isOpen, double netPL, NumberFormat currencyFormat) {
    final isProfit = netPL >= 0;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(isOpen ? 'Estimated Net P&L' : 'Net P&L',
                style: const TextStyle(
                    color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
            Text(
              isOpen ? 'If sold at current price (₹0)' : '${isProfit ? 'Profit' : 'Loss'} after all charges',
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
        ),
        Text(
          isOpen ? 'N/A' : '${isProfit ? '+' : ''}${currencyFormat.format(netPL)}',
          style: TextStyle(
            color: isOpen
                ? Colors.white70
                : (isProfit ? const Color(0xFF10B981) : const Color(0xFFF43F5E)),
            fontWeight: FontWeight.w900,
            fontSize: 22,
            letterSpacing: -0.5,
          ),
        ),
      ],
    );
  }
}
