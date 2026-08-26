/*==============================================================================
 design2_entity_did_robust.do

 Robustness for the rel==0 blip in the portfolio-purchase tract DiD. The
 blip is a handful of single-building/resort acquisitions coinciding with
 treatment onset (Cobian Plaza 2014 = 74% of all rel==0 portfolio
 purchases alone). Checks, each as a LEVELS event study (-4..+3, binned):

   (1) baseline (as figE3b)
   (2) drop the 5 tracts whose onset-year bulk events drive the blip
   (3) extensive margin: 1{any portfolio purchase} (LPM)
   (4) capped counts: min(port10_n, 3)

 Output: output/design2/entity_did_robust_coefs.csv, entity_did_robust.log
==============================================================================*/

version 17
clear all
set more off

global REPO "C:/Users/mva284/Documents/GitHub/ClaudeAct2260MergeExercise"
global D2   "$REPO/data/design2"
global OUT  "$REPO/output/design2"

capture which reghdfe
if _rc ssc install reghdfe, replace

* onset-year bulk-event tracts (entity_t0_diagnostic.py, top 5 = 88% of blip)
global BLIPTRACTS 72127001600 72053150601 72127002100 72023830606 72095951400

import delimited "$REPO/data/cleaned/pr_tract_zcta_crosswalk.csv", varnames(1) stringcols(1) clear
keep tract_geoid
duplicates drop
expand 14
bysort tract_geoid: gen year = 2011 + _n
tempfile frame
save `frame'

import delimited "$D2/entity_tract_year.csv", varnames(1) stringcols(1) clear
keep if inrange(year, 2012, 2025)
merge 1:1 tract_geoid year using `frame', nogen
foreach v in sales_n entity_n port10_n port25_n {
    replace `v' = 0 if missing(`v')
}
preserve
    import delimited "$D2/design2_tract_treatment.csv", varnames(1) stringcols(1) clear
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

gen anyport = port10_n > 0
gen port_cap = min(port10_n, 3)
gen blip = 0
foreach t of global BLIPTRACTS {
    replace blip = 1 if tract_geoid == "`t'"
}
egen tract_num = group(tract_geoid)
tempfile panel
save `panel'

log using "$OUT/entity_did_robust.log", replace text

tempname pf
postfile `pf' str16 spec double h b se using "$OUT/_er.dta", replace

capture program drop runes
program define runes
    args yvar spec cond pf
    preserve
    if "`cond'" != "" keep if `cond'
    di as result _n "===== `spec' ====="
    reghdfe `yvar' Dm4 Dm3 Dm2 D0 D1 D2 D3, absorb(tract_num year) vce(cluster tract_num)
    foreach h in -4 -3 -2 0 1 2 3 {
        local d = cond(`h' < 0, "Dm" + string(-`h'), "D" + string(`h'))
        post `pf' ("`spec'") (`h') (_b[`d']) (_se[`d'])
    }
    post `pf' ("`spec'") (-1) (0) (.)
    restore
end

use `panel', clear
runes port10_n baseline "" `pf'
use `panel', clear
runes port10_n dropblip "blip == 0" `pf'
use `panel', clear
runes anyport extensive "" `pf'
use `panel', clear
runes port_cap capped "" `pf'

postclose `pf'
log close

use "$OUT/_er.dta", clear
gen lb = b - 1.96*se
gen ub = b + 1.96*se
sort spec h
export delimited "$OUT/entity_did_robust_coefs.csv", replace
capture erase "$OUT/_er.dta"
list, noobs sep(8)
