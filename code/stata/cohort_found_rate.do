********************************************************************************
* PROPERTY-SEARCH FOUND RATE BY DECREE APPROVAL COHORT (non-cumulative)
*
* Cleaner test of "is the search worse for recent decree holders": each cohort's
* OWN found rate, held to one construct. Split by Act (Act 22 = the cleanest
* within-program comparison; Act 60 shown separately).
*
* CAVEAT: a lower found rate for recent cohorts confounds TWO things --
*   (a) genuinely less time to buy AND register property, and
*   (b) worse name-search coverage. This chart cannot separate them.
*
* READ-ONLY Dropbox; output to GitHub.
********************************************************************************
set more off
clear all

global Drop  "C:/Users/mva284/Dropbox/ClaudeAct2260MergeExercise/data/raw"
global GH    "C:/Users/mva284/Documents/GitHub/ClaudeAct2260MergeExercise"
global Clean "$GH/data/clean"
global Out   "$GH/output"

*--- name normalizer ---
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

*--- decree names + approval year + act ---
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
gen ayear = year(date(approval_date, "MDY"))
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

*--- cohort found rate: mean(found) by act x approval year ---
collapse (mean) found_pct=found (sum) n=one, by(act ayear)
replace found_pct = 100*found_pct
gen nlab = string(n)
sort act ayear
list act ayear n found_pct, sepby(act) noobs
save "$Clean/cohort_found.dta", replace

*--- chart: Act 22 cohorts (2012-2020, reliable N) and Act 60 cohorts (2021-2024) ---
twoway ///
	(connected found_pct ayear if act=="22" & inrange(ayear,2012,2020), ///
		lcolor(navy) mcolor(navy) msymbol(O) lwidth(medthick) ///
		mlabel(nlab) mlabpos(12) mlabsize(vsmall) mlabcolor(navy)) ///
	(connected found_pct ayear if act=="60" & inrange(ayear,2021,2024), ///
		lcolor(orange) mcolor(orange) msymbol(D) lpattern(dash) lwidth(medthick) ///
		mlabel(nlab) mlabpos(12) mlabsize(vsmall) mlabcolor(orange)), ///
	ylabel(0(10)70, grid angle(0)) yscale(range(0 72)) ///
	ytitle("% of cohort found with property (search)") ///
	xlabel(2012(1)2024, angle(45)) xtitle("Decree approval year (cohort)") ///
	title("Property-search found rate by approval cohort", size(medium)) ///
	subtitle("Each point = that cohort's own found rate (non-cumulative)", size(small)) ///
	legend(order(1 "Act 22 cohorts" 2 "Act 60 cohorts") ///
		rows(1) size(small) position(6) region(lstyle(none))) ///
	note("Labels = cohort size (N). A lower rate for recent cohorts confounds" ///
	     "less-time-to-buy/register with worse search coverage -- cannot separate them.", ///
	     size(vsmall)) ///
	graphregion(color(white)) plotregion(color(white))

graph export "$Out/cohort_found_rate.png", replace width(1700) height(1050)
di "Saved: $Out/cohort_found_rate.png"
