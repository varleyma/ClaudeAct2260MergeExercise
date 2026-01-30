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
├── README.md           (this file - project documentation)
├── CLAUDE.md           (AI assistant rules and instructions)
├── .git\               (git version control)
└── code\
    ├── python\         (Python scripts - empty, 0 files)
    ├── R\              (R scripts - empty, 0 files)
    └── stata\          (Stata do-files - 2 files)
        ├── dta_act60_report_fuzzy_merge.do  (data cleaning/prep script)
        └── mrg_act60_report_fuzzy_merge.do  (merge execution script)
```

**File Descriptions:**

| File | Description |
|------|-------------|
| `README.md` | Project overview, directory structure, data descriptions |
| `CLAUDE.md` | Critical rules for AI assistant (no deletion, folder boundaries, git restrictions) |
| `dta_act60_report_fuzzy_merge.do` | Stata script (~25KB) - Cleans and prepares 2015-2018 data, standardizes location names, handles redacted values |
| `mrg_act60_report_fuzzy_merge.do` | Stata script (~2.5KB) - Performs fuzzy merge matching 2017 assets to 2018 filings using municipality + wealth variables |

**Total Files:** 4 (2 markdown, 2 Stata do-files)

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
