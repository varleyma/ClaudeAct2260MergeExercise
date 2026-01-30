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

* Convert assets to numeric
foreach var in financial_wealth_pre real_estate_wealth_pre business_wealth_pre other_wealth_pre ///
               financial_wealth real_estate_wealth business_wealth other_wealth {
	destring `var', replace force
	replace `var' = 0 if `var' == .
	replace `var' = round(`var')
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

* Handle duplicates - keep first per id-year
sort id report_year
bysort id report_year: keep if _n == 1

* Keep key variables
keep id filename municipio_name report_year match_year ///
	fin_pre re_pre bus_pre oth_pre fin_cur re_cur bus_cur oth_cur

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

* Asset variables
rename asset_type_financial_previous_re fin_pre
rename asset_type_financial_current_rep fin_cur
rename asset_type_real_estate_previous_ re_pre
rename asset_type_real_estate_current_r re_cur
rename asset_type_privately_held_busine bus_pre
rename asset_type_privately_held_busin bus_cur
rename asset_type_other_previous_report oth_pre
rename asset_type_other_current_reporti oth_cur

foreach var in fin_pre fin_cur re_pre re_cur bus_pre bus_cur oth_pre oth_cur {
	destring `var', replace force
	replace `var' = 0 if `var' == .
	replace `var' = round(`var')
}

gen id = ""
gen source_file = "2019"

keep id filename municipio_name report_year match_year ///
	fin_pre re_pre bus_pre oth_pre fin_cur re_cur bus_cur oth_cur source_file

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

rename asset_type_financial_previous_re fin_pre
rename asset_type_financial_current_rep fin_cur
rename asset_type_real_estate_previous_ re_pre
rename asset_type_real_estate_current_r re_cur
rename asset_type_privately_held_busine bus_pre
rename asset_type_privately_held_busin bus_cur
rename asset_type_other_previous_report oth_pre
rename asset_type_other_current_reporti oth_cur

foreach var in fin_pre fin_cur re_pre re_cur bus_pre bus_cur oth_pre oth_cur {
	destring `var', replace force
	replace `var' = 0 if `var' == .
	replace `var' = round(`var')
}

gen id = ""
gen source_file = "2020"

keep id filename municipio_name report_year match_year ///
	fin_pre re_pre bus_pre oth_pre fin_cur re_cur bus_cur oth_cur source_file

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

rename asset_type_financial_previous_re fin_pre
rename asset_type_financial_current_rep fin_cur
rename asset_type_real_estate_previous_ re_pre
rename asset_type_real_estate_current_r re_cur
rename asset_type_privately_held_busine bus_pre
rename asset_type_privately_held_busin bus_cur
rename asset_type_other_previous_report oth_pre
rename asset_type_other_current_reporti oth_cur

foreach var in fin_pre fin_cur re_pre re_cur bus_pre bus_cur oth_pre oth_cur {
	destring `var', replace force
	replace `var' = 0 if `var' == .
	replace `var' = round(`var')
}

gen id = ""
gen source_file = "2021"

keep id filename municipio_name report_year match_year ///
	fin_pre re_pre bus_pre oth_pre fin_cur re_cur bus_cur oth_cur source_file

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

rename asset_type_financial_previous_re fin_pre
rename asset_type_financial_current_rep fin_cur
rename asset_type_real_estate_previous_ re_pre
rename asset_type_real_estate_current_r re_cur
rename asset_type_privately_held_busine bus_pre
rename asset_type_privately_held_busin bus_cur
rename asset_type_other_previous_report oth_pre
rename asset_type_other_current_reporti oth_cur

foreach var in fin_pre fin_cur re_pre re_cur bus_pre bus_cur oth_pre oth_cur {
	destring `var', replace force
	replace `var' = 0 if `var' == .
	replace `var' = round(`var')
}

gen id = ""
gen source_file = "2022_format19"

keep id filename municipio_name report_year match_year ///
	fin_pre re_pre bus_pre oth_pre fin_cur re_cur bus_cur oth_cur source_file

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

rename asset_type_financial_previous_re fin_pre
rename asset_type_financial_current_rep fin_cur
rename asset_type_real_estate_previous_ re_pre
rename asset_type_real_estate_current_r re_cur
rename asset_type_privately_held_busine bus_pre
rename asset_type_privately_held_busin bus_cur
rename asset_type_other_previous_report oth_pre
rename asset_type_other_current_reporti oth_cur

foreach var in fin_pre fin_cur re_pre re_cur bus_pre bus_cur oth_pre oth_cur {
	destring `var', replace force
	replace `var' = 0 if `var' == .
	replace `var' = round(`var')
}

gen id = ""
gen source_file = "2022_format22"

keep id filename municipio_name report_year match_year ///
	fin_pre re_pre bus_pre oth_pre fin_cur re_cur bus_cur oth_cur source_file

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

rename asset_type_financial_previous_re fin_pre
rename asset_type_financial_current_rep fin_cur
rename asset_type_real_estate_previous_ re_pre
rename asset_type_real_estate_current_r re_cur
rename asset_type_privately_held_busine bus_pre
rename asset_type_privately_held_busin bus_cur
rename asset_type_other_previous_report oth_pre
rename asset_type_other_current_reporti oth_cur

foreach var in fin_pre fin_cur re_pre re_cur bus_pre bus_cur oth_pre oth_cur {
	destring `var', replace force
	replace `var' = 0 if `var' == .
	replace `var' = round(`var')
}

gen id = ""
gen source_file = "2023"

keep id filename municipio_name report_year match_year ///
	fin_pre re_pre bus_pre oth_pre fin_cur re_cur bus_cur oth_cur source_file

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
* SECTION 5: SEQUENTIAL FUZZY MATCHING
********************************************************************************
* Strategy: Match forward through time. Each year's current assets become
* the next year's previous assets for matching.
*
* For each unmatched record, try to find a match in earlier data where:
*   - Municipality matches
*   - Previous year assets match current year assets of the earlier record
*   - Allow fuzzy matching with 1-2 digit tolerance
********************************************************************************

di " "
di "========================================"
di "STARTING SEQUENTIAL FUZZY MATCHING"
di "========================================"

*------------------------------------------------------------------------------
* STEP 5.1: Create matching keys from 2015-2018 (the "base" with known IDs)
*------------------------------------------------------------------------------
* These are the records we'll try to match later records to.
* For each observation, their CURRENT assets can match to future observations'
* PREVIOUS assets.

use "$CleanDataPath/all_records_combined.dta", clear

* Keep only 2015-2018 records with IDs
keep if source_file == "2015-2018"

* For matching, we need: municipality, report_year (becomes match_year for future),
* and current assets (become previous assets for future records)
keep obs_id id filename municipio_name report_year fin_cur re_cur bus_cur oth_cur

* These current assets will be matched against future records' previous assets
rename fin_cur fin_match
rename re_cur re_match
rename bus_cur bus_match
rename oth_cur oth_match
rename report_year match_year_key

save "$CleanDataPath/base_for_matching.dta", replace

di "Base records for matching (2015-2018): " _N

*------------------------------------------------------------------------------
* STEP 5.2: Create records to be matched (2019+)
*------------------------------------------------------------------------------
use "$CleanDataPath/all_records_combined.dta", clear

* Keep records without ID (need to be matched)
keep if id == "" | id == "."

* For matching, we use previous assets
keep obs_id filename municipio_name match_year report_year ///
	fin_pre re_pre bus_pre oth_pre fin_cur re_cur bus_cur oth_cur source_file

* Rename for matching
rename fin_pre fin_match
rename re_pre re_match
rename bus_pre bus_match
rename oth_pre oth_match
rename match_year match_year_key

save "$CleanDataPath/records_to_match.dta", replace

di "Records to match (2019+): " _N

*------------------------------------------------------------------------------
* STEP 5.3: EXACT MATCHING
*------------------------------------------------------------------------------
di " "
di "--- EXACT MATCHING ---"

use "$CleanDataPath/records_to_match.dta", clear

* Create unique list of base municipality + year + asset combinations
preserve
use "$CleanDataPath/base_for_matching.dta", clear
keep municipio_name match_year_key fin_match re_match bus_match oth_match id
tempfile base_unique
save `base_unique'
restore

* Join on all keys
joinby municipio_name match_year_key fin_match re_match bus_match oth_match ///
	using `base_unique', unmatched(master) _merge(_exact)

* Count matches
count if _exact == 3
local n_exact = r(N)
di "Exact matches found: `n_exact'"

* For matched records, assign the ID
replace id = "" if _exact == 1

* Handle duplicates - if multiple matches, keep first
bysort obs_id (id): gen dup = _n
keep if dup == 1
drop dup _exact

* Save exact matches
preserve
keep if id != ""
gen match_type = "exact"
gen match_confidence = 100
save "$CleanDataPath/matches_exact_full.dta", replace
di "Exact matches saved: " _N
restore

* Keep unmatched for fuzzy matching
keep if id == ""
drop id
save "$CleanDataPath/unmatched_stage1.dta", replace
di "Unmatched after exact: " _N

*------------------------------------------------------------------------------
* STEP 5.4: FUZZY MATCHING (1-2 digit tolerance)
*------------------------------------------------------------------------------
di " "
di "--- FUZZY MATCHING ---"

use "$CleanDataPath/unmatched_stage1.dta", clear

* Join on municipality and year only
joinby municipio_name match_year_key ///
	using "$CleanDataPath/base_for_matching.dta", unmatched(master) _merge(_fuzzy)

* Keep only potential matches
keep if _fuzzy == 3

* Calculate digit distance for each asset
foreach asset in fin re bus oth {
	* Absolute difference
	gen `asset'_diff = abs(`asset'_match - `asset'_match)

	* Wait - we need the base values. Let me fix this.
	* The issue is that after joinby, we have BOTH sets of values.
	* Actually joinby creates duplicate column names... need to handle this differently.
}

* This approach won't work directly. Let me restructure.
drop _all

*------------------------------------------------------------------------------
* STEP 5.4 (REVISED): FUZZY MATCHING WITH PROPER STRUCTURE
*------------------------------------------------------------------------------
di " "
di "--- FUZZY MATCHING (Revised) ---"

* Load unmatched records
use "$CleanDataPath/unmatched_stage1.dta", clear

* Rename matching variables to distinguish them
rename fin_match fin_new
rename re_match re_new
rename bus_match bus_new
rename oth_match oth_new

tempfile unmatched_renamed
save `unmatched_renamed'

* Load base records and rename their variables
use "$CleanDataPath/base_for_matching.dta", clear
rename fin_match fin_base
rename re_match re_base
rename bus_match bus_base
rename oth_match oth_base

* Join on municipality and year only (creates all candidate pairs)
joinby municipio_name match_year_key using `unmatched_renamed', unmatched(none)

di "Candidate pairs for fuzzy matching: " _N

* Calculate digit distance for each asset
foreach asset in fin re bus oth {
	gen `asset'_diff = abs(`asset'_new - `asset'_base)

	* Calculate magnitude (number of digits)
	gen `asset'_mag_new = floor(log10(max(`asset'_new, 1))) + 1
	gen `asset'_mag_base = floor(log10(max(`asset'_base, 1))) + 1
	gen `asset'_mag = max(`asset'_mag_new, `asset'_mag_base)

	* Classify digit distance
	gen `asset'_digit_dist = 0 if `asset'_diff == 0
	replace `asset'_digit_dist = 1 if `asset'_diff > 0 & `asset'_diff <= 10^(`asset'_mag - 1)
	replace `asset'_digit_dist = 2 if `asset'_diff > 10^(`asset'_mag - 1) & `asset'_diff <= 10^(`asset'_mag)
	replace `asset'_digit_dist = 99 if `asset'_diff > 10^(`asset'_mag) | `asset'_digit_dist == .

	drop `asset'_mag_new `asset'_mag_base `asset'_mag
}

* Total digit distance
gen total_digit_dist = fin_digit_dist + re_digit_dist + bus_digit_dist + oth_digit_dist

* Keep only fuzzy matches (total distance <= 4, meaning at most 2 one-digit errors per asset on average)
keep if total_digit_dist <= 4 & total_digit_dist > 0

di "Fuzzy match candidates (total_digit_dist <= 4): " _N

* Calculate confidence score
* Base 100, -5 per 1-digit error, -10 per 2-digit error
gen n_1digit = (fin_digit_dist == 1) + (re_digit_dist == 1) + (bus_digit_dist == 1) + (oth_digit_dist == 1)
gen n_2digit = (fin_digit_dist == 2) + (re_digit_dist == 2) + (bus_digit_dist == 2) + (oth_digit_dist == 2)
gen match_confidence = 100 - 5*n_1digit - 10*n_2digit

* For each unmatched record, keep best match (highest confidence, then lowest distance)
gsort obs_id -match_confidence total_digit_dist
bysort obs_id: gen rank = _n
keep if rank == 1
drop rank

* Also ensure each base ID only matches once (keep best match)
gsort id -match_confidence total_digit_dist
bysort id match_year_key: gen rank = _n
keep if rank == 1
drop rank

gen match_type = "fuzzy"

di "Final fuzzy matches: " _N

save "$CleanDataPath/matches_fuzzy_full.dta", replace

*------------------------------------------------------------------------------
* STEP 5.5: Combine all matches
*------------------------------------------------------------------------------
di " "
di "--- COMBINING MATCHES ---"

use "$CleanDataPath/matches_exact_full.dta", clear

* Keep relevant variables
keep obs_id id filename municipio_name match_year_key report_year ///
	fin_match re_match bus_match oth_match fin_cur re_cur bus_cur oth_cur ///
	source_file match_type match_confidence

append using "$CleanDataPath/matches_fuzzy_full.dta", ///
	keep(obs_id id filename municipio_name match_year_key report_year ///
	source_file match_type match_confidence)

di "Total matches: " _N

* Count by type
tab match_type

save "$CleanDataPath/all_matches_full.dta", replace

********************************************************************************
* SECTION 6: CREATE PANEL DATASET
********************************************************************************

di " "
di "========================================"
di "CREATING PANEL DATASET"
di "========================================"

* Start with all records
use "$CleanDataPath/all_records_combined.dta", clear

* Merge in matched IDs
merge 1:1 obs_id using "$CleanDataPath/all_matches_full.dta", ///
	keepusing(id match_type match_confidence) update replace

* For unmatched records without ID, use filename as panel_id
gen panel_id = id
replace panel_id = filename if panel_id == "" | panel_id == "."

* Keep panel variables
keep panel_id report_year id filename fin_cur re_cur bus_cur oth_cur source_file

* Rename assets
rename fin_cur fin
rename re_cur re
rename bus_cur bus
rename oth_cur oth

* Order and sort
order panel_id report_year id filename fin re bus oth source_file
sort panel_id report_year

* Label variables
label var panel_id "Unique person identifier"
label var report_year "Current reporting year"
label var id "Original ID from 2015-2018 file"
label var filename "Original CSV filename"
label var fin "Financial wealth"
label var re "Real estate wealth"
label var bus "Business wealth"
label var oth "Other wealth"
label var source_file "Source data file"

* Summary statistics
di " "
di "========================================"
di "PANEL DATASET SUMMARY"
di "========================================"

egen tag_panel = tag(panel_id)
count if tag_panel == 1
local n_persons = r(N)
di "Unique persons: `n_persons'"

count if id != "" & id != "."
local n_with_id = r(N)
di "Records with original ID: `n_with_id'"

count if id == "" | id == "."
local n_without_id = r(N)
di "Records without original ID: `n_without_id'"

di " "
di "Records by source file:"
tab source_file

di " "
di "Records by reporting year:"
tab report_year

drop tag_panel

save "$CleanDataPath/act22_panel_full.dta", replace

di " "
di "========================================"
di "PANEL SAVED: $CleanDataPath/act22_panel_full.dta"
di "========================================"

********************************************************************************
* END OF SCRIPT
********************************************************************************
