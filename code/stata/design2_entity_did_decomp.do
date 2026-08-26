/*==============================================================================
 design2_entity_did_decomp.do

 Decompose the pooled LEVELS estimate for portfolio purchases (+0.60, se
 0.28): is it the year-0 blip, or deep post years (rel >= 4)?
   (a) pooled excluding rel == 0
   (b) extended event study: D0, D1-3 pooled, D4-6, D7+
 Output: printed in entity_did_decomp.log
==============================================================================*/

version 17
clear all
set more off

global REPO "C:/Users/mva284/Documents/GitHub/ClaudeAct2260MergeExercise"
global D2   "$REPO/data/design2"
global OUT  "$REPO/output/design2"

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
egen tract_num = group(tract_geoid)

log using "$OUT/entity_did_decomp.log", replace text

di as result _n "===== (a) pooled LEVELS, all post ====="
reghdfe port10_n treat, absorb(tract_num year) vce(cluster tract_num)

di as result _n "===== (a') pooled LEVELS, excluding rel==0 ====="
reghdfe port10_n treat if rel != 0, absorb(tract_num year) vce(cluster tract_num)

di as result _n "===== (b) extended bins: pre / 0 / 1-3 / 4-6 / 7+ ====="
gen Dpre = !missing(rel) & rel <= -2
gen D0   = !missing(rel) & rel == 0
gen D13  = !missing(rel) & inrange(rel, 1, 3)
gen D46  = !missing(rel) & inrange(rel, 4, 6)
gen D7p  = !missing(rel) & rel >= 7
reghdfe port10_n Dpre D0 D13 D46 D7p, absorb(tract_num year) vce(cluster tract_num)

di as result _n "===== same, entity_n ====="
reghdfe entity_n Dpre D0 D13 D46 D7p, absorb(tract_num year) vce(cluster tract_num)

log close
di as result "done"
