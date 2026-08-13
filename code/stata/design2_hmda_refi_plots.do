/*==============================================================================
 design2_hmda_refi_plots.do

 Figures for the refinancing-by-ethnicity results (hmda_refi_coefs.csv):
   figH10_refi_eth_long   all refis by borrower ethnicity, 2012-2024
   figH11_cashout_eth     cash-out refis by ethnicity, 2018-2024 (the
                          cash-out/rate-term split first exists in 2018 HMDA)
==============================================================================*/

version 17
clear all
set more off

global REPO "C:/Users/mva284/Documents/GitHub/ClaudeAct2260MergeExercise"
global OUT  "$REPO/output/design2"

import delimited "$OUT/hmda_refi_coefs.csv", varnames(1) clear
drop if h == 99
foreach v in b lb ub {
    replace `v' = 100 * `v'
}
rename h horizon
rename test test0
gen test = test0
sort test horizon
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
        note("$FIG_NOTE1" "$FIG_NOTE2", size(vsmall)) ///
        xlabel(-4(1)3) name(`out', replace)
    graph export "$OUT/`out'.png", replace width(2000)
end

local XT "Years since first investor purchase in tract"
local YT "Effect on refi counts (100 x Poisson coef ~ %)"

use `coefs', clear
global FIG_TESTS  refi_hisp_n refi_nonhisp_n
global FIG_LABELS `""Hispanic borrowers" "Non-Hispanic borrowers""'
global FIG_TITLE  Refinancings by borrower ethnicity (2012-2024 panel)
global FIG_YT     `YT'
global FIG_XT     `XT'
global FIG_NOTE1  "ppmlhdfe with tract and year FE, never-treated controls, clustered by tract; endpoints binned at -4 and +3."
global FIG_NOTE2  "Consistent population: originated first-lien owner-occupied 1-4 family refinancings (all refi types -- the cash-out split does not exist before 2018)."
drawfig, out(figH10_refi_eth_long)

use `coefs', clear
global FIG_TESTS  cashout_hisp_n cashout_nonhisp_n
global FIG_LABELS `""Hispanic borrowers" "Non-Hispanic borrowers""'
global FIG_TITLE  Cash-out refinancings by borrower ethnicity (2018-2024 only)
global FIG_YT     "Effect on cash-out counts (100 x Poisson coef ~ %)"
global FIG_XT     `XT'
global FIG_NOTE1  "ppmlhdfe with tract and year FE, never-treated controls, clustered by tract; endpoints binned at -4 and +3."
global FIG_NOTE2  "2018-2024 panel only: HMDA first distinguishes cash-out from rate/term refis in 2018 reporting. Deep pre horizons rest on late adopters."
drawfig, out(figH11_cashout_eth)

di as result _n "Refi figures: figH10_refi_eth_long, figH11_cashout_eth"
