/*==============================================================================
 design1_withinevent_plot.do
 Event-study figure for the within-event LP-DiD (absorb(event x year)),
 coefficients transcribed (x100) from withinevent_results.log.
 Output: output/design1/figD13_withinevent_es.png
==============================================================================*/

version 17
clear all
set more off

global OUT "C:/Users/mva284/Documents/GitHub/ClaudeAct2260MergeExercise/output/design1"

import delimited "$OUT/withinevent_es.csv", varnames(1) clear
sort horizon

twoway ///
    (rcap ub lb horizon, lcolor(navy) lwidth(medthin)) ///
    (connected b horizon, color(navy) msymbol(O) lwidth(medthin) sort(horizon)) ///
    , graphregion(color(white)) bgcolor(white) ///
    ylabel(, angle(horizontal) format(%9.0f)) ///
    yline(0, lcolor(gs8) lwidth(thin)) ///
    xline(-0.5, lcolor(gs11) lpattern(dash)) ///
    legend(off) ///
    title("Within-event LP-DiD: near ring vs own far ring", size(medium)) ///
    ytitle("Effect on log sale price (x100)") ///
    xtitle("Years since investor purchase (0 = purchase year)") ///
    xlabel(-4(1)3) ///
    note("LP-DiD with event x calendar-year effects absorbed: each near ring's long difference is contrasted only with its" ///
         "own event's far ring. Pooled post +5.10 (2.15), pre -2.57 (1.84, ns); effective N 1,350. 95% CIs, clustered by cell.", size(vsmall)) ///
    name(figD13_withinevent, replace)
graph export "$OUT/figD13_withinevent_es.png", replace width(2000)
di as result "Saved figD13_withinevent_es.png"
