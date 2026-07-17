********************************************************************************
* FALSE-POSITIVE CHECK FOR THE KARIBE NAME SEARCH
*
* Question: how much of the ~52% "found with property" is real vs. inflated by
*           same-name coincidences (searching 'Gary Smith' returns every Gary
*           Smith)?
*
* Method 1 (PLACEBO / PERMUTATION): scramble first<->last name pairings across
*   decree holders to make realistic-but-fake names, run the IDENTICAL match
*   against karibe. Any hits are pure name-coincidence => false-positive floor.
*
* Method 2 (SURNAME COMMONNESS): found rate should rise with how common the
*   surname is if collisions inflate it; distinctive surnames give a cleaner rate.
*
* Reuses intermediates from homeownership_comparison.do. READ-ONLY Dropbox.
********************************************************************************
set more off
clear all

global GH    "C:/Users/mva284/Documents/GitHub/ClaudeAct2260MergeExercise"
global Clean "$GH/data/clean"
global Out   "$GH/output"

*-------------------------------------------------------------------------------
* Build unique (tid, token) list from the normalized karibe owner names
*-------------------------------------------------------------------------------
use "$Clean/karibe_norm.dta", clear          // vars: tid, tpad (" TOK TOK ")
split tpad, parse(" ") generate(w)
drop tpad
reshape long w, i(tid) j(k)
drop k
rename w token
drop if token == ""
bysort tid token: keep if _n == 1
save "$Clean/karibe_tokens.dta", replace
global TOK "$Clean/karibe_tokens.dta"
di "karibe (tid,token) pairs: " _N

*-------------------------------------------------------------------------------
* Usable decree names (reuse normalized fn/ln + loop-based 'found')
*-------------------------------------------------------------------------------
use "$Clean/names_karibe_found.dta", clear
keep if usable == 1
gen long nid = _n
keep nid fn ln found act
rename fn F
rename ln L
save "$Clean/names_for_fp.dta", replace
count
local Nusable = r(N)

*-------------------------------------------------------------------------------
* Fast vectorized matcher: a name matches if some titular contains BOTH its
* first and last token. Blocks on last name (more selective).
* Expects vars nid F L in memory; returns r(rate), r(nfound), r(ndenom).
*-------------------------------------------------------------------------------
capture program drop run_match
program run_match, rclass
	qui count
	local d = r(N)
	preserve
	keep nid F L
	gen token = L
	joinby token using "$TOK"                       // tids containing last name
	replace token = F
	merge m:1 tid token using "$TOK", keep(match) nogen keepusing(tid)
	keep nid
	duplicates drop
	qui count
	local f = r(N)
	restore
	return scalar ndenom = `d'
	return scalar nfound = `f'
	return scalar rate   = `f'/`d'
end

*-------------------------------------------------------------------------------
* REAL found rate (validate vectorized matcher vs the loop-based 'found')
*-------------------------------------------------------------------------------
use "$Clean/names_for_fp.dta", clear
run_match
scalar real_rate = r(rate)
qui summarize found
di "Loop-based real found rate:       " %5.1f 100*r(mean) "%"
di "Vectorized real found rate:       " %5.1f 100*real_rate "%   (should match)"

*-------------------------------------------------------------------------------
* PLACEBO: scramble last names, re-run match, average over many permutations
*-------------------------------------------------------------------------------
set seed 8675309
local R = 30
matrix P = J(`R', 1, .)
scalar tot_excl = 0

forvalues r = 1/`R' {
	use "$Clean/names_for_fp.dta", clear
	gen long id0 = _n

	* shuffle the last-name column
	preserve
		keep id0 L
		gen double u = runiform()
		sort u
		gen long newid = _n
		keep newid L
		rename L Lperm
		tempfile pf
		save `pf'
	restore
	rename id0 newid
	merge 1:1 newid using `pf', nogen

	* drop placebo names that happen to equal a REAL decree full name
	gen realfull = F + "|" + L
	gen permfull = F + "|" + Lperm
	preserve
		keep realfull
		duplicates drop
		rename realfull permfull
		gen byte isreal = 1
		tempfile rf
		save `rf'
	restore
	merge m:1 permfull using `rf', keep(master match) nogen
	replace isreal = 0 if isreal == .
	qui count if isreal == 1
	scalar tot_excl = tot_excl + r(N)

	drop L
	rename Lperm L
	keep if isreal == 0

	run_match
	matrix P[`r', 1] = r(rate)
}

svmat P, names(prate)
qui summarize prate1
scalar plac_mean = r(mean)
scalar plac_min  = r(min)
scalar plac_max  = r(max)
di "Placebo (scrambled-name) found rate: mean " %4.1f 100*plac_mean ///
	"%  [min " %4.1f 100*plac_min "%, max " %4.1f 100*plac_max "%]"

*-------------------------------------------------------------------------------
* Method 2: found rate by how common the surname is (in the decree list)
*-------------------------------------------------------------------------------
use "$Clean/names_for_fp.dta", clear
bysort L: gen lcount = _N
gen str16 surntype = "3+ share surname" if lcount >= 3
replace surntype   = "2 share surname"  if lcount == 2
replace surntype   = "unique surname"   if lcount == 1
di "Found rate by surname commonness (decree list):"
table surntype, statistic(mean found) statistic(frequency) nformat(%5.3f)

*-------------------------------------------------------------------------------
* Report
*-------------------------------------------------------------------------------
scalar real_pct  = 100*real_rate
scalar plac_pct  = 100*plac_mean

* Surname-commonness rates (recompute here for the report)
use "$Clean/names_for_fp.dta", clear
bysort L: gen lcount = _N
quietly summarize found if lcount == 1
scalar uniq_pct = 100*r(mean)
quietly summarize found if lcount >= 3
scalar comm_pct = 100*r(mean)
quietly summarize found
scalar raw_pct = 100*r(mean)

capture file close fh
file open fh using "$Out/false_positive_check.txt", write replace text
file write fh "HOW BADLY COULD SAME-NAME FALSE POSITIVES INFLATE THE ~52%?" _n
file write fh "==========================================================" _n _n
file write fh "Raw name search found property for  " %4.1f (raw_pct) "% of decree names." _n
file write fh "There are TWO kinds of false positive; they differ a lot in size." _n _n

file write fh "1) UNRELATED-NAME COINCIDENCE  (a totally different name matches)" _n
file write fh "   Placebo test: scramble first<->last pairings into fake-but-" _n
file write fh "   realistic names, run the same search. They match only " ///
	%3.1f (plac_pct) "%" _n
file write fh "   of the time (mean of 30 shuffles; range " %3.1f (100*plac_min) ///
	"-" %3.1f (100*plac_max) "%)." _n
file write fh "   => Random-name noise is SMALL. The search is not just matching junk." _n _n

file write fh "2) SAME-NAME, DIFFERENT PERSON  (searched the right name, but the" _n
file write fh "   property belongs to a namesake) -- the real concern, and the" _n
file write fh "   placebo CANNOT see it. Proxy = how found rate moves with how" _n
file write fh "   common the surname is (true ownership should not depend on that):" _n
file write fh "     unique surname (1 holder):   " %4.1f (uniq_pct) "%" _n
file write fh "     3+ holders share surname:    " %4.1f (comm_pct) "%" _n
file write fh "   The " %3.1f (comm_pct-uniq_pct) "-point jump for common surnames is" _n
file write fh "   plausibly namesake inflation, concentrated among common names." _n _n

file write fh "BOTTOM LINE" _n
file write fh "- Wholesale name noise is minor (~" %2.0f (plac_pct) "%)." _n
file write fh "- But namesake collisions DO inflate the raw " %2.0f (raw_pct) "%: a" _n
file write fh "  cleaner 'discovery' rate is nearer the unique-surname " %2.0f (uniq_pct) "%," _n
file write fh "  so the raw figure is inflated by roughly " %2.0f (raw_pct-uniq_pct) ///
	"-" %2.0f (comm_pct-uniq_pct) " points" _n
file write fh "  (aggregate vs. common-surname worst case)." _n
file write fh "- Net: the earlier conclusion (search UNDER-covered true owners," _n
file write fh "  ~58% own vs ~52% found) is ROBUST -- deflating for false positives" _n
file write fh "  only widens the gap." _n
file close fh

type "$Out/false_positive_check.txt"
di "Placebo names excluded as accidental real names (total over 30 reps): " tot_excl
