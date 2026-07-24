/*==============================================================================
 design1_ctrlband_ladder.do

 Control-band ladder: the near ring (0-250m) estimated against each candidate
 control band. One exhibit that shows how BOTH the pooled pre-period
 imbalance and the pooled post effect move as the control band approaches the
 event -- replacing the "which control band is right?" argument with a
 transparency figure.

 Reading the figure:
   - Pre -> 0 as the control nears  = nearer bands share investor-territory
     drift (parallel trends restored)
   - Post declines as the control nears = the control band itself carries
     part of the effect (estimates become gradients, conservative)
   - The defensible headline is the nearest band with clean pre-trends.

 Ladder rungs (control bands, meters):
   400-1000 (the original 1km design) | 1000-1500 | 1500-2000 |
   2000-2500 | 2500-3500

 Output: output/design1/ladder_coefs.dta (+.csv), figD4_ctrlband_ladder.png
 Input:  data/design1/design1_sale_event_pairs_5km.csv + events info
==============================================================================*/

version 17
clear all
set more off

global REPO "C:/Users/mva284/Documents/GitHub/ClaudeAct2260MergeExercise"
global D1   "$REPO/data/design1"
global OUT  "$REPO/output/design1"
capture mkdir "$REPO/output"
capture mkdir "$OUT"
global COEFTMP "$OUT/_ladder_accum.dta"
capture erase "$COEFTMP"

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
  LOAD + PREP (identical filters to design1_decay_results.do)
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
keep event_id dist_m tt ett lnp salesamt
save "$OUT/_ladder_sales.dta", replace

/*============================================================================
  LADDER: near ring 0-250m vs each control band
============================================================================*/
log using "$OUT/ladder_results.log", replace text

local bands "400_1000 1000_1500 1500_2000 2000_2500 2500_3500"
foreach bnd of local bands {
    local cmin = real(substr("`bnd'", 1, strpos("`bnd'", "_") - 1))
    local cmax = real(substr("`bnd'", strpos("`bnd'", "_") + 1, .))
    use "$OUT/_ladder_sales.dta", clear
    keep if dist_m <= 250 | (dist_m > `cmin' & dist_m <= `cmax')
    gen near = dist_m <= 250
    egen cellid = group(event_id near)
    collapse (mean) y = lnp (first) near ett (count) nsales = salesamt, ///
        by(cellid tt)
    drop if missing(y)
    gen treat = near & tt >= ett
    xtset cellid tt
    di as result _n "===== near 0-250m vs control `cmin'-`cmax' ====="
    lpdid y, unit(cellid) time(tt) treat(treat) ///
        pre_window(4) post_window(3) nevertreated
    capture graph rename Graph lad_`bnd', replace
    local tag "C_`bnd'"
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
save "$OUT/ladder_coefs.dta", replace
export delimited "$OUT/ladder_coefs.csv", replace
capture erase "$COEFTMP"
capture erase "$OUT/_ladder_sales.dta"

/*============================================================================
  FIGURE: pooled Pre and Post vs control-band midpoint
============================================================================*/
use "$OUT/ladder_coefs.dta", clear
keep if matrix_type == "pooled"
gen b  = c1
gen se = c2
gen lb = c5
gen ub = c6
replace lb = b - 1.96*se if missing(lb) & !missing(se)
replace ub = b + 1.96*se if missing(ub) & !missing(se)
gen post = lower(rowname) == "post"
gen mid = .
replace mid = 700  if test == "C_400_1000"
replace mid = 1250 if test == "C_1000_1500"
replace mid = 1750 if test == "C_1500_2000"
replace mid = 2250 if test == "C_2000_2500"
replace mid = 3000 if test == "C_2500_3500"
drop if missing(mid)
gen x = mid + cond(post, 0, 60)
sort post x

twoway ///
    (rcap ub lb x if post, lcolor(navy) lwidth(medthin)) ///
    (connected b x if post, color(navy) msymbol(O) lwidth(medthin) sort(x)) ///
    (rcap ub lb x if !post, lcolor(gs9) lwidth(thin)) ///
    (connected b x if !post, color(gs9) msymbol(Oh) lpattern(dash) lwidth(thin) sort(x)) ///
    , graphregion(color(white)) bgcolor(white) ///
    ylabel(, angle(horizontal) format(%9.2f)) ///
    yline(0, lcolor(gs8) lwidth(thin)) ///
    legend(order(2 "Pooled post-treatment effect (0-250m ring)" ///
                 4 "Pooled pre-period (parallel-trends check)") ///
           rows(2) position(6) region(lstyle(none))) ///
    title("The control-band dial: effect and pre-trend vs control distance", size(medium)) ///
    ytitle("Pooled effect on log sale price, 0-250m ring") ///
    xtitle("Control-band midpoint (meters from investor purchase)") ///
    xlabel(700 "700" 1250 "1,250" 1750 "1,750" 2250 "2,250" 3000 "3,000") ///
    note("Treated ring fixed at 0-250m; each x-position uses a different control band (400-1,000 / 1,000-1,500 / 1,500-2,000 /" ///
         "2,000-2,500 / 2,500-3,500m). Pre near zero identifies bands sharing the treated ring's counterfactual trend;" ///
         "Post declines with nearer controls as the band itself carries part of the effect (estimates are within-area gradients).", size(vsmall)) ///
    name(figD4_ladder, replace)
graph export "$OUT/figD4_ctrlband_ladder.png", replace width(2000)

di as result _n "Ladder complete: ladder_coefs.dta + figD4_ctrlband_ladder.png"
