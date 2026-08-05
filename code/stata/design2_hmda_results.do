/*==============================================================================
 design2_hmda_results.do

 Tract-level DiD on HMDA mortgage originations (2018-2024), same treatment
 as design2_tract_results.do (first identified decree-era purchase in tract).

 Outcomes (counts _n and dollar volume _v), each as 100 x asinh(x) so
 zero-origination tract-years are retained:
   purch_oo    home purchases, owner-occupied
   purch_nonoo home purchases, second home / investment
   refi        rate/term refinancings
   cashout     cash-out refinancings
   total       all originations

 Panel: balanced 981 tracts x 2018-2024, zeros filled. lpdid pre 3 / post 3
 (the 7-year span cannot support deeper windows). NOTE: tracts first treated
 before 2018 are already-treated for the whole panel and identify nothing;
 estimation leans on 2018+ adopters, never-treated as controls.

 Interpretation note: decree investors are predominantly cash buyers, so HMDA
 originations proxy the FINANCED (largely local) side of the market.

 Output: output/design2/hmda_coefs.dta (+.csv), hmda_results.log
==============================================================================*/

version 17
clear all
set more off

global REPO "C:/Users/mva284/Documents/GitHub/ClaudeAct2260MergeExercise"
global D2   "$REPO/data/design2"
global OUT  "$REPO/output/design2"
capture mkdir "$OUT"
global COEFTMP "$OUT/_hmda_accum.dta"
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

/*============================================================================
  BALANCED PANEL WITH ZEROS
============================================================================*/
* universe: all 2020 PR tracts
import delimited "$REPO/data/cleaned/pr_tract_zcta_crosswalk.csv", varnames(1) clear
keep tract_geoid
duplicates drop
expand 7
bysort tract_geoid: gen year = 2017 + _n
tempfile frame
save `frame'

import delimited "$D2/hmda_tract_year.csv", varnames(1) clear
merge 1:1 tract_geoid year using `frame', nogen
foreach v in purch_oo_n purch_oo_v purch_nonoo_n purch_nonoo_v ///
             refi_n refi_v cashout_n cashout_v total_n total_v {
    replace `v' = 0 if missing(`v')
}

preserve
    import delimited "$D2/design2_tract_treatment.csv", varnames(1) clear
    tempfile trt
    save `trt'
restore
merge m:1 tract_geoid using `trt', keep(master match) nogen
gen treat = !missing(first_event_year) & year >= first_event_year

foreach v in purch_oo_n purch_oo_v purch_nonoo_n purch_nonoo_v ///
             refi_n refi_v cashout_n cashout_v total_n total_v {
    gen ihs_`v' = 100 * asinh(`v')
}
egen tract_num = group(tract_geoid)
xtset tract_num year
save "$OUT/_hmda_panel.dta", replace

/*============================================================================
  ESTIMATION
============================================================================*/
log using "$OUT/hmda_results.log", replace text

foreach v in purch_oo_n purch_oo_v purch_nonoo_n purch_nonoo_v ///
             refi_n refi_v cashout_n cashout_v total_n total_v {
    use "$OUT/_hmda_panel.dta", clear
    di as result _n "===== HMDA outcome `v' ====="
    lpdid ihs_`v', unit(tract_num) time(year) treat(treat) ///
        pre_window(3) post_window(3) nograph
    matrix E = e(results)
    grabmat E H_`v' event
    capture matrix P = e(pooled_results)
    if !_rc grabmat P H_`v' pooled
}

log close

use "$COEFTMP", clear
order test matrix_type row rowname
sort test matrix_type row
tab test matrix_type
save "$OUT/hmda_coefs.dta", replace
export delimited "$OUT/hmda_coefs.csv", replace
capture erase "$COEFTMP"
capture erase "$OUT/_hmda_panel.dta"
di as result _n "Saved: $OUT/hmda_coefs.dta"
