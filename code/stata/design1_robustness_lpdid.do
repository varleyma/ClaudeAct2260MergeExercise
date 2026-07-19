/*==============================================================================
 design1_robustness_lpdid.do

 Robustness suite for the Design 1 near-ring price bump.
 Annual resolution, lpdid only (baseline showed estimator- and FE-robustness).
 Conventions mirror design1_eventstudy_lpdid_csdid.do with TIMEUNIT="year":
   window sales -72..+60 months, pre_window(4) post_window(3),
   onset tt >= ett (event's own year treated).

 Tests
 -----
 T1  Baseline reference (annual near-vs-far, lnp)         -> the bump
 T2  COMPOSITION: characteristics as outcomes             -> flat = real prices
       ln(structure), ln(cabida), subunit share, vacant share
 T3  DISTANCE GRADIENT: gap ring (250-400m) vs far        -> expect near > gap > 0
 T4  DOSE RESPONSE: split by n_other_events_within_1000m  -> clean > crowded per event
 T5  LATE SAMPLE: events 2018+                            -> censoring robustness
 T6  PLACEBO: non-investor luxury purchases as events     -> expect ~0
       (co-located <=250m with real event sites, temporally separated by >3y;
        far ring truncated at 750m for coverage -> matching real baseline rerun
        with the same 400-750m far ring)

 Inputs (repo): data/design1/design1_sale_event_pairs.csv, design1_events.csv,
                placebo_sale_event_pairs.csv, placebo_events.csv
                (pairs files are gitignored; regenerate via code/python/)
 Output: output/design1/robustness_lpdid.log + per-test event-study plots
==============================================================================*/

version 17
clear all
set more off

global REPO "C:/Users/mva284/Documents/GitHub/ClaudeAct2260MergeExercise"
global D1   "$REPO/data/design1"
global OUT  "$REPO/output/design1"
capture mkdir "$REPO/output"
capture mkdir "$OUT"

local PREW  4
local POSTW 3

capture which lpdid
if _rc ssc install lpdid, replace
capture which reghdfe
if _rc ssc install reghdfe, replace

/*============================================================================
  0. SALE-LEVEL PREP (shared by T1-T5)
============================================================================*/
import delimited "$D1/design1_sale_event_pairs.csv", ///
    varnames(1) encoding(utf8) stringcols(_all) clear
destring salesamt dist_m event_time_months cabida structure, replace force

gen sdate = date(sale_date, "YMD")
gen edate = date(event_date, "YMD")
gen tt    = yofd(sdate)
gen ett   = yofd(edate)

drop if flag_junk_date == "True"
drop if flag_nominal_price == "True"
drop if sale_is_investor_parcel == "True"
drop if year(edate) < 2012
keep if salesamt > 0 & !missing(salesamt)
keep if inrange(event_time_months, -72, 60)

* event contamination info
preserve
    import delimited "$D1/design1_events.csv", varnames(1) ///
        encoding(utf8) stringcols(_all) clear
    keep event_id n_other_events_within_1000m
    destring n_other_events_within_1000m, replace force
    tempfile evinfo
    save `evinfo'
restore
merge m:1 event_id using `evinfo', keep(master match) nogen

gen lnp     = ln(salesamt)
gen lnstru  = ln(structure) if structure > 0
gen lncab   = ln(cabida)    if cabida > 0
gen subu    = is_subunit == "True"
gen vac     = vacant_land == "True"

tempfile sales
save `sales'

* ---- reusable collapse+lpdid: rings/sample filtered BEFORE calling ----
capture program drop run_lpdid
program define run_lpdid
    args yvar tag
    * builds event x ring x year cells from data in memory, runs lpdid
    egen cellid = group(event_id ring)
    gen near = ring == "near_0_250"
    collapse (mean) y = `yvar' (first) near ett (count) nsales = salesamt, ///
        by(cellid tt)
    drop if missing(y)
    gen treat = near & tt >= ett
    xtset cellid tt
    di as result _n "===== lpdid [`tag'] outcome=`yvar' ====="
    lpdid y, unit(cellid) time(tt) treat(treat) ///
        pre_window(4) post_window(3) nevertreated
    graph export "$OUT/rob_`tag'.png", replace
end

log using "$OUT/robustness_lpdid.log", replace text

/*============================================================================
  T1. BASELINE REFERENCE (annual near-vs-far, lnp)
============================================================================*/
use `sales', clear
drop if ring == "gap_250_400"
run_lpdid lnp T1_baseline

/*============================================================================
  T2. COMPOSITION: characteristics as outcomes (flat => bump is prices)
============================================================================*/
foreach y in lnstru lncab subu vac {
    use `sales', clear
    drop if ring == "gap_250_400"
    run_lpdid `y' T2_comp_`y'
}

/*============================================================================
  T3. DISTANCE GRADIENT: gap ring as the treated group vs far
      (compare T3 coefficient path to T1: expect near > gap > ~0)
============================================================================*/
use `sales', clear
drop if ring == "near_0_250"
replace ring = "near_0_250" if ring == "gap_250_400"   // gap plays "treated"
run_lpdid lnp T3_gradient_gap

/*============================================================================
  T4. DOSE RESPONSE by contamination (n other events within 1km)
============================================================================*/
use `sales', clear
drop if ring == "gap_250_400"
keep if n_other_events_within_1000m <= 2
run_lpdid lnp T4_dose_low

use `sales', clear
drop if ring == "gap_250_400"
keep if inrange(n_other_events_within_1000m, 3, 25)
run_lpdid lnp T4_dose_mid

use `sales', clear
drop if ring == "gap_250_400"
keep if n_other_events_within_1000m > 25
run_lpdid lnp T4_dose_high

/*============================================================================
  T5. LATE SAMPLE: events 2018+ (short last-sale censoring window)
============================================================================*/
use `sales', clear
drop if ring == "gap_250_400"
keep if year(edate) >= 2018
run_lpdid lnp T5_late

/*============================================================================
  T6. PLACEBO EVENTS (+ matching real baseline with far ring 400-750m)
============================================================================*/
* real baseline, far truncated to 400-750m (placebo coverage limit)
use `sales', clear
drop if ring == "gap_250_400"
drop if ring == "far_400_1000" & dist_m > 750
run_lpdid lnp T6_real_far750

* placebo
import delimited "$D1/placebo_sale_event_pairs.csv", ///
    varnames(1) encoding(utf8) stringcols(_all) clear
destring salesamt dist_m event_time_months, replace force
gen sdate = date(sale_date, "YMD")
gen edate = date(event_date, "YMD")
gen tt    = yofd(sdate)
gen ett   = yofd(edate)
drop if flag_junk_date == "True"
drop if flag_nominal_price == "True"
drop if sale_is_investor_parcel == "True"
keep if salesamt > 0 & !missing(salesamt)
keep if inrange(event_time_months, -72, 60)

* temporal separation from the co-located real event (>3y either side)
preserve
    import delimited "$D1/placebo_events.csv", varnames(1) ///
        encoding(utf8) stringcols(_all) clear
    keep event_id months_to_nearest_event
    destring months_to_nearest_event, replace force
    tempfile pinfo
    save `pinfo'
restore
merge m:1 event_id using `pinfo', keep(master match) nogen
drop if abs(months_to_nearest_event) <= 36

gen lnp = ln(salesamt)
drop if ring == "gap_250_400"
drop if ring == "far_400_1000" & dist_m > 750
run_lpdid lnp T6_placebo

log close

/*============================================================================
  READING THE RESULTS
  - T2 flat + T1 bump              -> price effect, not composition
  - T3 between T1 and zero          -> spatial decay (spillover signature)
  - T4 low > mid > high (per event) -> dose-response consistent with causality
  - T5 similar to T1                -> last-sale censoring not driving it
  - T6 placebo ~0 vs T6 real > 0    -> effect specific to decree investors,
                                       not any luxury transaction
  Caveats: placebo buyers are non-corporate individuals in the investor price
  band; some may be unmatched investors (LLC/name-miss) -> attenuates the
  placebo contrast, i.e. a conservative test.
==============================================================================*/
