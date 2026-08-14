/*==============================================================================
 design2_controls_robustness.do

 Spec ladder for the tract-level outcomes, three columns per outcome, all
 estimated with the PMD LP-DiD (Dube-Girardi-Jorda-Taylor pre-mean
 differencing, H=3, k=4; clean-control sample: newly treated tracts at
 onset + never-treated tracts):
   (1) base:            calendar-year effects
   (2) + county-year:   county x year effects
   (3) + controls:      (2) + 2010 PRCS baseline controls (standardized)
                        interacted with Post (1{year >= 2020})

 Outcomes:
   lnhp            100 x ln tract price (Red Atlas, count-weighted annual mean)
   lninc_all       100 x ln mean purchase-borrower income (HMDA long panel)
   purch_hisp_n    100 x asinh Hispanic-borrower purchases (PMD-OLS; Poisson
   purch_nonhisp_n 100 x asinh non-Hispanic purchases       does not compose
                                                            with PMD)

 SEs clustered by tract. 2010 PRCS controls: med hh income, med home value,
 med gross rent, poverty, BA+ share, renter share, vacancy, seasonal-home
 share, mainland-born share, ln population.

 Output: output/design2/controls_robustness.csv (outcome,spec,b,se,r2,nobs),
         controls_robustness.log
==============================================================================*/

version 17
clear all
set more off

global REPO "C:/Users/mva284/Documents/GitHub/ClaudeAct2260MergeExercise"
global D2   "$REPO/data/design2"
global OUT  "$REPO/output/design2"
global REDATLAS "C:/Users/mva284/Dropbox/Ley60PR/data/clean/monthly_data_red_atlas.csv"

capture which reghdfe
if _rc ssc install reghdfe, replace

global CTRLS med_hh_inc med_value med_rent poverty ba_share renter_share ///
    vacancy seasonal_share mainland_share lnpop

capture program drop prepctrl
program define prepctrl
    merge m:1 tract_geoid using "$D2/_prcs.dta", keep(master match) nogen
    gen lnpop = ln(pop) if pop > 0
    gen post = year >= 2020
    global ZP
    foreach c of global CTRLS {
        capture drop z_`c'
        qui sum `c'
        gen z_`c' = (`c' - r(mean)) / r(sd)
        gen zp_`c' = z_`c' * post
        global ZP $ZP zp_`c'
    }
    gen county = substr(tract_geoid, 1, 5)
    egen cyear = group(county year)
end

capture program drop pmdladder
program define pmdladder
    * pmdladder <yvar> <name> <pf> -- PMD construction + 3-spec ladder.
    * expects tract_num year treat cyear $ZP in memory
    args yvar name pf
    preserve
    xtset tract_num year
    gen y0  = `yvar'
    gen yf1 = F1.`yvar'
    gen yf2 = F2.`yvar'
    gen yf3 = F3.`yvar'
    gen yl1 = L1.`yvar'
    gen yl2 = L2.`yvar'
    gen yl3 = L3.`yvar'
    gen yl4 = L4.`yvar'
    egen postm = rowmean(y0 yf1 yf2 yf3)
    egen prem  = rowmean(yl1 yl2 yl3 yl4)
    gen pmd = postm - prem
    gen dD = treat == 1 & L1.treat == 0
    egen evertr = max(treat), by(tract_num)
    keep if dD == 1 | evertr == 0
    forvalues s = 1/3 {
        if `s' == 1 local abs absorb(year)
        else        local abs absorb(cyear)
        local rhs dD
        if `s' == 3 local rhs dD $ZP
        di as result _n "===== PMD `name' spec `s' ====="
        reghdfe pmd `rhs', `abs' vce(cluster tract_num)
        post `pf' ("`name'") (`s') (_b[dD]) (_se[dD]) (e(r2)) (e(N))
    }
    restore
end

* controls -> dta for merging
import delimited "$D2/prcs2010_tract_controls.csv", varnames(1) stringcols(1) clear
save "$D2/_prcs.dta", replace

log using "$OUT/controls_robustness.log", replace text

tempname pf
postfile `pf' str20 outcome double spec b se r2 nobs using "$OUT/_cr.dta", replace

/*---- A. tract price (Red Atlas annual panel) -------------------------------*/
import delimited "$REDATLAS", varnames(1) clear
keep geotractid month meantransactionpricepertract numberoftransactions
rename geotractid tract_geoid
rename meantransactionpricepertract p_mean
rename numberoftransactions n_sales
destring p_mean n_sales, replace force
gen year = real(substr(month, 1, 4))
drop if missing(p_mean) | missing(n_sales) | n_sales <= 0
gen pw = p_mean * n_sales
collapse (sum) pw n_sales, by(tract_geoid year)
gen lnhp = 100 * ln(pw / n_sales)
tostring tract_geoid, replace format(%011.0f)
preserve
    import delimited "$D2/design2_tract_treatment.csv", varnames(1) stringcols(1) clear
    tempfile trt
    save `trt'
restore
merge m:1 tract_geoid using `trt', keep(master match) nogen
gen treat = !missing(first_event_year) & year >= first_event_year
egen tract_num = group(tract_geoid)
prepctrl
pmdladder lnhp lnhp `pf'

/*---- B. HMDA long panel (income + counts) ----------------------------------*/
import delimited "$REPO/data/cleaned/pr_tract_zcta_crosswalk.csv", varnames(1) stringcols(1) clear
keep tract_geoid
duplicates drop
expand 13
bysort tract_geoid: gen year = 2011 + _n
tempfile frame
save `frame'

import delimited "$D2/hmda_tract_year_long.csv", varnames(1) stringcols(1) clear
merge 1:1 tract_geoid year using `frame', nogen
foreach v in purch_hisp_n purch_hisp_inc purch_hisp_incn ///
             purch_nonhisp_n purch_nonhisp_inc purch_nonhisp_incn {
    replace `v' = 0 if missing(`v')
}
preserve
    import delimited "$D2/design2_tract_treatment.csv", varnames(1) stringcols(1) clear
    tempfile trt
    save `trt'
restore
merge m:1 tract_geoid using `trt', keep(master match) nogen
gen treat = !missing(first_event_year) & year >= first_event_year
gen lninc_all = 100 * ln((purch_hisp_inc + purch_nonhisp_inc) / ///
                         (purch_hisp_incn + purch_nonhisp_incn)) ///
                if purch_hisp_incn + purch_nonhisp_incn > 0
gen ihs_hisp    = 100 * asinh(purch_hisp_n)
gen ihs_nonhisp = 100 * asinh(purch_nonhisp_n)
egen tract_num = group(tract_geoid)
prepctrl
pmdladder lninc_all lninc_all `pf'
pmdladder ihs_hisp purch_hisp_n `pf'
pmdladder ihs_nonhisp purch_nonhisp_n `pf'

postclose `pf'
log close

use "$OUT/_cr.dta", clear
export delimited "$OUT/controls_robustness.csv", replace
capture erase "$OUT/_cr.dta"
capture erase "$D2/_prcs.dta"
list, noobs sep(3)
di as result "Saved: $OUT/controls_robustness.csv"
