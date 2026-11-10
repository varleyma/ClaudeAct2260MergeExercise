/*==============================================================================
 design1_presentation_figs.do

 Presentation variants of three canonical figures, replotted from the saved
 coefficient files (no re-estimation):

   fig1_baseline_pres.png  from robustness_coefs.dta (T1_baseline)
   figD3_decay_pres.png    from decay_coefs.dta (pooled rows)
   fig4_dose_pres.png      from dose2_coefs.csv (T4b_lo14 / T4b_hi5)

 Differences vs the canonical versions (which are NOT overwritten):
   - no title, no note/caption
   - x- and y-axis titles 25% larger (size(*1.25))
   - axis tick labels 25% larger (labsize(*1.25))
   - legends on one row and 25% larger (rows(1) size(*1.25))
 Everything else (styling, series, CIs, legends) matches the originals in
 design1_robustness_plots.do / design1_decay_plots.do / design1_dose_2way.do.

 lpdid matrix columns: c1=coefficient c2=se c3=t c4=p c5=ci_low c6=ci_high c7=obs
==============================================================================*/

version 17
clear all
set more off

global REPO "C:/Users/mva284/Documents/GitHub/ClaudeAct2260MergeExercise"
global OUT  "$REPO/output/design1"

local XT "Years since investor purchase (0 = purchase year)"
local YT "Effect on log sale price"

/*============================================================================
  FIG 1: baseline event study (single series, no legend)
============================================================================*/
use "$OUT/robustness_coefs.dta", clear
gen b  = c1
gen se = c2
gen lb = c5
gen ub = c6
replace lb = b - 1.96*se if missing(lb) & !missing(se)
replace ub = b + 1.96*se if missing(ub) & !missing(se)
gen horizon = "-"+substr(rowname,4,1) if substr(rowname,1,3) == "pre"
replace horizon = substr(rowname,4,1) if substr(rowname,1,3) == "tau"
destring horizon, replace force
drop if missing(horizon) | missing(b)
keep if test == "T1_baseline"

twoway ///
    (rcap ub lb horizon, lcolor(navy) lwidth(medthin)) ///
    (connected b horizon, color(navy) msymbol(O) lwidth(medthin)) ///
    , graphregion(color(white)) bgcolor(white) ///
    ylabel(, angle(horizontal) format(%9.2f) labsize(*1.25)) ///
    yline(0, lcolor(gs8) lwidth(thin)) ///
    xline(-0.5, lcolor(gs11) lpattern(dash)) ///
    legend(off) ///
    ytitle("`YT'", size(*1.25)) ///
    xtitle("`XT'", size(*1.25)) ///
    xlabel(-4(1)3, labsize(*1.25)) name(fig1_baseline_pres, replace)
graph export "$OUT/fig1_baseline_pres.png", replace width(2000)

/*============================================================================
  FIG D3: decay curve (pooled post vs distance, pre-period placebo alongside)
============================================================================*/
use "$OUT/decay_coefs.dta", clear
gen b  = c1
gen se = c2
gen lb = c5
gen ub = c6
replace lb = b - 1.96*se if missing(lb) & !missing(se)
replace ub = b + 1.96*se if missing(ub) & !missing(se)
drop if missing(b)
keep if matrix_type == "pooled"
gen post = lower(rowname) == "post"
gen mid = .
replace mid = 125  if test == "D_0_250"
replace mid = 375  if test == "D_250_500"
replace mid = 750  if test == "D_500_1000"
replace mid = 1250 if test == "D_1000_1500"
drop if missing(mid)
gen x = mid + cond(post, 0, 40)
sort post x

twoway ///
    (rcap ub lb x if post, lcolor(navy) lwidth(medthin)) ///
    (connected b x if post, color(navy) msymbol(O) lwidth(medthin) sort(x)) ///
    (rcap ub lb x if !post, lcolor(gs9) lwidth(thin)) ///
    (connected b x if !post, color(gs9) msymbol(Oh) lpattern(dash) lwidth(thin) sort(x)) ///
    , graphregion(color(white)) bgcolor(white) ///
    ylabel(, angle(horizontal) format(%9.2f) labsize(*1.25)) ///
    yline(0, lcolor(gs8) lwidth(thin)) ///
    legend(order(2 "Pooled post-treatment effect" 4 "Pooled pre-period (placebo)") ///
           rows(1) position(6) region(lstyle(none)) size(*1.25)) ///
    ytitle("Pooled effect on log sale price", size(*1.25)) ///
    xtitle("Distance from investor purchase (ring midpoint, meters)", size(*1.25)) ///
    xlabel(125 "125" 375 "375" 750 "750" 1250 "1,250", labsize(*1.25)) ///
    name(figD3_decay_pres, replace)
graph export "$OUT/figD3_decay_pres.png", replace width(2000)

/*============================================================================
  FIG 4: dose response, 2-way split (1-4 vs 5+ purchases within 1km)
============================================================================*/
import delimited "$OUT/dose2_coefs.csv", varnames(1) clear
keep if matrix_type == "event"
gen horizon = -real(substr(rowname,4,1)) if substr(rowname,1,3) == "pre"
replace horizon = real(substr(rowname,4,1)) if substr(rowname,1,3) == "tau"
drop if missing(horizon) | missing(c1)
gen b  = c1
gen lb = c5
gen ub = c6
sort test horizon
gen x1 = horizon - 0.06 if test == "T4b_lo14"
gen x2 = horizon + 0.06 if test == "T4b_hi5"

twoway ///
    (rcap ub lb x1 if test == "T4b_lo14", lcolor(cranberry) lwidth(medthin)) ///
    (connected b x1 if test == "T4b_lo14", color(cranberry) msymbol(O) lwidth(medthin)) ///
    (rcap ub lb x2 if test == "T4b_hi5", lcolor(navy) lwidth(medthin)) ///
    (connected b x2 if test == "T4b_hi5", color(navy) msymbol(O) lwidth(medthin)) ///
    , graphregion(color(white)) bgcolor(white) ///
    ylabel(, angle(horizontal) labsize(*1.25)) ///
    yline(0, lcolor(gs8) lwidth(thin)) ///
    xline(-0.5, lcolor(gs11) lpattern(dash)) ///
    legend(order(2 "1-4 purchases within 1km" 4 "5+ purchases within 1km") ///
           rows(1) position(6) region(lstyle(none)) size(*1.25)) ///
    ytitle("`YT'", size(*1.25)) ///
    xtitle("`XT'", size(*1.25)) ///
    xlabel(-4(1)3, labsize(*1.25)) name(fig4_dose_pres, replace)
graph export "$OUT/fig4_dose_pres.png", replace width(2000)

di as result _n "Presentation figures written: fig1_baseline_pres, figD3_decay_pres, fig4_dose_pres"
