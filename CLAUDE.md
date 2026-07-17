# CLAUDE.md - AI Assistant Instructions

**READ THIS FILE FIRST EVERY TIME YOU ENTER THIS PROJECT.**

**THEN read the latest log file in `log/` to pick up where we left off.**

This file contains critical rules and instructions for Claude (AI assistant) when working on this project. These rules are non-negotiable and must be followed at all times.

---

## CRITICAL RULES

### Rule 1: NEVER DELETE DATA, CODE, OR FILES
Under **no circumstances** are you ever to DELETE data, code, or any files in this project directory structure. This includes:
- CSV data files
- Code scripts (Python, R, Stata, etc.)
- Documentation files
- Any other project files

If something needs to be deprecated, rename it with a prefix like `_deprecated_` or `_old_` instead of deleting.

### Rule 2: FOLDER BOUNDARIES - NEVER LEAVE THESE TWO FOLDERS

You are **ONLY** permitted to work within these two folder paths:

1. **READ-ONLY Data Folder (Dropbox):**
   ```
   C:\Users\mva284\Dropbox\ClaudeAct2260MergeExercise\
   ```
   - This folder is for **READING CSV files ONLY**
   - **DO NOT** create, modify, or save any files here
   - **DO NOT** write output files here

2. **Code & Output Folder (GitHub):**
   ```
   C:\Users\mva284\Documents\GitHub\ClaudeAct2260MergeExercise\
   ```
   - This is where **ALL new code and files** must be saved
   - Save Python scripts to: `code/python/`
   - Save R scripts to: `code/R/`
   - Save Stata scripts to: `code/stata/`
   - Output data files go here (create `data/` or `output/` subfolder as needed)

**Under NO circumstances are you to EVER LEAVE these two folders.**

### Rule 3: Data Flow Direction
```
[Dropbox - READ ONLY] ──READ──> [Your Process] ──WRITE──> [GitHub Repository]
```

### Rule 4: GIT PUSH RESTRICTIONS
Claude may **ONLY** perform the following git operations:
- `git status` - Check repository status
- `git add` - Stage files for commit
- `git commit` - Commit staged changes locally

**Claude is NEVER permitted to run `git push`.**

Only the user decides when to push commits to GitHub. When commits are ready, Claude should inform the user and let them run `git push origin main` themselves.

### Rule 5: MAINTAIN PROGRESS LOGS
Claude must regularly update progress logs in the `log/` directory to ensure session continuity:
- Create new log entries with format `YYYY-MM-DD_HHMM.md`
- Log what was accomplished, files changed, current status, and next steps
- When starting a new session, read the latest log to resume work seamlessly

---

## Git & GitHub Guidance

Since the user is new to GitHub, provide clear step-by-step guidance for:

1. **Checking status:** `git status`
2. **Staging changes:** `git add <filename>` or `git add .`
3. **Committing:** `git commit -m "descriptive message"`
4. **Pushing:** `git push origin main` *(User runs this manually)*

Always explain what each git command does before running it.

---

## Project Context

- **Purpose:** Fuzzy merge of Puerto Rico Act 22 Individual Investor Annual Reports
- **Data Sources:** Seven CSV files covering 2015-2023 filings
  - `Act22AnnualReports2015-2018.csv` (has unique IDs)
  - `Act22AnnualReports2019.csv` through `Act22AnnualReports2023.csv` (no IDs)
- **Challenge:** No direct ID linkage in 2019+ files; must use location and financial data for matching
- **Example:** The `2015to2019example/` folder contains a simpler 2-file merge example

---

## Amendment Log

*New rules will be added below as they arise:*

| Date | Rule Added |
|------|------------|
| 2025-01-30 | Initial rules: No deletion, folder boundaries, read/write separation |
| 2025-01-30 | Rule 4: Claude may stage and commit, but NEVER push to GitHub |
| 2025-01-30 | Rule 5: Maintain progress logs in `log/` for session continuity |
| 2025-01-30 | Project expanded from 2 files to 7 files (2015-2023); original work moved to 2015to2019example/ |

---

## Common Errors & Fixes (Lessons Learned)

This section documents errors encountered during development and their solutions, to avoid repeating similar mistakes.

### Stata Variable Name Truncation

**Problem:** Stata truncates long variable names when importing CSVs. The variable for "current year business wealth" gets truncated differently across files:
- `v40` in 2015-2018 file
- `v41` in 2019, 2020, 2021, and 2022_format19 files
- `v42` in 2022_format22 and 2023 files

**Solution:** Use multiple `capture rename` statements to handle all possible truncated names:
```stata
capture rename v41 bus_cur
capture rename asset_type_privately_held_busin bus_cur
capture rename asset_type_privately_held_business_cur bus_cur
```

### Stata Local Macro Syntax

**Problem:** This syntax does NOT work in Stata:
```stata
local n_unique_keys = r(N) if match_key_tag == 1  // WRONG!
```

**Solution:** Run `count` with the condition first, then capture:
```stata
count if match_key_tag == 1
local n_unique_keys = r(N)
```

### Stata `collapse` with String Variables

**Problem:** `collapse (count)` cannot operate on string variables.

**Solution:** Create a numeric indicator first:
```stata
gen one = 1
collapse (sum) n = one, by(groupvar)
```

### Stata `joinby` Key Matching

**Problem:** `joinby` requires both datasets to have identically-named variables for the join keys. You cannot join `fin_base` from master to `fin_new` from using.

**Solution:** Either:
1. Rename variables to match before joining, OR
2. Join on fewer keys (e.g., municipality + year) and then filter for exact matches afterward:
```stata
joinby municipio_name match_year_key using `to_match', unmatched(using) _merge(_m)
gen exact_match = (fin_base == fin_new) & (re_base == re_new) & ...
```

### Stata `tempfile` Scope in Nested Blocks

**Problem:** `tempfile` macros created inside `if` blocks or nested `preserve/restore` may not be accessible outside those blocks.

**Solution:** Save to a permanent file path instead of using `tempfile`:
```stata
save "$CleanDataPath/temp_exact_used_base.dta", replace
* ... later ...
merge m:1 base_filename using "$CleanDataPath/temp_exact_used_base.dta", keep(master) nogen
```
Remember to clean up temp files at the end of the script.

### Stata `merge 1:1` Uniqueness Requirement

**Problem:** `merge 1:1` fails with "variable X does not uniquely identify observations" when the merge key has duplicates.

**Solution:**
1. Deduplicate before merging:
```stata
gsort filename -match_confidence
bysort filename: keep if _n == 1
```
2. Or use `merge m:1` if duplicates are expected on one side.

### Zero-to-Zero Matching Bug

**Problem:** When fuzzy matching on asset values, zeros matching zeros provides no evidence of a true match. Two unrelated people could both have [0, 0, 0, 0] assets.

**Solution:**
1. Track which assets are truly zero vs missing with `_missing` flags
2. Set digit distance to a sentinel value (e.g., 88) for both-zero comparisons
3. Require at least one non-zero asset match:
```stata
gen n_nonzero = (fin_new > 0 & fin_new_missing == 0) + ...
replace exact_match = 0 if n_nonzero == 0
```

### Iterative Chaining - Adding Only Matched Records

**Problem:** Initially, only matched records were added to the matching base. This prevented "short chains" (e.g., a person who first appears in 2019 can't be linked to their 2020 record).

**Solution:** Add ALL records from each year to the base, not just matched ones. Unmatched records use their filename as a temporary ID for future chaining.

### Panel Uniqueness - Reusing Base Records

**Problem:** A base record (person-year) could be matched to multiple new records if not properly tracked.

**Solution:**
1. After matching, save list of used `base_filename` values
2. Exclude used base records from subsequent fuzzy matching
3. Deduplicate by `base_filename` (not just `id + match_year_key`)

### Source File vs Reporting Year Confusion

**Problem:** Each source file (e.g., "2020 file") contains filings from MULTIPLE reporting years, not just one. For example, the 2022 file might contain filings for reporting years 2019, 2020, 2021, and 2022. Matching by source file order misses chains because:
- A person's 2019 reporting year record might be in the 2020 file
- Their 2020 reporting year record might be in the 2022 file
- If we match "2020 file" then "2021 file" then "2022 file", we miss the 2019→2020 chain

**Solution:**
1. Combine all 2019+ source files into one dataset first
2. Match by REPORTING YEAR sequence (2016, 2017, 2018, 2019, ...), not by source file
3. After matching each reporting year, add ALL those records to the base
4. This ensures proper chaining regardless of which source file a record came from

```stata
* Combine all 2019+ files
use "$CleanDataPath/clean_2019.dta", clear
append using "$CleanDataPath/clean_2020.dta"
* ... etc

* Match by reporting year, not source file
levelsof report_year, local(report_years)
foreach yr of local report_years {
    match_reporting_year `yr'
}
```

### Duplicate Filenames Across Source Files

**Problem:** When combining multiple source files (e.g., 2019, 2020, 2021, 2022, 2023), the same record might appear in multiple files, causing duplicate filenames. This breaks `merge 1:1` operations.

**Solution:**
1. After appending source files, check for and remove duplicate filenames:
```stata
duplicates tag filename, gen(_dup_fn)
count if _dup_fn > 0
if r(N) > 0 {
    di "WARNING: Found " r(N) " duplicate filenames"
    bysort filename: keep if _n == 1
}
drop _dup_fn
```
2. Before any `merge 1:1` on filename, verify uniqueness or use deduplication.

### Municipality Name Standardization - Use UPPERCASE

**Problem:** Municipality names come from various variables (`county`, `sworn_statement_city_and_country`, `real_estate_municipality`, etc.) with inconsistent capitalization, encoding issues from PDF extraction, and typos. Trying to handle all case variations leads to missed matches and duplicates.

**Solution:**
1. Convert to UPPERCASE first using `replace municipio_name = upper(municipio_name)`
2. Then apply standardization rules (removing suffixes like "PUERTO RICO", "USA", etc.)
3. Then apply typo corrections and mappings
4. Validate against list of 78 valid PR municipalities (in UPPERCASE)

**Key patterns to handle:**
- Suffixes: "PUERTO RICO", "P.R.", "PR", "USA", "U.S.A.", etc.
- Encoding issues: garbled accented characters (Ă, ñ → N, etc.)
- Neighborhoods/barrios: SANTURCE → SAN JUAN, PALMAS DEL MAR → HUMACAO
- Typos: DORADOPUERTO RIC → DORADO, UMACAO → HUMACAO
- US mainland locations: Try alternative variables first (real_estate_municipality, mailing_county), then drop if truly unrecoverable

**Do NOT** simply drop records when county shows a US location - the PR municipality may be in another variable.

### Stata Merge Does NOT Overwrite Existing Variables

**Problem:** When using `merge` to bring in values from a using file, if the master data already has the variable (even with empty/missing values), Stata will NOT overwrite those values for matched observations. It only fills in values when the variable doesn't exist in master.

**Example of the bug:**
```stata
* Master has id="" for all records
use master_data, clear
merge 1:1 filename using matched_ids, keep(master match) nogen
* BUG: id is still "" for all records! The merge didn't update it.
```

**Solution:** Drop the variable from master before merging if you want to bring in values from the using file:
```stata
use master_data, clear
drop id  // Remove the empty variable first
merge 1:1 filename using matched_ids, keep(master match) nogen
* Now id is properly filled in for matched records
* For unmatched, id won't exist - handle with:
capture confirm variable id
if _rc != 0 gen id = ""
replace id = filename if id == ""  // Assign default for unmatched
```

This was a critical bug in the iterative chaining logic - matched records weren't inheriting IDs from the base because the merge wasn't updating the empty `id` variable.

---

*This file will be amended regularly with new rules as they come along.*
