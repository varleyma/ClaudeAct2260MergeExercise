/*==============================================================================
 design1_withinevent_lpdid.do

 Baseline ring LP-DiD with EVENT x CALENDAR-YEAR effects absorbed
 (lpdid's absorb() option): forces identification within event-year, i.e.
 each near cell's long difference against its OWN far ring's, rather than
 the pooled never-treated control pool.

 Note: event x ring (cell) FE are NOT added -- long-differencing already
 removes time-invariant cell effects, and adding cell FE to the differenced
 equation would (a) control cell trends instead, and (b) singleton-drop every
 newly treated observation.

 Output: appended to output/design1/withinevent_results.log (comparison vs
 the pooled-control baseline printed at the end)
==============================================================================*/

version 17
clear all
set more off

global REPO "C:/Users/mva284/Documents/GitHub/ClaudeAct2260MergeExercise"
global D1   "$REPO/data/design1"
global OUT  "$REPO/output/design1"

capture which lpdid
if _rc ssc install lpdid, replace

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
collapse (mean) y = lnp (first) near ett (firstnm) event_id ///
    (count) nsales = salesamt, by(cellid tt)
drop if missing(y)
gen treat = near & tt >= ett
egen evyear = group(event_id tt)
xtset cellid tt

log using "$OUT/withinevent_results.log", replace text

di as result _n "===== BASELINE (pooled controls, for reference) ====="
lpdid y, unit(cellid) time(tt) treat(treat) ///
    pre_window(4) post_window(3) nograph nevertreated
matrix list e(pooled_results)

di as result _n "===== WITHIN-EVENT: absorb(event x year) ====="
lpdid y, unit(cellid) time(tt) treat(treat) ///
    pre_window(4) post_window(3) nograph nevertreated absorb(evyear)
matrix list e(results)
matrix list e(pooled_results)

log close
di as result "Saved: $OUT/withinevent_results.log"
