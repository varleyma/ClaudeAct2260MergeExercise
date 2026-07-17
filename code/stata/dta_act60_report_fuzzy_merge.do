
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

************************************
*********** 2015-2018 **************
************************************

import delim ///
	"$DataPath/temp/processed_FOIA/Act22AnnualReports2015-2018.csv", ///
	varn(1) clear
	
rename folder folder_year
	
gen filename_short = substr(filename,1,25)
drop if filename_short == "15-22-S-219-2016_Redacted" & ///
	type_of_charity == "REDACTED"

gen temp = subinstr(sworn_statement_city_and_country,", Puerto Rico","",.)
replace temp = subinstr(temp,", P.R.","",.)
replace temp = subinstr(temp,", P. R.","",.)
replace temp = subinstr(temp,"- P.R","",.)
replace temp = subinstr(temp," P.R.","",.)
replace temp = subinstr(temp,", P.R","",.)
replace temp = subinstr(temp," P.R","",.)
replace temp = subinstr(temp,", PR","",.)
replace temp = subinstr(temp," PR","",.)
replace temp = subinstr(temp," PR USA","",.)
replace temp = subinstr(temp," Puerto Rico USA","",.)
replace temp = subinstr(temp," Puerto Rico","",.)
replace temp = subinstr(temp,", PUERTO RICO","",.)
replace temp = subinstr(temp," PUERTO RICO","",.)
replace temp = subinstr(temp," Puerto Rico","",.)
replace temp = subinstr(temp,", USA","",.)
replace temp = subinstr(temp," USA","",.)
replace temp = subinstr(temp,", U.S.A.","",.)
replace temp = subinstr(temp,", U.S.A","",.)
replace temp = subinstr(temp,", United States","",.)
replace temp = subinstr(temp," -","",.)

gen municipio_name = temp

* Manual checks
replace municipio_name = "Añasco" if municipio_name == "ANASCO" ///
	| municipio_name == "Anasco"
replace municipio_name = "Arecibo" if municipio_name == "ARECIBO"
replace municipio_name = "Dorado" if municipio_name == "Aotealo"
replace municipio_name = "Humacao" if id == "12-22-S-009"
replace municipio_name = "Humacao" if municipio_name == "Almacao"
replace municipio_name = "San Juan" if ///
	municipio_name == "Austin Turks & Caicos"
replace municipio_name = county if ///
	municipio_name == "Austin, TX"
replace municipio_name = "Rio Grande" if municipio_name == "Bahia Beach"
replace municipio_name = "Humacao" if municipio_name == "Birmingham AL"
replace municipio_name = "San Juan" if ///
	municipio_name == "Brighton Township, MI"
replace municipio_name = "San Juan" if ///
	municipio_name == "Condado"
replace municipio_name = "San Juan" if ///
	municipio_name == "Cao CuraĂ§ao"
replace municipio_name = "Carolina" if municipio_name == "CAROLINA" | ///
	municipio_name == "Carolina, P R   U S A"
replace municipio_name = "Dorado" if ///
	municipio_name == "Captial L.A. U.S.A."
replace municipio_name = "Dorado" if ///
	municipio_name == "Caribe"
replace municipio_name = "Humacao" if municipio_name == "Cary McHenry, IL"
replace municipio_name = "Humacao" if municipio_name == "Chicago"
replace municipio_name = "Dorado" if municipio_name == "DORADO" | ///
	municipio_name == "Doado" | ///
	municipio_name == "Dorado 00646" | ///
	municipio_name == "Dorado Beach" | ///
	municipio_name == "Dorado Olio" | ///
	municipio_name == "Dorado, Dorado"
replace municipio_name = "Fajardo" if municipio_name == "Durango, CO"	
replace municipio_name = "Dorado" if municipio_name == "Durham"	
replace municipio_name = "Guaynabo" if municipio_name == "Guaynabo ." | ///
	municipio_name == "Guaynabo P R" | ///
	municipio_name == "Guaynabo, P. Rico (USA" | ///
	municipio_name == "GUAYNABO"	
replace municipio_name = "Dorado" if id=="16-22-S-036"
replace municipio_name = "Dorado" if id=="13-22-S-062"
replace municipio_name = "Rio Grande" if municipio_name == "Garden City, NY"
replace municipio_name = "Humacao" if id == "14-22-S-023" | ///
	id == "14-22-S-022"
replace municipio_name = "Humacao" if municipio_name == "HUMACAO" | ///
	municipio_name == "Humacao 00719" | ///
	municipio_name == "Humacao AZ" | ///
	municipio_name == "Humacao US" | ///
	municipio_name == "Humacao, US" | ///
	municipio_name == "Humaco" | ///
	municipio_name == "Humaco oro"
	
replace municipio_name = "Dorado" if id == "14-22-S-025"
replace municipio_name = "San Juan" if id == "16-22-S-153"
replace municipio_name = "San Juan" if id == "14-22-S-324"
replace municipio_name = "Humacao" if id == "15-22-S-265"
replace municipio_name = "Loiza" if municipio_name == "Loza"
replace municipio_name = "Moca" if municipio_name == "MOCA"
replace municipio_name = "San Juan" if id == "13-22-S-128"
replace municipio_name = "Guaynabo" if id == "14-22-S-151"
replace municipio_name = "San Juan" if id == "14-22-S-219"

replace municipio_name = "San Juan" if municipio_name == "NEW YORK, NY"
replace municipio_name = "San Juan" if id == "15-22-S-193"
replace municipio_name = "San Juan" if id == "14-22-S-039"
replace municipio_name = "Carolina" if id == "14-22-S-099"
replace municipio_name = "Dorado" if id == "14-22-S-130"
replace municipio_name = "Dorado" if id == "14-22-S-032"
replace municipio_name = "Dorado" if id == "14-22-S-055"

replace municipio_name = "Dorado" if id == "15-22-S-005"
replace municipio_name = "Humacao" if id == "15-22-S-011"
replace municipio_name = "Dorado" if id == "15-22-S-050"
replace municipio_name = "Añasco" if id == "15-22-S-233"
replace municipio_name = "Añasco" if id == "15-22-S-234"
replace municipio_name = "Guaynabo" if id == "16-22-S-057"
replace municipio_name = "NA" if id == "16-22-S-198"
replace municipio_name = "San Juan" if id == "14-22-S-286"
replace municipio_name = "San Juan" if id == "15-22-S-133"


replace municipio_name = "San Juan" if id == "14-22-S-321"
replace municipio_name = "San Juan" if id == "14-22-S-136"
replace municipio_name = "San Juan" if id == "14-22-S-137"
replace municipio_name = "San Juan" if id == "14-22-S-315"
replace municipio_name = "San Juan" if id == "14-22-S-316"
replace municipio_name = "Humacao" if municipio_name == "Palmas del Mar"

replace municipio_name = "Rio Grande" if municipio_name == "RIO GRANDE"
replace municipio_name = "Rincon" if municipio_name == "RincĂłn"

replace municipio_name = "San Juan" if municipio_name == "SAN JUAN"
replace municipio_name = "San Juan" if municipio_name == "San Jaun"
replace municipio_name = "San Juan" if municipio_name == "San Juan (USA"
replace municipio_name = "San Juan" if municipio_name == "San Juan US"
replace municipio_name = "San Juan" if municipio_name == "San Juan, San Juan"
replace municipio_name = "San Juan" if municipio_name == "Santurce San Turce"

replace municipio_name = "NA" if id == "15-22-S-356"
replace municipio_name = "Dorado" if id == "16-22-S-324"
replace municipio_name = "San Juan" if id == "14-22-S-067"
replace municipio_name = "NA" if id == "13-22-S-019"
replace municipio_name = "NA" if id == "17-22-S-131"
replace municipio_name = "Humacao" if id == "14-22-S-161"
replace municipio_name = "San Juan" if id == "13-22-S-108"
replace municipio_name = "Vega Alta" if id == "15-22-S-027"

* Redacted
replace municipio_name = "San Juan" if id == "13-22-S-023"
replace municipio_name = "San Juan" if id == "14-22-S-110"
replace municipio_name = "San Juan" if id == "15-22-S-063"
replace municipio_name = "Ponce" if id == "13-22-S-109"
replace municipio_name = "Rio Grande" if id == "15-22-S-155"
replace municipio_name = "Humacao" if id == "15-22-S-184"
replace municipio_name = "San Juan" if id == "14-22-S-037"
replace municipio_name = "Humacao" if id == "15-22-S-045"
replace municipio_name = "Humacao" if id == "14-22-S-300"
replace municipio_name = "San Juan" if id == "14-22-S-150"
replace municipio_name = "San Juan" if id == "16-22-S-159"
replace municipio_name = "San Juan" if id == "16-22-S-182"
replace municipio_name = "San Juan" if id == "14-22-S-001"
replace municipio_name = "San Juan" if id == "14-22-S-075"
replace municipio_name = "San Juan" if id == "14-22-S-337"
replace municipio_name = "San Juan" if id == "15-22-S-025"
replace municipio_name = "San Juan" if id == "15-22-S-026"
replace municipio_name = "Carolina" if id == "15-22-S-256"
replace municipio_name = "Dorado" if id == "16-22-S-179"
replace municipio_name = "Dorado" if id == "16-22-S-323"
replace municipio_name = "Dorado" if id == "16-22-S-107"


* NA
replace municipio_name = "Dorado" if id == "12-22-S-006"
replace municipio_name = "San Juan" if id == "13-22-S-054"
replace municipio_name = "Dorado" if id == "13-22-S-119"
replace municipio_name = "Dorado" if id == "13-22-S-132"
replace municipio_name = "Dorado" if id == "13-22-S-136"
replace municipio_name = "Dorado" if id == "14-22-S-141"
replace municipio_name = "Dorado" if id == "15-22-S-270"
replace municipio_name = "San Juan" if id == "14-22-S-081"
replace municipio_name = "San Juan" if id == "14-22-S-126"
replace municipio_name = "Guaynabo" if id == "14-22-S-271"

*don't know 
replace municipio_name = "NA" if municipio_name == "Austin" | ///
	municipio_name == "Buenos Aires, Argentina" | ///
	municipio_name == "Chico, California" | ///
	municipio_name == "Irving, Texas"
	
replace municipio_name = "Anasco" if municipio_name == "Añasco"

* Not many obs, and can't merge to newer data without municipio_name anyways
drop if municipio_name == "REDACTED" | municipio_name == "NA"

* Duplicate filenames (known because more than 4 obs per id)
drop if filename == "13-22-097_2016_Redacted.pdf"
drop if filename == "13-22-S-005-2013_Redacted.pdf"
gen filename_temp = substr(filename,1,13)
drop if filename_temp == "14-22-S-009-A"

rename total_net_worth total_net_worth
rename asset_type_financial_previous_re financial_wealth_pre
rename asset_type_real_estate_previous_ real_estate_wealth_pre
rename asset_type_privately_held_busine business_wealth_pre
rename asset_type_other_previous_report other_wealth_pre

rename asset_type_financial_current_rep financial_wealth
rename asset_type_real_estate_current_r real_estate_wealth
rename v40 business_wealth
rename asset_type_other_current_reporti other_wealth

rename asset_type_financial_difference financial_wealth_diff
rename asset_type_real_estate_differenc real_estate_wealth_diff
rename v41 business_wealth_diff
rename asset_type_other_difference other_wealth_diff

destring current_reporting_year previous_reporting_year, replace force
rename current_reporting_year year
rename previous_reporting_year previous_year

keep filename id previous_year year decree_year municipio_name  ///
	financial_wealth* real_estate_wealth* business_wealth* other_wealth*
	
order filename id decree_year municipio_name previous_year year ///
	financial_wealth* real_estate_wealth* business_wealth* other_wealth*
	
sort id year

* This starts by showing 32 duplicates. Will manually into their causes.
*	Can verify by running code up to the above and checking whether my
*		adjustments are correct.
egen id_year_tag = tag(id year)
tab id_year_tag 
egen min_id_year_tag = min(id_year_tag), by(id)
bro if min_id_year_tag == 0

// Seems report was redone, other 2015 entry lines up with other years.
drop if filename == "13-22-S-064_2015_Redacted.pdf" 
// Double report
drop if filename == "13-22-S-077_2017_Redacted.pdf" & year == 2013 
// Double report
drop if filename == "13-22-S-100_2016.pdf"  
// Seems that this was the report for 2014, not 2015. May need to come back
//	to make sure this one is right.
replace previous_year = 2013 if filename == "13-22-S-115_2015_Redacted.pdf"
replace year = 2014 if filename == "13-22-S-115_2015_Redacted.pdf"
// Seems one of 2015 reports is duplicate of 2016 report. 
drop if filename == "13-22-S-117_2016_Redacted.pdf" & year == 2015 
// Double report
drop if filename == "13-22-S-118_2017_Redacted.pdf" 
// Dropping 2017 redacted ones for now
drop if filename == "13-22-S-121_2017_Redacted.pdf"
// Double report
drop if filename == "13-22-S-135_2017_Redacted.pdf" 
// Double report, deferring to the one where financial wealth lines up
drop if filename == "13-22-S-146-2017_Redacted.pdf"
// Double report
drop if filename == "14-22-S-016_2017_Redacted.pdf" 
// Seems that this was the report for 2014, not 2015. May need to come back
//	to make sure this one is right.
replace previous_year = 2013 if filename == "14-22-S-022_2015_Redacted.pdf"
replace year = 2014 if filename == "14-22-S-022_2015_Redacted.pdf"
// Seems that this was the report for 2014, not 2015. May need to come back
//	to make sure this one is right.
replace previous_year = 2013 if filename == "14-22-S-023_2015_Redacted.pdf"
replace year = 2014 if filename == "14-22-S-023_2015_Redacted.pdf"
// Double report, might be reporting a second spot in Dorado
drop if filename == "14-22-S-058_2017_Redacted.pdf" 
// Double report
drop if filename == "14-22-S-105_2014_Redacted.pdf" 
// Double report, might be reporting a second spot in San Juan
drop if filename == "14-22-S-125_2015_Redacted.pdf" 
// Double report, might be reporting a second spot in Isabela
drop if filename == "14-22-S-170_2016_Redacted.pdf" 
// Double report, fixing a mistake in financial wealth
drop if filename == "14-22-S-191_2015.pdf" & ///
	financial_wealth_diff == "63659787"
// Seems that this was the report for 2014, not 2015. May need to come back
//	to make sure this one is right.
replace previous_year = 2013 if filename == "14-22-S-203_2016_Redacted.pdf"
replace year = 2014 if filename == "14-22-S-203_2016_Redacted.pdf"
// Seems that this was the report for 2014, not 2015. May need to come back
//	to make sure this one is right.
replace previous_year = 2013 if filename == "14-22-S-214_2016_Redacted.pdf"
replace year = 2014 if filename == "14-22-S-214_2016_Redacted.pdf"
// Double report
drop if filename == "14-22-S-219-2016_Redacted.pdf" 
// Seems that this was the report for 2014, not 2015. May need to come back
//	to make sure this one is right.
replace previous_year = 2013 if filename == "14-22-S-220_2016_Redacted.pdf"
replace year = 2014 if filename == "14-22-S-220_2016_Redacted.pdf"
// Double report
drop if filename == "14-22-S-243_2016_Redacted.pdf"
drop if filename == "14-22-S-243-2017_Redacted.pdf" 
// Double report
drop if filename == "14-22-S-276_2015_Redacted.pdf"
// Seems that this was the report for 2016, not 2017. May need to come back
//	to make sure this one is right.
replace previous_year = 2015 if filename == "15-22-S-019_216_Redacted.pdf"
replace year = 2016 if filename == "15-22-S-019_216_Redacted.pdf"
// Double report, dropping the one with inconsistent muni (Dorado)
drop if filename == "15-22-S-064_2015_Redacted.pdf"
// Double report
drop if filename == "15-22-S-089_2016_Redacted.pdf"
// Double report
drop if filename == "15-22-S-11_2016_Redacted.pdf" & id == "15-22-S-111"
// Double report, drop one with mistake in financial wealth
drop if filename == "15-22-S-146_2016_Redacted.pdf" & ///
	financial_wealth == "170000"
// Double report, drop one with mistake in business wealth
drop if filename == "15-22-S-195-2015_Redacted.pdf" & ///
	business_wealth == "750000"
// Double report, dropping one with inconsistent filename format to others
drop if filename == "15-22-S-291_2016_Redacted.pdf"
// Double report, drop the earlier submitted one
drop if filename == "16-22-S-207_2016_Redacted.pdf"
	
drop id_year_tag min_id_year_tag

egen id_year_tag = tag(id year)
tab id_year_tag 
egen min_id_year_tag = min(id_year_tag), by(id)
bro if min_id_year_tag == 0
drop id_year_tag min_id_year_tag


* Once panel is unique, reshape to get merging variables	
drop *pre *diff
drop previous_year
drop filename 

* Sometimes muni changes. Could be a move or misreporting. Will keep most
* common muni in panel and last muni name to see what works better for
* matching to other samples.
egen municipio_name_mode = mode(municipio_name), by(id)
egen municipio_name_last = lastnm(municipio_name), by(id)

* If not a unique mode, use last reported
replace municipio_name_mode = municipio_name_last if municipio_name_mode == ""
drop municipio_name

reshape wide *_wealth, i(id) j(year)	
	
save "$CleanDataPath/merge_practice_2015_2018_folder.dta", replace

// egen person_group = group(municipio_name ///
// 	financial_wealth ///
// 	real_estate_wealth business_wealth other_wealth)
// sort person_group
// egen person_tag = tag(municipio_name ///
// 	financial_wealth ///
// 	real_estate_wealth business_wealth other_wealth)
// tab person_tag
// egen person_year_tag = tag(person_group current_reporting_year)
// tab person_year_tag
// keep if person_year_tag==1

*******************************
*********** 2019 **************
*******************************

import delim "$DataPath/temp/processed_FOIA/Act22AnnualReports2019.csv", ///
	varn(1) clear
	
gen filename_short = substr(filename,1,20)
li filename_short if _n<5
egen temp = tag(filename_short)
keep if temp == 1
drop temp

gen municipio_name = county

drop if municipio_name == "26"
drop if municipio_name == "HILLSBOROUGH"
drop if municipio_name == "Las Vegas"
drop if municipio_name == "Loganville"

* Manual checks
replace municipio_name = "Adjuntas" if county == "Adjuntas,Adjuntas"
replace municipio_name = "Añasco" if county == "AĂąasco"
replace municipio_name = "Añasco" if county == "Aiasco"
replace municipio_name = "Añasco" if county == "Afiasco"
replace municipio_name = "Anasco" if municipio_name == "Añasco"
replace municipio_name = "Bayamon" if county == "BayamĂłn"
replace municipio_name = "Bayamon" if municipio_name == "Bayamón"
replace municipio_name = "Dorado" if county == "DORADO"
replace municipio_name = "San Juan" if county == "DALLAS"
replace municipio_name = "Guaynabo" if county == "Key Largo"
replace municipio_name = "Mayaguez" if county == "MayagĂźez"
replace municipio_name = "San Juan" if county == "Newbury Park"
replace municipio_name = "Carolina" if ///
	filename == "2020-RepAct22-001283_Redacted.pdf"
replace municipio_name = "Humacao" if county == "Redondo Beach"
replace municipio_name = "Rincon" if county == "RincĂłn"
replace municipio_name = "Carolina" if county == "Queens" 
replace municipio_name = "San Juan" if county == "Austin" 
replace municipio_name = "Humacao" if county == "CARY" 
replace municipio_name = "Dorado" if county == "CHICAGO" 
replace municipio_name = "Dorado" if county == "Dorado,Dorado" 
replace municipio_name = "Dorado" if county == "FALLBROOK" 
replace municipio_name = "San Juan" if county == "IRON STATION"
replace municipio_name = "San Juan" if county == "Miami" 
replace municipio_name = "Rincon" if county == "Rincón" 
replace municipio_name = "Rincon" if municipio_name == "Rincón" 
replace municipio_name = "Rio Grande" if county == "Río Grande" 
replace municipio_name = "Rio Grande" if county == "RĂ­o Grande" 
replace municipio_name = "San Juan" if county == "SANJUAN" 
replace municipio_name = "San Juan" if county == "SAN JUAN" 
replace municipio_name = "San Juan" if county == "Sen Juan" 
replace municipio_name = "Carolina" if county == "WESTON" 
replace municipio_name = "Humacao" if county == "Urbandale" 
replace municipio_name = "San Germán" if county == "San GermĂĄn" 
replace municipio_name = "San German" if municipio_name == "San Germán" 

drop if municipio_name == "REDACTED"

rename total_net_worth total_net_worth
rename asset_type_financial_previous_re financial_wealth_pre
rename asset_type_real_estate_previous_ real_estate_wealth_pre
rename asset_type_privately_held_busine business_wealth_pre
rename asset_type_other_previous_report other_wealth_pre

rename asset_type_financial_current_rep financial_wealth
rename asset_type_real_estate_current_r real_estate_wealth
rename v41 business_wealth
rename asset_type_other_current_reporti other_wealth

rename asset_type_financial_difference financial_wealth_diff
rename asset_type_real_estate_differenc real_estate_wealth_diff
rename v42 business_wealth_diff
rename asset_type_other_difference other_wealth_diff

destring current_reporting_year previous_reporting_year, replace force
rename current_reporting_year year
rename previous_reporting_year previous_year

keep filename previous_year year municipio_name  ///
	financial_wealth* real_estate_wealth* business_wealth* other_wealth*
	
order filename municipio_name previous_year year ///
	financial_wealth* real_estate_wealth* business_wealth* other_wealth*

rename filename filename2019

// egen person_group = group(municipio_name ///
// 	financial_wealth2019 ///
// 	real_estate_wealth2019 business_wealth2019 other_wealth2019)
// sort person_group
// egen person_tag = tag(municipio_name ///
// 	financial_wealth2019 ///
// 	real_estate_wealth2019 business_wealth2019 other_wealth2019)
// tab person_tag
// keep if person_tag==1

save "$CleanDataPath/merge_practice_2019.dta", replace

*******************************
*********** 2020 **************
*******************************

import delim "$DataPath/temp/processed_FOIA/Act22AnnualReports2021.csv", ///
	varn(1) clear
	
gen filename_short = substr(filename,1,20)
li filename_short if _n<5
egen temp = tag(filename_short)
keep if temp == 1
drop temp

gen municipio_name = county

drop if municipio_name == "26"
drop if municipio_name == "HILLSBOROUGH"
drop if municipio_name == "Las Vegas"
drop if municipio_name == "Loganville"

* Manual checks
replace municipio_name = "Adjuntas" if county == "Adjuntas,Adjuntas"
replace municipio_name = "Añasco" if county == "AĂąasco"
replace municipio_name = "Añasco" if county == "Aiasco"
replace municipio_name = "Añasco" if county == "Afiasco"
replace municipio_name = "Bayamón" if county == "BayamĂłn"
replace municipio_name = "Dorado" if county == "DORADO"
replace municipio_name = "San Juan" if county == "DALLAS"
replace municipio_name = "Guaynabo" if county == "Key Largo"
replace municipio_name = "Mayaguez" if county == "MayagĂźez"
replace municipio_name = "San Juan" if county == "Newbury Park"
replace municipio_name = "Carolina" if ///
	filename == "2020-RepAct22-001283_Redacted.pdf"
replace municipio_name = "Humacao" if county == "Redondo Beach"
replace municipio_name = "Rincón" if county == "RincĂłn"
replace municipio_name = "Carolina" if county == "Queens" 
replace municipio_name = "San Juan" if county == "Austin" 
replace municipio_name = "Humacao" if county == "CARY" 
replace municipio_name = "Dorado" if county == "CHICAGO" 
replace municipio_name = "Dorado" if county == "Dorado,Dorado" 
replace municipio_name = "Dorado" if county == "FALLBROOK" 
replace municipio_name = "San Juan" if county == "IRON STATION"
replace municipio_name = "San Juan" if county == "Miami" 
replace municipio_name = "Rincón" if county == "Rincon" 
replace municipio_name = "Rio Grande" if county == "Río Grande" 
replace municipio_name = "Rio Grande" if county == "RĂ­o Grande" 
replace municipio_name = "San Juan" if county == "SANJUAN" 
replace municipio_name = "San Juan" if county == "SAN JUAN" 
replace municipio_name = "San Juan" if county == "Sen Juan" 
replace municipio_name = "Carolina" if county == "WESTON" 
replace municipio_name = "Humacao" if county == "Urbandale" 
replace municipio_name = "San Germán" if county == "San GermĂĄn" 

drop if municipio_name == "REDACTED"
	
rename total_net_worth total_net_worth2019
rename asset_type_financial_previous_re financial_wealth2019
rename asset_type_real_estate_previous_ real_estate_wealth2019
rename asset_type_privately_held_busine business_wealth2019
rename asset_type_other_previous_report other_wealth2019

rename filename filename2020

egen person_group = group(municipio_name ///
	financial_wealth2019 ///
	real_estate_wealth2019 business_wealth2019 other_wealth2019)
sort person_group
egen person_tag = tag(municipio_name ///
	financial_wealth2019 ///
	real_estate_wealth2019 business_wealth2019 other_wealth2019)
tab person_tag
keep if person_tag==1

keep filename2020 municipio_name financial_wealth2019 ///
	real_estate_wealth2019 business_wealth2019 other_wealth2019

	
save "$CleanDataPath/merge_practice_2020.dta", replace
	
************************************
*********** 2022-2023 **************
************************************

import delim ///
	"$DataPath/temp/processed_FOIA/Act22AnnualReports2022_format22.csv", ///
	varn(1) clear
	
import delim ///
	"$DataPath/temp/processed_FOIA/Act22AnnualReports2023.csv", ///
	varn(1) clear
	
* Merge
use "$CleanDataPath/merge_practice_2019.dta", clear

merge 1:1 municipio_name financial_wealth2019 ///
	real_estate_wealth2019 business_wealth2019 other_wealth2019 using ///
	"$CleanDataPath/merge_practice_2020.dta"

	
sort municipio_name financial_wealth2019 ///
	real_estate_wealth2019 business_wealth2019 other_wealth2019