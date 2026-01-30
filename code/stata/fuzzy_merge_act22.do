********************************************************************************
* FUZZY MERGE OF ACT 22 INDIVIDUAL INVESTOR ANNUAL REPORTS
********************************************************************************
*
* Purpose: 	Link individual investor records across 2015-2018 and 2019 datasets
*			using fuzzy matching on municipality and asset values
*
* Authors: 	Michael Varley, Lucy Msall, with Claude AI assistance
* Created: 	January 30, 2025
*
* Data Sources:
*	- Act22AnnualReports2015-2018.csv (1,532 records, has unique ID per person)
*	- Act22AnnualReports2019.csv (877 records, NO unique ID)
*
* Matching Strategy:
*	1. Clean municipality names to standardized format
*	2. Extract previous year asset values from both datasets
*	3. Match on: municipality + financial_wealth + real_estate_wealth +
*	   business_wealth + other_wealth (from previous reporting year)
*	4. Apply fuzzy matching with tolerance for 1-digit typos in asset values
*	5. Generate confidence scores based on match quality
*
* Key Variables for Matching:
*	- municipio_name: Puerto Rico municipality of residence
*	- previous_reporting_year / current_reporting_year: Year identifiers
*	- asset_type_financial_previous_reporting_year: Financial assets (prev yr)
*	- asset_type_real_estate_previous_reporting_year: Real estate (prev yr)
*	- asset_type_privately_held_business_previous_reporting_year: Business (prev yr)
*	- asset_type_other_previous_reporting_year: Other assets (prev yr)
*
********************************************************************************

set more off
clear all

********************************************************************************
* SECTION 0: SET UP FILE PATHS
********************************************************************************
* NOTE: Modify MyPath to match your local setup

global MyPath "C:/Users/mva284"

* Data is READ from the GitHub repository data folder
* All output is WRITTEN to the GitHub repository
global GitHubPath "$MyPath/Documents/GitHub/ClaudeAct2260MergeExercise"
global RawDataPath "$GitHubPath/data/raw"
global CleanDataPath "$GitHubPath/data/clean"
global OutputPath "$GitHubPath/output"

* Create output directories if they don't exist
capture mkdir "$CleanDataPath"
capture mkdir "$OutputPath"

********************************************************************************
* SECTION 1: IMPORT AND CLEAN 2015-2018 DATA
********************************************************************************
* This section imports the 2015-2018 data which has unique IDs for each
* individual investor. We clean municipality names and standardize asset
* variable names for merging.
********************************************************************************

import delimited "$RawDataPath/Act22AnnualReports2015-2018.csv", ///
	varnames(1) clear stringcols(_all)

* Document initial record count
local n_initial_1518 = _N
di "Initial 2015-2018 records: `n_initial_1518'"

*------------------------------------------------------------------------------
* STEP 1.1: Clean municipality names from sworn statement location
*------------------------------------------------------------------------------
* The sworn_statement_city_and_country field contains the location where the
* report was signed. We extract the Puerto Rico municipality from this field.

gen temp = sworn_statement_city_and_country

* Remove common suffixes/variations of Puerto Rico
local pr_suffixes `" ", Puerto Rico" ", P.R." ", P. R." "- P.R" " P.R." ", P.R" " P.R" ", PR" " PR" " PR USA" " Puerto Rico USA" " Puerto Rico" ", PUERTO RICO" " PUERTO RICO" ", USA" " USA" ", U.S.A." ", U.S.A" ", United States" " -" "'

foreach suffix of local pr_suffixes {
	replace temp = subinstr(temp, "`suffix'", "", .)
}

gen municipio_name = temp
drop temp

*------------------------------------------------------------------------------
* STEP 1.2: Standardize municipality name spellings
*------------------------------------------------------------------------------
* There are many variations in how municipality names are spelled. We
* standardize to a consistent format.

* Añasco variations
replace municipio_name = "Anasco" if inlist(municipio_name, "ANASCO", "Anasco", "Añasco")

* Arecibo variations
replace municipio_name = "Arecibo" if municipio_name == "ARECIBO"

* Carolina variations
replace municipio_name = "Carolina" if inlist(municipio_name, "CAROLINA", "Carolina, P R   U S A")

* Dorado variations (common destination for Act 22 investors)
replace municipio_name = "Dorado" if inlist(municipio_name, "DORADO", "Doado", "Dorado 00646", "Dorado Beach")
replace municipio_name = "Dorado" if inlist(municipio_name, "Dorado Olio", "Dorado, Dorado", "Aotealo", "Durham")
replace municipio_name = "Dorado" if inlist(municipio_name, "Caribe", "Captial L.A. U.S.A.")

* Guaynabo variations
replace municipio_name = "Guaynabo" if inlist(municipio_name, "GUAYNABO", "Guaynabo .", "Guaynabo P R")
replace municipio_name = "Guaynabo" if municipio_name == "Guaynabo, P. Rico (USA"

* Humacao variations (major resort area - Palmas del Mar)
replace municipio_name = "Humacao" if inlist(municipio_name, "HUMACAO", "Humacao 00719", "Humacao AZ", "Humacao US")
replace municipio_name = "Humacao" if inlist(municipio_name, "Humacao, US", "Humaco", "Humaco oro", "Almacao")
replace municipio_name = "Humacao" if municipio_name == "Palmas del Mar"
replace municipio_name = "Humacao" if inlist(municipio_name, "Birmingham AL", "Cary McHenry, IL", "Chicago")

* Loiza variation
replace municipio_name = "Loiza" if municipio_name == "Loza"

* Moca variation
replace municipio_name = "Moca" if municipio_name == "MOCA"

* Rincon variations
replace municipio_name = "Rincon" if inlist(municipio_name, "RincĂłn", "Rincón")

* Rio Grande variations
replace municipio_name = "Rio Grande" if inlist(municipio_name, "RIO GRANDE", "Bahia Beach", "Garden City, NY")

* San Juan variations (capital, most common location)
replace municipio_name = "San Juan" if inlist(municipio_name, "SAN JUAN", "San Jaun", "San Juan (USA")
replace municipio_name = "San Juan" if inlist(municipio_name, "San Juan US", "San Juan, San Juan", "Santurce San Turce")
replace municipio_name = "San Juan" if inlist(municipio_name, "Condado", "NEW YORK, NY", "Austin Turks & Caicos")
replace municipio_name = "San Juan" if municipio_name == "Cao CuraĂ§ao"
replace municipio_name = "San Juan" if municipio_name == "Brighton Township, MI"

* Fajardo - some CO addresses map here
replace municipio_name = "Fajardo" if municipio_name == "Durango, CO"

*------------------------------------------------------------------------------
* STEP 1.3: Manual corrections based on ID lookup
*------------------------------------------------------------------------------
* Some records need manual correction based on examining the original PDFs
* or cross-referencing with other data. These are indexed by the unique ID.

* Known municipality corrections by ID
replace municipio_name = "Humacao" if id == "12-22-S-009"
replace municipio_name = county if municipio_name == "Austin, TX"
replace municipio_name = "Humacao" if inlist(id, "14-22-S-023", "14-22-S-022")
replace municipio_name = "Dorado" if inlist(id, "16-22-S-036", "13-22-S-062", "14-22-S-025")
replace municipio_name = "San Juan" if inlist(id, "16-22-S-153", "14-22-S-324", "13-22-S-128")
replace municipio_name = "Humacao" if id == "15-22-S-265"
replace municipio_name = "Guaynabo" if id == "14-22-S-151"
replace municipio_name = "San Juan" if inlist(id, "14-22-S-219", "15-22-S-193", "14-22-S-039")
replace municipio_name = "Carolina" if id == "14-22-S-099"
replace municipio_name = "Dorado" if inlist(id, "14-22-S-130", "14-22-S-032", "14-22-S-055")
replace municipio_name = "Dorado" if id == "15-22-S-005"
replace municipio_name = "Humacao" if id == "15-22-S-011"
replace municipio_name = "Dorado" if id == "15-22-S-050"
replace municipio_name = "Anasco" if inlist(id, "15-22-S-233", "15-22-S-234")
replace municipio_name = "Guaynabo" if id == "16-22-S-057"
replace municipio_name = "San Juan" if inlist(id, "14-22-S-286", "15-22-S-133")
replace municipio_name = "San Juan" if inlist(id, "14-22-S-321", "14-22-S-136", "14-22-S-137")
replace municipio_name = "San Juan" if inlist(id, "14-22-S-315", "14-22-S-316")
replace municipio_name = "Dorado" if id == "16-22-S-324"
replace municipio_name = "San Juan" if id == "14-22-S-067"
replace municipio_name = "Humacao" if id == "14-22-S-161"
replace municipio_name = "San Juan" if id == "13-22-S-108"
replace municipio_name = "Vega Alta" if id == "15-22-S-027"

* Corrections for REDACTED locations (looked up from other sources)
replace municipio_name = "San Juan" if inlist(id, "13-22-S-023", "14-22-S-110", "15-22-S-063")
replace municipio_name = "Ponce" if id == "13-22-S-109"
replace municipio_name = "Rio Grande" if id == "15-22-S-155"
replace municipio_name = "Humacao" if inlist(id, "15-22-S-184", "15-22-S-045", "14-22-S-300")
replace municipio_name = "San Juan" if inlist(id, "14-22-S-037", "14-22-S-150", "16-22-S-159")
replace municipio_name = "San Juan" if inlist(id, "16-22-S-182", "14-22-S-001", "14-22-S-075")
replace municipio_name = "San Juan" if inlist(id, "14-22-S-337", "15-22-S-025", "15-22-S-026")
replace municipio_name = "Carolina" if id == "15-22-S-256"
replace municipio_name = "Dorado" if inlist(id, "16-22-S-179", "16-22-S-323", "16-22-S-107")

* NA locations (from county field)
replace municipio_name = "Dorado" if inlist(id, "12-22-S-006", "13-22-S-119", "13-22-S-132")
replace municipio_name = "Dorado" if inlist(id, "13-22-S-136", "14-22-S-141", "15-22-S-270")
replace municipio_name = "San Juan" if inlist(id, "13-22-S-054", "14-22-S-081", "14-22-S-126")
replace municipio_name = "Guaynabo" if id == "14-22-S-271"

* Mark truly unknown locations as NA
replace municipio_name = "NA" if inlist(municipio_name, "Austin", "Buenos Aires, Argentina")
replace municipio_name = "NA" if inlist(municipio_name, "Chico, California", "Irving, Texas")
replace municipio_name = "NA" if inlist(id, "16-22-S-198", "13-22-S-019", "17-22-S-131", "15-22-S-356")

*------------------------------------------------------------------------------
* STEP 1.4: Drop records that cannot be matched
*------------------------------------------------------------------------------
* Records with REDACTED or NA municipality cannot be reliably matched

local n_before_drop = _N
drop if municipio_name == "REDACTED" | municipio_name == "NA"
local n_dropped = `n_before_drop' - _N
di "Dropped `n_dropped' records with REDACTED or NA municipality"

*------------------------------------------------------------------------------
* STEP 1.5: Handle duplicate filenames
*------------------------------------------------------------------------------
* Some PDFs were processed multiple times. Keep only unique records.

gen filename_short = substr(filename, 1, 25)
drop if filename_short == "15-22-S-219-2016_Redacted" & type_of_charity == "REDACTED"
drop if filename == "13-22-097_2016_Redacted.pdf"
drop if filename == "13-22-S-005-2013_Redacted.pdf"

gen filename_temp = substr(filename, 1, 13)
drop if filename_temp == "14-22-S-009-A"
drop filename_short filename_temp

*------------------------------------------------------------------------------
* STEP 1.6: Rename and standardize asset variables
*------------------------------------------------------------------------------

* Previous year assets (used for matching)
rename asset_type_financial_previous_re financial_wealth_pre
rename asset_type_real_estate_previous_ real_estate_wealth_pre
rename asset_type_privately_held_busine business_wealth_pre
rename asset_type_other_previous_report other_wealth_pre

* Current year assets
rename asset_type_financial_current_rep financial_wealth
rename asset_type_real_estate_current_r real_estate_wealth
capture rename v40 business_wealth
capture rename asset_type_privately_held_busin business_wealth
rename asset_type_other_current_reporti other_wealth

* Differences
rename asset_type_financial_difference financial_wealth_diff
rename asset_type_real_estate_differenc real_estate_wealth_diff
capture rename v41 business_wealth_diff
capture rename asset_type_privately_held_busi business_wealth_diff
rename asset_type_other_difference other_wealth_diff

* Year variables
destring current_reporting_year previous_reporting_year, replace force
rename current_reporting_year year
rename previous_reporting_year previous_year

*------------------------------------------------------------------------------
* STEP 1.7: Handle duplicate ID-year combinations
*------------------------------------------------------------------------------
* Some individuals have multiple filings for the same year (amended returns,
* late filings, etc.). We keep the most reliable one based on data quality.

sort id year
egen id_year_tag = tag(id year)
tab id_year_tag

* List of known duplicates with specific resolution rules
* (keeping the one with better data quality or correct timing)

drop if filename == "13-22-S-064_2015_Redacted.pdf"
drop if filename == "13-22-S-077_2017_Redacted.pdf" & year == 2013
drop if filename == "13-22-S-100_2016.pdf"

* Fix misreported years
replace previous_year = 2013 if filename == "13-22-S-115_2015_Redacted.pdf"
replace year = 2014 if filename == "13-22-S-115_2015_Redacted.pdf"

drop if filename == "13-22-S-117_2016_Redacted.pdf" & year == 2015
drop if filename == "13-22-S-118_2017_Redacted.pdf"
drop if filename == "13-22-S-121_2017_Redacted.pdf"
drop if filename == "13-22-S-135_2017_Redacted.pdf"
drop if filename == "13-22-S-146-2017_Redacted.pdf"
drop if filename == "14-22-S-016_2017_Redacted.pdf"

replace previous_year = 2013 if filename == "14-22-S-022_2015_Redacted.pdf"
replace year = 2014 if filename == "14-22-S-022_2015_Redacted.pdf"
replace previous_year = 2013 if filename == "14-22-S-023_2015_Redacted.pdf"
replace year = 2014 if filename == "14-22-S-023_2015_Redacted.pdf"

drop if filename == "14-22-S-058_2017_Redacted.pdf"
drop if filename == "14-22-S-105_2014_Redacted.pdf"
drop if filename == "14-22-S-125_2015_Redacted.pdf"
drop if filename == "14-22-S-170_2016_Redacted.pdf"
drop if filename == "14-22-S-191_2015.pdf" & financial_wealth_diff == "63659787"

replace previous_year = 2013 if filename == "14-22-S-203_2016_Redacted.pdf"
replace year = 2014 if filename == "14-22-S-203_2016_Redacted.pdf"
replace previous_year = 2013 if filename == "14-22-S-214_2016_Redacted.pdf"
replace year = 2014 if filename == "14-22-S-214_2016_Redacted.pdf"

drop if filename == "14-22-S-219-2016_Redacted.pdf"

replace previous_year = 2013 if filename == "14-22-S-220_2016_Redacted.pdf"
replace year = 2014 if filename == "14-22-S-220_2016_Redacted.pdf"

drop if filename == "14-22-S-243_2016_Redacted.pdf"
drop if filename == "14-22-S-243-2017_Redacted.pdf"
drop if filename == "14-22-S-276_2015_Redacted.pdf"

replace previous_year = 2015 if filename == "15-22-S-019_216_Redacted.pdf"
replace year = 2016 if filename == "15-22-S-019_216_Redacted.pdf"

drop if filename == "15-22-S-064_2015_Redacted.pdf"
drop if filename == "15-22-S-089_2016_Redacted.pdf"
drop if filename == "15-22-S-11_2016_Redacted.pdf" & id == "15-22-S-111"
drop if filename == "15-22-S-146_2016_Redacted.pdf" & financial_wealth == "170000"
drop if filename == "15-22-S-195-2015_Redacted.pdf" & business_wealth == "750000"
drop if filename == "15-22-S-291_2016_Redacted.pdf"
drop if filename == "16-22-S-207_2016_Redacted.pdf"

drop id_year_tag

* Verify uniqueness
egen id_year_tag = tag(id year)
tab id_year_tag
assert id_year_tag == 1
drop id_year_tag

*------------------------------------------------------------------------------
* STEP 1.8: Create panel-level municipality variable
*------------------------------------------------------------------------------
* Some individuals report different municipalities across years. We use the
* modal (most common) municipality as the primary matching variable, with
* the last reported as a fallback.

egen municipio_name_mode = mode(municipio_name), by(id)
egen municipio_name_last = lastnm(municipio_name), by(id)
replace municipio_name_mode = municipio_name_last if municipio_name_mode == ""

*------------------------------------------------------------------------------
* STEP 1.9: Keep matching variables and reshape to wide format
*------------------------------------------------------------------------------

keep id decree_year municipio_name_mode municipio_name_last year ///
	financial_wealth real_estate_wealth business_wealth other_wealth ///
	financial_wealth_pre real_estate_wealth_pre business_wealth_pre other_wealth_pre

order id decree_year municipio_name_mode municipio_name_last year

* Reshape to have one row per individual with columns for each year's assets
reshape wide financial_wealth real_estate_wealth business_wealth other_wealth ///
	financial_wealth_pre real_estate_wealth_pre business_wealth_pre other_wealth_pre, ///
	i(id decree_year municipio_name_mode municipio_name_last) j(year)

* Document final record count
local n_final_1518 = _N
di "Final 2015-2018 unique individuals: `n_final_1518'"

save "$CleanDataPath/clean_2015_2018.dta", replace

********************************************************************************
* SECTION 2: IMPORT AND CLEAN 2019 DATA
********************************************************************************
* The 2019 data does NOT have unique individual IDs. We will match these
* records to the 2015-2018 data using municipality and asset values.
********************************************************************************

import delimited "$RawDataPath/Act22AnnualReports2019.csv", ///
	varnames(1) clear stringcols(_all)

local n_initial_2019 = _N
di "Initial 2019 records: `n_initial_2019'"

*------------------------------------------------------------------------------
* STEP 2.1: Remove duplicate filings
*------------------------------------------------------------------------------

gen filename_short = substr(filename, 1, 20)
egen temp = tag(filename_short)
keep if temp == 1
drop temp filename_short

*------------------------------------------------------------------------------
* STEP 2.2: Clean municipality names
*------------------------------------------------------------------------------

gen municipio_name = county

* Drop non-PR locations
drop if inlist(municipio_name, "26", "HILLSBOROUGH", "Las Vegas", "Loganville")

* Standardize municipality names
replace municipio_name = "Adjuntas" if county == "Adjuntas,Adjuntas"
replace municipio_name = "Anasco" if inlist(county, "AĂąasco", "Aiasco", "Afiasco", "Añasco")
replace municipio_name = "Bayamon" if inlist(county, "BayamĂłn", "Bayamón")
replace municipio_name = "Dorado" if inlist(county, "DORADO", "CHICAGO", "Dorado,Dorado", "FALLBROOK")
replace municipio_name = "Guaynabo" if county == "Key Largo"
replace municipio_name = "Mayaguez" if county == "MayagĂźez"
replace municipio_name = "Rincon" if inlist(county, "RincĂłn", "Rincón")
replace municipio_name = "Rio Grande" if inlist(county, "Río Grande", "RĂ­o Grande")
replace municipio_name = "San Juan" if inlist(county, "SANJUAN", "SAN JUAN", "Sen Juan")
replace municipio_name = "San Juan" if inlist(county, "DALLAS", "Newbury Park", "Austin", "IRON STATION", "Miami")
replace municipio_name = "San German" if inlist(county, "San GermĂĄn", "San Germán")
replace municipio_name = "Carolina" if inlist(county, "Queens", "WESTON")
replace municipio_name = "Carolina" if filename == "2020-RepAct22-001283_Redacted.pdf"
replace municipio_name = "Humacao" if inlist(county, "Redondo Beach", "CARY", "Urbandale")

drop if municipio_name == "REDACTED"

*------------------------------------------------------------------------------
* STEP 2.3: Rename asset variables
*------------------------------------------------------------------------------

rename asset_type_financial_previous_re financial_wealth_pre
rename asset_type_real_estate_previous_ real_estate_wealth_pre
rename asset_type_privately_held_busine business_wealth_pre
rename asset_type_other_previous_report other_wealth_pre

rename asset_type_financial_current_rep financial_wealth
rename asset_type_real_estate_current_r real_estate_wealth
capture rename v41 business_wealth
capture rename asset_type_privately_held_busin business_wealth
rename asset_type_other_current_reporti other_wealth

rename asset_type_financial_difference financial_wealth_diff
rename asset_type_real_estate_differenc real_estate_wealth_diff
capture rename v42 business_wealth_diff
capture rename asset_type_privately_held_busi business_wealth_diff
rename asset_type_other_difference other_wealth_diff

destring current_reporting_year previous_reporting_year, replace force
rename current_reporting_year year
rename previous_reporting_year previous_year

*------------------------------------------------------------------------------
* STEP 2.4: Keep matching variables
*------------------------------------------------------------------------------

keep filename municipio_name year previous_year ///
	financial_wealth_pre real_estate_wealth_pre ///
	business_wealth_pre other_wealth_pre ///
	financial_wealth real_estate_wealth business_wealth other_wealth

rename filename filename2019

local n_final_2019 = _N
di "Final 2019 records for matching: `n_final_2019'"

save "$CleanDataPath/clean_2019.dta", replace

********************************************************************************
* SECTION 3: PREPARE MATCHING VARIABLES
********************************************************************************
* We will match 2019 records to 2015-2018 records using previous year assets.
* The key insight is:
*   2019 record with previous_year=2017 should match to
*   2015-2018 record's year=2017 current assets
********************************************************************************

*------------------------------------------------------------------------------
* STEP 3.1: Prepare 2015-2018 data for matching (2017 values)
*------------------------------------------------------------------------------

use "$CleanDataPath/clean_2015_2018.dta", clear

* Keep only records that have 2017 data (for matching to 2019)
keep if financial_wealth2017 != "" | real_estate_wealth2017 != "" | ///
	business_wealth2017 != "" | other_wealth2017 != ""

keep id municipio_name_mode ///
	financial_wealth2017 real_estate_wealth2017 ///
	business_wealth2017 other_wealth2017

* Drop if all 2017 assets are NA (likely secondary household members)
drop if financial_wealth2017 == "NA" & real_estate_wealth2017 == "NA" & ///
	business_wealth2017 == "NA" & other_wealth2017 == "NA"

* Convert to numeric and round for matching
foreach var in financial_wealth real_estate_wealth business_wealth other_wealth {
	destring `var'2017, replace force
	replace `var'2017 = round(`var'2017)
}

* Create matching key (municipality + all 4 asset values)
* First check for duplicates on exact match
egen match_key_tag = tag(municipio_name_mode ///
	financial_wealth2017 real_estate_wealth2017 ///
	business_wealth2017 other_wealth2017)

* Count unique vs duplicate matching keys
tab match_key_tag

* Count how many have unique keys vs duplicates
count if match_key_tag == 1
local n_unique_keys_1518 = r(N)
count if match_key_tag == 0
local n_dup_keys_1518 = r(N)
di "Unique matching keys: `n_unique_keys_1518'"
di "Duplicate matching keys: `n_dup_keys_1518'"

* For now, keep only unique matching keys (exact duplicates cause ambiguity)
* We'll handle these with fuzzy matching later
keep if match_key_tag == 1
drop match_key_tag

local n_matchable_1518 = _N
di "Records from 2015-2018 with unique 2017 matching keys: `n_matchable_1518'"

tempfile match_2015_2018
save `match_2015_2018'

*------------------------------------------------------------------------------
* STEP 3.2: Prepare 2019 data for matching
*------------------------------------------------------------------------------

use "$CleanDataPath/clean_2019.dta", clear

* Focus on 2018 filings that report 2017 as previous year
keep if year == 2018 & previous_year == 2017

* Rename previous year assets to match 2017 naming
rename financial_wealth_pre financial_wealth2017
rename real_estate_wealth_pre real_estate_wealth2017
rename business_wealth_pre business_wealth2017
rename other_wealth_pre other_wealth2017

* Drop if all previous year assets are 0 or missing (can't match)
drop if financial_wealth2017 == "0" & real_estate_wealth2017 == "0" & ///
	business_wealth2017 == "0" & other_wealth2017 == "0"
drop if financial_wealth2017 == "NA" & real_estate_wealth2017 == "NA" & ///
	business_wealth2017 == "NA" & other_wealth2017 == "NA"
drop if financial_wealth2017 == "" & real_estate_wealth2017 == "" & ///
	business_wealth2017 == "" & other_wealth2017 == ""

* Standardize municipality name variable
rename municipio_name municipio_name_mode

* Convert to numeric and round
foreach var in financial_wealth real_estate_wealth business_wealth other_wealth {
	destring `var'2017, replace force
	replace `var'2017 = round(`var'2017)
}

* Check for duplicates in 2019 data
egen match_key_tag = tag(municipio_name_mode ///
	financial_wealth2017 real_estate_wealth2017 ///
	business_wealth2017 other_wealth2017)
tab match_key_tag
keep if match_key_tag == 1
drop match_key_tag

local n_matchable_2019 = _N
di "Records from 2019 with unique 2017 matching keys: `n_matchable_2019'"

tempfile match_2019
save `match_2019'

********************************************************************************
* SECTION 4: EXACT MATCHING
********************************************************************************
* First attempt: exact match on municipality + all 4 asset values
********************************************************************************

use `match_2019', clear

merge 1:1 municipio_name_mode ///
	financial_wealth2017 real_estate_wealth2017 ///
	business_wealth2017 other_wealth2017 ///
	using `match_2015_2018'

* Document match results
tab _merge

* Count matches by merge status
count if _merge == 3
local n_exact_match = r(N)
count if _merge == 1
local n_2019_only = r(N)
count if _merge == 2
local n_1518_only = r(N)

di "===== EXACT MATCH RESULTS ====="
di "Matched (both datasets): `n_exact_match'"
di "2019 only (unmatched): `n_2019_only'"
di "2015-2018 only (unmatched): `n_1518_only'"

* Save exact matches
preserve
keep if _merge == 3
gen match_type = "exact"
gen match_confidence = 100
drop _merge
save "$CleanDataPath/exact_matches.dta", replace
restore

* Save unmatched 2019 records for fuzzy matching
preserve
keep if _merge == 1
drop _merge id
save "$CleanDataPath/unmatched_2019.dta", replace
restore

* Save unmatched 2015-2018 records for fuzzy matching
preserve
keep if _merge == 2
drop _merge filename2019 year previous_year ///
	financial_wealth real_estate_wealth business_wealth other_wealth
save "$CleanDataPath/unmatched_1518.dta", replace
restore

********************************************************************************
* SECTION 5: FUZZY MATCHING
********************************************************************************
* For records that didn't match exactly, we try fuzzy matching with tolerance
* for small differences in asset values (potential typos/rounding errors).
*
* DUPLICATE HANDLING STRATEGY:
* 1. Identify records with same matching key (municipality + bucketed assets)
* 2. For TRUE duplicates (same person filed twice): keep one, track the other
* 3. For FALSE duplicates (different people): use additional variables to
*    distinguish (current assets, days in PR, expenditure, etc.)
********************************************************************************

use "$CleanDataPath/unmatched_2019.dta", clear

local n_unmatched_2019 = _N
di "Attempting fuzzy match for `n_unmatched_2019' unmatched 2019 records"

*------------------------------------------------------------------------------
* STEP 5.1: Create bucketed asset variables for fuzzy matching
*------------------------------------------------------------------------------
* Buckets allow matching with tolerance for small typos/rounding differences

foreach var in financial_wealth2017 real_estate_wealth2017 ///
	business_wealth2017 other_wealth2017 {

	* Create buckets: round to nearest 1000 for values > 10000
	* round to nearest 100 for values <= 10000
	gen `var'_bucket = .
	replace `var'_bucket = round(`var' / 1000) * 1000 if `var' > 10000
	replace `var'_bucket = round(`var' / 100) * 100 if `var' <= 10000 & `var' > 0
	replace `var'_bucket = 0 if `var' == 0
	replace `var'_bucket = . if `var' == .
}

*------------------------------------------------------------------------------
* STEP 5.2: Identify and handle duplicates in 2019 data
*------------------------------------------------------------------------------
* Tag records that share the same matching key

egen fuzzy_key_group = group(municipio_name_mode ///
	financial_wealth2017_bucket real_estate_wealth2017_bucket ///
	business_wealth2017_bucket other_wealth2017_bucket), missing

bysort fuzzy_key_group: gen n_in_group = _N
bysort fuzzy_key_group: gen group_seq = _n

* Count how many have duplicates
count if n_in_group > 1
local n_with_dups = r(N)
di "2019 records sharing a matching key with others: `n_with_dups'"

* For records with duplicates, we need to decide which to keep
* Strategy:
*   - If current year assets are identical -> TRUE duplicate, keep first
*   - If current year assets differ -> different people, keep both but flag

* Create a "duplicate signature" using current year assets to identify true dups
egen dup_sig = group(fuzzy_key_group ///
	financial_wealth real_estate_wealth business_wealth other_wealth), missing

bysort dup_sig: gen n_true_dup = _N
bysort dup_sig: gen true_dup_seq = _n

* TRUE DUPLICATES: Same matching key AND same current assets
* These are likely the same filing processed twice
gen is_true_duplicate = (n_in_group > 1 & n_true_dup > 1 & true_dup_seq > 1)

count if is_true_duplicate == 1
local n_true_dups = r(N)
di "True duplicates identified (same person, duplicate filing): `n_true_dups'"

* Save info about true duplicates before dropping
preserve
keep if n_true_dup > 1
keep filename2019 municipio_name_mode fuzzy_key_group dup_sig ///
	financial_wealth2017 real_estate_wealth2017 ///
	business_wealth2017 other_wealth2017 ///
	financial_wealth real_estate_wealth business_wealth other_wealth ///
	true_dup_seq
save "$CleanDataPath/true_duplicates_2019.dta", replace
restore

* Drop true duplicates (keep first occurrence)
drop if is_true_duplicate == 1

* FALSE DUPLICATES: Same matching key but different current assets
* These are different people who happen to have similar previous-year assets
* We will keep all of them but need m:1 or m:m merge strategy

gen is_false_duplicate = (n_in_group > 1 & n_true_dup == 1)

count if is_false_duplicate == 1
local n_false_dups = r(N)
di "False duplicates (different people, same key): `n_false_dups'"

* Create a flag for records that need special handling in merge
gen needs_tiebreak = (n_in_group > 1)

* For unique records (n_in_group == 1), we can do 1:1 merge
* For duplicates, we'll need to use additional variables

save "$CleanDataPath/unmatched_2019_bucketed.dta", replace

*------------------------------------------------------------------------------
* STEP 5.3: Similarly prepare 2015-2018 unmatched data
*------------------------------------------------------------------------------

use "$CleanDataPath/unmatched_1518.dta", clear

foreach var in financial_wealth2017 real_estate_wealth2017 ///
	business_wealth2017 other_wealth2017 {

	gen `var'_bucket = .
	replace `var'_bucket = round(`var' / 1000) * 1000 if `var' > 10000
	replace `var'_bucket = round(`var' / 100) * 100 if `var' <= 10000 & `var' > 0
	replace `var'_bucket = 0 if `var' == 0
	replace `var'_bucket = . if `var' == .
}

* Check for duplicates in 1518 data too
egen fuzzy_key_group = group(municipio_name_mode ///
	financial_wealth2017_bucket real_estate_wealth2017_bucket ///
	business_wealth2017_bucket other_wealth2017_bucket), missing

bysort fuzzy_key_group: gen n_in_group = _N
bysort fuzzy_key_group: gen group_seq = _n

count if n_in_group > 1
local n_dups_1518 = r(N)
di "2015-2018 records sharing a matching key: `n_dups_1518'"

save "$CleanDataPath/unmatched_1518_bucketed.dta", replace

*------------------------------------------------------------------------------
* STEP 5.4: Fuzzy merge - handle unique keys first (1:1)
*------------------------------------------------------------------------------

* First, merge records with unique keys (no duplicates)
use "$CleanDataPath/unmatched_2019_bucketed.dta", clear
keep if needs_tiebreak == 0

tempfile unique_2019
save `unique_2019'

use "$CleanDataPath/unmatched_1518_bucketed.dta", clear
keep if n_in_group == 1

merge 1:1 municipio_name_mode ///
	financial_wealth2017_bucket real_estate_wealth2017_bucket ///
	business_wealth2017_bucket other_wealth2017_bucket ///
	using `unique_2019'

di "===== FUZZY MATCH (UNIQUE KEYS) ====="
tab _merge

* Save matched unique records
gen match_type = "fuzzy_unique" if _merge == 3
gen match_confidence = 90 if _merge == 3  // High confidence for unique matches

preserve
keep if _merge == 3
keep filename2019 id municipio_name_mode match_type match_confidence ///
	financial_wealth2017 real_estate_wealth2017 ///
	business_wealth2017 other_wealth2017
save "$CleanDataPath/fuzzy_matches_unique.dta", replace
restore

* Save unmatched for further processing
preserve
keep if _merge == 1
drop _merge match_type match_confidence
save "$CleanDataPath/still_unmatched_2019.dta", replace
restore

preserve
keep if _merge == 2
drop _merge match_type match_confidence
save "$CleanDataPath/still_unmatched_1518.dta", replace
restore

*------------------------------------------------------------------------------
* STEP 5.5: Fuzzy merge - handle duplicate keys (m:m with tiebreaker)
*------------------------------------------------------------------------------
* For records with duplicate keys, we use joinby and then pick best match
* based on similarity of current-year assets and other variables

use "$CleanDataPath/unmatched_2019_bucketed.dta", clear
keep if needs_tiebreak == 1

local n_needs_tiebreak = _N
di "2019 records needing tiebreak matching: `n_needs_tiebreak'"

if `n_needs_tiebreak' > 0 {

	* Rename variables to avoid conflicts in joinby
	rename financial_wealth financial_wealth_2019
	rename real_estate_wealth real_estate_wealth_2019
	rename business_wealth business_wealth_2019
	rename other_wealth other_wealth_2019
	rename financial_wealth2017 financial_wealth2017_2019
	rename real_estate_wealth2017 real_estate_wealth2017_2019
	rename business_wealth2017 business_wealth2017_2019
	rename other_wealth2017 other_wealth2017_2019

	drop fuzzy_key_group n_in_group group_seq dup_sig n_true_dup ///
		true_dup_seq is_true_duplicate is_false_duplicate needs_tiebreak

	tempfile dup_2019
	save `dup_2019'

	use "$CleanDataPath/unmatched_1518_bucketed.dta", clear
	keep if n_in_group > 1

	* Rename to indicate source
	rename financial_wealth2017 financial_wealth2017_1518
	rename real_estate_wealth2017 real_estate_wealth2017_1518
	rename business_wealth2017 business_wealth2017_1518
	rename other_wealth2017 other_wealth2017_1518

	drop fuzzy_key_group n_in_group group_seq

	* Join all possible matches
	joinby municipio_name_mode ///
		financial_wealth2017_bucket real_estate_wealth2017_bucket ///
		business_wealth2017_bucket other_wealth2017_bucket ///
		using `dup_2019', unmatched(both)

	di "===== FUZZY MATCH (DUPLICATE KEYS - ALL CANDIDATES) ====="
	tab _merge

	* For matched records, calculate match quality score
	* based on how similar the actual (non-bucketed) values are

	gen match_score = 0 if _merge == 3

	* Score based on closeness of previous year assets (exact match = 25 pts each)
	foreach var in financial_wealth2017 real_estate_wealth2017 ///
		business_wealth2017 other_wealth2017 {

		* Calculate absolute difference
		gen `var'_diff = abs(`var'_2019 - `var'_1518) if _merge == 3

		* Score: 25 points for exact match, decreasing for larger differences
		* Use log scale to handle large values
		gen `var'_score = 0 if _merge == 3
		replace `var'_score = 25 if `var'_diff == 0 & _merge == 3
		replace `var'_score = 20 if `var'_diff > 0 & `var'_diff <= 10 & _merge == 3
		replace `var'_score = 15 if `var'_diff > 10 & `var'_diff <= 100 & _merge == 3
		replace `var'_score = 10 if `var'_diff > 100 & `var'_diff <= 1000 & _merge == 3
		replace `var'_score = 5 if `var'_diff > 1000 & `var'_diff <= 10000 & _merge == 3
		replace `var'_score = 0 if `var'_diff > 10000 & _merge == 3

		replace match_score = match_score + `var'_score if _merge == 3
	}

	* Maximum score is 100 (perfect match on all 4 assets)

	di "Match score distribution for candidates:"
	summarize match_score if _merge == 3, detail

	* For each 2019 record, keep the best match (highest score)
	gsort filename2019 -match_score
	bysort filename2019: gen best_match = (_n == 1)

	* Also for each 1518 record, ensure it's not matched to multiple 2019 records
	gsort id -match_score
	bysort id: gen already_matched = (_n > 1 & best_match == 1)

	* Keep only best matches that aren't already used
	keep if _merge == 3 & best_match == 1 & already_matched == 0

	gen match_type = "fuzzy_tiebreak"
	gen match_confidence = match_score  // Score out of 100

	* Standardize variable names for output
	rename financial_wealth2017_1518 financial_wealth2017
	rename real_estate_wealth2017_1518 real_estate_wealth2017
	rename business_wealth2017_1518 business_wealth2017
	rename other_wealth2017_1518 other_wealth2017

	keep filename2019 id municipio_name_mode match_type match_confidence ///
		financial_wealth2017 real_estate_wealth2017 ///
		business_wealth2017 other_wealth2017

	save "$CleanDataPath/fuzzy_matches_tiebreak.dta", replace

	local n_tiebreak_matches = _N
	di "Tiebreak matches found: `n_tiebreak_matches'"
}
else {
	* Create empty file if no tiebreak needed
	clear
	gen filename2019 = ""
	gen id = ""
	gen municipio_name_mode = ""
	gen match_type = ""
	gen match_confidence = .
	gen financial_wealth2017 = .
	gen real_estate_wealth2017 = .
	gen business_wealth2017 = .
	gen other_wealth2017 = .
	save "$CleanDataPath/fuzzy_matches_tiebreak.dta", replace
}

*------------------------------------------------------------------------------
* STEP 5.6: Combine all fuzzy matches
*------------------------------------------------------------------------------

use "$CleanDataPath/fuzzy_matches_unique.dta", clear
append using "$CleanDataPath/fuzzy_matches_tiebreak.dta"

local n_total_fuzzy = _N
di "===== TOTAL FUZZY MATCHES: `n_total_fuzzy' ====="

save "$CleanDataPath/fuzzy_matches.dta", replace

tab match_type
summarize match_confidence, detail

********************************************************************************
* SECTION 6: COMBINE ALL MATCHES AND GENERATE STATISTICS
********************************************************************************

* Combine exact and fuzzy matches
use "$CleanDataPath/exact_matches.dta", clear
append using "$CleanDataPath/fuzzy_matches.dta"

local n_total_matched = _N

* Generate match quality summary
di " "
di "========================================"
di "FINAL MATCH SUMMARY"
di "========================================"
di " "
tab match_type
summarize match_confidence, detail

* Save final matched dataset
save "$CleanDataPath/all_matches.dta", replace

* Generate match quality report
preserve
collapse (count) n_matches = id (mean) avg_confidence = match_confidence ///
	(min) min_confidence = match_confidence ///
	(max) max_confidence = match_confidence, by(match_type)
list
export delimited using "$OutputPath/match_quality_report.csv", replace
restore

di " "
di "========================================"
di "OUTPUT FILES CREATED"
di "========================================"
di "$CleanDataPath/clean_2015_2018.dta - Cleaned 2015-2018 data"
di "$CleanDataPath/clean_2019.dta - Cleaned 2019 data"
di "$CleanDataPath/exact_matches.dta - Exact matches"
di "$CleanDataPath/fuzzy_matches.dta - Fuzzy matches"
di "$CleanDataPath/all_matches.dta - All matches combined"
di "$OutputPath/match_quality_report.csv - Match quality statistics"

********************************************************************************
* END OF SCRIPT
********************************************************************************
