/*==============================================================================
 design2_entity_did_robust_plots.do

 Four-panel event-study figure for the t=0 robustness battery
 (entity_did_robust_coefs.csv): baseline levels, drop bulk-event tracts,
 extensive margin, capped counts. Own y-scales (different units).

 Output: output/design2/figE4_t0_robustness.png
==============================================================================*/

version 17
clear all
set more off

global OUT "C:/Users/mva284/Documents/GitHub/ClaudeAct2260MergeExercise/output/design2"

import delimited "$OUT/entity_did_robust_coefs.csv", varnames(1) clear
rename h horizon
sort spec horizon

local t_baseline  "(a) Baseline: purchases per tract-year"
local t_dropblip  "(b) Dropping 5 bulk-event tracts"
local t_extensive "(c) Extensive margin: 1{any portfolio purchase}"
local t_capped    "(d) Counts capped at 3"
local i = 0
foreach s in baseline dropblip extensive capped {
    local ++i
    twoway ///
        (rcap ub lb horizon if spec == "`s'", lcolor(cranberry) lwidth(medthin)) ///
        (connected b horizon if spec == "`s'", color(cranberry) msymbol(O) lwidth(medthin)) ///
        , graphregion(color(white)) bgcolor(white) ///
        ylabel(, angle(horizontal)) ///
        yline(0, lcolor(gs8) lwidth(thin)) ///
        xline(-0.5, lcolor(gs11) lpattern(dash)) legend(off) ///
        subtitle("`t_`s''", size(small)) ///
        ytitle("") xtitle("Years since first purchase in tract", size(small)) ///
        xlabel(-4(1)3) name(p`i', replace) nodraw
}
graph combine p1 p2 p3 p4, rows(2) graphregion(color(white)) ///
    title("Portfolio-scale purchases: the year-0 blip is five bulk acquisitions", size(medsmall)) ///
    note("OLS event studies, tract and year FE, never-treated controls, 95% CIs clustered by tract; endpoints binned at -4 and +3." ///
         "(a) counts per tract-year. (b) drops the five tracts whose onset-year single-building/resort acquisitions are 88% of all" ///
         "year-0 portfolio purchases (Cobian Plaza's 480-unit 2014 purchase alone is 74%). (c) probability of any portfolio purchase." ///
         "(d) counts capped at 3. The year-0 spike exists only in (a). The binned 3+ endpoint in (c)-(d) turns slightly positive" ///
         "(+9.5pp probability, +0.22 capped) but is null in the Poisson (proportional) specification -- a threshold effect of the" ///
         "island-wide portfolio trend in high-volume markets, and within the ~0.6-purchase absolute bound in any case.", size(vsmall)) ///
    xsize(10) ysize(7) name(figE4, replace)
graph export "$OUT/figE4_t0_robustness.png", replace width(2400)
di as result "Saved figE4_t0_robustness.png"
