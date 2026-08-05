/*==============================================================================
 design2_hmda_plots_cfe.do

 Event-study figures for the county x year FE HMDA Poisson results
 (hmda_pois_cfe_coefs.csv). FE-adjusted series on their own (no side-by-side).

   figH1cfe_purchases   owner-occ vs non-owner-occ purchase counts
   figH2cfe_refis       rate/term vs cash-out refi counts
   figH3cfe_total       all originations
==============================================================================*/

version 17
clear all
set more off

global REPO "C:/Users/mva284/Documents/GitHub/ClaudeAct2260MergeExercise"
global OUT  "$REPO/output/design2"

import delimited "$OUT/hmda_pois_cfe_coefs.csv", varnames(1) clear
drop if h == 99
replace b  = 100 * b
replace lb = 100 * lb
replace ub = 100 * ub
rename h horizon
rename outcome test
tempfile coefs
save `coefs'

capture program drop drawfig
program define drawfig
    syntax, out(string)
    local STYLE  graphregion(color(white)) bgcolor(white) ///
                 ylabel(, angle(horizontal) format(%9.0f)) ///
                 yline(0, lcolor(gs8) lwidth(thin)) ///
                 xline(-0.5, lcolor(gs11) lpattern(dash))
    local colors navy cranberry
    local n : word count $FIG_TESTS
    local plots
    local legorder
    local i = 0
    foreach t of global FIG_TESTS {
        local ++i
        local col : word `i' of `colors'
        local off = cond(`n'==1, 0, (`i' - (`n'+1)/2) * 0.10)
        capture drop x`i'
        gen x`i' = horizon + `off' if test == "`t'"
        local lab : word `i' of $FIG_LABELS
        local plots `plots' ///
            (rcap ub lb x`i' if test == "`t'", lcolor(`col') lwidth(medthin)) ///
            (connected b x`i' if test == "`t'", color(`col') msymbol(O) lwidth(medthin))
        local legorder `legorder' `= 2*`i'' "`lab'"
    }
    if `n' == 1 local legend legend(off)
    else        local legend legend(order(`legorder') rows(1) position(6) region(lstyle(none)))
    twoway `plots', `STYLE' `legend' ///
        title("$FIG_TITLE", size(medium)) ///
        ytitle("$FIG_YT") xtitle("$FIG_XT") ///
        note("$FIG_NOTE", size(vsmall)) ///
        xlabel(-3(1)3) name(`out', replace)
    graph export "$OUT/`out'.png", replace width(2000)
end

local XT "Years since first investor purchase in tract"
local YT "Effect on origination counts (100 x Poisson coef ~ %)"
local CAV "ppmlhdfe with tract FE and county x year FE (identification within county-year), never-treated controls, SEs clustered by tract; endpoints binned. HMDA covers financed purchases only -- decree investors are largely cash buyers."

use `coefs', clear
global FIG_TESTS  purch_oo_n purch_nonoo_n
global FIG_LABELS `""Owner-occupied purchases" "Non-owner-occupied purchases""'
global FIG_TITLE  Purchase originations by occupancy (county x year FE)
global FIG_YT     `YT'
global FIG_XT     `XT'
global FIG_NOTE   `CAV'
drawfig, out(figH1cfe_purchases)

use `coefs', clear
global FIG_TESTS  refi_n cashout_n
global FIG_LABELS `""Rate/term refis" "Cash-out refis""'
global FIG_TITLE  Refinancing originations (county x year FE)
global FIG_YT     `YT'
global FIG_XT     `XT'
global FIG_NOTE   `CAV'
drawfig, out(figH2cfe_refis)

use `coefs', clear
global FIG_TESTS  total_n
global FIG_LABELS `""All originations""'
global FIG_TITLE  Total originations (county x year FE)
global FIG_YT     `YT'
global FIG_XT     `XT'
global FIG_NOTE   `CAV'
drawfig, out(figH3cfe_total)

di as result _n "County-FE HMDA figures: figH1cfe, figH2cfe, figH3cfe"
