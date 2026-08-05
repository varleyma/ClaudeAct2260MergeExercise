/*==============================================================================
 design2_hmda_poisson.do

 Poisson (ppmlhdfe) event studies for HMDA origination COUNTS at tract level
 -- the appropriate model for zero-heavy counts, replacing asinh+lpdid.

 Spec per outcome y (counts):
     ppmlhdfe y  D[-3] D[-2] D0 D1 D2 D3 , absorb(tract year) cluster(tract)
 with rel time binned at the endpoints (<=-3 -> D[-3], >=3 -> D3), base = -1,
 never-treated tracts as controls; plus a pooled version with a single post
 dummy. Coefficients x100 ~ percent effects.

 CAVEAT: TWFE event study under staggered adoption (most adopters 2020-22,
 never-treated majority) -- acceptable second pass, noted in output.

 Outcomes: purch_oo_n, purch_nonoo_n, refi_n, cashout_n, total_n
 Output:   output/design2/hmda_pois_coefs.csv, hmda_poisson.log
==============================================================================*/

version 17
clear all
set more off

global REPO "C:/Users/mva284/Documents/GitHub/ClaudeAct2260MergeExercise"
global D2   "$REPO/data/design2"
global OUT  "$REPO/output/design2"
capture mkdir "$OUT"

capture which ppmlhdfe
if _rc ssc install ppmlhdfe, replace
capture which reghdfe
if _rc ssc install reghdfe, replace
capture which ftools
if _rc ssc install ftools, replace

/*============================================================================
  PANEL (same construction as design2_hmda_results.do)
============================================================================*/
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

gen treat = !missing(first_event_year) & year >= first_event_year
gen rel = year - first_event_year if !missing(first_event_year)

* binned event-time dummies, base = -1, never-treated all zero
gen Dm3 = !missing(rel) & rel <= -3
gen Dm2 = !missing(rel) & rel == -2
gen D0  = !missing(rel) & rel == 0
gen D1  = !missing(rel) & rel == 1
gen D2  = !missing(rel) & rel == 2
gen D3  = !missing(rel) & rel >= 3

egen tract_num = group(tract_geoid)

log using "$OUT/hmda_poisson.log", replace text

tempname pf
postfile `pf' str20 outcome double h b se using "$OUT/_hmda_pois.dta", replace

foreach v in purch_oo_n purch_nonoo_n refi_n cashout_n total_n {
    di as result _n "===== POISSON event study: `v' ====="
    ppmlhdfe `v' Dm3 Dm2 D0 D1 D2 D3, absorb(tract_num year) vce(cluster tract_num)
    post `pf' ("`v'") (-3) (_b[Dm3]) (_se[Dm3])
    post `pf' ("`v'") (-2) (_b[Dm2]) (_se[Dm2])
    post `pf' ("`v'") (-1) (0) (.)
    post `pf' ("`v'") (0)  (_b[D0]) (_se[D0])
    post `pf' ("`v'") (1)  (_b[D1]) (_se[D1])
    post `pf' ("`v'") (2)  (_b[D2]) (_se[D2])
    post `pf' ("`v'") (3)  (_b[D3]) (_se[D3])

    di as result _n "===== POISSON pooled post: `v' ====="
    ppmlhdfe `v' treat, absorb(tract_num year) vce(cluster tract_num)
    post `pf' ("`v'") (99) (_b[treat]) (_se[treat])
}

postclose `pf'
log close

use "$OUT/_hmda_pois.dta", clear
gen lb = b - 1.96*se
gen ub = b + 1.96*se
export delimited "$OUT/hmda_pois_coefs.csv", replace
capture erase "$OUT/_hmda_pois.dta"
di as result _n "Saved: $OUT/hmda_pois_coefs.csv  (h=99 rows are pooled post)"
