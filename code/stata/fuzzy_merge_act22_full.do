********************************************************************************
* FUZZY MERGE OF ACT 22 INDIVIDUAL INVESTOR ANNUAL REPORTS - FULL PANEL
********************************************************************************
*
* Purpose: 	Link individual investor records across ALL years (2015-2023)
*			using fuzzy matching on municipality and asset values
*
* Authors: 	Michael Varley, Lucy Msall, with Claude AI assistance
* Created: 	January 30, 2025
*
* Data Sources:
*	- Act22AnnualReports2015-2018.csv (has unique ID per person)
*	- Act22AnnualReports2019.csv (NO unique ID)
*	- Act22AnnualReports2020.csv (NO unique ID)
*	- Act22AnnualReports2021.csv (NO unique ID)
*	- Act22AnnualReports2022_format19.csv (NO unique ID, old form format)
*	- Act22AnnualReports2022_format22.csv (NO unique ID, new form format)
*	- Act22AnnualReports2023.csv (NO unique ID)
*
* Matching Strategy:
*	1. Clean municipality names to standardized format across all files
*	2. Extract previous year asset values from all datasets
*	3. Match sequentially: 2015-2018 → 2019 → 2020 → 2021 → 2022 → 2023
*	4. Apply fuzzy matching with tolerance for 1-2 digit typos in asset values
*	5. Generate confidence scores based on match quality
*	6. Create unified panel dataset
*
* Key Variables for Matching:
*	- municipio_name: Puerto Rico municipality of residence
*	- previous_reporting_year / current_reporting_year: Year identifiers
*	- 4 asset types: financial, real_estate, business, other (previous year values)
*
********************************************************************************

set more off
clear all

********************************************************************************
* SECTION 0: SET UP FILE PATHS
********************************************************************************

global MyPath "C:/Users/mva284"

global GitHubPath "$MyPath/Documents/GitHub/ClaudeAct2260MergeExercise"
global RawDataPath "$GitHubPath/data/raw"
global CleanDataPath "$GitHubPath/data/clean"
global OutputPath "$GitHubPath/output"

* Create output directories if they don't exist
capture mkdir "$CleanDataPath"
capture mkdir "$OutputPath"

********************************************************************************
* SECTION 1: DEFINE MUNICIPALITY STANDARDIZATION PROGRAM
********************************************************************************
* This program standardizes municipality names across all files.
* STRATEGY: Convert to uppercase first, then clean suffixes, then map to standard names.
* IMPORTANT: Municipality must be a Puerto Rico municipality, NOT a US mainland location.
********************************************************************************

capture program drop standardize_municipio
program define standardize_municipio
	* Input: variable called municipio_name
	* Output: standardized municipio_name (UPPERCASE, ASCII only)

	* STEP 1: Replace accented characters with ASCII equivalents BEFORE uppercasing
	* Spanish accented vowels (lowercase)
	replace municipio_name = subinstr(municipio_name, "á", "a", .)
	replace municipio_name = subinstr(municipio_name, "é", "e", .)
	replace municipio_name = subinstr(municipio_name, "í", "i", .)
	replace municipio_name = subinstr(municipio_name, "ó", "o", .)
	replace municipio_name = subinstr(municipio_name, "ú", "u", .)
	replace municipio_name = subinstr(municipio_name, "ü", "u", .)
	replace municipio_name = subinstr(municipio_name, "ñ", "n", .)

	* Spanish accented vowels (uppercase)
	replace municipio_name = subinstr(municipio_name, "Á", "A", .)
	replace municipio_name = subinstr(municipio_name, "É", "E", .)
	replace municipio_name = subinstr(municipio_name, "Í", "I", .)
	replace municipio_name = subinstr(municipio_name, "Ó", "O", .)
	replace municipio_name = subinstr(municipio_name, "Ú", "U", .)
	replace municipio_name = subinstr(municipio_name, "Ü", "U", .)
	replace municipio_name = subinstr(municipio_name, "Ñ", "N", .)

	* Common garbled encodings from PDF extraction (UTF-8 misread as Latin-1, etc.)
	replace municipio_name = subinstr(municipio_name, "Ă", "A", .)
	replace municipio_name = subinstr(municipio_name, "ă", "a", .)
	replace municipio_name = subinstr(municipio_name, "ł", "n", .)
	replace municipio_name = subinstr(municipio_name, "ń", "n", .)
	replace municipio_name = subinstr(municipio_name, "ö", "o", .)
	replace municipio_name = subinstr(municipio_name, "ź", "z", .)
	replace municipio_name = subinstr(municipio_name, "ż", "z", .)
	replace municipio_name = subinstr(municipio_name, "ş", "s", .)
	replace municipio_name = subinstr(municipio_name, "ğ", "g", .)
	replace municipio_name = subinstr(municipio_name, "ı", "i", .)
	replace municipio_name = subinstr(municipio_name, "ą", "A", .)  // garbled Añasco
	replace municipio_name = subinstr(municipio_name, "­", "I", .)  // soft hyphen becoming I for Río Grande

	* STEP 2: Convert to uppercase - eliminates case sensitivity issues
	replace municipio_name = upper(municipio_name)

	* STEP 3: Trim whitespace
	replace municipio_name = strtrim(municipio_name)
	replace municipio_name = stritrim(municipio_name)  // Remove internal multiple spaces

	* STEP 3: Remove "PUERTO RICO" and variants (order matters - longer first)
	replace municipio_name = subinstr(municipio_name, "PUERTO RICO USA", "", .)
	replace municipio_name = subinstr(municipio_name, "PUETO RICO", "", .)
	replace municipio_name = subinstr(municipio_name, "PURETO RICO", "", .)
	replace municipio_name = subinstr(municipio_name, "PUERTO RICO", "", .)
	replace municipio_name = subinstr(municipio_name, "P.R.", "", .)
	replace municipio_name = subinstr(municipio_name, "P. R.", "", .)
	replace municipio_name = subinstr(municipio_name, ", PR", "", .)
	replace municipio_name = subinstr(municipio_name, " PR", "", .)
	replace municipio_name = subinstr(municipio_name, ",PR", "", .)

	* STEP 4: Remove "USA" and variants
	replace municipio_name = subinstr(municipio_name, ", USA", "", .)
	replace municipio_name = subinstr(municipio_name, " USA", "", .)
	replace municipio_name = subinstr(municipio_name, ", U.S.A.", "", .)
	replace municipio_name = subinstr(municipio_name, ", U.S.A", "", .)
	replace municipio_name = subinstr(municipio_name, ", UNITED STATES", "", .)

	* STEP 5: Remove other common suffixes and prefixes
	replace municipio_name = subinstr(municipio_name, " -", "", .)
	replace municipio_name = subinstr(municipio_name, "- ", "", .)
	replace municipio_name = subinstr(municipio_name, ",", " ", .)  // Replace commas with spaces

	* Re-trim after substitutions
	replace municipio_name = strtrim(municipio_name)
	replace municipio_name = stritrim(municipio_name)

	* STEP 6: Fix specific typos and variations (all uppercase now)
	* Dorado variations
	replace municipio_name = "DORADO" if regexm(municipio_name, "^DORADO")
	replace municipio_name = "DORADO" if inlist(municipio_name, "DOADO", "CARIBE")

	* San Juan variations
	replace municipio_name = "SAN JUAN" if regexm(municipio_name, "^SAN ?JUAN")
	replace municipio_name = "SAN JUAN" if inlist(municipio_name, "SANJUAN", "SAN JAUN", "SAB JUAN")
	replace municipio_name = "SAN JUAN" if inlist(municipio_name, "SANTURCE", "CONDADO", "MILFORD SAN JUAN")
	replace municipio_name = "SAN JUAN" if inlist(municipio_name, "AVE SAN JUAN", "SAN JUANP")

	* Humacao variations
	replace municipio_name = "HUMACAO" if regexm(municipio_name, "^HUMACAO")
	replace municipio_name = "HUMACAO" if inlist(municipio_name, "HUMACO", "HUMACOA", "ALMACAO", "UMACAO")
	replace municipio_name = "HUMACAO" if municipio_name == "PALMAS DEL MAR"

	* Rincon variations
	replace municipio_name = "RINCON" if regexm(municipio_name, "^RINCON")
	replace municipio_name = "RINCON" if municipio_name == "RINCANN"  // garbled encoding

	* Guaynabo variations
	replace municipio_name = "GUAYNABO" if regexm(municipio_name, "^GUAYNABO")
	replace municipio_name = "GUAYNABO" if municipio_name == "GUAYANABO"

	* Quebradillas variations
	replace municipio_name = "QUEBRADILLAS" if regexm(municipio_name, "^QUEBRADILLAS")

	* Bayamon variations (handle accented characters that become garbled)
	replace municipio_name = "BAYAMON" if regexm(municipio_name, "^BAYAM")

	* Anasco variations
	replace municipio_name = "ANASCO" if regexm(municipio_name, "^A.ASCO")
	replace municipio_name = "ANASCO" if regexm(municipio_name, "^AA.ASCO")  // AAąASCO garbled encoding
	replace municipio_name = "ANASCO" if inlist(municipio_name, "AIASCO", "AFIASCO", "AAASCO")

	* Mayaguez variations
	replace municipio_name = "MAYAGUEZ" if regexm(municipio_name, "^MAYAG")

	* Rio Grande variations
	replace municipio_name = "RIO GRANDE" if regexm(municipio_name, "^R.O GRANDE")
	replace municipio_name = "RIO GRANDE" if regexm(municipio_name, "^RA.O GRANDE")  // RA­O GRANDE garbled encoding
	replace municipio_name = "RIO GRANDE" if municipio_name == "BAHIA BEACH"

	* Other specific fixes
	replace municipio_name = "CAROLINA" if regexm(municipio_name, "^CAROLINA")
	replace municipio_name = "LOIZA" if municipio_name == "LOZA"
	replace municipio_name = "SAN GERMAN" if regexm(municipio_name, "^SAN GERM")
	replace municipio_name = "ADJUNTAS" if regexm(municipio_name, "^ADJUNTAS")
	replace municipio_name = "COTO LAUREL" if municipio_name == "COTO LAUREL"  // This is in Ponce
	replace municipio_name = "PONCE" if municipio_name == "COTO LAUREL"
	replace municipio_name = "TOA BAJA" if municipio_name == "SABANA SECA"  // Sabana Seca is in Toa Baja
	replace municipio_name = "HUMACAO" if municipio_name == "PALMER"  // Palmer is in Humacao

	* Handle neighborhoods/barrios that should map to municipalities
	replace municipio_name = "SAN JUAN" if municipio_name == "SANTURCE"
	replace municipio_name = "SAN JUAN" if municipio_name == "CONDADO"
	replace municipio_name = "SAN JUAN" if municipio_name == "HATO REY"
	replace municipio_name = "SAN JUAN" if municipio_name == "RIO PIEDRAS"
	replace municipio_name = "HUMACAO" if municipio_name == "PALMAS DEL MAR"
	replace municipio_name = "RIO GRANDE" if municipio_name == "BAHIA BEACH"

	* Additional typos from data inspection
	replace municipio_name = "BOQUERON" if municipio_name == "BOQUERON"  // Boqueron is in Cabo Rojo
	replace municipio_name = "CABO ROJO" if municipio_name == "BOQUERON"
	replace municipio_name = "SAN JUAN" if municipio_name == "ORLANDOFLORIDA"  // Clearly wrong extraction

	* Handle "DORADO BEACH DRIVE DORADO" and similar
	replace municipio_name = "DORADO" if regexm(municipio_name, "DORADO BEACH")
	replace municipio_name = "DORADO" if regexm(municipio_name, "^DORADOPUERTO")  // DORADOPUERTO RIC

	* Handle garbled encoding that shows "FLORIDA" but means Puerto Rico municipality
	* Note: There IS a municipality called Florida in PR - don't change legitimate Florida

	* Fix ORLANDOFLORIDA - this is clearly garbled
	replace municipio_name = "" if municipio_name == "ORLANDOFLORIDA"

	* STEP 7: Final cleanup - remove any trailing numbers (like zip codes)
	replace municipio_name = regexr(municipio_name, " [0-9]+$", "")
	replace municipio_name = strtrim(municipio_name)

	* STEP 8: Flag known US mainland locations as empty (will be dropped or use fallback)
	* These are confirmed US locations, not PR municipalities
	replace municipio_name = "" if inlist(municipio_name, "AUSTIN", "BIRMINGHAM", "BOCA RATON", "BOYNTON BEACH")
	replace municipio_name = "" if inlist(municipio_name, "CHICO", "DURANGO", "DURANGO CO", "HAVERFORD")
	replace municipio_name = "" if inlist(municipio_name, "IRVING", "LA JOLLA", "SANDS POINT", "SEELEY LAKE")
	replace municipio_name = "" if inlist(municipio_name, "TAMPA", "SAN DIEGO")

end

********************************************************************************
* SECTION 1B: DEFINE PROGRAM TO VALIDATE AND FLAG INVALID MUNICIPALITIES
********************************************************************************
* This checks if the municipality is a valid PR municipality (UPPERCASE).
* US mainland locations get flagged for review/dropping.
********************************************************************************

capture program drop validate_pr_municipio
program define validate_pr_municipio
	* Creates valid_pr_muni = 1 if it's a valid Puerto Rico municipality

	* List of all 78 Puerto Rico municipalities (UPPERCASE standardized names)
	gen valid_pr_muni = 0

	* Check against valid list (all UPPERCASE)
	replace valid_pr_muni = 1 if inlist(municipio_name, "ADJUNTAS", "AGUADA", "AGUADILLA", "AGUAS BUENAS", "AIBONITO", "ANASCO", "ARECIBO")
	replace valid_pr_muni = 1 if inlist(municipio_name, "ARROYO", "BARCELONETA", "BARRANQUITAS", "BAYAMON", "CABO ROJO", "CAGUAS", "CAMUY")
	replace valid_pr_muni = 1 if inlist(municipio_name, "CANOVANAS", "CAROLINA", "CATANO", "CAYEY", "CEIBA", "CIALES", "CIDRA")
	replace valid_pr_muni = 1 if inlist(municipio_name, "COAMO", "COMERIO", "COROZAL", "CULEBRA", "DORADO", "FAJARDO", "FLORIDA")
	replace valid_pr_muni = 1 if inlist(municipio_name, "GUANICA", "GUAYAMA", "GUAYANILLA", "GUAYNABO", "GURABO", "HATILLO", "HORMIGUEROS")
	replace valid_pr_muni = 1 if inlist(municipio_name, "HUMACAO", "ISABELA", "JAYUYA", "JUANA DIAZ", "JUNCOS", "LAJAS", "LARES")
	replace valid_pr_muni = 1 if inlist(municipio_name, "LAS MARIAS", "LAS PIEDRAS", "LOIZA", "LUQUILLO", "MANATI", "MARICAO", "MAUNABO")
	replace valid_pr_muni = 1 if inlist(municipio_name, "MAYAGUEZ", "MOCA", "MOROVIS", "NAGUABO", "NARANJITO", "OROCOVIS", "PATILLAS")
	replace valid_pr_muni = 1 if inlist(municipio_name, "PENUELAS", "PONCE", "QUEBRADILLAS", "RINCON", "RIO GRANDE", "SABANA GRANDE", "SALINAS")
	replace valid_pr_muni = 1 if inlist(municipio_name, "SAN GERMAN", "SAN JUAN", "SAN LORENZO", "SAN SEBASTIAN", "SANTA ISABEL", "TOA ALTA", "TOA BAJA")
	replace valid_pr_muni = 1 if inlist(municipio_name, "TRUJILLO ALTO", "UTUADO", "VEGA ALTA", "VEGA BAJA", "VIEQUES", "VILLALBA", "YABUCOA", "YAUCO")

	* Report invalid municipalities
	count if valid_pr_muni == 0
	if r(N) > 0 {
		di "WARNING: Found " r(N) " records with invalid/US mainland municipality names:"
		tab municipio_name if valid_pr_muni == 0, sort
	}

end

********************************************************************************
* SECTION 1C: DEFINE PROGRAM TO EXTRACT BEST PR MUNICIPALITY FROM MULTIPLE VARS
********************************************************************************
* When county shows a US mainland location, the PR municipality might be in
* another variable like real_estate_municipality, mailing_county, etc.
* This program tries multiple sources to find a valid PR municipality.
********************************************************************************

capture program drop extract_best_municipio
program define extract_best_municipio
	args primary_var alt_var1 alt_var2
	* primary_var: first choice (usually county)
	* alt_var1: second choice (usually real_estate_municipality)
	* alt_var2: third choice (usually mailing_county)

	* Start with primary variable
	gen municipio_name = `primary_var'
	standardize_municipio
	validate_pr_municipio

	* If primary is invalid, try alternative 1
	capture confirm variable `alt_var1'
	if _rc == 0 {
		gen temp_muni = `alt_var1' if valid_pr_muni == 0
		replace temp_muni = "" if temp_muni == "NA"
		gen orig_muni = municipio_name if valid_pr_muni == 0
		replace municipio_name = temp_muni if valid_pr_muni == 0 & temp_muni != ""
		drop valid_pr_muni
		standardize_municipio
		validate_pr_municipio

		* Report how many were fixed
		count if valid_pr_muni == 1 & orig_muni != ""
		if r(N) > 0 {
			di "Fixed " r(N) " records using `alt_var1' instead of `primary_var'"
		}
		drop temp_muni orig_muni
	}

	* If still invalid, try alternative 2
	capture confirm variable `alt_var2'
	if _rc == 0 {
		gen temp_muni = `alt_var2' if valid_pr_muni == 0
		replace temp_muni = "" if temp_muni == "NA"
		gen orig_muni = municipio_name if valid_pr_muni == 0
		replace municipio_name = temp_muni if valid_pr_muni == 0 & temp_muni != ""
		drop valid_pr_muni
		standardize_municipio
		validate_pr_municipio

		* Report how many were fixed
		count if valid_pr_muni == 1 & orig_muni != ""
		if r(N) > 0 {
			di "Fixed " r(N) " records using `alt_var2'"
		}
		drop temp_muni orig_muni
	}

	* Final report
	count if valid_pr_muni == 0
	if r(N) > 0 {
		di " "
		di "FINAL: " r(N) " records still have invalid municipality after trying all sources:"
		tab municipio_name if valid_pr_muni == 0, sort
	}

end

********************************************************************************
* SECTION 2: IMPORT AND CLEAN 2015-2018 DATA (HAS UNIQUE IDs)
********************************************************************************

di " "
di "========================================"
di "IMPORTING 2015-2018 DATA"
di "========================================"

import delimited "$RawDataPath/Act22AnnualReports2015-2018.csv", ///
	varnames(1) clear stringcols(_all)

local n_initial_1518 = _N
di "Initial 2015-2018 records: `n_initial_1518'"

* Extract municipality - try multiple sources
* Primary: sworn_statement_city_and_country (most reliable for this file per original code)
* Fallback 1: county
* Fallback 2: real_estate_municipality

* Start with sworn_statement_city_and_country (as in original code)
gen municipio_name = sworn_statement_city_and_country
standardize_municipio
validate_pr_municipio

* If invalid, try county
gen temp_muni = county if valid_pr_muni == 0
replace temp_muni = "" if temp_muni == "NA"
replace municipio_name = temp_muni if valid_pr_muni == 0 & temp_muni != ""
drop valid_pr_muni temp_muni
standardize_municipio
validate_pr_municipio

* If still invalid, try real_estate_municipality
capture confirm variable real_estate_municipality
if _rc == 0 {
	gen temp_muni = real_estate_municipality if valid_pr_muni == 0
	replace temp_muni = "" if temp_muni == "NA"
	replace municipio_name = temp_muni if valid_pr_muni == 0 & temp_muni != ""
	drop temp_muni
	drop valid_pr_muni
	standardize_municipio
	validate_pr_municipio
}

* Apply ID-based manual corrections from original code (all UPPERCASE)
replace municipio_name = "HUMACAO" if id == "12-22-S-009"
replace municipio_name = "SAN JUAN" if id == "16-22-S-153"
replace municipio_name = "SAN JUAN" if id == "14-22-S-324"
replace municipio_name = "HUMACAO" if id == "15-22-S-265"
replace municipio_name = "SAN JUAN" if id == "13-22-S-128"
replace municipio_name = "GUAYNABO" if id == "14-22-S-151"
replace municipio_name = "SAN JUAN" if id == "14-22-S-219"
replace municipio_name = "SAN JUAN" if id == "15-22-S-193"
replace municipio_name = "SAN JUAN" if id == "14-22-S-039"
replace municipio_name = "CAROLINA" if id == "14-22-S-099"
replace municipio_name = "DORADO" if id == "14-22-S-130"
replace municipio_name = "DORADO" if id == "14-22-S-032"
replace municipio_name = "DORADO" if id == "14-22-S-055"
replace municipio_name = "DORADO" if id == "15-22-S-005"
replace municipio_name = "HUMACAO" if id == "15-22-S-011"
replace municipio_name = "DORADO" if id == "15-22-S-050"
replace municipio_name = "ANASCO" if id == "15-22-S-233"
replace municipio_name = "ANASCO" if id == "15-22-S-234"
replace municipio_name = "GUAYNABO" if id == "16-22-S-057"
replace municipio_name = "SAN JUAN" if id == "14-22-S-286"
replace municipio_name = "SAN JUAN" if id == "15-22-S-133"
replace municipio_name = "SAN JUAN" if id == "14-22-S-321"
replace municipio_name = "SAN JUAN" if id == "14-22-S-136"
replace municipio_name = "SAN JUAN" if id == "14-22-S-137"
replace municipio_name = "SAN JUAN" if id == "14-22-S-315"
replace municipio_name = "SAN JUAN" if id == "14-22-S-316"
replace municipio_name = "SAN JUAN" if id == "14-22-S-067"
replace municipio_name = "HUMACAO" if id == "14-22-S-161"
replace municipio_name = "SAN JUAN" if id == "13-22-S-108"
replace municipio_name = "VEGA ALTA" if id == "15-22-S-027"
replace municipio_name = "SAN JUAN" if id == "13-22-S-023"
replace municipio_name = "SAN JUAN" if id == "14-22-S-110"
replace municipio_name = "SAN JUAN" if id == "15-22-S-063"
replace municipio_name = "PONCE" if id == "13-22-S-109"
replace municipio_name = "RIO GRANDE" if id == "15-22-S-155"
replace municipio_name = "HUMACAO" if id == "15-22-S-184"
replace municipio_name = "SAN JUAN" if id == "14-22-S-037"
replace municipio_name = "HUMACAO" if id == "15-22-S-045"
replace municipio_name = "HUMACAO" if id == "14-22-S-300"
replace municipio_name = "SAN JUAN" if id == "14-22-S-150"
replace municipio_name = "SAN JUAN" if id == "16-22-S-159"
replace municipio_name = "SAN JUAN" if id == "16-22-S-182"
replace municipio_name = "SAN JUAN" if id == "14-22-S-001"
replace municipio_name = "SAN JUAN" if id == "14-22-S-075"
replace municipio_name = "SAN JUAN" if id == "14-22-S-337"
replace municipio_name = "SAN JUAN" if id == "15-22-S-025"
replace municipio_name = "SAN JUAN" if id == "15-22-S-026"
replace municipio_name = "CAROLINA" if id == "15-22-S-256"
replace municipio_name = "DORADO" if id == "16-22-S-179"
replace municipio_name = "DORADO" if id == "16-22-S-323"
replace municipio_name = "DORADO" if id == "16-22-S-107"
replace municipio_name = "DORADO" if id == "12-22-S-006"
replace municipio_name = "SAN JUAN" if id == "13-22-S-054"
replace municipio_name = "DORADO" if id == "13-22-S-119"
replace municipio_name = "DORADO" if id == "13-22-S-132"
replace municipio_name = "DORADO" if id == "13-22-S-136"
replace municipio_name = "DORADO" if id == "14-22-S-141"
replace municipio_name = "DORADO" if id == "15-22-S-270"
replace municipio_name = "SAN JUAN" if id == "14-22-S-081"
replace municipio_name = "SAN JUAN" if id == "14-22-S-126"
replace municipio_name = "GUAYNABO" if id == "14-22-S-271"
replace municipio_name = "DORADO" if id == "16-22-S-036"
replace municipio_name = "DORADO" if id == "13-22-S-062"
replace municipio_name = "RIO GRANDE" if id == "14-22-S-023"
replace municipio_name = "RIO GRANDE" if id == "14-22-S-022"
replace municipio_name = "DORADO" if id == "14-22-S-025"
replace municipio_name = "DORADO" if id == "16-22-S-324"

* Re-run validation after manual corrections
drop valid_pr_muni
validate_pr_municipio

* Drop records with REDACTED or NA municipalities (can't match anyway)
drop if municipio_name == "REDACTED" | municipio_name == "NA" | municipio_name == ""

* Final count
di "After municipality cleaning, remaining records: " _N

* Rename and convert asset variables
rename asset_type_financial_previous_re financial_wealth_pre
rename asset_type_real_estate_previous_ real_estate_wealth_pre
rename asset_type_privately_held_busine business_wealth_pre
rename asset_type_other_previous_report other_wealth_pre

rename asset_type_financial_current_rep financial_wealth
rename asset_type_real_estate_current_r real_estate_wealth
capture rename v40 business_wealth
capture rename asset_type_privately_held_busin business_wealth
rename asset_type_other_current_reporti other_wealth

* Year variables
destring current_reporting_year previous_reporting_year, replace force
rename current_reporting_year report_year
rename previous_reporting_year match_year

* Convert assets to numeric and track missing values
foreach var in financial_wealth_pre real_estate_wealth_pre business_wealth_pre other_wealth_pre ///
               financial_wealth real_estate_wealth business_wealth other_wealth {
	destring `var', replace force
}

* Rename for consistency
rename financial_wealth fin_cur
rename real_estate_wealth re_cur
rename business_wealth bus_cur
rename other_wealth oth_cur
rename financial_wealth_pre fin_pre
rename real_estate_wealth_pre re_pre
rename business_wealth_pre bus_pre
rename other_wealth_pre oth_pre

* Create missing flags and replace missing with 0
foreach var in fin_pre re_pre bus_pre oth_pre fin_cur re_cur bus_cur oth_cur {
	gen `var'_missing = (`var' == .)
	replace `var' = 0 if `var' == .
	replace `var' = round(`var')
}

* Handle duplicates - keep first per id-year
sort id report_year
bysort id report_year: keep if _n == 1

* Handle decree_year variable
capture confirm variable decree_year
if _rc != 0 {
	gen decree_year = .
}
else {
	destring decree_year, replace force
}

* Keep key variables
keep id filename municipio_name report_year match_year decree_year ///
	fin_pre re_pre bus_pre oth_pre fin_cur re_cur bus_cur oth_cur ///
	fin_pre_missing re_pre_missing bus_pre_missing oth_pre_missing ///
	fin_cur_missing re_cur_missing bus_cur_missing oth_cur_missing

gen source_file = "2015-2018"

local n_final_1518 = _N
di "Final 2015-2018 records: `n_final_1518'"

save "$CleanDataPath/clean_2015_2018.dta", replace

********************************************************************************
* SECTION 3: IMPORT AND CLEAN 2019+ DATA (NO UNIQUE IDs)
********************************************************************************
* Each file is imported, cleaned, and saved separately.
* Common structure: filename, county (municipality), asset variables
********************************************************************************

*------------------------------------------------------------------------------
* 3.1: IMPORT 2019 DATA
*------------------------------------------------------------------------------
di " "
di "========================================"
di "IMPORTING 2019 DATA"
di "========================================"

import delimited "$RawDataPath/Act22AnnualReports2019.csv", ///
	varnames(1) clear stringcols(_all)

local n_2019 = _N
di "2019 records: `n_2019'"

* Municipality extraction - try multiple sources
* Primary: county
* Fallback 1: real_estate_municipality
* Fallback 2: mailing_county

gen municipio_name = county
standardize_municipio
validate_pr_municipio

* If invalid, try real_estate_municipality
capture confirm variable real_estate_municipality
if _rc == 0 {
	gen temp_muni = real_estate_municipality if valid_pr_muni == 0
	replace temp_muni = "" if temp_muni == "NA"
	replace municipio_name = temp_muni if valid_pr_muni == 0 & temp_muni != ""
	drop temp_muni valid_pr_muni
	standardize_municipio
	validate_pr_municipio
}

* If still invalid, try mailing_county
capture confirm variable mailing_county
if _rc == 0 {
	gen temp_muni = mailing_county if valid_pr_muni == 0
	replace temp_muni = "" if temp_muni == "NA"
	replace municipio_name = temp_muni if valid_pr_muni == 0 & temp_muni != ""
	drop temp_muni valid_pr_muni
	standardize_municipio
	validate_pr_municipio
}

* Manual corrections from original code for known mainland US locations
* These were manually verified to have correct PR municipality from other data
replace municipio_name = "SAN JUAN" if inlist(upper(county), "DALLAS", "NEWBURY PARK", "AUSTIN")
replace municipio_name = "SAN JUAN" if inlist(upper(county), "IRON STATION", "MIAMI", "NEW YORK, NY")
replace municipio_name = "GUAYNABO" if upper(county) == "KEY LARGO"
replace municipio_name = "CAROLINA" if inlist(upper(county), "QUEENS", "WESTON")
replace municipio_name = "HUMACAO" if inlist(upper(county), "REDONDO BEACH", "CARY", "URBANDALE")
replace municipio_name = "DORADO" if inlist(upper(county), "CHICAGO", "FALLBROOK")
replace municipio_name = "CAROLINA" if filename == "2020-RepAct22-001283_Redacted.pdf"

* Drop records we can't reliably identify
drop if inlist(upper(county), "26", "HILLSBOROUGH", "LAS VEGAS", "LOGANVILLE")
drop if municipio_name == "REDACTED" | municipio_name == ""

* Re-validate after corrections
drop valid_pr_muni
validate_pr_municipio

di "After municipality cleaning: " _N " records"

* Year variables
destring current_reporting_year previous_reporting_year, replace force
rename current_reporting_year report_year
rename previous_reporting_year match_year

* Asset variables - use capture to handle variable name truncation variations
* Note: business_wealth_cur gets truncated to v41 for 2019, 2020, 2021, 2022_format19
capture rename asset_type_financial_previous_re fin_pre
capture rename asset_type_financial_previous_rep fin_pre
capture rename asset_type_financial_current_rep fin_cur
capture rename asset_type_financial_current_repo fin_cur
capture rename asset_type_real_estate_previous_ re_pre
capture rename asset_type_real_estate_previous_r re_pre
capture rename asset_type_real_estate_current_r re_cur
capture rename asset_type_real_estate_current_re re_cur
capture rename asset_type_privately_held_busine bus_pre
capture rename asset_type_privately_held_business_pre bus_pre
capture rename v41 bus_cur
capture rename asset_type_privately_held_busin bus_cur
capture rename asset_type_privately_held_business_cur bus_cur
capture rename asset_type_other_previous_report oth_pre
capture rename asset_type_other_previous_reporti oth_pre
capture rename asset_type_other_current_reporti oth_cur
capture rename asset_type_other_current_reporting oth_cur

* Track which variables are real vs imputed (missing from source)
foreach var in fin_pre fin_cur re_pre re_cur bus_pre bus_cur oth_pre oth_cur {
	capture confirm variable `var'
	if _rc != 0 {
		di "WARNING: Variable `var' not found, creating with missing flag"
		gen `var' = .
		gen `var'_missing = 1
	}
	else {
		gen `var'_missing = 0
		destring `var', replace force
		replace `var'_missing = 1 if `var' == .
		replace `var' = 0 if `var' == .
		replace `var' = round(`var')
	}
}

gen id = ""
gen source_file = "2019"

* 2019 doesn't have decree_year
gen decree_year = .

keep id filename municipio_name report_year match_year decree_year ///
	fin_pre re_pre bus_pre oth_pre fin_cur re_cur bus_cur oth_cur ///
	fin_pre_missing re_pre_missing bus_pre_missing oth_pre_missing ///
	fin_cur_missing re_cur_missing bus_cur_missing oth_cur_missing source_file

save "$CleanDataPath/clean_2019.dta", replace

*------------------------------------------------------------------------------
* 3.2: IMPORT 2020 DATA
*------------------------------------------------------------------------------
di " "
di "========================================"
di "IMPORTING 2020 DATA"
di "========================================"

import delimited "$RawDataPath/Act22AnnualReports2020.csv", ///
	varnames(1) clear stringcols(_all)

local n_2020 = _N
di "2020 records: `n_2020'"

* Municipality extraction - try multiple sources
gen municipio_name = county
standardize_municipio
validate_pr_municipio

* If invalid, try real_estate_municipality
capture confirm variable real_estate_municipality
if _rc == 0 {
	gen temp_muni = real_estate_municipality if valid_pr_muni == 0
	replace temp_muni = "" if temp_muni == "NA"
	replace municipio_name = temp_muni if valid_pr_muni == 0 & temp_muni != ""
	drop temp_muni valid_pr_muni
	standardize_municipio
	validate_pr_municipio
}

* If still invalid, try mailing_county
capture confirm variable mailing_county
if _rc == 0 {
	gen temp_muni = mailing_county if valid_pr_muni == 0
	replace temp_muni = "" if temp_muni == "NA"
	replace municipio_name = temp_muni if valid_pr_muni == 0 & temp_muni != ""
	drop temp_muni valid_pr_muni
	standardize_municipio
	validate_pr_municipio
}

* Manual corrections for known US mainland locations
replace municipio_name = "SAN JUAN" if inlist(upper(county), "DALLAS", "NEWBURY PARK", "AUSTIN")
replace municipio_name = "SAN JUAN" if inlist(upper(county), "IRON STATION", "MIAMI")
replace municipio_name = "GUAYNABO" if upper(county) == "KEY LARGO"
replace municipio_name = "CAROLINA" if inlist(upper(county), "QUEENS", "WESTON")
replace municipio_name = "HUMACAO" if inlist(upper(county), "REDONDO BEACH", "CARY", "URBANDALE")
replace municipio_name = "DORADO" if inlist(upper(county), "CHICAGO", "FALLBROOK")

* Drop records we can't reliably identify
drop if inlist(upper(county), "26", "HILLSBOROUGH", "LAS VEGAS", "LOGANVILLE")
drop if municipio_name == "REDACTED" | municipio_name == ""

drop valid_pr_muni
di "After municipality cleaning: " _N " records"

destring current_reporting_year previous_reporting_year, replace force
rename current_reporting_year report_year
rename previous_reporting_year match_year

* Asset variables - use capture to handle variable name truncation variations
* Note: business_wealth_cur gets truncated to v41 for 2019, 2020, 2021, 2022_format19
capture rename asset_type_financial_previous_re fin_pre
capture rename asset_type_financial_previous_rep fin_pre
capture rename asset_type_financial_current_rep fin_cur
capture rename asset_type_financial_current_repo fin_cur
capture rename asset_type_real_estate_previous_ re_pre
capture rename asset_type_real_estate_previous_r re_pre
capture rename asset_type_real_estate_current_r re_cur
capture rename asset_type_real_estate_current_re re_cur
capture rename asset_type_privately_held_busine bus_pre
capture rename asset_type_privately_held_business_pre bus_pre
capture rename v41 bus_cur
capture rename asset_type_privately_held_busin bus_cur
capture rename asset_type_privately_held_business_cur bus_cur
capture rename asset_type_other_previous_report oth_pre
capture rename asset_type_other_previous_reporti oth_pre
capture rename asset_type_other_current_reporti oth_cur
capture rename asset_type_other_current_reporting oth_cur

* Track which variables are real vs imputed (missing from source)
foreach var in fin_pre fin_cur re_pre re_cur bus_pre bus_cur oth_pre oth_cur {
	capture confirm variable `var'
	if _rc != 0 {
		di "WARNING: Variable `var' not found, creating with missing flag"
		gen `var' = .
		gen `var'_missing = 1
	}
	else {
		gen `var'_missing = 0
		destring `var', replace force
		replace `var'_missing = 1 if `var' == .
		replace `var' = 0 if `var' == .
		replace `var' = round(`var')
	}
}

gen id = ""
gen source_file = "2020"

* 2020 doesn't have decree_year
gen decree_year = .

keep id filename municipio_name report_year match_year decree_year ///
	fin_pre re_pre bus_pre oth_pre fin_cur re_cur bus_cur oth_cur ///
	fin_pre_missing re_pre_missing bus_pre_missing oth_pre_missing ///
	fin_cur_missing re_cur_missing bus_cur_missing oth_cur_missing source_file

save "$CleanDataPath/clean_2020.dta", replace

*------------------------------------------------------------------------------
* 3.3: IMPORT 2021 DATA
*------------------------------------------------------------------------------
di " "
di "========================================"
di "IMPORTING 2021 DATA"
di "========================================"

import delimited "$RawDataPath/Act22AnnualReports2021.csv", ///
	varnames(1) clear stringcols(_all)

local n_2021 = _N
di "2021 records: `n_2021'"

* Municipality extraction - try multiple sources
gen municipio_name = county
standardize_municipio
validate_pr_municipio

* If invalid, try real_estate_municipality
capture confirm variable real_estate_municipality
if _rc == 0 {
	gen temp_muni = real_estate_municipality if valid_pr_muni == 0
	replace temp_muni = "" if temp_muni == "NA"
	replace municipio_name = temp_muni if valid_pr_muni == 0 & temp_muni != ""
	drop temp_muni valid_pr_muni
	standardize_municipio
	validate_pr_municipio
}

* If still invalid, try mailing_county
capture confirm variable mailing_county
if _rc == 0 {
	gen temp_muni = mailing_county if valid_pr_muni == 0
	replace temp_muni = "" if temp_muni == "NA"
	replace municipio_name = temp_muni if valid_pr_muni == 0 & temp_muni != ""
	drop temp_muni valid_pr_muni
	standardize_municipio
	validate_pr_municipio
}

* Manual corrections for known US mainland locations
replace municipio_name = "SAN JUAN" if inlist(upper(county), "DALLAS", "NEWBURY PARK", "AUSTIN")
replace municipio_name = "SAN JUAN" if inlist(upper(county), "IRON STATION", "MIAMI")
replace municipio_name = "GUAYNABO" if upper(county) == "KEY LARGO"
replace municipio_name = "CAROLINA" if inlist(upper(county), "QUEENS", "WESTON")
replace municipio_name = "HUMACAO" if inlist(upper(county), "REDONDO BEACH", "CARY", "URBANDALE")
replace municipio_name = "DORADO" if inlist(upper(county), "CHICAGO", "FALLBROOK")

* Drop records we can't reliably identify
drop if inlist(upper(county), "26", "HILLSBOROUGH", "LAS VEGAS", "LOGANVILLE")
drop if municipio_name == "REDACTED" | municipio_name == ""

drop valid_pr_muni
di "After municipality cleaning: " _N " records"

destring current_reporting_year previous_reporting_year, replace force
rename current_reporting_year report_year
rename previous_reporting_year match_year

* Asset variables - use capture to handle variable name truncation variations
* Note: business_wealth_cur gets truncated to v41 for 2019, 2020, 2021, 2022_format19
capture rename asset_type_financial_previous_re fin_pre
capture rename asset_type_financial_previous_rep fin_pre
capture rename asset_type_financial_current_rep fin_cur
capture rename asset_type_financial_current_repo fin_cur
capture rename asset_type_real_estate_previous_ re_pre
capture rename asset_type_real_estate_previous_r re_pre
capture rename asset_type_real_estate_current_r re_cur
capture rename asset_type_real_estate_current_re re_cur
capture rename asset_type_privately_held_busine bus_pre
capture rename asset_type_privately_held_business_pre bus_pre
capture rename v41 bus_cur
capture rename asset_type_privately_held_busin bus_cur
capture rename asset_type_privately_held_business_cur bus_cur
capture rename asset_type_other_previous_report oth_pre
capture rename asset_type_other_previous_reporti oth_pre
capture rename asset_type_other_current_reporti oth_cur
capture rename asset_type_other_current_reporting oth_cur

* Track which variables are real vs imputed (missing from source)
foreach var in fin_pre fin_cur re_pre re_cur bus_pre bus_cur oth_pre oth_cur {
	capture confirm variable `var'
	if _rc != 0 {
		di "WARNING: Variable `var' not found, creating with missing flag"
		gen `var' = .
		gen `var'_missing = 1
	}
	else {
		gen `var'_missing = 0
		destring `var', replace force
		replace `var'_missing = 1 if `var' == .
		replace `var' = 0 if `var' == .
		replace `var' = round(`var')
	}
}

gen id = ""
gen source_file = "2021"

* 2021 doesn't have decree_year
gen decree_year = .

keep id filename municipio_name report_year match_year decree_year ///
	fin_pre re_pre bus_pre oth_pre fin_cur re_cur bus_cur oth_cur ///
	fin_pre_missing re_pre_missing bus_pre_missing oth_pre_missing ///
	fin_cur_missing re_cur_missing bus_cur_missing oth_cur_missing source_file

save "$CleanDataPath/clean_2021.dta", replace

*------------------------------------------------------------------------------
* 3.4: IMPORT 2022 DATA (format19 - old form)
*------------------------------------------------------------------------------
di " "
di "========================================"
di "IMPORTING 2022 DATA (format19)"
di "========================================"

import delimited "$RawDataPath/Act22AnnualReports2022_format19.csv", ///
	varnames(1) clear stringcols(_all)

local n_2022a = _N
di "2022 format19 records: `n_2022a'"

* Municipality extraction - try multiple sources
gen municipio_name = county
standardize_municipio
validate_pr_municipio

* If invalid, try real_estate_municipality
capture confirm variable real_estate_municipality
if _rc == 0 {
	gen temp_muni = real_estate_municipality if valid_pr_muni == 0
	replace temp_muni = "" if temp_muni == "NA"
	replace municipio_name = temp_muni if valid_pr_muni == 0 & temp_muni != ""
	drop temp_muni valid_pr_muni
	standardize_municipio
	validate_pr_municipio
}

* If still invalid, try mailing_county
capture confirm variable mailing_county
if _rc == 0 {
	gen temp_muni = mailing_county if valid_pr_muni == 0
	replace temp_muni = "" if temp_muni == "NA"
	replace municipio_name = temp_muni if valid_pr_muni == 0 & temp_muni != ""
	drop temp_muni valid_pr_muni
	standardize_municipio
	validate_pr_municipio
}

* Manual corrections for known US mainland locations
replace municipio_name = "SAN JUAN" if inlist(upper(county), "DALLAS", "NEWBURY PARK", "AUSTIN")
replace municipio_name = "SAN JUAN" if inlist(upper(county), "IRON STATION", "MIAMI")
replace municipio_name = "GUAYNABO" if upper(county) == "KEY LARGO"
replace municipio_name = "CAROLINA" if inlist(upper(county), "QUEENS", "WESTON")
replace municipio_name = "HUMACAO" if inlist(upper(county), "REDONDO BEACH", "CARY", "URBANDALE")
replace municipio_name = "DORADO" if inlist(upper(county), "CHICAGO", "FALLBROOK")

* Drop records we can't reliably identify
drop if inlist(upper(county), "26", "HILLSBOROUGH", "LAS VEGAS", "LOGANVILLE")
drop if municipio_name == "REDACTED" | municipio_name == "" | municipio_name == "NA"

drop valid_pr_muni
di "After municipality cleaning: " _N " records"

destring current_reporting_year previous_reporting_year, replace force
rename current_reporting_year report_year
rename previous_reporting_year match_year

* Asset variables - use capture to handle variable name truncation variations
* Note: business_wealth_cur gets truncated to v41 for 2019, 2020, 2021, 2022_format19
capture rename asset_type_financial_previous_re fin_pre
capture rename asset_type_financial_previous_rep fin_pre
capture rename asset_type_financial_current_rep fin_cur
capture rename asset_type_financial_current_repo fin_cur
capture rename asset_type_real_estate_previous_ re_pre
capture rename asset_type_real_estate_previous_r re_pre
capture rename asset_type_real_estate_current_r re_cur
capture rename asset_type_real_estate_current_re re_cur
capture rename asset_type_privately_held_busine bus_pre
capture rename asset_type_privately_held_business_pre bus_pre
capture rename v41 bus_cur
capture rename asset_type_privately_held_busin bus_cur
capture rename asset_type_privately_held_business_cur bus_cur
capture rename asset_type_other_previous_report oth_pre
capture rename asset_type_other_previous_reporti oth_pre
capture rename asset_type_other_current_reporti oth_cur
capture rename asset_type_other_current_reporting oth_cur

* Track which variables are real vs imputed (missing from source)
foreach var in fin_pre fin_cur re_pre re_cur bus_pre bus_cur oth_pre oth_cur {
	capture confirm variable `var'
	if _rc != 0 {
		di "WARNING: Variable `var' not found, creating with missing flag"
		gen `var' = .
		gen `var'_missing = 1
	}
	else {
		gen `var'_missing = 0
		destring `var', replace force
		replace `var'_missing = 1 if `var' == .
		replace `var' = 0 if `var' == .
		replace `var' = round(`var')
	}
}

gen id = ""
gen source_file = "2022_format19"

* 2022_format19 doesn't have decree_year (old form)
gen decree_year = .

keep id filename municipio_name report_year match_year decree_year ///
	fin_pre re_pre bus_pre oth_pre fin_cur re_cur bus_cur oth_cur ///
	fin_pre_missing re_pre_missing bus_pre_missing oth_pre_missing ///
	fin_cur_missing re_cur_missing bus_cur_missing oth_cur_missing source_file

save "$CleanDataPath/clean_2022_format19.dta", replace

*------------------------------------------------------------------------------
* 3.5: IMPORT 2022 DATA (format22 - new form)
*------------------------------------------------------------------------------
di " "
di "========================================"
di "IMPORTING 2022 DATA (format22)"
di "========================================"

import delimited "$RawDataPath/Act22AnnualReports2022_format22.csv", ///
	varnames(1) clear stringcols(_all)

local n_2022b = _N
di "2022 format22 records: `n_2022b'"

* Municipality extraction - try multiple sources
gen municipio_name = county
standardize_municipio
validate_pr_municipio

* If invalid, try real_estate_municipality
capture confirm variable real_estate_municipality
if _rc == 0 {
	gen temp_muni = real_estate_municipality if valid_pr_muni == 0
	replace temp_muni = "" if temp_muni == "NA"
	replace municipio_name = temp_muni if valid_pr_muni == 0 & temp_muni != ""
	drop temp_muni valid_pr_muni
	standardize_municipio
	validate_pr_municipio
}

* If still invalid, try mailing_county
capture confirm variable mailing_county
if _rc == 0 {
	gen temp_muni = mailing_county if valid_pr_muni == 0
	replace temp_muni = "" if temp_muni == "NA"
	replace municipio_name = temp_muni if valid_pr_muni == 0 & temp_muni != ""
	drop temp_muni valid_pr_muni
	standardize_municipio
	validate_pr_municipio
}

* Manual corrections for known US mainland locations
replace municipio_name = "SAN JUAN" if inlist(upper(county), "DALLAS", "NEWBURY PARK", "AUSTIN")
replace municipio_name = "SAN JUAN" if inlist(upper(county), "IRON STATION", "MIAMI")
replace municipio_name = "GUAYNABO" if upper(county) == "KEY LARGO"
replace municipio_name = "CAROLINA" if inlist(upper(county), "QUEENS", "WESTON")
replace municipio_name = "HUMACAO" if inlist(upper(county), "REDONDO BEACH", "CARY", "URBANDALE")
replace municipio_name = "DORADO" if inlist(upper(county), "CHICAGO", "FALLBROOK")

* Drop records we can't reliably identify
drop if inlist(upper(county), "26", "HILLSBOROUGH", "LAS VEGAS", "LOGANVILLE")
drop if municipio_name == "REDACTED" | municipio_name == "" | municipio_name == "NA"

drop valid_pr_muni
di "After municipality cleaning: " _N " records"

destring current_reporting_year previous_reporting_year, replace force
rename current_reporting_year report_year
rename previous_reporting_year match_year

* Asset variables - use capture to handle variable name truncation variations
* Note: business_wealth_cur gets truncated to v42 for 2022_format22 and 2023
capture rename asset_type_financial_previous_re fin_pre
capture rename asset_type_financial_previous_rep fin_pre
capture rename asset_type_financial_current_rep fin_cur
capture rename asset_type_financial_current_repo fin_cur
capture rename asset_type_real_estate_previous_ re_pre
capture rename asset_type_real_estate_previous_r re_pre
capture rename asset_type_real_estate_current_r re_cur
capture rename asset_type_real_estate_current_re re_cur
capture rename asset_type_privately_held_busine bus_pre
capture rename asset_type_privately_held_business_pre bus_pre
capture rename v42 bus_cur
capture rename asset_type_privately_held_busin bus_cur
capture rename asset_type_privately_held_business_cur bus_cur
capture rename asset_type_other_previous_report oth_pre
capture rename asset_type_other_previous_reporti oth_pre
capture rename asset_type_other_current_reporti oth_cur
capture rename asset_type_other_current_reporting oth_cur

* Track which variables are real vs imputed (missing from source)
foreach var in fin_pre fin_cur re_pre re_cur bus_pre bus_cur oth_pre oth_cur {
	capture confirm variable `var'
	if _rc != 0 {
		di "WARNING: Variable `var' not found, creating with missing flag"
		gen `var' = .
		gen `var'_missing = 1
	}
	else {
		gen `var'_missing = 0
		destring `var', replace force
		replace `var'_missing = 1 if `var' == .
		replace `var' = 0 if `var' == .
		replace `var' = round(`var')
	}
}

gen id = ""
gen source_file = "2022_format22"

* Handle decree_year variable (2022_format22 has it)
capture confirm variable decree_year
if _rc != 0 {
	gen decree_year = .
}
else {
	destring decree_year, replace force
}

keep id filename municipio_name report_year match_year decree_year ///
	fin_pre re_pre bus_pre oth_pre fin_cur re_cur bus_cur oth_cur ///
	fin_pre_missing re_pre_missing bus_pre_missing oth_pre_missing ///
	fin_cur_missing re_cur_missing bus_cur_missing oth_cur_missing source_file

save "$CleanDataPath/clean_2022_format22.dta", replace

*------------------------------------------------------------------------------
* 3.6: IMPORT 2023 DATA
*------------------------------------------------------------------------------
di " "
di "========================================"
di "IMPORTING 2023 DATA"
di "========================================"

import delimited "$RawDataPath/Act22AnnualReports2023.csv", ///
	varnames(1) clear stringcols(_all)

local n_2023 = _N
di "2023 records: `n_2023'"

* Municipality extraction - try multiple sources
gen municipio_name = county
standardize_municipio
validate_pr_municipio

* If invalid, try real_estate_municipality
capture confirm variable real_estate_municipality
if _rc == 0 {
	gen temp_muni = real_estate_municipality if valid_pr_muni == 0
	replace temp_muni = "" if temp_muni == "NA"
	replace municipio_name = temp_muni if valid_pr_muni == 0 & temp_muni != ""
	drop temp_muni valid_pr_muni
	standardize_municipio
	validate_pr_municipio
}

* If still invalid, try mailing_county
capture confirm variable mailing_county
if _rc == 0 {
	gen temp_muni = mailing_county if valid_pr_muni == 0
	replace temp_muni = "" if temp_muni == "NA"
	replace municipio_name = temp_muni if valid_pr_muni == 0 & temp_muni != ""
	drop temp_muni valid_pr_muni
	standardize_municipio
	validate_pr_municipio
}

* Manual corrections for known US mainland locations
replace municipio_name = "SAN JUAN" if inlist(upper(county), "DALLAS", "NEWBURY PARK", "AUSTIN")
replace municipio_name = "SAN JUAN" if inlist(upper(county), "IRON STATION", "MIAMI")
replace municipio_name = "GUAYNABO" if upper(county) == "KEY LARGO"
replace municipio_name = "CAROLINA" if inlist(upper(county), "QUEENS", "WESTON")
replace municipio_name = "HUMACAO" if inlist(upper(county), "REDONDO BEACH", "CARY", "URBANDALE")
replace municipio_name = "DORADO" if inlist(upper(county), "CHICAGO", "FALLBROOK")

* Drop records we can't reliably identify
drop if inlist(upper(county), "26", "HILLSBOROUGH", "LAS VEGAS", "LOGANVILLE")
drop if municipio_name == "REDACTED" | municipio_name == "" | municipio_name == "NA"

drop valid_pr_muni
di "After municipality cleaning: " _N " records"

destring current_reporting_year previous_reporting_year, replace force
rename current_reporting_year report_year
rename previous_reporting_year match_year

* Asset variables - use capture to handle variable name truncation variations
* Note: business_wealth_cur gets truncated to v42 for 2022_format22 and 2023
capture rename asset_type_financial_previous_re fin_pre
capture rename asset_type_financial_previous_rep fin_pre
capture rename asset_type_financial_current_rep fin_cur
capture rename asset_type_financial_current_repo fin_cur
capture rename asset_type_real_estate_previous_ re_pre
capture rename asset_type_real_estate_previous_r re_pre
capture rename asset_type_real_estate_current_r re_cur
capture rename asset_type_real_estate_current_re re_cur
capture rename asset_type_privately_held_busine bus_pre
capture rename asset_type_privately_held_business_pre bus_pre
capture rename v42 bus_cur
capture rename asset_type_privately_held_busin bus_cur
capture rename asset_type_privately_held_business_cur bus_cur
capture rename asset_type_other_previous_report oth_pre
capture rename asset_type_other_previous_reporti oth_pre
capture rename asset_type_other_current_reporti oth_cur
capture rename asset_type_other_current_reporting oth_cur

* Track which variables are real vs imputed (missing from source)
foreach var in fin_pre fin_cur re_pre re_cur bus_pre bus_cur oth_pre oth_cur {
	capture confirm variable `var'
	if _rc != 0 {
		di "WARNING: Variable `var' not found, creating with missing flag"
		gen `var' = .
		gen `var'_missing = 1
	}
	else {
		gen `var'_missing = 0
		destring `var', replace force
		replace `var'_missing = 1 if `var' == .
		replace `var' = 0 if `var' == .
		replace `var' = round(`var')
	}
}

gen id = ""
gen source_file = "2023"

* Handle decree_year variable (2023 has it)
capture confirm variable decree_year
if _rc != 0 {
	gen decree_year = .
}
else {
	destring decree_year, replace force
}

keep id filename municipio_name report_year match_year decree_year ///
	fin_pre re_pre bus_pre oth_pre fin_cur re_cur bus_cur oth_cur ///
	fin_pre_missing re_pre_missing bus_pre_missing oth_pre_missing ///
	fin_cur_missing re_cur_missing bus_cur_missing oth_cur_missing source_file

save "$CleanDataPath/clean_2023.dta", replace

*------------------------------------------------------------------------------
* 3.7: COMBINE 2022 FILES
*------------------------------------------------------------------------------
use "$CleanDataPath/clean_2022_format19.dta", clear
append using "$CleanDataPath/clean_2022_format22.dta"
replace source_file = "2022"
save "$CleanDataPath/clean_2022.dta", replace

di "Combined 2022 records: " _N

********************************************************************************
* SECTION 4: APPEND ALL DATA INTO ONE FILE FOR MATCHING
********************************************************************************

di " "
di "========================================"
di "COMBINING ALL DATA FILES"
di "========================================"

use "$CleanDataPath/clean_2015_2018.dta", clear
append using "$CleanDataPath/clean_2019.dta"
append using "$CleanDataPath/clean_2020.dta"
append using "$CleanDataPath/clean_2021.dta"
append using "$CleanDataPath/clean_2022.dta"
append using "$CleanDataPath/clean_2023.dta"

di "Total combined records: " _N

* Create observation identifier
gen obs_id = _n
gen has_id = (id != "" & id != ".")

tab source_file
tab source_file has_id

save "$CleanDataPath/all_records_combined.dta", replace

********************************************************************************
* SECTION 5: ITERATIVE CHAINED MATCHING
********************************************************************************
* Strategy: Match forward through time BY REPORTING YEAR (not by source file).
*
* IMPORTANT: Each source file contains filings from MULTIPLE reporting years.
* For example, the 2022 file might have filings for reporting years 2019-2022.
*
* Approach:
* 1. Combine all 2019+ records into one dataset
* 2. Start with 2015-2018 as the base (has known IDs)
* 3. Match by REPORTING YEAR sequence: 2016, 2017, 2018, 2019, 2020, 2021, 2022
* 4. After matching each reporting year, add those records to the base
* 5. This allows proper chaining regardless of which source file a record is in
********************************************************************************

di " "
di "========================================"
di "STARTING ITERATIVE CHAINED MATCHING"
di "========================================"

*------------------------------------------------------------------------------
* STEP 5.1: Combine all 2019+ records into one dataset
*------------------------------------------------------------------------------
di "Combining all 2019+ records..."

use "$CleanDataPath/clean_2019.dta", clear
append using "$CleanDataPath/clean_2020.dta"
append using "$CleanDataPath/clean_2021.dta"
append using "$CleanDataPath/clean_2022.dta"
append using "$CleanDataPath/clean_2023.dta"

di "Total 2019+ records (before dedup): " _N

* Check for and remove duplicate filenames
* This can happen if a record appears in multiple source files
duplicates tag filename, gen(_dup_fn)
count if _dup_fn > 0
if r(N) > 0 {
	di "WARNING: Found " r(N) " duplicate filenames in combined 2019+ data"
	di "Keeping first observation per filename (prioritizing earlier source files)"
	bysort filename: keep if _n == 1
}
drop _dup_fn

di "Total 2019+ records (after dedup): " _N

* Fix obvious errors in report_year
* Values like 2, 7000 are clearly data entry/extraction errors
* Attempt to fix based on source_file, otherwise drop
count if report_year < 2010 | report_year > 2025
if r(N) > 0 {
	di "WARNING: Found " r(N) " records with invalid report_year values"
	tab report_year source_file if report_year < 2010 | report_year > 2025

	* Try to infer correct year from source_file
	* Records from 2022 batch with bad year → assume 2021 (most common reporting year in that batch)
	replace report_year = 2021 if (report_year < 2010 | report_year > 2025) & ///
		(source_file == "2022" | source_file == "2022_format19" | source_file == "2022_format22")

	* Records from 2023 batch with bad year → assume 2022
	replace report_year = 2022 if (report_year < 2010 | report_year > 2025) & source_file == "2023"

	* Any remaining bad values - drop them since we can't determine their report year
	count if report_year < 2010 | report_year > 2025
	if r(N) > 0 {
		di "Dropping " r(N) " records with unfixable report_year values"
		drop if report_year < 2010 | report_year > 2025
	}
}

* Also fix bad match_year values (previous_reporting_year)
count if match_year != . & (match_year < 2010 | match_year > 2025)
if r(N) > 0 {
	di "WARNING: Found " r(N) " records with invalid match_year values"
	* Set to missing - they can still be added to base but won't match on year
	replace match_year = . if match_year < 2010 | match_year > 2025
}

* Show distribution of reporting years across source files
di "Reporting year distribution by source file:"
tab report_year source_file

save "$CleanDataPath/all_2019plus_records.dta", replace

*------------------------------------------------------------------------------
* STEP 5.2: Initialize the base with 2015-2018 records
*------------------------------------------------------------------------------
* The base contains records with known IDs whose CURRENT assets can be matched
* against future records' PREVIOUS assets.

use "$CleanDataPath/clean_2015_2018.dta", clear

* For matching, current assets become the key
* report_year becomes match_year_key (the year future records would reference)
keep id filename municipio_name report_year ///
	fin_cur re_cur bus_cur oth_cur ///
	fin_cur_missing re_cur_missing bus_cur_missing oth_cur_missing

rename fin_cur fin_base
rename re_cur re_base
rename bus_cur bus_base
rename oth_cur oth_base
rename fin_cur_missing fin_base_missing
rename re_cur_missing re_base_missing
rename bus_cur_missing bus_base_missing
rename oth_cur_missing oth_base_missing
rename report_year match_year_key
rename filename base_filename

save "$CleanDataPath/matching_base.dta", replace

di "Initial base records (2015-2018): " _N
di "Base match_year_key distribution:"
tab match_year_key

* Initialize all matches file (will append to this)
clear
gen obs_id = .
gen id = ""
gen filename = ""
gen municipio_name = ""
gen match_year_key = .
gen report_year = .
gen source_file = ""
gen match_type = ""
gen match_confidence = .
save "$CleanDataPath/all_matches_full.dta", replace

*------------------------------------------------------------------------------
* STEP 5.3: Define matching program (to reuse for each REPORTING year)
*------------------------------------------------------------------------------
* NOTE: This program matches by REPORTING YEAR, not source file.
* It pulls records from the combined 2019+ dataset that have a specific report_year.
*------------------------------------------------------------------------------
capture program drop match_reporting_year
program define match_reporting_year
	args target_report_year

	di " "
	di "========================================"
	di "MATCHING REPORTING YEAR `target_report_year'"
	di "========================================"

	* Load all 2019+ records and keep only those for this reporting year
	use "$CleanDataPath/all_2019plus_records.dta", clear
	keep if report_year == `target_report_year'

	* Skip if no records
	count
	if r(N) == 0 {
		di "No records for reporting year `target_report_year'"
		exit
	}

	* Keep records without ID (need to be matched)
	keep if id == "" | id == "."
	count
	local n_to_match = r(N)
	di "Records to match for reporting year `target_report_year': `n_to_match'"

	if `n_to_match' == 0 {
		di "No unmatched records for reporting year `target_report_year'"
		exit
	}

	* Prepare for matching - use previous year assets as the key
	* Keep source_file to track which batch the record came from
	keep filename municipio_name match_year report_year source_file ///
		fin_pre re_pre bus_pre oth_pre fin_cur re_cur bus_cur oth_cur ///
		fin_pre_missing re_pre_missing bus_pre_missing oth_pre_missing ///
		fin_cur_missing re_cur_missing bus_cur_missing oth_cur_missing

	rename fin_pre fin_new
	rename re_pre re_new
	rename bus_pre bus_new
	rename oth_pre oth_new
	rename fin_pre_missing fin_new_missing
	rename re_pre_missing re_new_missing
	rename bus_pre_missing bus_new_missing
	rename oth_pre_missing oth_new_missing
	rename match_year match_year_key

	tempfile to_match
	save `to_match'

	* Load base and join on municipality + year only first
	* Then filter for exact asset matches
	use "$CleanDataPath/matching_base.dta", clear

	* Join on municipality and year - creates all candidate pairs
	joinby municipio_name match_year_key using `to_match', unmatched(using) _merge(_m)

	* For exact matches, require all 4 assets to match exactly
	gen exact_match = (_m == 3) & ///
		(fin_base == fin_new) & (re_base == re_new) & ///
		(bus_base == bus_new) & (oth_base == oth_new)

	* CRITICAL: Require at least one non-zero asset to count as valid match
	gen n_nonzero = (fin_new > 0 & fin_new_missing == 0) + ///
		(re_new > 0 & re_new_missing == 0) + ///
		(bus_new > 0 & bus_new_missing == 0) + ///
		(oth_new > 0 & oth_new_missing == 0)

	* Reject matches where all assets are zero
	replace exact_match = 0 if n_nonzero == 0

	* Separate matched from unmatched
	* First, save the joined data for later use
	tempfile joined_data
	save `joined_data'

	keep if exact_match == 1

	count
	local n_exact = r(N)
	di "Exact matches: `n_exact'"

	if `n_exact' > 0 {
		* Handle duplicates - keep first match per filename
		bysort filename (id): gen dup = _n
		keep if dup == 1
		drop dup

		* Also ensure each base record only matches once
		bysort base_filename (filename): gen dup = _n
		keep if dup == 1
		drop dup

		count
		local n_exact_dedup = r(N)
		di "Exact matches after dedup: `n_exact_dedup'"

		* Save list of base records used and matched filenames
		preserve
		keep base_filename
		duplicates drop
		save "$CleanDataPath/temp_exact_used_base.dta", replace
		restore

		preserve
		keep filename
		duplicates drop
		save "$CleanDataPath/temp_exact_matched_files.dta", replace
		restore

		gen match_type = "exact"
		gen match_confidence = 100
		gen obs_id = _n + 1000000  // Placeholder

		* Save these matches
		keep obs_id id filename municipio_name match_year_key report_year ///
			source_file match_type match_confidence

		append using "$CleanDataPath/all_matches_full.dta"
		save "$CleanDataPath/all_matches_full.dta", replace
	}
	else {
		* No exact matches - create empty temp files
		clear
		gen base_filename = ""
		save "$CleanDataPath/temp_exact_used_base.dta", replace

		clear
		gen filename = ""
		save "$CleanDataPath/temp_exact_matched_files.dta", replace
	}

	* Now get unmatched records - those that weren't exactly matched
	* Reload the original to_match file to get clean unmatched records
	use `to_match', clear
	merge 1:1 filename using "$CleanDataPath/temp_exact_matched_files.dta", keep(master) nogen

	count
	local n_unmatched = r(N)
	di "Unmatched after exact: `n_unmatched'"

	if `n_unmatched' > 0 {
		* FUZZY MATCHING
		tempfile unmatched
		save `unmatched'

		* Load base for fuzzy matching - but exclude base records already used in exact matching
		use "$CleanDataPath/matching_base.dta", clear

		* Remove base records that were already used in exact matches
		merge m:1 base_filename using "$CleanDataPath/temp_exact_used_base.dta", keep(master) nogen

		* Join on municipality and year only
		joinby municipio_name match_year_key using `unmatched', unmatched(none)

		count
		local n_candidates = r(N)
		di "Fuzzy match candidates: `n_candidates'"

		if `n_candidates' > 0 {
			* Calculate digit distance for each asset
			foreach asset in fin re bus oth {
				gen `asset'_either_missing = (`asset'_new_missing == 1) | (`asset'_base_missing == 1)
				gen `asset'_diff = abs(`asset'_new - `asset'_base)
				gen `asset'_mag_new = floor(log10(max(`asset'_new, 1))) + 1
				gen `asset'_mag_base = floor(log10(max(`asset'_base, 1))) + 1
				gen `asset'_mag = max(`asset'_mag_new, `asset'_mag_base)
				gen `asset'_both_zero = (`asset'_new == 0 & `asset'_base == 0)

				gen `asset'_digit_dist = 0 if `asset'_diff == 0 & `asset'_both_zero == 0
				replace `asset'_digit_dist = 88 if `asset'_both_zero == 1
				replace `asset'_digit_dist = 1 if `asset'_diff > 0 & `asset'_diff <= 10^(`asset'_mag - 1)
				replace `asset'_digit_dist = 2 if `asset'_diff > 10^(`asset'_mag - 1) & `asset'_diff <= 10^(`asset'_mag)
				replace `asset'_digit_dist = 99 if `asset'_diff > 10^(`asset'_mag) | `asset'_digit_dist == .
				replace `asset'_digit_dist = 99 if `asset'_either_missing == 1

				drop `asset'_mag_new `asset'_mag_base `asset'_mag `asset'_either_missing `asset'_both_zero
			}

			* Require at least 1 valid non-zero match
			gen n_valid = (fin_digit_dist < 88) + (re_digit_dist < 88) + ///
				(bus_digit_dist < 88) + (oth_digit_dist < 88)
			keep if n_valid >= 1

			* Calculate total distance (only valid comparisons)
			gen total_dist = 0
			foreach asset in fin re bus oth {
				replace total_dist = total_dist + `asset'_digit_dist if `asset'_digit_dist < 88
			}

			* Keep only fuzzy matches with small total distance
			keep if total_dist <= 4 & total_dist > 0

			count
			local n_fuzzy_cand = r(N)
			di "Fuzzy candidates after distance filter: `n_fuzzy_cand'"

			if `n_fuzzy_cand' > 0 {
				* Confidence score
				gen n_1digit = (fin_digit_dist == 1) + (re_digit_dist == 1) + ///
					(bus_digit_dist == 1) + (oth_digit_dist == 1)
				gen n_2digit = (fin_digit_dist == 2) + (re_digit_dist == 2) + ///
					(bus_digit_dist == 2) + (oth_digit_dist == 2)
				gen match_confidence = 100 - 5*n_1digit - 10*n_2digit

				* Keep best match per filename (new record)
				gsort filename -match_confidence total_dist
				bysort filename: gen rank = _n
				keep if rank == 1
				drop rank

				* Keep best match per base record (base_filename is unique)
				gsort base_filename -match_confidence total_dist
				bysort base_filename: gen rank = _n
				keep if rank == 1
				drop rank

				count
				local n_fuzzy = r(N)
				di "Final fuzzy matches: `n_fuzzy'"

				gen match_type = "fuzzy"
				gen obs_id = _n + 2000000

				keep obs_id id filename municipio_name match_year_key report_year ///
					source_file match_type match_confidence

				append using "$CleanDataPath/all_matches_full.dta"
				save "$CleanDataPath/all_matches_full.dta", replace
			}
		}
	}

	* UPDATE THE BASE: Add ALL records from this REPORTING YEAR (matched AND unmatched)
	* Their current assets become available for matching future reporting years
	* This allows chaining regardless of which source file records came from

	* First, get matched IDs for this reporting year
	use "$CleanDataPath/all_matches_full.dta", clear
	keep if report_year == `target_report_year'

	count
	local n_matched = r(N)
	di "Matched records for reporting year `target_report_year': `n_matched'"

	if `n_matched' > 0 {
		keep filename id
		* Deduplicate matched_ids (keep first match per filename)
		duplicates drop filename, force
		tempfile matched_ids
		save `matched_ids'
	}

	* Now load ALL records from this reporting year (from the combined 2019+ file)
	use "$CleanDataPath/all_2019plus_records.dta", clear
	keep if report_year == `target_report_year'

	* Check for and handle duplicate filenames in master
	duplicates tag filename, gen(_dup_fn)
	count if _dup_fn > 0
	if r(N) > 0 {
		di "WARNING: Found " r(N) " duplicate filenames in master data for reporting year `target_report_year'"
		di "Keeping first observation per filename"
		bysort filename: keep if _n == 1
	}
	drop _dup_fn

	* Merge in IDs for matched records (now safe to use 1:1)
	* NOTE: The master has id="" for all records. We need to UPDATE id from the using file.
	* Stata merge won't replace existing values, so we drop id first then merge.
	drop id

	if `n_matched' > 0 {
		merge 1:1 filename using `matched_ids', keep(master match) nogen
	}

	* Ensure id variable exists (for unmatched records or when n_matched=0)
	capture confirm variable id
	if _rc != 0 {
		gen id = ""
	}

	* For unmatched records, assign filename as temporary ID for chaining
	replace id = filename if id == "" | id == "."

	* DIAGNOSTIC: Check how many got inherited IDs vs new filename IDs
	* An inherited ID means id != filename (they matched to someone in the base)
	gen inherited_id = (id != filename)
	count if inherited_id == 1
	di "DIAGNOSTIC: Records that MATCHED (inherited ID from base): " r(N)
	count if inherited_id == 0
	di "DIAGNOSTIC: Records that DID NOT MATCH (new chain, id=filename): " r(N)
	drop inherited_id

	count
	local n_all = r(N)
	di "Total records to add to base for reporting year `target_report_year': `n_all'"

	* Prepare for base format
	rename fin_cur fin_base
	rename re_cur re_base
	rename bus_cur bus_base
	rename oth_cur oth_base
	rename fin_cur_missing fin_base_missing
	rename re_cur_missing re_base_missing
	rename bus_cur_missing bus_base_missing
	rename oth_cur_missing oth_base_missing
	rename report_year match_year_key
	rename filename base_filename

	keep id base_filename municipio_name match_year_key ///
		fin_base re_base bus_base oth_base ///
		fin_base_missing re_base_missing bus_base_missing oth_base_missing

	* Append to base
	append using "$CleanDataPath/matching_base.dta"
	save "$CleanDataPath/matching_base.dta", replace

	di "Base expanded with ALL `n_all' records for reporting year `target_report_year'"
	di "New base size: " _N

	* Diagnostic: Show distribution of match_year_key in base
	di "Base match_year_key distribution:"
	tab match_year_key

	* DIAGNOSTIC: Check how many unique IDs are in the base
	preserve
	keep id
	duplicates drop
	count
	di "DIAGNOSTIC: Unique IDs in base: " r(N)
	restore

	* DIAGNOSTIC: Show a sample of IDs that came from 2015-2018 to verify chaining
	di "DIAGNOSTIC: Sample base records with 2015-2018 style IDs:"
	list id base_filename match_year_key if regexm(id, "^[0-9]+-22-S-") in 1/10

end

*------------------------------------------------------------------------------
* STEP 5.4: Run matching for each REPORTING YEAR sequentially
*------------------------------------------------------------------------------
* We need to match in order of reporting year, starting from the earliest
* that appears in the 2019+ data.

* First, find what reporting years exist in the 2019+ data
use "$CleanDataPath/all_2019plus_records.dta", clear
levelsof report_year, local(report_years)
di "Reporting years found in 2019+ data: `report_years'"

* Sort and match each reporting year in sequence (ensure chronological order)
local sorted_years : list sort report_years
di "Sorted reporting years: `sorted_years'"

foreach yr of local sorted_years {
	match_reporting_year `yr'

	* DIAGNOSTIC: Show how many matches we have so far
	use "$CleanDataPath/all_matches_full.dta", clear
	count
	di "DIAGNOSTIC: Total matches so far after year `yr': " r(N)
	tab report_year
}

*------------------------------------------------------------------------------
* STEP 5.5: Summary of all matches
*------------------------------------------------------------------------------
di " "
di "========================================"
di "MATCHING COMPLETE"
di "========================================"

use "$CleanDataPath/all_matches_full.dta", clear

* Remove placeholder empty row
drop if id == ""

count
local n_total = r(N)
di "Total matches: `n_total'"

tab source_file match_type

save "$CleanDataPath/all_matches_full.dta", replace

********************************************************************************
* SECTION 6: CREATE PANEL DATASET
********************************************************************************
* The panel needs to track:
* - Original IDs from 2015-2018 file
* - Filenames from each year (since the same person has different filenames each year)
* - Matched IDs (which could be original IDs or filenames from earlier years)
********************************************************************************

di " "
di "========================================"
di "CREATING PANEL DATASET"
di "========================================"

* First, build a crosswalk of all matched records to trace chains back
* Start with the matches file and expand to track all filenames per person

use "$CleanDataPath/all_matches_full.dta", clear
drop if id == ""

* Keep key variables
keep id filename source_file
rename filename matched_filename
rename source_file matched_year

* Save crosswalk of matches
save "$CleanDataPath/match_crosswalk.dta", replace

* Now build the panel - start with 2015-2018
use "$CleanDataPath/clean_2015_2018.dta", clear
keep id filename municipio_name report_year decree_year fin_cur re_cur bus_cur oth_cur
rename filename filename_2015_2018
gen source_file = "2015-2018"

* Create placeholder filename variables for future years
foreach year in 2019 2020 2021 2022 2023 {
	gen filename_`year' = ""
}

tempfile panel_build
save `panel_build'

* First, create a deduplicated version of matches for merging
use "$CleanDataPath/all_matches_full.dta", clear
drop if id == ""
* Keep one match per filename (prefer higher confidence)
gsort filename -match_confidence
bysort filename: keep if _n == 1
keep filename id
save "$CleanDataPath/all_matches_dedup.dta", replace

* Load all 2019+ records and merge in matched IDs
use "$CleanDataPath/all_2019plus_records.dta", clear
keep filename municipio_name report_year decree_year source_file fin_cur re_cur bus_cur oth_cur

* Merge in matched IDs (using deduplicated file)
merge 1:1 filename using "$CleanDataPath/all_matches_dedup.dta", ///
	keepusing(id) keep(master match) nogen

* For unmatched, use filename as ID (they start their own chain)
replace id = filename if id == "" | id == "."

* Create placeholder filename variables for all source file batches
gen filename_2015_2018 = ""
gen filename_2019 = ""
gen filename_2020 = ""
gen filename_2021 = ""
gen filename_2022 = ""
gen filename_2023 = ""

* Fill in the appropriate filename variable based on source_file
replace filename_2019 = filename if source_file == "2019"
replace filename_2020 = filename if source_file == "2020"
replace filename_2021 = filename if source_file == "2021"
replace filename_2022 = filename if source_file == "2022" | source_file == "2022_format19" | source_file == "2022_format22"
replace filename_2023 = filename if source_file == "2023"

append using `panel_build'
save `panel_build', replace

use `panel_build', clear

* Now we need to fill in the filename columns for matched records
* For records that matched to a 2015-2018 ID, the 2015-2018 filename should be populated
* For records that matched to a 2019 filename-ID, the 2019 filename should be filled

* First, get 2015-2018 filenames for records with original IDs
preserve
keep if source_file == "2015-2018"
keep id filename_2015_2018
rename filename_2015_2018 fn_1518
duplicates drop id, force
tempfile fn1518
save `fn1518'
restore

merge m:1 id using `fn1518', keep(master match) nogen
replace filename_2015_2018 = fn_1518 if filename_2015_2018 == "" & fn_1518 != ""
drop fn_1518

* Now propagate filenames for chained matches (2019 onward)
* For each year, get the filename for records that match to that year's IDs
foreach year in 2019 2020 2021 2022 2023 {
	preserve
	keep if source_file == "`year'"
	keep id filename_`year'
	rename filename_`year' fn_`year'
	* Keep only where the ID started in this year (filename-based ID)
	gen id_from_this_year = (id == fn_`year')
	keep if id_from_this_year == 1 | fn_`year' != ""
	drop id_from_this_year
	duplicates drop id, force
	tempfile fn`year'
	save `fn`year''
	restore

	merge m:1 id using `fn`year'', keep(master match) nogen
	replace filename_`year' = fn_`year' if filename_`year' == "" & fn_`year' != ""
	capture drop fn_`year'
}

* For unmatched records without original ID, use filename as panel_id
gen panel_id = id
replace panel_id = filename if panel_id == "" | panel_id == "."

* Rename assets
rename fin_cur fin
rename re_cur re
rename bus_cur bus
rename oth_cur oth

* Order and sort
order panel_id report_year decree_year id filename filename_2015_2018 filename_2019 ///
	filename_2020 filename_2021 filename_2022 filename_2023 ///
	fin re bus oth source_file
sort panel_id report_year

* Label variables
label var panel_id "Unique person identifier (original ID or first filename)"
label var report_year "Current reporting year"
label var decree_year "Year of Act 22 decree (if available)"
label var id "Matched ID (original ID or filename from first appearance)"
label var filename "CSV filename for this specific record"
label var filename_2015_2018 "Filename from 2015-2018 file (if matched)"
label var filename_2019 "Filename from 2019 file (if matched)"
label var filename_2020 "Filename from 2020 file (if matched)"
label var filename_2021 "Filename from 2021 file (if matched)"
label var filename_2022 "Filename from 2022 file (if matched)"
label var filename_2023 "Filename from 2023 file (if matched)"
label var fin "Financial wealth"
label var re "Real estate wealth"
label var bus "Business wealth"
label var oth "Other wealth"
label var source_file "Source data file"

* Verify panel uniqueness - panel_id + report_year should be unique
duplicates tag panel_id report_year, gen(dup_check)
count if dup_check > 0
local n_dups = r(N)
if `n_dups' > 0 {
	di "WARNING: `n_dups' duplicate panel_id + report_year combinations found!"
	di "Keeping first observation per panel_id + report_year"
	bysort panel_id report_year: keep if _n == 1
}
drop dup_check

* Summary statistics
di " "
di "========================================"
di "PANEL DATASET SUMMARY"
di "========================================"

egen tag_panel = tag(panel_id)
count if tag_panel == 1
local n_persons = r(N)
di "Unique persons (panel_id): `n_persons'"

* Count records linked to original 2015-2018 IDs
gen has_orig_id = (substr(id, 1, 2) != "" & strpos(id, ".pdf") == 0 & strpos(id, ".PDF") == 0)
count if has_orig_id == 1
local n_with_orig_id = r(N)
di "Records linked to 2015-2018 ID: `n_with_orig_id'"

count if has_orig_id == 0
local n_new_chains = r(N)
di "Records in new chains (2019+): `n_new_chains'"

di " "
di "Records by source file:"
tab source_file

di " "
di "Records by reporting year:"
tab report_year

di " "
di "Filename coverage by year:"
count if filename_2015_2018 != ""
di "Records with 2015-2018 filename: " r(N)
count if filename_2019 != ""
di "Records with 2019 filename: " r(N)
count if filename_2020 != ""
di "Records with 2020 filename: " r(N)
count if filename_2021 != ""
di "Records with 2021 filename: " r(N)
count if filename_2022 != ""
di "Records with 2022 filename: " r(N)
count if filename_2023 != ""
di "Records with 2023 filename: " r(N)

drop tag_panel has_orig_id

save "$CleanDataPath/act22_panel_full.dta", replace

* Clean up temporary files
capture erase "$CleanDataPath/temp_exact_used_base.dta"
capture erase "$CleanDataPath/temp_exact_matched_files.dta"

di " "
di "========================================"
di "PANEL SAVED: $CleanDataPath/act22_panel_full.dta"
di "========================================"

********************************************************************************
* END OF SCRIPT
********************************************************************************
