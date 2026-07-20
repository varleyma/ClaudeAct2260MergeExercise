/*==============================================================================
 design1_robustness_plots.do

 Plots the coefficient dataset produced by design1_robustness_results.do
 (output/design1/robustness_coefs.dta). Series can be overlaid on ONE graph
 (e.g. real vs placebo) with slight x-offsets, and titles/axis labels are
 set per figure below.

 Column mapping: lpdid's e(results) columns are (verified in lpdid.ado):
   c1=coefficient  c2=se  c3=t  c4=p  c5=ci_low  c6=ci_high  c7=obs
==============================================================================*/

version 17
clear all
set more off

global REPO "C:/Users/mva284/Documents/GitHub/ClaudeAct2260MergeExercise"
global OUT  "$REPO/output/design1"

*---- column mapping for lpdid e(results) (edit here only if lpdid changes) --
local COL_B  c1
local COL_SE c2
local COL_LB c5
local COL_UB c6

/*============================================================================
  LOAD + STANDARDIZE
============================================================================*/
use "$OUT/robustness_coefs.dta", clear
di as text "raw matrix columns were: " colnames[1]

gen b  = `COL_B'
gen se = `COL_SE'
gen lb = `COL_LB'
gen ub = `COL_UB'
* fall back to +/-1.96*se if the matrix has no CI columns
replace lb = b - 1.96*se if missing(lb) & !missing(se)
replace ub = b + 1.96*se if missing(ub) & !missing(se)

* horizon from rownames (numeric, or embedded number like "t-4"/"pre4")
gen horizon = "-"+substr(rowname,4,1) if substr(rowname,1,3) == "pre"
replace horizon = substr(rowname,4,1) if substr(rowname,1,3) == "tau"
destring horizon, replace force
// replace horizon = real(regexs(1)) if missing(horizon) & regexm(rowname, "(-?[0-9]+)")
assert !missing(horizon) if !missing(b)
drop if missing(b)



tempfile coefs
save `coefs'

/*============================================================================
  OVERLAY PLOTTING PROGRAM
  Usage per figure: set globals FIG_TESTS (test names), FIG_LABELS (legend
  labels), FIG_TITLE / FIG_YT / FIG_XT / FIG_NOTE, then:  drawfig, out(name)
  Up to 3 series overlaid on one graph, x-offset so CIs don't overlap.
============================================================================*/
capture program drop drawfig
program define drawfig
    * args: out ; uses globals FIG_TESTS FIG_LABELS FIG_TITLE FIG_YT FIG_XT FIG_NOTE
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
    else        local legend legend(order(`legorder') pos(6) rows(1) region(lstyle(none)))
    twoway `plots', `STYLE' `legend' ///
        title("$FIG_TITLE", size(medium)) ///
        ytitle("$FIG_YT") xtitle("$FIG_XT") ///
        note("$FIG_NOTE", size(vsmall)) ///
        xlabel(-4(1)3)
    graph export "$OUT/`out'.png", replace width(2000)
end

/*============================================================================
  FIGURES
============================================================================*/
local XT "Years since investor purchase (0 = purchase year)"
local YT "Effect on log sale price"

*---- F1: baseline ------------------------------------------------------------
use `coefs', clear
global FIG_TESTS  T1_baseline
global FIG_LABELS `""Near ring (0-250m)""'
global FIG_TITLE  Effect of an Act 22/60 investor purchase on nearby sale prices
global FIG_YT     `YT'
global FIG_XT     `XT'
global FIG_NOTE   Annual lpdid; near ring 0-250m vs control ring 400-1000m; never-treated comparison.
drawfig, out(fig1_baseline)

*---- F2: real vs placebo (the key overlay) ----------------------------------
use `coefs', clear
global FIG_TESTS  T6_real_far750 T6_placebo
global FIG_LABELS `""Investor purchase" "Placebo: non-investor luxury purchase""'
global FIG_TITLE  Investor purchases vs placebo luxury purchases
global FIG_YT     `YT'
global FIG_XT     "Years since (placebo) purchase"
global FIG_NOTE   Far rings matched at 400-750m. Placebo: individual non-investor buyers, investor price band, same micro-areas, >3y from the real event.
drawfig, out(fig2_real_vs_placebo)

*---- F3: distance gradient ---------------------------------------------------
use `coefs', clear
global FIG_TESTS  T1_baseline T3_gradient_gap
global FIG_LABELS `""Near ring (0-250m)" "Gap ring (250-400m)""'
global FIG_TITLE  Spatial decay of the price effect
global FIG_YT     `YT'
global FIG_XT     `XT'
global FIG_NOTE   Both series vs the same 400-1000m control ring.
drawfig, out(fig3_gradient)

*---- F4: dose response -------------------------------------------------------
use `coefs', clear
global FIG_TESTS  T4_dose_low T4_dose_mid T4_dose_high
global FIG_LABELS `""0-2 other events" "3-25 other events" ">25 other events""'
global FIG_TITLE  By density of other investor events within 1km
global FIG_YT     `YT'
global FIG_XT     `XT'
global FIG_NOTE   Splits by n_other_events_within_1000m of the event.
drawfig, out(fig4_dose)

*---- F5: censoring robustness -----------------------------------------------
use `coefs', clear
global FIG_TESTS  T1_baseline T5_late
global FIG_LABELS `""All events (2012+)" "Events 2018+""'
global FIG_TITLE  Robustness to last-sale censoring (late events)
global FIG_YT     `YT'
global FIG_XT     `XT'
global FIG_NOTE   CRIM records only each parcel's most recent sale; late events have short censoring windows.
drawfig, out(fig5_late)

*---- F6: composition outcomes (2x2 grid of single-series panels) ------------
local complabs `" "ln assessed structure value" "ln lot size (cabida)" "share condo sub-units" "share vacant land" "'
local i = 0
foreach y in lnstru lncab subu vac {
    local ++i
    local lab : word `i' of `complabs'
    use `coefs', clear
    global FIG_TESTS  T2_comp_`y'
    global FIG_LABELS `""`lab'""'
    global FIG_TITLE  Composition check: `lab'
    global FIG_YT     Effect on `lab'
    global FIG_XT     `XT'
    global FIG_NOTE   Flat = the price bump is not driven by a change in what transacts.
    drawfig, out(fig6_comp_`y')
}

*---- F7: buyer/seller composition (displacement proxy) ----------------------
* name-based proxy: non-Hispanic-sounding name ~ mainland buyer/seller.
* Caveat for titles/notes: proxy for NAME origin; Hispanic-named mainlanders
* (incl. stateside Puerto Ricans) classify as "local" -> understates effects.
capture confirm file "$OUT/robustness_coefs.dta"
use `coefs', clear
count if test == "T7_buy_nh"
if r(N) > 0 {
    use `coefs', clear
    global FIG_TESTS  T7_buy_nh T7_sell_nh
    global FIG_LABELS `""Buyers" "Sellers""'
    global FIG_TITLE  Non-Hispanic-named parties in nearby sales
    global FIG_YT     "Effect on share with non-Hispanic name"
    global FIG_XT     `XT'
    global FIG_NOTE   Census 2010 surname classification (pcthispanic <=20 vs >=70); corporate/ambiguous names excluded.
    drawfig, out(fig7_parties)

    use `coefs', clear
    global FIG_TESTS  T7_isl2main T7_main2main
    global FIG_LABELS `""Hispanic seller to non-Hispanic buyer" "non-Hispanic seller to non-Hispanic buyer""'
    global FIG_TITLE  Who sells to the incoming buyers?
    global FIG_YT     "Effect on share of transactions"
    global FIG_XT     `XT'
    global FIG_NOTE   Among sales where both parties' names classify. Rising islander-to-mainlander = displacement margin; rising mainlander-to-mainlander = churn within the incomer segment.
    drawfig, out(fig8_transitions)
}

di as result _n "Figures written to $OUT (fig1..fig8_*)"
