
*** By: Michael Varley and Lucy Msall
*** Kentucky Gatton

set more off 
clear


global MyPath "C:/Users/mva284"
*global MyPath "C:/Users/Michael"

* Lucy: comment out the code above, uncomment the code below with your local 
* 	path if you want to run this code on your computer. 
*global MyPath "C:/Users/lucyusername"

global MainPath "$MyPath/Dropbox/Ley60PR"
global DataPath "$MainPath/data"
global RawDataPath "$DataPath/raw"
global CleanDataPath "$DataPath/clean"
global OutputPath "$MainPath/output"

********************************************************************************

use "$CleanDataPath/merge_practice_2015_2018_folder.dta", clear

* Match 2017 to 2018
keep if financial_wealth2017 != "" | ///
	real_estate_wealth2017 != "" | ///
	business_wealth2017 != "" | ///
	other_wealth2017 != ""

keep id financial_wealth2017-other_wealth2017 decree_year municipio*

* These are almost certainly secondary household members
drop if financial_wealth2017 == "NA" & ///
	real_estate_wealth == "NA" & ///
	business_wealth == "NA" & ///
	other_wealth == "NA"
	
foreach var in financial_wealth real_estate_wealth business_wealth ///
	other_wealth {
		destring `var'2017, replace force
		replace `var'2017 = round(`var'2017)
}


egen temp = tag(municipio_name_mode ///
	financial_wealth2017 ///
	real_estate_wealth2017 ///
	business_wealth2017 ///
	other_wealth2017)

tab temp
drop if temp == 0


tempfile MATCH17_1518
save `MATCH17_1518'

use "$CleanDataPath/merge_practice_2019.dta", clear

* Focus on 2018 cohort. 
keep if year == 2018
* Drop if previous year is not there
keep if previous_year == 2017

foreach var in financial_wealth real_estate_wealth business_wealth ///
	other_wealth {
		rename `var'_pre `var'2017
}
	
* Drop if all previous year assets are 0.
drop if financial_wealth2017 == "0" & real_estate_wealth2017 == "0" & business_wealth2017 == "0" & other_wealth2017 == "0"

rename municipio_name municipio_name_mode	

foreach var in financial_wealth real_estate_wealth business_wealth ///
	other_wealth {
		destring `var'2017, replace force
		replace `var'2017 = round(`var'2017)
}

egen temp = tag(municipio_name_mode ///
	financial_wealth2017 ///
	real_estate_wealth2017 ///
	business_wealth2017 ///
	other_wealth2017 )
	
tab temp
drop if temp == 0

*bro temp *2017 municipio_name_last filename2019

merge 1:1 municipio_name_mode ///
	financial_wealth2017 ///
	real_estate_wealth2017 ///
	business_wealth2017 ///
	other_wealth2017 using `MATCH17_1518'

