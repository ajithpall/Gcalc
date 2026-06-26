import pandas as pd
import sys
sys.stdout.reconfigure(encoding='utf-8')
df = pd.read_excel('example_sheet/Grow_Intraday_Corrected.xlsx')
print(df.to_csv(index=False))
