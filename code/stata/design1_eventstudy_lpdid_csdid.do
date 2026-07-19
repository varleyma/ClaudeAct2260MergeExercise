/*==============================================================================
 design1_eventstudy_lpdid_csdid.do

 Design 1 stacked ring event study: effect of an Act 22/60 investor purchase
 on nearby sale prices, +/- 2 years, via lpdid and csdid.
 Reports each estimator without and with tract fixed effects.

 DESIGN MAPPING (read this first)
 ---------------------------------
 lpdid / csdid need a panel, but CRIM gives ONE sale per parcel (its last).
 We therefore build an event x ring x quarter panel:
   unit  = event x ring cell (near ring = 0-250m, far ring = 400-1000m;
           the 250-400m gap ring is dropped as a spillover buffer)
   time  = calendar quarter of sale
   y     = mean log sale price among that cell's sales that quarter
   treatment: the NEAR cell of event e switches on in e's event quarter
              (absorbing); FAR cells never switch -> never-treated controls.
 "With tract FE": sale-level ln(price) is residualized on tract dummies
 (reghdfe) BEFORE collapsing, so cross-tract level differences and the
 composition drift across tracts are removed. (FE cannot be added inside
 csdid; residualizing first is the clean equivalent.)

 KNOWN LIMITATIONS OF THIS STARTER
 ----------------------------------
 - Cells are SPARSE (many cell-quarters have 0 sales). lpdid/csdid drop
   missing cells; treat the first run as diagnostic, and consider quarterly ->
   half-year aggregation, or your tract-month price data as an alternative
   outcome panel, if too noisy.
 - CRIM keeps only each parcel's LAST sale: earlier sales are censored by
   later resales, and the censoring can be treatment-correlated. Within-window
   near-vs-far comparisons mitigate but do not eliminate this. See
   log/2026-07-18_1530.md.
 - Only 158/1256 events have no other event within 1km (median 25!). The
   CLEAN_ONLY toggle below restricts to less-contaminated events; the full
   sample estimates a "dose-diluted" effect.

 Inputs  (repo): data/design1/design1_sale_event_pairs.csv  (regenerate via
                 code/python/build_design1_event_panel.py if missing - 673MB,
                 gitignored), data/design1/design1_events.csv
 Outputs (repo): output/design1/  (estimates logs + event-study plots)
==============================================================================*/

version 17
clear all
set more off

*--- paths (repo only; Dropbox is read-only and not touched here) ------------
global REPO   "C:/Users/mva284/Documents/GitHub/ClaudeAct2260MergeExercise"
global D1     "$REPO/data/design1"
global OUT    "$REPO/output/design1"
capture mkdir "$REPO/output"
capture mkdir "$OUT"

*--- toggles ------------------------------------------------------------------
local CLEAN_ONLY  0   // 1 = keep only events with <=2 other events within 1km
local MIN_EVYEAR  2012  // drop pre-decree-era "events" (sales before Act 22)
local HALFYEARS   1   // 1 = half-year time units (4x fewer ATT(g,t) cells,
                      //     denser cells); 0 = quarters
local FAST_CS     1   // 1 = csdid2 (much faster) + jwdid; 0 = original csdid

*--- packages (one-time) ------------------------------------------------------
capture which lpdid
if _rc ssc install lpdid, replace
capture which csdid
if _rc ssc install csdid, replace
capture which drdid
if _rc ssc install drdid, replace
capture which reghdfe
if _rc ssc install reghdfe, replace
capture which ftools
if _rc ssc install ftools, replace
capture which csdid2
if _rc ssc install csdid2, replace
capture which jwdid
if _rc ssc install jwdid, replace

/*============================================================================
  1. LOAD PAIRS + FILTERS
============================================================================*/
import delimited "$D1/design1_sale_event_pairs.csv", ///
    varnames(1) encoding(utf8) stringcols(_all) clear

* numeric conversions
destring salesamt dist_m event_time_months cabida land structure totalval, ///
    replace force

* dates
gen sdate  = date(sale_date, "YMD")
gen edate  = date(event_date, "YMD")
format sdate edate %td
gen sqtr   = qofd(sdate)
gen eqtr   = qofd(edate)
format sqtr eqtr %tq

* ---- sample filters ----
drop if ring == "gap_250_400"                    // spillover buffer
drop if flag_junk_date == "True"                 // ~0.3% junk CRIM dates
drop if flag_nominal_price == "True"             // $1-type transfers
drop if sale_is_investor_parcel == "True"        // market sales only
drop if year(edate) < `MIN_EVYEAR'               // decree-era events only
keep if salesamt > 0 & !missing(salesamt)

* +/- 2y estimation window, with 1y margin so lpdid has pre-period levels
keep if inrange(event_time_months, -36, 30)

* event-level contamination info
preserve
    import delimited "$D1/design1_events.csv", varnames(1) ///
        encoding(utf8) stringcols(_all) clear
    keep event_id n_other_events_within_1000m clean_event_1000m
    destring n_other_events_within_1000m, replace force
    tempfile evinfo
    save `evinfo'
restore
merge m:1 event_id using `evinfo', keep(master match) nogen
if `CLEAN_ONLY' keep if n_other_events_within_1000m <= 2

gen lnp = ln(salesamt)

/*============================================================================
  2. TRACT-FE VERSION OF THE OUTCOME (residualize BEFORE collapsing)
============================================================================*/
egen tract = group(tract_geoid)
* hedonic-adjusted option: add cabida structure is_subunit etc. as controls here
reghdfe lnp, absorb(tract) residuals(lnp_trfe)

/*============================================================================
  3. COLLAPSE TO EVENT x RING x QUARTER PANEL
============================================================================*/
gen near = ring == "near_0_250"
egen cellid = group(event_id ring)

* time unit: quarters or half-years (HALFYEARS=1 -> 4x fewer ATT(g,t) cells)
if `HALFYEARS' {
    gen tt  = hofd(sdate)
    gen ett = hofd(edate)
    local PREW  4
    local POSTW 4
}
else {
    gen tt  = sqtr
    gen ett = eqtr
    local PREW  8
    local POSTW 8
}

collapse (mean) lnp lnp_trfe (first) near ett (count) nsales = salesamt, ///
    by(cellid tt)

* treatment structure
gen treat = near & tt >= ett           // absorbing 0->1 for near cells
gen gq    = cond(near, ett, 0)         // csdid group var (0 = never treated)

xtset cellid tt

/*============================================================================
  4. ESTIMATION  (+/- 8 quarters = +/- 2 years)
============================================================================*/
log using "$OUT/design1_lpdid_csdid.log", replace text

*---- (a) lpdid, no tract FE -------------------------------------------------
lpdid lnp, unit(cellid) time(tt) treat(treat) ///
    pre_window(`PREW') post_window(`POSTW') nevertreated
matrix LP_NOFE = r(results)
graph export "$OUT/lpdid_noFE.png", replace

*---- (b) lpdid, tract FE ----------------------------------------------------
lpdid lnp_trfe, unit(cellid) time(tt) treat(treat) ///
    pre_window(`PREW') post_window(`POSTW') nevertreated
matrix LP_FE = r(results)
graph export "$OUT/lpdid_tractFE.png", replace

*---- (c)-(d) Callaway-Sant'Anna ---------------------------------------------
* csdid computes a doubly-robust ATT(g,t) for EVERY cohort x period pair
* (~50 cohorts x ~50 periods here) -> very slow. FAST_CS=1 uses csdid2
* (same estimator, compiled, much faster) and cross-checks with jwdid
* (Wooldridge-Mundlak via reghdfe, near-instant, same never-treated logic).
* For csdid keep only the +/-2y window (the extra margin is lpdid-only).
preserve
keep if inrange(tt - ett, -`PREW'-1, `POSTW') | gq == 0

if `FAST_CS' {
    * csdid2: no tract FE
    csdid2 lnp, ivar(cellid) tvar(tt) gvar(gq) method(dripw) notyet
    estat event, window(-`PREW' `POSTW') estore(cs_noFE)
    estat plot
    graph export "$OUT/csdid_noFE.png", replace

    * csdid2: tract FE
    csdid2 lnp_trfe, ivar(cellid) tvar(tt) gvar(gq) method(dripw) notyet
    estat event, window(-`PREW' `POSTW') estore(cs_FE)
    estat plot
    graph export "$OUT/csdid_tractFE.png", replace

    * jwdid cross-check (fast; should be close to csdid2)
    jwdid lnp, ivar(cellid) tvar(tt) gvar(gq) never
    estat event
    jwdid lnp_trfe, ivar(cellid) tvar(tt) gvar(gq) never
    estat event
}
else {
    csdid lnp, ivar(cellid) time(tt) gvar(gq) method(dripw) notyet
    estat event, window(-`PREW' `POSTW')
    csdid_plot
    graph export "$OUT/csdid_noFE.png", replace

    csdid lnp_trfe, ivar(cellid) time(tt) gvar(gq) method(dripw) notyet
    estat event, window(-`PREW' `POSTW')
    csdid_plot
    graph export "$OUT/csdid_tractFE.png", replace
}
restore

log close

/*============================================================================
  NOTES / NEXT STEPS
  - Weighting: cells are unweighted means; consider [aw = nsales] robustness
    (supported in a plain stacked reghdfe check:
      reghdfe lnp i.near##ib(-1).rel_qtr [aw=nsales], absorb(cellid sqtr) )
  - If csdid errors on unbalanced cells, coarsen time (half-years) or collapse
    rings to event-level long differences.
  - Set CLEAN_ONLY=1 for the low-contamination subsample; compare.
  - Cluster level: both estimators cluster by cellid (unit) by default; the
    two cells of one event share shocks - for conservative SEs re-run csdid
    with cluster(event-level id).
  - Deflation intentionally omitted (see 2026-07-18 log): municipio repeat-
    sales index deflation is the recommended robustness, NOT tract mean price.
==============================================================================*/
