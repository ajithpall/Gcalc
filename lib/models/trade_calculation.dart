import 'dart:math';

enum TradeType {
  delivery,
  intraday,
  futures,
  options;

  String get displayName {
    switch (this) {
      case TradeType.delivery:
        return 'Equity Delivery';
      case TradeType.intraday:
        return 'Equity Intraday';
      case TradeType.futures:
        return 'Equity Futures';
      case TradeType.options:
        return 'Equity Options';
    }
  }

  String toJson() => name;

  static TradeType fromJson(String json) {
    return TradeType.values.firstWhere((e) => e.name == json);
  }
}

class CalculationResult {
  final TradeType type;
  final int quantity;
  final double buyPrice;
  final double sellPrice;
  
  final double turnover;
  final double grossPL;
  final double totalCharges;
  final double growwCharges; // Brokerage
  final double nonGrowwCharges;
  final double stt;
  final double exchangeCharges;
  final double sebiFees;
  final double dpCharges;
  final double gst;
  final double stampDuty;
  final double netPL;

  CalculationResult({
    required this.type,
    required this.quantity,
    required this.buyPrice,
    required this.sellPrice,
    required this.turnover,
    required this.grossPL,
    required this.totalCharges,
    required this.growwCharges,
    required this.nonGrowwCharges,
    required this.stt,
    required this.exchangeCharges,
    required this.sebiFees,
    required this.dpCharges,
    required this.gst,
    required this.stampDuty,
    required this.netPL,
  });
}

CalculationResult calculateGrowwCharges({
  required TradeType type,
  required int quantity,
  required double buyPrice,
  required double sellPrice,
  bool isNSE = true, // true for NSE, false for BSE
}) {
  // ─── Utility: round to exactly 2 decimal places ──────────────────────────
  double round2(double v) =>
      double.parse(v.toStringAsFixed(2));

  final double buyTurnover  = quantity * buyPrice;
  final double sellTurnover = quantity * sellPrice;
  final double turnover     = buyTurnover + sellTurnover;
  final double grossPL      = round2((sellPrice - buyPrice) * quantity);

  // ─── Helper: single-side brokerage with low-value fallback ───────────────
  // Step 1 — Base   : min(₹20 cap, baseRate% × sideValue)
  // Step 2 — Fallback: if Step 1 < ₹5  →  min(₹5, 2.5% × sideValue)
  // Step 3 — Zero guard: if sideValue == 0  →  ₹0.00
  // Step 4 — Round  : final result rounded to 2 dp (prevents ₹20.0000001 drift)
  double singleSideBrokerage(double sideValue, double baseRate, {double cap = 20.0}) {
    if (sideValue <= 0) return 0.0;
    final double base = min(cap, baseRate * sideValue); // hard cap enforced here
    final double raw  = (base < 5.0) ? min(5.0, 0.025 * sideValue) : base;
    return round2(raw);
  }

  // 1. Groww Brokerage (segment-aware)
  double growwCharges = 0.0;
  if (type == TradeType.intraday) {
    // 0.1% per side, hard cap ₹20 per side
    final double buyBrok  = singleSideBrokerage(buyTurnover,  0.001);
    final double sellBrok = singleSideBrokerage(sellTurnover, 0.001);
    growwCharges = round2(buyBrok + sellBrok);
  } else if (type == TradeType.delivery) {
    // 0.1% per side, hard cap ₹20 per side
    final double buyBrok  = singleSideBrokerage(buyTurnover,  0.001);
    final double sellBrok = singleSideBrokerage(sellTurnover, 0.001);
    growwCharges = round2(buyBrok + sellBrok);
  } else if (type == TradeType.futures || type == TradeType.options) {
    // Flat ₹20 per executed side — no percentage, no fallback
    growwCharges = (buyTurnover  > 0 ? 20.0 : 0.0)
                 + (sellTurnover > 0 ? 20.0 : 0.0);
  }

  // 2. Securities Transaction Tax (STT) — rounded to nearest whole rupee
  //    Rule: paise >= 50 → round UP, paise < 50 → round DOWN  (standard exchange rule)
  double stt = 0.0;
  if (type == TradeType.delivery) {
    stt = (turnover     * 0.001).roundToDouble();    // 0.1%   on buy + sell
  } else if (type == TradeType.intraday) {
    stt = (sellTurnover * 0.00025).roundToDouble();  // 0.025% on sell side only
  } else if (type == TradeType.futures) {
    stt = (sellTurnover * 0.0005).roundToDouble();   // 0.05% on sell side only
  } else if (type == TradeType.options) {
    stt = (sellTurnover * 0.0015).roundToDouble();   // 0.15% on sell premium (Groww options rate)
  }

  // 3. Stamp Duty (buy side only) — rounded to 2 dp
  double stampDuty = 0.0;
  if (type == TradeType.delivery) {
    stampDuty = round2(buyTurnover * 0.00015);  // 0.015%
  } else if (type == TradeType.intraday) {
    stampDuty = round2(buyTurnover * 0.00003);  // 0.003%
  } else if (type == TradeType.futures) {
    stampDuty = round2(buyTurnover * 0.00002);  // 0.002%
  } else if (type == TradeType.options) {
    stampDuty = round2(buyTurnover * 0.00003);  // 0.003%
  }

  // 4. Exchange Transaction Charges — 2D matrix: segment × exchange
  //    NSE/BSE rates are distinct for every segment.
  final double exchangeRate;
  switch (type) {
    case TradeType.intraday:
    case TradeType.delivery:
      exchangeRate = isNSE ? 0.0000297 : 0.0000375; // NSE 0.00297% | BSE 0.00375%
    case TradeType.futures:
      exchangeRate = isNSE ? 0.0000173 : 0.0;        // NSE 0.00173% | BSE ₹0.00
    case TradeType.options:
      exchangeRate = isNSE ? 0.0003503 : 0.0003250;  // NSE 0.03503% | BSE 0.03250%
  }
  final double exchangeCharges = round2(turnover * exchangeRate);


  // 5. SEBI Turnover Fees — ₹10 per crore (rounded to 2 dp)
  final double sebiFees = round2(turnover * 0.000001);

  // 6. DP Charges (delivery sell side only — fixed CDSL fee)
  double dpCharges = 0.0;
  if (type == TradeType.delivery && sellTurnover > 0) {
    dpCharges = 18.29;
  }

  // 7. GST — 18% on (Brokerage + Exchange Transaction Charges + SEBI Turnover Fees)
  final double gst = round2(
    (growwCharges + exchangeCharges + sebiFees) * 0.18,
  );

  // 8. Consolidation — all inputs already rounded; final totals rounded once more
  final double nonGrowwCharges = round2(
    stt + stampDuty + exchangeCharges + sebiFees + dpCharges + gst,
  );
  final double totalCharges = round2(growwCharges + nonGrowwCharges);
  final double netPL        = round2(grossPL - totalCharges);

  return CalculationResult(
    type: type,
    quantity: quantity,
    buyPrice: buyPrice,
    sellPrice: sellPrice,
    turnover: turnover,
    grossPL: grossPL,
    totalCharges: totalCharges,
    growwCharges: growwCharges,
    nonGrowwCharges: nonGrowwCharges,
    stt: stt,
    exchangeCharges: exchangeCharges,
    sebiFees: sebiFees,
    dpCharges: dpCharges,
    gst: gst,
    stampDuty: stampDuty,
    netPL: netPL,
  );
}
