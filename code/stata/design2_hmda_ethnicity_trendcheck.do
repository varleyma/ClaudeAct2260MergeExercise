/*==============================================================================
 design2_hmda_ethnicity_trendcheck.do

 Pre-trend stress test for the borrower-income result: the event-study pre
 coefficients climb monotonically (-4.5, -3.5, 0), so rerun the pooled and
 event-study income specs WITH TRACT-SPECIFIC LINEAR TRENDS. Surviving
 effect = income jump beyond each tract's own income trajectory.

 Output: appended results in hmda_eth_trendcheck.log,
         output/design2/hmda_eth_trend_coefs.csv
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
foreach v in purch_hisp_inc purch_hisp_incn purch_nonhisp_inc purch_nonhisp_incn {
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
gen Dm4 = !missing(rel) & rel <= -4
gen Dm3 = !missing(rel) & rel == -3
gen Dm2 = !missing(rel) & rel == -2
gen D0  = !missing(rel) & rel == 0
gen D1  = !missing(rel) & rel == 1
gen D2  = !missing(rel) & rel == 2
gen D3  = !missing(rel) & rel >= 3

gen lninc_all  = 100 * ln((purch_hisp_inc + purch_nonhisp_inc) / ///
                          (purch_hisp_incn + purch_nonhisp_incn)) ///
                 if purch_hisp_incn + purch_nonhisp_incn > 0
gen lninc_hisp = 100 * ln(purch_hisp_inc / purch_hisp_incn) if purch_hisp_incn > 0

egen tract_num = group(tract_geoid)

log using "$OUT/hmda_eth_trendcheck.log", replace text

tempname pf
postfile `pf' str20 outcome double h b se using "$OUT/_eth_trend.dta", replace

foreach v in lninc_all lninc_hisp {
    di as result _n "===== `v': BASELINE (tract + year FE) pooled ====="
    reghdfe `v' treat, absorb(tract_num year) vce(cluster tract_num)

    di as result _n "===== `v': + tract-specific linear trends, pooled ====="
    reghdfe `v' treat, absorb(tract_num year tract_num#c.year) vce(cluster tract_num)
    post `pf' ("`v'") (99) (_b[treat]) (_se[treat])

    di as result _n "===== `v': + tract-specific linear trends, event study ====="
    reghdfe `v' Dm4 Dm3 Dm2 D0 D1 D2 D3, absorb(tract_num year tract_num#c.year) ///
        vce(cluster tract_num)
    post `pf' ("`v'") (-4) (_b[Dm4]) (_se[Dm4])
    post `pf' ("`v'") (-3) (_b[Dm3]) (_se[Dm3])
    post `pf' ("`v'") (-2) (_b[Dm2]) (_se[Dm2])
    post `pf' ("`v'") (-1) (0) (.)
    post `pf' ("`v'") (0)  (_b[D0]) (_se[D0])
    post `pf' ("`v'") (1)  (_b[D1]) (_se[D1])
    post `pf' ("`v'") (2)  (_b[D2]) (_se[D2])
    post `pf' ("`v'") (3)  (_b[D3]) (_se[D3])
}

postclose `pf'
log close

use "$OUT/_eth_trend.dta", clear
export delimited "$OUT/hmda_eth_trend_coefs.csv", replace
capture erase "$OUT/_eth_trend.dta"
di as result "Saved: $OUT/hmda_eth_trend_coefs.csv"
