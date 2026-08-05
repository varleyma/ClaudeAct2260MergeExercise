/*==============================================================================
 design1_salelevel_plots.do

 Figure: the near-ring event study estimated two ways --
   (a) cell-level lpdid (the paper's baseline, from robustness_coefs.dta
       T1_baseline) and
   (b) transaction-level stacked OLS (literature convention, S3 from
       salelevel_coefs.csv) -- overlaid on one graph, plus the hedonic
       variant S4 as a third series.

 Output: output/design1/figD12_salelevel_robustness.png
==============================================================================*/

version 17
clear all
set more off

global REPO "C:/Users/mva284/Documents/GitHub/ClaudeAct2260MergeExercise"
global OUT  "$REPO/output/design1"

* (a) cell-level lpdid baseline
use "$REPO/output/design1/robustness_coefs.dta", clear
keep if test == "T1_baseline"
* (this dataset predates the pooled-matrix capture: all rows are event rows)
gen b  = c1
gen se = c2
gen lb = c5
gen ub = c6
replace lb = b - 1.96*se if missing(lb) & !missing(se)
replace ub = b + 1.96*se if missing(ub) & !missing(se)
gen horizon = .
replace horizon = -real(substr(rowname, 4, .)) if strpos(rowname, "pre") == 1
replace horizon =  real(substr(rowname, 4, .)) if strpos(rowname, "tau") == 1
drop if missing(horizon) | missing(b)
keep horizon b lb ub
gen spec = "lpdid_cells"
tempfile a
save `a'

* (b) sale-level specs
import delimited "$OUT/salelevel_coefs.csv", varnames(1) clear
keep if inlist(spec, "S3_es", "S4_es_hed") & h != 99
rename h horizon
append using `a'
* lpdid coefficients are in log points x1 vs sale-level in logs -> both are
* log points already (lpdid ran on lnp in logs; sale-level b in logs). Scale
* both x100 for percent display.
foreach v in b lb ub {
    replace `v' = 100 * `v'
}
sort spec horizon

local STYLE  graphregion(color(white)) bgcolor(white) ///
             ylabel(, angle(horizontal) format(%9.0f)) ///
             yline(0, lcolor(gs8) lwidth(thin)) ///
             xline(-0.5, lcolor(gs11) lpattern(dash))
capture drop x1 x2 x3
gen x1 = horizon - 0.12 if spec == "lpdid_cells"
gen x2 = horizon        if spec == "S3_es"
gen x3 = horizon + 0.12 if spec == "S4_es_hed"

twoway ///
    (rcap ub lb x1 if spec == "lpdid_cells", lcolor(navy) lwidth(medthin)) ///
    (connected b x1 if spec == "lpdid_cells", color(navy) msymbol(O) lwidth(medthin) sort(x1)) ///
    (rcap ub lb x2 if spec == "S3_es", lcolor(cranberry) lwidth(medthin)) ///
    (connected b x2 if spec == "S3_es", color(cranberry) msymbol(D) lwidth(medthin) sort(x2)) ///
    (rcap ub lb x3 if spec == "S4_es_hed", lcolor(dkorange) lwidth(thin)) ///
    (connected b x3 if spec == "S4_es_hed", color(dkorange) msymbol(Th) lpattern(dash) lwidth(thin) sort(x3)) ///
    , `STYLE' ///
    legend(order(2 "Cell-level LP-DiD (baseline)" ///
                 4 "Sale-level stacked OLS" ///
                 6 "Sale-level + hedonics") rows(3) position(6) region(lstyle(none))) ///
    title("Ring design: cell-level vs transaction-level estimation", size(medium)) ///
    ytitle("Effect on log sale price (x100)") ///
    xtitle("Years since investor purchase (0 = purchase year)") ///
    xlabel(-4(1)3) ///
    note("Baseline: event x ring x year cell means, lpdid, never-treated far rings. Sale-level: stacked transactions, event x ring" ///
         "and event x calendar-year FE, SEs clustered by event (Linden-Rockoff / stacking convention). Rings 0-250m vs 400-1,000m.", size(vsmall)) ///
    name(figD12_salelevel, replace)
graph export "$OUT/figD12_salelevel_robustness.png", replace width(2000)

di as result _n "Saved figD12_salelevel_robustness.png"
