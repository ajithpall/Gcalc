import 'trade_calculation.dart';
import 'pnl_record.dart';

class TradeLog {
  final String id;
  final String symbol;
  final TradeType type;
  final DateTime date;
  final int quantity;
  final double buyPrice;
  final double? sellPrice; // null if Delivery position is OPEN
  final DateTime? sellDate; // null if position is OPEN
  final double grossPL;
  final double totalCharges;
  final double netPL;
  final String note;
  final PositionStatus status; // OPEN = holding; CLOSED = realized

  TradeLog({
    required this.id,
    required this.symbol,
    required this.type,
    required this.date,
    required this.quantity,
    required this.buyPrice,
    this.sellPrice,
    this.sellDate,
    required this.grossPL,
    required this.totalCharges,
    required this.netPL,
    required this.note,
    PositionStatus? status,
  }) : status = status ??
            ((type == TradeType.delivery && sellPrice == null)
                ? PositionStatus.open
                : PositionStatus.closed);

  factory TradeLog.fromCalculation({
    required String id,
    required String symbol,
    required CalculationResult calc,
    required DateTime date,
    required String note,
    DateTime? sellDate,
  }) {
    return TradeLog(
      id: id,
      symbol: symbol.trim().isEmpty
          ? calc.type.displayName
          : symbol.trim().toUpperCase(),
      type: calc.type,
      date: date,
      quantity: calc.quantity,
      buyPrice: calc.buyPrice,
      sellPrice: calc.sellPrice,
      sellDate: sellDate,
      grossPL: calc.grossPL,
      totalCharges: calc.totalCharges,
      netPL: calc.netPL,
      note: note,
      status: PositionStatus.closed,
    );
  }

  /// Creates an OPEN delivery journal log (buy side only, no sell yet).
  factory TradeLog.openDelivery({
    required String id,
    required String symbol,
    required int quantity,
    required double buyPrice,
    required DateTime buyDate,
    required String note,
  }) {
    return TradeLog(
      id: id,
      symbol: symbol.trim().isEmpty ? 'UNKNOWN' : symbol.trim().toUpperCase(),
      type: TradeType.delivery,
      date: buyDate,
      quantity: quantity,
      buyPrice: buyPrice,
      sellPrice: null,
      sellDate: null,
      grossPL: 0.0,
      totalCharges: 0.0,
      netPL: 0.0,
      note: note,
      status: PositionStatus.open,
    );
  }

  /// Returns a copy with overridden fields — used when closing an open position.
  TradeLog copyWith({
    String? id,
    String? symbol,
    TradeType? type,
    DateTime? date,
    int? quantity,
    double? sellPrice,
    DateTime? sellDate,
    double? grossPL,
    double? totalCharges,
    double? netPL,
    String? note,
    PositionStatus? status,
  }) {
    return TradeLog(
      id: id ?? this.id,
      symbol: symbol ?? this.symbol,
      type: type ?? this.type,
      date: date ?? this.date,
      quantity: quantity ?? this.quantity,
      buyPrice: buyPrice, // buy price is immutable
      sellPrice: sellPrice ?? this.sellPrice,
      sellDate: sellDate ?? this.sellDate,
      grossPL: grossPL ?? this.grossPL,
      totalCharges: totalCharges ?? this.totalCharges,
      netPL: netPL ?? this.netPL,
      note: note ?? this.note,
      status: status ?? this.status,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'symbol': symbol,
      'type': type.toJson(),
      'date': date.toIso8601String(),
      'quantity': quantity,
      'buyPrice': buyPrice,
      'sellPrice': sellPrice,
      'sellDate': sellDate?.toIso8601String(),
      'grossPL': grossPL,
      'totalCharges': totalCharges,
      'netPL': netPL,
      'note': note,
      'status': status.toJson(),
    };
  }

  factory TradeLog.fromJson(Map<String, dynamic> json) {
    final type = TradeType.fromJson(json['type'] as String);
    final statusVal = json['status'] as String?;
    final status = statusVal != null
        ? PositionStatus.fromJson(statusVal)
        : (type == TradeType.delivery
            ? PositionStatus.open
            : PositionStatus.closed);

    return TradeLog(
      id: json['id'] as String,
      symbol: json['symbol'] as String,
      type: type,
      date: DateTime.parse(json['date'] as String),
      quantity: json['quantity'] as int,
      buyPrice: (json['buyPrice'] as num).toDouble(),
      sellPrice: json['sellPrice'] != null
          ? (json['sellPrice'] as num).toDouble()
          : null,
      sellDate: json['sellDate'] != null
          ? DateTime.parse(json['sellDate'] as String)
          : null,
      grossPL: (json['grossPL'] as num).toDouble(),
      totalCharges: (json['totalCharges'] as num).toDouble(),
      netPL: (json['netPL'] as num).toDouble(),
      note: json['note'] as String,
      status: status,
    );
  }

  PnlRecord toPnlRecord() {
    return PnlRecord(
      id: id,
      date: date,
      exchange: 'NSE', // default
      stockName: symbol,
      quantity: quantity,
      buyPrice: buyPrice,
      sellPrice: sellPrice,
      sellDate: sellDate,
      tradeType: type,
      grossPL: grossPL,
      totalCharges: totalCharges,
      netPL: netPL,
      status: status,
    );
  }
}
