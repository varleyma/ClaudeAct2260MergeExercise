/*==============================================================================
 design1_controls_robustness.do

 Ring-design analog of the tract spec ladder (design2_controls_robustness.do):
 TWFE pooled treat coefficient on the event x ring CELL panel, three specs:
   (1) base:          cell FE + year FE
   (2) + county-year: cell FE + county x year FE (county = the event's
                      municipio, from its tract geoid)
   (3) + controls:    (2) + standardized 2010 PRCS characteristics of the
                      EVENT's tract interacted with Post (1{year >= 2020})

 treat = near ring x post-event. Outcomes: cell mean log sale price (lnp)
 and net H->NH conversion per classified sale (netin). SEs clustered by cell.

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
gen post = tt >= 2020
global ZP
foreach c of global CTRLS {
    qui sum `c'
    gen z_`c' = (`c' - r(mean)) / r(sd)
    gen zp_`c' = z_`c' * post
    global ZP $ZP zp_`c'
}
gen county = substr(tract_geoid, 1, 5)
egen cyear = group(county tt)

log using "$OUT/controls_robustness_ring.log", replace text

tempname pf
postfile `pf' str20 outcome double spec b se r2 nobs using "$OUT/_crr.dta", replace

foreach y in lnp netin {
    forvalues s = 1/3 {
        if `s' == 1 local abs absorb(cellid tt)
        else        local abs absorb(cellid cyear)
        local rhs treat
        if `s' == 3 local rhs treat $ZP
        di as result _n "===== ring `y' spec `s' ====="
        reghdfe `y' `rhs', `abs' vce(cluster cellid)
        post `pf' ("ring_`y'") (`s') (_b[treat]) (_se[treat]) (e(r2)) (e(N))
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
