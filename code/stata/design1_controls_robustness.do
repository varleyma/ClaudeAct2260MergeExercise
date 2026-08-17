/*==============================================================================
 design1_controls_robustness.do

 Ring-design spec ladder, all specs estimated with the PMD LP-DiD
 (pre-mean differencing, H=3, k=4; clean-control sample: newly treated
 near cells at onset + never-treated cells), matching the paper's baseline
 estimator (spec (1) reproduces pmd_stats T1_baseline / T7_netin exactly):
   (1) base:            calendar-year effects
   (2) + county-year:   county x year effects (county = event's municipio)
   (3) + hedonics:      (2) + HOUSE-CHARACTERISTIC controls from the
                        transaction data: cell-year means of log assessed
                        structure value, log lot size (cabida), sub-unit
                        share, and vacant-land share, each pre-mean
                        differenced exactly like the outcome -- controlling
                        for composition shifts in what transacts
   (PRCS x onset spec retained as spec 4 for the record, not reported)

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
destring salesamt dist_m event_time_months cabida structure, replace force
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
* house characteristics (transaction data)
gen lnstru = ln(structure) if structure > 0
gen lncab  = ln(cabida)    if cabida > 0
gen subu   = is_subunit == "True"
gen vac    = vacant_land == "True"

egen cellid = group(event_id ring)
gen near = ring == "near_0_250"
collapse (mean) lnp netin lnstru lncab subu vac ///
    (first) near ett (firstnm) event_id, by(cellid tt)
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

global HED lnstru lncab subu vac

foreach y in lnp netin {
    use `panel', clear
    drop if missing(`y')
    xtset cellid tt
    * PMD transform: outcome and each hedonic control identically
    foreach v in `y' $HED {
        gen h0_`v'  = `v'
        gen hf1_`v' = F1.`v'
        gen hf2_`v' = F2.`v'
        gen hf3_`v' = F3.`v'
        gen hl1_`v' = L1.`v'
        gen hl2_`v' = L2.`v'
        gen hl3_`v' = L3.`v'
        gen hl4_`v' = L4.`v'
        egen postm_`v' = rowmean(h0_`v' hf1_`v' hf2_`v' hf3_`v')
        egen prem_`v'  = rowmean(hl1_`v' hl2_`v' hl3_`v' hl4_`v')
        gen pmd_`v' = postm_`v' - prem_`v'
    }
    gen pmd = pmd_`y'
    gen dD = treat == 1 & L1.treat == 0
    egen evertr = max(treat), by(cellid)
    keep if dD == 1 | evertr == 0
    local HEDP
    foreach c of global HED {
        local HEDP `HEDP' pmd_`c'
    }
    * X x post-treatment (PRCS): kept as unreported spec 4
    global ZPD
    foreach c of global CTRLS {
        capture drop zpd_`c'
        gen zpd_`c' = z_`c' * dD
        global ZPD $ZPD zpd_`c'
    }
    forvalues s = 1/4 {
        if `s' == 1 local abs absorb(tt)
        else        local abs absorb(cyear)
        local rhs dD
        if `s' == 3 local rhs dD `HEDP'
        if `s' == 4 local rhs dD $ZPD
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
