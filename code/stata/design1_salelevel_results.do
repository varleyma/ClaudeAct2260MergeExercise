/*==============================================================================
 design1_salelevel_results.do

 Literature-convention robustness for the Design 1 ring estimates:
 TRANSACTION-LEVEL stacked DiD (Linden-Rockoff / Campbell-Giglio-Pathak
 style) instead of the event x ring x year cell panel used by lpdid.

 Spec (sale j, event e, calendar year t; near = 0-250m ring, far = 400-1000m):
     ln P_jet = a_{e x ring} + d_{e x t} + b (near x post) + [hedonics] + eps
 absorb(event x ring FE, event x calendar-year FE); post is constant within
 event-year so only near x post identifies; SEs clustered by event.

   S1  pooled near x post, no controls
   S2  pooled + hedonics (ln cabida, sub-unit, vacant)
   S3  event study: near x event-year dummies (base -1), no controls
   S4  event study + hedonics

 Differences from the cell design worth knowing: transactions (not events)
 carry the weight, so dense events dominate; stacked duplicates (a sale near
 several events) enter once per event, as in the stacking literature.

 Input:  data/design1/design1_sale_event_pairs.csv
 Output: output/design1/salelevel_coefs.csv, salelevel_results.log
==============================================================================*/

version 17
clear all
set more off

global REPO "C:/Users/mva284/Documents/GitHub/ClaudeAct2260MergeExercise"
global D1   "$REPO/data/design1"
global OUT  "$REPO/output/design1"

capture which reghdfe
if _rc ssc install reghdfe, replace

/*============================================================================
  SALE-LEVEL STACKED SAMPLE (baseline filters, rings near/far, +/-4..3 years)
============================================================================*/
import delimited "$D1/design1_sale_event_pairs.csv", ///
    varnames(1) encoding(utf8) stringcols(_all) clear
destring salesamt dist_m cabida structure, replace force

gen sdate = date(sale_date, "YMD")
gen edate = date(event_date, "YMD")
gen syear = year(sdate)
gen rel   = syear - year(edate)

drop if ring == "gap_250_400"
drop if flag_junk_date == "True"
drop if flag_nominal_price == "True"
drop if sale_is_investor_parcel == "True"
drop if year(edate) < 2012
keep if salesamt > 0 & !missing(salesamt)
keep if inrange(rel, -4, 3)

gen lnp   = ln(salesamt)
gen near  = ring == "near_0_250"
gen post  = rel >= 0
gen nearpost = near * post
gen lncab = ln(cabida) if cabida > 0
gen subu  = is_subunit == "True"
gen vac   = vacant_land == "True"
gen relf  = rel + 5          // 1..8, base 4 (= rel -1)

egen evring = group(event_id near)
egen evyear = group(event_id syear)
egen evnum  = group(event_id)

log using "$OUT/salelevel_results.log", replace text
di as result "stacked sale-level sample: " _N " sale-event rows"

tempname pf
postfile `pf' str12 spec double h b se using "$OUT/_sl_coefs.dta", replace

* ---- S1: pooled, no controls ----
di as result _n "===== S1: pooled near x post ====="
reghdfe lnp nearpost, absorb(evring evyear) vce(cluster evnum)
post `pf' ("S1_pooled") (99) (_b[nearpost]) (_se[nearpost])

* ---- S2: pooled + hedonics ----
di as result _n "===== S2: pooled + hedonics ====="
reghdfe lnp nearpost lncab subu vac, absorb(evring evyear) vce(cluster evnum)
post `pf' ("S2_hedonic") (99) (_b[nearpost]) (_se[nearpost])

* ---- S3/S4 event studies ----
* NOTE: with BOTH event x ring and event x year FE absorbed, the full set of
* near x relf dummies is collinear (it sums to the absorbed near main effect)
* and Stata silently imposes a second normalization. Literature convention
* instead: absorb event x year FE, include the near MAIN EFFECT, interactions
* relative to the -1 base only.
di as result _n "===== S3: event study ====="
reghdfe lnp near ib4.relf#c.near, absorb(evyear) vce(cluster evnum)
forvalues f = 1/8 {
    local h = `f' - 5
    if `f' == 4 post `pf' ("S3_es") (-1) (0) (.)
    else post `pf' ("S3_es") (`h') (_b[`f'.relf#c.near]) (_se[`f'.relf#c.near])
}

di as result _n "===== S4: event study + hedonics ====="
reghdfe lnp near ib4.relf#c.near lncab subu vac, absorb(evyear) vce(cluster evnum)
forvalues f = 1/8 {
    local h = `f' - 5
    if `f' == 4 post `pf' ("S4_es_hed") (-1) (0) (.)
    else post `pf' ("S4_es_hed") (`h') (_b[`f'.relf#c.near]) (_se[`f'.relf#c.near])
}

postclose `pf'
log close

use "$OUT/_sl_coefs.dta", clear
gen lb = b - 1.96*se
gen ub = b + 1.96*se
sort spec h
export delimited "$OUT/salelevel_coefs.csv", replace
capture erase "$OUT/_sl_coefs.dta"
di as result _n "Saved: $OUT/salelevel_coefs.csv (h=99 rows are pooled)"
