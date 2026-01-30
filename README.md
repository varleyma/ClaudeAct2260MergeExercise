# ClaudeAct2260MergeExercise

## Project Overview
This project performs a fuzzy merge of Puerto Rico Act 22 (Individual Investor) Annual Filing Reports across multiple years. The goal is to link individual investor records across different reporting periods using fuzzy matching techniques.

## Directory Structure

### Data Source (READ-ONLY - Dropbox)
**Location:** `C:\Users\mva284\Dropbox\ClaudeAct2260MergeExercise\`

```
Dropbox\ClaudeAct2260MergeExercise\
└── data\
    └── raw\
        ├── Act22AnnualReports2015-2018.csv  (1,532 records + header)
        └── Act22AnnualReports2019.csv       (877 records + header)
```

**Total Records:** 2,409 investor annual filings

### Code Repository (GitHub)
**Location:** `C:\Users\mva284\Documents\GitHub\ClaudeAct2260MergeExercise\`

```
GitHub\ClaudeAct2260MergeExercise\
├── README.md           (this file)
├── CLAUDE.md           (AI assistant instructions)
├── .git\               (git version control)
└── code\
    ├── python\         (Python scripts - empty)
    ├── R\              (R scripts - empty)
    └── stata\
        ├── dta_act60_report_fuzzy_merge.do
        └── mrg_act60_report_fuzzy_merge.do
```

## Data Description

### Act22AnnualReports2015-2018.csv
- **Records:** 1,532 annual filings
- **Years Covered:** Tax years 2013-2017 (filings from 2015-2018)
- **Key Identifier:** `id` column (format: "XX-22-S-XXX", e.g., "12-22-S-003")
- **Key Columns:** 60 columns including:
  - `id`, `taxable_year_end`, `decree_year`
  - `county`, `state`, `physical_address`
  - Income fields (interest, dividends, capital gains, wages)
  - Asset fields (financial, real estate, business)
  - Business information, days in PR, expenditures

### Act22AnnualReports2019.csv
- **Records:** 877 annual filings
- **Years Covered:** Tax year 2018 (and some catch-up filings from prior years)
- **Key Identifier:** `filename` column (format: "2019-RepAct22-XXXXXX_Redacted.pdf")
- **Key Columns:** 67 columns including:
  - `filename`, `fecha_de_radicacion` (filing date)
  - `county`, `state`, `country`
  - Similar income and asset fields to 2015-2018 data
  - Additional business type columns (up to 9 businesses)

## Fuzzy Merge Challenge

The primary challenge is that:
1. **No direct ID linkage** between the two datasets
2. **Names are redacted** for privacy
3. **Column schemas differ** between datasets
4. Must rely on **indirect matching** using:
   - Location (county, municipality)
   - Financial profiles (net worth ranges, property values)
   - Business types and decree information
   - Asset patterns over time

## Getting Started

1. Read `CLAUDE.md` for project rules and conventions
2. All new code goes in `code/python/`, `code/R/`, or `code/stata/`
3. Data is READ-ONLY from Dropbox
4. Commit changes to GitHub regularly

---
*Last Updated: January 30, 2025*
