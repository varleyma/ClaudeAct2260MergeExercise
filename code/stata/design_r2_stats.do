/*==============================================================================
 design_r2_stats.do

 R2 and N for every lpdid-based specification, from the EQUIVALENT stacked
 TWFE regression on the same estimation panel:

     reghdfe y treat, absorb(cellid tt)   (cells)  /  absorb(tract year) (D2)

 LP-DiD itself estimates separate long-difference regressions and returns no
 single R2; these statistics describe the fit of the analogous two-way FE
 model on identical data and are footnoted as such in the tables.

 Output: output/tables/r2_stats.csv  (test, r2, nobs)
==============================================================================*/

version 17
clear all
set more off

global REPO "C:/Users/mva284/Documents/GitHub/ClaudeAct2260MergeExercise"
global D1   "$REPO/data/design1"
global D2   "$REPO/data/design2"
global OUT  "$REPO/output/tables"
capture mkdir "$OUT"

capture which reghdfe
if _rc ssc install reghdfe, replace

tempname pf
postfile `pf' str24 test double r2 nobs using "$OUT/_r2_stats.dta", replace

capture program drop r2cell
program define r2cell
    * r2cell <yvar> <test>  -- collapse in-memory sale rows to cells, run TWFE
    args yvar test
    preserve
    egen cellid = group(event_id ring)
    gen near = ring == "near_0_250"
    collapse (mean) y = `yvar' (first) near ett (count) nsales = salesamt, ///
        by(cellid tt)
    drop if missing(y)
    gen treat = near & tt >= ett
    reghdfe y treat, absorb(cellid tt) vce(cluster cellid)
    global R2 = e(r2)
    global NN = e(N)
    restore
end

/*============================================================================
  A. 1km robustness specs (T1-T8)
============================================================================*/
import delimited "$D1/design1_sale_event_pairs.csv", ///
    varnames(1) encoding(utf8) stringcols(_all) clear
destring salesamt dist_m event_time_months cabida structure, replace force
gen sdate = date(sale_date, "YMD")
gen edate = date(event_date, "YMD")
gen tt    = yofd(sdate)
gen ett   = yofd(edate)
drop if flag_junk_date == "True"
drop if flag_nominal_price == "True"
gen inv_sale = sale_is_investor_parcel == "True"
drop if year(edate) < 2012
keep if salesamt > 0 & !missing(salesamt)
keep if inrange(event_time_months, -72, 60)
preserve
    import delimited "$D1/design1_events.csv", varnames(1) ///
        encoding(utf8) stringcols(_all) clear
    keep event_id n_other_events_within_1000m
    destring n_other_events_within_1000m, replace force
    tempfile evinfo
    save `evinfo'
restore
merge m:1 event_id using `evinfo', keep(master match) nogen
gen lnp     = ln(salesamt)
gen lnstru  = ln(structure) if structure > 0
gen lncab   = ln(cabida)    if cabida > 0
gen subu    = is_subunit == "True"
gen vac     = vacant_land == "True"
capture confirm variable buyer_nonhispanic
if !_rc {
    gen buy_nh  = buyer_nonhispanic  == "True" if inlist(buyer_nonhispanic,  "True", "False")
    gen sell_nh = seller_nonhispanic == "True" if inlist(seller_nonhispanic, "True", "False")
    gen bothcl  = inlist(buyer_nonhispanic, "True", "False") & ///
                  inlist(seller_nonhispanic, "True", "False")
    gen isl2main  = (seller_nonhispanic == "False" & buyer_nonhispanic == "True")  if bothcl
    gen main2main = (seller_nonhispanic == "True"  & buyer_nonhispanic == "True")  if bothcl
    drop bothcl
}
tempfile salesall sales
save `salesall'
drop if inv_sale
save `sales'

use `sales', clear
drop if ring == "gap_250_400"
r2cell lnp T1_baseline
post `pf' ("T1_baseline") ($R2) ($NN)

foreach y in lnstru lncab subu vac {
    use `sales', clear
    drop if ring == "gap_250_400"
    r2cell `y' T2_comp_`y'
    post `pf' ("T2_comp_`y'") ($R2) ($NN)
}

use `sales', clear
drop if ring == "near_0_250"
replace ring = "near_0_250" if ring == "gap_250_400"
r2cell lnp T3_gradient_gap
post `pf' ("T3_gradient_gap") ($R2) ($NN)

use `sales', clear
drop if ring == "gap_250_400"
keep if n_other_events_within_1000m <= 2
r2cell lnp T4_dose_low
post `pf' ("T4_dose_low") ($R2) ($NN)

use `sales', clear
drop if ring == "gap_250_400"
keep if inrange(n_other_events_within_1000m, 3, 25)
r2cell lnp T4_dose_mid
post `pf' ("T4_dose_mid") ($R2) ($NN)

use `sales', clear
drop if ring == "gap_250_400"
keep if n_other_events_within_1000m > 25
r2cell lnp T4_dose_high
post `pf' ("T4_dose_high") ($R2) ($NN)

use `sales', clear
drop if ring == "gap_250_400"
keep if year(edate) >= 2018
r2cell lnp T5_late
post `pf' ("T5_late") ($R2) ($NN)

foreach y in buy_nh sell_nh isl2main main2main {
    use `sales', clear
    capture confirm variable `y'
    if _rc continue
    drop if ring == "gap_250_400"
    r2cell `y' T7_`y'
    post `pf' ("T7_`y'") ($R2) ($NN)
}

use `salesall', clear
drop if ring == "gap_250_400"
r2cell lnp T8_incl_investors
post `pf' ("T8_incl_investors") ($R2) ($NN)

use `sales', clear
capture confirm variable buyer_nonhispanic
if !_rc {
    drop if ring == "gap_250_400"
    keep if buyer_nonhispanic == "False"
    r2cell lnp T8_hisp_buyers
    post `pf' ("T8_hisp_buyers") ($R2) ($NN)
}

use `sales', clear
drop if ring == "gap_250_400"
drop if ring == "far_400_1000" & dist_m > 750
r2cell lnp T6_real_far750
post `pf' ("T6_real_far750") ($R2) ($NN)

* placebo
import delimited "$D1/placebo_sale_event_pairs.csv", ///
    varnames(1) encoding(utf8) stringcols(_all) clear
destring salesamt dist_m event_time_months, replace force
gen sdate = date(sale_date, "YMD")
gen edate = date(event_date, "YMD")
gen tt    = yofd(sdate)
gen ett   = yofd(edate)
drop if flag_junk_date == "True"
drop if flag_nominal_price == "True"
drop if sale_is_investor_parcel == "True"
keep if salesamt > 0 & !missing(salesamt)
keep if inrange(event_time_months, -72, 60)
preserve
    import delimited "$D1/placebo_events.csv", varnames(1) ///
        encoding(utf8) stringcols(_all) clear
    keep event_id months_to_nearest_event
    destring months_to_nearest_event, replace force
    tempfile pinfo
    save `pinfo'
restore
merge m:1 event_id using `pinfo', keep(master match) nogen
drop if abs(months_to_nearest_event) <= 36
gen lnp = ln(salesamt)
drop if ring == "gap_250_400"
drop if ring == "far_400_1000" & dist_m > 750
r2cell lnp T6_placebo
post `pf' ("T6_placebo") ($R2) ($NN)

/*============================================================================
  B. 5km decay / ladder specs
============================================================================*/
import delimited "$D1/design1_sale_event_pairs_5km.csv", ///
    varnames(1) encoding(utf8) stringcols(_all) clear
destring salesamt dist_m, replace force
gen sdate = date(sale_date, "YMD")
gen edate = date(event_date, "YMD")
gen etm   = (year(sdate)*12 + month(sdate)) - (year(edate)*12 + month(edate))
gen tt    = yofd(sdate)
gen ett   = yofd(edate)
drop if flag_junk_date == "True"
drop if flag_nominal_price == "True"
drop if sale_is_investor_parcel == "True"
drop if year(edate) < 2012
keep if salesamt > 0 & !missing(salesamt)
keep if inrange(etm, -72, 60)
gen lnp = ln(salesamt)
save "$OUT/_r2_5km.dta", replace

capture program drop r2band
program define r2band
    * r2band <lo> <hi> <cmin> <cmax> <test>
    args lo hi cmin cmax test
    use "$OUT/_r2_5km.dta", clear
    keep if (dist_m > `lo' & dist_m <= `hi') | (dist_m > `cmin' & dist_m <= `cmax')
    gen near = dist_m > `lo' & dist_m <= `hi'
    egen cellid = group(event_id near)
    collapse (mean) y = lnp (first) near ett (count) n = salesamt, by(cellid tt)
    drop if missing(y)
    gen treat = near & tt >= ett
    reghdfe y treat, absorb(cellid tt) vce(cluster cellid)
    global R2 = e(r2)
    global NN = e(N)
end
* note: r2band's lo=0 uses dist_m > 0; the 0-250 ring includes dist 0 -> use -1
* main decay spec (control 1500-2000)
foreach s in "-1 250 D_0_250" "250 500 D_250_500" "500 1000 D_500_1000" "1000 1500 D_1000_1500" {
    local lo : word 1 of `s'
    local hi : word 2 of `s'
    local t  : word 3 of `s'
    r2band `lo' `hi' 1500 2000 `t'
    post `pf' ("`t'") ($R2) ($NN)
}
* ladder (0-250 vs each band)
foreach s in "400 1000 C_400_1000" "1000 1500 C_1000_1500" "1500 2000 C_1500_2000" "2000 2500 C_2000_2500" "2500 3500 C_2500_3500" {
    local c1 : word 1 of `s'
    local c2 : word 2 of `s'
    local t  : word 3 of `s'
    r2band -1 250 `c1' `c2' `t'
    post `pf' ("`t'") ($R2) ($NN)
}
* 3.5km spec (control 2500-3500)
foreach s in "-1 250 D35_0_250" "250 500 D35_250_500" "500 1000 D35_500_1000" "1000 1750 D35_1000_1750" "1750 2500 D35_1750_2500" {
    local lo : word 1 of `s'
    local hi : word 2 of `s'
    local t  : word 3 of `s'
    r2band `lo' `hi' 2500 3500 `t'
    post `pf' ("`t'") ($R2) ($NN)
}
* 5km spec (control 4000-5000)
foreach s in "-1 250 D5K_0_250" "250 500 D5K_250_500" "500 1000 D5K_500_1000" "1000 1750 D5K_1000_1750" "1750 2500 D5K_1750_2500" "2500 3500 D5K_2500_3500" "3500 4000 D5K_3500_4000" {
    local lo : word 1 of `s'
    local hi : word 2 of `s'
    local t  : word 3 of `s'
    r2band `lo' `hi' 4000 5000 `t'
    post `pf' ("`t'") ($R2) ($NN)
}
capture erase "$OUT/_r2_5km.dta"

/*============================================================================
  C. Design 2 tract specs
============================================================================*/
import delimited "C:/Users/mva284/Dropbox/Ley60PR/data/clean/monthly_data_red_atlas.csv", varnames(1) clear
keep geotractid month meantransactionpricepertract ///
    mediantransactionpricepertract numberoftransactions
rename geotractid tract_geoid
rename meantransactionpricepertract p_mean
rename numberoftransactions n_sales
destring p_mean n_sales, replace force
gen year = real(substr(month, 1, 4))
drop if missing(p_mean) | missing(n_sales) | n_sales <= 0
gen pw = p_mean * n_sales
collapse (sum) pw n_sales (mean) p_mean_simple = p_mean, by(tract_geoid year)
gen p_wtd = pw / n_sales
preserve
    import delimited "$D2/design2_tract_treatment.csv", varnames(1) clear
    tempfile trt
    save `trt'
restore
merge m:1 tract_geoid using `trt', keep(master match) nogen
replace n_events = 0 if missing(n_events)
gen treat = !missing(first_event_year) & year >= first_event_year
gen lnhp    = 100 * ln(p_wtd)
gen lnhp_s  = 100 * ln(p_mean_simple)
gen lnsales = 100 * ln(n_sales)
gen fips    = floor(tract_geoid / 1000000)
egen tract_num = group(tract_geoid)
egen fips_year = group(fips year)
save "$OUT/_r2_d2.dta", replace

foreach s in "lnhp tract_num#year T_x" {
}
use "$OUT/_r2_d2.dta", clear
reghdfe lnhp treat, absorb(tract_num year) vce(cluster tract_num)
post `pf' ("T_lnhp_base") (`e(r2)') (`e(N)')
use "$OUT/_r2_d2.dta", clear
reghdfe lnhp treat, absorb(tract_num year fips_year) vce(cluster tract_num)
post `pf' ("T_lnhp_fips") (`e(r2)') (`e(N)')
use "$OUT/_r2_d2.dta", clear
reghdfe lnhp_s treat, absorb(tract_num year) vce(cluster tract_num)
post `pf' ("T_lnhpsimple_base") (`e(r2)') (`e(N)')
use "$OUT/_r2_d2.dta", clear
reghdfe lnsales treat, absorb(tract_num year) vce(cluster tract_num)
post `pf' ("T_lnsales_base") (`e(r2)') (`e(N)')
use "$OUT/_r2_d2.dta", clear
keep if n_events >= 5 | missing(first_event_year)
reghdfe lnhp treat, absorb(tract_num year) vce(cluster tract_num)
post `pf' ("T_lnhp_dose5") (`e(r2)') (`e(N)')
use "$OUT/_r2_d2.dta", clear
keep if inrange(n_events, 1, 4) | missing(first_event_year)
reghdfe lnhp treat, absorb(tract_num year) vce(cluster tract_num)
post `pf' ("T_lnhp_dose14") (`e(r2)') (`e(N)')
capture erase "$OUT/_r2_d2.dta"

postclose `pf'
use "$OUT/_r2_stats.dta", clear
export delimited "$OUT/r2_stats.csv", replace
capture erase "$OUT/_r2_stats.dta"
di as result _n "Saved: $OUT/r2_stats.csv"
