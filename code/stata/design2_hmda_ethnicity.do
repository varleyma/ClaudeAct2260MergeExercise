/*==============================================================================
 design2_hmda_ethnicity.do

 Borrower-composition DiD on HMDA PURCHASE originations, split by
 self-reported derived_ethnicity (Hispanic or Latino vs Not; Joint and
 Not Available excluded). Direct displacement evidence on the buyer margin:
 does Hispanic purchase lending fall (locals exiting the market) and does
 non-Hispanic lending rise in treated tracts?

 Counts: ppmlhdfe event study + pooled post (same spec as
 design2_hmda_poisson.do: binned rel time, base -1, absorb(tract year),
 cluster tract, never-treated controls).
 Income: reghdfe on 100 x ln(mean borrower income) of purchase borrowers
 (all classified, and Hispanic-only), tract-years with any income reports.

 CAVEAT: HMDA covers financed purchases only -- decree investors buy in cash,
 so these are the LOCAL (financed) side of the market. PR borrowers are ~94%
 Hispanic; non-Hispanic counts are thin (island total a few hundred/yr).

 Outputs: output/design2/hmda_eth_coefs.csv, hmda_ethnicity.log
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

/*============================================================================
  PANEL (same construction as design2_hmda_poisson.do)
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
foreach v in purch_hisp_n purch_hisp_inc purch_hisp_incn ///
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

gen Dm3 = !missing(rel) & rel <= -3
gen Dm2 = !missing(rel) & rel == -2
gen D0  = !missing(rel) & rel == 0
gen D1  = !missing(rel) & rel == 1
gen D2  = !missing(rel) & rel == 2
gen D3  = !missing(rel) & rel >= 3

* borrower mean income (HMDA income is in $000s), 100 x ln
gen lninc_all  = 100 * ln((purch_hisp_inc + purch_nonhisp_inc) / ///
                          (purch_hisp_incn + purch_nonhisp_incn)) ///
                 if purch_hisp_incn + purch_nonhisp_incn > 0
gen lninc_hisp = 100 * ln(purch_hisp_inc / purch_hisp_incn) if purch_hisp_incn > 0

egen tract_num = group(tract_geoid)

log using "$OUT/hmda_ethnicity.log", replace text

tempname pf
postfile `pf' str20 outcome double h b se using "$OUT/_hmda_eth.dta", replace

*---- counts: Poisson ---------------------------------------------------------
foreach v in purch_hisp_n purch_nonhisp_n {
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

*---- borrower income: OLS on 100 x ln(mean income) ---------------------------
foreach v in lninc_all lninc_hisp {
    di as result _n "===== OLS event study: `v' ====="
    reghdfe `v' Dm3 Dm2 D0 D1 D2 D3, absorb(tract_num year) vce(cluster tract_num)
    post `pf' ("`v'") (-3) (_b[Dm3]) (_se[Dm3])
    post `pf' ("`v'") (-2) (_b[Dm2]) (_se[Dm2])
    post `pf' ("`v'") (-1) (0) (.)
    post `pf' ("`v'") (0)  (_b[D0]) (_se[D0])
    post `pf' ("`v'") (1)  (_b[D1]) (_se[D1])
    post `pf' ("`v'") (2)  (_b[D2]) (_se[D2])
    post `pf' ("`v'") (3)  (_b[D3]) (_se[D3])

    di as result _n "===== OLS pooled post: `v' ====="
    reghdfe `v' treat, absorb(tract_num year) vce(cluster tract_num)
    post `pf' ("`v'") (99) (_b[treat]) (_se[treat])
}

postclose `pf'
log close

use "$OUT/_hmda_eth.dta", clear
gen lb = b - 1.96*se
gen ub = b + 1.96*se
export delimited "$OUT/hmda_eth_coefs.csv", replace
capture erase "$OUT/_hmda_eth.dta"
di as result _n "Saved: $OUT/hmda_eth_coefs.csv  (h=99 rows are pooled post)"
