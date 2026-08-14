/*==============================================================================
 design1_controls_robustness.do

 Ring-design spec ladder, all specs estimated with the PMD LP-DiD
 (pre-mean differencing, H=3, k=4; clean-control sample: newly treated
 near cells at onset + never-treated cells), matching the paper's baseline
 estimator (spec (1) reproduces pmd_stats T1_baseline / T7_netin exactly):
   (1) base:            calendar-year effects
   (2) + county-year:   county x year effects (county = event's municipio)
   (3) + controls:      (2) + standardized 2010 PRCS characteristics of the
                        EVENT's tract interacted with the cell's
                        POST-TREATMENT indicator (X x 1{t>=onset} = X x dD
                        in the differenced clean sample -> Treated = effect
                        at sample-mean baseline characteristics)

 Outcomes: cell mean log sale price (lnp) and net H->NH conversion per
 classified sale (netin). SEs clustered by cell.

 Output: output/design1/controls_robustness_ring.csv (outcome,spec,b,se,r2,nobs)
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
gen bothcl = inlist(buyer_nonhispanic, "True", "False") & ///
             inlist(seller_nonhispanic, "True", "False")
gen netin = (seller_nonhispanic == "False" & buyer_nonhispanic == "True") ///
          - (seller_nonhispanic == "True"  & buyer_nonhispanic == "False") if bothcl

egen cellid = group(event_id ring)
gen near = ring == "near_0_250"
collapse (mean) lnp netin (first) near ett (firstnm) event_id, by(cellid tt)
gen treat = near & tt >= ett

* event tract -> county + 2010 controls
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
tempfile panel
save `panel'

log using "$OUT/controls_robustness_ring.log", replace text

tempname pf
postfile `pf' str20 outcome double spec b se r2 nobs using "$OUT/_crr.dta", replace

foreach y in lnp netin {
    use `panel', clear
    drop if missing(`y')
    xtset cellid tt
    gen y0  = `y'
    gen yf1 = F1.`y'
    gen yf2 = F2.`y'
    gen yf3 = F3.`y'
    gen yl1 = L1.`y'
    gen yl2 = L2.`y'
    gen yl3 = L3.`y'
    gen yl4 = L4.`y'
    egen postm = rowmean(y0 yf1 yf2 yf3)
    egen prem  = rowmean(yl1 yl2 yl3 yl4)
    gen pmd = postm - prem
    gen dD = treat == 1 & L1.treat == 0
    egen evertr = max(treat), by(cellid)
    keep if dD == 1 | evertr == 0
    * X x post-treatment: in the differenced clean sample 1{t>=onset} = dD
    global ZPD
    foreach c of global CTRLS {
        capture drop zpd_`c'
        gen zpd_`c' = z_`c' * dD
        global ZPD $ZPD zpd_`c'
    }
    forvalues s = 1/3 {
        if `s' == 1 local abs absorb(tt)
        else        local abs absorb(cyear)
        local rhs dD
        if `s' == 3 local rhs dD $ZPD
        di as result _n "===== ring PMD `y' spec `s' ====="
        reghdfe pmd `rhs', `abs' vce(cluster cellid)
        post `pf' ("ring_`y'") (`s') (_b[dD]) (_se[dD]) (e(r2)) (e(N))
    }
}

postclose `pf'
log close

use "$OUT/_crr.dta", clear
export delimited "$OUT/controls_robustness_ring.csv", replace
capture erase "$OUT/_crr.dta"
capture erase "$D2/_prcs.dta"
list, noobs sep(3)
di as result "Saved: $OUT/controls_robustness_ring.csv"
