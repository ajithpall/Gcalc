import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/trade_calculation.dart';
import '../models/trade_log.dart';
import '../services/journal_service.dart';

class CalculatorScreen extends StatefulWidget {
  final VoidCallback onTradeSaved;

  const CalculatorScreen({super.key, required this.onTradeSaved});

  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen> {
  final JournalService _journalService = JournalService();
  final _buyController = TextEditingController();
  final _sellController = TextEditingController();
  final _qtyController = TextEditingController();

  TradeType _selectedType = TradeType.intraday;
  TradeType _foSubType = TradeType.futures;
  bool _isNSE = true; // true = NSE, false = BSE
  CalculationResult? _calculation;

  final _currencyFormat =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

  @override
  void initState() {
    super.initState();
    _buyController.addListener(_calculate);
    _sellController.addListener(_calculate);
    _qtyController.addListener(_calculate);
  }

  @override
  void dispose() {
    _buyController.dispose();
    _sellController.dispose();
    _qtyController.dispose();
    super.dispose();
  }

  void _calculate() {
    final b = double.tryParse(_buyController.text) ?? 0.0;
    final s = double.tryParse(_sellController.text) ?? 0.0;
    final q = int.tryParse(_qtyController.text) ?? 0;

    if (b > 0 && s > 0 && q > 0) {
      setState(() {
        _calculation = calculateGrowwCharges(
          type: _selectedType,
          buyPrice: b,
          sellPrice: s,
          quantity: q,
          isNSE: _isNSE,
        );
      });
    } else {
      setState(() => _calculation = null);
    }
  }

  void _showLogTradeSheet(BuildContext context) {
    if (_calculation == null) return;

    final symbolController = TextEditingController();
    final noteController = TextEditingController();
    DateTime selectedDate = DateTime.now();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 24,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Log to Journal',
                            style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.white)),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white60),
                          onPressed: () => Navigator.pop(sheetContext),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Summary
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_selectedType.displayName,
                                  style: const TextStyle(
                                      color: Colors.white60, fontSize: 12)),
                              const SizedBox(height: 4),
                              Text(
                                'Qty: ${_calculation!.quantity} @ ${_currencyFormat.format(_calculation!.buyPrice)}',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const Text('Est. Net P&L',
                                  style: TextStyle(
                                      color: Colors.white60, fontSize: 12)),
                              const SizedBox(height: 4),
                              Text(
                                (_calculation!.netPL >= 0 ? '+' : '') +
                                    _currencyFormat.format(_calculation!.netPL),
                                style: TextStyle(
                                  color: _calculation!.netPL >= 0
                                      ? const Color(0xFF10B981)
                                      : const Color(0xFFF43F5E),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: symbolController,
                      style: const TextStyle(color: Colors.white),
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        labelText: 'Stock Symbol',
                        labelStyle:
                            TextStyle(color: Colors.white.withOpacity(0.6)),
                        hintText: 'e.g., RELIANCE, NIFTY FUT',
                        hintStyle:
                            TextStyle(color: Colors.white.withOpacity(0.3)),
                        filled: true,
                        fillColor: const Color(0xFF0F172A),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 16),
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: selectedDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                          builder: (c, child) => Theme(
                            data: Theme.of(c).copyWith(
                              colorScheme: const ColorScheme.dark(
                                primary: Color(0xFF10B981),
                                onPrimary: Colors.white,
                                surface: Color(0xFF1E293B),
                                onSurface: Colors.white,
                              ),
                            ),
                            child: child!,
                          ),
                        );
                        if (picked != null) {
                          setSheetState(() => selectedDate = picked);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(children: [
                              const Icon(Icons.calendar_today,
                                  color: Color(0xFF10B981), size: 20),
                              const SizedBox(width: 12),
                              Text(
                                DateFormat('dd MMM yyyy').format(selectedDate),
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500),
                              ),
                            ]),
                            const Icon(Icons.arrow_drop_down,
                                color: Colors.white54),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: noteController,
                      style: const TextStyle(color: Colors.white),
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: 'Trade Note',
                        labelStyle:
                            TextStyle(color: Colors.white.withOpacity(0.6)),
                        hintText: 'Why did you take this trade?',
                        hintStyle:
                            TextStyle(color: Colors.white.withOpacity(0.3)),
                        filled: true,
                        fillColor: const Color(0xFF0F172A),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: () async {
                          final log = TradeLog.fromCalculation(
                            id: DateTime.now()
                                .millisecondsSinceEpoch
                                .toString(),
                            symbol: symbolController.text,
                            calc: _calculation!,
                            date: selectedDate,
                            note: noteController.text,
                          );
                          await _journalService.addTrade(log);
                          widget.onTradeSaved();
                          if (context.mounted) {
                            Navigator.pop(sheetContext);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Row(children: [
                                  const Icon(Icons.check_circle_outline,
                                      color: Colors.white),
                                  const SizedBox(width: 8),
                                  Text('${log.symbol} logged!'),
                                ]),
                                backgroundColor: const Color(0xFF059669),
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                            );
                          }
                        },
                        child: const Text('Log to Journal',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 20),
            _buildSegmentSelector(),
            const SizedBox(height: 20),
            _buildInputSection(),
            const SizedBox(height: 20),
            if (_calculation != null) ...[
              _buildResultCard(),
              const SizedBox(height: 16),
              _buildDetailedBreakdown(),
              const SizedBox(height: 16),
              _buildActionButton(),
              const SizedBox(height: 16),
            ] else
              _buildPlaceholder(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Brokerage Calc',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.8,
                color: Colors.white,
              ),
            ),
            Text(
              'Groww-exact fee structures',
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withOpacity(0.5),
              ),
            ),
          ],
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF10B981).withOpacity(0.15),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.calculate_rounded,
              color: Color(0xFF10B981), size: 22),
        ),
      ],
    );
  }

  Widget _buildSegmentSelector() {
    final isFO = _selectedType == TradeType.futures ||
        _selectedType == TradeType.options;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Row 1: label + NSE/BSE toggle ────────────────────────────────
        Row(
          children: [
            const Text(
              'SELECT TRADE TYPE',
              style: TextStyle(
                color: Colors.white38,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
            const Spacer(),
            _buildExchangeToggle(),
          ],
        ),
        const SizedBox(height: 10),

        // ── Row 2: Intraday | Delivery | F&O tiles ───────────────────────
        Row(
          children: [
            _typeTile(
              label: 'Intraday',
              icon: Icons.flash_on_rounded,
              color: const Color(0xFF10B981),
              isSelected: _selectedType == TradeType.intraday,
              onTap: () => setState(() {
                _selectedType = TradeType.intraday;
                _calculate();
              }),
            ),
            const SizedBox(width: 10),
            _typeTile(
              label: 'Delivery',
              icon: Icons.inventory_2_outlined,
              color: const Color(0xFF3B82F6),
              isSelected: _selectedType == TradeType.delivery,
              onTap: () => setState(() {
                _selectedType = TradeType.delivery;
                _calculate();
              }),
            ),
            const SizedBox(width: 10),
            _typeTile(
              label: 'F & O',
              icon: Icons.candlestick_chart_outlined,
              color: const Color(0xFF8B5CF6),
              isSelected: isFO,
              onTap: () => setState(() {
                _selectedType = _foSubType;
                _calculate();
              }),
            ),
          ],
        ),

        // ── Row 3 (conditional): Futures | Options sub-toggle ────────────
        if (isFO) ...[
          const SizedBox(height: 10),
          Container(
            height: 40,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: const Color(0xFF8B5CF6).withOpacity(0.35)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() {
                      _selectedType = TradeType.futures;
                      _foSubType = TradeType.futures;
                      _calculate();
                    }),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      decoration: BoxDecoration(
                        color: _selectedType == TradeType.futures
                            ? const Color(0xFF8B5CF6)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'Futures',
                        style: TextStyle(
                          color: _selectedType == TradeType.futures
                              ? Colors.white
                              : Colors.white54,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() {
                      _selectedType = TradeType.options;
                      _foSubType = TradeType.options;
                      _calculate();
                    }),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      decoration: BoxDecoration(
                        color: _selectedType == TradeType.options
                            ? const Color(0xFF8B5CF6)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'Options',
                        style: TextStyle(
                          color: _selectedType == TradeType.options
                              ? Colors.white
                              : Colors.white54,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// Compact animated NSE / BSE segmented toggle.
  Widget _buildExchangeToggle() {
    const nseColor = Color(0xFF10B981); // green
    const bseColor = Color(0xFFF59E0B); // amber
    final activeColor = _isNSE ? nseColor : bseColor;

    return GestureDetector(
      onTap: () => setState(() {
        _isNSE = !_isNSE;
        _calculate();
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        height: 30,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: activeColor.withOpacity(0.4), width: 1.2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _exchangeTab('NSE', _isNSE,  nseColor),
            const SizedBox(width: 2),
            _exchangeTab('BSE', !_isNSE, bseColor),
          ],
        ),
      ),
    );
  }

  Widget _exchangeTab(String label, bool active, Color color) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: active ? color.withOpacity(0.18) : Colors.transparent,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: active ? color.withOpacity(0.7) : Colors.transparent,
          width: 1,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: active ? color : Colors.white30,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _typeTile({
    required String label,
    required IconData icon,
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: isSelected
                ? color.withOpacity(0.12)
                : const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? color.withOpacity(0.6)
                  : Colors.white.withOpacity(0.05),
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  color: isSelected ? color : Colors.white30, size: 22),
              const SizedBox(height: 5),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? color : Colors.white30,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        children: [
          _buildTextField(
            label: 'Buy Price',
            controller: _buyController,
            icon: Icons.arrow_downward_rounded,
            iconColor: const Color(0xFF3B82F6),
          ),
          const SizedBox(height: 14),
          _buildTextField(
            label: 'Sell Price',
            controller: _sellController,
            icon: Icons.arrow_upward_rounded,
            iconColor: const Color(0xFF8B5CF6),
          ),
          const SizedBox(height: 14),
          _buildTextField(
            label: 'Quantity',
            controller: _qtyController,
            icon: Icons.numbers_rounded,
            iconColor: const Color(0xFFF59E0B),
            isInteger: true,
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    required Color iconColor,
    bool isInteger = false,
  }) {
    return TextField(
      controller: controller,
      keyboardType:
          TextInputType.numberWithOptions(decimal: !isInteger),
      style: const TextStyle(
          fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
            color: Colors.white.withOpacity(0.6), fontSize: 14),
        prefixIcon: Icon(icon, color: iconColor),
        filled: true,
        fillColor: const Color(0xFF0F172A),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: iconColor, width: 1.5),
        ),
      ),
    );
  }

  Widget _buildResultCard() {
    final calc = _calculation!;
    final isProfit = calc.netPL >= 0;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          colors: isProfit
              ? [const Color(0xFF059669), const Color(0xFF10B981)]
              : [const Color(0xFFBE185D), const Color(0xFFF43F5E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: (isProfit
                        ? const Color(0xFF10B981)
                        : const Color(0xFFF43F5E))
                    .withOpacity(0.35),
            blurRadius: 24,
            offset: const Offset(0, 10),
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
              color: Colors.white.withOpacity(0.1),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Net P&L (After All Charges)',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 13,
                      fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 4),
                Text(
                  (isProfit ? '+' : '') + _currencyFormat.format(calc.netPL),
                  style: const TextStyle(
                    fontSize: 38,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _resultPill('Turnover',
                        _currencyFormat.format(calc.turnover)),
                    const SizedBox(width: 10),
                    _resultPill('Gross P&L',
                        _currencyFormat.format(calc.grossPL)),
                    const SizedBox(width: 10),
                    _resultPill('Charges',
                        _currencyFormat.format(calc.totalCharges)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultPill(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5)),
            const SizedBox(height: 2),
            Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800),
                overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailedBreakdown() {
    final calc = _calculation!;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Detailed Charges Breakdown',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white),
          ),
          const SizedBox(height: 6),
          Text(
            'Where your money goes',
            style: TextStyle(
                color: Colors.white.withOpacity(0.4), fontSize: 12),
          ),
          const SizedBox(height: 18),

          // Summary row
          _breakdownSummaryRow(calc),
          const SizedBox(height: 16),
          const Divider(color: Color(0xFF334155)),
          const SizedBox(height: 12),

          // Groww charges section
          _sectionLabel('BROKER CHARGES (GROWW)'),
          const SizedBox(height: 10),
          _chargeRow(
            label: 'Brokerage',
            sublabel: _brokerageNote(),
            value: calc.growwCharges,
            icon: Icons.business_center_outlined,
            color: const Color(0xFF6366F1),
          ),
          const SizedBox(height: 12),
          const Divider(color: Color(0xFF334155)),
          const SizedBox(height: 12),

          // Government / Exchange charges
          _sectionLabel('REGULATORY & EXCHANGE CHARGES'),
          const SizedBox(height: 10),
          _chargeRow(
            label: 'STT',
            sublabel: _sttNote(),
            value: calc.stt,
            icon: Icons.account_balance_outlined,
            color: const Color(0xFFF59E0B),
          ),
          const SizedBox(height: 10),
          _chargeRow(
            label: 'Exchange Transaction Charges',
            sublabel: _exchangeNote(),
            value: calc.exchangeCharges,
            icon: Icons.sync_alt,
            color: const Color(0xFF3B82F6),
          ),
          const SizedBox(height: 10),
          _chargeRow(
            label: 'SEBI Turnover Fees',
            sublabel: '₹10 per crore turnover',
            value: calc.sebiFees,
            icon: Icons.gavel_outlined,
            color: const Color(0xFF10B981),
          ),
          if (calc.dpCharges > 0) ...[
            const SizedBox(height: 10),
            _chargeRow(
              label: 'DP Charges',
              sublabel: '₹18.29 (GST incl.) on sell',
              value: calc.dpCharges,
              icon: Icons.account_balance_wallet_outlined,
              color: const Color(0xFFF97316),
            ),
          ],
          const SizedBox(height: 10),
          _chargeRow(
            label: 'Stamp Duty',
            sublabel: _stampNote(),
            value: calc.stampDuty,
            icon: Icons.local_post_office_outlined,
            color: const Color(0xFFEC4899),
          ),
          const SizedBox(height: 10),
          _chargeRow(
            label: 'GST',
            sublabel: '18% on brokerage + exchange + SEBI',
            value: calc.gst,
            icon: Icons.receipt_outlined,
            color: const Color(0xFF8B5CF6),
          ),
          const SizedBox(height: 16),
          const Divider(color: Color(0xFF334155)),
          const SizedBox(height: 14),

          // Total charges
          _totalChargesRow(calc),
        ],
      ),
    );
  }

  String _brokerageNote() {
    switch (_selectedType) {
      case TradeType.delivery:
      case TradeType.intraday:
      case TradeType.futures:
        return '0.05% or ₹20 per order (whichever is lower)';
      case TradeType.options:
        return 'Flat ₹20 per buy + ₹20 per sell';
    }
  }

  String _sttNote() {
    switch (_selectedType) {
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

  String _exchangeNote() {
    switch (_selectedType) {
      case TradeType.delivery:
      case TradeType.intraday:
        return '0.00297% of turnover (NSE)';
      case TradeType.futures:
        return '0.00173% of turnover (NSE)';
      case TradeType.options:
        return '0.03503% of premium turnover';
    }
  }

  String _stampNote() {
    switch (_selectedType) {
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

  Widget _breakdownSummaryRow(CalculationResult calc) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _summaryCell('Turnover',
              _currencyFormat.format(calc.turnover), Colors.white70),
          _vDivider(),
          _summaryCell(
              'Gross P&L',
              _currencyFormat.format(calc.grossPL),
              calc.grossPL >= 0
                  ? const Color(0xFF10B981)
                  : const Color(0xFFF43F5E)),
          _vDivider(),
          _summaryCell('Total Charges',
              _currencyFormat.format(calc.totalCharges),
              const Color(0xFFF43F5E)),
        ],
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
        width: 1, height: 32, color: Colors.white.withOpacity(0.08));
  }

  Widget _chargeRow({
    required String label,
    required String sublabel,
    required double value,
    required IconData icon,
    required Color color,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
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
          _currencyFormat.format(value),
          style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 13),
        ),
      ],
    );
  }

  Widget _totalChargesRow(CalculationResult calc) {
    final isProfit = calc.netPL >= 0;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Net P&L',
                style: TextStyle(
                    color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
            Text(
              (isProfit ? 'Profit' : 'Loss') + ' after all charges',
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
        ),
        Text(
          (isProfit ? '+' : '') + _currencyFormat.format(calc.netPL),
          style: TextStyle(
            color: isProfit ? const Color(0xFF10B981) : const Color(0xFFF43F5E),
            fontWeight: FontWeight.w900,
            fontSize: 22,
            letterSpacing: -0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        children: [
          Icon(Icons.calculate_outlined,
              size: 56, color: Colors.white.withOpacity(0.1)),
          const SizedBox(height: 14),
          const Text('Enter trade details above',
              style: TextStyle(
                  color: Colors.white54,
                  fontSize: 15,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(
            'Results will appear here instantly',
            style:
                TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        icon: const Icon(Icons.add_task, color: Colors.white),
        label: const Text('Log Trade to Journal',
            style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF10B981),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          shadowColor: const Color(0xFF10B981).withOpacity(0.3),
          elevation: 8,
        ),
        onPressed: () => _showLogTradeSheet(context),
      ),
    );
  }
}
