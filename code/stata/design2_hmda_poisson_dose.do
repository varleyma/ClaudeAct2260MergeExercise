/*==============================================================================
 design2_hmda_poisson_dose.do

 High-dose variant of design2_hmda_poisson.do: 5+ purchase tracts (n=44)
 vs never-treated only. Pooled post + event-time dummies per count outcome.
 Output: output/design2/hmda_pois_dose_coefs.csv
==============================================================================*/

version 17
clear all
set more off

global REPO "C:/Users/mva284/Documents/GitHub/ClaudeAct2260MergeExercise"
global D2   "$REPO/data/design2"
global OUT  "$REPO/output/design2"

import delimited "$REPO/data/cleaned/pr_tract_zcta_crosswalk.csv", varnames(1) clear
keep tract_geoid
duplicates drop
expand 7
bysort tract_geoid: gen year = 2017 + _n
tempfile frame
save `frame'

import delimited "$D2/hmda_tract_year.csv", varnames(1) clear
merge 1:1 tract_geoid year using `frame', nogen
foreach v in purch_oo_n purch_nonoo_n refi_n cashout_n total_n {
    replace `v' = 0 if missing(`v')
}
preserve
    import delimited "$D2/design2_tract_treatment.csv", varnames(1) clear
    tempfile trt
    save `trt'
restore
merge m:1 tract_geoid using `trt', keep(master match) nogen
replace n_events = 0 if missing(n_events)

* high-dose treated vs never-treated
keep if n_events >= 5 | missing(first_event_year)

gen treat = !missing(first_event_year) & year >= first_event_year
gen rel = year - first_event_year if !missing(first_event_year)
gen Dm3 = !missing(rel) & rel <= -3
gen Dm2 = !missing(rel) & rel == -2
gen D0  = !missing(rel) & rel == 0
gen D1  = !missing(rel) & rel == 1
gen D2  = !missing(rel) & rel == 2
gen D3  = !missing(rel) & rel >= 3
egen tract_num = group(tract_geoid)

log using "$OUT/hmda_poisson_dose.log", replace text

tempname pf
postfile `pf' str20 outcome double h b se using "$OUT/_hp_dose.dta", replace
foreach v in purch_oo_n purch_nonoo_n refi_n cashout_n total_n {
    di as result _n "===== POISSON 5+ dose: `v' ====="
    capture noisily ppmlhdfe `v' Dm3 Dm2 D0 D1 D2 D3, absorb(tract_num year) vce(cluster tract_num)
    if !_rc {
        foreach spec in "Dm3 -3" "Dm2 -2" "D0 0" "D1 1" "D2 2" "D3 3" {
            local nm : word 1 of `spec'
            local hh : word 2 of `spec'
            post `pf' ("`v'") (`hh') (_b[`nm']) (_se[`nm'])
        }
    }
    capture noisily ppmlhdfe `v' treat, absorb(tract_num year) vce(cluster tract_num)
    if !_rc post `pf' ("`v'") (99) (_b[treat]) (_se[treat])
}
postclose `pf'
log close

use "$OUT/_hp_dose.dta", clear
export delimited "$OUT/hmda_pois_dose_coefs.csv", replace
capture erase "$OUT/_hp_dose.dta"
di as result "Saved: $OUT/hmda_pois_dose_coefs.csv"
