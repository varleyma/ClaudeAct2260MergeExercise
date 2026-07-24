/*==============================================================================
 design1_decay_results_5km.do

 EXPLORATORY EXTREME: decay rings to the edge of the pairs data. Treated bins
 out to 4km, control = 4000-5000m -- far outside the event's housing market,
 so expect the largest pre-drift yet; the companion detrended plots file
 (design1_decay_plots_5km_detrended.do) projects each bin's linear pre-drift
 out. Purpose: see how far the "linear trend difference between markets"
 account stretches. Headline spec remains the near-control version.

 Treated bins: 0-250 | 250-500 | 500-1000 | 1000-1750 | 1750-2500 |
               2500-3500 | 3500-4000    Control: 4000-5000m

 Output: output/design1/decay_coefs_5km.dta (+.csv)
==============================================================================*/

version 17
clear all
set more off

global REPO "C:/Users/mva284/Documents/GitHub/ClaudeAct2260MergeExercise"
global D1   "$REPO/data/design1"
global OUT  "$REPO/output/design1"
capture mkdir "$REPO/output"
capture mkdir "$OUT"
global COEFTMP "$OUT/_decay5k_accum.dta"
capture erase "$COEFTMP"

local CTRL_MIN 4000
local CTRL_MAX 5000

capture which lpdid
if _rc ssc install lpdid, replace

capture program drop grabmat
program define grabmat
    args M test mtype
    local rn : rowfullnames `M'
    local nr = rowsof(`M')
    preserve
    clear
    qui svmat double `M', names(c)
    qui gen row = _n
    qui gen str32 rowname = ""
    forvalues i = 1/`nr' {
        local r : word `i' of `rn'
        qui replace rowname = "`r'" in `i'
    }
    qui gen str40 test = "`test'"
    qui gen str10 matrix_type = "`mtype'"
    capture confirm file "$COEFTMP"
    if !_rc qui append using "$COEFTMP"
    qui save "$COEFTMP", replace
    restore
end

/*============================================================================
  LOAD + PREP (identical filters to the main decay file)
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

gen str12 bin = ""
replace bin = "0_250"     if dist_m <= 250
replace bin = "250_500"   if dist_m > 250  & dist_m <= 500
replace bin = "500_1000"  if dist_m > 500  & dist_m <= 1000
replace bin = "1000_1750" if dist_m > 1000 & dist_m <= 1750
replace bin = "1750_2500" if dist_m > 1750 & dist_m <= 2500
replace bin = "2500_3500" if dist_m > 2500 & dist_m <= 3500
replace bin = "3500_4000" if dist_m > 3500 & dist_m <= 4000
replace bin = "control"   if dist_m > `CTRL_MIN' & dist_m <= `CTRL_MAX'
drop if bin == ""

save "$OUT/_decay5k_sales.dta", replace

log using "$OUT/decay_results_5km.log", replace text

foreach b in 0_250 250_500 500_1000 1000_1750 1750_2500 2500_3500 3500_4000 {
    use "$OUT/_decay5k_sales.dta", clear
    keep if inlist(bin, "`b'", "control")
    gen near = bin == "`b'"
    egen cellid = group(event_id near)
    collapse (mean) y = lnp (first) near ett (count) nsales = salesamt, ///
        by(cellid tt)
    drop if missing(y)
    gen treat = near & tt >= ett
    xtset cellid tt
    di as result _n "===== decay bin `b' vs control `CTRL_MIN'-`CTRL_MAX' ====="
    lpdid y, unit(cellid) time(tt) treat(treat) ///
        pre_window(4) post_window(3) nevertreated
    capture graph rename Graph d5k_`b', replace
    local tag "D_`b'"
    matrix E = e(results)
    grabmat E `tag' event
    capture matrix P = e(pooled_results)
    if !_rc grabmat P `tag' pooled
}

log close

use "$COEFTMP", clear
order test matrix_type row rowname
sort test matrix_type row
tab test matrix_type
assert !inlist(test, "D_", "")
save "$OUT/decay_coefs_5km.dta", replace
export delimited "$OUT/decay_coefs_5km.csv", replace
capture erase "$COEFTMP"
capture erase "$OUT/_decay5k_sales.dta"
di as result _n "Saved: $OUT/decay_coefs_5km.dta"
