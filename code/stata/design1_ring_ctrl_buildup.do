/*==============================================================================
 design1_ring_ctrl_buildup.do

 Diagnostic: ring price PMD LP-DiD (clean-control sample, county x year
 effects) adding the 2010 PRCS control x treatment-entry interactions one at
 a time -- (a) cumulatively in the listed order, (b) each control alone.
 Shows which covariate drives the attenuation of the spec-(3) estimate.

 Output: output/design1/ring_ctrl_buildup.csv (mode,step,ctrl,b,se,nobs)
==============================================================================*/

version 17
clear all
set more off

global REPO "C:/Users/mva284/Documents/GitHub/ClaudeAct2260MergeExercise"
global D1   "$REPO/data/design1"
global D2   "$REPO/data/design2"
global OUT  "$REPO/output/design1"

capture which reghdfe
if _rc ssc install reghdfe, replace

global CTRLS med_hh_inc med_value med_rent poverty ba_share renter_share ///
    vacancy seasonal_share mainland_share lnpop

import delimited "$D2/prcs2010_tract_controls.csv", varnames(1) stringcols(1) clear
save "$D2/_prcs.dta", replace

import delimited "$D1/design1_sale_event_pairs.csv", ///
    varnames(1) encoding(utf8) stringcols(_all) clear
destring salesamt dist_m event_time_months, replace force
gen sdate = date(sale_date, "YMD")
gen edate = date(event_date, "YMD")
gen tt    = yofd(sdate)
gen ett   = yofd(edate)
drop if ring == "gap_250_400"
drop if flag_junk_date == "True"
drop if flag_nominal_price == "True"
drop if sale_is_investor_parcel == "True"
drop if year(edate) < 2012
keep if salesamt > 0 & !missing(salesamt)
keep if inrange(event_time_months, -72, 60)
gen lnp = ln(salesamt)
egen cellid = group(event_id ring)
gen near = ring == "near_0_250"
collapse (mean) lnp (first) near ett (firstnm) event_id, by(cellid tt)
gen treat = near & tt >= ett

preserve
    import delimited "$D1/design1_events.csv", varnames(1) ///
        encoding(utf8) stringcols(_all) clear
    keep event_id tract_geoid
    duplicates drop event_id, force
    tempfile evtr
    save `evtr'
restore
merge m:1 event_id using `evtr', keep(master match) nogen
rename tract_geoid tract_geoid_raw
gen tract_geoid = substr(tract_geoid_raw, 1, 11)
merge m:1 tract_geoid using "$D2/_prcs.dta", keep(master match) nogen
gen lnpop = ln(pop) if pop > 0
foreach c of global CTRLS {
    qui sum `c'
    gen z_`c' = (`c' - r(mean)) / r(sd)
}
gen county = substr(tract_geoid, 1, 5)
egen cyear = group(county tt)

xtset cellid tt
gen y0  = lnp
gen yf1 = F1.lnp
gen yf2 = F2.lnp
gen yf3 = F3.lnp
gen yl1 = L1.lnp
gen yl2 = L2.lnp
gen yl3 = L3.lnp
gen yl4 = L4.lnp
egen postm = rowmean(y0 yf1 yf2 yf3)
egen prem  = rowmean(yl1 yl2 yl3 yl4)
gen pmd = postm - prem
gen dD = treat == 1 & L1.treat == 0
egen evertr = max(treat), by(cellid)
keep if dD == 1 | evertr == 0
foreach c of global CTRLS {
    gen zpd_`c' = z_`c' * dD
}
* common sample: complete controls, so steps are comparable
gen ok = 1
foreach c of global CTRLS {
    replace ok = 0 if missing(z_`c')
}
keep if ok

log using "$OUT/ring_ctrl_buildup.log", replace text

tempname pf
postfile `pf' str6 mode double step str16 ctrl double b se nobs ///
    using "$OUT/_bu.dta", replace

* step 0: county x year only
reghdfe pmd dD, absorb(cyear) vce(cluster cellid)
post `pf' ("cumul") (0) ("none") (_b[dD]) (_se[dD]) (e(N))

local rhs dD
local i = 0
foreach c of global CTRLS {
    local ++i
    local rhs `rhs' zpd_`c'
    di as result _n "===== cumulative step `i': + `c' ====="
    reghdfe pmd `rhs', absorb(cyear) vce(cluster cellid)
    post `pf' ("cumul") (`i') ("`c'") (_b[dD]) (_se[dD]) (e(N))
}
local i = 0
foreach c of global CTRLS {
    local ++i
    di as result _n "===== solo: `c' ====="
    reghdfe pmd dD zpd_`c', absorb(cyear) vce(cluster cellid)
    post `pf' ("solo") (`i') ("`c'") (_b[dD]) (_se[dD]) (e(N))
}

postclose `pf'
log close

use "$OUT/_bu.dta", clear
export delimited "$OUT/ring_ctrl_buildup.csv", replace
capture erase "$OUT/_bu.dta"
capture erase "$D2/_prcs.dta"
list, noobs sep(11)
di as result "Saved: $OUT/ring_ctrl_buildup.csv"
