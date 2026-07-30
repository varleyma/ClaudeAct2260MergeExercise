/*==============================================================================
 design2_tract_results.do

 Tract-level staggered DiD (Design 2), building on ana_tract.do (Msall/Varley)
 with three changes:
   1. Treatment timing from DATED DECREE-ERA events (design2_tract_treatment.csv,
      derived from design1_events.csv, events >= 2012) -- not raw parcel sales,
      whose dates can predate the program.
   2. Annual price = transaction-count-weighted mean of the Red Atlas monthly
      tract means (reduces composition noise; simple mean kept as robustness).
   3. Saves all coefficients to design2_coefs.dta and merges the ring-implied
      per-tract predictions for the RECONCILIATION test:
         tract-DiD estimate vs what micro-spillover integration predicts.

 Outcomes: lnhp (100 x ln price), lnsales. Specs: lpdid annual, pre 4 / post 3,
 base and county-FE (absorb(fips)); dose split (tracts with >= 5 events).

 Inputs: Dropbox Ley60PR Red Atlas monthly tract data (READ ONLY),
         data/design2/design2_tract_treatment.csv, design2_ring_prediction.csv
 Output: output/design2/design2_coefs.dta (+.csv), design2_results.log
==============================================================================*/

version 17
clear all
set more off

global REPO "C:/Users/mva284/Documents/GitHub/ClaudeAct2260MergeExercise"
global D2   "$REPO/data/design2"
global OUT  "$REPO/output/design2"
global REDATLAS "C:/Users/mva284/Dropbox/Ley60PR/data/clean/monthly_data_red_atlas.csv"
capture mkdir "$REPO/output"
capture mkdir "$OUT"
global COEFTMP "$OUT/_d2_accum.dta"
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
    lpdid `yvar', unit(tract_num) time(year) treat(treat) ///
        pre_window(4) post_window(3) nograph `abs'
    matrix E = e(results)
    grabmat E `tag' event
    capture matrix P = e(pooled_results)
    if !_rc grabmat P `tag' pooled
end

/*============================================================================
  BUILD ANNUAL TRACT PANEL
============================================================================*/
import delimited "$REDATLAS", varnames(1) clear
keep geotractid month meantransactionpricepertract ///
    mediantransactionpricepertract numberoftransactions
rename geotractid tract_geoid
rename meantransactionpricepertract p_mean
rename mediantransactionpricepertract p_median
rename numberoftransactions n_sales
destring p_mean p_median n_sales, replace force
gen year = real(substr(month, 1, 4))
drop if missing(p_mean) | missing(n_sales) | n_sales <= 0

* transaction-count-weighted annual mean price (+ simple mean, median-of-medians)
gen pw = p_mean * n_sales
collapse (sum) pw n_sales (mean) p_mean_simple = p_mean ///
    (median) p_median, by(tract_geoid year)
gen p_wtd = pw / n_sales
drop pw

* treatment timing + dose (identified decree-era events)
preserve
    import delimited "$D2/design2_tract_treatment.csv", varnames(1) clear
    tempfile trt
    save `trt'
restore
merge m:1 tract_geoid using `trt', keep(master match) nogen
replace n_events = 0 if missing(n_events)
gen treat = !missing(first_event_year) & year >= first_event_year

* ring-implied predictions (for the reconciliation, merged for later use)
preserve
    import delimited "$D2/design2_ring_prediction.csv", varnames(1) clear
    tempfile pred
    save `pred'
restore
merge m:1 tract_geoid using `pred', keep(master match) nogen

gen lnhp    = 100 * ln(p_wtd)
gen lnhp_s  = 100 * ln(p_mean_simple)
gen lnsales = 100 * ln(n_sales)
gen fips    = floor(tract_geoid / 1000000)
egen tract_num = group(tract_geoid)

xtset tract_num year
save "$OUT/_d2_panel.dta", replace

/*============================================================================
  ESTIMATION
============================================================================*/
log using "$OUT/design2_results.log", replace text

* headline: weighted price, base and county-FE
use "$OUT/_d2_panel.dta", clear
runspec lnhp   T_lnhp_base
use "$OUT/_d2_panel.dta", clear
runspec lnhp   T_lnhp_fips  fips
* simple-mean robustness (their original construction)
use "$OUT/_d2_panel.dta", clear
runspec lnhp_s T_lnhpsimple_base
* volume
use "$OUT/_d2_panel.dta", clear
runspec lnsales T_lnsales_base
* dose: high-dose treated (>=5 events) vs never-treated only
use "$OUT/_d2_panel.dta", clear
keep if n_events >= 5 | missing(first_event_year)
runspec lnhp   T_lnhp_dose5
* low-dose treated (1-4 events) vs never-treated
use "$OUT/_d2_panel.dta", clear
keep if inrange(n_events, 1, 4) | missing(first_event_year)
runspec lnhp   T_lnhp_dose14

/*============================================================================
  RECONCILIATION: tract DiD vs ring-implied prediction
============================================================================*/
use "$OUT/_d2_panel.dta", clear
keep if !missing(first_event_year)
collapse (first) pred_central_vw pred_conserv_vw n_events, by(tract_geoid)
qui su pred_central_vw
local pc = 100 * r(mean)
qui su pred_conserv_vw
local pk = 100 * r(mean)
di as result _n "===== RECONCILIATION BENCHMARK ====="
di as result "Ring-implied predicted tract effect (mean over treated tracts):"
di as result "  central profile:      " %5.2f `pc' " log points"
di as result "  conservative profile: " %5.2f `pk' " log points"
di as result "Compare to the pooled Post estimates for T_lnhp_base / T_lnhp_fips above."
di as result "Tract estimate >> prediction  => market-level channel beyond proximity."

log close

use "$COEFTMP", clear
order test matrix_type row rowname
sort test matrix_type row
tab test matrix_type
save "$OUT/design2_coefs.dta", replace
export delimited "$OUT/design2_coefs.csv", replace
capture erase "$COEFTMP"
di as result _n "Saved: $OUT/design2_coefs.dta"
