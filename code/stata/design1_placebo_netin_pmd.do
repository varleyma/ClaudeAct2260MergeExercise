/*==============================================================================
 design1_placebo_netin_pmd.do

 PMD LP-DiD post-pre for NET H->NH ownership conversion under the placebo
 comparison: real investor events vs 1,500 placebo luxury purchases by
 individual non-investor buyers, both with far rings matched at 400-750m
 (the placebo table's convention; same sample rules as design_pmd_stats.do
 T6_real_far750 / T6_placebo). If conversion is an investor phenomenon and
 not a generic luxury-transaction effect, the placebo should be null.

 Output: output/tables/pmd_stats_placebo_netin.csv
         (keys T6n_real_far750, T6n_placebo)
==============================================================================*/

version 17
clear all
set more off

global REPO "C:/Users/mva284/Documents/GitHub/ClaudeAct2260MergeExercise"
global D1   "$REPO/data/design1"
global OUT  "$REPO/output/tables"

capture which reghdfe
if _rc ssc install reghdfe, replace

capture program drop pmdcell
program define pmdcell
    * pmdcell <test> <pf> -- expects sale rows with event_id ring tt ett netin
    args test pf
    preserve
    egen cellid = group(event_id ring)
    gen near = ring == "near_0_250"
    collapse (mean) y = netin (first) near ett, by(cellid tt)
    drop if missing(y)
    gen treat = near & tt >= ett
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
    di as result _n "===== PMD netin [`test'] ====="
    reghdfe pmd dD, absorb(tt) vce(cluster cellid)
    post `pf' ("`test'") (_b[dD]) (_se[dD]) (e(r2)) (e(N))
    restore
end

tempname pf
postfile `pf' str24 test double b se r2 nobs using "$OUT/_pmd_pn.dta", replace

*---- real events, far ring 400-750m -----------------------------------------
import delimited "$D1/design1_sale_event_pairs.csv", ///
    varnames(1) encoding(utf8) stringcols(_all) clear
destring salesamt dist_m event_time_months, replace force
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
drop if ring == "gap_250_400"
drop if ring == "far_400_1000" & dist_m > 750
gen bothcl = inlist(buyer_nonhispanic, "True", "False") & ///
             inlist(seller_nonhispanic, "True", "False")
gen netin = (seller_nonhispanic == "False" & buyer_nonhispanic == "True") ///
          - (seller_nonhispanic == "True"  & buyer_nonhispanic == "False") if bothcl
pmdcell T6n_real_far750 `pf'

*---- placebo events ---------------------------------------------------------
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
drop if ring == "gap_250_400"
drop if ring == "far_400_1000" & dist_m > 750
gen bothcl = inlist(buyer_nonhispanic, "True", "False") & ///
             inlist(seller_nonhispanic, "True", "False")
gen netin = (seller_nonhispanic == "False" & buyer_nonhispanic == "True") ///
          - (seller_nonhispanic == "True"  & buyer_nonhispanic == "False") if bothcl
pmdcell T6n_placebo `pf'

postclose `pf'
use "$OUT/_pmd_pn.dta", clear
export delimited "$OUT/pmd_stats_placebo_netin.csv", replace
capture erase "$OUT/_pmd_pn.dta"
list, noobs
di as result "Saved: $OUT/pmd_stats_placebo_netin.csv"
