/*==============================================================================
 design2_hmda_long.do

 Borrower-composition DiD on the LONG HMDA panel (2012-2024, consistent
 population: originated first-lien owner-occupied 1-4 family purchases).
 Pre window now reaches -6 (binned endpoint), giving real pre-period support
 for the early-adopting high-dose tracts.

   A. counts by ethnicity (ppmlhdfe): purch_hisp_n, purch_nonhisp_n
   B. borrower income (reghdfe, 100 x ln mean income): all + Hispanic-only
   C. income dose split: tracts with 5+ purchases vs 1-4, each vs never-treated

 Outputs: output/design2/hmda_long_coefs.csv (test,h,b,se,lb,ub),
          hmda_long.log
==============================================================================*/

version 17
clear all
set more off

global REPO "C:/Users/mva284/Documents/GitHub/ClaudeAct2260MergeExercise"
global D2   "$REPO/data/design2"
global OUT  "$REPO/output/design2"

capture which ppmlhdfe
if _rc ssc install ppmlhdfe, replace
capture which reghdfe
if _rc ssc install reghdfe, replace

import delimited "$REPO/data/cleaned/pr_tract_zcta_crosswalk.csv", varnames(1) clear
keep tract_geoid
duplicates drop
expand 13
bysort tract_geoid: gen year = 2011 + _n
tempfile frame
save `frame'

import delimited "$D2/hmda_tract_year_long.csv", varnames(1) clear
merge 1:1 tract_geoid year using `frame', nogen
foreach v in purch_n purch_hisp_n purch_hisp_inc purch_hisp_incn ///
             purch_nonhisp_n purch_nonhisp_inc purch_nonhisp_incn {
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

gen Dm6 = !missing(rel) & rel <= -6
gen Dm5 = !missing(rel) & rel == -5
gen Dm4 = !missing(rel) & rel == -4
gen Dm3 = !missing(rel) & rel == -3
gen Dm2 = !missing(rel) & rel == -2
gen D0  = !missing(rel) & rel == 0
gen D1  = !missing(rel) & rel == 1
gen D2  = !missing(rel) & rel == 2
gen D3  = !missing(rel) & rel >= 3
local DVARS Dm6 Dm5 Dm4 Dm3 Dm2 D0 D1 D2 D3

gen lninc_all  = 100 * ln((purch_hisp_inc + purch_nonhisp_inc) / ///
                          (purch_hisp_incn + purch_nonhisp_incn)) ///
                 if purch_hisp_incn + purch_nonhisp_incn > 0
gen lninc_hisp = 100 * ln(purch_hisp_inc / purch_hisp_incn) if purch_hisp_incn > 0

egen tract_num = group(tract_geoid)
gen nevertr = missing(first_event_year)
tempfile panel
save `panel'

log using "$OUT/hmda_long.log", replace text

tempname pf
postfile `pf' str20 test double h b se using "$OUT/_hl.dta", replace

capture program drop grabes
program define grabes
    args pf test
    post `pf' ("`test'") (-6) (_b[Dm6]) (_se[Dm6])
    post `pf' ("`test'") (-5) (_b[Dm5]) (_se[Dm5])
    post `pf' ("`test'") (-4) (_b[Dm4]) (_se[Dm4])
    post `pf' ("`test'") (-3) (_b[Dm3]) (_se[Dm3])
    post `pf' ("`test'") (-2) (_b[Dm2]) (_se[Dm2])
    post `pf' ("`test'") (-1) (0) (.)
    post `pf' ("`test'") (0)  (_b[D0]) (_se[D0])
    post `pf' ("`test'") (1)  (_b[D1]) (_se[D1])
    post `pf' ("`test'") (2)  (_b[D2]) (_se[D2])
    post `pf' ("`test'") (3)  (_b[D3]) (_se[D3])
end

*---- A. counts by ethnicity --------------------------------------------------
foreach v in purch_hisp_n purch_nonhisp_n {
    use `panel', clear
    di as result _n "===== POISSON `v' (2012-2024) ====="
    ppmlhdfe `v' `DVARS', absorb(tract_num year) vce(cluster tract_num)
    grabes `pf' `v'
    di as result _n "===== POISSON pooled `v' ====="
    ppmlhdfe `v' treat, absorb(tract_num year) vce(cluster tract_num)
    post `pf' ("`v'") (99) (_b[treat]) (_se[treat])
}

*---- B. borrower income ------------------------------------------------------
foreach v in lninc_all lninc_hisp {
    use `panel', clear
    di as result _n "===== OLS `v' (2012-2024) ====="
    reghdfe `v' `DVARS', absorb(tract_num year) vce(cluster tract_num)
    grabes `pf' `v'
    di as result _n "===== OLS pooled `v' ====="
    reghdfe `v' treat, absorb(tract_num year) vce(cluster tract_num)
    post `pf' ("`v'") (99) (_b[treat]) (_se[treat])
}

*---- C. income dose ----------------------------------------------------------
foreach g in hi5 lo14 {
    use `panel', clear
    if "`g'" == "hi5"  keep if nevertr | n_events >= 5
    if "`g'" == "lo14" keep if nevertr | inrange(n_events, 1, 4)
    di as result _n "===== OLS lninc_all dose `g' (2012-2024) ====="
    reghdfe lninc_all `DVARS', absorb(tract_num year) vce(cluster tract_num)
    grabes `pf' inc_`g'
    di as result _n "===== OLS pooled lninc_all dose `g' ====="
    reghdfe lninc_all treat, absorb(tract_num year) vce(cluster tract_num)
    post `pf' ("inc_`g'") (99) (_b[treat]) (_se[treat])
}

postclose `pf'
log close

use "$OUT/_hl.dta", clear
gen lb = b - 1.96*se
gen ub = b + 1.96*se
export delimited "$OUT/hmda_long_coefs.csv", replace
capture erase "$OUT/_hl.dta"
di as result "Saved: $OUT/hmda_long_coefs.csv  (h=99 rows are pooled post)"
