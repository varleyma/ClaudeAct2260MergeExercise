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
* SECTION 3: PREPARE DATA FOR MULTI-YEAR MATCHING
********************************************************************************
* EXPANDED MATCHING STRATEGY:
* 1. Match across ALL available years (2013-2017), not just 2017
* 2. Match WITHIN the 2019 file (multiple reports of same person)
* 3. Allow 1-2 digit typo tolerance with confidence penalties
*
* Key insight:
*   2019 record with previous_year=Y should match to
*   2015-2018 record's year=Y current assets
********************************************************************************

*------------------------------------------------------------------------------
* STEP 3.1: Reshape 2015-2018 data to long format for multi-year matching
*------------------------------------------------------------------------------
* We need to match on ANY year, not just 2017

use "$CleanDataPath/clean_2015_2018.dta", clear

* Reshape from wide to long to get one row per id-year
reshape long financial_wealth real_estate_wealth business_wealth other_wealth ///
	financial_wealth_pre real_estate_wealth_pre business_wealth_pre other_wealth_pre, ///
	i(id decree_year municipio_name_mode municipio_name_last) j(year)

* Drop rows with no data for this year
drop if financial_wealth == "" & real_estate_wealth == "" & ///
	business_wealth == "" & other_wealth == ""

* Drop if all assets are NA
drop if financial_wealth == "NA" & real_estate_wealth == "NA" & ///
	business_wealth == "NA" & other_wealth == "NA"

* Convert to numeric
foreach var in financial_wealth real_estate_wealth business_wealth other_wealth {
	destring `var', replace force
	replace `var' = round(`var')
}

* Keep matching variables
keep id municipio_name_mode year financial_wealth real_estate_wealth ///
	business_wealth other_wealth

* Rename for clarity - these are the CURRENT year values from 2015-2018 file
rename financial_wealth fin_1518
rename real_estate_wealth re_1518
rename business_wealth bus_1518
rename other_wealth oth_1518
rename year match_year

local n_1518_long = _N
di "2015-2018 records in long format (id-year pairs): `n_1518_long'"

save "$CleanDataPath/clean_1518_long.dta", replace

*------------------------------------------------------------------------------
* STEP 3.2: Prepare 2019 data with previous year values for matching
*------------------------------------------------------------------------------

use "$CleanDataPath/clean_2019.dta", clear

* Keep records that have previous year data
drop if previous_year == .

* Convert previous year assets to numeric
foreach var in financial_wealth_pre real_estate_wealth_pre ///
	business_wealth_pre other_wealth_pre {
	destring `var', replace force
	replace `var' = round(`var')
}

* Rename for clarity - previous year values will match to 2015-2018 current values
rename financial_wealth_pre fin_2019_pre
rename real_estate_wealth_pre re_2019_pre
rename business_wealth_pre bus_2019_pre
rename other_wealth_pre oth_2019_pre
rename previous_year match_year

* Also keep current year values for tiebreaking and within-2019 matching
foreach var in financial_wealth real_estate_wealth business_wealth other_wealth {
	destring `var', replace force
	replace `var' = round(`var')
}
rename financial_wealth fin_2019_cur
rename real_estate_wealth re_2019_cur
rename business_wealth bus_2019_cur
rename other_wealth oth_2019_cur

* Keep matching variables
keep filename2019 municipio_name match_year year ///
	fin_2019_pre re_2019_pre bus_2019_pre oth_2019_pre ///
	fin_2019_cur re_2019_cur bus_2019_cur oth_2019_cur

rename municipio_name municipio_name_mode
rename year report_year

local n_2019_matchable = _N
di "2019 records with previous year data: `n_2019_matchable'"

save "$CleanDataPath/clean_2019_long.dta", replace

********************************************************************************
* SECTION 4: MULTI-STAGE MATCHING WITH TYPO TOLERANCE
********************************************************************************
* Stage 1: Exact match on municipality + year + all 4 assets
* Stage 2: Fuzzy match allowing 1-digit difference (confidence 90)
* Stage 3: Fuzzy match allowing 2-digit difference (confidence 80)
* Stage 4: Match ignoring one asset at a time (confidence 70)
********************************************************************************

*------------------------------------------------------------------------------
* STEP 4.1: EXACT MATCHING (Confidence = 100)
*------------------------------------------------------------------------------
* Use joinby instead of merge to handle non-unique keys, then deduplicate

* Load 2019 data
use "$CleanDataPath/clean_2019_long.dta", clear

* Create standardized join keys from 2019 previous year values
rename fin_2019_pre fin_key
rename re_2019_pre re_key
rename bus_2019_pre bus_key
rename oth_2019_pre oth_key

tempfile temp_2019_for_join
save `temp_2019_for_join'

* Load 2015-2018 data and create matching keys
use "$CleanDataPath/clean_1518_long.dta", clear
rename fin_1518 fin_key
rename re_1518 re_key
rename bus_1518 bus_key
rename oth_1518 oth_key

* Join on all 6 keys: municipality + year + 4 assets
joinby municipio_name_mode match_year fin_key re_key bus_key oth_key ///
	using `temp_2019_for_join', unmatched(both) _merge(_join_exact)

* Rename keys back
rename fin_key fin_2019_pre
rename re_key re_2019_pre
rename bus_key bus_2019_pre
rename oth_key oth_2019_pre

* Count matches
count if _join_exact == 3
local n_exact_raw = r(N)
di "Raw exact match pairs: `n_exact_raw'"

* Save exact matches (matched records)
preserve
keep if _join_exact == 3

* Handle duplicates: if same 2019 record matches multiple 1518 records, keep first
* (they have same assets so it's arbitrary which one we pick)
bysort filename2019 (id): gen dup_2019 = _n
keep if dup_2019 == 1
drop dup_2019

* Also prevent same 1518 record from matching multiple 2019 records
bysort id match_year (filename2019): gen dup_1518 = _n
keep if dup_1518 == 1
drop dup_1518

count
local n_exact = r(N)
di "===== EXACT MATCHES (after deduplication): `n_exact' ====="

gen match_type = "exact"
gen match_confidence = 100
gen digits_changed = 0
keep filename2019 id municipio_name_mode match_year report_year ///
	fin_2019_pre re_2019_pre bus_2019_pre oth_2019_pre ///
	match_type match_confidence digits_changed
save "$CleanDataPath/matches_exact.dta", replace
restore

* Keep unmatched 2019 records for fuzzy matching
* _join_exact == 2 means record was only in 2019 (using data), not matched
keep if _join_exact == 2
drop _join_exact id
save "$CleanDataPath/unmatched_2019_stage1.dta", replace

*------------------------------------------------------------------------------
* STEP 4.2: FUZZY MATCHING WITH DIGIT TOLERANCE
*------------------------------------------------------------------------------
* Strategy: Use joinby to create all candidate pairs, then score by
* number of digits that differ. A "digit difference" is defined as:
* - Values that differ by a factor of ~10 (one digit typo)
* - E.g., 109600 vs 103600 differ by 6000 which is ~1 digit off
*
* We calculate "digit distance" for each asset and sum across assets.
* Keep matches where total digit distance <= 2
*------------------------------------------------------------------------------

use "$CleanDataPath/unmatched_2019_stage1.dta", clear
local n_to_fuzzy = _N
di "Records for fuzzy matching: `n_to_fuzzy'"

if `n_to_fuzzy' > 0 {

	* Create join key on municipality + year only
	tempfile fuzzy_2019
	save `fuzzy_2019'

	use "$CleanDataPath/clean_1518_long.dta", clear

	* Remove records already matched
	merge m:1 id match_year using "$CleanDataPath/matches_exact.dta", ///
		keepusing(id) keep(master) nogen

	* Join all candidate pairs on municipality + year
	joinby municipio_name_mode match_year using `fuzzy_2019', unmatched(none)

	local n_candidates = _N
	di "Candidate pairs for fuzzy matching: `n_candidates'"

	if `n_candidates' > 0 {

		*------------------------------------------------------------------
		* Calculate digit distance for each asset
		*------------------------------------------------------------------
		* Digit distance: how many digits would need to change to match
		* We approximate this by looking at the ratio and log10

		foreach asset in fin re bus oth {

			* Calculate absolute difference
			gen `asset'_diff = abs(`asset'_2019_pre - `asset'_1518)

			* Calculate the magnitude of each value (number of digits)
			gen `asset'_mag_2019 = floor(log10(max(`asset'_2019_pre, 1))) + 1
			gen `asset'_mag_1518 = floor(log10(max(`asset'_1518, 1))) + 1
			gen `asset'_mag = max(`asset'_mag_2019, `asset'_mag_1518)

			* Digit distance: difference relative to magnitude
			* 0 = exact match
			* 1 = off by ~1 digit (e.g., 6000 difference in 6-digit number)
			* 2 = off by ~2 digits
			gen `asset'_digit_dist = 0

			* Exact match
			replace `asset'_digit_dist = 0 if `asset'_diff == 0

			* 1-digit error: difference is < 10^(mag-1) but > 0
			* E.g., for 100000, 1-digit error is < 10000
			replace `asset'_digit_dist = 1 if `asset'_diff > 0 & ///
				`asset'_diff <= 10^(`asset'_mag - 1)

			* 2-digit error: difference is < 10^(mag) but > 10^(mag-1)
			replace `asset'_digit_dist = 2 if `asset'_diff > 10^(`asset'_mag - 1) & ///
				`asset'_diff <= 10^(`asset'_mag)

			* More than 2 digits: not a match
			replace `asset'_digit_dist = 99 if `asset'_diff > 10^(`asset'_mag)

			* Handle zeros and missing
			replace `asset'_digit_dist = 0 if `asset'_2019_pre == 0 & `asset'_1518 == 0
			replace `asset'_digit_dist = 0 if `asset'_2019_pre == . & `asset'_1518 == .
			replace `asset'_digit_dist = 1 if (`asset'_2019_pre == 0 | `asset'_2019_pre == .) & ///
				`asset'_1518 > 0 & `asset'_1518 <= 1000
			replace `asset'_digit_dist = 1 if (`asset'_1518 == 0 | `asset'_1518 == .) & ///
				`asset'_2019_pre > 0 & `asset'_2019_pre <= 1000
		}

		* Total digit distance across all 4 assets
		gen total_digit_dist = fin_digit_dist + re_digit_dist + ///
			bus_digit_dist + oth_digit_dist

		* Count how many assets have exact match vs 1-digit vs 2-digit
		gen n_exact_assets = (fin_digit_dist == 0) + (re_digit_dist == 0) + ///
			(bus_digit_dist == 0) + (oth_digit_dist == 0)
		gen n_1digit_assets = (fin_digit_dist == 1) + (re_digit_dist == 1) + ///
			(bus_digit_dist == 1) + (oth_digit_dist == 1)
		gen n_2digit_assets = (fin_digit_dist == 2) + (re_digit_dist == 2) + ///
			(bus_digit_dist == 2) + (oth_digit_dist == 2)

		*------------------------------------------------------------------
		* Filter to valid fuzzy matches (max 2 total digit distance)
		*------------------------------------------------------------------

		* Keep only matches where total digit distance <= 2
		* AND no single asset has more than 2-digit difference
		gen valid_fuzzy = (total_digit_dist <= 2) & ///
			(fin_digit_dist <= 2) & (re_digit_dist <= 2) & ///
			(bus_digit_dist <= 2) & (oth_digit_dist <= 2)

		count if valid_fuzzy == 1
		local n_valid_fuzzy = r(N)
		di "Valid fuzzy match candidates: `n_valid_fuzzy'"

		keep if valid_fuzzy == 1

		*------------------------------------------------------------------
		* Calculate confidence score
		*------------------------------------------------------------------
		* Base confidence = 100
		* Penalty: -5 for each 1-digit difference, -10 for each 2-digit difference

		gen match_confidence = 100 - (n_1digit_assets * 5) - (n_2digit_assets * 10)

		* Classify match type
		gen match_type = ""
		replace match_type = "fuzzy_1digit" if total_digit_dist > 0 & total_digit_dist <= 1
		replace match_type = "fuzzy_2digit" if total_digit_dist > 1 & total_digit_dist <= 2

		gen digits_changed = total_digit_dist

		*------------------------------------------------------------------
		* Handle multiple candidates: keep best match for each 2019 record
		*------------------------------------------------------------------

		* Sort by confidence (descending) within each 2019 record
		gsort filename2019 -match_confidence
		bysort filename2019: gen best_for_2019 = (_n == 1)

		* Also prevent same 1518 record from matching multiple 2019 records
		gsort id match_year -match_confidence
		bysort id match_year: gen already_used = (_n > 1)

		* Keep best match that isn't already used
		keep if best_for_2019 == 1 & already_used == 0

		count
		local n_fuzzy_matches = r(N)
		di "===== FUZZY MATCHES (after deduplication): `n_fuzzy_matches' ====="

		* Summary of fuzzy matches by type
		tab match_type
		summarize match_confidence, detail

		* Save fuzzy matches
		keep filename2019 id municipio_name_mode match_year report_year ///
			fin_2019_pre re_2019_pre bus_2019_pre oth_2019_pre ///
			match_type match_confidence digits_changed

		save "$CleanDataPath/matches_fuzzy.dta", replace
	}
	else {
		* No candidates - create empty file
		clear
		gen filename2019 = ""
		gen id = ""
		gen municipio_name_mode = ""
		gen match_year = .
		gen report_year = .
		gen fin_2019_pre = .
		gen re_2019_pre = .
		gen bus_2019_pre = .
		gen oth_2019_pre = .
		gen match_type = ""
		gen match_confidence = .
		gen digits_changed = .
		save "$CleanDataPath/matches_fuzzy.dta", replace
	}
}
else {
	* No records to fuzzy match - create empty file
	clear
	gen filename2019 = ""
	gen id = ""
	gen municipio_name_mode = ""
	gen match_year = .
	gen report_year = .
	gen fin_2019_pre = .
	gen re_2019_pre = .
	gen bus_2019_pre = .
	gen oth_2019_pre = .
	gen match_type = ""
	gen match_confidence = .
	gen digits_changed = .
	save "$CleanDataPath/matches_fuzzy.dta", replace
}

*------------------------------------------------------------------------------
* STEP 4.3: WITHIN-2019 MATCHING
*------------------------------------------------------------------------------
* Match records within the 2019 file that appear to be the same person
* (multiple filings for different years)

use "$CleanDataPath/clean_2019_long.dta", clear

* Create a self-join on municipality + overlapping year info
* Record A's current year assets should match Record B's previous year assets
* if they're the same person filing for consecutive years

* For this, we need: A.report_year = B.match_year AND A.current_assets = B.prev_assets

rename filename2019 filename_A
rename report_year report_year_A
rename match_year match_year_A
rename fin_2019_cur fin_cur_A
rename re_2019_cur re_cur_A
rename bus_2019_cur bus_cur_A
rename oth_2019_cur oth_cur_A
rename fin_2019_pre fin_pre_A
rename re_2019_pre re_pre_A
rename bus_2019_pre bus_pre_A
rename oth_2019_pre oth_pre_A

tempfile self_A
save `self_A'

use "$CleanDataPath/clean_2019_long.dta", clear
rename filename2019 filename_B
rename report_year report_year_B
rename match_year match_year_B
rename fin_2019_cur fin_cur_B
rename re_2019_cur re_cur_B
rename bus_2019_cur bus_cur_B
rename oth_2019_cur oth_cur_B
rename fin_2019_pre fin_pre_B
rename re_2019_pre re_pre_B
rename bus_2019_pre bus_pre_B
rename oth_2019_pre oth_pre_B

* Join on municipality
joinby municipio_name_mode using `self_A', unmatched(none)

* Keep pairs where A's current year = B's previous year
* (i.e., A filed for year Y, B filed for year Y+1 and reports Y as previous)
keep if report_year_A == match_year_B

* Keep pairs where A's current assets match B's previous assets (with tolerance)
foreach asset in fin re bus oth {
	gen `asset'_diff = abs(`asset'_cur_A - `asset'_pre_B)
	gen `asset'_match = (`asset'_diff == 0)
	gen `asset'_close = (`asset'_diff <= 10^(floor(log10(max(`asset'_cur_A, 1)))))
}

gen n_asset_match = fin_match + re_match + bus_match + oth_match
gen n_asset_close = fin_close + re_close + bus_close + oth_close

* Keep matches where at least 3 assets match exactly, or all 4 are close
keep if n_asset_match >= 3 | n_asset_close == 4

* Remove self-matches
drop if filename_A == filename_B

* Calculate confidence
gen within_match_conf = 70 + (n_asset_match * 5)

* Keep best match for each B record
gsort filename_B -within_match_conf
bysort filename_B: gen best_within = (_n == 1)
keep if best_within == 1

count
local n_within = r(N)
di "===== WITHIN-2019 MATCHES: `n_within' ====="

if `n_within' > 0 {
	keep filename_A filename_B municipio_name_mode report_year_A report_year_B ///
		within_match_conf n_asset_match
	rename within_match_conf match_confidence
	gen match_type = "within_2019"
	save "$CleanDataPath/matches_within_2019.dta", replace
}
else {
	clear
	gen filename_A = ""
	gen filename_B = ""
	gen municipio_name_mode = ""
	gen report_year_A = .
	gen report_year_B = .
	gen match_confidence = .
	gen match_type = ""
	gen n_asset_match = .
	save "$CleanDataPath/matches_within_2019.dta", replace
}

********************************************************************************
* SECTION 5: COMBINE ALL MATCHES AND GENERATE STATISTICS
********************************************************************************

di " "
di "========================================"
di "COMBINING ALL MATCH FILES"
di "========================================"

* Combine exact and fuzzy matches (2019 to 2015-2018)
use "$CleanDataPath/matches_exact.dta", clear
append using "$CleanDataPath/matches_fuzzy.dta"

* Standardize variable names
capture rename fin_2019_pre financial_wealth_prev
capture rename re_2019_pre real_estate_wealth_prev
capture rename bus_2019_pre business_wealth_prev
capture rename oth_2019_pre other_wealth_prev

local n_cross_file = _N
di "Cross-file matches (2019 to 2015-2018): `n_cross_file'"

save "$CleanDataPath/all_matches.dta", replace

* Generate match quality summary
di " "
di "========================================"
di "FINAL MATCH SUMMARY"
di "========================================"
di " "
tab match_type
summarize match_confidence, detail

* Generate match quality report
preserve
gen one = 1
collapse (sum) n_matches = one (mean) avg_confidence = match_confidence ///
	(min) min_confidence = match_confidence ///
	(max) max_confidence = match_confidence, by(match_type)
list
export delimited using "$OutputPath/match_quality_report.csv", replace
restore

* Also report within-2019 matches separately
di " "
di "========================================"
di "WITHIN-2019 MATCHES (same person, multiple filings)"
di "========================================"
use "$CleanDataPath/matches_within_2019.dta", clear
count
local n_within = r(N)
di "Within-2019 linked records: `n_within'"
if `n_within' > 0 {
	tab match_type
	summarize match_confidence, detail
}

di " "
di "========================================"
di "OUTPUT FILES CREATED"
di "========================================"
di "$CleanDataPath/clean_2015_2018.dta - Cleaned 2015-2018 data (wide format)"
di "$CleanDataPath/clean_1518_long.dta - Cleaned 2015-2018 data (long format)"
di "$CleanDataPath/clean_2019.dta - Cleaned 2019 data"
di "$CleanDataPath/clean_2019_long.dta - Cleaned 2019 data for matching"
di "$CleanDataPath/matches_exact.dta - Exact matches"
di "$CleanDataPath/matches_fuzzy.dta - Fuzzy matches (1-2 digit tolerance)"
di "$CleanDataPath/matches_within_2019.dta - Within-2019 person links"
di "$CleanDataPath/all_matches.dta - All cross-file matches combined"
di "$OutputPath/match_quality_report.csv - Match quality statistics"

di " "
di "========================================"
di "SUMMARY STATISTICS"
di "========================================"

* Count unique persons in each original file
use "$CleanDataPath/clean_2015_2018.dta", clear
local n_unique_1518 = _N
di "Unique persons in 2015-2018 file: `n_unique_1518'"

use "$CleanDataPath/clean_2019.dta", clear
local n_unique_2019 = _N
di "Unique records in 2019 file: `n_unique_2019'"

* Count matchable 2019 records (those with previous year data)
use "$CleanDataPath/clean_2019_long.dta", clear
local n_matchable_2019 = _N
di "Matchable 2019 records (with previous year data): `n_matchable_2019'"

* Count matches
use "$CleanDataPath/all_matches.dta", clear
local n_total = _N

count if match_type == "exact"
local n_exact = r(N)

count if match_type == "fuzzy_1digit"
local n_fuzzy1 = r(N)

count if match_type == "fuzzy_2digit"
local n_fuzzy2 = r(N)

* Count unique 2019 records that were matched
preserve
keep filename2019
duplicates drop
local n_2019_matched = _N
restore

* Count unique 1518 IDs that were matched
preserve
keep id
duplicates drop
local n_1518_matched = _N
restore

di " "
di "========================================"
di "MATCH RESULTS"
di "========================================"
di " "
di "ORIGINAL DATA:"
di "  - Unique persons in 2015-2018 file: `n_unique_1518'"
di "  - Total records in 2019 file: `n_unique_2019'"
di "  - Matchable 2019 records (with prev year data): `n_matchable_2019'"
di " "
di "MATCHES FOUND:"
di "  - Total matches: `n_total'"
di "    - Exact matches: `n_exact'"
di "    - Fuzzy (1-digit): `n_fuzzy1'"
di "    - Fuzzy (2-digit): `n_fuzzy2'"
di " "
di "MATCH RATES:"
local pct_2019 = round(100 * `n_2019_matched' / `n_matchable_2019', 0.1)
local pct_1518 = round(100 * `n_1518_matched' / `n_unique_1518', 0.1)
di "  - 2019 records matched: `n_2019_matched' / `n_matchable_2019' (`pct_2019'%)"
di "  - 2015-2018 persons matched: `n_1518_matched' / `n_unique_1518' (`pct_1518'%)"

di " "
di "========================================"
di "DIAGNOSTICS: WHY RECORDS DIDN'T MATCH"
di "========================================"

*------------------------------------------------------------------------------
* Analyze 2015-2018 file: What's the last reporting year for each person?
*------------------------------------------------------------------------------
di " "
di "--- 2015-2018 FILE: Last Reporting Year Distribution ---"

use "$CleanDataPath/clean_1518_long.dta", clear

* Find the last (max) year each person reported
bysort id: egen last_year = max(match_year)

* Keep one row per person
bysort id: keep if _n == 1

* Tabulate last reporting year
di "Last reporting year for each person in 2015-2018 file:"
tab last_year

* Count how many have last year before 2017
count if last_year < 2017
local n_before_2017 = r(N)
local pct_before_2017 = round(100 * `n_before_2017' / `n_unique_1518', 0.1)
di " "
di "Persons whose last report was BEFORE 2017: `n_before_2017' (`pct_before_2017'%)"
di "  (These cannot match to 2019 file where most report 2017 as previous year)"

* Check which of these were matched vs unmatched
* First create a unique list of matched IDs
preserve
use "$CleanDataPath/all_matches.dta", clear
keep id
duplicates drop
tempfile matched_ids
save `matched_ids'
restore

merge 1:1 id using `matched_ids', keep(master match) gen(_matched)

di " "
di "Breakdown by match status and last year:"
tab last_year _matched, row

*------------------------------------------------------------------------------
* Analyze 2019 file: What previous year do they report?
*------------------------------------------------------------------------------
di " "
di "--- 2019 FILE: Previous Year (match_year) Distribution ---"

use "$CleanDataPath/clean_2019_long.dta", clear
di "Previous year reported in 2019 file:"
tab match_year

* How many report years that aren't in the 2015-2018 data?
count if match_year < 2013
local n_pre_2013 = r(N)
di " "
di "2019 records reporting previous year before 2013: `n_pre_2013'"
di "  (These cannot match because 2015-2018 file only has years 2013-2017)"

*------------------------------------------------------------------------------
* Analyze unmatched 2019 records: Why didn't they match?
*------------------------------------------------------------------------------
di " "
di "--- UNMATCHED 2019 RECORDS: Analysis ---"

* Load 2019 matchable records
use "$CleanDataPath/clean_2019_long.dta", clear

* Merge to see which were matched
* First create a unique list of matched filenames
preserve
use "$CleanDataPath/all_matches.dta", clear
keep filename2019
duplicates drop
tempfile matched_filenames
save `matched_filenames'
restore

merge 1:1 filename2019 using `matched_filenames', keep(master match) gen(_was_matched)

* Keep unmatched
keep if _was_matched == 1
local n_unmatched_2019 = _N
di "Unmatched 2019 records: `n_unmatched_2019'"

if `n_unmatched_2019' > 0 {
	di " "
	di "Previous year distribution of UNMATCHED 2019 records:"
	tab match_year

	di " "
	di "Municipality distribution of UNMATCHED 2019 records (top 10):"
	preserve
	gen one = 1
	collapse (sum) n = one, by(municipio_name_mode)
	gsort -n
	list in 1/10
	restore

	* Check if their previous year exists in 2015-2018 at all
	di " "
	di "Checking if unmatched 2019 records have ANY potential match in 2015-2018..."

	* Create a unique list of municipality + year combinations in 2015-2018
	preserve
	use "$CleanDataPath/clean_1518_long.dta", clear
	keep municipio_name_mode match_year
	duplicates drop
	tempfile muni_year_combos
	save `muni_year_combos'
	restore

	* For each unmatched 2019, check if there's a 2015-2018 record with same municipality + year
	merge m:1 municipio_name_mode match_year using `muni_year_combos', ///
		keep(master match) gen(_has_muni_year)

	count if _has_muni_year == 1
	local n_no_muni_year = r(N)
	local pct_no_muni_year = round(100 * `n_no_muni_year' / `n_unmatched_2019', 0.1)
	di "Unmatched because NO 2015-2018 record exists with same municipality + year: `n_no_muni_year' (`pct_no_muni_year'%)"

	count if _has_muni_year == 3
	local n_has_muni_year = r(N)
	local pct_has_muni_year = round(100 * `n_has_muni_year' / `n_unmatched_2019', 0.1)
	di "Had municipality + year match but assets didn't match: `n_has_muni_year' (`pct_has_muni_year'%)"
}

*------------------------------------------------------------------------------
* Analyze unmatched 2015-2018 persons
*------------------------------------------------------------------------------
di " "
di "--- UNMATCHED 2015-2018 PERSONS: Analysis ---"

use "$CleanDataPath/clean_2015_2018.dta", clear

* Merge to see which were matched
* First create a unique list of matched IDs
preserve
use "$CleanDataPath/all_matches.dta", clear
keep id
duplicates drop
tempfile matched_ids_1518
save `matched_ids_1518'
restore

merge 1:1 id using `matched_ids_1518', keep(master match) gen(_was_matched)

* Keep unmatched
keep if _was_matched == 1
local n_unmatched_1518 = _N
di "Unmatched 2015-2018 persons: `n_unmatched_1518'"

if `n_unmatched_1518' > 0 {
	* Get their last reporting year from long file
	merge 1:m id using "$CleanDataPath/clean_1518_long.dta", ///
		keepusing(match_year) keep(match) nogen

	bysort id: egen last_year = max(match_year)
	bysort id: keep if _n == 1

	di " "
	di "Last reporting year of UNMATCHED 2015-2018 persons:"
	tab last_year

	count if last_year == 2017
	local n_unmatched_2017 = r(N)
	di " "
	di "Unmatched persons who DID report in 2017: `n_unmatched_2017'"
	di "  (These should have been matchable - check municipality spelling or asset values)"

	di " "
	di "Municipality distribution of UNMATCHED 2015-2018 persons (top 10):"
	preserve
	gen one = 1
	collapse (sum) n = one, by(municipio_name_mode)
	gsort -n
	list in 1/10
	restore
}

di " "
di "========================================"
di "END OF DIAGNOSTICS"
di "========================================"

********************************************************************************
* SECTION 7: CREATE PANEL DATASET
********************************************************************************
* Create a unified panel dataset with:
*   - panel_id: unique person identifier (created)
*   - report_year: current reporting year (time variable)
*   - id: original ID from 2015-2018 file (empty for unmatched 2019 records)
*   - filename: original CSV filename
*   - fin: financial wealth (current year)
*   - re: real estate wealth (current year)
*   - bus: business wealth (current year)
*   - oth: other wealth (current year)
********************************************************************************

di " "
di "========================================"
di "CREATING PANEL DATASET"
di "========================================"

*------------------------------------------------------------------------------
* STEP 7.1: Get matched IDs from all_matches
*------------------------------------------------------------------------------
use "$CleanDataPath/all_matches.dta", clear
keep id filename2019
duplicates drop
rename filename2019 filename
tempfile matched_links
save `matched_links'

*------------------------------------------------------------------------------
* STEP 7.2: Build 2015-2018 panel observations
*------------------------------------------------------------------------------
* Re-import raw data to get current year assets for each year

import delimited "$RawDataPath/Act22AnnualReports2015-2018.csv", ///
	varnames(1) clear stringcols(_all)

* Keep key variables
keep id filename current_reporting_year ///
	asset_type_financial_current_rep asset_type_real_estate_current_r ///
	asset_type_privately_held_busin asset_type_other_current_reporti

* Rename and clean
rename current_reporting_year report_year
rename asset_type_financial_current_rep fin
rename asset_type_real_estate_current_r re
capture rename asset_type_privately_held_busin bus
capture rename v40 bus
rename asset_type_other_current_reporti oth

* Convert to numeric
destring report_year fin re bus oth, replace force

* Drop duplicates (keep first observation for each id-year)
sort id report_year
bysort id report_year: keep if _n == 1

* Mark source
gen source = "2015-2018"

tempfile panel_1518
save `panel_1518'

di "2015-2018 panel observations: " _N

*------------------------------------------------------------------------------
* STEP 7.3: Build 2019 panel observations
*------------------------------------------------------------------------------
import delimited "$RawDataPath/Act22AnnualReports2019.csv", ///
	varnames(1) clear stringcols(_all)

* Keep key variables
keep filename current_reporting_year ///
	asset_type_financial_current_rep asset_type_real_estate_current_r ///
	asset_type_privately_held_busin asset_type_other_current_reporti

* Rename and clean
rename current_reporting_year report_year
rename asset_type_financial_current_rep fin
rename asset_type_real_estate_current_r re
rename asset_type_privately_held_busin bus
rename asset_type_other_current_reporti oth

* Convert to numeric
destring report_year fin re bus oth, replace force

* Merge in ID from matched records
merge 1:1 filename using `matched_links', keep(master match) nogen

* Mark source
gen source = "2019"

tempfile panel_2019
save `panel_2019'

di "2019 panel observations: " _N

*------------------------------------------------------------------------------
* STEP 7.4: Combine into unified panel
*------------------------------------------------------------------------------
use `panel_1518', clear
append using `panel_2019'

di "Combined panel observations: " _N

*------------------------------------------------------------------------------
* STEP 7.5: Create unified panel_id
*------------------------------------------------------------------------------
* Logic:
*   - If id exists (from 2015-2018 or matched 2019), use id as base
*   - If id missing (unmatched 2019), create new ID based on filename

* First, for records with id, panel_id = id
gen panel_id = id

* For records without id, use filename as panel_id
* This ensures stability - same filename always gets same panel_id
count if panel_id == ""
local n_need_id = r(N)
di "Records needing new panel_id: `n_need_id'"

replace panel_id = filename if panel_id == ""

*------------------------------------------------------------------------------
* STEP 7.6: Final cleanup and order
*------------------------------------------------------------------------------
* Keep only the 8 required variables
keep panel_id report_year id filename fin re bus oth

* Order variables
order panel_id report_year id filename fin re bus oth

* Sort by panel_id and year
sort panel_id report_year

* Label variables
label var panel_id "Unique person identifier (created)"
label var report_year "Current reporting year"
label var id "Original ID from 2015-2018 file (empty if unmatched 2019)"
label var filename "Original CSV filename"
label var fin "Financial wealth (current year)"
label var re "Real estate wealth (current year)"
label var bus "Business wealth (current year)"
label var oth "Other wealth (current year)"

* Verify panel structure
di " "
di "Panel dataset summary:"
di "======================"
egen tag_panel_id = tag(panel_id)
count if tag_panel_id == 1
local n_persons = r(N)
drop tag_panel_id
di "Unique persons (panel_id): `n_persons'"

tab report_year

* Count by source
count if id != ""
local n_with_id = r(N)
count if id == ""
local n_without_id = r(N)
di " "
di "Observations with original ID: `n_with_id'"
di "Observations without original ID (unmatched 2019): `n_without_id'"

* Save panel dataset
save "$CleanDataPath/act22_panel.dta", replace

di " "
di "========================================"
di "PANEL DATASET SAVED"
di "========================================"
di "File: $CleanDataPath/act22_panel.dta"
di "Variables: panel_id report_year id filename fin re bus oth"
di "Unique persons: `n_persons'"
di "Total observations: " _N

********************************************************************************
* END OF SCRIPT
********************************************************************************
