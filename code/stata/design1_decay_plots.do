/*==============================================================================
 design1_decay_plots.do

 Plots for the spatial-decay results (decay_coefs.dta from
 design1_decay_results.do).

 Figures:
   figD1_es_inner   event-study overlay: 0-250 / 250-500 / 500-1000 bins
   figD2_es_outer   event-study overlay: 1000-1750 / 1750-2500 bins
   figD3_decay      THE decay curve: pooled post-treatment effect (95% CI)
                    against ring distance, with the pooled pre-period placebo
                    series alongside -- the maximal-precision spatial profile.

 lpdid matrix columns: c1=coefficient c2=se c3=t c4=p c5=ci_low c6=ci_high c7=obs
==============================================================================*/

version 17
clear all
set more off

global REPO "C:/Users/mva284/Documents/GitHub/ClaudeAct2260MergeExercise"
global OUT  "$REPO/output/design1"

local COL_B  c1
local COL_SE c2
local COL_LB c5
local COL_UB c6

use "$OUT/decay_coefs.dta", clear
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
  EVENT-STUDY OVERLAYS (same drawfig pattern as the robustness plots)
============================================================================*/
capture program drop drawfig
program define drawfig
    syntax, out(string)
    local STYLE  graphregion(color(white)) bgcolor(white) ///
                 ylabel(, angle(horizontal) format(%9.2f)) ///
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
    else        local legend legend(order(`legorder') rows(1) region(lstyle(none)))
    twoway `plots', `STYLE' `legend' ///
        title("$FIG_TITLE", size(medium)) ///
        ytitle("$FIG_YT") xtitle("$FIG_XT") ///
        note("$FIG_NOTE", size(vsmall)) ///
        xlabel(-4(1)3) name(`out', replace)
    graph export "$OUT/`out'.png", replace width(2000)
end

local XT "Years since investor purchase (0 = purchase year)"
local YT "Effect on log sale price"

* horizon for event-study rows
use `coefs', clear
keep if matrix_type == "event"
* lpdid rownames: pre4..pre1 (leads; pre1 = base) and tau0..tau3 (lags)
gen horizon = .
replace horizon = -real(substr(rowname, 4, .)) if strpos(rowname, "pre") == 1
replace horizon =  real(substr(rowname, 4, .)) if strpos(rowname, "tau") == 1
replace horizon = real(rowname) if missing(horizon)
drop if missing(horizon)
tempfile es
save `es'

use `es', clear
global FIG_TESTS  D_0_250 D_250_500 D_500_1000
global FIG_LABELS `""0-250m" "250-500m" "500-1000m""'
global FIG_TITLE  Spatial decay: inner rings vs common control band
global FIG_YT     `YT'
global FIG_XT     `XT'
global FIG_NOTE   Each series: that ring vs the common control band (set in design1_decay_results.do). Annual lpdid.
drawfig, out(figD1_es_inner)

use `es', clear
global FIG_TESTS  D_1000_1500
global FIG_LABELS `""1,000-1,500m""'
global FIG_TITLE  Spatial decay: outermost treated ring vs common control band
global FIG_YT     `YT'
global FIG_XT     `XT'
global FIG_NOTE   The ring adjacent to the control band; its estimate bounds the gradient at the control boundary.
drawfig, out(figD2_es_outer)

/*============================================================================
  THE DECAY CURVE (pooled post effect vs distance, with pre-period placebo)
============================================================================*/
use `coefs', clear
keep if matrix_type == "pooled"
gen post = lower(rowname) == "post"
gen mid = .
replace mid = 125  if test == "D_0_250"
replace mid = 375  if test == "D_250_500"
replace mid = 750  if test == "D_500_1000"
replace mid = 1250 if test == "D_1000_1500"
drop if missing(mid)
* offset pre series slightly for visibility
gen x = mid + cond(post, 0, 40)
sort post x   // connected() joins in data order -- must be sorted by x

twoway ///
    (rcap ub lb x if post, lcolor(navy) lwidth(medthin)) ///
    (connected b x if post, color(navy) msymbol(O) lwidth(medthin) sort(x)) ///
    (rcap ub lb x if !post, lcolor(gs9) lwidth(thin)) ///
    (connected b x if !post, color(gs9) msymbol(Oh) lpattern(dash) lwidth(thin) sort(x)) ///
    , graphregion(color(white)) bgcolor(white) ///
    ylabel(, angle(horizontal) format(%9.2f)) ///
    yline(0, lcolor(gs8) lwidth(thin)) ///
    legend(order(2 "Pooled post-treatment effect" 4 "Pooled pre-period (placebo)") ///
           rows(2) position(6) region(lstyle(none))) ///
    title("Spatial decay of the price effect", size(medium)) ///
    ytitle("Pooled effect on log sale price") ///
    xtitle("Distance from investor purchase (ring midpoint, meters)") ///
    xlabel(125 "125" 375 "375" 750 "750" 1250 "1,250") ///
    note("Each point: one ring vs the common control band (set in design1_decay_results.do); annual lpdid, pooled across horizons 0-3." ///
         "Gray dashed: the same object for pooled pre-period years -- a distance-profile placebo.", size(vsmall)) ///
    name(figD3_decay, replace)
graph export "$OUT/figD3_decay.png", replace width(2000)

di as result _n "Decay figures written: figD1_es_inner, figD2_es_outer, figD3_decay"
