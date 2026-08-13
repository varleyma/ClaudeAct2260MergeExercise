/*==============================================================================
 design1_netin_dose.do

 Dose splits for the NET compositional inflow outcome (netin = H->NH minus
 NH->H conversions per classified sale): same density groups as the price
 dose figure (n_other_events_within_1000m <=2 / 3-25 / >25), each group's
 near ring vs never-treated controls, annual lpdid pre 4 / post 3.

 Outputs: output/design1/netin_dose_coefs.csv, fig8c_netinflow_dose.png
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

tempfile sales
save `sales'

tempname pf
postfile `pf' str20 test str10 rowname double b se lb ub using "$OUT/_nid.dta", replace

foreach g in low mid high {
    use `sales', clear
    if "`g'" == "low"  keep if n_other_events_within_1000m <= 2
    if "`g'" == "mid"  keep if inrange(n_other_events_within_1000m, 3, 25)
    if "`g'" == "high" keep if n_other_events_within_1000m > 25
    egen cellid = group(event_id ring)
    gen near = ring == "near_0_250"
    collapse (mean) y = netin (first) near ett, by(cellid tt)
    drop if missing(y)
    gen treat = near & tt >= ett
    di as result _n "===== netin dose group `g' ====="
    lpdid y, unit(cellid) time(tt) treat(treat) ///
        pre_window(4) post_window(3) nograph nevertreated
    matrix E = e(results)
    local rn : rowfullnames E
    forvalues i = 1/`= rowsof(E)' {
        local r : word `i' of `rn'
        post `pf' ("`g'") ("`r'") (E[`i',1]) (E[`i',2]) (E[`i',5]) (E[`i',6])
    }
    matrix P = e(pooled_results)
    local rn : rowfullnames P
    forvalues i = 1/`= rowsof(P)' {
        local r : word `i' of `rn'
        post `pf' ("`g'") ("`r'") (P[`i',1]) (P[`i',2]) (P[`i',5]) (P[`i',6])
    }
}
postclose `pf'

use "$OUT/_nid.dta", clear
export delimited "$OUT/netin_dose_coefs.csv", replace
capture erase "$OUT/_nid.dta"

*---- plot ------------------------------------------------------------------
keep if inlist(substr(rowname,1,3), "pre", "tau")
gen horizon = -real(substr(rowname,4,1)) if substr(rowname,1,3) == "pre"
replace horizon = real(substr(rowname,4,1)) if substr(rowname,1,3) == "tau"
drop if missing(horizon) | missing(b)
sort test horizon

local colors navy cranberry dkorange
local i = 0
local plots
local legorder
foreach g in low mid high {
    local ++i
    local col : word `i' of `colors'
    local off = (`i' - 2) * 0.12
    gen x`i' = horizon + `off' if test == "`g'"
    local plots `plots' ///
        (rcap ub lb x`i' if test == "`g'", lcolor(`col') lwidth(medthin)) ///
        (connected b x`i' if test == "`g'", color(`col') msymbol(O) lwidth(medthin))
    local legorder `legorder' `= 2*`i''
}
twoway `plots' ///
    , graphregion(color(white)) bgcolor(white) ///
    ylabel(, angle(horizontal)) ///
    yline(0, lcolor(gs8) lwidth(thin)) ///
    xline(-0.5, lcolor(gs11) lpattern(dash)) ///
    legend(order(2 "0-2 other events" 4 "3-25 other events" 6 ">25 other events") ///
           rows(1) position(6) region(lstyle(none))) ///
    title("Net stock conversion by local investor density", size(medium)) ///
    ytitle("Net conversions per classified sale") ///
    xtitle("Years since investor purchase (0 = purchase year)") ///
    note("netin = 1{Hisp seller, non-Hisp buyer} - 1{non-Hisp seller, Hisp buyer}; splits by n_other_events_within_1000m.", size(vsmall)) ///
    xlabel(-4(1)3) name(fig8c, replace)
graph export "$OUT/fig8c_netinflow_dose.png", replace width(2000)
di as result "Saved fig8c_netinflow_dose.png"
