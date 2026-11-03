/*==============================================================================
 design1_pioneer_follow.do

 "Once the first investor arrives, how likely is it that others follow?"

 Units (build_pioneer_follow.py): 237 PIONEER events (first decree investor
 within 1km) vs island-wide VIRGIN LUXURY purchases (individual buyers, same
 price band, also no decree event within 1km at purchase). Outcomes: >=1 (and
 count of) subsequent other-buyer decree events within 250/500/1000m by
 horizon k = 1/2/3 years; horizon-k estimates condition on obs_yk = 1
 (date + k yrs <= 2025-12-31).

 Estimators per (radius, horizon):
   LPM:  any = b*pioneer + year FE + municipio FE, cluster(municipio)
   PPML: count, same FE/cluster (proportional, drops all-zero FE groups)
 Raw group means saved alongside for the cumulative-incidence figure.

 Output: output/design1/pioneer_follow_coefs.csv, pioneer_follow_results.log
==============================================================================*/

version 17
clear all
set more off

global REPO "C:/Users/mva284/Documents/GitHub/ClaudeAct2260MergeExercise"
global D1   "$REPO/data/design1"
global OUT  "$REPO/output/design1"

capture which reghdfe
if _rc ssc install reghdfe, replace
capture which ppmlhdfe
if _rc ssc install ppmlhdfe, replace

import delimited "$D1/pioneer_follow_units.csv", varnames(1) encoding(utf8) clear
rename group pioneer
replace municipio = upper(strtrim(municipio))
encode municipio, gen(muni)

log using "$OUT/pioneer_follow_results.log", replace text

di as result "units: " _N
count if pioneer == 1
di as result "pioneers: " r(N)

capture postclose PF
postfile PF str8 est double radius horizon coef se p double mean_pio mean_ctl ///
    double n_pio n_ctl using "$OUT/_pf_coefs.dta", replace

foreach r in 250 500 1000 {
    foreach k in 1 2 3 {
        qui summ any_`r'_y`k' if pioneer == 1 & obs_y`k' == 1
        local mp = r(mean)
        local np = r(N)
        qui summ any_`r'_y`k' if pioneer == 0 & obs_y`k' == 1
        local mc = r(mean)
        local nc = r(N)

        di as result _n "===== radius `r'm, horizon `k'y: raw P(follow) " ///
            %5.3f `mp' " (pioneer) vs " %5.3f `mc' " (virgin luxury) ====="

        * LPM with year + municipio FE
        capture noisily reghdfe any_`r'_y`k' pioneer if obs_y`k' == 1, ///
            absorb(year muni) vce(cluster muni)
        if !_rc {
            local b = _b[pioneer]
            local s = _se[pioneer]
            local pv = 2 * ttail(e(df_r), abs(`b'/`s'))
            post PF ("lpm") (`r') (`k') (`b') (`s') (`pv') (`mp') (`mc') (`np') (`nc')
        }

        * PPML on counts
        capture noisily ppmlhdfe n_`r'_y`k' pioneer if obs_y`k' == 1, ///
            absorb(year muni) vce(cluster muni)
        if !_rc {
            local b = _b[pioneer]
            local s = _se[pioneer]
            local pv = 2 * normal(-abs(`b'/`s'))
            post PF ("ppml") (`r') (`k') (`b') (`s') (`pv') (`mp') (`mc') (`np') (`nc')
        }
    }
}
postclose PF

log close

use "$OUT/_pf_coefs.dta", clear
export delimited "$OUT/pioneer_follow_coefs.csv", replace
capture erase "$OUT/_pf_coefs.dta"
di as result _n "Saved: pioneer_follow_coefs.csv"
