** Description: HIV-TB and HIV-other calculations
** Step (1): run a mixed effects regression to predict proportions of HIV-TB among all TB cases
** Step (2): calculate PAF using the predicted proportions above and global RR
** Step (3): generate HIV death age pattern
** Step (4): calculate hivtb deaths based on high quality VR data and proportions of HIV positive TB cases
** Step (5): capping hivtb deaths if hivtb/hiv>45%
** Step (6): upload results

// Settings
			// Clear memory and set memory and variable limits
				clear all
				set mem 5G
				set maxvar 32000

			// Set to run all selected code without pausing
				set more off

			// Set graph output color scheme
				set scheme s1color

			// Define J drive (data) for cluster (UNIX) and Windows (Windows)
				if c(os) == "Unix" {
					global prefix "/home/j"
					set odbcmgr unixodbc
				}
				else if c(os) == "Windows" {
					global prefix "J:"
				}
			
			// Close any open log file
				cap log close
				
			// local

				

** *************************************************************************************************************************************************
// locals
local acause hiv_tb
local custom_version v24

// Make folders on cluster
capture mkdir "/ihme/codem/data/`acause'/`custom_version'"
capture mkdir "/ihme/codem/data/hiv_other/`custom_version'"

// define filepaths
	cap mkdir "$prefix/WORK/04_epi/01_database/02_data/`acause'/GBD2015//`custom_version'/"
	cap mkdir "$prefix/WORK/04_epi/01_database/02_data/`acause'/GBD2015//`custom_version'/results"
	
	local outdir "$prefix/WORK/04_epi/01_database/02_data//`acause'/GBD2015//`custom_version'/"
	local indir "$prefix/WORK/04_epi/01_database/02_data//`acause'/GBD2015/data"
	local tempdir "$prefix/WORK/04_epi/01_database/02_data/hiv_tb/GBD2015/temp"
	
** **************************************************************************************************************************************************
** Step (1): run a mixed effects regression to predict proportions of HIV-TB among all TB cases
** **************************************************************************************************************************************************

// get direct coded HIV-TB before redistribution

		use "`indir'/hivtb_prop_all.dta", clear 
		gen year_mean=(year_start+year_end)/2	 
        gen year=round(year_mean, 1)
		keep location_id year mean cases sample_size
		
		preserve
		keep if location_id==44539 | location_id==44540
		collapse (sum) cases sample_size, by (location_id year)
		gen mean=cases/sample_size
		tempfile six_minor_ter
		save `six_minor_ter', replace
		restore
		
		drop if location_id==44539 | location_id==44540
		append using `six_minor_ter'
		
		rename mean raw_prop
		drop cases sample_size
		
		// drop outliers
		drop if location_id==196 & (year==2002 | year==2003)
		drop if location_id==130 & (year==2006 | year==2007)
		drop if inlist(location_id,43882,43884,43885,43886,43895,43888,43894,43895,43903,43918,43920,43922,43924,43926,43931) & year==2008
		drop if inlist(location_id,43894,43903,43911,43930,43921,43939) & year==2009
		drop if location_id==6 & year==2006
		drop if location_id==11
		tempfile prop
		save `prop', replace		
	

      // get iso3
	  
	  use "`tempdir'/iso3.dta", clear
	  replace location_name="USA Georgia" if location_id==533
	  replace location_name="MEX Distrito Federal" if location_id==4651
	  duplicates drop location_name, force
	  tempfile iso3
	  save `iso3', replace
	  
      // get population
	  
		clear all
		adopath + "$prefix/Project/Mortality/shared/functions"
		get_env_results
		tempfile pop_all
		save `pop_all', replace
		
		keep if age_group_id==22
        tempfile pop
		save `pop', replace
		
	 // get the covariate
	 
		clear all
		adopath + "$prefix/WORK/10_gbd/00_library/functions"
		get_covariate_estimates, covariate_name_short(adult_hiv_death_rate)
		save "`indir'/adult_hiv_death_rate.dta", replace

        duplicates drop 
	  // merge on pop data
	  merge m:1 location_id year_id age_group_id sex using `pop', keepusing(mean_pop) keep(3)nogen
	  merge m:1 location_id using `iso3', keepusing(iso3) keep(3)nogen
	  rename mean_value rate
	  gen deaths=rate*mean_pop
	  collapse (sum) deaths mean_pop, by (location_id location_name year_id) fast
	  
	  preserve
	  merge m:1 location_id using "`tempdir'/location_id_parent.dta", keep(3)nogen
	  keep if parent=="Brazil" | parent=="China" | parent=="India" | parent=="Japan" | parent=="Kenya" | parent=="Mexico" | parent=="Saudi Arabia" | parent=="Sweden" | parent=="United Kingdom" | parent=="United States" | parent=="South Africa"
      collapse (sum) deaths mean_pop, by (parent year_id) fast
	  rename parent location_name
	  merge m:1 location_name using `iso3', keep(3)nogen
	  tempfile sub_collapse
	  save `sub_collapse', replace
	  
	  restore
	  append using `sub_collapse'
	  
	  gen rate=deaths/mean_pop
	  gen ln_rate=ln(rate)
	
	  gen year=year_id
		merge 1:m location_id year using `prop', keepusing(raw_prop) nogen 
		merge m:1 location_id using "`tempdir'/sr_all.dta", keep(3)nogen
		
		gen logit_prop_tbhiv=logit(raw_prop)
		
		drop iso3
		merge m:1 location_id using "`tempdir'/iso3.dta", keepusing(iso3) keep(3)nogen
		
		tempfile tmp_reg_dta
	    save `tmp_reg_dta', replace
        save "`outdir'/tmp_reg_dta", replace
		
** *****************************
// Predict Fraction TB-HIV in TB
** *****************************

		use `tmp_reg_dta', clear
		drop if year<1980	
		log using "`outdir'/hivtb_prop_log_`custom_version'.smcl", replace
	
		//  regression 
			xtmixed logit_prop_tbhiv ln_rate || location_id: 
		
	    cap log close 		
		** store location_id

		/*
			preserve
				predict u_location_id, reffects
				keep location_id u*
				duplicates drop 
				outsheet using "`outdir'\Country_RE_HIVTB_prop_reg.csv", delim(",") replace 
			restore
		*/
	
	preserve
		predict iso_RE, reffects
		predict iso_RE_se, reses
		collapse (mean) iso_RE iso_RE_se, by(iso3 super_region)
		tempfile iso_RE
		save `iso_RE', replace
		
		restore
		merge m:1 iso3 using `iso_RE', nogen
		tempfile all
		save `all', replace 
		
				
		use `iso_RE', clear
		preserve
		keep if iso3=="CHN"
		local iso_RE_CHN=iso_RE
		local iso_RE_se_CHN=iso_RE_se
		restore
		
		preserve
		keep if iso3=="MEX"
		local iso_RE_MEX=iso_RE
		local iso_RE_se_MEX=iso_RE_se
		restore
		
		preserve
		keep if iso3=="GBR"
		local iso_RE_GBR=iso_RE
		local iso_RE_se_GBR=iso_RE_se
		restore
		
		preserve
		keep if iso3=="USA"
		local iso_RE_USA=iso_RE
		local iso_RE_se_USA=iso_RE_se
		restore
		
		preserve
		keep if iso3=="BRA"
		local iso_RE_BRA=iso_RE
		local iso_RE_se_BRA=iso_RE_se
		restore
		/*
		preserve
		keep if iso3=="IND"
		local iso_RE_IND=iso_RE
		local iso_RE_se_IND=iso_RE_se
		restore
		*/
		preserve
		keep if iso3=="KEN"
		local iso_RE_KEN=iso_RE
		local iso_RE_se_KEN=iso_RE_se
		restore
		
		
		preserve
		keep if iso3=="JPN"
		local iso_RE_JPN=iso_RE
		local iso_RE_se_JPN=iso_RE_se
		restore
		
	
	    preserve
		keep if iso3=="SWE"
		local iso_RE_SWE=iso_RE
		local iso_RE_se_SWE=iso_RE_se
		restore
		
		preserve
		keep if iso3=="ZAF"
		local iso_RE_ZAF=iso_RE
		local iso_RE_se_ZAF=iso_RE_se
		restore
		
		
		preserve
		keep if iso3=="SAU"
		local iso_RE_SAU=iso_RE
		local iso_RE_se_SAU=iso_RE_se
		restore
		
    use `all', clear
    
	/* merge m:1 super_region using `super_RE', nogen	*/
		
	// missing subnational random effects and SEs are replaced with country random effects and SEs
	replace iso_RE=`iso_RE_CHN' if regexm(iso3,"CHN_")
	replace iso_RE_se=`iso_RE_se_CHN' if regexm(iso3,"CHN_")
	/* replace iso_RE=`iso_RE_IND' if regexm(iso3,"IND_")
	replace iso_RE_se=`iso_RE_se_IND' if regexm(iso3,"IND_") */
	replace iso_RE=`iso_RE_GBR' if regexm(iso3,"GBR_")
	replace iso_RE_se=`iso_RE_se_GBR' if regexm(iso3,"GBR_")
	replace iso_RE=`iso_RE_MEX' if regexm(iso3,"MEX_")
	replace iso_RE_se=`iso_RE_se_MEX' if regexm(iso3,"MEX_")
	replace iso_RE=`iso_RE_USA' if regexm(iso3,"USA_")
	replace iso_RE_se=`iso_RE_se_USA' if regexm(iso3,"USA_")
	replace iso_RE=`iso_RE_BRA' if regexm(iso3,"BRA_")
	replace iso_RE_se=`iso_RE_se_BRA' if regexm(iso3,"BRA_")
	replace iso_RE=`iso_RE_KEN' if regexm(iso3,"KEN_")
	replace iso_RE_se=`iso_RE_se_KEN' if regexm(iso3,"KEN_")
	replace iso_RE=`iso_RE_JPN' if regexm(iso3,"JPN_")
	replace iso_RE_se=`iso_RE_se_JPN' if regexm(iso3,"JPN_")
	replace iso_RE=`iso_RE_SWE' if regexm(iso3,"SWE_")
	replace iso_RE_se=`iso_RE_se_SWE' if regexm(iso3,"SWE_")
	replace iso_RE=`iso_RE_ZAF' if regexm(iso3,"ZAF_")
	replace iso_RE_se=`iso_RE_se_ZAF' if regexm(iso3,"ZAF_")
	replace iso_RE=`iso_RE_SAU' if regexm(iso3,"SAU_")
	replace iso_RE_se=`iso_RE_se_SAU' if regexm(iso3,"SAU_")
	

	// missing country random effects are replaced with the average random effect at the global level (i.e., 0)
	replace iso_RE=0 if iso_RE==.
	// countries with missing standard errors are replaced with global standard deviation of the country random effects
	// run _diparm  to get global sd of random effects /* need to use lns1_1_1. xtmixed estimates the ln_sigma, the inverse function is exp(). The derivative of exp() is just exp() */
	_diparm lns1_1_1, f(exp(@)) d(exp(@))
	gen global_sd=`r(est)'
	
	replace iso_RE_se = global_sd if missing(iso_RE_se)
	
		// create draws from the covariance matrix to get parameter uncertainty
		
			matrix m = e(b)'
			matrix m = m[1..(rowsof(m)-2),1]
			local covars: rownames m
			local num_covars: word count `covars'
			local betas
			forvalues j = 1/`num_covars' {
				local this_covar: word `j' of `covars'
				local betas `betas' b_`this_covar'
			}
			matrix C = e(V)
			matrix C = C[1..(colsof(C)-2), 1..(rowsof(C)-2)]
			drawnorm `betas', means(m) cov(C)
			** just save 1,000 betas... 
			preserve
				qui keep b*
				qui drop if _n>1000
				qui gen id=_n
				qui tempfile tmp_betas
				save `tmp_betas', replace 
			restore
			qui drop b_*
			** drop duplicates
			qui duplicates drop
			qui gen id=_n
			merge 1:1 id using "`tmp_betas'", nogen 
			drop id
	
			
		// Generate 1000 estimates - predict without RE
			forvalues j = 1/1000 {
				di in red "Generating Draw `j'"
				 qui gen prop_tbhiv_xb_d`j'=ln_rate*b_ln_rate[`j']+b__cons[`j']+rnormal(iso_RE, iso_RE_se)
				** qui gen prop_tbhiv_xb_d`j'=sex_2*b_sex_2[`j']+ln_tb_dth_rt*b_ln_tb_dth_rt[`j']+b__cons[`j']
				qui replace prop_tbhiv_xb_d`j'=invlogit(prop_tbhiv_xb_d`j')
			}
			
		** drop duplicates
			duplicates drop 
		tempfile tmp_prop_xb
		save `tmp_prop_xb', replace 
		
     // calculate mean, upper, and lower
     egen mean_prop=rowmean(prop_tbhiv*)
	 egen lower_prop=rowpctile(prop_tbhiv*), p(2.5)
	 egen upper_prop=rowpctile(prop_tbhiv*), p(97.5)
	 drop prop_tbhiv*

     save "`outdir'/Prop_tbhiv_mean_ui_`custom_version'.dta", replace
	 
** *****************************
// Graph predictions... prop tbhiv/tb
** *****************************
// Initialize pdfmaker

	set scheme s1color
	set printcolor asis
	capture confirm file "C:/Program Files (x86)/Adobe/Acrobat 9.0/Acrobat/acrodist.exe"
	if _rc == 0 {
		do "$prefix/Usable/Tools/ADO/pdfmaker.do"
	}
	else {
		do "$prefix/Usable/Tools/ADO/pdfmaker_Acrobat11.do"
	}
	
	
	use "`outdir'/Prop_tbhiv_mean_ui_`custom_version'.dta", clear
	duplicates drop location_id year, force
	tempfile prop
	save `prop', replace
	
	use "`outdir'/tmp_reg_dta", clear
	duplicates drop location_id year, force
	tempfile reg
	save `reg', replace
	
	    use `prop', clear
		merge m:1 location_id year using `reg', nogen 
		merge m:1 location_id using "`tempdir'/iso3.dta", keepusing(iso3) keep(3)nogen
		gen pred_prop=mean_prop
		gen pred_prop_lower=lower_prop
		gen pred_prop_upper=upper_prop
		drop if year<1980	
		drop if (location_id>=4841 & location_id<=4875) | location_id==44538
		
		pdfstart using "`outdir'/Prop_tbhiv_scatter_`custom_version'.pdf"
			sort iso3 year
			levelsof iso3 , local(isos)
			foreach i of local isos {
					scatter pred_prop year if iso3=="`i'" || scatter raw_prop year if iso3=="`i'", title("`i'")    ///
					legend(order(1 "Predicted proportions" 2 "Raw proportions") col(2))
					pdfappend
			}
		pdffinish
		
** ********************************************************************************************************************************************************	
** Step (2): calculate PAF using the predicted proportions above and global RR
** ********************************************************************************************************************************************************	
				 
insheet using "`indir'/hiv_tb_icd10.csv", comma names clear

preserve
keep if acause=="hiv_tb"
drop if deaths==0 | deaths==.
rename deaths deaths_hivtb
keep iso3 year deaths_hivtb
tempfile hivtb
save `hivtb', replace
restore

keep if acause=="tb"
drop if deaths==0 | deaths==.
collapse (sum) deaths, by (acause iso3 year) 
rename deaths deaths_tb
keep iso3 year deaths_tb
tempfile tb
save `tb', replace

import excel using "`indir'/high_quality_countries.xlsx", firstrow clear
tempfile high_qual
save `high_qual', replace

use "`outdir'/Prop_tbhiv_mean_ui_`custom_version'.dta", clear
keep iso3 year mean_prop raw_prop
tempfile prop
save `prop', replace

use `hivtb', clear
merge 1:1 iso3 year using `tb', keep(3) nogen
merge 1:1 iso3 year using `high_qual', keep(3)nogen
keep if high_quality==1

// drop if the number of hivtb deaths is 10 or less
drop if deaths_hivtb <=10

// drop Russia as suggested by Chris
drop if iso3=="RUS"
gen frac=deaths_hivtb/(deaths_tb+deaths_hivtb)
drop if frac>1
merge 1:1 iso3 year using `prop', keep (3) nogen

gen RR=((frac*mean_prop)-frac)/((frac*mean_prop)-mean_prop)

gen RR_2=((frac*raw_prop)-frac)/((frac*raw_prop)-raw_prop)

save "`outdir'/RR_updated_all_`custom_version'.dta", replace

// drop if RR less than 1
drop if RR<1 & RR !=.

// generate locals for mean and median RRs
sum RR, detail

gen RR_mean=`r(mean)'

gen RR_median=`r(p50)'


save "`outdir'/global_RR_updated_`custom_version'.dta", replace

//

use `prop', clear

gen RR_mean=`r(mean)'

gen RR_median=`r(p50)'

gen PAR_based_on_mean_RR=(mean_prop*`r(mean)')/((mean_prop*`r(mean)')+(1-mean_prop))

gen PAR_based_on_median_RR=(mean_prop*`r(p50)')/((mean_prop*`r(p50)')+(1-mean_prop))

sort iso3 year

outsheet using "`outdir'/predicted_PAR_`custom_version'.csv", comma names replace

** ****************************************************************************************************************************************************
** Step (3): generate HIV death age pattern
** ****************************************************************************************************************************************************

clear all
adopath + /home/j/WORK/10_gbd/00_library/functions
get_estimates, gbd_team(cod) model_version_id(76997) 
tempfile male
save `male', replace

clear all
adopath + /home/j/WORK/10_gbd/00_library/functions
get_estimates, gbd_team(cod) model_version_id(77000)
tempfile female
save `female', replace


use `male', clear
append using `female'

save "`indir'/hiv_deaths_76997_77000.dta", replace

/*
// prep

keep if location_id==1
*/

// drop aggregate locations

keep location_id year_id sex_id age_group_id mean_death_rate

rename mean_death_rate hiv_death_rate

drop if age_group_id<4 | age_group_id>21

save "`indir'/hiv_death_rate_age_pattern.dta", replace

** ****************************************************************************************************************************************************
** Step (4): calculate hivtb deaths based on high quality VR data and proportions of HIV positive TB cases
** ****************************************************************************************************************************************************

// run ado file for fast collapse

adopath+ "$prefix/WORK/10_gbd/00_library/functions"


insheet using "`outdir'/predicted_PAR_`custom_version'.csv", comma names clear
//merge on location_id
merge m:1 iso3 using "`tempdir'/iso3.dta", keepusing(location_id) keep(3)nogen
rename year year_id
tempfile frac
save `frac', replace


** *****************************
// Generate TB-HIV death numbers
** *****************************
use /ihme/gbd/WORK/04_epi/01_database/02_data/tb/temp/tb_codem_draws_75173_75176, clear
duplicates drop location_id year_id age_group_id sex_id, force
// collapse draws
// collapse(sum) draw_*, by (location_id year_id)
fastcollapse draw_*, type(sum) by(location_id year_id) 

** merge on the fraction data
merge 1:1 location_id year_id using `frac', keepusing(par_based_on_median_rr) keep(3)nogen
		
	** loop through draws and adjust them... 
		forvalues i=0/999 {
			di in red "draw `i'"
			replace draw_`i'=0 if draw_`i'==.
			gen tbhiv_d`i'=(par_based_on_median_rr/(1-par_based_on_median_rr))*draw_`i'
			drop draw_`i' 
			replace tbhiv_d`i'=0 if tbhiv_d`i'==.
		}
tempfile hivtb
save `hivtb', replace
		
save /ihme/gbd/WORK/04_epi/01_database/02_data/tb/temp/HIVTB_mortality_draws_`custom_version'.dta, replace

/*
// generate mean, upper, and lower 

egen mean_tbhiv=rowmean(tbhiv_d*)
egen lower_tbhiv=rowpctile(tbhiv_d*), p(2.5)
egen upper_tbhiv=rowpctile(tbhiv_d*), p(97.5)
drop tbhiv_d*
				
save "$prefix/WORK/04_epi/01_database/02_data//`acause'/GBD2015//`custom_version'/HIVTB_mortality_mean_UI.dta", replace 
*/


// prep pop
use `pop_all', clear
drop if year_id<1980
drop if location_id==1
keep if age_group_id>=4 & age_group_id<=21
drop if sex_id==3
tempfile tmp_pop
save `tmp_pop', replace

// get hiv deaths age pattern

use "$prefix/WORK/04_epi/01_database/02_data//`acause'/GBD2015/data/hiv_death_rate_age_pattern.dta", clear
tempfile age_pattern
save `age_pattern', replace

// prep for age split

use /ihme/gbd/WORK/04_epi/01_database/02_data/tb/temp/HIVTB_mortality_draws_`custom_version'.dta, clear
merge 1:m location_id year_id using `tmp_pop', keep(1 3) nogen
merge m:1 location_id year_id age_group_id sex_id using `age_pattern', keep(3)nogen

rename mean_pop sub_pop
gen rate_sub_pop=hiv_death_rate*sub_pop

preserve
collapse (sum) rate_sub_pop, by(location_id year_id) fast
rename rate_sub_pop sum_rate_sub_pop
tempfile sum
save `sum', replace

restore
merge m:1 location_id year_id using `sum', keep(3)nogen

forvalues i=0/999 {
			di in red "draw `i'"
			gen draw_`i'=rate_sub_pop*(tbhiv_d`i'/sum_rate_sub_pop)
			drop tbhiv_d`i' 
		}

keep location_id year_id age_group_id sex_id draw_*
tempfile hivtb_cyas
save `hivtb_cyas', replace
save /ihme/gbd/WORK/04_epi/01_database/02_data/tb/temp/HIVTB_cyas_`custom_version'.dta, replace

** *****************************************************************************************************************************************
** Step (5): capping hivtb deaths if hivtb/hiv>45%
** *****************************************************************************************************************************************

// rename hiv death draws
use /ihme/gbd/WORK/04_epi/01_database/02_data/tb/temp/hiv_draws_76997_77000.dta, clear
duplicates drop location_id year_id age_group_id sex_id, force
// rename draws
forvalues i = 0/999 {
			  rename draw_`i' hiv_`i'
			}
tempfile hiv
save `hiv', replace

// rename hivtb death draws
use /ihme/gbd/WORK/04_epi/01_database/02_data/tb/temp/HIVTB_cyas_`custom_version'.dta, clear
duplicates drop location_id year_id age_group_id sex_id, force
/*
// rename draws
forvalues i = 0/999 {
			  rename draw_`i' hivtb_`i'
			}
*/
tempfile hivtb
save `hivtb', replace

// merge the files
			use `hiv', clear
			merge 1:1 location_id year_id age_group_id sex using `hivtb', keep(3) nogen 

// loop through draws and adjust them... 
		forvalues i=0/999 {
			gen frac_`i'=draw_`i'/hiv_`i'
			replace draw_`i'=hiv_`i'*0.45 if frac_`i'>0.45
			replace draw_`i'=0 if draw_`i'==.
			}
drop hiv_* frac_*
tempfile hivtb_capped
save `hivtb_capped', replace

replace cause_id=299		
outsheet using /ihme/codem/data/`acause'/`custom_version'/hivtb_capped_`custom_version'.csv, comma names replace 

// calculate hiv_other

use `hiv', clear
merge 1:1 location_id year_id age_group_id sex using `hivtb_capped', keep(3) nogen
// loop through draws and subtract hiv_tb from hiv 
		forvalues i=0/999 {
			replace draw_`i'=hiv_`i'-draw_`i'
			}
replace cause_id=300		
outsheet using /ihme/codem/data/hiv_other/`custom_version'/hiv_other_`custom_version'.csv, comma names replace 


** *********************************************************************************************************************************************************
** Step (6): upload results
** *********************************************************************************************************************************************************

// save results for hiv_tb

do /home/j/WORK/10_gbd/00_library/functions/save_results.do
save_results, cause_id(299) description(`acause' custom `custom_version', capped at hivtb/hiv 45 percent) mark_best(yes) in_dir(/ihme/codem/data/`acause'/`custom_version') model_version_type_id(6)


// save results for hiv_other

do /home/j/WORK/10_gbd/00_library/functions/save_results.do
save_results, cause_id(300) description(hiv_other custom `custom_version') mark_best(yes) in_dir(/ihme/codem/data/hiv_other/`custom_version') model_version_type_id(6)


	