"""Inspect structure of the Experian credit-bureau header file (READ-ONLY from Dropbox).

Prints variable names, dtypes, labels, and a small sample of rows without
loading the full 2GB file into memory.
"""
import pandas as pd

SRC = r"C:\Users\mva284\Dropbox\ClaudeAct2260MergeExercise\data\raw\header2005_2023_ctk.dta"

with pd.io.stata.StataReader(SRC) as rdr:
    print("=== Variable labels ===")
    for k, v in rdr.variable_labels().items():
        print(f"  {k}: {v}")
    vl = rdr.value_labels()
    if vl:
        print("=== Value labels ===")
        for k, v in vl.items():
            print(f"  {k}: {dict(list(v.items())[:10])}")

with pd.read_stata(SRC, iterator=True) as rdr:
    sample = rdr.read(20)
print("\n=== Dtypes ===")
print(sample.dtypes)
print("\n=== First 20 rows ===")
pd.set_option("display.width", 250)
pd.set_option("display.max_columns", 50)
print(sample)
