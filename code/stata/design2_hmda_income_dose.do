/*==============================================================================
 design2_hmda_income_dose.do

 Dose split for the HMDA borrower-income result: mean purchase-borrower
 income (100 x ln) in tracts with 5+ identified purchases vs 1-4, each
 group vs never-treated tracts (same split as the tract price dose figure).

 Outputs: output/design2/hmda_income_dose_coefs.csv, figH6_income_dose.png
==============================================================================*/

version 17
clear all
set more off

global REPO "C:/Users/mva284/Documents/GitHub/ClaudeAct2260MergeExercise"
global D2   "$REPO/data/design2"
global OUT  "$REPO/output/design2"

capture which reghdfe
if _rc ssc install reghdfe, replace

import delimited "$REPO/data/cleaned/pr_tract_zcta_crosswalk.csv", varnames(1) clear
keep tract_geoid
duplicates drop
expand 7
bysort tract_geoid: gen year = 2017 + _n
tempfile frame
save `frame'

import delimited "$D2/hmda_tract_year.csv", varnames(1) clear
merge 1:1 tract_geoid year using `frame', nogen
foreach v in purch_hisp_inc purch_hisp_incn purch_nonhisp_inc purch_nonhisp_incn {
    replace `v' = 0 if missing(`v')
}

preserve
    import delimited "$D2/design2_tract_treatment.csv", varnames(1) clear
    tempfile trt
    save `trt'
restore
merge m:1 tract_geoid using `trt', keep(master match) nogen

gen treat = !missing(first_event_year) & year >= first_event_year
gen rel = year - first_event_year if !missing(first_event_year)
gen Dm4 = !missing(rel) & rel <= -4
gen Dm3 = !missing(rel) & rel == -3
gen Dm2 = !missing(rel) & rel == -2
gen D0  = !missing(rel) & rel == 0
gen D1  = !missing(rel) & rel == 1
gen D2  = !missing(rel) & rel == 2
gen D3  = !missing(rel) & rel >= 3

gen lninc_all = 100 * ln((purch_hisp_inc + purch_nonhisp_inc) / ///
                         (purch_hisp_incn + purch_nonhisp_incn)) ///
                if purch_hisp_incn + purch_nonhisp_incn > 0
egen tract_num = group(tract_geoid)
gen nevertr = missing(first_event_year)
tempfile panel
save `panel'

log using "$OUT/hmda_income_dose.log", replace text

tempname pf
postfile `pf' str10 test double h b se using "$OUT/_hid.dta", replace

foreach g in hi5 lo14 {
    use `panel', clear
    if "`g'" == "hi5"  keep if nevertr | n_events >= 5
    if "`g'" == "lo14" keep if nevertr | inrange(n_events, 1, 4)
    di as result _n "===== lninc_all, dose group `g' ====="
    reghdfe lninc_all Dm4 Dm3 Dm2 D0 D1 D2 D3, absorb(tract_num year) ///
        vce(cluster tract_num)
    post `pf' ("`g'") (-4) (_b[Dm4]) (_se[Dm4])
    post `pf' ("`g'") (-3) (_b[Dm3]) (_se[Dm3])
    post `pf' ("`g'") (-2) (_b[Dm2]) (_se[Dm2])
    post `pf' ("`g'") (-1) (0) (.)
    post `pf' ("`g'") (0)  (_b[D0]) (_se[D0])
    post `pf' ("`g'") (1)  (_b[D1]) (_se[D1])
    post `pf' ("`g'") (2)  (_b[D2]) (_se[D2])
    post `pf' ("`g'") (3)  (_b[D3]) (_se[D3])

    di as result _n "===== lninc_all pooled, dose group `g' ====="
    reghdfe lninc_all treat, absorb(tract_num year) vce(cluster tract_num)
    post `pf' ("`g'") (99) (_b[treat]) (_se[treat])
}
postclose `pf'
log close

use "$OUT/_hid.dta", clear
gen lb = b - 1.96*se
gen ub = b + 1.96*se
export delimited "$OUT/hmda_income_dose_coefs.csv", replace
capture erase "$OUT/_hid.dta"

*---- plot ------------------------------------------------------------------
drop if h == 99
rename h horizon
sort test horizon
gen x1 = horizon - 0.06 if test == "hi5"
gen x2 = horizon + 0.06 if test == "lo14"
twoway ///
    (rcap ub lb x1 if test == "hi5", lcolor(navy) lwidth(medthin)) ///
    (connected b x1 if test == "hi5", color(navy) msymbol(O) lwidth(medthin)) ///
    (rcap ub lb x2 if test == "lo14", lcolor(cranberry) lwidth(medthin)) ///
    (connected b x2 if test == "lo14", color(cranberry) msymbol(O) lwidth(medthin)) ///
    , graphregion(color(white)) bgcolor(white) ///
    ylabel(, angle(horizontal) format(%9.0f)) ///
    yline(0, lcolor(gs8) lwidth(thin)) ///
    xline(-0.5, lcolor(gs11) lpattern(dash)) ///
    legend(order(2 "Tracts with 5+ purchases" 4 "Tracts with 1-4 purchases") ///
           rows(1) position(6) region(lstyle(none))) ///
    title("Borrower income by investor concentration", size(medium)) ///
    ytitle("Effect on 100 x ln(mean borrower income)") ///
    xtitle("Years since first investor purchase in tract") ///
    note("Each series: that treated group vs never-treated tracts; tract and year FE, clustered by tract." ///
         "Mean income of purchase borrowers (HMDA, financed side of the market)." ///
         "CAUTION: for the 5+ group, h <= -3 is identified off only 2-3 late-adopting tracts (panel starts 2018) -- uninformative.", size(vsmall)) ///
    xlabel(-4(1)3) name(figH6, replace)
graph export "$OUT/figH6_income_dose.png", replace width(2000)
di as result "Saved figH6_income_dose.png"
