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
* It handles all known variations and typos.
********************************************************************************

capture program drop standardize_municipio
program define standardize_municipio
	* Input: variable called municipio_name
	* Output: standardized municipio_name

	* Remove common suffixes
	replace municipio_name = subinstr(municipio_name, ", Puerto Rico", "", .)
	replace municipio_name = subinstr(municipio_name, ", P.R.", "", .)
	replace municipio_name = subinstr(municipio_name, ", P. R.", "", .)
	replace municipio_name = subinstr(municipio_name, " P.R.", "", .)
	replace municipio_name = subinstr(municipio_name, ", PR", "", .)
	replace municipio_name = subinstr(municipio_name, " PR", "", .)
	replace municipio_name = subinstr(municipio_name, " Puerto Rico", "", .)
	replace municipio_name = subinstr(municipio_name, ", USA", "", .)
	replace municipio_name = subinstr(municipio_name, " USA", "", .)
	replace municipio_name = subinstr(municipio_name, ", U.S.A.", "", .)
	replace municipio_name = subinstr(municipio_name, " -", "", .)

	* Trim whitespace
	replace municipio_name = strtrim(municipio_name)

	* Standardize to title case versions
	replace municipio_name = "Aguada" if inlist(municipio_name, "AGUADA", "aguada")
	replace municipio_name = "Aguadilla" if inlist(municipio_name, "AGUADILLA", "aguadilla")
	replace municipio_name = "Aguas Buenas" if inlist(municipio_name, "AGUAS BUENAS", "aguas buenas", "Aguas buenas")
	replace municipio_name = "Aibonito" if inlist(municipio_name, "AIBONITO", "aibonito")
	replace municipio_name = "Anasco" if inlist(municipio_name, "ANASCO", "Añasco", "AÑASCO", "anasco")
	replace municipio_name = "Arecibo" if inlist(municipio_name, "ARECIBO", "arecibo")
	replace municipio_name = "Arroyo" if inlist(municipio_name, "ARROYO", "arroyo")
	replace municipio_name = "Barceloneta" if inlist(municipio_name, "BARCELONETA", "barceloneta")
	replace municipio_name = "Barranquitas" if inlist(municipio_name, "BARRANQUITAS", "barranquitas")
	replace municipio_name = "Bayamon" if inlist(municipio_name, "BAYAMON", "Bayamón", "BAYAMÓN", "bayamon")
	replace municipio_name = "Cabo Rojo" if inlist(municipio_name, "CABO ROJO", "cabo rojo", "Cabo rojo")
	replace municipio_name = "Caguas" if inlist(municipio_name, "CAGUAS", "caguas")
	replace municipio_name = "Camuy" if inlist(municipio_name, "CAMUY", "camuy")
	replace municipio_name = "Canovanas" if inlist(municipio_name, "CANOVANAS", "Canóvanas", "CANÓVANAS", "canovanas")
	replace municipio_name = "Carolina" if inlist(municipio_name, "CAROLINA", "carolina", "Carolina, P R   U S A")
	replace municipio_name = "Catano" if inlist(municipio_name, "CATANO", "Cataño", "CATAÑO", "catano")
	replace municipio_name = "Cayey" if inlist(municipio_name, "CAYEY", "cayey")
	replace municipio_name = "Ceiba" if inlist(municipio_name, "CEIBA", "ceiba")
	replace municipio_name = "Ciales" if inlist(municipio_name, "CIALES", "ciales")
	replace municipio_name = "Cidra" if inlist(municipio_name, "CIDRA", "cidra")
	replace municipio_name = "Coamo" if inlist(municipio_name, "COAMO", "coamo")
	replace municipio_name = "Comerio" if inlist(municipio_name, "COMERIO", "Comerío", "COMERÍO", "comerio")
	replace municipio_name = "Corozal" if inlist(municipio_name, "COROZAL", "corozal")
	replace municipio_name = "Culebra" if inlist(municipio_name, "CULEBRA", "culebra")
	replace municipio_name = "Dorado" if inlist(municipio_name, "DORADO", "dorado")
	replace municipio_name = "Fajardo" if inlist(municipio_name, "FAJARDO", "fajardo")
	replace municipio_name = "Florida" if inlist(municipio_name, "FLORIDA", "florida")
	replace municipio_name = "Guanica" if inlist(municipio_name, "GUANICA", "Guánica", "GUÁNICA", "guanica")
	replace municipio_name = "Guayama" if inlist(municipio_name, "GUAYAMA", "guayama")
	replace municipio_name = "Guayanilla" if inlist(municipio_name, "GUAYANILLA", "guayanilla")
	replace municipio_name = "Guaynabo" if inlist(municipio_name, "GUAYNABO", "guaynabo")
	replace municipio_name = "Gurabo" if inlist(municipio_name, "GURABO", "gurabo")
	replace municipio_name = "Hatillo" if inlist(municipio_name, "HATILLO", "hatillo")
	replace municipio_name = "Hormigueros" if inlist(municipio_name, "HORMIGUEROS", "hormigueros")
	replace municipio_name = "Humacao" if inlist(municipio_name, "HUMACAO", "humacao")
	replace municipio_name = "Isabela" if inlist(municipio_name, "ISABELA", "isabela")
	replace municipio_name = "Jayuya" if inlist(municipio_name, "JAYUYA", "jayuya")
	replace municipio_name = "Juana Diaz" if inlist(municipio_name, "JUANA DIAZ", "Juana Díaz", "JUANA DÍAZ", "juana diaz")
	replace municipio_name = "Juncos" if inlist(municipio_name, "JUNCOS", "juncos")
	replace municipio_name = "Lajas" if inlist(municipio_name, "LAJAS", "lajas")
	replace municipio_name = "Lares" if inlist(municipio_name, "LARES", "lares")
	replace municipio_name = "Las Marias" if inlist(municipio_name, "LAS MARIAS", "Las Marías", "LAS MARÍAS", "las marias")
	replace municipio_name = "Las Piedras" if inlist(municipio_name, "LAS PIEDRAS", "las piedras")
	replace municipio_name = "Loiza" if inlist(municipio_name, "LOIZA", "Loíza", "LOÍZA", "loiza")
	replace municipio_name = "Luquillo" if inlist(municipio_name, "LUQUILLO", "luquillo")
	replace municipio_name = "Manati" if inlist(municipio_name, "MANATI", "Manatí", "MANATÍ", "manati")
	replace municipio_name = "Maricao" if inlist(municipio_name, "MARICAO", "maricao")
	replace municipio_name = "Maunabo" if inlist(municipio_name, "MAUNABO", "maunabo")
	replace municipio_name = "Mayaguez" if inlist(municipio_name, "MAYAGUEZ", "Mayagüez", "MAYAGÜEZ", "mayaguez")
	replace municipio_name = "Moca" if inlist(municipio_name, "MOCA", "moca")
	replace municipio_name = "Morovis" if inlist(municipio_name, "MOROVIS", "morovis")
	replace municipio_name = "Naguabo" if inlist(municipio_name, "NAGUABO", "naguabo")
	replace municipio_name = "Naranjito" if inlist(municipio_name, "NARANJITO", "naranjito")
	replace municipio_name = "Orocovis" if inlist(municipio_name, "OROCOVIS", "orocovis")
	replace municipio_name = "Patillas" if inlist(municipio_name, "PATILLAS", "patillas")
	replace municipio_name = "Penuelas" if inlist(municipio_name, "PENUELAS", "Peñuelas", "PEÑUELAS", "penuelas")
	replace municipio_name = "Ponce" if inlist(municipio_name, "PONCE", "ponce")
	replace municipio_name = "Quebradillas" if inlist(municipio_name, "QUEBRADILLAS", "quebradillas")
	replace municipio_name = "Rincon" if inlist(municipio_name, "RINCON", "Rincón", "RINCÓN", "rincon")
	replace municipio_name = "Rio Grande" if inlist(municipio_name, "RIO GRANDE", "Río Grande", "RÍO GRANDE", "rio grande")
	replace municipio_name = "Sabana Grande" if inlist(municipio_name, "SABANA GRANDE", "sabana grande")
	replace municipio_name = "Salinas" if inlist(municipio_name, "SALINAS", "salinas")
	replace municipio_name = "San German" if inlist(municipio_name, "SAN GERMAN", "San Germán", "SAN GERMÁN", "san german")
	replace municipio_name = "San Juan" if inlist(municipio_name, "SAN JUAN", "san juan", "Sn Juan", "SN JUAN")
	replace municipio_name = "San Lorenzo" if inlist(municipio_name, "SAN LORENZO", "san lorenzo")
	replace municipio_name = "San Sebastian" if inlist(municipio_name, "SAN SEBASTIAN", "San Sebastián", "SAN SEBASTIÁN", "san sebastian")
	replace municipio_name = "Santa Isabel" if inlist(municipio_name, "SANTA ISABEL", "santa isabel")
	replace municipio_name = "Toa Alta" if inlist(municipio_name, "TOA ALTA", "toa alta")
	replace municipio_name = "Toa Baja" if inlist(municipio_name, "TOA BAJA", "toa baja")
	replace municipio_name = "Trujillo Alto" if inlist(municipio_name, "TRUJILLO ALTO", "trujillo alto")
	replace municipio_name = "Utuado" if inlist(municipio_name, "UTUADO", "utuado")
	replace municipio_name = "Vega Alta" if inlist(municipio_name, "VEGA ALTA", "vega alta")
	replace municipio_name = "Vega Baja" if inlist(municipio_name, "VEGA BAJA", "vega baja")
	replace municipio_name = "Vieques" if inlist(municipio_name, "VIEQUES", "vieques")
	replace municipio_name = "Villalba" if inlist(municipio_name, "VILLALBA", "villalba")
	replace municipio_name = "Yabucoa" if inlist(municipio_name, "YABUCOA", "yabucoa")
	replace municipio_name = "Yauco" if inlist(municipio_name, "YAUCO", "yauco")

	* Additional common variations/typos from 2015-2019 data
	replace municipio_name = "Dorado" if inlist(municipio_name, "dorado PR", "Dorado PR")
	replace municipio_name = "San Juan" if inlist(municipio_name, "San  Juan", "San juan", "Sanjuan", "SANJUAN")
	replace municipio_name = "Guaynabo" if inlist(municipio_name, "Guayanabo", "GUAYANABO")
	replace municipio_name = "Carolina" if inlist(municipio_name, "Caroliina", "CAROLIINA")
	replace municipio_name = "Humacao" if inlist(municipio_name, "Humacoa", "HUMACOA")
	replace municipio_name = "Bayamon" if inlist(municipio_name, "Bayamon PR", "BAYAMON PR")

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

* Extract municipality from sworn statement location
gen municipio_name = sworn_statement_city_and_country
standardize_municipio

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

* Municipality is in 'county' field
rename county municipio_name
standardize_municipio

* Year variables
destring current_reporting_year previous_reporting_year, replace force
rename current_reporting_year report_year
rename previous_reporting_year match_year

* Asset variables - use capture to handle variable name truncation variations
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

rename county municipio_name
standardize_municipio

destring current_reporting_year previous_reporting_year, replace force
rename current_reporting_year report_year
rename previous_reporting_year match_year

* Asset variables - use capture to handle variable name truncation variations
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

rename county municipio_name
standardize_municipio

destring current_reporting_year previous_reporting_year, replace force
rename current_reporting_year report_year
rename previous_reporting_year match_year

* Asset variables - use capture to handle variable name truncation variations
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

rename county municipio_name
standardize_municipio

destring current_reporting_year previous_reporting_year, replace force
rename current_reporting_year report_year
rename previous_reporting_year match_year

* Asset variables - use capture to handle variable name truncation variations
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

rename county municipio_name
standardize_municipio

destring current_reporting_year previous_reporting_year, replace force
rename current_reporting_year report_year
rename previous_reporting_year match_year

* Asset variables - use capture to handle variable name truncation variations
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

rename county municipio_name
standardize_municipio

destring current_reporting_year previous_reporting_year, replace force
rename current_reporting_year report_year
rename previous_reporting_year match_year

* Asset variables - use capture to handle variable name truncation variations
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
* Strategy: Match forward through time ITERATIVELY.
* 1. Start with 2015-2018 as the base (has known IDs)
* 2. Match 2019 records to 2015-2018 based on previous year assets
* 3. Add matched 2019 records to the base
* 4. Match 2020 records to the expanded base
* 5. Repeat for 2021, 2022, 2023
*
* This allows chaining: A 2020 record can match to a 2019 record that was
* already matched to a 2015-2018 ID.
********************************************************************************

di " "
di "========================================"
di "STARTING ITERATIVE CHAINED MATCHING"
di "========================================"

*------------------------------------------------------------------------------
* STEP 5.1: Initialize the base with 2015-2018 records
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
* STEP 5.2: Define matching program (to reuse for each year)
*------------------------------------------------------------------------------
capture program drop match_year_to_base
program define match_year_to_base
	args source_year

	di " "
	di "========================================"
	di "MATCHING `source_year' DATA"
	di "========================================"

	* Load records from this source year
	use "$CleanDataPath/clean_`source_year'.dta", clear

	* Skip if no records or all have IDs already
	count
	if r(N) == 0 {
		di "No records to match for `source_year'"
		exit
	}

	* Keep records without ID (need to be matched)
	keep if id == "" | id == "."
	count
	local n_to_match = r(N)
	di "Records to match: `n_to_match'"

	if `n_to_match' == 0 {
		di "No unmatched records for `source_year'"
		exit
	}

	* Prepare for matching - use previous year assets as the key
	keep filename municipio_name match_year report_year ///
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

	gen source_file = "`source_year'"

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

	* UPDATE THE BASE: Add ALL records from this year (matched AND unmatched)
	* Their current assets become available for matching future years
	* This allows chaining: 2020 can match to unmatched 2019 records, etc.

	* First, get matched IDs for this year
	use "$CleanDataPath/all_matches_full.dta", clear
	keep if source_file == "`source_year'"

	count
	local n_matched = r(N)
	di "Matched records from `source_year': `n_matched'"

	if `n_matched' > 0 {
		keep filename id
		tempfile matched_ids
		save `matched_ids'
	}

	* Now load ALL records from this year
	use "$CleanDataPath/clean_`source_year'.dta", clear

	* Merge in IDs for matched records
	if `n_matched' > 0 {
		merge 1:1 filename using `matched_ids', keep(master match) nogen
	}

	* For unmatched records, assign filename as temporary ID for chaining
	replace id = filename if id == "" | id == "."

	count
	local n_all = r(N)
	di "Total records to add to base from `source_year': `n_all'"

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

	di "Base expanded with ALL `n_all' records from `source_year'"
	di "New base size: " _N

end

*------------------------------------------------------------------------------
* STEP 5.3: Run matching for each year sequentially
*------------------------------------------------------------------------------
match_year_to_base 2019
match_year_to_base 2020
match_year_to_base 2021
match_year_to_base 2022
match_year_to_base 2023

*------------------------------------------------------------------------------
* STEP 5.4: Summary of all matches
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

* For each subsequent year, process and add to panel
foreach year in 2019 2020 2021 2022 2023 {
	use "$CleanDataPath/clean_`year'.dta", clear
	keep filename municipio_name report_year decree_year fin_cur re_cur bus_cur oth_cur

	* Merge in matched IDs (using deduplicated file)
	merge 1:1 filename using "$CleanDataPath/all_matches_dedup.dta", ///
		keepusing(id) keep(master match) nogen

	* For unmatched, use filename as ID (they start their own chain)
	replace id = filename if id == "" | id == "."

	gen source_file = "`year'"

	* Create year-specific filename variable
	gen filename_`year' = filename
	rename filename filename_original

	* Create placeholder filename variables for other years
	gen filename_2015_2018 = ""
	foreach yr in 2019 2020 2021 2022 2023 {
		if "`yr'" != "`year'" {
			gen filename_`yr' = ""
		}
	}

	rename filename_original filename

	append using `panel_build'
	save `panel_build', replace
}

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
