/*==============================================================================
 design2_entity_did_robust_plots.do

 Five-panel event-study figures for the t=0 robustness battery
 (entity_did_robust_coefs.csv): baseline levels, drop bulk-event tracts,
 post-2014 cohorts, extensive margin, capped counts. One figure per event
 window: post capped at +3 (figE4) and at +2 (figE4b).

 Outputs: output/design2/figE4_t0_robustness.png, figE4b_t0_robustness_t2.png
==============================================================================*/

version 17
clear all
set more off

global OUT "C:/Users/mva284/Documents/GitHub/ClaudeAct2260MergeExercise/output/design2"

import delimited "$OUT/entity_did_robust_coefs.csv", varnames(1) clear
rename h horizon
sort spec win horizon
tempfile coefs
save `coefs'

local t_baseline  "(a) Baseline: purchases per tract-year"
local t_dropblip  "(b) Dropping 5 bulk-event tracts"
local t_post2014  "(c) Events 2015+ only (cohort cut)"
local t_extensive "(d) Extensive margin: 1{any portfolio purchase}"
local t_capped    "(e) Counts capped at 3"

local NOTE1 "OLS event studies, tract and year FE, never-treated controls, 95% CIs clustered by tract; endpoints binned."
local NOTE2 "(a) counts per tract-year. (b) drops the five tracts whose onset-year single-building/resort acquisitions are 88% of all"
local NOTE3 "year-0 portfolio purchases (Cobian Plaza's 480-unit 2014 purchase alone is 74%). (c) restricts to tracts first treated"
local NOTE4 "2015+ -- a cohort cut avoiding the 2014 Cobian acquisition without outcome-based selection. (d) probability of any"
local NOTE5 "portfolio purchase. (e) counts capped at 3. The year-0 spike exists only in (a); late-endpoint positives in (d)-(e) are"
local NOTE6 "null in the Poisson (proportional) specification and within the absolute bound."

foreach w in 3 2 {
    local xmax = `w'
    local fn = cond(`w' == 3, "figE4_t0_robustness", "figE4b_t0_robustness_t2")
    local ttl = cond(`w' == 3, "Portfolio-scale purchases: robustness (post window +3)", ///
                               "Portfolio-scale purchases: robustness (post window +2)")
    local i = 0
    foreach s in baseline dropblip post2014 extensive capped {
        local ++i
        use `coefs', clear
        keep if spec == "`s'" & win == `w'
        twoway ///
            (rcap ub lb horizon, lcolor(cranberry) lwidth(medthin)) ///
            (connected b horizon, color(cranberry) msymbol(O) lwidth(medthin)) ///
            , graphregion(color(white)) bgcolor(white) ///
            ylabel(, angle(horizontal)) ///
            yline(0, lcolor(gs8) lwidth(thin)) ///
            xline(-0.5, lcolor(gs11) lpattern(dash)) legend(off) ///
            subtitle("`t_`s''", size(small)) ///
            ytitle("") xtitle("Years since first purchase in tract", size(small)) ///
            xlabel(-4(1)`xmax') name(p`i', replace) nodraw
    }
    graph combine p1 p2 p3 p4 p5, rows(2) graphregion(color(white)) ///
        title("`ttl'", size(medsmall)) ///
        note("`NOTE1'" "`NOTE2'" "`NOTE3'" "`NOTE4'" "`NOTE5'" "`NOTE6'", size(vsmall)) ///
        xsize(12) ysize(7) name(fig_w`w', replace)
    graph export "$OUT/`fn'.png", replace width(2400)
}
di as result "Saved figE4_t0_robustness.png, figE4b_t0_robustness_t2.png"
