/*==============================================================================
 design2_hmda_long_plots.do

 Figures for the long-panel (2012-2024) HMDA results (hmda_long_coefs.csv):
   figH7_income_long       borrower income, all + Hispanic-only, h = -4..3
   figH8_income_dose_long  borrower income by tract dose (5+ vs 1-4)
   figH9_eth_counts_long   purchase counts by borrower ethnicity
==============================================================================*/

version 17
clear all
set more off

global REPO "C:/Users/mva284/Documents/GitHub/ClaudeAct2260MergeExercise"
global OUT  "$REPO/output/design2"

import delimited "$OUT/hmda_long_coefs.csv", varnames(1) clear
drop if h == 99
foreach v in b lb ub {
    replace `v' = 100 * `v' if inlist(test, "purch_hisp_n", "purch_nonhisp_n")
}
rename h horizon
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
global FIG_NOTE2 "Consistent population 2012-2024: originated first-lien owner-occupied 1-4 family purchases. Endpoints binned at -4 and +3."

use `coefs', clear
global FIG_TESTS  lninc_all lninc_hisp
global FIG_LABELS `""All classified borrowers" "Hispanic borrowers""'
global FIG_TITLE  Income of purchase borrowers in treated tracts (2012-2024 panel)
global FIG_YT     "Effect on 100 x ln(mean borrower income)"
global FIG_XT     `XT'
global FIG_NOTE1  "reghdfe on tract-year mean purchase-borrower income (thousands), tract and year FE, never-treated controls, clustered by tract."
drawfig, out(figH7_income_long)

use `coefs', clear
global FIG_TESTS  inc_hi5 inc_lo14
global FIG_LABELS `""Tracts with 5+ purchases" "Tracts with 1-4 purchases""'
global FIG_TITLE  Borrower income by investor concentration (2012-2024 panel)
global FIG_YT     "Effect on 100 x ln(mean borrower income)"
global FIG_XT     `XT'
global FIG_NOTE1  "Each series: that treated group vs never-treated tracts; tract and year FE, clustered by tract."
drawfig, out(figH8_income_dose_long)

use `coefs', clear
global FIG_TESTS  purch_hisp_n purch_nonhisp_n
global FIG_LABELS `""Hispanic borrowers" "Non-Hispanic borrowers""'
global FIG_TITLE  Purchase originations by borrower ethnicity (2012-2024 panel)
global FIG_YT     "Effect on origination counts (100 x Poisson coef ~ %)"
global FIG_XT     `XT'
global FIG_NOTE1  "ppmlhdfe with tract and year FE, never-treated controls, clustered by tract."
drawfig, out(figH9_eth_counts_long)

* single-series non-Hispanic purchases (own scale -- thin base, wide CIs)
use `coefs', clear
global FIG_TESTS  purch_nonhisp_n
global FIG_LABELS `""Non-Hispanic borrowers""'
global FIG_TITLE  Purchase originations by non-Hispanic borrowers (2012-2024 panel)
global FIG_YT     "Effect on origination counts (100 x Poisson coef ~ %)"
global FIG_XT     `XT'
global FIG_NOTE1  "ppmlhdfe with tract and year FE, never-treated controls, clustered by tract. Thin base: a few hundred non-Hispanic borrower purchases per year island-wide."
drawfig, out(figH9b_purch_nonhisp)

di as result _n "Long-panel HMDA figures: figH7, figH8, figH9"
