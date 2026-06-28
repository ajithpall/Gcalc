import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/trade_log.dart';
import '../models/pnl_record.dart';
import '../models/trade_calculation.dart';

class JournalService {
  // Singleton pattern
  static final JournalService _instance = JournalService._internal();
  factory JournalService() => _instance;
  JournalService._internal();

  static const String _storageKey = 'trading_journal_logs';
  static const String _pnlStorageKey = 'pnl_daily_records';

  // State update notification mechanism
  final List<VoidCallback> _listeners = [];

  void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  void notifyListeners() {
    for (final listener in _listeners) {
      try {
        listener();
      } catch (_) {}
    }
  }

  // ============================================================
  // Trade Journal (Journal Screen)
  // ============================================================

  /// Load all trades from SharedPreferences, sorted newest-first.
  Future<List<TradeLog>> loadTrades() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? tradesJson = prefs.getString(_storageKey);
      if (tradesJson == null) return [];
      final List<dynamic> decodedList =
          jsonDecode(tradesJson) as List<dynamic>;
      final List<TradeLog> list = decodedList
          .map((item) => TradeLog.fromJson(item as Map<String, dynamic>))
          .toList();
      list.sort((a, b) => b.date.compareTo(a.date));
      return list;
    } catch (e) {
      return [];
    }
  }

  /// Save the full trades list to SharedPreferences.
  Future<bool> saveTrades(List<TradeLog> trades) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<Map<String, dynamic>> jsonList =
          trades.map((t) => t.toJson()).toList();
      final String encoded = jsonEncode(jsonList);
      return await prefs.setString(_storageKey, encoded);
    } catch (e) {
      return false;
    }
  }

  /// Add a single trade and return the updated sorted list.
  /// Also synchronizes the trade to the Record Book.
  Future<List<TradeLog>> addTrade(TradeLog trade) async {
    final List<TradeLog> currentTrades = await loadTrades();
    if (!currentTrades.any((t) => t.id == trade.id)) {
      currentTrades.add(trade);
      await saveTrades(currentTrades);
    }

    // Sync to P&L Records
    final List<PnlRecord> currentPnl = await loadPnlRecords();
    if (!currentPnl.any((r) => r.id == trade.id)) {
      currentPnl.add(trade.toPnlRecord());
      await _savePnlRecords(currentPnl);
    }

    notifyListeners();
    currentTrades.sort((a, b) => b.date.compareTo(a.date));
    return currentTrades;
  }

  /// Replace a trade by id.
  /// Also synchronizes the trade to the Record Book.
  Future<List<TradeLog>> updateTrade(TradeLog updated) async {
    final List<TradeLog> current = await loadTrades();
    final idx = current.indexWhere((t) => t.id == updated.id);
    if (idx != -1) {
      current[idx] = updated;
    } else {
      current.add(updated);
    }
    await saveTrades(current);

    // Sync to P&L Records
    final List<PnlRecord> currentPnl = await loadPnlRecords();
    final pnlIdx = currentPnl.indexWhere((r) => r.id == updated.id);
    if (pnlIdx != -1) {
      currentPnl[pnlIdx] = updated.toPnlRecord();
    } else {
      currentPnl.add(updated.toPnlRecord());
    }
    await _savePnlRecords(currentPnl);

    notifyListeners();
    current.sort((a, b) => b.date.compareTo(a.date));
    return current;
  }

  /// Delete a trade by id.
  /// Also deletes the trade from the Record Book.
  Future<List<TradeLog>> deleteTrade(String id) async {
    final List<TradeLog> currentTrades = await loadTrades();
    currentTrades.removeWhere((t) => t.id == id);
    await saveTrades(currentTrades);

    // Sync to P&L Records
    final List<PnlRecord> currentPnl = await loadPnlRecords();
    currentPnl.removeWhere((r) => r.id == id);
    await _savePnlRecords(currentPnl);

    notifyListeners();
    return currentTrades;
  }

  /// Clear all trades and P&L records.
  Future<bool> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    final res1 = await prefs.remove(_storageKey);
    final res2 = await prefs.remove(_pnlStorageKey);
    notifyListeners();
    return res1 && res2;
  }

  /// Returns all OPEN delivery trades from the journal store.
  List<TradeLog> getOpenDeliveryTrades(List<TradeLog> trades) {
    return trades
        .where((t) =>
            t.type == TradeType.delivery &&
            t.status == PositionStatus.open)
        .toList();
  }

  /// Close an open journal delivery trade: recalculate P&L, set status to CLOSED.
  /// Also synchronizes the closed state to the Record Book.
  Future<List<TradeLog>> closeJournalPosition({
    required String id,
    required double sellPrice,
    required DateTime sellDate,
    bool isNSE = true,
  }) async {
    final List<TradeLog> current = await loadTrades();
    final idx = current.indexWhere((t) => t.id == id);
    if (idx == -1) return current;

    final open = current[idx];
    final calc = calculateGrowwCharges(
      type: TradeType.delivery,
      quantity: open.quantity,
      buyPrice: open.buyPrice,
      sellPrice: sellPrice,
      isNSE: isNSE,
    );

    final updated = open.copyWith(
      sellPrice: sellPrice,
      sellDate: sellDate,
      grossPL: calc.grossPL,
      totalCharges: calc.totalCharges,
      netPL: calc.netPL,
      status: PositionStatus.closed,
    );

    current[idx] = updated;
    await saveTrades(current);

    // Sync to P&L Records
    final List<PnlRecord> currentPnl = await loadPnlRecords();
    final pnlIdx = currentPnl.indexWhere((r) => r.id == id);
    if (pnlIdx != -1) {
      currentPnl[pnlIdx] = updated.toPnlRecord();
    } else {
      currentPnl.add(updated.toPnlRecord());
    }
    await _savePnlRecords(currentPnl);

    notifyListeners();
    current.sort((a, b) => b.date.compareTo(a.date));
    return current;
  }

  // ============================================================
  // P&L Record Book (Record Screen)
  // ============================================================

  Future<List<PnlRecord>> loadPnlRecords() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? json = prefs.getString(_pnlStorageKey);
      if (json == null) return [];
      final List<dynamic> decoded = jsonDecode(json) as List<dynamic>;
      final List<PnlRecord> list = decoded
          .map((item) => PnlRecord.fromJson(item as Map<String, dynamic>))
          .toList();
      list.sort((a, b) => b.date.compareTo(a.date));
      return list;
    } catch (e) {
      return [];
    }
  }

  /// Add a single P&L record and return the updated sorted list.
  /// Also synchronizes the record to the Journal.
  Future<List<PnlRecord>> addPnlRecord(PnlRecord record) async {
    final List<PnlRecord> current = await loadPnlRecords();
    if (!current.any((r) => r.id == record.id)) {
      current.add(record);
      await _savePnlRecords(current);
    }

    // Sync to TradeLog
    final List<TradeLog> currentTrades = await loadTrades();
    if (!currentTrades.any((t) => t.id == record.id)) {
      currentTrades.add(record.toTradeLog());
      await saveTrades(currentTrades);
    }

    notifyListeners();
    current.sort((a, b) => b.date.compareTo(a.date));
    return current;
  }

  /// Replace a PnlRecord by id.
  /// Also synchronizes the record to the Journal.
  Future<List<PnlRecord>> updatePnlRecord(PnlRecord updated) async {
    final List<PnlRecord> current = await loadPnlRecords();
    final idx = current.indexWhere((r) => r.id == updated.id);
    if (idx != -1) {
      current[idx] = updated;
    } else {
      current.add(updated);
    }
    await _savePnlRecords(current);

    // Sync to TradeLog
    final List<TradeLog> currentTrades = await loadTrades();
    final tradeIdx = currentTrades.indexWhere((t) => t.id == updated.id);
    if (tradeIdx != -1) {
      currentTrades[tradeIdx] = updated.toTradeLog();
    } else {
      currentTrades.add(updated.toTradeLog());
    }
    await saveTrades(currentTrades);

    notifyListeners();
    current.sort((a, b) => b.date.compareTo(a.date));
    return current;
  }

  /// Delete a PnlRecord by id.
  /// Also deletes the trade from the Journal.
  Future<List<PnlRecord>> deletePnlRecord(String id) async {
    final List<PnlRecord> current = await loadPnlRecords();
    current.removeWhere((r) => r.id == id);
    await _savePnlRecords(current);

    // Sync to TradeLog
    final List<TradeLog> currentTrades = await loadTrades();
    currentTrades.removeWhere((t) => t.id == id);
    await saveTrades(currentTrades);

    notifyListeners();
    return current;
  }

  /// Returns all OPEN delivery positions from the record-book store.
  List<PnlRecord> getOpenDeliveryPositions(List<PnlRecord> records) {
    return records
        .where((r) =>
            r.tradeType == TradeType.delivery &&
            r.status == PositionStatus.open)
        .toList();
  }

  /// Closes an open delivery position: recalculates P&L and saves.
  /// Also synchronizes the closed state to the Journal.
  Future<List<PnlRecord>> closePnlPosition({
    required String id,
    required double sellPrice,
    required DateTime sellDate,
    bool isNSE = true,
  }) async {
    final List<PnlRecord> current = await loadPnlRecords();
    final idx = current.indexWhere((r) => r.id == id);
    if (idx == -1) return current;

    final open = current[idx];
    final calc = calculateGrowwCharges(
      type: TradeType.delivery,
      quantity: open.quantity,
      buyPrice: open.buyPrice,
      sellPrice: sellPrice,
      isNSE: isNSE,
    );

    final updated = open.copyWith(
      sellPrice: sellPrice,
      sellDate: sellDate,
      grossPL: calc.grossPL,
      totalCharges: calc.totalCharges,
      netPL: calc.netPL,
      status: PositionStatus.closed,
    );
    current[idx] = updated;
    await _savePnlRecords(current);

    // Sync to TradeLog
    final List<TradeLog> currentTrades = await loadTrades();
    final tradeIdx = currentTrades.indexWhere((t) => t.id == id);
    if (tradeIdx != -1) {
      currentTrades[tradeIdx] = updated.toTradeLog();
    } else {
      currentTrades.add(updated.toTradeLog());
    }
    await saveTrades(currentTrades);

    notifyListeners();
    current.sort((a, b) => b.date.compareTo(a.date));
    return current;
  }

  /// Bulk-add multiple P&L records at once (used by import pipeline).
  /// Avoids N separate SharedPreferences read/write cycles.
  /// Skips records whose composite trade key already exists. Syncs to TradeLog store.
  Future<int> addPnlRecordsBulk(List<PnlRecord> newRecords) async {
    if (newRecords.isEmpty) return 0;

    final List<PnlRecord> current = await loadPnlRecords();
    
    // Map existing database occurrences
    final Map<String, int> dbCounts = {};
    for (final r in current) {
      final key = r.uniqueTradeKey;
      dbCounts[key] = (dbCounts[key] ?? 0) + 1;
    }

    final List<PnlRecord> toAdd = [];
    final Map<String, int> fileCounts = {};

    for (final record in newRecords) {
      final key = record.uniqueTradeKey;
      fileCounts[key] = (fileCounts[key] ?? 0) + 1;

      final existingCountInDB = dbCounts[key] ?? 0;
      final currentSeenInFile = fileCounts[key] ?? 0;

      if (currentSeenInFile <= existingCountInDB) {
        // This instance of the row is already in the database. Skip it!
      } else {
        toAdd.add(record);
        // Increment count dynamically to handle identical items in the incoming list
        dbCounts[key] = existingCountInDB + 1;
      }
    }

    if (toAdd.isEmpty) return 0;

    current.addAll(toAdd);
    await _savePnlRecords(current);

    // Sync all new records to TradeLog store
    final List<TradeLog> currentTrades = await loadTrades();
    final existingTradeIds = currentTrades.map((t) => t.id).toSet();
    for (final record in toAdd) {
      if (!existingTradeIds.contains(record.id)) {
        currentTrades.add(record.toTradeLog());
      }
    }
    await saveTrades(currentTrades);

    notifyListeners();
    return toAdd.length;
  }

  Future<void> _savePnlRecords(List<PnlRecord> records) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<Map<String, dynamic>> jsonList =
          records.map((r) => r.toJson()).toList();
      await prefs.setString(_pnlStorageKey, jsonEncode(jsonList));
    } catch (_) {}
  }
}
