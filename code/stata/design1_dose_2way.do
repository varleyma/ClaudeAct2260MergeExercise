/*==============================================================================
 design1_dose_2way.do

 Ring-design dose splits aligned with the tract design's convention: TWO
 groups by TOTAL identified purchases within 1km of the event (the event
 itself + n_other_events_within_1000m): 1-4 purchases vs 5+.

 Outcomes:
   lnp    log sale price      -> fig4_dose.png   (replaces the 3-way split)
   netin  net H->NH conversion -> fig8c_netinflow_dose.png (replaces 3-way)

 Per group: annual lpdid (event + pooled, suite grab format appended to
 dose2_coefs.csv for the table generator) and the one-regression PMD
 post-pre (b/se/R2/N -> pmd_stats_dose2.csv, keys T4b_lo14 / T4b_hi5).
==============================================================================*/

version 17
clear all
set more off

global REPO "C:/Users/mva284/Documents/GitHub/ClaudeAct2260MergeExercise"
global D1   "$REPO/data/design1"
global OUT  "$REPO/output/design1"
global TAB  "$REPO/output/tables"

capture which lpdid
if _rc ssc install lpdid, replace
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
gen bothcl = inlist(buyer_nonhispanic, "True", "False") & ///
             inlist(seller_nonhispanic, "True", "False")
gen netin = (seller_nonhispanic == "False" & buyer_nonhispanic == "True") ///
          - (seller_nonhispanic == "True"  & buyer_nonhispanic == "False") if bothcl

preserve
    import delimited "$D1/design1_events.csv", varnames(1) ///
        encoding(utf8) stringcols(_all) clear
    keep event_id n_other_events_within_1000m
    destring n_other_events_within_1000m, replace force
    tempfile evinfo
    save `evinfo'
restore
merge m:1 event_id using `evinfo', keep(master match) nogen
gen n_total = n_other_events_within_1000m + 1   // include the event itself
tempfile sales
save `sales'

tempname pf pr2
postfile `pf' str20 test str20 outcome double row str12 rowname ///
    double prew postw c1 c2 c3 c4 c5 c6 c7 str8 matrix_type ///
    using "$OUT/_d2w.dta", replace
postfile `pr2' str24 test double b se r2 nobs using "$TAB/_d2w_pmd.dta", replace

capture program drop runcell
program define runcell
    * runcell <yvar> <test> <pf> <pr2> <dopmd>
    args yvar test pf pr2 dopmd
    preserve
    egen cellid = group(event_id ring)
    gen near = ring == "near_0_250"
    collapse (mean) y = `yvar' (first) near ett, by(cellid tt)
    drop if missing(y)
    gen treat = near & tt >= ett
    di as result _n "===== lpdid [`test'] outcome=`yvar' ====="
    lpdid y, unit(cellid) time(tt) treat(treat) ///
        pre_window(4) post_window(3) nograph nevertreated
    foreach M in results pooled_results {
        local mtype = cond("`M'" == "results", "event", "pooled")
        matrix E = e(`M')
        local rn : rowfullnames E
        forvalues i = 1/`= rowsof(E)' {
            local r : word `i' of `rn'
            post `pf' ("`test'") ("`yvar'") (`i') ("`r'") (4) (3) ///
                (E[`i',1]) (E[`i',2]) (E[`i',3]) (E[`i',4]) ///
                (E[`i',5]) (E[`i',6]) (E[`i',7]) ("`mtype'")
        }
    }
    if `dopmd' {
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
        reghdfe pmd dD, absorb(tt) vce(cluster cellid)
        post `pr2' ("`test'") (_b[dD]) (_se[dD]) (e(r2)) (e(N))
    }
    restore
end

foreach g in lo14 hi5 {
    use `sales', clear
    if "`g'" == "lo14" keep if inrange(n_total, 1, 4)
    if "`g'" == "hi5"  keep if n_total >= 5
    runcell lnp   T4b_`g'   `pf' `pr2' 1
    runcell netin T4bn_`g'  `pf' `pr2' 0
}

postclose `pf'
postclose `pr2'

use "$OUT/_d2w.dta", clear
export delimited "$OUT/dose2_coefs.csv", replace
capture erase "$OUT/_d2w.dta"
use "$TAB/_d2w_pmd.dta", clear
export delimited "$TAB/pmd_stats_dose2.csv", replace
capture erase "$TAB/_d2w_pmd.dta"

/*============================================================================
  FIGURES (two-series overlays, house style)
============================================================================*/
import delimited "$OUT/dose2_coefs.csv", varnames(1) clear
keep if matrix_type == "event"
gen horizon = -real(substr(rowname,4,1)) if substr(rowname,1,3) == "pre"
replace horizon = real(substr(rowname,4,1)) if substr(rowname,1,3) == "tau"
drop if missing(horizon) | missing(c1)
gen b  = c1
gen lb = c5
gen ub = c6
sort test horizon
tempfile coefs
save `coefs'

capture program drop dosefig
program define dosefig
    syntax, t1(string) t2(string) out(string) yt(string) ttl(string) note1(string)
    gen x1 = horizon - 0.06 if test == "`t1'"
    gen x2 = horizon + 0.06 if test == "`t2'"
    twoway ///
        (rcap ub lb x1 if test == "`t1'", lcolor(cranberry) lwidth(medthin)) ///
        (connected b x1 if test == "`t1'", color(cranberry) msymbol(O) lwidth(medthin)) ///
        (rcap ub lb x2 if test == "`t2'", lcolor(navy) lwidth(medthin)) ///
        (connected b x2 if test == "`t2'", color(navy) msymbol(O) lwidth(medthin)) ///
        , graphregion(color(white)) bgcolor(white) ///
        ylabel(, angle(horizontal)) ///
        yline(0, lcolor(gs8) lwidth(thin)) ///
        xline(-0.5, lcolor(gs11) lpattern(dash)) ///
        legend(order(2 "1-4 purchases within 1km" 4 "5+ purchases within 1km") ///
               rows(1) position(6) region(lstyle(none))) ///
        title("`ttl'", size(medium)) ///
        ytitle("`yt'") ///
        xtitle("Years since investor purchase (0 = purchase year)") ///
        note("`note1'" ///
             "Groups by total identified purchases within 1km of the event (the event itself included), matching the tract design's 1-4 / 5+ split.", size(vsmall)) ///
        xlabel(-4(1)3) name(`out', replace)
    graph export "$OUT/`out'.png", replace width(2000)
end

use `coefs', clear
dosefig, t1(T4b_lo14) t2(T4b_hi5) out(fig4_dose) ///
    yt("Effect on log sale price") ///
    ttl("Price effect by local investor concentration") ///
    note1("Each series: that group's near rings vs never-treated controls; annual lpdid, 95% CIs clustered by cell.")

use `coefs', clear
dosefig, t1(T4bn_lo14) t2(T4bn_hi5) out(fig8c_netinflow_dose) ///
    yt("Net H-to-NH conversions per classified sale") ///
    ttl("Net stock conversion by local investor concentration") ///
    note1("netin = 1{Hisp seller, non-Hisp buyer} - 1{non-Hisp seller, Hisp buyer} among classified sales; annual lpdid, 95% CIs clustered by cell.")

di as result "Saved fig4_dose.png, fig8c_netinflow_dose.png (2-way splits)"
