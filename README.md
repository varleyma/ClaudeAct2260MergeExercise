# ClaudeAct2260MergeExercise

## Project Overview
This project performs a fuzzy merge of Puerto Rico Act 22 (Individual Investor) Annual Filing Reports across multiple years (2015-2023). The goal is to link individual investor records across different reporting periods using fuzzy matching techniques to create a unified panel dataset.

## Directory Structure

### Data Source (READ-ONLY - Dropbox)
**Location:** `C:\Users\mva284\Dropbox\ClaudeAct2260MergeExercise\`

```
Dropbox\ClaudeAct2260MergeExercise\
└── data\
    └── raw\
        ├── Act22AnnualReports2015-2018.csv   (has unique ID per person)
        ├── Act22AnnualReports2019.csv        (NO unique ID)
        ├── Act22AnnualReports2020.csv        (NO unique ID)
        ├── Act22AnnualReports2021.csv        (NO unique ID)
        ├── Act22AnnualReports2022_format19.csv (NO unique ID, old form)
        ├── Act22AnnualReports2022_format22.csv (NO unique ID, new form)
        └── Act22AnnualReports2023.csv        (NO unique ID)
```

### Code Repository (GitHub)
**Location:** `C:\Users\mva284\Documents\GitHub\ClaudeAct2260MergeExercise\`

```
GitHub\ClaudeAct2260MergeExercise\
├── README.md                   (this file - project documentation)
├── CLAUDE.md                   (AI assistant rules and instructions)
├── .git\                       (git version control)
│
├── 2015to2019example\          (Example merge using only 2015-2019 data)
│   ├── code\stata\             (Stata scripts for 2-file merge)
│   ├── data\raw\               (2015-2018 and 2019 CSV files)
│   ├── data\clean\             (Cleaned datasets and match results)
│   ├── output\                 (Reports and statistics)
│   └── log\                    (Progress logs)
│
├── code\                       (MAIN: Full 7-file merge scripts)
│   └── stata\
│       └── fuzzy_merge_act22_full.do  (Full panel merge script)
│
├── data\
│   ├── raw\                    (All 7 CSV files from Dropbox)
│   └── clean\                  (Output: cleaned data and panel)
│
├── output\                     (Reports and statistics)
└── log\                        (Progress logs)
```

## Data Description

### Files with Unique IDs

**Act22AnnualReports2015-2018.csv**
- Contains unique `id` column (format: "XX-22-S-XXX")
- Multiple years per person (2013-2017 reporting years)
- This is the "base" file for linking

### Files without Unique IDs (require fuzzy matching)

| File | Records | Notes |
|------|---------|-------|
| Act22AnnualReports2019.csv | ~877 | First file without IDs |
| Act22AnnualReports2020.csv | varies | |
| Act22AnnualReports2021.csv | varies | |
| Act22AnnualReports2022_format19.csv | varies | Old form format |
| Act22AnnualReports2022_format22.csv | varies | New form format |
| Act22AnnualReports2023.csv | varies | |

### Key Matching Variables
- `county` / `municipio_name`: Puerto Rico municipality
- `previous_reporting_year` / `current_reporting_year`: Year identifiers
- Asset variables (previous and current year):
  - `asset_type_financial_*`
  - `asset_type_real_estate_*`
  - `asset_type_privately_held_business_*`
  - `asset_type_other_*`

## Fuzzy Merge Strategy

1. **Clean municipality names** - Standardize across all files
2. **Sequential matching** - Match forward through time:
   - 2015-2018 (base with IDs) → 2019 → 2020 → 2021 → 2022 → 2023
3. **Exact matching first** - Match on municipality + year + all 4 assets
4. **Fuzzy matching second** - Allow 1-2 digit tolerance in asset values
5. **Confidence scoring** - 100 (exact), 95 (1-digit off), 90 (2-digits off)

## Output

The main output is `data/clean/act22_panel_full.dta` with 8 variables:
- `panel_id` - Unique person identifier (original ID or filename)
- `report_year` - Reporting year (time variable)
- `id` - Original ID from 2015-2018 (blank for unmatched)
- `filename` - Source CSV filename
- `fin` - Financial wealth
- `re` - Real estate wealth
- `bus` - Business wealth
- `oth` - Other wealth

## Getting Started

1. Read `CLAUDE.md` for project rules and conventions
2. For the simpler 2-file example, see `2015to2019example/`
3. For the full 7-file merge, run `code/stata/fuzzy_merge_act22_full.do`
4. Data is READ-ONLY from Dropbox; outputs go to GitHub

---
*Last Updated: January 30, 2025*
