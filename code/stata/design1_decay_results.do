/*==============================================================================
 design1_decay_results.do

 Spatial-decay event studies from the 5km pairs file (annual, lpdid).

 RING DESIGN (precision-oriented; need not match the 1km files)
 --------------------------------------------------------------
 Treated bins:  0-250m | 250-500m | 500-1000m | 1000-1500m
 Control band:  one COMMON control for every bin. MAIN spec = 2500-3500m:
                beyond where effects decay, but close enough to stay within
                the event's own housing market (wider bands bleed into other
                markets -> parallel-trends risk). Sensitivity: CTRL_MAX 5000.
 Rationale: ring area grows with r^2, so outer bins are self-precise and the
 control band dwarfs every treated bin either way; the near bins stay at the
 baseline's 250m resolution. The 1000-2500m bins are where effects should be
 dead -- estimating them precisely is the point of the 5km data. Pre-period
 profiles per bin are the direct test of the control band's validity.

 For each bin b: panel = event x {bin b, control} x year cells; the bin-b
 cell adopts treatment at the event year (lpdid, never-treated controls,
 same conventions as the 1km suite: events >=2012, window -72..+60 months,
 pre_window 4 / post_window 3).

 Saves BOTH the event-study matrix e(results) and the pooled pre/post matrix
 e(pooled_results) for every bin into:
     output/design1/decay_coefs.dta (+ .csv)
 with matrix_type = "event" | "pooled". The pooled Post row per bin is the
 maximal-precision decay curve; pooled Pre is its placebo twin.

 Inputs: data/design1/design1_sale_event_pairs_5km.csv (gitignored; regenerate
         with code/python/build_design1_event_panel_5km.py),
         data/design1/design1_events_5km_info.csv
==============================================================================*/

version 17
clear all
set more off

global REPO "C:/Users/mva284/Documents/GitHub/ClaudeAct2260MergeExercise"
global D1   "$REPO/data/design1"
global OUT  "$REPO/output/design1"
capture mkdir "$REPO/output"
capture mkdir "$OUT"
global COEFTMP "$OUT/_decay_accum.dta"
capture erase "$COEFTMP"

* Control band (meters). MAIN spec = 1500-2000m: near enough to share the
* common pre-period drift of investor territory (restoring parallel trends),
* at the cost of differencing out the ~+5-6% effect present at that distance
* -> all estimates are gradients WITHIN 1.5km, conservative by construction.
* (Earlier specs: 2500-3500 market-safe band; 2500-5000 wide band.)
local CTRL_MIN 1500
local CTRL_MAX 2000

capture which lpdid
if _rc ssc install lpdid, replace

/*============================================================================
  COEFFICIENT CAPTURE (event-study + pooled matrices)
============================================================================*/
capture program drop grabmat
program define grabmat
    * grabmat <matname> <test> <matrix_type>
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
  LOAD + PREP
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

* contamination info at these radii (available for subsetting/robustness)
preserve
    import delimited "$D1/design1_events_5km_info.csv", varnames(1) clear
    tempfile evinfo
    save `evinfo'
restore
merge m:1 event_id using `evinfo', keep(master match) nogen

gen lnp = ln(salesamt)

* ring bins (treated bins must end at CTRL_MIN)
drop if dist_m > `CTRL_MAX'
gen str12 bin = ""
replace bin = "0_250"     if dist_m <= 250
replace bin = "250_500"   if dist_m > 250  & dist_m <= 500
replace bin = "500_1000"  if dist_m > 500  & dist_m <= 1000
replace bin = "1000_1500" if dist_m > 1000 & dist_m <= 1500
replace bin = "control"   if dist_m > `CTRL_MIN'  & dist_m <= `CTRL_MAX'

* on-disk temp (not a tempfile) so the estimation loop below can be re-run
* on its own within a session without redoing the import
save "$OUT/_decay_sales.dta", replace

/*============================================================================
  RUN: one lpdid per treated bin vs the common control band
  (re-runnable alone AFTER the file has run once this session)
============================================================================*/
log using "$OUT/decay_results.log", replace text

foreach b in 0_250 250_500 500_1000 1000_1500 {
    use "$OUT/_decay_sales.dta", clear
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
    * keep the per-bin lpdid graph in its own named window
    capture graph rename Graph des_`b', replace
    local tag "D_`b'"
    matrix E = e(results)
    grabmat E `tag' event
    capture matrix P = e(pooled_results)
    if !_rc grabmat P `tag' pooled
}

log close

/*============================================================================
  FINALIZE
============================================================================*/
use "$COEFTMP", clear
order test matrix_type row rowname
sort test matrix_type row
* sanity: all five bins present with real labels
tab test matrix_type
assert !inlist(test, "D_", "")
save "$OUT/decay_coefs.dta", replace
export delimited "$OUT/decay_coefs.csv", replace
capture erase "$COEFTMP"
capture erase "$OUT/_decay_sales.dta"
di as result _n "Saved: $OUT/decay_coefs.dta (+.csv), " _N " rows"
