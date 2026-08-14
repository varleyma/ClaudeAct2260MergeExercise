/*==============================================================================
 design1_transitions_panel.do

 Three-panel transition figure for the ring design, one lpdid event study
 per outcome (shares among sales where both parties' names classify):

   (a) isl2main  = 1{Hispanic seller -> non-Hispanic buyer}
   (b) main2isl  = 1{non-Hispanic seller -> Hispanic buyer}
   (c) netin     = (a) - (b)   net conversion per classified sale

 Panels share a common y-scale so the asymmetry is visible: conversion is
 one-directional -- (a) rises, (b) stays flat, so the net tracks (a).

 Outputs: output/design1/transitions_panel_coefs.csv,
          fig8d_transitions_3panel.png
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
gen isl2main = (seller_nonhispanic == "False" & buyer_nonhispanic == "True")  if bothcl
gen main2isl = (seller_nonhispanic == "True"  & buyer_nonhispanic == "False") if bothcl
gen netin    = isl2main - main2isl if bothcl

egen cellid = group(event_id ring)
gen near = ring == "near_0_250"
collapse (mean) isl2main main2isl netin (first) near ett, by(cellid tt)
gen treat = near & tt >= ett
tempfile panel
save `panel'

tempname pf
postfile `pf' str12 test str10 rowname double b se lb ub using "$OUT/_tp.dta", replace

foreach y in isl2main main2isl netin {
    use `panel', clear
    drop if missing(`y')
    rename `y' y
    di as result _n "===== lpdid transitions: `y' ====="
    lpdid y, unit(cellid) time(tt) treat(treat) ///
        pre_window(4) post_window(3) nograph nevertreated
    matrix E = e(results)
    local rn : rowfullnames E
    forvalues i = 1/`= rowsof(E)' {
        local r : word `i' of `rn'
        post `pf' ("`y'") ("`r'") (E[`i',1]) (E[`i',2]) (E[`i',5]) (E[`i',6])
    }
    matrix P = e(pooled_results)
    local rn : rowfullnames P
    forvalues i = 1/`= rowsof(P)' {
        local r : word `i' of `rn'
        post `pf' ("`y'") ("`r'") (P[`i',1]) (P[`i',2]) (P[`i',5]) (P[`i',6])
    }
}
postclose `pf'

use "$OUT/_tp.dta", clear
export delimited "$OUT/transitions_panel_coefs.csv", replace
capture erase "$OUT/_tp.dta"

*---- three panels, common scale ---------------------------------------------
keep if inlist(substr(rowname,1,3), "pre", "tau")
gen horizon = -real(substr(rowname,4,1)) if substr(rowname,1,3) == "pre"
replace horizon = real(substr(rowname,4,1)) if substr(rowname,1,3) == "tau"
drop if missing(horizon) | missing(b)
sort test horizon

local STYLE graphregion(color(white)) bgcolor(white) ///
    ylabel(-0.06(0.02)0.08, angle(horizontal)) ///
    yline(0, lcolor(gs8) lwidth(thin)) ///
    xline(-0.5, lcolor(gs11) lpattern(dash)) legend(off) xlabel(-4(1)3)

local t1 "Hispanic seller {&rarr} non-Hispanic buyer"
local t2 "non-Hispanic seller {&rarr} Hispanic buyer"
local t3 "Net conversion (a {&minus} b)"
local i = 0
foreach y in isl2main main2isl netin {
    local ++i
    local yt ""
    if `i' == 1 local yt "Effect on share of classified sales"
    twoway ///
        (rcap ub lb horizon if test == "`y'", lcolor(navy) lwidth(medthin)) ///
        (connected b horizon if test == "`y'", color(navy) msymbol(O) lwidth(medthin)) ///
        , `STYLE' subtitle("(`=char(96+`i')') `t`i''", size(small)) ///
        ytitle("`yt'", size(small)) ///
        xtitle("Years since purchase", size(small)) ///
        name(p`i', replace) nodraw
}
graph combine p1 p2 p3, rows(1) ycommon graphregion(color(white)) ///
    title("Ownership transitions around investor purchases", size(medium)) ///
    note("Shares among near-ring sales where both parties' names classify, vs never-treated controls; annual lpdid, 95% CIs clustered by cell." ///
         "Conversion is one-directional: Hispanic-to-non-Hispanic sales rise while the reverse flow stays flat, so the net tracks panel (a).", size(vsmall)) ///
    xsize(11) ysize(4) name(fig8d, replace)
graph export "$OUT/fig8d_transitions_3panel.png", replace width(2600)
di as result "Saved fig8d_transitions_3panel.png"
