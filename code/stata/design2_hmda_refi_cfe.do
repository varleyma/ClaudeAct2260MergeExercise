/*==============================================================================
 design2_hmda_refi_cfe.do

 NOT USED IN THE WRITE-UP (user decision 2026-08-13): refi outcome fails
 parallel trends (pre-path ~+5 pts/yr into treatment, no post kink).
 Exploratory record only.

 County x year FE robustness for the refinancing-by-ethnicity event studies
 (2012-2024 long panel): identification within municipio-year, absorbing
 county-specific shocks and trends. Tract FE (nesting county) retained.

 Outputs: output/design2/hmda_refi_cfe_coefs.csv,
          figH10c_refi_hisp_cfe.png, figH11c_refi_nonhisp_cfe.png
==============================================================================*/

version 17
clear all
set more off

global REPO "C:/Users/mva284/Documents/GitHub/ClaudeAct2260MergeExercise"
global D2   "$REPO/data/design2"
global OUT  "$REPO/output/design2"

capture which ppmlhdfe
if _rc ssc install ppmlhdfe, replace

import delimited "$REPO/data/cleaned/pr_tract_zcta_crosswalk.csv", varnames(1) clear
keep tract_geoid
duplicates drop
expand 13
bysort tract_geoid: gen year = 2011 + _n
tempfile frame
save `frame'

import delimited "$D2/hmda_tract_year_long.csv", varnames(1) clear
merge 1:1 tract_geoid year using `frame', nogen
foreach v in refi_hisp_n refi_nonhisp_n {
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
local DVARS Dm4 Dm3 Dm2 D0 D1 D2 D3

egen tract_num = group(tract_geoid)
gen county = substr(string(tract_geoid, "%011.0f"), 1, 5)
capture confirm string variable tract_geoid
if !_rc replace county = substr(tract_geoid, 1, 5)
egen cyear = group(county year)
tempfile panel
save `panel'

log using "$OUT/hmda_refi_cfe.log", replace text

tempname pf
postfile `pf' str20 test double h b se using "$OUT/_hrc.dta", replace

foreach v in refi_hisp_n refi_nonhisp_n {
    use `panel', clear
    di as result _n "===== POISSON `v' + county x year FE ====="
    ppmlhdfe `v' `DVARS', absorb(tract_num cyear) vce(cluster tract_num)
    post `pf' ("`v'") (-4) (_b[Dm4]) (_se[Dm4])
    post `pf' ("`v'") (-3) (_b[Dm3]) (_se[Dm3])
    post `pf' ("`v'") (-2) (_b[Dm2]) (_se[Dm2])
    post `pf' ("`v'") (-1) (0) (.)
    post `pf' ("`v'") (0)  (_b[D0]) (_se[D0])
    post `pf' ("`v'") (1)  (_b[D1]) (_se[D1])
    post `pf' ("`v'") (2)  (_b[D2]) (_se[D2])
    post `pf' ("`v'") (3)  (_b[D3]) (_se[D3])

    di as result _n "===== POISSON pooled `v' + county x year FE ====="
    ppmlhdfe `v' treat, absorb(tract_num cyear) vce(cluster tract_num)
    post `pf' ("`v'") (99) (_b[treat]) (_se[treat])
}

postclose `pf'
log close

use "$OUT/_hrc.dta", clear
gen lb = b - 1.96*se
gen ub = b + 1.96*se
export delimited "$OUT/hmda_refi_cfe_coefs.csv", replace
capture erase "$OUT/_hrc.dta"

*---- plots (same style as design2_hmda_refi_plots.do) -----------------------
drop if h == 99
foreach v in b lb ub {
    replace `v' = 100 * `v'
}
rename h horizon
sort test horizon

foreach v in refi_hisp_n refi_nonhisp_n {
    preserve
    keep if test == "`v'"
    local ttl "Refinancings by Hispanic borrowers: county x year FE"
    local out figH10c_refi_hisp_cfe
    if "`v'" == "refi_nonhisp_n" {
        local ttl "Refinancings by non-Hispanic borrowers: county x year FE"
        local out figH11c_refi_nonhisp_cfe
    }
    twoway ///
        (rcap ub lb horizon, lcolor(navy) lwidth(medthin)) ///
        (connected b horizon, color(navy) msymbol(O) lwidth(medthin)) ///
        , graphregion(color(white)) bgcolor(white) ///
        ylabel(, angle(horizontal) format(%9.0f)) ///
        yline(0, lcolor(gs8) lwidth(thin)) ///
        xline(-0.5, lcolor(gs11) lpattern(dash)) ///
        legend(off) ///
        title("`ttl'", size(medium)) ///
        ytitle("Effect on refi counts (100 x Poisson coef ~ %)") ///
        xtitle("Years since first investor purchase in tract") ///
        note("ppmlhdfe with tract and county x year FE, never-treated controls, clustered by tract; endpoints binned at -4 and +3." ///
             "Consistent population 2012-2024: originated first-lien owner-occupied 1-4 family refinancings (all types).", size(vsmall)) ///
        xlabel(-4(1)3) name(`out', replace)
    graph export "$OUT/`out'.png", replace width(2000)
    restore
}
di as result "Saved: figH10c_refi_hisp_cfe.png, figH11c_refi_nonhisp_cfe.png"
