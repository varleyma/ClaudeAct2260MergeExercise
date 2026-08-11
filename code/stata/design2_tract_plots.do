/*==============================================================================
 design2_tract_plots.do

 Figures for the tract-level DiD (design2_coefs.dta from
 design2_tract_results.do):

   figT1_lnhp_es          event study, ln price: base vs county-FE overlay
   figT2_dose_es          event study, ln price: >=5-event vs 1-4-event tracts
   figT3_volume_es        event study, ln sales volume (pre-trends violated --
                          descriptive only, note says so)
   figT4_reconciliation   observed tract-DiD pooled Post vs ring-implied
                          prediction, by dose group -- the whole-vs-sum-of-
                          parts exhibit

 lpdid matrix columns: c1=coefficient c2=se c3=t c4=p c5=ci_low c6=ci_high c7=obs
==============================================================================*/

version 17
clear all
set more off

global REPO "C:/Users/mva284/Documents/GitHub/ClaudeAct2260MergeExercise"
global D2   "$REPO/data/design2"
global OUT  "$REPO/output/design2"

local COL_B  c1
local COL_SE c2
local COL_LB c5
local COL_UB c6

use "$OUT/design2_coefs.dta", clear
gen b  = `COL_B'
gen se = `COL_SE'
gen lb = `COL_LB'
gen ub = `COL_UB'
replace lb = b - 1.96*se if missing(lb) & !missing(se)
replace ub = b + 1.96*se if missing(ub) & !missing(se)
drop if missing(b)
tempfile coefs
save `coefs'

/*============================================================================
  EVENT-STUDY OVERLAYS (drawfig pattern, horizons from pre/tau rownames)
============================================================================*/
capture program drop drawfig
program define drawfig
    syntax, out(string)
    local STYLE  graphregion(color(white)) bgcolor(white) ///
                 ylabel(, angle(horizontal) format(%9.0f)) ///
                 yline(0, lcolor(gs8) lwidth(thin)) ///
                 xline(-0.5, lcolor(gs11) lpattern(dash))
    local colors navy cranberry dkorange
    local n : word count $FIG_TESTS
    local plots
    local legorder
    local i = 0
    foreach t of global FIG_TESTS {
        local ++i
        local col : word `i' of `colors'
        local off = cond(`n'==1, 0, (`i' - (`n'+1)/2) * 0.12)
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
        xlabel(-4(1)3) name(`out', replace)
    graph export "$OUT/`out'.png", replace width(2000)
end

local XT "Years since first investor purchase in tract"

use `coefs', clear
keep if matrix_type == "event"
gen horizon = .
replace horizon = -real(substr(rowname, 4, .)) if strpos(rowname, "pre") == 1
replace horizon =  real(substr(rowname, 4, .)) if strpos(rowname, "tau") == 1
drop if missing(horizon)
tempfile es
save `es'

use `es', clear
global FIG_TESTS  T_lnhp_base T_lnhp_fips
global FIG_LABELS `""Base" "+ County FE""'
global FIG_TITLE  Tract-level DiD: log house price
global FIG_YT     "Effect on 100 x ln(price)"
global FIG_XT     `XT'
global FIG_NOTE   Annual lpdid on the Red Atlas tract panel (count-weighted mean price); never-treated tracts as controls; 235 treated tracts.
drawfig, out(figT1_lnhp_es)

use `es', clear
global FIG_TESTS  T_lnhp_dose5 T_lnhp_dose14
global FIG_LABELS `""Tracts with 5+ purchases" "Tracts with 1-4 purchases""'
global FIG_TITLE  Tract-level DiD by investor concentration
global FIG_YT     "Effect on 100 x ln(price)"
global FIG_XT     `XT'
global FIG_NOTE   Each series: that treated group vs never-treated tracts. The concentration result at tract scale.
drawfig, out(figT2_dose_es)

use `es', clear
global FIG_TESTS  T_lnsales_base
global FIG_LABELS `""Sales volume""'
global FIG_TITLE  Tract-level DiD: log transaction volume
global FIG_YT     "Effect on 100 x ln(sales)"
global FIG_XT     `XT'
global FIG_NOTE   DESCRIPTIVE ONLY: pre-period coefficients are significantly nonzero (declining volume precedes treatment) -- parallel trends fails for this outcome.
drawfig, out(figT3_volume_es)

/*============================================================================
  RECONCILIATION FIGURE: observed vs ring-implied, by dose group
============================================================================*/
* group means of ring-implied predictions (grp 1 = all treated, 2 = 1-4, 3 = 5+)
import delimited "$D2/design2_tract_treatment.csv", varnames(1) clear
tempfile trt
save `trt'
import delimited "$D2/design2_ring_prediction.csv", varnames(1) clear
merge 1:1 tract_geoid using `trt', keep(match) nogen
gen pred_c = pred_central_vw
gen pred_k = pred_conserv_vw
preserve
    collapse (mean) pred_c pred_k
    gen grp = 1
    tempfile g1
    save `g1'
restore
preserve
    keep if inrange(n_events, 1, 4)
    collapse (mean) pred_c pred_k
    gen grp = 2
    tempfile g2
    save `g2'
restore
keep if n_events >= 5
collapse (mean) pred_c pred_k
gen grp = 3
append using `g1'
append using `g2'
replace pred_c = 100 * pred_c
replace pred_k = 100 * pred_k
tempfile predgrp
save `predgrp'

* observed pooled Post per group
use `coefs', clear
keep if matrix_type == "pooled" & lower(rowname) == "post"
keep if inlist(test, "T_lnhp_base", "T_lnhp_dose14", "T_lnhp_dose5")
gen grp = 1
replace grp = 2 if test == "T_lnhp_dose14"
replace grp = 3 if test == "T_lnhp_dose5"
merge 1:1 grp using `predgrp', nogen

gen xo = grp - 0.12
gen xp = grp + 0.08
gen xk = grp + 0.20

twoway ///
    (rcap ub lb xo, lcolor(navy) lwidth(medthin)) ///
    (scatter b xo, color(navy) msymbol(O) msize(medium)) ///
    (scatter pred_c xp, color(cranberry) msymbol(D) msize(medium)) ///
    (scatter pred_k xk, color(cranberry*.55) msymbol(Dh) msize(medium)) ///
    , graphregion(color(white)) bgcolor(white) ///
    ylabel(0(5)25, angle(horizontal)) ///
    yline(0, lcolor(gs8) lwidth(thin)) ///
    xlabel(1 `""All treated" "tracts""' 2 `""1-4" "purchases""' 3 `""5+" "purchases""', noticks) ///
    xscale(range(0.6 3.4)) ///
    legend(order(2 "Observed tract-DiD effect (95% CI)" ///
                 3 "Ring-implied prediction (central)" ///
                 4 "Ring-implied prediction (conservative)") ///
           rows(3) position(6) region(lstyle(none))) ///
    title("The whole vs the sum of the parts", size(medium)) ///
    ytitle("Pooled post effect on 100 x ln(price)") ///
    xtitle("") ///
    note("Observed: lpdid pooled post estimate (that group vs never-treated tracts). Prediction: stock-value-weighted mean of the" ///
         "estimated distance gradient over each treated tract's parcels -- the tract effect if micro-spillovers were the whole story." ///
         "Excess of observed over predicted in 5+ tracts = the market-level channel operating only under concentration.", size(vsmall)) ///
    name(figT4_reconciliation, replace)
graph export "$OUT/figT4_reconciliation.png", replace width(2000)

di as result _n "Design 2 figures: figT1..figT4"
