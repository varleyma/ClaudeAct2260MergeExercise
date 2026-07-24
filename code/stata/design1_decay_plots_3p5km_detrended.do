/*==============================================================================
 design1_decay_plots_3p5km_detrended.do

 EXPLORATORY: the wide-band (2500-3500m control) decay figures with each
 bin's LINEAR PRE-PERIOD DRIFT projected out.

 Method: for each bin, fit the line through the pre-period event-study
 coefficients constrained to pass through the base period (-1, 0):
     b(h) = s * (h + 1)  on  h in {-4,...,-1}
 and subtract s*(h+1) from every coefficient (pre and post). Pooled points
 are shifted by s * mean(h+1) over their horizons (post: 2.5; pre: -1.5).

 CAVEAT (say it in any presentation): the drift is extrapolated 4+ years
 beyond the pre-window and treated as KNOWN -- confidence intervals are
 shifted, not widened, so they understate uncertainty. This is a
 "what would the broader-market effects look like if the pre-drift is a
 simple linear trend difference between housing markets" exercise, second
 order to the near-control headline spec.

 Figures: figD5_es_inner_3p5_detrended, figD6_es_outer_3p5_detrended,
          figD7_decay_3p5_detrended (raw vs detrended pooled post + detrended pre)
==============================================================================*/

version 17
clear all
set more off

global REPO "C:/Users/mva284/Documents/GitHub/ClaudeAct2260MergeExercise"
global OUT  "$REPO/output/design1"

use "$OUT/decay_coefs_3p5km.dta", clear
gen b  = c1
gen se = c2
gen lb = c5
gen ub = c6
replace lb = b - 1.96*se if missing(lb) & !missing(se)
replace ub = b + 1.96*se if missing(ub) & !missing(se)
drop if missing(b)

* horizons for event rows
gen horizon = .
replace horizon = -real(substr(rowname, 4, .)) if strpos(rowname, "pre") == 1
replace horizon =  real(substr(rowname, 4, .)) if strpos(rowname, "tau") == 1
gen hp1 = horizon + 1

/*============================================================================
  PER-BIN LINEAR PRE-TREND (through the base period) AND DETRENDING
============================================================================*/
gen b_adj  = .
gen lb_adj = .
gen ub_adj = .
gen slope  = .
levelsof test, local(T)
foreach t of local T {
    qui reg b c.hp1 if test == "`t'" & matrix_type == "event" & horizon < 0, nocons
    local s = _b[hp1]
    di as result "bin `t': pre-period linear drift = " %6.4f `s' " per year"
    replace slope = `s' if test == "`t'"
    * event rows: subtract the trend at each horizon
    replace b_adj  = b  - `s'*hp1 if test == "`t'" & matrix_type == "event"
    replace lb_adj = lb - `s'*hp1 if test == "`t'" & matrix_type == "event"
    replace ub_adj = ub - `s'*hp1 if test == "`t'" & matrix_type == "event"
    * pooled rows: shift by s * mean(h+1) over pooled horizons
    replace b_adj  = b  - `s'*2.5    if test == "`t'" & matrix_type == "pooled" & lower(rowname) == "post"
    replace lb_adj = lb - `s'*2.5    if test == "`t'" & matrix_type == "pooled" & lower(rowname) == "post"
    replace ub_adj = ub - `s'*2.5    if test == "`t'" & matrix_type == "pooled" & lower(rowname) == "post"
    replace b_adj  = b  + `s'*1.5    if test == "`t'" & matrix_type == "pooled" & lower(rowname) == "pre"
    replace lb_adj = lb + `s'*1.5    if test == "`t'" & matrix_type == "pooled" & lower(rowname) == "pre"
    replace ub_adj = ub + `s'*1.5    if test == "`t'" & matrix_type == "pooled" & lower(rowname) == "pre"
}
tempfile coefs
save `coefs'

/*============================================================================
  DETRENDED EVENT-STUDY OVERLAYS
============================================================================*/
capture program drop drawadj
program define drawadj
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
            (rcap ub_adj lb_adj x`i' if test == "`t'", lcolor(`col') lwidth(medthin)) ///
            (connected b_adj x`i' if test == "`t'", color(`col') msymbol(O) lwidth(medthin))
        local legorder `legorder' `= 2*`i'' "`lab'"
    }
    twoway `plots', `STYLE' ///
        legend(order(`legorder') rows(1) region(lstyle(none))) ///
        title("$FIG_TITLE", size(medium)) ///
        ytitle("$FIG_YT") xtitle("$FIG_XT") ///
        note("$FIG_NOTE", size(vsmall)) ///
        xlabel(-4(1)3) name(`out', replace)
    graph export "$OUT/`out'.png", replace width(2000)
end

local XT "Years since investor purchase (0 = purchase year)"
local YT "Detrended effect on log sale price"
local CAVEAT "EXPLORATORY: per-bin linear pre-drift projected out (fit through base period, extrapolated post); CIs shifted, not widened -- uncertainty understated. Control band 2,500-3,500m."

use `coefs', clear
keep if matrix_type == "event"
global FIG_TESTS  D_0_250 D_250_500 D_500_1000
global FIG_LABELS `""0-250m" "250-500m" "500-1000m""'
global FIG_TITLE  Detrended: inner rings vs 2.5-3.5km control
global FIG_YT     `YT'
global FIG_XT     `XT'
global FIG_NOTE   `CAVEAT'
drawadj, out(figD5_es_inner_3p5_detrended)

use `coefs', clear
keep if matrix_type == "event"
global FIG_TESTS  D_1000_1750 D_1750_2500
global FIG_LABELS `""1,000-1,750m" "1,750-2,500m""'
global FIG_TITLE  Detrended: outer rings vs 2.5-3.5km control
global FIG_YT     `YT'
global FIG_XT     `XT'
global FIG_NOTE   `CAVEAT'
drawadj, out(figD6_es_outer_3p5_detrended)

/*============================================================================
  DECAY CURVE: raw vs detrended pooled post (+ detrended pooled pre)
============================================================================*/
use `coefs', clear
keep if matrix_type == "pooled"
gen post = lower(rowname) == "post"
gen mid = .
replace mid = 125  if test == "D_0_250"
replace mid = 375  if test == "D_250_500"
replace mid = 750  if test == "D_500_1000"
replace mid = 1375 if test == "D_1000_1750"
replace mid = 2125 if test == "D_1750_2500"
drop if missing(mid)
gen x  = mid
gen xr = mid - 55
gen xp = mid + 55
sort post x

twoway ///
    (rcap ub lb xr if post, lcolor(gs10) lwidth(thin)) ///
    (connected b xr if post, color(gs10) msymbol(Th) lpattern(shortdash) lwidth(thin) sort(xr)) ///
    (rcap ub_adj lb_adj x if post, lcolor(navy) lwidth(medthin)) ///
    (connected b_adj x if post, color(navy) msymbol(O) lwidth(medthin) sort(x)) ///
    (connected b_adj xp if !post, color(gs9) msymbol(Oh) lpattern(dash) lwidth(thin) sort(xp)) ///
    , graphregion(color(white)) bgcolor(white) ///
    ylabel(, angle(horizontal) format(%9.2f)) ///
    yline(0, lcolor(gs8) lwidth(thin)) ///
    legend(order(4 "Detrended pooled post effect" 2 "Raw pooled post (unadjusted)" ///
                 5 "Detrended pooled pre (should be ~0)") ///
           rows(3) position(6) region(lstyle(none))) ///
    title("Spatial decay, linear pre-drift removed (2.5-3.5km control)", size(medium)) ///
    ytitle("Pooled effect on log sale price") ///
    xtitle("Distance from investor purchase (ring midpoint, meters)") ///
    xlabel(125 "125" 375 "375" 750 "750" 1375 "1,375" 2125 "2,125") ///
    note("`CAVEAT'", size(vsmall)) ///
    name(figD7_decay_3p5_detrended, replace)
graph export "$OUT/figD7_decay_3p5_detrended.png", replace width(2000)

di as result _n "Detrended figures: figD5, figD6, figD7 (_3p5_detrended)"
