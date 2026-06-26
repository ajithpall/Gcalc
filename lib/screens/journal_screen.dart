import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/trade_calculation.dart';
import '../models/trade_log.dart';
import '../models/pnl_record.dart' show PositionStatus;
import '../services/journal_service.dart';

class JournalScreen extends StatefulWidget {
  const JournalScreen({super.key});

  @override
  State<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends State<JournalScreen> {
  final JournalService _journalService = JournalService();

  List<TradeLog> _allTrades = [];
  List<TradeLog> _filteredTrades = [];
  bool _isLoading = true;

  String _searchQuery = '';
  TradeType? _selectedTypeFilter;
  // 'all' | 'closed' | 'open'
  String _statusFilter = 'all';

  final _currencyFormat =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
  final _dateFormat = DateFormat('dd MMM yyyy');

  // ─── Manual entry form controllers ───────────────────────────
  final _symbolController = TextEditingController();
  final _buyController = TextEditingController();
  final _sellController = TextEditingController();
  final _qtyController = TextEditingController();
  final _noteController = TextEditingController();
  TradeType _manualType = TradeType.intraday;
  DateTime _manualDate = DateTime.now();
  DateTime? _manualSellDate;

  // ─── Open position selection for close-mode ───────────────────
  TradeLog? _selectedOpenTrade;

  @override
  void initState() {
    super.initState();
    _journalService.addListener(_onJournalChanged);
    _loadTrades();
  }

  @override
  void dispose() {
    _journalService.removeListener(_onJournalChanged);
    _symbolController.dispose();
    _buyController.dispose();
    _sellController.dispose();
    _qtyController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _onJournalChanged() {
    _loadTrades(silent: true);
  }

  Future<void> _loadTrades({bool silent = false}) async {
    if (!silent) {
      setState(() => _isLoading = true);
    }
    final trades = await _journalService.loadTrades();
    if (mounted) {
      setState(() {
        _allTrades = trades;
        _isLoading = false;
        _applyFilters();
      });
    }
  }

  void _applyFilters() {
    setState(() {
      _filteredTrades = _allTrades.where((trade) {
        // Status filter
        if (_statusFilter == 'open' &&
            trade.status != PositionStatus.open) return false;
        if (_statusFilter == 'closed' &&
            trade.status != PositionStatus.closed) return false;

        // Type filter
        if (_selectedTypeFilter != null &&
            trade.type != _selectedTypeFilter) return false;

        // Search query
        if (_searchQuery.isNotEmpty) {
          final query = _searchQuery.toLowerCase();
          final matchesSymbol = trade.symbol.toLowerCase().contains(query);
          final matchesNote = trade.note.toLowerCase().contains(query);
          return matchesSymbol || matchesNote;
        }
        return true;
      }).toList();
    });
  }

  // ─── Metrics ─────────────────────────────────────────────────
  List<TradeLog> get _closedTrades =>
      _allTrades.where((t) => t.status == PositionStatus.closed).toList();
  int get _openCount =>
      _allTrades.where((t) => t.status == PositionStatus.open).length;

  double get _totalNetPL =>
      _closedTrades.fold(0.0, (sum, item) => sum + item.netPL);
  double get _totalCharges =>
      _closedTrades.fold(0.0, (sum, item) => sum + item.totalCharges);
  double get _winRate {
    if (_closedTrades.isEmpty) return 0.0;
    final wins = _closedTrades.where((t) => t.netPL > 0).length;
    return (wins / _closedTrades.length) * 100.0;
  }

  // ─── Delete ───────────────────────────────────────────────────
  Future<void> _deleteTrade(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Delete Trade Log?',
            style: TextStyle(color: Colors.white)),
        content: const Text('This action cannot be undone. Are you sure?',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:
                const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete',
                style: TextStyle(
                    color: Color(0xFFF43F5E), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final updated = await _journalService.deleteTrade(id);
      setState(() {
        _allTrades = updated;
        _applyFilters();
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Trade log deleted.'),
            backgroundColor: const Color(0xFF334155),
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  // ─── Manual entry sheet ───────────────────────────────────────
  void _showManualEntrySheet() {
    _symbolController.clear();
    _buyController.clear();
    _sellController.clear();
    _qtyController.clear();
    _noteController.clear();
    _manualType = TradeType.intraday;
    _manualDate = DateTime.now();
    _manualSellDate = null;
    _selectedOpenTrade = null;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final isDelivery = _manualType == TradeType.delivery;
            final isClosingMode =
                isDelivery && _selectedOpenTrade != null;
            final openTrades =
                _journalService.getOpenDeliveryTrades(_allTrades);

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
                    // ── Header ──
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isClosingMode
                                    ? 'Close Position'
                                    : 'Manual Trade Entry',
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              if (isClosingMode)
                                Text(
                                  _selectedOpenTrade!.symbol,
                                  style: const TextStyle(
                                      color: Color(0xFFF59E0B),
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13),
                                ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white60),
                          onPressed: () => Navigator.pop(sheetContext),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ── Trade Type Selector ──
                    DropdownButtonFormField<TradeType>(
                      value: _manualType,
                      dropdownColor: const Color(0xFF1E293B),
                      decoration: InputDecoration(
                        labelText: 'Trade Type',
                        labelStyle: const TextStyle(color: Colors.white70),
                        filled: true,
                        fillColor: const Color(0xFF0F172A),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none),
                      ),
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w500),
                      items: TradeType.values.map((type) {
                        return DropdownMenuItem(
                          value: type,
                          child: Text(type.displayName),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setSheetState(() {
                            _manualType = val;
                            _selectedOpenTrade = null;
                            _symbolController.clear();
                            _buyController.clear();
                            _qtyController.clear();
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),

                    // ── Delivery: search autocomplete for open positions ──
                    if (isDelivery &&
                        !isClosingMode &&
                        openTrades.isNotEmpty) ...[
                      const Text(
                        'CLOSE AN OPEN POSITION?',
                        style: TextStyle(
                            color: Colors.white38,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.1),
                      ),
                      const SizedBox(height: 8),
                      _buildSheetAutocomplete(
                          openTrades, setSheetState, isClosingMode),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.info_outline,
                              color: Color(0xFFF59E0B), size: 12),
                          const SizedBox(width: 4),
                          Text(
                            'Select to auto-fill buy details',
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.4),
                                fontSize: 11),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],

                    // ── Clear close mode button ──
                    if (isClosingMode) ...[
                      GestureDetector(
                        onTap: () => setSheetState(() {
                          _selectedOpenTrade = null;
                          _symbolController.clear();
                          _buyController.clear();
                          _qtyController.clear();
                          _manualDate = DateTime.now();
                        }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.close,
                                  color: Colors.white38, size: 14),
                              const SizedBox(width: 6),
                              const Text('Clear selection',
                                  style: TextStyle(
                                      color: Colors.white38,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // ── Stock symbol ──
                    _buildSheetField(
                      controller: _symbolController,
                      label: isDelivery
                          ? 'Stock Name (mandatory)'
                          : 'Stock Ticker / Symbol',
                      hint: 'e.g., RELIANCE',
                      caps: true,
                      readOnly: isClosingMode,
                    ),
                    const SizedBox(height: 16),

                    // ── Qty | Buy | Sell ──
                    Row(
                      children: [
                        Expanded(
                          child: _buildSheetNumField(
                            controller: _qtyController,
                            label: 'Quantity',
                            readOnly: isClosingMode,
                            borderColor: isClosingMode
                                ? const Color(0xFFF59E0B)
                                : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildSheetNumField(
                            controller: _buyController,
                            label: 'Buy Price',
                            isDecimal: true,
                            readOnly: isClosingMode,
                            borderColor: isClosingMode
                                ? const Color(0xFFF59E0B)
                                : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildSheetNumField(
                            controller: _sellController,
                            label: isDelivery
                                ? 'Sell ₹ (opt.)'
                                : 'Sell Price',
                            isDecimal: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    InkWell(
                      onTap: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: _manualDate,
                                firstDate: DateTime(2020),
                                lastDate: DateTime.now(),
                                builder: (context, child) {
                                  return Theme(
                                    data: Theme.of(context).copyWith(
                                      colorScheme: const ColorScheme.dark(
                                        primary: Color(0xFF10B981),
                                        onPrimary: Colors.white,
                                        surface: Color(0xFF1E293B),
                                        onSurface: Colors.white,
                                      ),
                                    ),
                                    child: child!,
                                  );
                                },
                              );
                              if (picked != null) {
                                setSheetState(() => _manualDate = picked);
                              }
                            },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(16),
                          border: isClosingMode
                              ? Border.all(
                                  color: const Color(0xFFF59E0B)
                                      .withOpacity(0.3))
                              : null,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.calendar_today,
                                  color: isClosingMode
                                      ? const Color(0xFFF59E0B)
                                      : const Color(0xFF10B981),
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Buy Date',
                                        style: TextStyle(
                                            color: Colors.white38,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600)),
                                    Text(
                                      _dateFormat.format(_manualDate),
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w500),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const Icon(Icons.arrow_drop_down,
                                color: Colors.white54),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── Delivery: optional sell date ──
                    if (isDelivery) ...[
                      GestureDetector(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate:
                                _manualSellDate ?? DateTime.now(),
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
                          if (picked != null) {
                            setSheetState(() => _manualSellDate = picked);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color: _manualSellDate != null
                                    ? const Color(0xFFF59E0B).withOpacity(0.4)
                                    : Colors.transparent),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.event_available,
                                  color: Color(0xFFF59E0B), size: 16),
                              const SizedBox(width: 10),
                              Text(
                                _manualSellDate != null
                                    ? 'Sell Date: ${_dateFormat.format(_manualSellDate!)}'
                                    : 'Tap to set sell date (optional)',
                                style: TextStyle(
                                    color: _manualSellDate != null
                                        ? Colors.white
                                        : Colors.white38,
                                    fontSize: 13),
                              ),
                              const Spacer(),
                              if (_manualSellDate != null)
                                GestureDetector(
                                  onTap: () => setSheetState(
                                      () => _manualSellDate = null),
                                  child: const Icon(Icons.close,
                                      color: Colors.white38, size: 14),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Delivery hint banner
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B).withOpacity(0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color:
                                  const Color(0xFFF59E0B).withOpacity(0.25)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.inventory_2_outlined,
                                color: Color(0xFFF59E0B), size: 14),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Sell Price is OPTIONAL for Delivery. '
                                'Leave blank to log as OPEN holding.',
                                style: TextStyle(
                                    color: Colors.white.withOpacity(0.6),
                                    fontSize: 11,
                                    height: 1.4),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),

                    // ── Notes ──
                    TextField(
                      controller: _noteController,
                      style: const TextStyle(color: Colors.white),
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: 'Trade Note / Setup Details',
                        labelStyle: TextStyle(
                            color: Colors.white.withOpacity(0.6)),
                        hintText: 'Enter notes or setup rules...',
                        filled: true,
                        fillColor: const Color(0xFF0F172A),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // ── Submit button ──
                    _buildSheetSubmitButton(
                        sheetContext, setSheetState, isDelivery, isClosingMode),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSheetAutocomplete(
    List<TradeLog> openTrades,
    StateSetter setSheetState,
    bool isClosingMode,
  ) {
    return Autocomplete<TradeLog>(
      optionsBuilder: (TextEditingValue textEditingValue) {
        if (textEditingValue.text.isEmpty) return openTrades;
        final query = textEditingValue.text.toLowerCase();
        return openTrades
            .where((t) => t.symbol.toLowerCase().contains(query))
            .toList();
      },
      displayStringForOption: (t) => t.symbol,
      onSelected: (trade) {
        setSheetState(() {
          _selectedOpenTrade = trade;
          _symbolController.text = trade.symbol;
          _buyController.text = trade.buyPrice.toString();
          _qtyController.text = trade.quantity.toString();
          _manualDate = trade.date;
          _sellController.clear();
          _manualSellDate = null;
        });
      },
      fieldViewBuilder: (context, textController, focusNode, onSubmitted) {
        return TextField(
          controller: textController,
          focusNode: focusNode,
          style: const TextStyle(
              color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            labelText: 'Search open holdings...',
            labelStyle: const TextStyle(color: Colors.white38, fontSize: 12),
            prefixIcon: const Icon(Icons.search,
                color: Color(0xFFF59E0B), size: 18),
            filled: true,
            fillColor: const Color(0xFF0F172A),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 14),
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
              constraints: const BoxConstraints(maxHeight: 180),
              child: ListView.builder(
                padding: const EdgeInsets.all(6),
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final trade = options.elementAt(index);
                  return GestureDetector(
                    onTap: () => onSelected(trade),
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
                                Text(trade.symbol,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13)),
                                Text(
                                  'Qty: ${trade.quantity} · Buy: ${_currencyFormat.format(trade.buyPrice)} · ${_dateFormat.format(trade.date)}',
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

  Widget _buildSheetField({
    required TextEditingController controller,
    required String label,
    String? hint,
    bool caps = false,
    bool readOnly = false,
  }) {
    return TextField(
      controller: controller,
      readOnly: readOnly,
      style: TextStyle(
          color: readOnly ? Colors.white54 : Colors.white),
      textCapitalization:
          caps ? TextCapitalization.characters : TextCapitalization.none,
      decoration: InputDecoration(
        labelText: label,
        labelStyle:
            TextStyle(color: Colors.white.withOpacity(0.6)),
        hintText: hint,
        filled: true,
        fillColor: readOnly
            ? const Color(0xFF0F172A).withOpacity(0.5)
            : const Color(0xFF0F172A),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none),
      ),
    );
  }

  Widget _buildSheetNumField({
    required TextEditingController controller,
    required String label,
    bool isDecimal = false,
    bool readOnly = false,
    Color? borderColor,
  }) {
    return TextField(
      controller: controller,
      readOnly: readOnly,
      keyboardType: isDecimal
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.number,
      style: TextStyle(
          color: readOnly ? Colors.white54 : Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle:
            TextStyle(color: Colors.white.withOpacity(0.6)),
        filled: true,
        fillColor: readOnly
            ? const Color(0xFF0F172A).withOpacity(0.5)
            : const Color(0xFF0F172A),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: borderColor != null
              ? BorderSide(color: borderColor.withOpacity(0.4))
              : BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: borderColor != null
              ? BorderSide(color: borderColor.withOpacity(0.3))
              : BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildSheetSubmitButton(
    BuildContext sheetContext,
    StateSetter setSheetState,
    bool isDelivery,
    bool isClosingMode,
  ) {
    final qty = int.tryParse(_qtyController.text) ?? 0;
    final buy = double.tryParse(_buyController.text) ?? 0.0;
    final sell = double.tryParse(_sellController.text);
    final hasSell = sell != null && sell > 0;
    final stockName = _symbolController.text.trim();

    // Delivery: enabled if stock + buy + qty filled (sell optional)
    // Non-delivery: all three required
    bool canSubmit;
    if (isDelivery) {
      canSubmit = stockName.isNotEmpty && qty > 0 && buy > 0;
    } else {
      canSubmit = qty > 0 && buy > 0 && hasSell;
    }

    String label;
    Color color;
    IconData icon;

    if (isClosingMode) {
      label = hasSell ? 'Close Position' : 'Needs sell price';
      color = hasSell && canSubmit
          ? const Color(0xFFF59E0B)
          : const Color(0xFF334155);
      icon = Icons.lock_outline;
    } else if (isDelivery && !hasSell) {
      label = 'Save as OPEN Holding';
      color = canSubmit
          ? const Color(0xFFF59E0B)
          : const Color(0xFF334155);
      icon = Icons.inventory_2_outlined;
    } else {
      label = 'Save Log Entry';
      color = canSubmit
          ? const Color(0xFF10B981)
          : const Color(0xFF334155);
      icon = Icons.save_alt_outlined;
    }

    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton.icon(
        icon: Icon(icon, color: Colors.white, size: 20),
        label: Text(label,
            style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Colors.white)),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          elevation: canSubmit ? 8 : 0,
          shadowColor: color.withOpacity(0.4),
        ),
        onPressed: canSubmit
            ? () async {
                await _submitManualEntry(sheetContext, isDelivery,
                    isClosingMode, qty, buy, sell);
              }
            : null,
      ),
    );
  }

  Future<void> _submitManualEntry(
    BuildContext sheetContext,
    bool isDelivery,
    bool isClosingMode,
    int qty,
    double buy,
    double? sell,
  ) async {
    List<TradeLog> updated;
    final hasSell = sell != null && sell > 0;

    if (isDelivery && isClosingMode && hasSell) {
      // ── Close an existing open delivery journal trade ──────────
      final effectiveSellDate = _manualSellDate ?? DateTime.now();
      updated = await _journalService.closeJournalPosition(
        id: _selectedOpenTrade!.id,
        sellPrice: sell!,
        sellDate: effectiveSellDate,
      );
      if (context.mounted) {
        _showSnack(
            '${_selectedOpenTrade!.symbol} position CLOSED!',
            isOpen: false);
      }
    } else if (isDelivery && !hasSell) {
      // ── Log as OPEN holding ────────────────────────────────────
      final log = TradeLog.openDelivery(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        symbol: _symbolController.text,
        quantity: qty,
        buyPrice: buy,
        buyDate: _manualDate,
        note: _noteController.text,
      );
      updated = await _journalService.addTrade(log);
      if (context.mounted) {
        _showSnack('${log.symbol} logged as OPEN holding.', isOpen: true);
      }
    } else {
      // ── Normal closed trade ────────────────────────────────────
      final calc = calculateGrowwCharges(
        type: _manualType,
        buyPrice: buy,
        sellPrice: sell!,
        quantity: qty,
      );
      final log = TradeLog.fromCalculation(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        symbol: _symbolController.text,
        calc: calc,
        date: _manualDate,
        note: _noteController.text,
        sellDate: _manualSellDate,
      );
      updated = await _journalService.addTrade(log);
      if (context.mounted) {
        _showSnack('${log.symbol} trade saved!');
      }
    }

    setState(() {
      _allTrades = updated;
      _applyFilters();
    });

    if (context.mounted) {
      Navigator.pop(sheetContext);
    }
  }

  void _showSnack(String msg, {bool isError = false, bool isOpen = false}) {
    if (!mounted) return;
    final color = isError
        ? const Color(0xFFF43F5E)
        : isOpen
            ? const Color(0xFFF59E0B)
            : const Color(0xFF059669);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // ─── Build ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF10B981)))
          : RefreshIndicator(
              onRefresh: _loadTrades,
              color: const Color(0xFF10B981),
              backgroundColor: const Color(0xFF1E293B),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Trading Journal',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -1,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Track profits, losses, fees and trade notes.',
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.6), fontSize: 15),
                      ),
                      const SizedBox(height: 24),

                      _buildMetricsDashboard(),
                      const SizedBox(height: 24),
                      _buildSearchAndFilters(),
                      const SizedBox(height: 16),

                      _filteredTrades.isEmpty
                          ? _buildEmptyState()
                          : _buildTradeFeed(),

                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF10B981),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        onPressed: _showManualEntrySheet,
        child: const Icon(Icons.add, color: Colors.white, size: 28),
      ),
    );
  }

  Widget _buildMetricsDashboard() {
    final isProfit = _totalNetPL >= 0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Realized Net P&L',
                      style: TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 6),
                  Text(
                    (_totalNetPL >= 0 ? '+' : '') +
                        _currencyFormat.format(_totalNetPL),
                    style: TextStyle(
                      color: isProfit
                          ? const Color(0xFF10B981)
                          : const Color(0xFFF43F5E),
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isProfit
                      ? const Color(0xFF10B981).withOpacity(0.1)
                      : const Color(0xFFF43F5E).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      isProfit ? Icons.arrow_upward : Icons.arrow_downward,
                      color: isProfit
                          ? const Color(0xFF10B981)
                          : const Color(0xFFF43F5E),
                      size: 16,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${_winRate.toStringAsFixed(1)}% WR',
                      style: TextStyle(
                        color: isProfit
                            ? const Color(0xFF10B981)
                            : const Color(0xFFF43F5E),
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              )
            ],
          ),
          const Divider(color: Color(0xFF334155), height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildMiniMetric('Charges Paid',
                  _currencyFormat.format(_totalCharges),
                  icon: Icons.receipt_long,
                  color: const Color(0xFFF59E0B)),
              _buildMiniMetric('Closed Trades',
                  _closedTrades.length.toString(),
                  icon: Icons.history, color: const Color(0xFF6366F1)),
              if (_openCount > 0)
                _buildMiniMetric('Holdings', _openCount.toString(),
                    icon: Icons.inventory_2_outlined,
                    color: const Color(0xFFF59E0B)),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildMiniMetric(String label, String value,
      {required IconData icon, required Color color}) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(color: Colors.white54, fontSize: 11)),
            const SizedBox(height: 2),
            Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14)),
          ],
        )
      ],
    );
  }

  Widget _buildSearchAndFilters() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Search bar
        TextField(
          style: const TextStyle(color: Colors.white, fontSize: 14),
          onChanged: (val) {
            _searchQuery = val;
            _applyFilters();
          },
          decoration: InputDecoration(
            hintText: 'Search notes or stocks...',
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
            prefixIcon:
                const Icon(Icons.search, color: Colors.white60),
            filled: true,
            fillColor: const Color(0xFF1E293B),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
        const SizedBox(height: 12),

        // Status filter chips + type filter chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: [
              // Status chips
              _statusChip('all', 'All', null),
              _statusChip(
                  'closed', 'Closed', const Color(0xFF10B981)),
              _statusChip(
                  'open', 'Open Holdings', const Color(0xFFF59E0B)),
              const SizedBox(width: 8),
              Container(
                  width: 1,
                  height: 20,
                  color: Colors.white.withOpacity(0.1)),
              const SizedBox(width: 8),
              // Type chips
              ..._buildTypeFilterChips(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _statusChip(String value, String label, Color? color) {
    final isSelected = _statusFilter == value;
    final chipColor = color ?? const Color(0xFF6366F1);
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (selected) {
          if (selected) {
            setState(() {
              _statusFilter = value;
              _applyFilters();
            });
          }
        },
        backgroundColor: const Color(0xFF1E293B),
        selectedColor: chipColor.withOpacity(0.2),
        checkmarkColor: chipColor,
        labelStyle: TextStyle(
          color: isSelected ? chipColor : Colors.white.withOpacity(0.6),
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
        side: BorderSide(
          color: isSelected ? chipColor.withOpacity(0.5) : Colors.transparent,
        ),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide.none),
      ),
    );
  }

  List<Widget> _buildTypeFilterChips() {
    return [
      Padding(
        padding: const EdgeInsets.only(right: 8.0),
        child: FilterChip(
          label: const Text('All Types'),
          selected: _selectedTypeFilter == null,
          onSelected: (selected) {
            if (selected) {
              setState(() {
                _selectedTypeFilter = null;
                _applyFilters();
              });
            }
          },
          backgroundColor: const Color(0xFF1E293B),
          selectedColor: const Color(0xFF10B981).withOpacity(0.15),
          checkmarkColor: const Color(0xFF10B981),
          labelStyle: TextStyle(
            color: _selectedTypeFilter == null
                ? const Color(0xFF10B981)
                : Colors.white.withOpacity(0.6),
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide.none),
        ),
      ),
      ...TradeType.values.map((type) {
        final isSelected = _selectedTypeFilter == type;
        return Padding(
          padding: const EdgeInsets.only(right: 8.0),
          child: FilterChip(
            label: Text(type == TradeType.delivery
                ? 'Delivery'
                : type == TradeType.intraday
                    ? 'Intraday'
                    : type == TradeType.futures
                        ? 'Futures'
                        : 'Options'),
            selected: isSelected,
            onSelected: (selected) {
              setState(() {
                _selectedTypeFilter = selected ? type : null;
                _applyFilters();
              });
            },
            backgroundColor: const Color(0xFF1E293B),
            selectedColor: const Color(0xFF6366F1).withOpacity(0.15),
            checkmarkColor: const Color(0xFF6366F1),
            labelStyle: TextStyle(
              color: isSelected
                  ? const Color(0xFF6366F1)
                  : Colors.white.withOpacity(0.6),
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide.none),
          ),
        );
      }),
    ];
  }

  Widget _buildEmptyState() {
    final isFiltered = _statusFilter != 'all' || _selectedTypeFilter != null ||
        _searchQuery.isNotEmpty;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40.0),
        child: Column(
          children: [
            Icon(
              isFiltered ? Icons.filter_list_off : Icons.history_edu,
              size: 64,
              color: Colors.white.withOpacity(0.15),
            ),
            const SizedBox(height: 16),
            Text(
              isFiltered ? 'No matching logs' : 'No logs found',
              style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              isFiltered
                  ? 'Try adjusting filters or search'
                  : "Log a trade from the calculator or tap '+' below.",
              style: TextStyle(
                  color: Colors.white.withOpacity(0.4), fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTradeFeed() {
    final Map<String, List<TradeLog>> grouped = {};
    for (var trade in _filteredTrades) {
      final key = _dateFormat.format(trade.date);
      grouped.putIfAbsent(key, () => []).add(trade);
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: grouped.keys.length,
      itemBuilder: (context, index) {
        final dateStr = grouped.keys.elementAt(index);
        final dateTrades = grouped[dateStr]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(
                  top: 20.0, bottom: 10.0, left: 4.0),
              child: Text(
                dateStr,
                style: const TextStyle(
                  color: Color(0xFF6366F1),
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            ...dateTrades.map((trade) => _buildTradeCard(trade)),
          ],
        );
      },
    );
  }

  Widget _buildTradeCard(TradeLog trade) {
    final isOpen = trade.status == PositionStatus.open;

    if (isOpen) return _buildOpenTradeCard(trade);

    final isProfit = trade.netPL >= 0;

    return Card(
      color: const Color(0xFF1E293B),
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.white.withOpacity(0.02)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          iconColor: Colors.white70,
          collapsedIconColor: Colors.white30,
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isProfit
                  ? const Color(0xFF10B981).withOpacity(0.1)
                  : const Color(0xFFF43F5E).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isProfit ? Icons.arrow_upward : Icons.arrow_downward,
              color: isProfit
                  ? const Color(0xFF10B981)
                  : const Color(0xFFF43F5E),
              size: 20,
            ),
          ),
          title: Text(
            trade.symbol,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 15),
          ),
          subtitle: Row(
            children: [
              Text(
                trade.type.displayName,
                style: TextStyle(
                    color: Colors.white.withOpacity(0.4), fontSize: 11),
              ),
              const SizedBox(width: 8),
              Container(
                width: 3,
                height: 3,
                decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(width: 8),
              Text(
                'Qty: ${trade.quantity}',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.4), fontSize: 11),
              ),
            ],
          ),
          trailing: Text(
            (isProfit ? '+' : '') + _currencyFormat.format(trade.netPL),
            style: TextStyle(
              color: isProfit
                  ? const Color(0xFF10B981)
                  : const Color(0xFFF43F5E),
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.only(
                  left: 20.0, right: 20.0, bottom: 20.0, top: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(color: Color(0xFF334155), height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildDetailItem('Buy Price',
                          _currencyFormat.format(trade.buyPrice)),
                      _buildDetailItem('Sell Price',
                          _currencyFormat.format(trade.sellPrice ?? 0)),
                      _buildDetailItem(
                          'Gross P&L',
                          _currencyFormat.format(trade.grossPL),
                          color: trade.grossPL >= 0
                              ? const Color(0xFF10B981)
                              : const Color(0xFFF43F5E)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildDetailItem(
                          'Total Charges',
                          _currencyFormat.format(trade.totalCharges),
                          color: const Color(0xFFF43F5E)),
                      _buildDetailItem(
                          'Net Earnings',
                          _currencyFormat.format(trade.netPL),
                          color: isProfit
                              ? const Color(0xFF10B981)
                              : const Color(0xFFF43F5E)),
                      const SizedBox(width: 80),
                    ],
                  ),
                  if (trade.note.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text('Journal Note:',
                        style: TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.white.withOpacity(0.05)),
                      ),
                      child: Text(
                        trade.note,
                        style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            height: 1.4),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        icon: const Icon(Icons.delete_outline,
                            size: 18, color: Color(0xFFF43F5E)),
                        label: const Text('Delete',
                            style: TextStyle(
                                color: Color(0xFFF43F5E), fontSize: 13)),
                        onPressed: () => _deleteTrade(trade.id),
                      ),
                    ],
                  )
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildOpenTradeCard(TradeLog trade) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.4)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF59E0B).withOpacity(0.07),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.inventory_2_outlined,
                          color: Color(0xFFF59E0B), size: 11),
                      SizedBox(width: 4),
                      Text(
                        'OPEN HOLDING',
                        style: TextStyle(
                            color: Color(0xFFF59E0B),
                            fontWeight: FontWeight.w800,
                            fontSize: 10,
                            letterSpacing: 0.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    trade.symbol,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  trade.type.displayName,
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.4), fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _buildDetailItem(
                    'Buy Price', _currencyFormat.format(trade.buyPrice)),
                const SizedBox(width: 20),
                _buildDetailItem('Qty', trade.quantity.toString()),
                const SizedBox(width: 20),
                _buildDetailItem('Buy Date', _dateFormat.format(trade.date)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color:
                          const Color(0xFFF59E0B).withOpacity(0.06),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: const Color(0xFFF59E0B).withOpacity(0.2)),
                    ),
                    child: const Text(
                      'Un-sold position · No P&L realized yet',
                      style: TextStyle(
                          color: Color(0xFFF59E0B), fontSize: 11),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: () {
                    Navigator.pop(context); // close if in sheet
                    _showManualEntrySheetPreselected(trade);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'SELL',
                      style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                          letterSpacing: 0.5),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => _deleteTrade(trade.id),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF43F5E).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.delete_outline,
                        color: Color(0xFFF43F5E), size: 16),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showManualEntrySheetPreselected(TradeLog openTrade) {
    _symbolController.text = openTrade.symbol;
    _buyController.text = openTrade.buyPrice.toString();
    _qtyController.text = openTrade.quantity.toString();
    _manualDate = openTrade.date;
    _manualType = TradeType.delivery;
    _sellController.clear();
    _noteController.clear();
    _manualSellDate = null;
    _selectedOpenTrade = openTrade;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final isDelivery = _manualType == TradeType.delivery;
            final isClosingMode =
                isDelivery && _selectedOpenTrade != null;
            final openTrades =
                _journalService.getOpenDeliveryTrades(_allTrades);

            return Padding(
              padding: EdgeInsets.only(
                left: 24.0,
                right: 24.0,
                top: 24.0,
                bottom:
                    MediaQuery.of(context).viewInsets.bottom + 24.0,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.lock_open_outlined,
                            color: Color(0xFFF59E0B), size: 22),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Close Position',
                              style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white),
                            ),
                            Text(
                              openTrade.symbol,
                              style: const TextStyle(
                                  color: Color(0xFFF59E0B),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13),
                            ),
                          ],
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close,
                              color: Colors.white60),
                          onPressed: () => Navigator.pop(sheetContext),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Locked buy fields
                    Row(
                      children: [
                        Expanded(
                          child: _buildSheetNumField(
                            controller: _qtyController,
                            label: 'Quantity',
                            readOnly: true,
                            borderColor: const Color(0xFFF59E0B),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildSheetNumField(
                            controller: _buyController,
                            label: 'Buy Price',
                            isDecimal: true,
                            readOnly: true,
                            borderColor: const Color(0xFFF59E0B),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildSheetNumField(
                            controller: _sellController,
                            label: 'Sell Price ₹',
                            isDecimal: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Sell Date
                    GestureDetector(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate:
                              _manualSellDate ?? DateTime.now(),
                          firstDate: openTrade.date,
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
                        if (picked != null) {
                          setSheetState(
                              () => _manualSellDate = picked);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: _manualSellDate != null
                                  ? const Color(0xFFF59E0B)
                                      .withOpacity(0.4)
                                  : Colors.transparent),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.event_available,
                                color: Color(0xFFF59E0B), size: 16),
                            const SizedBox(width: 10),
                            Text(
                              _manualSellDate != null
                                  ? 'Sell Date: ${_dateFormat.format(_manualSellDate!)}'
                                  : 'Tap to set sell date (default: today)',
                              style: TextStyle(
                                  color: _manualSellDate != null
                                      ? Colors.white
                                      : Colors.white38,
                                  fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    TextField(
                      controller: _noteController,
                      style: const TextStyle(color: Colors.white),
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: 'Note (optional)',
                        labelStyle: TextStyle(
                            color: Colors.white.withOpacity(0.6)),
                        filled: true,
                        fillColor: const Color(0xFF0F172A),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 20),

                    _buildSheetSubmitButton(
                        sheetContext,
                        setSheetState,
                        isDelivery,
                        isClosingMode),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDetailItem(String label, String value, {Color? color}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style:
                const TextStyle(color: Colors.white38, fontSize: 11)),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: color ?? Colors.white70,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}
