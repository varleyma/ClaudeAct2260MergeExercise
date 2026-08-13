/*==============================================================================
 design2_hmda_refi.do

 Refinancing DiD by borrower ethnicity -- the equity-extraction margin: do
 incumbent (overwhelmingly Hispanic) owners in treated tracts monetize the
 appreciation? Same population as the long purchase panel (originated
 first-lien owner-occupied 1-4 family).

   A. ALL refis by ethnicity, 2012-2024 (historic purpose 3 + modern 31/32):
      ppmlhdfe refi_{hisp,nonhisp}_n, ES -4..+3 (binned endpoints) + pooled
   B. CASH-OUT vs RATE/TERM refis by ethnicity, 2018-2024 only (the split
      does not exist in pre-2018 HMDA): same specs on the short window

 Outputs: output/design2/hmda_refi_coefs.csv (test,h,b,se,lb,ub),
          hmda_refi.log
==============================================================================*/

version 17
clear all
set more off

global REPO "C:/Users/mva284/Documents/GitHub/ClaudeAct2260MergeExercise"
global D2   "$REPO/data/design2"
global OUT  "$REPO/output/design2"

capture which ppmlhdfe
if _rc ssc install ppmlhdfe, replace

import delimited "$REPO/data/cleaned/pr_tract_zcta_crosswalk.csv", varnames(1) clear
keep tract_geoid
duplicates drop
expand 13
bysort tract_geoid: gen year = 2011 + _n
tempfile frame
save `frame'

import delimited "$D2/hmda_tract_year_long.csv", varnames(1) clear
merge 1:1 tract_geoid year using `frame', nogen
foreach v in refi_n refi_hisp_n refi_nonhisp_n ///
             cashout_hisp_n cashout_nonhisp_n refirt_hisp_n refirt_nonhisp_n {
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
local DVARS Dm4 Dm3 Dm2 D0 D1 D2 D3

egen tract_num = group(tract_geoid)
tempfile panel
save `panel'

log using "$OUT/hmda_refi.log", replace text

tempname pf
postfile `pf' str20 test double h b se using "$OUT/_hr.dta", replace

capture program drop grabes
program define grabes
    args pf test
    post `pf' ("`test'") (-4) (_b[Dm4]) (_se[Dm4])
    post `pf' ("`test'") (-3) (_b[Dm3]) (_se[Dm3])
    post `pf' ("`test'") (-2) (_b[Dm2]) (_se[Dm2])
    post `pf' ("`test'") (-1) (0) (.)
    post `pf' ("`test'") (0)  (_b[D0]) (_se[D0])
    post `pf' ("`test'") (1)  (_b[D1]) (_se[D1])
    post `pf' ("`test'") (2)  (_b[D2]) (_se[D2])
    post `pf' ("`test'") (3)  (_b[D3]) (_se[D3])
end

*---- A. all refis, 2012-2024 -------------------------------------------------
foreach v in refi_hisp_n refi_nonhisp_n {
    use `panel', clear
    di as result _n "===== POISSON `v' (2012-2024) ====="
    ppmlhdfe `v' `DVARS', absorb(tract_num year) vce(cluster tract_num)
    grabes `pf' `v'
    di as result _n "===== POISSON pooled `v' ====="
    ppmlhdfe `v' treat, absorb(tract_num year) vce(cluster tract_num)
    post `pf' ("`v'") (99) (_b[treat]) (_se[treat])
}

*---- B. cash-out vs rate/term, 2018-2024 only --------------------------------
foreach v in cashout_hisp_n cashout_nonhisp_n refirt_hisp_n refirt_nonhisp_n {
    use `panel', clear
    keep if year >= 2018
    di as result _n "===== POISSON `v' (2018-2024) ====="
    ppmlhdfe `v' `DVARS', absorb(tract_num year) vce(cluster tract_num)
    grabes `pf' `v'
    di as result _n "===== POISSON pooled `v' ====="
    ppmlhdfe `v' treat, absorb(tract_num year) vce(cluster tract_num)
    post `pf' ("`v'") (99) (_b[treat]) (_se[treat])
}

postclose `pf'
log close

use "$OUT/_hr.dta", clear
gen lb = b - 1.96*se
gen ub = b + 1.96*se
export delimited "$OUT/hmda_refi_coefs.csv", replace
capture erase "$OUT/_hr.dta"
di as result "Saved: $OUT/hmda_refi_coefs.csv  (h=99 rows are pooled post)"
