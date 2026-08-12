/*==============================================================================
 zip_migration_did.do

 Zip-level staggered DiD of OUTMIGRATION on investor-purchase treatment,
 mirroring design2_tract_results.do (lpdid annual, pre 4 / post 3, base +
 FE variant, dose split 5+ / 1-4 vs never-treated).

 Panel: data/experian/pr_outmigration_zip_year_treated.csv (Experian credit
 header, zip x year 2005-2022; year = t of the t->t+1 transition).
 Treatment: data/experian/zip_treatment.csv timing (first decree-era investor
 event in the ZCTA, from design1 events sjoined to 2020 ZCTA polygons).

 Outcomes (x100 = percentage points):
   rate_move_any       - moved to ANY different zip (incl. within PR)
   rate_move_off_pr    - moved off-island
   rate_move_within_pr - moved within PR
 Sample: 132 true ZCTAs only (PO-box-only USPS zips dropped: not polygons,
 untreated by construction). Robustness: cells with n_at_risk >= 20.

 Output: output/experian/zip_migration_coefs.dta (+.csv), zip_migration_results.log
==============================================================================*/

version 17
clear all
set more off

global REPO "C:/Users/mva284/Documents/GitHub/ClaudeAct2260MergeExercise"
global EXP  "$REPO/data/experian"
global OUT  "$REPO/output/experian"
capture mkdir "$REPO/output"
capture mkdir "$OUT"
global COEFTMP "$OUT/_zm_accum.dta"
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
    * runspec <yvar> <tag> [absorbvar]
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
import delimited "$EXP/pr_outmigration_zip_year_treated.csv", ///
    varnames(1) stringcols(1) clear

* keep true ZCTAs only
preserve
    import delimited "$EXP/pr_zcta_list.csv", varnames(1) stringcols(1) clear
    tempfile zctas
    save `zctas'
restore
merge m:1 zip using `zctas', keep(match) nogen

* dominant-municipio crosswalk (area-based; median dominant share 99.4%,
* 128/132 ZCTAs >= 80% in one municipio -- FE well-defined)
preserve
    import delimited "$EXP/pr_zcta_muni_crosswalk.csv", varnames(1) stringcols(1 2) clear
    tempfile muni
    save `muni'
restore
merge m:1 zip using `muni', keep(master match) nogen

replace n_events = 0 if missing(n_events)
gen treat = !missing(first_event_year) & year >= first_event_year

gen y_any    = 100 * rate_move_any
gen y_offpr  = 100 * rate_move_off_pr
gen y_within = 100 * rate_move_within_pr
gen zip3     = substr(zip, 1, 3)
egen zip_num  = group(zip)
egen zip3_num = group(zip3)
egen muni_num = group(muni_fips)

xtset zip_num year
save "$OUT/_zm_panel.dta", replace

qui count
di as result "Panel cells: " r(N)
qui su zip_num
di as result "ZCTAs in panel: " r(max)
qui su n_at_risk, detail

/*============================================================================
  ESTIMATION
============================================================================*/
log using "$OUT/zip_migration_results.log", replace text

* sample description
use "$OUT/_zm_panel.dta", clear
qui levelsof zip if n_events > 0, local(tz)
di as result "Treated ZCTAs in panel: " `:word count `tz''
tab year treat
su n_at_risk if treat == 0
su n_at_risk if treat == 1

* headline: off-island outmigration, base and zip3-FE
use "$OUT/_zm_panel.dta", clear
runspec y_offpr  T_offpr_base
use "$OUT/_zm_panel.dta", clear
runspec y_offpr  T_offpr_zip3  zip3_num
use "$OUT/_zm_panel.dta", clear
runspec y_offpr  T_offpr_muni  muni_num
* any-move (incl. within-PR)
use "$OUT/_zm_panel.dta", clear
runspec y_any    T_any_base
use "$OUT/_zm_panel.dta", clear
runspec y_any    T_any_zip3    zip3_num
use "$OUT/_zm_panel.dta", clear
runspec y_any    T_any_muni    muni_num
* within-PR decomposition
use "$OUT/_zm_panel.dta", clear
runspec y_within T_within_base
* dose: 5+ events vs never-treated
use "$OUT/_zm_panel.dta", clear
keep if n_events >= 5 | missing(first_event_year)
runspec y_offpr  T_offpr_dose5
use "$OUT/_zm_panel.dta", clear
keep if n_events >= 5 | missing(first_event_year)
runspec y_any    T_any_dose5
* dose: 1-4 events vs never-treated
use "$OUT/_zm_panel.dta", clear
keep if inrange(n_events, 1, 4) | missing(first_event_year)
runspec y_offpr  T_offpr_dose14
use "$OUT/_zm_panel.dta", clear
keep if inrange(n_events, 1, 4) | missing(first_event_year)
runspec y_any    T_any_dose14
* robustness: drop thin cells (n_at_risk < 20)
use "$OUT/_zm_panel.dta", clear
keep if n_at_risk >= 20
runspec y_offpr  T_offpr_min20
use "$OUT/_zm_panel.dta", clear
keep if n_at_risk >= 20
runspec y_any    T_any_min20

log close

use "$COEFTMP", clear
order test matrix_type row rowname
sort test matrix_type row
tab test matrix_type
save "$OUT/zip_migration_coefs.dta", replace
export delimited "$OUT/zip_migration_coefs.csv", replace
capture erase "$COEFTMP"
di as result _n "Saved: $OUT/zip_migration_coefs.dta"
