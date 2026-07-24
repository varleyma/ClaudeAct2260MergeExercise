/*==============================================================================
 design1_robustness_results.do

 Runs all Design 1 robustness tests (annual, lpdid) and saves every
 event-study coefficient into ONE dataset for plotting elsewhere:

     output/design1/robustness_coefs.dta   (+ .csv copy)

 One row per (test x event-time horizon), with the raw r(results) matrix
 columns preserved as c1, c2, ... plus rowname/colnames strings so nothing
 is lost regardless of lpdid version. Standardization to b/se/lb/ub happens
 in design1_robustness_plots.do (single mapping block there).

 Tests (same samples/conventions as design1_robustness_lpdid.do):
   T1_baseline        near(0-250) vs far(400-1000), lnp
   T2_comp_lnstru / lncab / subu / vac    composition outcomes
   T3_gradient_gap    gap(250-400) vs far, lnp
   T4_dose_low/mid/high   by n other events within 1km (<=2 / 3-25 / >25)
   T5_late            events 2018+
   T6_real_far750     near vs far(400-750), lnp   } far rings matched
   T6_placebo         placebo events, same rings  } for comparability
==============================================================================*/

version 17
clear all
set more off

global REPO "C:/Users/mva284/Documents/GitHub/ClaudeAct2260MergeExercise"
global D1   "$REPO/data/design1"
global OUT  "$REPO/output/design1"
capture mkdir "$REPO/output"
capture mkdir "$OUT"
global COEFTMP "$OUT/_coefs_accum.dta"
capture erase "$COEFTMP"

capture which lpdid
if _rc ssc install lpdid, replace
capture which reghdfe
if _rc ssc install reghdfe, replace

/*============================================================================
  COEFFICIENT CAPTURE
============================================================================*/
capture program drop grab
program define grab
    args test outcome
    * lpdid stores the event-study matrix in e(results) with columns:
    * coefficient se t p ci_low ci_high obs   (verified in lpdid.ado v-SSC)
    matrix R = e(results)
    local rn : rowfullnames R
    local cn : colfullnames R
    local nr = rowsof(R)
    preserve
    clear
    qui svmat double R, names(c)
    qui gen row = _n
    qui gen str32 rowname = ""
    forvalues i = 1/`nr' {
        local r : word `i' of `rn'
        qui replace rowname = "`r'" in `i'
    }
    qui gen str40 test     = "`test'"
    qui gen str20 outcome  = "`outcome'"
    qui gen str200 colnames = `"`cn'"'
    qui gen prew  = 4
    qui gen postw = 3
    capture confirm file "$COEFTMP"
    if !_rc qui append using "$COEFTMP"
    qui save "$COEFTMP", replace
    restore
end

capture program drop run_lpdid
program define run_lpdid
    args yvar tag
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
    * show the matrix layout once so the plot file's mapping can be verified
    if "`tag'" == "T1_baseline" matrix list e(results)
    grab `tag' `yvar'
    * keep the per-test lpdid graph in its own named window
    capture graph rename Graph g`tag', replace
end

/*============================================================================
  SALE-LEVEL PREP (identical to design1_robustness_lpdid.do)
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
gen inv_sale = sale_is_investor_parcel == "True"   // kept for T8; dropped below
drop if year(edate) < 2012
keep if salesamt > 0 & !missing(salesamt)
keep if inrange(event_time_months, -72, 60)

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

* name-ethnicity proxy outcomes (requires annotate_name_ethnicity.py run first;
* "True"/"False" = classified at the 20/70 pcthispanic thresholds, "" = corporate/
* ambiguous/unmatched -> missing, so cells average over classified sales only)
capture confirm variable buyer_nonhispanic
if !_rc {
    gen buy_nh  = buyer_nonhispanic  == "True" if inlist(buyer_nonhispanic,  "True", "False")
    gen sell_nh = seller_nonhispanic == "True" if inlist(seller_nonhispanic, "True", "False")
    gen bothcl  = inlist(buyer_nonhispanic, "True", "False") & ///
                  inlist(seller_nonhispanic, "True", "False")
    gen isl2main  = (seller_nonhispanic == "False" & buyer_nonhispanic == "True")  if bothcl
    gen main2main = (seller_nonhispanic == "True"  & buyer_nonhispanic == "True")  if bothcl
    drop bothcl
}
* `salesall' keeps investor-parcel sales (for the T8 decomposition);
* `sales' is the default market-only estimation sample used by T1-T7.
tempfile salesall sales
save `salesall'
drop if inv_sale
save `sales'

/*============================================================================
  RUN ALL TESTS
============================================================================*/
use `sales', clear
drop if ring == "gap_250_400"
run_lpdid lnp T1_baseline

foreach y in lnstru lncab subu vac {
    use `sales', clear
    drop if ring == "gap_250_400"
    run_lpdid `y' T2_comp_`y'
}

use `sales', clear
drop if ring == "near_0_250"
replace ring = "near_0_250" if ring == "gap_250_400"
run_lpdid lnp T3_gradient_gap

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

use `sales', clear
drop if ring == "gap_250_400"
keep if year(edate) >= 2018
run_lpdid lnp T5_late

* ---- T7: buyer/seller composition (displacement) ----
foreach y in buy_nh sell_nh isl2main main2main {
    use `sales', clear
    capture confirm variable `y'
    if _rc continue
    drop if ring == "gap_250_400"
    run_lpdid `y' T7_`y'
}

* ---- T8: role of investor transactions themselves ----
* (a) INCLUDING investor-parcel sales: the gap vs T1 decomposes the local
*     price rise into investors' own transactions vs spillover onto others'
use `salesall', clear
drop if ring == "gap_250_400"
run_lpdid lnp T8_incl_investors

* (b) Hispanic-named buyers only: prices in transactions locals actually won.
*     Bump surviving here = locals face higher prices (affordability);
*     bump shrinking = the average partly reflects incomers buying pricier stock.
*     (Also the best available guard against unmatched/LLC investors hiding
*     in the "market" sample.)
use `sales', clear
capture confirm variable buyer_nonhispanic
if !_rc {
    drop if ring == "gap_250_400"
    keep if buyer_nonhispanic == "False"
    run_lpdid lnp T8_hisp_buyers
}

use `sales', clear
drop if ring == "gap_250_400"
drop if ring == "far_400_1000" & dist_m > 750
run_lpdid lnp T6_real_far750

* ---- placebo ----
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

/*============================================================================
  FINALIZE
============================================================================*/
use "$COEFTMP", clear
order test outcome row rowname prew postw
sort test row
save "$OUT/robustness_coefs.dta", replace
export delimited "$OUT/robustness_coefs.csv", replace
capture erase "$COEFTMP"
di as result _n "Saved: $OUT/robustness_coefs.dta (+.csv), " _N " coefficient rows"
