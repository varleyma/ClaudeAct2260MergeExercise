/*==============================================================================
 design1_arrivals_did.do

 INVESTOR-BEGETS-INVESTOR: DiD / event-study evidence that an investor
 purchase raises SUBSEQUENT investor arrivals nearby (the causal counterpart
 of the exposure/co-location descriptive, fig_cluster_exposure).

 Outcome: arrivals of OTHER decree investors (other design1 events, other
 buyers; events already group same-buyer-same-day parcels) per km^2 in rings
 around each event, annual. Panel built by build_arrivals_panel.py:
 event x {0-250 | 250-500 | 500-1000 | 1000-1500 | control 1500-2000m} x year
 (zero-filled grid, 2008-2025).

 Design mirrors design1_decay_results.do exactly: per treated bin, cell =
 event x {bin, control}, lpdid annual, pre_window 4 / post_window 3,
 never-treated controls, window event_year-6..+5. Within-event comparison:
 event x year common shocks (incl. the mechanical decree-era ramp and the
 last-owner censoring profile) difference out; identification is the
 DIFFERENTIAL change in near-ring arrival rates vs the 1500-2000m band.

 Samples: all events | pioneer4 (no other-buyer event within 1km dated
 before t-4 YEARS -- predetermined relative to the pre-window, so pre-window
 arrivals are NOT conditioned on) | established (complement). The naive
 "no prior event at the event date" flag forces pre-window arrivals to zero
 by construction and is NOT used for estimation. Pioneer4 is the
 state-dependence test: did an investor landing in (near-)virgin territory
 trigger subsequent arrivals?

 Robustness: stacked ppmlhdfe (proportional effects) on counts, all treated
 bins x event-time vs control, absorb(event#bin event#year), cluster(event).

 Saves lpdid event + pooled matrices (grabmat pattern) and PPML coefficients:
     output/design1/arrivals_coefs.dta (+.csv), arrivals_ppml_coefs.csv
 Inputs: data/design1/arrivals_panel.csv
==============================================================================*/

version 17
clear all
set more off

global REPO "C:/Users/mva284/Documents/GitHub/ClaudeAct2260MergeExercise"
global D1   "$REPO/data/design1"
global OUT  "$REPO/output/design1"
global COEFTMP "$OUT/_arrivals_accum.dta"
capture erase "$COEFTMP"

capture which lpdid
if _rc ssc install lpdid, replace
capture which ppmlhdfe
if _rc ssc install ppmlhdfe, replace

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
  LOAD
============================================================================*/
import delimited "$D1/arrivals_panel.csv", varnames(1) encoding(utf8) clear
gen y = arrivals / area_km2
keep if inrange(year, event_year - 6, event_year + 5)
save "$OUT/_arrivals_panel.dta", replace

log using "$OUT/arrivals_results.log", replace text

/*============================================================================
  LPDID: per treated bin vs control, by sample
============================================================================*/
foreach samp in all pioneer established {
    foreach b in 0_250 250_500 500_1000 1000_1500 {
        use "$OUT/_arrivals_panel.dta", clear
        if "`samp'" == "pioneer"     keep if pioneer4 == 1
        if "`samp'" == "established" keep if pioneer4 == 0
        keep if inlist(bin, "`b'", "control")
        gen near = bin == "`b'"
        egen cellid = group(event_id near)
        gen treat = near & year >= event_year
        xtset cellid year
        di as result _n "===== arrivals `samp' | bin `b' vs control 1500-2000 ====="
        capture noisily lpdid y, unit(cellid) time(year) treat(treat) ///
            pre_window(4) post_window(3) nevertreated
        if _rc continue
        local tag "A_`b'_`samp'"
        matrix E = e(results)
        grabmat E `tag' event
        capture matrix P = e(pooled_results)
        if !_rc grabmat P `tag' pooled
    }
}

/*============================================================================
  PPML robustness: stacked, proportional effects, all bins at once
============================================================================*/
capture postclose PH
postfile PH str12 sample str12 bin double k coef se using "$OUT/_arrivals_ppml.dta", replace

foreach samp in all pioneer established {
    use "$OUT/_arrivals_panel.dta", clear
    if "`samp'" == "pioneer"     keep if pioneer4 == 1
    if "`samp'" == "established" keep if pioneer4 == 0
    gen k = year - event_year
    gen kk = k + 6                      // 0..11, base 5 (k = -1)
    encode bin, gen(binn)               // alphabetical: control is some level
    qui levelsof binn if bin == "control", local(cb)
    egen ebin  = group(event_id bin)
    egen eyear = group(event_id year)
    egen evid  = group(event_id)
    di as result _n "===== PPML arrivals `samp' (base: control band, k=-1) ====="
    capture noisily ppmlhdfe arrivals ib`cb'.binn#ib5.kk, ///
        absorb(ebin eyear) vce(cluster evid) d
    if _rc continue
    matrix b = e(b)
    matrix V = e(V)
    local cn : colfullnames b
    local j = 0
    foreach n of local cn {
        local ++j
        if strpos("`n'", "#") == 0 continue
        if strpos("`n'", "b.") | strpos("`n'", "o.") continue
        * name like  3.binn#7.kk
        local bl = real(substr("`n'", 1, strpos("`n'", ".") - 1))
        local rest = substr("`n'", strpos("`n'", "#") + 1, .)
        local kv = real(substr("`rest'", 1, strpos("`rest'", ".") - 1)) - 6
        local blab : label binn `bl'
        post PH ("`samp'") ("`blab'") (`kv') (b[1, `j']) (sqrt(V[`j', `j']))
    }
}
postclose PH

log close

/*============================================================================
  FINALIZE
============================================================================*/
use "$COEFTMP", clear
order test matrix_type row rowname
sort test matrix_type row
tab test matrix_type
save "$OUT/arrivals_coefs.dta", replace
export delimited "$OUT/arrivals_coefs.csv", replace

use "$OUT/_arrivals_ppml.dta", clear
export delimited "$OUT/arrivals_ppml_coefs.csv", replace

capture erase "$COEFTMP"
capture erase "$OUT/_arrivals_panel.dta"
capture erase "$OUT/_arrivals_ppml.dta"
di as result _n "Saved: arrivals_coefs.dta/.csv, arrivals_ppml_coefs.csv"
