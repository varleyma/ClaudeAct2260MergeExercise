*** Tract DiD Design ***
*** By: Lucy Msall and Michael Varley

set more off 
clear


global MyPath "C:/Users/mva284"
*global MyPath "C:/Users/Michael"

* Comment out the code above, uncomment the code below with your local 
* 	path if you want to run this code on your computer. 
*global MyPath "C:/Users/lucyusername"

global MainPath "$MyPath/Dropbox/Ley60PR"
global DataPath "$MainPath/data"
global RawDataPath "$DataPath/raw"
global CleanDataPath "$DataPath/clean"
global OutputPath "$MainPath/output"

********************************************************************************

********************************
**** Muni House Price Data ****
********************************

*import delim "$CleanDataPath/crim_parcels_uniquematch_tracts.csv", varn(1) clear
import delim ///
	"$CleanDataPath/combined_parcels_uniquematch_tracts.csv", varn(1) clear

keep salesamt salesdate tract_geoid zcta

gen year = substr(salesdate,1,4)
gen month = substr(salesdate,6,2)

destring year month, replace force
gen ym = ym(year,month)

format %tm ym

keep salesamt ym tract_geoid zcta
gen num_investor_sales = 1
rename salesamt price_investor


collapse (firstnm) zcta (mean) price_investor (sum) num_investor_sales, ///
	by(tract_geoid ym)

tempfile CRIM
save `CRIM', replace

import delim "$CleanDataPath/monthly_data_red_atlas.csv", varn(1) clear

keep geotractid month meantransactionpricepertract ///
	mediantransactionpricetract numberoftransactions
	
rename meantransactionpricepertract price_tract_mean
rename mediantransactionpricetract price_tract_median
rename numberoftransactions num_sales
rename geotractid tract_geoid
rename month date

gen year = substr(date,1,4)
gen month = substr(date,6,2)

destring year month, replace force
gen ym = ym(year,month)

format %tm ym

merge 1:1 tract_geoid ym using `CRIM', keep(matched master)

egen temp = mean(zcta), by(tract_geoid)
drop zcta
rename temp zcta 

replace num_investor_sales = 0 if _merge == 1

gen investor_sale = (num_investor_sales > 0)

sort tract_geoid ym
by tract_geoid: gen temp = sum(investor_sale)
gen treat = temp > 0
drop temp

// xtset tract_geoid ym, m
// gen treat2 = F2.treat
// gen lnhp = 100*ln(price_tract_mean)
// gen fips = floor(tract_geoid/1000000)
// gen lnsales = 100*ln(num_sales)
// gen lninv_sales = 100*ln(num_investor_sales)
// 
// lpdid lnhp, ///
// 	unit(tract_geoid) time(ym) treat(treat) ///
// 	pre_window(36) post_window(36)
//	
// lpdid num_investor_sales, ///
// 	unit(tract_geoid) time(ym) treat(treat) ///
// 	pre_window(12) post_window(12) 
//	
// lpdid num_sales, ///
// 	unit(tract_geoid) time(ym) treat(treat) ///
// 	pre_window(12) post_window(12) 
//	
// gen num_noninv_sales = num_sales - num_investor_sales
//
// lpdid num_noninv_sales, ///
// 	unit(tract_geoid) time(ym) treat(treat) ///
// 	pre_window(12) post_window(12)
//	
// gen inv_sales_share = 100*num_investor_sales/num_sales
//
// lpdid inv_sales_share, ///
// 	unit(tract_geoid) time(ym) treat(treat) ///
// 	pre_window(12) post_window(12)
	

	
collapse (max) treat (sum) num_sales num_investor_sales ///
	(mean) price_tract_mean price_tract_median, ///
	by(tract_geoid year)
	
gen fips = floor(tract_geoid/1000000)
egen fips_year = group(fips year)
*egen zcta_year = group(zcta year)
gen lnhp = 100*ln(price_tract_mean)
gen lnsales = 100*ln(num_sales)
gen num_noninv_sales = num_sales - num_investor_sales

gen treat_year_dummy = year if treat == 1 
egen treat_year = min(treat_year_dummy), by(tract_geoid)
replace treat_year = 0 if treat_year == .
	
lpdid lnhp, ///
	unit(tract_geoid) time(year) treat(treat) ///
	pre_window(4) post_window(3) nograph

matrix R = e(results)
svmat R, names(col)   // turns the matrix columns into variables
gen rel_time = _n - 5 if ci_low<.

lpdid lnhp, ///
	unit(tract_geoid) time(year) treat(treat) ///
	pre_window(4) post_window(3) nograph absorb(fips)
	
matrix R = e(results)

* append _fe to every column name
local cn : colnames R
local newnames ""
foreach c of local cn {
    local newnames "`newnames' `c'_fe"
}

matrix colnames R = `newnames'
svmat R, names(col)   // turns the matrix columns into variables

twoway (rcap ci_low ci_high rel_time, color(gs12)) ///
	   (rcap ci_low_fe ci_high_fe rel_time, color(gs12)) ///
       (connected coefficient coefficient_fe rel_time, ///
			mcolor(navy blue) lcolor(navy blue)), ///
			yline(0, lpattern(dash)) xline(-1, lpattern(dot)) ///
			xtitle("Year since First Investor Purchase in Census Tract") ///
			ytitle("Percent") ///
			title("Dynamic DiD: Log(House Price)") ///
			name("lnhp_tract", replace)
			xlabel(-4(1)3) ///
			legend(order(3 "Base" 4 "+ County FEs") ///
				pos(6) rows(1))

lpdid lnsales, ///
	unit(tract_geoid) time(year) treat(treat) ///
	pre_window(4) post_window(3)
	
//	
// lpdid num_investor_sales, ///
// 	unit(tract_geoid) time(year) treat(treat) ///
// 	pre_window(5) post_window(4)
//
// gen inv_sales_share = 100*num_investor_sales/num_sales
//
// lpdid inv_sales_share, ///
// 	unit(tract_geoid) time(year) treat(treat) ///
// 	pre_window(5) post_window(4)

