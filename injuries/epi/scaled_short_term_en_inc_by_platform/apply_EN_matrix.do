// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************

// Description:	This code applies the EN matrices to the Ecode-platform incidence data to get Ecode-Ncode-platform-level incidence data, then appends and saves it at the country/year/sex level

// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
	// prep stata
	clear all
	set more off
	set mem 2g
	set maxvar 32000
	if c(os) == "Unix" {
		global prefix "/home/j"
		set odbcmgr unixodbc
	}
	else if c(os) == "Windows" {
		global prefix "J:"
	}
	if "`1'"=="" {
		local 1 /snfs1/WORK/04_epi/01_database/02_data/_inj/04_models/gbd2015
		local 2 /share/injuries
		local 3 2016_02_08
		local 4 "04b"
		local 5 scaled_short_term_en_inc_by_platform
		local 6 "/share/code/injuries/ngraetz/inj/gbd2015"
		local 7 161
		local 8 1995
		local 9 1
	}
	// base directory on J 
	local root_j_dir `1'
	// base directory on clustertmp
	local root_tmp_dir `2'
	// timestamp of current run (i.e. 2014_01_17)
	local date `3'
	// step number of this step (i.e. 01a)
	local step_num `4'
	// name of current step (i.e. first_step_name)
	local step_name `5'
    // directory where the code lives
    local code_dir `6'
    // iso3
	local location_id `7'
	// year
	local year `8'
	// sex
	local sex `9'
	// directory for external inputs
	local in_dir "`root_j_dir'/02_inputs"
	// directory for output on the J drive
	local out_dir "`root_j_dir'/03_steps/`date'/`step_num'_`step_name'"
	// directory for output on clustertmp
	local tmp_dir "`root_tmp_dir'/03_steps/`date'/`step_num'_`step_name'"

	// directory for standard code files
	adopath + "$prefix/WORK/04_epi/01_database/01_code/04_models/prod"
	
	// start the timer for this substep
	adopath + "$prefix/WORK/04_epi/01_database/01_code/00_library/ado"

// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************

// SETTINGS
	** how many slots is this script being run on?
	local slots 2
	
// Filepaths
	local gbd_ado "$prefix/WORK/04_epi/01_database/01_code/00_library/ado"
	local diag_dir "`out_dir'/02_temp/04_diagnostics"
// Import functions
	adopath + "`code_dir'/ado"
	adopath + `gbd_ado'
	
	//start_timer, dir("`diag_dir'") name("`location_id'_`year'_`sex'") slots(`slots')

local location `location_id'

** we have two blocks in this code
** $apply_en=1 if we want to apply the EN matrix to the nonscaled E codes
global apply_en=1
** $ scale_children will calculate the proportions of all parent e-code incidence due to each child e-code
global scale_children = 1
 
** get imputed e-codes
insheet using "`in_dir'/parameters/ecode_imputation_relationships.csv", comma names clear
levelsof imputed_ecode, local(imputed_ecodes) clean

if "$prefix" == "/home/j" set odbcmgr unixodbc

** load params
load_params

** pull the list of iso3 codes that the results are saved at- written as an ado function and get the income level of the location - do this outside of the parallelized code now and saves to inputs file
use if location_id==`location_id' using "`out_dir'/01_inputs/income_map.dta", clear
local income_level=high_income in 1

** need to change this if in the future you have multiple age categories for EN matrices. In GBD 2013 all under 1 ncodes were aggergated to age=0
global collapsed_under1=1

** set locals for the location of the non-shock incidence results, the shock incidence results and the EN matrices based on the "steps" files
import excel using "`code_dir'/_inj_steps.xlsx", firstrow clear
** non-shock incidence
preserve
keep if name == "raw_nonshock_short_term_ecode_inc_by_platform"
local this_step=step in 1
local nonshock_inc_dir = "`root_tmp_dir'/03_steps/`date'/`this_step'_raw_nonshock_short_term_ecode_inc_by_platform"
restore
** EN Matrices results
preserve
keep if name == "EN_matrices"
local this_step=step in 1
local EN_mat_dir = "`root_tmp_dir'/03_steps/`date'/`this_step'_EN_matrices"

restore
	
** grab the incidence numbers for this location/year/sex and store in memory
import delimited "`nonshock_inc_dir'/03_outputs/01_draws/incidence_`location_id'_`year'_`sex'.csv", delim(",") varnames(1) asdouble clear
rename draw* inc_draw*
tempfile unscaled_incidence
save `unscaled_incidence', replace

** edit 8/7/14 ng - Collapse incidence in ages <1 to a single group, "0"
use "`out_dir'/01_inputs/pops.dta", clear
tempfile pops
save `pops', replace
use `unscaled_incidence', clear
gen location_id = `location_id'
gen year_id = `year'
gen sex_id = `sex'
merge m:1 location_id year_id age_group_id sex_id using `pops'
keep if _merge == 3
drop _merge
gen new_age = age_group_id
replace new_age = 2 if new_age < 5 // 5 is the new age id for age=1 year, 2 is the new age_id for 0
forvalues i = 0/999 {
	replace inc_draw_`i' = inc_draw_`i' * pop_scaled
}
fastcollapse inc_draw_* pop_scaled, type(sum) by(ecode inpatient new_age)
forvalues i = 0/999 {
	replace inc_draw_`i' = inc_draw_`i'/pop_scaled
}
rename new_age age_group_id
// Recode age_group_ids to actual ages, as this is how the EN matrices are formatted based on that data. I've decided to leave all intermediate injuries results with actual ages instead of GBD age_group_ids. I'll recode whenever I need to upload results - 11/4/2015
preserve
	insheet using "`code_dir'/convert_to_new_age_ids.csv", comma names clear
	tempfile age_codes
	save `age_codes', replace
restore
merge m:1 age_group_id using `age_codes', keep(3) nogen
drop age_group_id
rename age_start age
save `unscaled_incidence', replace
// ***********************

local scaling_counter = 0

foreach platform in otp inp {

	if "`platform'"=="otp" {
		local platform_num 0
	}
		
	if "`platform'"=="inp" {
		local platform_num 1
	}
	** get list of N-Codes to loop over for each platform
	local `platform'_ecode_list : dir "`EN_mat_dir'/03_outputs/01_draws/`platform'/" files "*.csv"
** this block applies the EN matrix to all E-codes
if $apply_en {	
	
	foreach e_code of local `platform'_ecode_list {
	
		local e_code = subinstr("`e_code'", ".csv", "", .)
		di "SPLITTING THIS ECODE: `e_code'"
		if regexm("`imputed_ecodes'", "`e_code'") {
			di "shock e_codes like `e_code' will be processed in a seperate piece of code"
		}
		else {
			** grab the EN matrix for this cause and store the n-codes in memory
			import delimited "`EN_mat_dir'/03_outputs/01_draws/`platform'//`e_code'.csv", delim(",") varnames(1) asdouble clear
			keep if high_income==`income_level' & sex == `sex'
			rename draw* n_draw*
			preserve
			keep n_code
			duplicates drop
			levelsof n_code, local(`e_code'_`platform'_ns) clean			
			clear mata
			putmata n_code
			count
			local n_count=`r(N)'
			restore
			
			tempfile en_matrix
			save `en_matrix', replace
			
			use if ecode=="`e_code'" & inpatient == `platform_num' using `unscaled_incidence', clear
			
			** depending on what ages we have e-n data for, we create a new age variable for merging on the EN matrix
			rename age true_age
			gen age = true_age
			replace age = 80 if true_age >= 80
			if $collapsed_under1 {
				replace age = round(age, 1)
			}
			** expand to the number of n_codes that have EN data for this E-code, generate a new variable for "N code" which will make age-n_code combination a unique identifier
			expand `n_count'
			bysort true_age: gen n=_n
			gen n_code=""
			forvalues i=1/`n_count' {
				mata: st_local("n_code",n_code[`i'])
				replace n_code="`n_code'" if n==`i'
			}
			
			** merge on the E-N matrix and generate the proportions of this e-code that get allocated to each n-code
			merge m:1 age n_code using `en_matrix', keep(3) nogen
			
			di "generating proportion of `e_code' incidence alloted to these n-code"
			** quietly {				
				forvalues j=0(1)999 {
					gen draw_`j'=n_draw`j'*inc_draw_`j'
					drop n_draw`j' inc_draw_`j'
				}
			** }
			drop age
			rename true_age age 
	
			keep age n_code draw_* inpatient
			gen e_code = "`e_code'"
			tempfile `platform'_`e_code'_ps
			save ``platform'_`e_code'_ps', replace
		}
		** end block that confirms this is a modeled e_code and not a shock code
	}
	** end e-code loop	
}
** end apply_en block

if $scale_children {
** now do the scaling for the child causes
** pull the list of child e-codes that need to be squeezed to fit the parent
use "`out_dir'/01_inputs/relationships.dta", clear
** cycle through the parent e_codes, pulling the list of child codes for each particular parent
** this list contains all of the e-codes WITH child models
levelsof parent_model if regexm(DisModmodels, "Child of"), local(parents_with_children) clean
** this list contains all of the e-codes that ARE child models
levelsof child_model if regexm(DisModmodels, "Child of"), local(children_with_parents) clean
** this list contains all of the e-codes that are single models
levelsof child_model if regexm(DisModmodels, "Single model"), local(single_models) clean
tempfile child_parent
save `child_parent', replace

global send_results_dir  "`tmp_dir'/03_outputs/01_draws"
	

	** loop through the modeled e_codes, identify if they are a parent, child or single model
	foreach e_code of local `platform'_ecode_list {
		
			di in red "in scaling loop for `e_code'"
			local e_code = subinstr("`e_code'", ".csv", "", .)
			
			if regexm("`imputed_ecodes'", "`e_code'") {
				di "shock e_codes like `e_code' will be processed in a seperate piece of code"
			}
			** end check shocks
			else {
				** OPTION 1
				** if this e-code is in the list of e_codes with children, find those children and then squeeze them
				if regexm("`parents_with_children'", "`e_code'") {
					use `child_parent', clear
					keep if parent_model=="`e_code'"
					levelsof child_model, local(model_children) clean
					
					** STEP 1: grab the incidence results for the children
					** and calculate the proportions of each
					local counter=0
					foreach child of local model_children {	
						** bring in incidence data
						use age draw_* n_code e_code inpatient using ``platform'_`child'_ps', clear
						
						if `counter'==0 {
							tempfile all_children
							save `all_children', replace
							local ++counter
						}
						else {
							append using `all_children'
							save `all_children', replace
							local ++counter
						}
				
					}
				
					use `all_children', clear
					
					** collapse over the sums for the denominator of each draw/age/ncode combination across all of the child causes 
					** sum of all child incidences
					collapse (sum) draw_*, by(age n_code inpatient)
					rename draw* sum_draws*
				
					** STEP 2: merge the sum of the incidences back on the child-level draws and generate 1000 new proportion variables
					** output is : prop_draw = child "C" incidence / sum of all child incidences
					merge 1:m age n_code inpatient using `all_children', nogen
					
						forvalues i=0(1)999 {
							qui generate prop_draw`i'=draw_`i'/sum_draws_`i'
							qui count if prop_draw`i'==.
							if `r(N)'!=0 {
								** di "draw `i' has no incidence for the children of `e_code' for `r(N)' observations"
							}
							drop draw_`i' sum_draws_`i'
							
						}
					tempfile child_proportions
					save `child_proportions', replace
				
					** STEP 3: cycle through the child codes and create new re-scaled incidence data using the parent incidence, save output to new folders
					** new child "C" incidence = parent incidence * (child "C" incidence/sum of all child incidences)
					use age draw_* n_code inpatient using ``platform'_`e_code'_ps', clear
					
					local child_count wordcount("`model_children'")
					merge 1:m age n_code using `child_proportions', nogen		
					
					** sometimes there are parent causes with nonzero incidence, but all of the child causes have draw_`i'==0. If this is the case, we distribute them equally
					forvalues i=0(1)999 {
						qui generate scaled_draw_`i'= prop_draw`i'*draw_`i'
						qui count if scaled_draw_`i'==.
						** if we are missing child-level proportions for this draw (i.e. the sum of all the child e-code incidences was 0 for a given N/sex/age) then we say that the parent incidence is equally distributed over children
						qui replace scaled_draw_`i'=draw_`i'/`child_count' if prop_draw`i'==.
						drop prop_draw`i' draw_`i'
					}
					rename scaled_draw* draw*
					fastrowmean draw_*, mean_var_name(mean_)
					fastpctile draw_*, pct(2.5 97.5) names(ll_ ul_)
					format mean ul_ ll_ draw_* %16.0g
					local ++scaling_counter
				}
				** end loop for e-codes that are parents
				
				** OPTION 2
				** if this is a single model, just save it
			if regexm("`single_models'", "`e_code'") {
				use age draw_* n_code e_code inpatient using ``platform'_`e_code'_ps', clear
				fastrowmean draw_*, mean_var_name(mean_)
				fastpctile draw_*, pct(2.5 97.5) names(ll_ ul_)
				format mean ul_ ll_ draw_* %16.0g
				local ++scaling_counter				
				}
				** OPTION 3
				** if this ecode is a child (i.e. it is in the "Children with parents" list, but not in the "parents with children"), skip this e-code, we'll capture it in its parent loop
				** for example "inj_trans_road" is in the children_with_parents (because inj_trans_road_2wheel, inj_trans_road_pedest, etc are in there, and that is how regexm works) but it is also in the parents_with_children
				if regexm("`children_with_parents'", "`e_code'") & !regexm("`parents_with_children'", "`e_code'") {
					display "`e_code' is a child E-Code that will be scaled in its parent loop"
				}					

				else {
					if `scaling_counter'==1 {
						tempfile all_appended
						save `all_appended', replace
					}
					if `scaling_counter'>1 {
						append using `all_appended'
						di "`e_code' `n_code'"
						isid age n_code e_code inpatient
						save `all_appended', replace
					}
				}
			}
			** end nonshock block
		}
		** end ecode loop
	}
** end scale_children block

}
** end platform loop
di `scaling_counter'

use `all_appended', clear

isid age n_code e_code inpatient
** keep only the EN combinations that have nonzero draws
foreach n of global inp_only_ncodes {
	drop if n_code=="`n'" & inpatient == 0
}
egen double dropthisn=rowtotal(draw*)
bysort e_code n_code inpatient : egen ensum = sum(dropthisn)
drop if ensum==0

rename e_code ecode
rename n_code ncode
capture mkdir "`tmp_dir'/03_outputs/01_draws/nonshocks/"
capture mkdir "`tmp_dir'/03_outputs/01_draws/nonshocks/collapsed"
sort_by_ncode ncode, other_sort(inpatient age)
sort ecode
preserve
keep ecode ncode inpatient age draw_*
save "`tmp_dir'/03_outputs/01_draws/nonshocks/collapsed/incidence_`location_id'_`year'_`sex'.dta", replace
restore

** get rid of the trailing _ on ul and ll (this should be cleaned up earlier but don't want to mess things up - IB 5/7/14)
rename *_ *
capture mkdir "`tmp_dir'/03_outputs/02_summary/nonshocks/"
capture mkdir "`tmp_dir'/03_outputs/02_summary/nonshocks/collapsed"
keep ecode ncode inpatient age mean ll ul
save "`tmp_dir'/03_outputs/02_summary/nonshocks/collapsed/incidence_`location_id'_`year'_`sex'.dta", replace

// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// CHECK FILES (NO NEED TO EDIT THIS SECTION)
	log close worker
	erase "`out_dir'/02_temp/02_logs/`step_num'_`location_id'_`year'_`sex'.smcl"
	
