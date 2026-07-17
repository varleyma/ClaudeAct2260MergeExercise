********************************************************************************
* HOMEOWNERSHIP RATE COMPARISON
*   Reports panel (who actually owns PR property, self-reported in filings)
*     vs.
*   Karibe name-search in property records (who we FOUND with property)
*
* Purpose: gauge how successful the property-record name search (karibe_matched)
*          was at finding decree holders who own property. The panel gives an
*          independent estimate of the true ownership rate.
*
* NOTE: Annual reports are redacted (no names), so this is an AGGREGATE-RATE
*       comparison, not a person-to-person link.
*
* READ-ONLY from Dropbox; all output written to GitHub.
********************************************************************************

set more off
clear all

global Drop  "C:/Users/mva284/Dropbox/ClaudeAct2260MergeExercise/data/raw"
global GH    "C:/Users/mva284/Documents/GitHub/ClaudeAct2260MergeExercise"
global Clean "$GH/data/clean"
global Out   "$GH/output"

capture mkdir "$Out"

*-------------------------------------------------------------------------------
* Normalization helper: strip accents, uppercase, punctuation -> space, squeeze
*-------------------------------------------------------------------------------
capture program drop norm_str
program define norm_str
	args v
	* Strip accents/diacritics (Wayné -> Wayne) then ASCII
	replace `v' = ustrto(ustrnormalize(`v', "nfd"), "ascii", 2)
	replace `v' = upper(`v')
	* Replace punctuation with spaces (explicit, to avoid quote-parsing issues)
	replace `v' = subinstr(`v', ".", " ", .)
	replace `v' = subinstr(`v', ",", " ", .)
	replace `v' = subinstr(`v', "-", " ", .)
	replace `v' = subinstr(`v', "/", " ", .)
	replace `v' = subinstr(`v', "(", " ", .)
	replace `v' = subinstr(`v', ")", " ", .)
	replace `v' = subinstr(`v', ";", " ", .)
	replace `v' = subinstr(`v', ":", " ", .)
	replace `v' = subinstr(`v', "*", " ", .)
	replace `v' = subinstr(`v', "#", " ", .)
	replace `v' = subinstr(`v', char(39), " ", .)
	replace `v' = subinstr(`v', char(34), " ", .)
	replace `v' = stritrim(strtrim(`v'))
end

********************************************************************************
* PART A: REPORTS-BASED HOMEOWNERSHIP (from panel + raw Own/Rent fields)
********************************************************************************

*-------------------------------------------------------------------------------
* A1. Build a filename -> ownership crosswalk from ALL raw report files
*     Fields: own_home ("Own"/"Rent"/...) and primary_property_value
*-------------------------------------------------------------------------------
* Single-line, unquoted list (filenames have no spaces). Quoted items with ///
* line continuation corrupt the list, so keep this on one line.
local rawfiles Act22AnnualReports2015-2018 Act22AnnualReports2019 Act22AnnualReports2020 Act22AnnualReports2021 Act22AnnualReports2022_format19 Act22AnnualReports2022_format22 Act22AnnualReports2023

local first = 1
foreach f of local rawfiles {
	di "Reading `f' ..."
	import delimited "$Drop/`f'.csv", varnames(1) clear stringcols(_all)

	* Homeownership Own/Rent question (long name, truncated by Stata; grab by wildcard)
	capture gen own_home = ""
	foreach v of varlist *own_a_home* {
		replace own_home = `v'
	}

	* Primary property value (may be absent in some files)
	capture confirm variable primary_property_value
	if _rc == 0 {
		gen double primary_val = real(primary_property_value)
	}
	else {
		gen double primary_val = .
	}

	keep filename own_home primary_val
	gen src = "`f'"

	if `first' == 1 {
		tempfile xwalk
		save `xwalk'
		local first = 0
	}
	else {
		append using `xwalk'
		save `xwalk', replace
	}
}

use `xwalk', clear
* One row per filename (a filename is a single report)
gsort filename
by filename: keep if _n == 1
save "$Clean/report_ownership_xwalk.dta", replace

di "Ownership crosswalk rows (unique filenames): " _N
gen own_bin = (own_home == "Own")
tab own_home if inlist(own_home,"Own","Rent"), missing
di "Raw report-level: share Own among Own/Rent responses:"
count if inlist(own_home,"Own","Rent")
local denom = r(N)
count if own_home == "Own"
di "  " r(N)/`denom'

*-------------------------------------------------------------------------------
* A2. Attach ownership to the panel and collapse to PERSON level
*-------------------------------------------------------------------------------
use "$Clean/act22_panel_full.dta", clear

* Build a single source filename per panel row (coalesce across year columns)
gen filename_key = filename
foreach y in 2015_2018 2019 2020 2021 2022 2023 {
	replace filename_key = filename_`y' if (filename_key == "" | filename_key == ".") & filename_`y' != ""
}

* Crosswalk keyed on filename -> rename to filename_key and merge
preserve
use "$Clean/report_ownership_xwalk.dta", clear
rename filename filename_key
tempfile xw2
save `xw2'
restore
merge m:1 filename_key using `xw2', keepusing(own_home primary_val) ///
	keep(master match) nogen

* Person-year ownership signals
gen byte own_home_bin = (own_home == "Own")
gen byte primary_pos  = (primary_val > 0 & !missing(primary_val))
gen byte re_pos       = (re > 0 & !missing(re))
gen byte owns_any_py  = (own_home_bin | primary_pos | re_pos)

* Collapse to person level: owns if TRUE in ANY report year
collapse (max) ever_own_home=own_home_bin (max) ever_primary=primary_pos ///
	(max) ever_re=re_pos (max) ever_any=owns_any_py, by(panel_id)

count
local n_people = r(N)
di "=================================================================="
di "REPORTS-BASED HOMEOWNERSHIP (person level, N = `n_people' decree"
di "  holders who filed Act 22 annual reports)"
di "=================================================================="
foreach m in ever_own_home ever_primary ever_re ever_any {
	quietly summarize `m'
	di "  `m': " %5.1f 100*r(mean) "%  (" r(sum) " of `n_people')"
}

* Save person-level ownership summary
save "$Clean/panel_person_ownership.dta", replace

* Stash key numbers
quietly summarize ever_any
scalar rep_any = r(mean)
scalar rep_n   = r(N)
quietly summarize ever_re
scalar rep_re  = r(mean)
quietly summarize ever_own_home
scalar rep_own = r(mean)

********************************************************************************
* PART B: KARIBE NAME-SEARCH IMPLIED OWNERSHIP RATE
********************************************************************************

*-------------------------------------------------------------------------------
* B1. Normalize the karibe property-owner names (titular)
*-------------------------------------------------------------------------------
import delimited "$Drop/karibe_matched.csv", varnames(1) clear stringcols(_all)
gen long tid = _n
keep tid titular
gen tnorm = titular
norm_str tnorm
gen tpad = " " + tnorm + " "
keep tid tpad
save "$Clean/karibe_norm.dta", replace
di "Karibe property records: " _N

*-------------------------------------------------------------------------------
* B2. Build decree-holder name universe (Act 22 and Act 60)
*-------------------------------------------------------------------------------
import delimited "$Drop/names_individuos22.csv", varnames(1) clear stringcols(_all)
gen act = "22"
tempfile n22
save `n22'
import delimited "$Drop/names_individuos60.csv", varnames(1) clear stringcols(_all)
gen act = "60"
append using `n22'

gen fn = first_name
gen ln = last_name
norm_str fn
norm_str ln

* Dedupe on normalized full name within act
gen fullnorm = fn + " " + ln
bysort act fullnorm: keep if _n == 1

* Only usable names (need reasonably distinctive tokens)
gen usable = (strlen(ln) >= 3 & strlen(fn) >= 2)

*-------------------------------------------------------------------------------
* B3. For each decree name, is there a karibe titular containing BOTH names?
*     Whole-word match via space-padding to avoid partial hits (AL in ALBERT).
*-------------------------------------------------------------------------------
frame create karibe
frame karibe: use "$Clean/karibe_norm.dta", clear

gen byte found = 0
local N = _N
forvalues i = 1/`N' {
	if usable[`i'] == 0 continue
	local f = fn[`i']
	local l = ln[`i']
	frame karibe: count if strpos(tpad, " `f' ") > 0 & strpos(tpad, " `l' ") > 0
	if r(N) > 0 replace found = 1 in `i'
}

save "$Clean/names_karibe_found.dta", replace

*-------------------------------------------------------------------------------
* B4. Implied ownership rates from the name search
*-------------------------------------------------------------------------------
di "=================================================================="
di "KARIBE NAME-SEARCH: share of decree holders found with >=1 property"
di "  (UPPER bound - inflated by same-name false positives)"
di "=================================================================="
foreach a in 22 60 {
	quietly count if act == "`a'" & usable == 1
	local du = r(N)
	quietly count if act == "`a'" & usable == 1 & found == 1
	local fu = r(N)
	di "  Act `a': " %5.1f 100*`fu'/`du' "%  (" `fu' " of `du' usable names)"
}
quietly count if usable == 1
local duall = r(N)
quietly count if usable == 1 & found == 1
local fuall = r(N)
di "  Combined: " %5.1f 100*`fuall'/`duall' "%  (" `fuall' " of `duall')"

scalar kar_all = `fuall'/`duall'
quietly count if act=="22" & usable==1
scalar kar22_d = r(N)
quietly count if act=="22" & usable==1 & found==1
scalar kar22_f = r(N)
scalar kar22 = kar22_f/kar22_d
quietly count if act=="60" & usable==1
scalar kar60_d = r(N)
quietly count if act=="60" & usable==1 & found==1
scalar kar60_f = r(N)
scalar kar60 = kar60_f/kar60_d

********************************************************************************
* PART C: WRITE COMPARISON REPORT
********************************************************************************
scalar recall_ceiling = 100*kar22/rep_any

capture file close fh
file open fh using "$Out/homeownership_comparison.txt", write replace text
file write fh "HOMEOWNERSHIP RATE COMPARISON" _n
file write fh "Reports panel (true ownership) vs. karibe name-search (found)" _n
file write fh "=============================================================" _n _n

file write fh "A) REPORTS-BASED  (person level, N=" (rep_n) " Act 22 report filers)" _n
file write fh "   Every panel row matched the ownership crosswalk (100%)." _n
file write fh "   Owns primary home (ever 'Own'):    " %5.1f (100*rep_own) "%" _n
file write fh "   Owns real estate assets (re>0):    " %5.1f (100*rep_re)  "%" _n
file write fh "   Owns ANY property (home OR re>0):   " %5.1f (100*rep_any) "%" _n _n

file write fh "B) KARIBE NAME-SEARCH  (share of decree holders found w/ >=1 property)" _n
file write fh "   Act 22 names:  " %5.1f (100*kar22)   "%   (" (kar22_f) " of " (kar22_d) ")" _n
file write fh "   Act 60 names:  " %5.1f (100*kar60)   "%   (" (kar60_f) " of " (kar60_d) ")" _n
file write fh "   All names:     " %5.1f (100*kar_all) "%   (" (kar22_f+kar60_f) " of " (kar22_d+kar60_d) ")" _n _n

file write fh "INTERPRETATION" _n
file write fh "Compare like-for-like: Act 22 reports say ~" %2.0f (100*rep_any) ///
	"% of filers own PR" _n
file write fh "property, but the name search turned up property for only " ///
	%2.0f (100*kar22) "% of" _n
file write fh "Act 22 names. Because the search rate is inflated by same-name false" _n
file write fh "positives (searching 'Gary Smith' returns every Gary Smith), it is an" _n
file write fh "UPPER bound - yet it still sits below the true ownership rate." _n _n
file write fh "=> Implied recall CEILING = kar22 / reports_any = " %3.0f (recall_ceiling) "%." _n
file write fh "   The search missed at least ~" %2.0f (100-recall_ceiling) ///
	"% of property-owning Act 22" _n
file write fh "   decree holders (more once false positives are netted out)." _n _n

file write fh "CAVEATS" _n
file write fh "- Reports are redacted (no names): aggregate-rate comparison only." _n
file write fh "- Populations differ: report FILERS vs. all named decree holders." _n
file write fh "- Reports = self-reported primary home + RE assets; karibe = any" _n
file write fh "  registry property (primary, investment, timeshare)." _n
file close fh

type "$Out/homeownership_comparison.txt"

di _n "DONE. Report written to $Out/homeownership_comparison.txt"
