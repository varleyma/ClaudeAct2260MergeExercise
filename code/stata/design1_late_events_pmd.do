/*==============================================================================
 design1_late_events_pmd.do

 Censoring robustness in table form: the CRIM snapshot records only each
 parcel's MOST RECENT sale, so pre-period sales near early events are
 survivors that never resold (stale). Restricting to later events shortens
 the censoring window. PMD LP-DiD (baseline estimator) on the ring cell
 panel for events dated 2012+ (full), 2018+, 2020+, 2022+.

 Outputs: output/tables/pmd_stats_late.csv (keys T5_all, T5_2018,
          T5_2020, T5_2022) + event counts per cut in the log
==============================================================================*/

version 17
clear all
set more off

global REPO "C:/Users/mva284/Documents/GitHub/ClaudeAct2260MergeExercise"
global D1   "$REPO/data/design1"
global OUT  "$REPO/output/tables"

capture which reghdfe
if _rc ssc install reghdfe, replace

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
collapse (mean) y = lnp (first) near ett (firstnm) event_id, by(cellid tt)
drop if missing(y)
gen treat = near & tt >= ett
tempfile panel
save `panel'

log using "$OUT/pmd_stats_late.log", replace text

tempname pf
postfile `pf' str24 test double b se r2 nobs nevents using "$OUT/_late.dta", replace

foreach cut in 2012 2018 2020 2022 {
    use `panel', clear
    keep if ett >= `cut'
    qui tab event_id
    local ne = r(r)
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
    local key = cond(`cut' == 2012, "T5_all", "T5_`cut'")
    di as result _n "===== PMD lnp, events >= `cut' (`ne' events) ====="
    reghdfe pmd dD, absorb(tt) vce(cluster cellid)
    post `pf' ("`key'") (_b[dD]) (_se[dD]) (e(r2)) (e(N)) (`ne')
}
postclose `pf'
log close

use "$OUT/_late.dta", clear
export delimited "$OUT/pmd_stats_late.csv", replace
capture erase "$OUT/_late.dta"
list, noobs
di as result "Saved: $OUT/pmd_stats_late.csv"
