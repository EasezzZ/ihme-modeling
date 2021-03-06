// Run nesarc analysis 1000 times with bootstrapping, but save a file each time of the people with each cause.
// See Detailed comments in the MEPS analysis - this generally mimics it.


cap restore, not

clear all
set mem 300m
set more off
set maxiter 25

// get data
cd "$dir"
use "$SAVE_DIR/2b_nesarc_lowess_r_interpolation.dta", clear
drop if key == -999
merge 1:m key using "$SAVE_DIR/2a_nesarc_prepped_to_crosswalk.dta", nogen

// prep a few things
replace dw_hat = 1 if dw_hat>1  & dw_hat != .
replace dw_hat = 0 if dw_hat<0
replace dw_hat = .999 if dw_hat >= 1
replace dw_hat = .001 if dw_hat <= 0
gen logit_dw = logit(dw_hat)
tab age_gr, generate(AGE)
replace AGE1 = 0

drop if dw != .

di in red "$r"
set seed $r
bsample



// set up mata for reporting table
mata: COMO 	 		 		= J(1500, 1, "")
mata: AGE 		 			= J(1500, 1, .)
mata: DEPENDENT				= J(1500, 1, "")
mata: DW_T					= J(1500, 1, .)
mata: SE					= J(1500, 1, .)
mata: DW_S					= J(1500, 1, .)
mata: DW_O					= J(1500, 1, .)
mata: N						= J(1500, 1, .)
local c = 1


xtmixed logit_dw I_* mental_anxiety mental_other mental_unipolar_mdd mental_unipolar_dys Mania Hypomania R_* || id:

foreach como of varlist I_* mental_anxiety mental_other mental_unipolar_mdd mental_unipolar_dys Mania Hypomania R_* {

	preserve
	di in red "CURRENTLY LOOPING THROUGH: `como'  "

	estimates esample: logit_dw I_* mental_anxiety mental_other mental_unipolar_mdd mental_unipolar_dys Mania Hypomania R_*, replace

	// keep only those with the condition in question
	predict re, reffects
	keep if  `como' == 1
		// predict for their DW and reverse logit it
		predict dw_obs // ADD RANDOM EFFECT IN@

		// replace dw_obs=dw_obs+re
		replace dw_obs = invlogit(dw_obs)

	// replace the condition in question to zero
	replace `como' = 0

	// now predict and inverse logit again. This will give the counterfactual DW (or their expected weight if they didnt have the condition in question)
	predict dw_s_`dependent'
		replace dw_s = dw_s // ADD RANDOM EFFECT IN@
		// replace dw_s_=dw_s_+re
		replace dw_s_`dependent' = invlogit(dw_s_`dependent')

	count

		sum dw_s
			if `r(N)' > 0 local mean_s = `r(mean)'
			else local mean_dw_s = .
		sum dw_obs
			if `r(N)' > 0 local mean_o = `r(mean)'
			else local mean_dw_o = .

		gen dw_t_`dependent' = (1 - ((1-dw_obs)/(1-dw_s_`dependent')))
			count
			if `r(N)' != 0 {
				summ dw_t_`dependent'

				local mean_dw_tnoreplace = `r(mean)'
				local se = `r(sd)'
			}
			else {
				local mean_dw_tnoreplace = .
				local se = .
			}
		count
		local N = `r(N)'

		mata: COMO[`c', 1]  	= "`como'"
		mata: DEPENDENT[`c', 1] = "logit"
		mata: DW_T[`c', 1] = `mean_dw_tnoreplace'
		mata: SE[`c', 1] = `se'
		mata: DW_S[`c', 1] 		= `mean_s'
		mata: DW_O[`c', 1]		= `mean_o'
		mata: N[`c', 1]     	= `N'

		keep id sex age_gr pcs mcs dw_hat dw_obs dw_s dw_t
		rename dw_hat DW_data
		rename dw_obs DW_pred
		rename dw_s DW_counter
		rename dw_t DW_diff_pred
		g DW_diff_data = 1 - ((1- DW_data)/(1- DW_counter))


		// save bootstrap dataset
		cap mkdir "$SAVE_DIR/3a_nesarc_bootstrap_datasets"
		cap mkdir "$SAVE_DIR/3a_nesarc_bootstrap_datasets//${i}"
		save	  "$SAVE_DIR/3a_nesarc_bootstrap_datasets//${i}//`como'", replace

		restore
		local c = `c' + 1
}

clear


getmata COMO DEPENDENT DW_T SE DW_S DW_O N

replace DW_S = . if DW_T == .
replace DW_O = . if DW_T == .
drop if COMO == ""

rename COMO como
rename DEPENDENT dependent
rename DW_T dw_t
rename SE se
rename DW_S dw_s
rename DW_O dw_o
rename N n

rename dw_t dw_t${i}
keep como dw_t
rename como condition

cap mkdir "$SAVE_DIR/3a_nesarc_dw_draws"
save	  "$SAVE_DIR/3a_nesarc_dw_draws//${i}.dta", replace

// END OF DO FILE
