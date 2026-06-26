import openpyxl

wb = openpyxl.load_workbook('C:/Users/ajith/Downloads/Stocks_PnL_Report_0353264990_01-04-2026_25-06-2026.xlsx')
ws = wb.active

rows = list(ws.iter_rows(values_only=False))
print(f'Total rows: {len(rows)}')

# Print remaining data rows
for i in range(35, min(len(rows), 90)):
    row = rows[i]
    vals = []
    for c in row:
        v = str(c.value)[:40] if c.value is not None else ''
        vals.append(v)
    print(f'Row {i}: {vals}')
