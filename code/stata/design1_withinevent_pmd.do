/*==============================================================================
 design1_withinevent_pmd.do

 One-regression post-minus-pre for the WITHIN-EVENT ring LP-DiD, via
 pre-mean differencing (Dube-Girardi-Jorda-Taylor): outcome
     (1/4) sum_{h=0..3} y_{t+h}  -  (1/4) sum_{tau=t-4..t-1} y_tau
 on treatment entry, absorbing EVENT x CALENDAR-YEAR effects, so each near
 ring's long difference is contrasted only with its own event's far ring.
 Clean sample: newly treated cells + never-treated cells. Delivers the
 post-pre coefficient with a proper single-regression SE, R2, and N.

 Kept separate from design_pmd_stats.do so it can rerun alone; the table
 generator reads both CSVs.

 Output: output/tables/pmd_stats_withinevent.csv  (test, b, se, r2, nobs)
==============================================================================*/

version 17
clear all
set more off

global REPO "C:/Users/mva284/Documents/GitHub/ClaudeAct2260MergeExercise"
global D1   "$REPO/data/design1"
global OUT  "$REPO/output/tables"

capture which reghdfe
if _rc ssc install reghdfe, replace

*---- cell panel, identical to design1_withinevent_lpdid.do ------------------
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

*---- PMD outcome and clean sample (as pmdreg in design_pmd_stats.do) --------
xtset cellid tt
gen y0  = y
gen yf1 = F1.y
gen yf2 = F2.y
gen yf3 = F3.y
gen yl1 = L1.y
gen yl2 = L2.y
gen yl3 = L3.y
gen yl4 = L4.y
egen postm = rowmean(y0 yf1 yf2 yf3)
egen prem  = rowmean(yl1 yl2 yl3 yl4)
gen pmd = postm - prem
gen dD = treat == 1 & L1.treat == 0
egen evertr = max(treat), by(cellid)
keep if dD == 1 | evertr == 0

* event x year FE nest calendar-year FE, so absorb(evyear) alone suffices
reghdfe pmd dD, absorb(evyear) vce(cluster cellid)

tempname pf
postfile `pf' str24 test double b se r2 nobs using "$OUT/_pmd_we.dta", replace
post `pf' ("T1_withinevent") (_b[dD]) (_se[dD]) (e(r2)) (e(N))
postclose `pf'
use "$OUT/_pmd_we.dta", clear
export delimited using "$OUT/pmd_stats_withinevent.csv", replace
erase "$OUT/_pmd_we.dta"
di as result "Saved: $OUT/pmd_stats_withinevent.csv"
