import 'trade_calculation.dart';
import 'trade_log.dart';

/// Status of a delivery position — OPEN (holding, not yet sold) or CLOSED (realized P&L).
enum PositionStatus {
  open,
  closed;

  String toJson() => name;

  static PositionStatus fromJson(String? value) {
    if (value == null) return PositionStatus.closed; // backward-compat default
    return PositionStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => PositionStatus.closed,
    );
  }
}

/// Represents a single P&L record entry in the Daily P&L Record Book.
/// Users provide: stock name, exchange, trade type, qty, buy price, sell price (optional for Delivery).
/// Everything else is auto-calculated.
class PnlRecord {
  final String id;
  final DateTime date;
  final String exchange; // 'NSE' or 'BSE'
  final String stockName; // user-input stock name
  final int quantity;
  final double buyPrice;
  final double? sellPrice; // null if position is OPEN
  final DateTime? sellDate; // null if position is OPEN
  final TradeType tradeType;
  final double grossPL;
  final double totalCharges;
  final double netPL;
  final PositionStatus status; // OPEN = holding; CLOSED = realized

  const PnlRecord({
    required this.id,
    required this.date,
    required this.exchange,
    required this.stockName,
    required this.quantity,
    required this.buyPrice,
    this.sellPrice,
    this.sellDate,
    required this.tradeType,
    required this.grossPL,
    required this.totalCharges,
    required this.netPL,
    PositionStatus? status,
  }) : status = status ??
            ((tradeType == TradeType.delivery && sellPrice == null)
                ? PositionStatus.open
                : PositionStatus.closed);

  /// Creates a CLOSED PnlRecord from a full CalculationResult (both buy + sell filled).
  factory PnlRecord.fromCalculation({
    required String id,
    required DateTime date,
    required String exchange,
    required String stockName,
    required CalculationResult calc,
    DateTime? sellDate,
  }) {
    return PnlRecord(
      id: id,
      date: date,
      exchange: exchange,
      stockName: stockName.trim().isEmpty
          ? 'UNKNOWN'
          : stockName.trim().toUpperCase(),
      quantity: calc.quantity,
      buyPrice: calc.buyPrice,
      sellPrice: calc.sellPrice,
      sellDate: sellDate,
      tradeType: calc.type,
      grossPL: calc.grossPL,
      totalCharges: calc.totalCharges,
      netPL: calc.netPL,
      status: PositionStatus.closed,
    );
  }

  /// Creates an OPEN (buy-only) Delivery record — no sell price yet.
  factory PnlRecord.openPosition({
    required String id,
    required DateTime buyDate,
    required String exchange,
    required String stockName,
    required int quantity,
    required double buyPrice,
  }) {
    return PnlRecord(
      id: id,
      date: buyDate,
      exchange: exchange,
      stockName: stockName.trim().isEmpty
          ? 'UNKNOWN'
          : stockName.trim().toUpperCase(),
      quantity: quantity,
      buyPrice: buyPrice,
      sellPrice: null,
      sellDate: null,
      tradeType: TradeType.delivery,
      grossPL: 0.0,
      totalCharges: 0.0,
      netPL: 0.0,
      status: PositionStatus.open,
    );
  }

  /// Returns a copy of this record with the given fields overridden.
  PnlRecord copyWith({
    String? id,
    DateTime? date,
    String? exchange,
    String? stockName,
    int? quantity,
    double? sellPrice,
    DateTime? sellDate,
    TradeType? tradeType,
    double? grossPL,
    double? totalCharges,
    double? netPL,
    PositionStatus? status,
  }) {
    return PnlRecord(
      id: id ?? this.id,
      date: date ?? this.date,
      exchange: exchange ?? this.exchange,
      stockName: stockName ?? this.stockName,
      quantity: quantity ?? this.quantity,
      buyPrice: buyPrice, // buy price is immutable
      sellPrice: sellPrice ?? this.sellPrice,
      sellDate: sellDate ?? this.sellDate,
      tradeType: tradeType ?? this.tradeType,
      grossPL: grossPL ?? this.grossPL,
      totalCharges: totalCharges ?? this.totalCharges,
      netPL: netPL ?? this.netPL,
      status: status ?? this.status,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.toIso8601String(),
        'exchange': exchange,
        'stockName': stockName,
        'quantity': quantity,
        'buyPrice': buyPrice,
        'sellPrice': sellPrice,
        'sellDate': sellDate?.toIso8601String(),
        'tradeType': tradeType.toJson(),
        'grossPL': grossPL,
        'totalCharges': totalCharges,
        'netPL': netPL,
        'status': status.toJson(),
      };

  factory PnlRecord.fromJson(Map<String, dynamic> json) {
    final tradeType = TradeType.fromJson(json['tradeType'] as String);
    final statusVal = json['status'] as String?;
    final status = statusVal != null
        ? PositionStatus.fromJson(statusVal)
        : (tradeType == TradeType.delivery
            ? PositionStatus.open
            : PositionStatus.closed);

    return PnlRecord(
      id: json['id'] as String,
      date: DateTime.parse(json['date'] as String),
      exchange: json['exchange'] as String? ?? 'NSE',
      stockName: json['stockName'] as String? ?? 'UNKNOWN',
      quantity: json['quantity'] as int,
      buyPrice: (json['buyPrice'] as num).toDouble(),
      sellPrice: json['sellPrice'] != null
          ? (json['sellPrice'] as num).toDouble()
          : null,
      sellDate: json['sellDate'] != null
          ? DateTime.parse(json['sellDate'] as String)
          : null,
      tradeType: tradeType,
      grossPL: (json['grossPL'] as num).toDouble(),
      totalCharges: (json['totalCharges'] as num).toDouble(),
      netPL: (json['netPL'] as num).toDouble(),
      status: status,
    );
  }

  TradeLog toTradeLog() {
    return TradeLog(
      id: id,
      symbol: stockName,
      type: tradeType,
      date: date,
      quantity: quantity,
      buyPrice: buyPrice,
      sellPrice: sellPrice,
      sellDate: sellDate,
      grossPL: grossPL,
      totalCharges: totalCharges,
      netPL: netPL,
      note: '',
      status: status,
    );
  }
}
