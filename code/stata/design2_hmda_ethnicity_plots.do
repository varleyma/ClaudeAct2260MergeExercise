/*==============================================================================
 design2_hmda_ethnicity_plots.do

 Event-study figures for the HMDA borrower-composition results
 (hmda_eth_coefs.csv from design2_hmda_ethnicity.do).

   figH4_eth_counts   purchase originations, Hispanic vs non-Hispanic borrowers
   figH5_eth_income   mean borrower income of purchase borrowers (100 x ln)
==============================================================================*/

version 17
clear all
set more off

global REPO "C:/Users/mva284/Documents/GitHub/ClaudeAct2260MergeExercise"
global OUT  "$REPO/output/design2"

import delimited "$OUT/hmda_eth_coefs.csv", varnames(1) clear
drop if h == 99
* Poisson count coefs are in natural units -> x100 ~ %; income already 100 x ln
foreach v in b lb ub {
    replace `v' = 100 * `v' if inlist(outcome, "purch_hisp_n", "purch_nonhisp_n")
}
rename h horizon
rename outcome test
sort test horizon    // connected() joins in data order -- must be sorted
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
        xlabel(-3(1)3) name(`out', replace)
    graph export "$OUT/`out'.png", replace width(2000)
end

local XT "Years since first investor purchase in tract"
global FIG_NOTE2 "HMDA covers financed purchases only -- decree investors are largely cash buyers, so this is the local (financed) side of the market. Self-reported derived_ethnicity; Joint/Not Available excluded."

use `coefs', clear
global FIG_TESTS  purch_hisp_n purch_nonhisp_n
global FIG_LABELS `""Hispanic borrowers" "Non-Hispanic borrowers""'
global FIG_TITLE  Purchase originations by borrower ethnicity
global FIG_YT     "Effect on origination counts (100 x Poisson coef ~ %)"
global FIG_XT     `XT'
global FIG_NOTE1  "ppmlhdfe with tract and year FE, never-treated controls, SEs clustered by tract; endpoints binned."
drawfig, out(figH4_eth_counts)

use `coefs', clear
global FIG_TESTS  lninc_all lninc_hisp
global FIG_LABELS `""All classified borrowers" "Hispanic borrowers""'
global FIG_TITLE  Income of purchase borrowers in treated tracts
global FIG_YT     "Effect on 100 x ln(mean borrower income)"
global FIG_XT     `XT'
global FIG_NOTE1  "reghdfe on tract-year mean income of purchase borrowers (thousands), tract and year FE, never-treated controls, clustered by tract."
drawfig, out(figH5_eth_income)

di as result _n "HMDA ethnicity figures: figH4_eth_counts, figH5_eth_income"
