********************************************************************************
* TIME SERIES: reports homeownership (Own/Rent) vs. property-search implied
*              homeownership (cumulative, using decree approval dates)
*
* Reports side:  share who OWN, by reporting year (from the Own/Rent field).
* Search side:   karibe has no dates, so use decree APPROVAL year + the
*                "once a homeowner, always a homeowner" assumption:
*                cumulative share of decree holders (approved by year Y) who are
*                found as a property owner in karibe.
*
* READ-ONLY Dropbox; output to GitHub.
********************************************************************************
set more off
clear all

global Drop  "C:/Users/mva284/Dropbox/ClaudeAct2260MergeExercise/data/raw"
global GH    "C:/Users/mva284/Documents/GitHub/ClaudeAct2260MergeExercise"
global Clean "$GH/data/clean"
global Out   "$GH/output"

*--- name normalizer (accents -> ascii, upper, punctuation -> space) ---
capture program drop norm_str
program define norm_str
	args v
	replace `v' = ustrto(ustrnormalize(`v', "nfd"), "ascii", 2)
	replace `v' = upper(`v')
	foreach c in "." "," "-" "/" "(" ")" ";" ":" "*" "#" {
		replace `v' = subinstr(`v', "`c'", " ", .)
	}
	replace `v' = subinstr(`v', char(39), " ", .)
	replace `v' = subinstr(`v', char(34), " ", .)
	replace `v' = stritrim(strtrim(`v'))
end

********************************************************************************
* PART 1: REPORTS -- share who OWN, by reporting year
********************************************************************************
local rawfiles Act22AnnualReports2015-2018 Act22AnnualReports2019 Act22AnnualReports2020 Act22AnnualReports2021 Act22AnnualReports2022_format19 Act22AnnualReports2022_format22 Act22AnnualReports2023

local first = 1
foreach f of local rawfiles {
	import delimited "$Drop/`f'.csv", varnames(1) clear stringcols(_all)
	capture gen own_home = ""
	foreach v of varlist *own_a_home* {
		replace own_home = `v'
	}
	capture confirm variable primary_property_value
	if _rc == 0 gen double primary_val = real(primary_property_value)
	else gen double primary_val = .
	capture confirm variable current_reporting_year
	gen double yr = real(current_reporting_year)
	keep own_home primary_val yr
	if `first' == 1 {
		tempfile R
		save `R'
		local first = 0
	}
	else {
		append using `R'
		save `R', replace
	}
}

use `R', clear
gen byte one       = 1
gen byte ownflag   = (own_home == "Own")
gen byte validresp = inlist(own_home, "Own", "Rent")
gen byte home      = (own_home == "Own") | (primary_val > 0 & !missing(primary_val))
rename yr year

* Own share among valid Own/Rent responses
preserve
	keep if validresp
	collapse (mean) own_rate=ownflag (sum) nvalid=one, by(year)
	tempfile own
	save `own'
restore
* Home share (Own OR primary value>0) among all filers
collapse (mean) home_rate=home (sum) nfilers=one, by(year)
merge 1:1 year using `own', nogen
keep if inrange(year, 2013, 2023)
replace own_rate  = 100*own_rate
replace home_rate = 100*home_rate
gen str6 tag = "REPORTS"
list year nfilers nvalid own_rate home_rate, sepby(tag) noobs
save "$Clean/ts_reports.dta", replace

********************************************************************************
* PART 2: PROPERTY SEARCH -- cumulative found-homeowner share by approval year
********************************************************************************
*--- karibe tokens (tid, token) ---
use "$Clean/karibe_norm.dta", clear
split tpad, parse(" ") generate(w)
drop tpad
reshape long w, i(tid) j(k)
drop k
rename w token
drop if token == ""
bysort tid token: keep if _n == 1
tempfile TOKENS
save `TOKENS'

*--- decree names with approval date ---
import delimited "$Drop/names_individuos22.csv", varnames(1) clear stringcols(_all)
gen act = "22"
tempfile n22
save `n22'
import delimited "$Drop/names_individuos60.csv", varnames(1) clear stringcols(_all)
gen act = "60"
append using `n22'

gen F = first_name
gen L = last_name
norm_str F
norm_str L
gen byte usable = (strlen(L) >= 3 & strlen(F) >= 2)
gen adate = date(approval_date, "MDY")
gen ayear = year(adate)
gen long nid = _n
gen byte one = 1

*--- found = some titular contains BOTH first and last token ---
preserve
	keep if usable
	keep nid F L
	gen token = L
	joinby token using `TOKENS'
	replace token = F
	merge m:1 tid token using `TOKENS', keep(match) nogen keepusing(tid)
	keep nid
	duplicates drop
	gen byte found = 1
	tempfile MATCHED
	save `MATCHED'
restore
merge 1:1 nid using `MATCHED', keep(master match) nogen
replace found = 0 if found == .

keep if usable == 1 & !missing(ayear)

* Distinctive surname = surname held by only one decree person (namesake-robust)
bysort L: gen lcount = _N
gen byte uniqsurn = (lcount == 1)

* (a) cumulative found share, ALL names (raw)
preserve
	collapse (sum) tot=one (sum) fnd=found, by(ayear)
	sort ayear
	gen ctot = sum(tot)
	gen cfnd = sum(fnd)
	gen cum_found = 100*cfnd/ctot
	rename ayear year
	keep year cum_found
	tempfile full
	save `full'
restore

* (b) cumulative found share, DISTINCTIVE-surname holders only (FP-deflated)
keep if uniqsurn == 1
collapse (sum) tot=one (sum) fnd=found, by(ayear)
sort ayear
gen ctot = sum(tot)
gen cfnd = sum(fnd)
gen cum_found_uniq = 100*cfnd/ctot
rename ayear year
keep year cum_found_uniq
merge 1:1 year using `full', nogen
sort year
list year cum_found cum_found_uniq, noobs
save "$Clean/ts_search.dta", replace

********************************************************************************
* PART 3: combine + chart
********************************************************************************
use "$Clean/ts_reports.dta", clear
keep year own_rate home_rate
merge 1:1 year using "$Clean/ts_search.dta", nogen
keep if inrange(year, 2015, 2022)
sort year
save "$Clean/ts_combined.dta", replace
list year own_rate cum_found cum_found_uniq, noobs

twoway ///
	(connected own_rate year, lcolor(navy) mcolor(navy) ///
		msymbol(O) lwidth(medthick)) ///
	(connected cum_found year, lcolor(orange) mcolor(orange) ///
		msymbol(D) lpattern(dash) lwidth(medthick)) ///
	(connected cum_found_uniq year, lcolor(cranberry) mcolor(cranberry) ///
		msymbol(T) lpattern(shortdash) lwidth(medthick)), ///
	ylabel(40(5)65, grid angle(0)) yscale(range(40 65)) ///
	ytitle("Percent who own a home") ///
	xlabel(2015(1)2022) xtitle("Reporting year (reports) / approval year (search)") ///
	title("Homeownership over time: reports vs. property search", size(medium)) ///
	subtitle("Act 22 + Act 60 decree holders, 2015-2022", size(small)) ///
	legend(order(1 "Reports: share who OWN" ///
		2 "Search: found w/ property (all names)" ///
		3 "Search: distinctive surnames only (namesake-robust)") ///
		rows(3) size(small) position(6) region(lstyle(none))) ///
	note("Search = cumulative homeowner share by decree approval year (once-a-homeowner-always)." ///
	     "Distinctive-surname line strips same-name false positives.", size(vsmall)) ///
	graphregion(color(white)) plotregion(color(white))

graph export "$Out/ownership_timeseries.png", replace width(1700) height(1050)
di "Saved chart: $Out/ownership_timeseries.png"
