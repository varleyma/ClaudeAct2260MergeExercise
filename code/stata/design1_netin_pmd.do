/*==============================================================================
 design1_netin_pmd.do

 One-regression post-minus-pre (PMD) for the NET compositional flow outcome:
 netin = 1{Hisp seller -> non-Hisp buyer} - 1{non-Hisp seller -> Hisp buyer}
 among sales where both parties' names classify. A sale changes the ownership
 composition of the stock only when the classes differ, so the cell mean of
 netin is the net rate of H->NH stock conversion per classified sale.

 Same PMD machinery as design_pmd_stats.do (which also carries T7_netin for
 full reruns); this standalone exists so the stat can refresh without the
 multi-hour wide-band sweep.

 Output: output/tables/pmd_stats_netin.csv  (test, b, se, r2, nobs)
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
gen bothcl = inlist(buyer_nonhispanic, "True", "False") & ///
             inlist(seller_nonhispanic, "True", "False")
gen main2isl = (seller_nonhispanic == "True" & buyer_nonhispanic == "False") if bothcl
gen netin = (seller_nonhispanic == "False" & buyer_nonhispanic == "True") ///
          - main2isl if bothcl

egen cellid = group(event_id ring)
gen near = ring == "near_0_250"
collapse (mean) netin main2isl (first) near ett, by(cellid tt)
gen treat = near & tt >= ett
tempfile panel
save `panel'

tempname pf
postfile `pf' str24 test double b se r2 nobs using "$OUT/_pmd_ni.dta", replace

foreach v in netin main2isl {
    use `panel', clear
    drop if missing(`v')
    rename `v' y
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
    di as result _n "===== PMD `v' ====="
    reghdfe pmd dD, absorb(tt) vce(cluster cellid)
    post `pf' ("T7_`v'") (_b[dD]) (_se[dD]) (e(r2)) (e(N))
}
postclose `pf'
use "$OUT/_pmd_ni.dta", clear
export delimited using "$OUT/pmd_stats_netin.csv", replace
erase "$OUT/_pmd_ni.dta"
di as result "Saved: $OUT/pmd_stats_netin.csv"
