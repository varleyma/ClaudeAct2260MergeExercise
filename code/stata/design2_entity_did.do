/*==============================================================================
 design2_entity_did.do

 Institutional-deployment tract DiD: did the decree shock crowd in
 portfolio-scale (institutional) buyers? Same design as the HMDA tract
 DiD: staggered treatment at the tract's first identified decree purchase,
 never-treated tracts as controls, Poisson (ppmlhdfe) with tract and year
 FE, event window -4..+3 with binned endpoints; pooled treat coefficient.

 Outcomes (tract-year counts from CRIM, banks/REO excluded):
   entity_n   all non-bank entity purchases  (decree buyers' LLC wrappers
              SHOULD respond -> positive = detection power on this margin)
   port10_n   purchases by portfolio clusters holding 10+ parcels
   port25_n   ... 25+ parcels               (the institutional signature)

 Panel 2012-2025. Output: output/design2/entity_did_coefs.csv,
 figE3_portfolio_did.png, entity_did.log
==============================================================================*/

version 17
clear all
set more off

global REPO "C:/Users/mva284/Documents/GitHub/ClaudeAct2260MergeExercise"
global D2   "$REPO/data/design2"
global OUT  "$REPO/output/design2"

capture which ppmlhdfe
if _rc ssc install ppmlhdfe, replace

import delimited "$REPO/data/cleaned/pr_tract_zcta_crosswalk.csv", varnames(1) stringcols(1) clear
keep tract_geoid
duplicates drop
expand 14
bysort tract_geoid: gen year = 2011 + _n
tempfile frame
save `frame'

import delimited "$D2/entity_tract_year.csv", varnames(1) stringcols(1) clear
keep if inrange(year, 2012, 2025)
merge 1:1 tract_geoid year using `frame', nogen
foreach v in sales_n entity_n port10_n port25_n {
    replace `v' = 0 if missing(`v')
}

preserve
    import delimited "$D2/design2_tract_treatment.csv", varnames(1) stringcols(1) clear
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
local DVARS Dm4 Dm3 Dm2 D0 D1 D2 D3

egen tract_num = group(tract_geoid)
tempfile panel
save `panel'

log using "$OUT/entity_did.log", replace text

tempname pf
postfile `pf' str16 test double h b se using "$OUT/_ed.dta", replace

foreach v in entity_n port10_n port25_n {
    use `panel', clear
    di as result _n "===== POISSON `v' (tract DiD, 2012-2025) ====="
    ppmlhdfe `v' `DVARS', absorb(tract_num year) vce(cluster tract_num)
    post `pf' ("`v'") (-4) (_b[Dm4]) (_se[Dm4])
    post `pf' ("`v'") (-3) (_b[Dm3]) (_se[Dm3])
    post `pf' ("`v'") (-2) (_b[Dm2]) (_se[Dm2])
    post `pf' ("`v'") (-1) (0) (.)
    post `pf' ("`v'") (0)  (_b[D0]) (_se[D0])
    post `pf' ("`v'") (1)  (_b[D1]) (_se[D1])
    post `pf' ("`v'") (2)  (_b[D2]) (_se[D2])
    post `pf' ("`v'") (3)  (_b[D3]) (_se[D3])

    di as result _n "===== POISSON pooled `v' ====="
    ppmlhdfe `v' treat, absorb(tract_num year) vce(cluster tract_num)
    post `pf' ("`v'") (99) (_b[treat]) (_se[treat])
}

*---- LEVELS version (OLS): absolute bound in purchases per tract-year -------
* Poisson gives proportional effects with wide CIs on rare counts; OLS in
* levels bounds the ABSOLUTE response directly (baseline: treated tracts
* averaged 0.32 portfolio purchases per tract-year pre-treatment).
tempname pl
postfile `pl' str16 test double h b se using "$OUT/_edl.dta", replace
foreach v in port10_n port25_n {
    use `panel', clear
    di as result _n "===== OLS LEVELS `v' (tract DiD) ====="
    reghdfe `v' `DVARS', absorb(tract_num year) vce(cluster tract_num)
    post `pl' ("`v'") (-4) (_b[Dm4]) (_se[Dm4])
    post `pl' ("`v'") (-3) (_b[Dm3]) (_se[Dm3])
    post `pl' ("`v'") (-2) (_b[Dm2]) (_se[Dm2])
    post `pl' ("`v'") (-1) (0) (.)
    post `pl' ("`v'") (0)  (_b[D0]) (_se[D0])
    post `pl' ("`v'") (1)  (_b[D1]) (_se[D1])
    post `pl' ("`v'") (2)  (_b[D2]) (_se[D2])
    post `pl' ("`v'") (3)  (_b[D3]) (_se[D3])

    di as result _n "===== OLS LEVELS pooled `v' ====="
    reghdfe `v' treat, absorb(tract_num year) vce(cluster tract_num)
    post `pl' ("`v'") (99) (_b[treat]) (_se[treat])
}
postclose `pl'
postclose `pf'
log close

use "$OUT/_edl.dta", clear
gen lb = b - 1.96*se
gen ub = b + 1.96*se
export delimited "$OUT/entity_did_levels_coefs.csv", replace
capture erase "$OUT/_edl.dta"

use "$OUT/_ed.dta", clear
gen lb = b - 1.96*se
gen ub = b + 1.96*se
export delimited "$OUT/entity_did_coefs.csv", replace
capture erase "$OUT/_ed.dta"

*---- figure: entity vs portfolio event studies ------------------------------
drop if h == 99
foreach v in b lb ub {
    replace `v' = 100 * `v'
}
rename h horizon
rename test test0
gen test = test0
sort test horizon
gen x1 = horizon - 0.06 if test == "entity_n"
gen x2 = horizon + 0.06 if test == "port10_n"
twoway ///
    (rcap ub lb x1 if test == "entity_n", lcolor(navy) lwidth(medthin)) ///
    (connected b x1 if test == "entity_n", color(navy) msymbol(O) lwidth(medthin)) ///
    (rcap ub lb x2 if test == "port10_n", lcolor(cranberry) lwidth(medthin)) ///
    (connected b x2 if test == "port10_n", color(cranberry) msymbol(O) lwidth(medthin)) ///
    , graphregion(color(white)) bgcolor(white) ///
    ylabel(, angle(horizontal) format(%9.0f)) ///
    yline(0, lcolor(gs8) lwidth(thin)) ///
    xline(-0.5, lcolor(gs11) lpattern(dash)) ///
    legend(order(2 "All entity purchases (small LLCs incl.)" ///
                 4 "Portfolio-scale buyers (10+ properties)") ///
           rows(1) position(6) region(lstyle(none))) ///
    title("Entity and institutional purchases around decree treatment", size(medium)) ///
    ytitle("Effect on purchase counts (100 x Poisson coef ~ %)") ///
    xtitle("Years since first investor purchase in tract") ///
    note("ppmlhdfe with tract and year FE, never-treated tracts as controls, SEs clustered by tract; endpoints binned at -4 and +3." ///
         "Counts from CRIM (sales >$10k; banks/coops/GSEs excluded). Portfolio clusters: same buyer name or rolled-up mailing" ///
         "address holding 10+ parcels island-wide. Panel 2012-2025.", size(vsmall)) ///
    xlabel(-4(1)3) name(figE3, replace)
graph export "$OUT/figE3_portfolio_did.png", replace width(2000)

*---- figE3a: all entity purchases alone (Poisson) ---------------------------
import delimited "$OUT/entity_did_coefs.csv", varnames(1) clear
drop if h == 99
keep if test == "entity_n"
foreach v in b lb ub {
    replace `v' = 100 * `v'
}
rename h horizon
sort horizon
twoway ///
    (rcap ub lb horizon, lcolor(navy) lwidth(medthin)) ///
    (connected b horizon, color(navy) msymbol(O) lwidth(medthin)) ///
    , graphregion(color(white)) bgcolor(white) ///
    ylabel(, angle(horizontal) format(%9.0f)) ///
    yline(0, lcolor(gs8) lwidth(thin)) ///
    xline(-0.5, lcolor(gs11) lpattern(dash)) ///
    legend(off) ///
    title("Entity purchases around decree treatment", size(medium)) ///
    ytitle("Effect on entity purchase counts (100 x Poisson coef ~ %)") ///
    xtitle("Years since first investor purchase in tract") ///
    note("ppmlhdfe with tract and year FE, never-treated tracts as controls, SEs clustered by tract; endpoints binned at -4 and +3." ///
         "Non-bank corporate-form buyers (LLC/Corp/LP/...), CRIM sales >$10k, panel 2012-2025. Pooled treat: +12.1% (s.e. 13.5)." ///
         "Treated tracts' raw entity purchases sextuple post-treatment -- but so do never-treated tracts': the island-wide LLC" ///
         "boom is not differentially concentrated where decree buyers land.", size(vsmall)) ///
    xlabel(-4(1)3) name(figE3a, replace)
graph export "$OUT/figE3a_entity_did.png", replace width(2000)

*---- figE3b: portfolio buyers, ABSOLUTE levels ------------------------------
import delimited "$OUT/entity_did_levels_coefs.csv", varnames(1) clear
drop if h == 99
keep if test == "port10_n"
rename h horizon
sort horizon
twoway ///
    (rcap ub lb horizon, lcolor(cranberry) lwidth(medthin)) ///
    (connected b horizon, color(cranberry) msymbol(O) lwidth(medthin)) ///
    , graphregion(color(white)) bgcolor(white) ///
    ylabel(, angle(horizontal) format(%9.1f)) ///
    yline(0, lcolor(gs8) lwidth(thin)) ///
    xline(-0.5, lcolor(gs11) lpattern(dash)) ///
    legend(off) ///
    title("Portfolio-scale purchases: absolute response", size(medium)) ///
    ytitle("Additional portfolio purchases per tract-year") ///
    xtitle("Years since first investor purchase in tract") ///
    note("OLS in LEVELS (counts per tract-year), tract and year FE, never-treated controls, SEs clustered by tract; endpoints binned." ///
         "Purchases by clusters holding 10+ parcels (name or rolled-up mailing address; banks excluded). Treated tracts' baseline:" ///
         "0.32 portfolio purchases per tract-year (1.3% of sales). Post-year CIs rule out more than ~0.6 additional portfolio" ///
         "purchases per tract-year; deep post bins (4-6 and 7+ years, not shown) are also null. The year-0 point is a noisy blip" ///
         "from a handful of bulk events coinciding with treatment onset. Pooled specifications without pre-period dummies are" ///
         "misleading here (staggered weighting); the event study is the bound.", size(vsmall)) ///
    xlabel(-4(1)3) name(figE3b, replace)
graph export "$OUT/figE3b_portfolio_levels.png", replace width(2000)

di as result "Saved figE3, figE3a, figE3b"
