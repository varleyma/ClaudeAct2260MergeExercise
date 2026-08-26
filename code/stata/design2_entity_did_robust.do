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

gen D2p = !missing(rel) & rel >= 2      // endpoint bin for the t<=2 window
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
postfile `pf' str16 spec double win h b se using "$OUT/_er.dta", replace

capture program drop runes
program define runes
    * runes <yvar> <spec> <cond> <win: 2|3> <pf>
    args yvar spec cond win pf
    preserve
    if "`cond'" != "" keep if `cond'
    di as result _n "===== `spec' (window +`win') ====="
    if `win' == 3 {
        reghdfe `yvar' Dm4 Dm3 Dm2 D0 D1 D2 D3, absorb(tract_num year) vce(cluster tract_num)
        local hs -4 -3 -2 0 1 2 3
        local ds Dm4 Dm3 Dm2 D0 D1 D2 D3
    }
    else {
        reghdfe `yvar' Dm4 Dm3 Dm2 D0 D1 D2p, absorb(tract_num year) vce(cluster tract_num)
        local hs -4 -3 -2 0 1 2
        local ds Dm4 Dm3 Dm2 D0 D1 D2p
    }
    local i = 0
    foreach h of local hs {
        local ++i
        local d : word `i' of `ds'
        post `pf' ("`spec'") (`win') (`h') (_b[`d']) (_se[`d'])
    }
    post `pf' ("`spec'") (`win') (-1) (0) (.)
    restore
end

foreach w in 3 2 {
    use `panel', clear
    runes port10_n baseline "" `w' `pf'
    use `panel', clear
    runes port10_n dropblip "blip == 0" `w' `pf'
    use `panel', clear
    runes anyport extensive "" `w' `pf'
    use `panel', clear
    runes port_cap capped "" `w' `pf'
    * cohort cut: post-2014 adopters only -- avoids the Cobian Plaza 2014
    * acquisition without outcome-based tract selection
    use `panel', clear
    runes port10_n post2014 "missing(first_event_year) | first_event_year >= 2015" `w' `pf'
}

/*============================================================================
  POOLED DiD, post capped at t=2: PMD LP-DiD with H=2, k=4 (the paper's
  estimator; avoids the staggered pooled-TWFE artifact). One Treated
  coefficient per robustness spec.
============================================================================*/
tempname pp
postfile `pp' str16 spec double b se r2 nobs using "$OUT/_erp.dta", replace

capture program drop pmdrun
program define pmdrun
    * pmdrun <yvar> <spec> <cond> <pp>
    args yvar spec cond pp
    preserve
    if "`cond'" != "" keep if `cond'
    xtset tract_num year
    gen y0  = `yvar'
    gen yf1 = F1.`yvar'
    gen yf2 = F2.`yvar'
    gen yl1 = L1.`yvar'
    gen yl2 = L2.`yvar'
    gen yl3 = L3.`yvar'
    gen yl4 = L4.`yvar'
    egen postm = rowmean(y0 yf1 yf2)
    egen prem  = rowmean(yl1 yl2 yl3 yl4)
    gen pmd = postm - prem
    gen dD = treat == 1 & L1.treat == 0
    egen evertr = max(treat), by(tract_num)
    keep if dD == 1 | evertr == 0
    di as result _n "===== PMD H=2 [`spec'] ====="
    reghdfe pmd dD, absorb(year) vce(cluster tract_num)
    post `pp' ("`spec'") (_b[dD]) (_se[dD]) (e(r2)) (e(N))
    restore
end

use `panel', clear
pmdrun port10_n baseline "" `pp'
use `panel', clear
pmdrun port10_n dropblip "blip == 0" `pp'
use `panel', clear
pmdrun port10_n post2014 "missing(first_event_year) | first_event_year >= 2015" `pp'
use `panel', clear
pmdrun anyport extensive "" `pp'
use `panel', clear
pmdrun port_cap capped "" `pp'

postclose `pp'
postclose `pf'
log close

use "$OUT/_erp.dta", clear
export delimited "$OUT/entity_robust_pmd.csv", replace
capture erase "$OUT/_erp.dta"
list, noobs

use "$OUT/_er.dta", clear
gen lb = b - 1.96*se
gen ub = b + 1.96*se
sort win spec h
export delimited "$OUT/entity_did_robust_coefs.csv", replace
capture erase "$OUT/_er.dta"
list, noobs sepby(spec win)
