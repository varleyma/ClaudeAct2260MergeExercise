********************************************************************************
* HOMEOWNERSHIP COMPARISON - BAR CHART
* Reuses intermediates from homeownership_comparison.do (fast, no name loop).
* Output: output/homeownership_comparison.png
********************************************************************************
set more off
clear all

global GH    "C:/Users/mva284/Documents/GitHub/ClaudeAct2260MergeExercise"
global Clean "$GH/data/clean"
global Out   "$GH/output"

*--- Reports homeownership rate (owns a primary home) ---
use "$Clean/panel_person_ownership.dta", clear
quietly summarize ever_home
scalar rep_home = 100*r(mean)

*--- Karibe name-search rates ---
use "$Clean/names_karibe_found.dta", clear
foreach a in 22 60 {
	quietly count if act=="`a'" & usable==1
	local d = r(N)
	quietly count if act=="`a'" & usable==1 & found==1
	scalar kar`a' = 100*r(N)/`d'
}
quietly count if usable==1
local dall = r(N)
quietly count if usable==1 & found==1
scalar karall = 100*r(N)/`dall'

*--- Build the 4-bar dataset ---
clear
set obs 4
gen int order = _n
gen str26 cat = ""
gen double rate = .
gen byte grp = .
replace cat = "Owns a home (reports)"      in 1
replace rate = rep_home                     in 1
replace grp  = 1                            in 1
replace cat = "Found: Act 22 names"         in 2
replace rate = kar22                        in 2
replace grp  = 2                            in 2
replace cat = "Found: Act 60 names"         in 3
replace rate = kar60                        in 3
replace grp  = 2                            in 3
replace cat = "Found: all names"            in 4
replace rate = karall                       in 4
replace grp  = 2                            in 4

local repline = rep_home
gen lbl = string(rate, "%3.1f") + "%"

*--- Graph: reports bar (blue) vs. the three karibe search bars (orange) ---
* twoway bar gives deterministic per-group colors; scatter adds value labels.
twoway ///
	(bar rate order if grp==1, barwidth(0.72) color("31 119 180")) ///
	(bar rate order if grp==2, barwidth(0.72) color("255 127 14")) ///
	(scatter rate order, msymbol(none) mlabel(lbl) mlabposition(12) ///
		mlabcolor(black) mlabsize(medium)), ///
	yline(`repline', lpattern(dash) lcolor(cranberry)) ///
	ylabel(0(10)70, grid angle(0)) yscale(range(0 72)) ///
	ytitle("Percent of decree holders") ///
	xlabel(1 `"Owns a home"' 2 `"Act 22"' 3 `"Act 60"' 4 `"All names"', noticks labsize(small)) ///
	xtitle("") xscale(range(0.5 4.5)) ///
	title("Homeownership: reported vs. found in property search", size(medium)) ///
	subtitle("Act 22 + Act 60 decree holders", size(small)) ///
	note("Reports = self-reported primary home (owns a home)." ///
	     "Search = karibe name match; UPPER bound (same-name false positives inflate it)." ///
	     "Dashed line = reported homeownership rate (58.3%).", size(vsmall)) ///
	legend(order(1 "Reported homeownership" 2 "Found in property search") ///
		rows(1) size(small) position(6) region(lstyle(none))) ///
	graphregion(color(white)) plotregion(color(white))

* Add the group sub-labels under each bar via a second x-axis note line
* (Reports / Act 22 / Act 60 / all names)
graph export "$Out/homeownership_comparison.png", replace width(1600) height(1000)
di "Saved: $Out/homeownership_comparison.png"
