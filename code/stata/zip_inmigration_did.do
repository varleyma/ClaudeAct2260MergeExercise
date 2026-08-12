/*==============================================================================
 zip_inmigration_did.do

 Zip-level staggered DiD of IN-MIGRATION on investor-purchase treatment.
 Same design as zip_migration_did.do (lpdid annual, pre 4 / post 3, 132 true
 ZCTAs, dose splits, municipio FE via dominant-muni crosswalk).

 Panel: data/experian/pr_inmigration_zip_year_treated.csv (arrival years
 2006-2023; rates = consecutive-year arrivals / stock; new credit files and
 gap-reappearances excluded from rates).
 Outcomes (x100 = pp): rate_in_any, rate_in_off_island, rate_in_within_pr.

 Output: output/experian/zip_inmigration_coefs.dta (+.csv),
         zip_inmigration_results.log
==============================================================================*/

version 17
clear all
set more off

global REPO "C:/Users/mva284/Documents/GitHub/ClaudeAct2260MergeExercise"
global EXP  "$REPO/data/experian"
global OUT  "$REPO/output/experian"
capture mkdir "$OUT"
global COEFTMP "$OUT/_zi_accum.dta"
capture erase "$COEFTMP"

capture which lpdid
if _rc ssc install lpdid, replace

capture program drop grabmat
program define grabmat
    args M test mtype
    local rn : rowfullnames `M'
    local nr = rowsof(`M')
    preserve
    clear
    qui svmat double `M', names(c)
    qui gen row = _n
    qui gen str32 rowname = ""
    forvalues i = 1/`nr' {
        local r : word `i' of `rn'
        qui replace rowname = "`r'" in `i'
    }
    qui gen str40 test = "`test'"
    qui gen str10 matrix_type = "`mtype'"
    capture confirm file "$COEFTMP"
    if !_rc qui append using "$COEFTMP"
    qui save "$COEFTMP", replace
    restore
end

capture program drop runspec
program define runspec
    args yvar tag absorbvar
    local abs
    if "`absorbvar'" != "" local abs "absorb(`absorbvar')"
    di as result _n "===== lpdid [`tag'] outcome=`yvar' `abs' ====="
    lpdid `yvar', unit(zip_num) time(year) treat(treat) ///
        pre_window(4) post_window(3) nograph `abs'
    matrix E = e(results)
    grabmat E `tag' event
    capture matrix P = e(pooled_results)
    if !_rc grabmat P `tag' pooled
end

/*============================================================================
  BUILD PANEL
============================================================================*/
import delimited "$EXP/pr_inmigration_zip_year_treated.csv", ///
    varnames(1) stringcols(1) clear
drop if year == 2005    // no prior year observable

preserve
    import delimited "$EXP/pr_zcta_list.csv", varnames(1) stringcols(1) clear
    tempfile zctas
    save `zctas'
restore
merge m:1 zip using `zctas', keep(match) nogen

preserve
    import delimited "$EXP/pr_zcta_muni_crosswalk.csv", varnames(1) stringcols(1 2) clear
    tempfile muni
    save `muni'
restore
merge m:1 zip using `muni', keep(master match) nogen

replace n_events = 0 if missing(n_events)
gen treat = !missing(first_event_year) & year >= first_event_year

gen y_any    = 100 * rate_in_any
gen y_offisl = 100 * rate_in_off_island
gen y_within = 100 * rate_in_within_pr
gen zip3     = substr(zip, 1, 3)
egen zip_num  = group(zip)
egen zip3_num = group(zip3)
egen muni_num = group(muni_fips)

xtset zip_num year
save "$OUT/_zi_panel.dta", replace

/*============================================================================
  ESTIMATION
============================================================================*/
log using "$OUT/zip_inmigration_results.log", replace text

use "$OUT/_zi_panel.dta", clear
qui count
di as result "Panel cells: " r(N)
tab year treat

* headline: off-island in-migration (the Act-60-adjacent inflow)
use "$OUT/_zi_panel.dta", clear
runspec y_offisl T_ioff_base
use "$OUT/_zi_panel.dta", clear
runspec y_offisl T_ioff_muni  muni_num
* any-origin arrivals
use "$OUT/_zi_panel.dta", clear
runspec y_any    T_iany_base
use "$OUT/_zi_panel.dta", clear
runspec y_any    T_iany_muni  muni_num
* within-PR arrivals
use "$OUT/_zi_panel.dta", clear
runspec y_within T_iwithin_base
* dose: 5+ vs never-treated
use "$OUT/_zi_panel.dta", clear
keep if n_events >= 5 | missing(first_event_year)
runspec y_offisl T_ioff_dose5
use "$OUT/_zi_panel.dta", clear
keep if n_events >= 5 | missing(first_event_year)
runspec y_any    T_iany_dose5
* dose: 1-4 vs never-treated
use "$OUT/_zi_panel.dta", clear
keep if inrange(n_events, 1, 4) | missing(first_event_year)
runspec y_offisl T_ioff_dose14
use "$OUT/_zi_panel.dta", clear
keep if inrange(n_events, 1, 4) | missing(first_event_year)
runspec y_any    T_iany_dose14
* robustness: drop thin cells
use "$OUT/_zi_panel.dta", clear
keep if n_stock >= 20
runspec y_offisl T_ioff_min20
use "$OUT/_zi_panel.dta", clear
keep if n_stock >= 20
runspec y_any    T_iany_min20

log close

use "$COEFTMP", clear
order test matrix_type row rowname
sort test matrix_type row
tab test matrix_type
save "$OUT/zip_inmigration_coefs.dta", replace
export delimited "$OUT/zip_inmigration_coefs.csv", replace
capture erase "$COEFTMP"
di as result _n "Saved: $OUT/zip_inmigration_coefs.dta"
