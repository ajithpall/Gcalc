import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:file_saver/file_saver.dart';
import 'package:file_picker/file_picker.dart';
import '../services/journal_service.dart';
import '../models/pnl_record.dart';
import '../models/trade_calculation.dart';

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  final JournalService _journalService = JournalService();
  List<PnlRecord> _records = [];
  bool _isLoading = false;

  // Separate loading states for each action
  bool _isImportingStocks = false;
  bool _isImportingFnO = false;
  bool _isExportingStocks = false;
  bool _isExportingFnO = false;

  final _currencyFormat =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

  @override
  void initState() {
    super.initState();
    _journalService.addListener(_onJournalChanged);
    _loadRecords();
  }

  @override
  void dispose() {
    _journalService.removeListener(_onJournalChanged);
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

  // ════════════════════════════════════════════════════════════════
  //  DATE PARSING HELPER
  // ════════════════════════════════════════════════════════════════

  DateTime _parseGrowwDate(String dateStr) {
    try {
      if (dateStr.trim().isEmpty) return DateTime.now();
      // Groww format splits using dashes: DD-MM-YYYY or slashes: DD/MM/YYYY
      String normalized = dateStr.trim().replaceAll('/', '-');
      List<String> parts = normalized.split('-');
      if (parts.length == 3) {
        int day = int.parse(parts[0]);
        int month = int.parse(parts[1]);
        int year = int.parse(parts[2]);
        return DateTime(year, month, day);
      }
    } catch (_) {}
    return DateTime.now(); // Fallback safely to prevent crashing
  }



  String _getCellValueAsString(dynamic cell) {
    if (cell == null) return "";
    if (cell is Map) return cell['value']?.toString() ?? "";
    // If it's a package CellValue object, extract its inner .value property
    try {
      return cell.value?.toString() ?? "";
    } catch (_) {
      return cell.toString();
    }
  }

  // ════════════════════════════════════════════════════════════════
  //  IMPORT — Groww Sheet Parser
  // ════════════════════════════════════════════════════════════════

  /// Core import logic for both Stocks and F&O Groww reports.
  /// [isFnO] = true maps remarks to futures/options; false maps to intraday/delivery.
  Future<void> _importGrowwSheet({required bool isFnO}) async {
    // Set loading state
    setState(() {
      if (isFnO) {
        _isImportingFnO = true;
      } else {
        _isImportingStocks = true;
      }
    });

    try {
      // 1. Pick file
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        withData: true,
      );

      if (result == null || result.files.isEmpty || result.files.first.bytes == null) {
        _showSnack('No file selected.', isError: true);
        return;
      }

      final bytes = result.files.first.bytes!;

      // 2. Decode Excel
      final excel = Excel.decodeBytes(bytes);
      if (excel.tables.isEmpty) {
        _showSnack('Excel file contains no sheets.', isError: true);
        return;
      }

      // 3. Find target sheet — use first sheet, or iterate to find one with "Stock name"
      Sheet? targetSheet;
      for (final sheetName in excel.tables.keys) {
        targetSheet = excel.tables[sheetName];
        if (targetSheet != null) break;
      }

      if (targetSheet == null || targetSheet.rows.isEmpty) {
        _showSnack('No data found in the Excel file.', isError: true);
        return;
      }

      // 4. Dynamic header row search — scan for "Stock name" in column A
      int headerRowIndex = -1;
      for (int r = 0; r < targetSheet.rows.length; r++) {
        final row = targetSheet.rows[r];
        if (row.isNotEmpty) {
          final cellText = _getCellValueAsString(row[0]).trim();
          if (cellText.toLowerCase() == 'stock name') {
            headerRowIndex = r;
            break;
          }
        }
      }

      if (headerRowIndex == -1) {
        _showSnack('Could not locate "Stock name" header row in the sheet.', isError: true);
        return;
      }

      // 5. Parse data rows after header
      final List<PnlRecord> parsedRecords = [];
      int skippedRows = 0;

      for (int r = headerRowIndex + 1; r < targetSheet.rows.length; r++) {
        try {
          final row = targetSheet.rows[r];
          if (row.isEmpty) continue;

          // Column A (0): Stock name
          String stockName = row.isNotEmpty ? _getCellValueAsString(row[0]) : "";
          if (stockName.isEmpty) continue; // skip empty rows

          // Column C (2): Quantity
          int qty = row.length > 2 ? (int.tryParse(_getCellValueAsString(row[2])) ?? 0) : 0;
          if (qty <= 0) {
            skippedRows++;
            continue;
          }

          // For Buy Date (Column Index 3):
          String buyDateRaw = row.length > 3 ? _getCellValueAsString(row[3]) : "";
          if (buyDateRaw.isEmpty) {
            skippedRows++;
            continue;
          }
          DateTime buyDate = _parseGrowwDate(buyDateRaw);

          // Column E (4): Buy price
          double buyPrice = row.length > 4 ? (double.tryParse(_getCellValueAsString(row[4])) ?? 0.0) : 0.0;
          if (buyPrice <= 0) {
            skippedRows++;
            continue;
          }

          // For Sell Date (Column Index 6):
          String sellDateRaw = row.length > 6 ? _getCellValueAsString(row[6]) : "";
          DateTime sellDate = _parseGrowwDate(sellDateRaw);

          // Column H (7): Sell price
          double sellPrice = row.length > 7 ? (double.tryParse(_getCellValueAsString(row[7])) ?? 0.0) : 0.0;

          // Column K (10): Remark — determines segment
          String remark = row.length > 10 ? _getCellValueAsString(row[10]) : "";

          TradeType tradeType;
          if (isFnO) {
            // F&O import: map to futures/options based on remark
            if (remark.toLowerCase().contains('option')) {
              tradeType = TradeType.options;
            } else {
              tradeType = TradeType.futures;
            }
          } else {
            // Stocks import: map to intraday/delivery based on remark
            if (remark.toLowerCase().contains('intraday')) {
              tradeType = TradeType.intraday;
            } else {
              tradeType = TradeType.delivery;
            }
          }

          // Generate unique ID and row key
          final id = '${DateTime.now().microsecondsSinceEpoch}_$r';
          final rowKey = row.map((cell) => _getCellValueAsString(cell).trim()).join('_');

          if (sellPrice > 0) {
            // CLOSED trade — calculate charges
            final calc = calculateGrowwCharges(
              type: tradeType,
              quantity: qty,
              buyPrice: buyPrice,
              sellPrice: sellPrice,
              isNSE: true,
            );

            parsedRecords.add(PnlRecord.fromCalculation(
              id: id,
              date: buyDate,
              exchange: 'NSE',
              stockName: stockName.toUpperCase(),
              calc: calc,
              sellDate: sellDate,
              rowKey: rowKey,
            ));
          } else {
            // OPEN position (no sell price)
            parsedRecords.add(PnlRecord.openPosition(
              id: id,
              buyDate: buyDate,
              exchange: 'NSE',
              stockName: stockName.toUpperCase(),
              quantity: qty,
              buyPrice: buyPrice,
              rowKey: rowKey,
            ));
          }
        } catch (e) {
          skippedRows++;
        }
      }

      if (parsedRecords.isEmpty) {
        _showSnack('No valid trade rows found in the file.', isError: true);
        return;
      }

      // ── Phase A: Map existing database occurrences ──
      final existingRecords = await _journalService.loadPnlRecords();
      final Map<String, int> dbCounts = {};
      for (final trade in existingRecords) {
        final key = trade.uniqueTradeKey;
        dbCounts[key] = (dbCounts[key] ?? 0) + 1;
      }

      // ── Phase B: Parse incoming rows with a Local File Counter ──
      final List<PnlRecord> uniqueNewRecords = [];
      int duplicateCount = 0;
      final Map<String, int> fileCounts = {};

      for (final record in parsedRecords) {
        final key = record.uniqueTradeKey;
        fileCounts[key] = (fileCounts[key] ?? 0) + 1;

        final existingCountInDB = dbCounts[key] ?? 0;
        final currentSeenInFile = fileCounts[key] ?? 0;

        if (currentSeenInFile <= existingCountInDB) {
          // This instance of the row is already in the database from a previous upload. Skip it!
          duplicateCount++;
        } else {
          uniqueNewRecords.add(record);
        }
      }

      final label = isFnO ? 'F&O' : 'Stocks';

      // ── Condition 1: Full sheet duplicate — skip entirely ──
      if (uniqueNewRecords.isEmpty) {
        _showSnack(
          'This data already exists! File skipped to prevent duplication.',
          isError: true,
        );
        return;
      }

      // ── Condition 2: Partial overlap — insert only new rows ──
      final inserted = await _journalService.addPnlRecordsBulk(uniqueNewRecords);
      await _loadRecords(silent: true);

      String msg;
      if (duplicateCount > 0) {
        msg = 'Import complete! $inserted new $label trades added, $duplicateCount duplicate trades skipped.';
      } else {
        msg = '$inserted $label trade(s) imported successfully.';
      }
      if (skippedRows > 0) {
        msg += ' ($skippedRows rows skipped due to missing data.)';
      }
      _showSnack(msg);
    } catch (e) {
      _showSnack('Import failed: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          if (isFnO) {
            _isImportingFnO = false;
          } else {
            _isImportingStocks = false;
          }
        });
      }
    }
  }

  // ════════════════════════════════════════════════════════════════
  //  EXPORT — Groww Mirror Template Generator
  // ════════════════════════════════════════════════════════════════

  /// Core export logic for both Stocks and F&O.
  /// Generates a Groww-format .xlsx with 25 reserved metadata rows,
  /// headers at row 26, and data from row 27.
  Future<void> _exportGrowwSheet({required bool isFnO}) async {
    // Filter records by segment
    final List<PnlRecord> filtered;
    final String label;

    if (isFnO) {
      filtered = _records
          .where((r) =>
              r.tradeType == TradeType.futures ||
              r.tradeType == TradeType.options)
          .toList();
      label = 'F&O';
    } else {
      filtered = _records
          .where((r) =>
              r.tradeType == TradeType.intraday ||
              r.tradeType == TradeType.delivery)
          .toList();
      label = 'Stocks';
    }

    if (filtered.isEmpty) {
      _showSnack('No $label trade records available to export.', isError: true);
      return;
    }

    setState(() {
      if (isFnO) {
        _isExportingFnO = true;
      } else {
        _isExportingStocks = true;
      }
    });

    try {
      var excel = Excel.createExcel();
      String defaultSheet = excel.getDefaultSheet() ?? 'Sheet1';
      Sheet sheet = excel[defaultSheet];

      // ── Styles ───────────────────────────────────────────────
      CellStyle titleStyle = CellStyle(
        backgroundColorHex: ExcelColor.fromHexString('#FF0F172A'),
        fontColorHex: ExcelColor.fromHexString('#FFFFFFFF'),
        bold: true,
        fontSize: 14,
        horizontalAlign: HorizontalAlign.Center,
      );

      CellStyle metaLabelStyle = CellStyle(
        fontColorHex: ExcelColor.fromHexString('#FF94A3B8'),
        bold: true,
        fontSize: 10,
      );

      CellStyle tableHeaderStyle = CellStyle(
        backgroundColorHex: ExcelColor.fromHexString('#FF1E293B'),
        fontColorHex: ExcelColor.fromHexString('#FFFFFFFF'),
        bold: true,
        fontSize: 11,
        horizontalAlign: HorizontalAlign.Center,
      );

      CellStyle dataStyle = CellStyle(
        fontSize: 11,
        horizontalAlign: HorizontalAlign.Center,
      );

      // ── Rows 1-25 (indices 0-24): Reserved metadata area ────
      // Row 1: Merged title
      sheet.merge(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0),
        CellIndex.indexByColumnRow(columnIndex: 10, rowIndex: 0),
        customValue: TextCellValue('GROWW - $label P&L REPORT'),
      );
      sheet.updateCell(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0),
        TextCellValue('GROWW - $label P&L REPORT'),
        cellStyle: titleStyle,
      );

      // Row 3: Client info placeholder
      sheet.updateCell(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 2),
        TextCellValue('Client Name:'),
        cellStyle: metaLabelStyle,
      );
      sheet.updateCell(
        CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 2),
        TextCellValue('—'),
      );

      // Row 4: Date range placeholder
      sheet.updateCell(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 3),
        TextCellValue('Report Period:'),
        cellStyle: metaLabelStyle,
      );
      sheet.updateCell(
        CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 3),
        TextCellValue('All records'),
      );

      // Row 5: Generated timestamp
      sheet.updateCell(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 4),
        TextCellValue('Generated:'),
        cellStyle: metaLabelStyle,
      );
      sheet.updateCell(
        CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 4),
        TextCellValue(DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())),
      );

      // Rows 6-25 remain empty (reserved layout space)

      // ── Row 26 (index 25): Groww-format column headers ──────
      final List<String> growwHeaders = [
        'Stock name',        // A
        'ISIN',              // B
        'Quantity',          // C
        'Buy date',          // D
        'Buy price',         // E
        'Buy value',         // F
        'Sell date',         // G
        'Sell price',        // H
        'Sell value',        // I
        'Realized P&L',      // J
        'Remark',            // K
      ];

      for (int col = 0; col < growwHeaders.length; col++) {
        sheet.updateCell(
          CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 25),
          TextCellValue(growwHeaders[col]),
          cellStyle: tableHeaderStyle,
        );
      }

      // ── Row 27+ (index 26+): Data rows ─────────────────────
      final dateFormat = DateFormat('dd/MM/yyyy');

      for (int i = 0; i < filtered.length; i++) {
        final record = filtered[i];
        final int rowIndex = 26 + i;

        // A: Stock name
        sheet.updateCell(
          CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIndex),
          TextCellValue(record.stockName),
          cellStyle: dataStyle,
        );

        // B: ISIN (not stored — leave empty)
        sheet.updateCell(
          CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: rowIndex),
          TextCellValue(''),
          cellStyle: dataStyle,
        );

        // C: Quantity
        sheet.updateCell(
          CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: rowIndex),
          IntCellValue(record.quantity),
          cellStyle: dataStyle,
        );

        // D: Buy date
        sheet.updateCell(
          CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: rowIndex),
          TextCellValue(dateFormat.format(record.date)),
          cellStyle: dataStyle,
        );

        // E: Buy price
        sheet.updateCell(
          CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: rowIndex),
          DoubleCellValue(record.buyPrice),
          cellStyle: dataStyle,
        );

        // F: Buy value (quantity * buyPrice)
        sheet.updateCell(
          CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: rowIndex),
          DoubleCellValue(record.quantity * record.buyPrice),
          cellStyle: dataStyle,
        );

        // G: Sell date
        if (record.sellDate != null) {
          sheet.updateCell(
            CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: rowIndex),
            TextCellValue(dateFormat.format(record.sellDate!)),
            cellStyle: dataStyle,
          );
        } else {
          sheet.updateCell(
            CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: rowIndex),
            TextCellValue(''),
            cellStyle: dataStyle,
          );
        }

        // H: Sell price
        if (record.sellPrice != null) {
          sheet.updateCell(
            CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: rowIndex),
            DoubleCellValue(record.sellPrice!),
            cellStyle: dataStyle,
          );
        } else {
          sheet.updateCell(
            CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: rowIndex),
            TextCellValue(''),
            cellStyle: dataStyle,
          );
        }

        // I: Sell value (quantity * sellPrice)
        if (record.sellPrice != null) {
          sheet.updateCell(
            CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: rowIndex),
            DoubleCellValue(record.quantity * record.sellPrice!),
            cellStyle: dataStyle,
          );
        } else {
          sheet.updateCell(
            CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: rowIndex),
            TextCellValue(''),
            cellStyle: dataStyle,
          );
        }

        // J: Realized P&L
        sheet.updateCell(
          CellIndex.indexByColumnRow(columnIndex: 9, rowIndex: rowIndex),
          DoubleCellValue(record.netPL),
          cellStyle: dataStyle,
        );

        // K: Remark — auto-insert based on tradeType
        String remark;
        switch (record.tradeType) {
          case TradeType.intraday:
            remark = 'Intraday trade';
          case TradeType.delivery:
            remark = 'Delivery trade';
          case TradeType.futures:
            remark = 'Futures trade';
          case TradeType.options:
            remark = 'Options trade';
        }
        sheet.updateCell(
          CellIndex.indexByColumnRow(columnIndex: 10, rowIndex: rowIndex),
          TextCellValue(remark),
          cellStyle: dataStyle,
        );
      }

      // Save
      final fileBytes = excel.save();
      if (fileBytes != null) {
        final fileName = isFnO
            ? 'Groww_FnO_PnL_${DateFormat('yyyyMMdd').format(DateTime.now())}'
            : 'Groww_Stocks_PnL_${DateFormat('yyyyMMdd').format(DateTime.now())}';

        await FileSaver.instance.saveFile(
          name: fileName,
          bytes: Uint8List.fromList(fileBytes),
          fileExtension: 'xlsx',
          mimeType: MimeType.microsoftExcel,
        );
        _showSnack('$label P&L report exported successfully (${filtered.length} records).');
      } else {
        _showSnack('Failed to compile Excel spreadsheet.', isError: true);
      }
    } catch (e) {
      _showSnack('Export failed: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          if (isFnO) {
            _isExportingFnO = false;
          } else {
            _isExportingStocks = false;
          }
        });
      }
    }
  }

  // ════════════════════════════════════════════════════════════════
  //  SNACKBAR
  // ════════════════════════════════════════════════════════════════

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(msg)),
          ],
        ),
        backgroundColor: isError ? const Color(0xFFF43F5E) : const Color(0xFF059669),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  //  BUILD
  // ════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final closedRecords =
        _records.where((r) => r.status == PositionStatus.closed).toList();
    final openRecords =
        _records.where((r) => r.status == PositionStatus.open).toList();

    final totalNetPL = closedRecords.fold(0.0, (s, r) => s + r.netPL);
    final winRate = closedRecords.isEmpty
        ? 0.0
        : (closedRecords.where((r) => r.netPL > 0).length / closedRecords.length) * 100;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Trading Reports',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.8,
                        ),
                      ),
                      Text(
                        'Import from Groww or export your trade data',
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
                      color: const Color(0xFFEC4899).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.swap_vert_rounded,
                        color: Color(0xFFEC4899), size: 22),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Metrics overview card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withOpacity(0.05)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'LOGGED ACTIVITY SUMMARY',
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _summaryItem('Total Records', '${_records.length}'),
                        _summaryItem('Open Holdings', '${openRecords.length}'),
                        _summaryItem('Win Rate', '${winRate.toStringAsFixed(1)}%'),
                        _summaryItem(
                          'Total Net P&L',
                          (totalNetPL >= 0 ? '+' : '') +
                              _currencyFormat.format(totalNetPL),
                          color: totalNetPL >= 0
                              ? const Color(0xFF10B981)
                              : const Color(0xFFF43F5E),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Scrollable IMPORT / EXPORT blocks
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    children: [
                      // ══════════════ IMPORT BLOCK ══════════════
                      _buildSectionCard(
                        icon: Icons.file_upload_rounded,
                        title: 'Import from Groww',
                        subtitle: 'Parse and import trade data from Groww\'s downloadable P&L reports into your Record Book.',
                        gradientColors: [
                          const Color(0xFF6366F1).withOpacity(0.14),
                          const Color(0xFF8B5CF6).withOpacity(0.14),
                        ],
                        borderColor: const Color(0xFF6366F1).withOpacity(0.3),
                        iconColor: const Color(0xFF818CF8),
                        children: [
                          _buildActionButton(
                            label: 'Import Stocks P&L (.xlsx)',
                            icon: Icons.candlestick_chart_rounded,
                            isLoading: _isImportingStocks,
                            color: const Color(0xFF6366F1),
                            onPressed: _isImportingStocks
                                ? null
                                : () => _importGrowwSheet(isFnO: false),
                          ),
                          const SizedBox(height: 12),
                          _buildActionButton(
                            label: 'Import F&O P&L (.xlsx)',
                            icon: Icons.trending_up_rounded,
                            isLoading: _isImportingFnO,
                            color: const Color(0xFF8B5CF6),
                            onPressed: _isImportingFnO
                                ? null
                                : () => _importGrowwSheet(isFnO: true),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // ══════════════ EXPORT BLOCK ══════════════
                      _buildSectionCard(
                        icon: Icons.file_download_rounded,
                        title: 'Export to Groww Format',
                        subtitle: 'Generate Groww-compatible Excel reports from your local trade records with auto-calculated charges.',
                        gradientColors: [
                          const Color(0xFFEC4899).withOpacity(0.14),
                          const Color(0xFFF97316).withOpacity(0.10),
                        ],
                        borderColor: const Color(0xFFEC4899).withOpacity(0.3),
                        iconColor: const Color(0xFFEC4899),
                        children: [
                          _buildActionButton(
                            label: 'Export Stocks P&L (.xlsx)',
                            icon: Icons.candlestick_chart_rounded,
                            isLoading: _isExportingStocks,
                            color: const Color(0xFFEC4899),
                            onPressed: _isExportingStocks
                                ? null
                                : () => _exportGrowwSheet(isFnO: false),
                          ),
                          const SizedBox(height: 12),
                          _buildActionButton(
                            label: 'Export F&O P&L (.xlsx)',
                            icon: Icons.trending_up_rounded,
                            isLoading: _isExportingFnO,
                            color: const Color(0xFFF97316),
                            onPressed: _isExportingFnO
                                ? null
                                : () => _exportGrowwSheet(isFnO: true),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
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

  // ════════════════════════════════════════════════════════════════
  //  REUSABLE WIDGETS
  // ════════════════════════════════════════════════════════════════

  Widget _buildSectionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Color> gradientColors,
    required Color borderColor,
    required Color iconColor,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 28),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withOpacity(0.55),
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 22),
          ...children,
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required bool isLoading,
    required Color color,
    VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: isLoading
            ? Container(
                key: ValueKey('${label}_loading'),
                height: 50,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: color,
                        strokeWidth: 2.5,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Processing...',
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              )
            : ElevatedButton.icon(
                key: ValueKey('${label}_button'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: color,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 6,
                  shadowColor: color.withOpacity(0.35),
                ),
                onPressed: onPressed,
                icon: Icon(icon, color: Colors.white, size: 18),
                label: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
      ),
    );
  }

  Widget _summaryItem(String label, String value, {Color? color}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white38, fontSize: 10),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: color ?? Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}
