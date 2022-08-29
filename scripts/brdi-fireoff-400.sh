#!/bin/bash

#==========================================================================================
#
#    This script generates an ensemble of cases for a single-point simulation for
# a user-defined site. It assumes all the site-specific data files (SITE_NAME) are located
# in the SITE_BASE_PATH folder.
#
# Developed by: Marcos Longo < m l o n g o -at- l b l -dot- g o v >
#               07 Jun 2022 10:24 PDT
# Based on scripts developed by Chonggang Xu, Ryan Knox and Shawn Serbin.
#
#     This script does not take any arguments. Instead, the beginning of the script has
# many variables to control the simulation settings. The script has been tested on Marcos'
# local computer (eschweilera) and at NERSC (cori-haswell and cori-knl). It is likely
# nearly compatible with other systems, but it may require a few tweaks. If you add new
# variables or change the script below the "CHANGES BEYOND THIS POINT ARE FOR SCRIPT
# DEVELOPMENT ONLY!" message, please consider submitting a pull request, so the script is
# more generalisable.
#
#     This script requires the following files:
# - Ensemble_FATES_Param.r, the R script that generates the NetCDF files for ensemble
#   members.
# - A default parameter file (cdl format) that will be used as basis for the ensembles.
#==========================================================================================


#--- Main settings.
export HESM="CTSM"        # Host "Earth System Model". (E3SM, CESM, CTSM)
export MACH="cheyenne"    # Machine used for preparing the case
#---~---


#---~---
#   Job submission settings. These settings depend on the machine select, and may not
# be used.
#
# ---------------------------------------------------------
#  Relevant for all submissions
# ---------------------------------------------------------
#
# - AUTO_SUBMIT -- Submit the job upon successful creation? (true or false)
#
# ---------------------------------------------------------
#  Relevant for SLURM-based HPC clusters
# ---------------------------------------------------------
#
# - PROJECT         -- Project account to be used for this submission
#                      Set it to empty (PROJECT="") in case this is not applicable.
# - PARTITION       -- Specify the partition for the job to be run.
#                      Set it to empty (PARTITION="") to use the default.
# - RUN_TIME        -- Run time for job, in HH:MM:SS format. Make sure this
#                      does not exceed maximum allowed.
# - TASKS_PER_NODE  -- Number of tasks per node (aka ensemble members per job).  This
#                      must be less than the maximum number of tasks per node. If zero,
#                      then the code will set it to the maximum number of tasks per node.
# - CPUS_PER_TASK   -- Number of CPUS requested for each task. Set it to 1 unless
#                      using multi-threading (shared memory parallelisation, OpenMP).
#---~---
export AUTO_SUBMIT=false
export PROJECT="ULBN0002"
export PARTITION="regular"
export RUN_TIME="12:00:00"
export TASKS_PER_NODE=36
export CPUS_PER_TASK=1
#---~---


#---~---
#    Debugging settings
#
# - DEBUG_LEVEL. The higher the number, the more information will be provided (at the
#   expense of running slower).  0 means no debugging (typical setting for scientific
#   analysis), 6 means very strict debugging (useful when developing the code).
#---~---
export DEBUG_LEVEL=0
#---~---


#---~---
#    Ensemble settings
#
# - ENS_R_TEMPLATE -- Template for the R script that defines parameters for ensemble
#                     simulations (either at the same path as this script, or the
#                     full path). This is typically the Ensemble_FATES_Param.r file.
# - N_ENSEMBLE     -- Number of ensemble realisations. This must be a positive number.
# - SAMPLE_METHOD  -- Ensemble sampling method. Options are:
#                     - default: Default approach (uniform distribution)
#                     - latin: Latin Hypercube sampling
# - SEED_INIT      -- Seed number for random generator. Setting the seed to a known
#                     number allows full reproducibility of the code. For a completely
#                     (non-reproducible) random sampling, set the seed to "NA_real_".
# - LHS_EPS        -- Tolerance for deviation between prescribed matrix and the result for
#                     correlated Latin Hypercube Sampling (ignored otherwise).  Very strict
#                     tolerances may cause convergence failure if the number of samples is
#                     large.
# - LHS_MAXIT      -- Maximum number of iterations before giving up on building the Latin
#                     hypercube when accounting for correlations (ignored otherwise). Set
#                     to 0 to let the algorithm define it. If negative, the method will
#                     never give up until convergence, but this risks running indefinitely
#                     in case the method fails to converge.
#---~---
export ENS_R_TEMPLATE="/glade/u/home/xiugao/CTSM/cime/scripts/Ensemble_FATES_Param.r"
export N_ENSEMBLE=1500
export SEED_INIT=6
export LHS_EPS=0.025
export LHS_MAXIT=1000
#---~---



#---~---
#    Path settings:
#
# WORK_PATH: The main working path (typically <host_model>/cime/scripts)
# CASE_ROOT: The main path where to create the directory for this case.
# SIMUL_ROOT: The main path where to create the directory for the simulation output.
#
# In all cases, use XXXX in the part you want to be replaced with either E3SM or CTSM.
#---~---
case "${MACH}" in
cheyenne)
   export WORK_PATH="${HOME}/XXXX/cime/scripts"
   export PERM_PATH="/glade/work/xiugao"
   export TEMP_PATH="/glade/scratch/xiugao"
   export CASE_ROOT="${PERM_PATH}/ParSensRuns/Cases"
   export SIMUL_ROOT="${TEMP_PATH}/ParSensRuns/Simulations"
   ;;
*)
   export WORK_PATH="${HOME}/Models/XXXX/cime/scripts"
   export CASE_ROOT="${HOME}/ParSensRuns/Cases"
   export SIMUL_ROOT="${SCRATCH}/ParSensRuns/Simulations"
   ;;
esac
#---~---



#---~---
#   Define a base directory using SITE_BASE_PATH.  If using a standard data file
# structure, this is the directory where all site data are located, one sub-directory per
# site. The names of these sub-directories match site_name. Each site-specific path (i.e.
# `<SITE_BASE_PATH>/<SITE_INFO%site_name>` should contain:
#
# 1. A sub-directory `CLM1PT` containing the meteorological drivers.  Check documentation
#    for script [make_fates_met_driver.Rmd](make_fates_met_driver.html) for more details.
# 2. The domain and surface data specific for this site. Check documentation for script
#    [make_fates_domain+surface.Rmd](make_fates_domain+surface.html) for further
#    information.
# 3. _Optional_. A FATES parameter file, which is defined by variable `fates_param_base`,
#    defined a bit below in the chunk. This file is assumed to be in the `<site_name>`
#    sub-directory.  In case none is provided (i.e., `<fates_param_base>=""`), the case
#    will use the default parameter file. Beware that the default is not optimised and
#    may yield bad results.
# 4. _Optional_. The forest structure control data, which should contain the full paths
#    to ED2-style  pss (patch) and css (cohort) files. This file base name should be
#    `<site_name>_<inv_suffix>.txt`, or blank in case inventories should not be used.
#     Check the ED2 Wiki (https://github.com/EDmodel/ED2/wiki/Initial-conditions)
#    for details on how to generate the files.
#
#    The actual scripts are available on GitHub:
#    https://github.com/mpaiao/ED2_Support_Files/tree/master/pss%2Bcss_processing.
#---~---
export SITE_BASE_PATH="/glade/work/xiugao/fates-input"
#---~---


#---~---
#   Main case settings.  These variables will control compilation settings and the
# case name for this simulation.  It is fine to leave these blank, in which case the
# script will use default settings.
#---~---
export COMP=""
export CASE_PREFIX="brdi-fireoff-400"
#---~---


#---~---
#   Append git commit to the case name?
#---~---
export APPEND_GIT_HASH=false
#---~---



#---~---
#   Grid resolution.  If this is a standard ELM/CLM grid resolution, variables defined
# in the site information block below will be ignored.  In case you want to use the
# site information, set RESOL to YYY_USRDAT. (The host model will be replaced later
# in the script).
#---~---
export RESOL="YYY_USRDAT" # Grid resolution
#---~---


#---~---
#   Site information (SITE_INFO). In case RESOL is set to YYY_USRDAT, this allows the user
# to pick one of their favourite sites, and load the pre-defined settings for each of
# them. This should be an array with each line containing the following elements:
#
#
# site_id    -- A unique site id.  Typically a sequential order (but the code checks it).
#               Do not use zero or negative numbers, though.
# site_desc  -- A descriptive but short name for site (no spaces, please).
# site_name  -- The full site name, typically the sub-directory where all the site-specific
#               data are stored.
# start_date -- The start date for simulating the site. Useful if running FATES over
#               site-specific time periods (e.g. tower data overlap).
# stop_n     -- Number of years to run the model for this site.  Useful if running FATES
#               over site-specific time periods (e.g. tower data overlap).
# datm_first -- First year with meteorological driver. This is normally fixed unless new
#               versions of the data become available.
# datm_last  -- Last year with meteorological driver. This is normally fixed unless new
#               versions of the data become available.
# calendar   -- Which calendar type should we use? This must be consistent with the
#               meteorological drivers. Options are `"NO_LEAP"`, for non-leap years and
#               `"GREGORIAN"`, for Gregorian calendar. Note that `"GREGORIAN"` calendar
#               requires meteorological drivers that extend to entire simulation time span
#               (i.e., no recycling), otherwise, the simulation will likely crash in one of
#               the Februaries outside the meteorological driver range.
#---~---
#                  site_id  site_desc            site_name                              start_date  stop_n   datm_first  datm_last  calendar
export SITE_INFO=("      1  VairaRanch           vaira-1pt                              1985-01-01      36         2000       2014   NO_LEAP"
                  "      2  CAannualGrass        ca-wrf-grassland                       1981-01-01      40         1981       2020   NO_LEAP")
#---~---


#---~---
#    Variable SITE_USE lets you pick which site to use. This is an integer variable that
# must correspond to one of the site_id listed in SITE_INFO.
#---~---
export SITE_USE=1
#---~---


#---~---
#   Set the base parameter path and file, in case a specific file exists. If the file is
# a site-specific one, set FATES_PARAMS_FILE= without directories. This will mean that
# the path is the SITE_PATH. If a specific parameter file is to be used across sites, set
# FATES_PARAMS_FILE with full path.  Leaving the variable empty (i.e., FATES_PARAMS_FILE="")
# means that we should be using the default parameter file.
#---~---
export FATES_PARAMS_FILE="${SITE_BASE_PATH}/vaira-1pt/fates_c3g_brdi_base2.cdl"
#---~---



#---~---
#   Configuration information.  This allows setting multiple FATES configurations. Note
# that this is different from changing parameter values or running parameter sensitivity
# experiments. Variable CONFIG_INFO should countain the following elements:
#
# config_id     -- A unique configuration ID. Typically a sequential order (but the code
#                  checks it).  Do not use zero or negative numbers, though.
# config_desc   -- Suffix to append to site name that summarises configuration.
# inv_suffix    -- Suffix for the forest inventory plot initialisation instructions.
#                  The base file name with instructions should be like:
#                  `<site_name>_<inv_suffix>.txt`.  In case you do not want to use
#                  inventory initialisation, set this to NA.
# ddphen_model  -- Which drought deciduous phenology to use (1 is the instantaneous
#                  flushing/shedding, and 2 is the ED2-like approach with partial
#                  flushing and shedding).
# fates_hydro   -- Use plant hydrodynamics? .true. turns it on, .false. turns it off..
#---~---
#                     config_id   config_desc                            inv_suffix     ddphen_model  fates_hydro       fates_spitfire_mode
export CONFIG_INFO=("         1   BareGround_InstDD_HydroOFF_FireOFF       NA                 0        .false.            0"
                    "         2   BareGround_InstDD_HydroOFF_Fireon        NA                 0        .false.            1"
                    "         3   BareGround_PartDD_HydroOFF               NA                 1        .false.            1"
                    "         4   Inventory_EGOnly_HydroOFF               evergreen_info      0        .false.            1" 
                    "         5   Inventory_InstDD_HydroOFF               nopft_info          0        .false.            1"
                    "         6   Inventory_PartDD_HydroOFF               nopft_info          1        .false.            1")
#---~---


#---~---
#    Variable CONFIG_USE lets you pick which configuration setting to use. This is an
# integer variable that must correspond to one of the config_id listed in CONFIG_INFO.
#---~---
export CONFIG_USE=1
#---~---



#---~---
#    XML settings to change.  In case you don't want to change any settings, leave this
# part blank.  Otherwise, the first argument is the variable name, the second argument is
# the value.  Make sure to add single quotes when needed.  If you want, you can use the
# generic XXX for variables that may be either CLM or ELM (lower case xxx will replace
# with the lower-case model name).  The code will interpret it accordingly.
#
#    If the variable is site-specific, it may be easier to develop the code by adding
# new columns to SITE_INFO, and using a similar approach as the one used to set variable
# RUN STARTDATE (look for it in the script).
#
# Example:
#
# No change in xml settings:
# xml_settings=()
#
# Changes in xml settings
# xml_settings=("DOUT_S_SAVE_INTERIM_RESTART_FILES TRUE"
#               "DOUT_S                            TRUE"
#               "STOP_N                            10"
#               "XXX_FORCE_COLDSTART               on"
#               "RUN_STARTDATE                     '2001-01-01'")
#---~---
xml_settings=("DEBUG                             FALSE"
              "STOP_OPTION                       nyears"
              "REST_N                            1"
              "YYY_FORCE_COLDSTART               on")
#---~---



#---~---
#    List of parameters to be updated for all ensemble members (meaning that
# these values WILL BE THE SAME FOR EVERY ENSEMBLE MEMBER). Do not add variables
# that should vary across ensemble members, use ens_settings instead. In case you
# don't want to change any parameter for every ensemble simulation, leave this part blank.
# Otherwise, the first argument is the variable name, the second argument
# is the PFT number (or zero for global parameter), and the third argument is the value.
#
# Example:
#
# No change in parameter settings:
# prm_settings=()
#
# Changes in xml settings
# prm_settings=("fates_wood_density 1      0.65"
#               "fates_wood_density 2      0.75"
#               "fates_smpsc        1 -200000.0"
#               "fates_smpsc        2 -300000.0")
#---~---
prm_settings=("fates_allom_amode                      1         1"
              "fates_allom_agb1                       1         0.02353439"
              "fates_allom_agb2                       1         2.20989"
              "fates_allom_agb3                       1         1.0510878"
              "fates_allom_agb4                       1         0"
              "fates_allom_agb_frac                   1         1"
              "fates_allom_lmode                      1         1"
              "fates_allom_d2bl1                      1         0.00044499"
              "fates_allom_d2bl2                      1         1.597315"
              "fates_allom_d2bl3                      1         0"
              "fates_allom_hmode                      1         3"
              "fates_allom_d2h1                       1         0.12812118"
              "fates_allom_d2h2                       1         0.510092"
              "fates_allom_dbh_maxheight              1         9"
              "fates_allom_fmode                      1         1"
              "fates_allom_l2fr                       1         1"
              "fates_allom_d2ca_coefficient_max       1         0.01651188"
              "fates_allom_d2ca_coefficient_min       1         0.01651188"
              "fates_allom_blca_expnt_diff            1         -0.182835"
              "fates_allom_la_per_sa_int              1         1000"
              "fates_recruit_seed_alloc               1         0"
              "fates_wood_density                     1         0.001"
              "fates_recruit_init_density             1         100"
              "fates_rad_leaf_rhonir                  1         0.35"
              "fates_rad_leaf_clumping_index          1         0.77")
#---~---



#---~---
#    List of parameters to be sampled across ensemble members (meaning that
# these values WILL CHANGE FROM ENSEMBLE MEMBER TO ENSEMBLE MEMBER).  This is
# an array with the following elements as columns:
#
#   * parameter -- Parameter names for the ensemble. These must be valid parameter names
#                  compatible with the provided NetCDF file
#   * value_min -- Minimum value allowed for each parameter.
#   * value_max -- Maximum value allowed for each parameter.
#   * pft       -- PFT for which the parameter should be updated. Set this
#                  value to NA in case the parameter is global, or to zero if this should
#                  be applied to all PFTs.
#   * organ     -- First organ for which the parameter should be updated. Set this value
#                  to NA in case the parameter is NOT organ-specific, or to zero if this
#                  value should be applied to all PFTs
#
# Example:
#
# Changes in xml settings
# ens_settings=( "fates_phen_drought_threshold  -200000. -100000.   NA   NA"
#                "fates_alloc_storage_cushion       0.5       2.5    0   NA"
#                "fates_leaf_vcmax25top             8.0      69.0    1   NA"
#                "fates_leaf_vcmax25top            13.0     120.0    2   NA")
#
# IMPORTANT: Unlike other settings, this cannot be empty. If not interested in running
#            ensemble runs, use the single-run script (create_case_hlm-fates.sh) instead.
#---~---
#               parameter                                value_min     value_max   pft   organ
ens_settings=( "fates_leaf_vcmax25top                    35.6           91.6         0      NA"
               "fates_alloc_storage_cushion              0.8            1.5          0      NA"
               "fates_leaf_slatop                        0.003          0.03         0      NA"
               "fates_leaf_slamax                        0.003          0.03         0      NA"
               "fates_turb_leaf_diameter                 0.01           0.04         0      NA"
               "fates_turnover_leaf                      0.02           0.32         0      NA"
               "fates_leaf_stomatal_intercept            10000          2030000      0      NA"
               "fates_leaf_stomatal_slope_ballberry      5.25           17.          0      NA"
               "fates_recruit_seed_dbh_repro_threshold   1.5            4.           0      NA"
               "fates_recruit_seed_alloc_mature          0.003          1.           0      NA"
               "fates_recruit_height_min                 0.1            0.5          0      NA"
               "fates_phen_drought_threshold             0.1            0.3          0      NA"
               "fates_nonhydro_smpsc                    -200000        -60000        0      NA"
               "fates_nonhydro_smpso                    -60000         -33000        0      NA"
               "fates_allom_fnrt_prof_a                  5.             13.          0      NA"
               "fates_allom_fnrt_prof_b                  3.             10.          0      NA"
               "fates_mort_scalar_hydrfailure            3.             20.          0      NA"
              # "fates_fire_FBD                           4.             22.          NA     5"
              # "fates_fire_FBD                           1.             4.           NA     6"
              # "fates_fire_nignitions                    0.01           1.           NA     NA"
              # "fates_fire_drying_ratio                  66             66000        NA     NA"
              # "fates_fire_fuel_energy                   6450           14300        NA     NA"
               "fates_frag_maxdecomp                     0.8            1.6          NA     5"
               "fates_stoich_nitr                        0.033          0.052        0      1"
               "fates_mort_scalar_cstarvation            1              6            0      NA"
               "fates_mort_hf_sm_threshold               0.25           0.9          0      NA")
# ---~---



#---~---
#   Optional list of correlations amongst the parameters to be sampled:
#
#   List only those correlations that are relevant, and no need to provide correlation
#   between var_b and var_a if the correlation between var_a and var_b is provided. The
#   sampling code will take care of this. Also, no need to provide diagonal terms (i.e.,
#   correlation between var_a and var_a). If a correlation between two variables is not
#   provided, the script will treat the parameters as uncorrelated.
#   The csv file should contain the following columns (case sensitive). This is an array
#   with the following columns:
#   * parameter_a -- First parameter name. These must be valid parameter names compatible
#                    with the provided NetCDF file AND must feature in the parameter
#                    instruction file.
#   * parameter_b -- Second parameter name. These must be valid parameter names compatible
#                    with the provided NetCDF file AND must feature in the parameter
#                    instruction file.
#   * pft         -- For which PFT should this correlation be considered? Set this value
#                    to 0 to apply the same correlation to all PFTs, or set it to the
#                    specific PFT for which the correlation should be applied. This is
#                    ignored when both parameter_a and parameter_b are global parameters,
#                    or both should be applied to all PFTs.
#   * org         -- For which organ should this correlation be considered? Set this value
#                    to 0 to apply the same correlation to all organs, or set it to the
#                    specific organ for which the correlation should be applied. This is
#                    ignored if neither parameter_a nor parameter_b are organ parameters.
#   * corr        -- Correlation between parameter_a and parameter_b.
#
# Example:
#
# No change in xml settings:
# cor_settings=()
#
# Changes in xml settings
# cor_settings=( "fates_leaf_vcmax25top       fates_alloc_storage_cushion  0  0 -0.5"
#                "fates_leaf_vcmax25top       fates_leaf_slatop            1  0  0.8"
#                "fates_leaf_vcmax25top       fates_leaf_slatop            2  0  0.4"
#                "fates_alloc_storage_cushion fates_leaf_slatop            0  0 -0.5")
#
# IMPORTANT: Unlike other settings, this cannot be empty. If not interested in running
#            ensemble runs, use the single-run script (create_case_hlm-fates.sh) instead.
#---~---
#               parameter_a                   parameter_b                    pft  organ     corr
cor_settings=( "fates_leaf_slamax             fates_leaf_slatop              0    NA        1"
               "fates_leaf_slamax             fates_stoich_nitr              0    1         0.31"
               "fates_leaf_slatop             fates_stoich_nitr              0    1         0.31")
#---~---



#---~---
#    Additional settings for the host land model namelist.  This is done in two steps:
#
# --------
#  Step 1
# --------
#    Define the output variables by setting variable "hlm_variables", which
# should have six entries:
# * variable  -- The variable name (case sensitive)
# * add_fates -- A flag to decide whether or not to include the variable based on whether or
#                not this is a FATES run. This is case insensitive. Possible options:
#                * yes  -- Add variable only when running FATES
#                * no   -- Add variable only when NOT running FATES
#                * both -- Add variable regardless of whether or not running FATES
# * add_hlm   -- List of the host land models (case insensitive) that can use the
#                variable. To list more than one model, use "+" as a separator.
# * monthly   -- Add the variable to monthly output? Use yes/no (case insensitive)
# * daily     -- Add the variable to daily output? Use yes/no (case insensitive)
# * hourly    -- Add the variable to hourly output? Use yes/no (case insenstive)
#
#    Alternatively, one can define the default list of variables by not changing the
# default variables. In this case, the code will only produce monthly output.  In this
# case, set hist_empty_tapes to .false. in hlm_settings (Step 2), otherwise the model
# will not write any output.
#
# Examples:
#
# No change in variable settings:
# hlm_variables=()
#
# List variables to be included:
# hlm_variables=("AR                          no    clm+elm yes yes yes"
#                "ELAI                      both    clm+elm yes yes  no"
#                "FATES_NPLANT_CANOPY_SZPF   yes    clm+elm yes  no  no")
#
# --------
#  Step 2
# --------
#   Define other namelist settings. This normally contains variable hist_empty_htapes,
# which decides whether or not to include the default variables.
#
# Example:
#
# No change in namelist settings:
# hlm_settings=()
#
# Changes in xml settings
# hlm_settings=("hist_empty_htapes  .true."
#               "fates_parteh_mode       1")
#---~---
#--- Step 1: Define output variables.
#               variable                               add_fates    add_hlm  monthly    daily   hourly"
hlm_variables=("AR                                            no    clm+elm      yes       no       no"
               "BTRAN                                       both    clm+elm      yes       no       no"
               "BTRANMN                                     both        clm      yes       no       no"
               "EFLX_SOIL_GRND                              both        clm      yes       no       no"
               "EFLX_LH_TOT                                 both    clm+elm      yes       no       no"
               "ELAI                                        both    clm+elm      yes       no       no"
               "ESAI                                        both    clm+elm      yes       no       no"
               "FATES_AGSAPMAINTAR_SZPF                      yes    clm+elm      yes       no       no"
               "FATES_AGSAPWOOD_ALLOC_SZPF                   yes    clm+elm      yes       no       no"
               "FATES_AGSTRUCT_ALLOC_SZPF                    yes    clm+elm      yes       no       no"
               "FATES_AUTORESP                               yes    clm+elm      yes       no       no"
               "FATES_AUTORESP_SZPF                          yes    clm+elm      yes       no       no"
               "FATES_BASALAREA_SZPF                         yes    clm+elm      yes       no       no"
               "FATES_BGSAPMAINTAR_SZPF                      yes    clm+elm      yes       no       no"
               "FATES_BGSAPWOOD_ALLOC_SZPF                   yes    clm+elm      yes       no       no"
               "FATES_BGSTRUCT_ALLOC_SZPF                    yes    clm+elm      yes       no       no"
#              "FATES_BURNFRAC                               yes    clm+elm      yes       no       no"
#              "FATES_BURNFRAC_AP                            yes    clm+elm      yes       no       no"
               "FATES_CANOPYAREA_AP                          yes    clm+elm      yes       no       no"
               "FATES_CANOPYAREA_HT                          yes    clm+elm      yes       no       no"
               "FATES_DAYSINCE_DROUGHTLEAFOFF                yes    clm+elm      yes       no       no"
               "FATES_DAYSINCE_DROUGHTLEAFON                 yes    clm+elm      yes       no       no"
               "FATES_DDBH_CANOPY_SZPF                       yes    clm+elm      yes       no       no"
               "FATES_DDBH_USTORY_SZPF                       yes    clm+elm      yes       no       no"
               "FATES_DEMOTION_RATE_SZ                       yes    clm+elm      yes       no       no"
               "FATES_DROUGHT_STATUS                         yes    clm+elm      yes       no       no"
               #"FATES_ELONG_FACTOR_PF                        yes    clm+elm      yes       no       no"
#               "FATES_FIRE_INTENSITY                         yes    clm+elm      yes       yes      no"
#               "FATES_FIRE_INTENSITY_BURNFRAC                yes    clm+elm      yes       yes      no"
#               "FATES_FUEL_BULKD                             yes    clm+elm      yes       yes      no"
               "FATES_FUEL_AMOUNT                            yes    clm+elm      yes       no       no"
               "FATES_FUEL_AMOUNT_FC                         yes    clm+elm      yes       no       no"
               "FATES_FUEL_AMOUNT_APFC                       yes    clm+elm      yes       no       no"
               "FATES_FUEL_MOISTURE_FC                       yes    clm+elm      yes       no       no"
               "FATES_FRAGMENTATION_SCALER_SL                yes    clm+elm      yes       no       no"
               "FATES_FROOT_ALLOC_SZPF                       yes    clm+elm      yes       no       no"
               "FATES_FROOTMAINTAR_SZPF                      yes    clm+elm      yes       no       no"
               "FATES_GPP                                    yes    clm+elm      yes       no       no"
               "FATES_GPP_AP                                 yes    clm+elm      yes       no       no"
               "FATES_GPP_SZPF                               yes    clm+elm      yes       no       no"
               "FATES_GROWAR_SZPF                            yes    clm+elm      yes       no       no"
               "FATES_HET_RESP                               yes    clm+elm      yes       no       no"
               "FATES_IGNITIONS                              yes    clm+elm      yes       no       no"
               "FATES_LAI_AP                                 yes    clm+elm      yes       no       no"
               "FATES_LAI_CANOPY_SZPF                        yes    clm+elm      yes       no       no"
               "FATES_LAI_USTORY_SZPF                        yes    clm+elm      yes       no       no"
               "FATES_LBLAYER_COND                           yes    clm+elm      yes       no       no"
               "FATES_LBLAYER_COND_AP                        yes    clm+elm      yes       no       no"
               "FATES_LEAF_ALLOC_SZPF                        yes    clm+elm      yes       no       no"
               "FATES_LEAFC_CANOPY_SZPF                      yes    clm+elm      yes       no       no"
               "FATES_LEAFC_USTORY_SZPF                      yes    clm+elm      yes       no       no"
               "FATES_LITTER_IN                              yes    clm+elm      yes       no       no"
               "FATES_LITTER_OUT                             yes    clm+elm      yes       no       no"
               "FATES_MEANLIQVOL_DROUGHTPHEN                 yes    clm+elm      yes       no       no"
#               "FATES_MEANSMP_DROUGHTPHEN_PF                 yes    clm+elm      yes       no       no"
               "FATES_MORTALITY_AGESCEN_SZPF                 yes    clm+elm      yes       no       no"
               "FATES_MORTALITY_BACKGROUND_SZPF              yes    clm+elm      yes       no       no"
               "FATES_MORTALITY_CANOPY_SZPF                  yes    clm+elm      yes       no       no"
               "FATES_MORTALITY_CSTARV_SZPF                  yes    clm+elm      yes       no       no"
               "FATES_MORTALITY_CSTARV_CFLUX_PF              yes    clm+elm      yes       no       no"
               "FATES_MORTALITY_CFLUX_CANOPY                 yes    clm+elm      yes       no       no"
               "FATES_MORTALITY_CFLUX_USTORY                 yes    clm+elm      yes       no       no"
#               "FATES_MORTALITY_CFLUX_PF                     yes    clm+elm      yes       no       no"
               "FATES_MORTALITY_FREEZING_SZPF                yes    clm+elm      yes       no       no"
               "FATES_MORTALITY_FIRE_SZPF                    yes    clm+elm      yes       no       no"
               "FATES_MORTALITY_FIRE_CFLUX_PF                yes    clm+elm      yes       no       no"
               "FATES_MORTALITY_HYDRAULIC_SZPF               yes    clm+elm      yes       no       no"
               "FATES_MORTALITY_HYDRAULIC_CFLUX_             yes    clm+elm      yes       no       no"
               "FATES_MORTALITY_IMPACT_SZPF                  yes    clm+elm      yes       no       no"
#               "FATES_MORTALITY_LOGGING_SZPF                 yes    clm+elm      yes       no       no"
               "FATES_MORTALITY_SENESCENCE_SZPF              yes    clm+elm      yes       no       no"
               "FATES_MORTALITY_TERMINATION_SZPF             yes    clm+elm      yes       no       no"
               "FATES_MORTALITY_USTORY_SZPF                  yes    clm+elm      yes       no       no"
               "FATES_NEP                                    yes    clm+elm      yes       no       no"
               "FATES_NPLANT_CANOPY_SZPF                     yes    clm+elm      yes       no       no"
               "FATES_NPLANT_USTORY_SZPF                     yes    clm+elm      yes       no       no"
               "FATES_NPP_SZPF                               yes    clm+elm      yes       no       no"
               "FATES_NPP_CANOPY_SZ                          yes    clm+elm      yes       no       no"
               "FATES_NPP_USTORY_SZ                          yes    clm+elm      yes       no       no"
               "FATES_PATCHAREA_AP                           yes    clm+elm      yes       no       no"
               "FATES_PROMOTION_RATE_SZ                      yes    clm+elm      yes       no       no"
               "FATES_RDARK_SZPF                             yes    clm+elm      yes       no       no"
               "FATES_RECRUITMENT_PF                         yes    clm+elm      yes       no       no"
#               "FATES_ROS                                    yes    clm+elm      yes       no       no"
               "FATES_SEED_ALLOC_SZPF                        yes    clm+elm      yes       no       no"
#               "FATES_SOILVWC_SL                             yes    clm+elm      yes       no       no"
               "FATES_STOMATAL_COND                          yes    clm+elm      yes       no       no"
               "FATES_STOMATAL_COND_AP                       yes    clm+elm      yes       no       no"
               "FATES_STORE_ALLOC_SZPF                       yes    clm+elm      yes       no       no"
               "FATES_STOREC_CANOPY_SZPF                     yes    clm+elm      yes       no       no"
               "FATES_STOREC_USTORY_SZPF                     yes    clm+elm      yes       no       no"
               "FATES_TRIMMING_CANOPY_SZ                     yes    clm+elm      yes       no       no"
               "FATES_TRIMMING_USTORY_SZ                     yes    clm+elm      yes       no       no"
               "FATES_VEGC_ABOVEGROUND                       yes    clm+elm      yes       no       no"
               "FATES_VEGC_ABOVEGROUND_SZPF                  yes    clm+elm      yes       no       no"
               "FIRE                                        both    clm+elm      yes       no       no"
               "FGR                                         both    clm+elm      yes       no       no"
               "FLDS                                        both    clm+elm      yes       no       no"
               "FSH                                         both    clm+elm      yes       no       no"
               "FSH_V                                       both    clm+elm      yes       no       no"
               "FSH_G                                       both    clm+elm      yes       no       no"
               "FSDS                                        both    clm+elm      yes       no       no"
               "FSR                                         both    clm+elm      yes       no       no"
               "GPP                                           no    clm+elm      yes       no       no"
               "HR                                            no    clm+elm      yes       no       no"
               "H2OSOI                                        yes       clm      yes       no       no"
               "NEP                                           no    clm+elm      yes       no       no"
               "PBOT                                        both    clm+elm      yes       no       no"
               "Q2M                                         both    clm+elm      yes       no       no"
               "QAF                                         both        clm      yes       no       no"
               "QBOT                                        both    clm+elm      yes       no       no"
               "QDIRECT_THROUGHFALL                         both        clm      yes       no       no"
               "QDRAI                                       both    clm+elm      yes       no       no"
               "QDRIP                                       both    clm+elm      yes       no       no"
               "QINTR                                       both    clm+elm      yes       no       no"
               "QOVER                                       both    clm+elm      yes       no       no"
               "QSOIL                                       both    clm+elm      yes       no       no"
               "Qtau                                        both        clm      yes       no       no"
               "QVEGE                                       both    clm+elm      yes       no       no"
               "QVEGT                                       both    clm+elm      yes       no       no"
               "RAIN                                        both    clm+elm      yes       no       no"
               "SMP                                         both    clm+elm      yes       no       no"
               "SOILPSI                                     both        clm      yes       no       no"
               "TAF                                         both        clm      yes       no       no"
               "TBOT                                        both    clm+elm      yes       no       no"
               "TG                                          both    clm+elm      yes       no       no"
               "TLAI                                        both    clm+elm      yes       no       no"
               "TREFMNAV                                    both    clm+elm      yes       no       no"
               "TREFMXAV                                    both    clm+elm      yes       no       no"
               "TSA                                         both    clm+elm      yes       no       no"
               "TSAI                                        both    clm+elm      yes       no       no"
               "TSOI                                        both    clm+elm      yes       no       no"
               "TV                                          both    clm+elm      yes       no       no"
               "U10                                         both    clm+elm      yes       no       no"
               "UAF                                         both        clm      yes       no       no"
               "USTAR                                       both        clm      yes       no       no"
               "ZWT                                         both    clm+elm      yes       no       no"
               "ZWT_PERCH                                   both    clm+elm      yes       no       no")
#--- Step 2: Additional namelist settings.
hlm_settings=("hist_empty_htapes    .true.")
#---~---


#-------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------
#                  CHANGES BEYOND THIS POINT ARE FOR SCRIPT DEVELOPMENT ONLY!
#-------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------



#---~---
#  Define the host Earth System Model from upper-case CIME_MODEL.
#---~---
export HESM=$(echo ${HESM} | tr '[:lower:]' '[:upper:]')
#---~---

#--- Update cade and simulation paths, in case a generic name was provided.
export WORK_PATH=$(echo ${WORK_PATH}           | sed s@"XXXX"@"${HESM}"@g)
export CASE_ROOT=$(echo ${CASE_ROOT}           | sed s@"XXXX"@"${HESM}"@g)
export SIMUL_ROOT=$(echo ${SIMUL_ROOT}         | sed s@"XXXX"@"${HESM}"@g)
#---~---

#--- Current date.
export TODAY=$(date +"%Y-%m-%d")
#---~---

#--- Path of the main script
export SOURCE_PATH=$(dirname ${BASH_SOURCE})
export SOURCE_PATH=$(cd ${SOURCE_PATH}; pwd)
export SOURCE_BASE="$(basename ${BASH_SOURCE})"
#---~---


#---~---
#   Check if cluster settings make sense (only if running in a HPC environment.
#---~---
case "${MACH}" in
cori-*|cheyenne)
   #---~---
   #   cori-haswell and cori-knl (NERSC). Set up some global SLURM information.
   #---~---
   case "${MACH}" in
   cori-haswell)
      export N_NODES_MAX=60
      export MAX_CPUS_PER_TASK=32
      export MAX_TASKS_PER_NODE=32
      export RUN_TIME_MAX="96:00:00"
      export CONSTRAINT="haswell"
      ;;
   cori-knl)
      export N_NODES_MAX=300
      export MAX_CPUS_PER_TASK=64
      export MAX_TASKS_PER_NODE=128
      export RUN_TIME_MAX="96:00:00"
      export CONSTRAINT="knl"
      ;;
   cheyenne)
     export N_NODES_MAX=4032
     export MAX_CPUS_PER_TASK=36
     export MAX_TASKS_PER_NODE=36
     export RUN_TIME_MAX="12:00:00"
      ;;
    esac
   #---~---
 
#---~---
   #---~---
   #   Set the default partition in case it is not provided.
   #---~---
   if [[ "${PARTITION}" == "" ]]
   then
      export PARTITION="regular"
   fi
   #---~---


   #---~---
   #   Do not let account to be undefined
   #---~---
   if [[ "${PROJECT}" == "" ]]
   then
      echo " Variable \"PROJECT\" ought to be defined if using cori-haswell or cori-knl or cheyenne!"
      exit 59
   fi
   #---~---


   #---~---
   #   Check that CPU requests are reasonable
   #---~---
   if [[ ${CPUS_PER_TASK} -gt ${MAX_CPUS_PER_TASK} ]]
   then
      echo " Too many CPUs per task requested:"
      echo " Machine                 = ${MACH}"
      echo " Maximum CPUs per task   = ${MAX_CPUS_PER_TASK}"
      echo " Requested CPUs per task = ${CPUS_PER_TASK}"
      exit 99
   else
      #--- Find maximum number of tasks allowed
      (( N_TASKS_MAX = N_NODES_MAX * CPUS_PER_NODE ))
      (( N_TASKS_MAX = N_TASKS_MAX / CPUS_PER_TASK ))
      #---~---
   fi
   #---~---


   #---~---
   #   Check time requests
   #---~---
   export RUN_TIME=$(echo     ${RUN_TIME}     | tr '[:upper:]' '[:lower:]')
   export RUN_TIME_MAX=$(echo ${RUN_TIME_MAX} | tr '[:upper:]' '[:lower:]')
   case "${RUN_TIME}" in
   infinite)
      #---~---
      #   Infinite run time.  Make sure the queue supports this type of submission.
      #---~---
      case "${RUN_TIME_MAX}" in
      infinite)
         echo "" > /dev/null
         ;;
      *)
         echo " Machine:                    ${MACH}"
         echo " Maximum run time permitted: ${RUN_TIME_MAX}"
         echo " Requested run time:         ${RUN_TIME}"
         echo " This cluster does not support infinite time."
         exit 91
         ;;
      esac
      #---~---
      ;;
   *)
      #---~---
      #   Find out the format provided.
      #---~---
      case "${RUN_TIME}" in
      *-*:*:*|*-*:*)
         #--- dd-hh:mm:ss.
         ndays=$(echo ${RUN_TIME}  | sed s@"-.*$"@@g)
         nhours=$(echo ${RUN_TIME} | sed s@"^[0-9]\+-"@@g | sed s@":.*"@@g)
         nminutes=$(echo ${RUN_TIME} | sed s@"^[0-9]\+-[0-9]\+:"@@g | sed s@":.*$"@@g)
         #---~---
         ;;
      *:*:*)
         #--- hh:mm:ss.
         ndays=0
         nhours=$(echo ${RUN_TIME} | sed s@":.*"@@g)
         nminutes=$(echo ${RUN_TIME} | sed s@"^[0-9]\+:"@@g | sed s@":.*"@@g)
         #---~---
         ;;
      *:*)
         #--- hh:mm:ss.
         ndays=0
         nhours=0
         nminutes=$(echo ${RUN_TIME} | sed s@":.*$"@@g)
         #---~---
         ;;
      *)
         #--- Hours.
         (( ndays  = RUN_TIME / 24 ))
         (( nhours = RUN_TIME % 24 ))
         nminutes=0
         #---~---
         ;;
      esac
      #---~---


      #---~---
      #   Find the walltime in hours, and the run time in nice format.
      #---~---
      (( wall     = nminutes + 60 * nhours + 1440 * ndays ))
      (( nhours   = wall / 60 ))
      (( nminutes = wall % 60 ))
      fmthr=$(printf '%.2i' ${nhours})
      fmtmn=$(printf '%2.2i' ${nminutes})
      RUN_TIME="${fmthr}:${fmtmn}:00"
      #---~---



      #---~---
      #   Find the maximum number of hours allowed in the partition.
      #---~---
      case "${RUN_TIME_MAX}" in
      infinite)
         (( ndays_max    = ndays + 1 ))
         (( nhours_max   = nhours    ))
         (( nminutes_max = nminutes  ))
         #---~---
         ;;
      *-*:*:*|*-*:*)
         #--- dd-hh:mm:ss.
         ndays_max=$(echo ${RUN_TIME_MAX}  | sed s@"-.*"@@g)
         nhours_max=$(echo ${RUN_TIME_MAX} | sed s@"^[0-9]\+-"@@g | sed s@":.*"@@g)
         nminutes_max=$(echo ${RUN_TIME_MAX} | sed s@"^[0-9]\+-[0-9]\+:"@@g | sed s@":.*$"@@g)
         #---~---
         ;;
      *:*:*)
         #--- hh:mm:ss.
         ndays_max=0
         nhours_max=$(echo ${RUN_TIME_MAX}   | sed s@":.*"@@g)
         nminutes_max=$(echo ${RUN_TIME_MAX} | sed s@"^[0-9]\+:"@@g | sed s@":.*"@@g)
         #---~---
         ;;
      *:*)
         #--- hh:mm:ss.
         ndays_max=0
         nhours_max=0
         nminutes_max=$(echo ${RUN_TIME_MAX} | sed s@":.*$"@@g)
         #---~---
         ;;
      *)
         #--- Hours.
         (( ndays_max  = RUN_TIME_MAX / 24 ))
         (( nhours_max = RUN_TIME_MAX % 24 ))
         nminutes_max=0
         #---~---
         ;;
      esac
      (( wall_max = nminutes_max + 60 * nhours_max + 1440 * ndays_max ))
      #---~---


      #---~---
      #   Check requested walltime and the availability.
      #---~---
      if [[ ${wall} -gt ${wall_max} ]]
      then
         echo " Machine:                    ${MACH}"
         echo " Maximum run time permitted: ${RUN_TIME_MAX}"
         echo " Requested run time:         ${RUN_TIME}"
         echo " - Requested time exceeds limits."
         exit 92
      fi
      #---~---
      ;;
   esac
   #---~---




   #---~---
   #   Make sure number of ensemble members per node does not exceed the maximum number
   # of tasks per node.
   #---~---
   (( N_CPUS             = N_ENSEMBLE         * CPUS_PER_TASK ))
   (( MAX_TASKS_PER_NODE = MAX_TASKS_PER_NODE / CPUS_PER_TASK ))

   if [[ ${TASKS_PER_NODE} -gt ${MAX_TASKS_PER_NODE} ]]
   then
      echo " Machine:                                             ${MACH}"
      echo " CPUs per task:                                       ${CPUS_PER_TASK}"
      echo " Requested tasks per node (ensemble members per job): ${TASKS_PER_NODE}"
      echo " Maximum number of tasks per node:                    ${MAX_TASKS_PER_NODE}"
      echo " - Requested tasks per node exceeds limits."
      exit 94
   elif [[ ${TASKS_PER_NODE} -eq 0 ]]
   then
      N_TASKS=${MAX_TASKS_PER_NODE}
   else
      N_TASKS=${TASKS_PER_NODE}
   fi
   (( N_NODES=(N_ENSEMBLE+N_TASKS-1)/N_TASKS ))
   #---~---


   #---~---
   #    Print configurations
   #---~---
   echo ""
   echo ""
   echo "--------------------------------------------------"
   echo "   Ensemble requests."
   echo "--------------------------------------------------"
   echo " N_ENSEMBLE           = ${N_ENSEMBLE}"
   echo " N_CPUS               = ${N_CPUS}"
   echo " N_TASKS (PER NODE)   = ${N_TASKS}"
   echo " N_NODES (N_JOBS)     = ${N_NODES}"
   echo " CPUS_PER_TASK        = ${CPUS_PER_TASK}"
   echo " RUN_TIME             = ${RUN_TIME}"
   echo "--------------------------------------------------"
   echo ""
   echo ""
   #---~---

   ;;
esac


#---~---
#   Find number of digits for formatting ensemble numbers
#---~---
LOG10_N_ENSEMBLE="l(${N_ENSEMBLE})/l(10)"
LOG10_N_NODES="l(${N_NODES})/l(10)"
LOG10_N_TASKS="l(${N_TASKS})/l(10)"
LOG10_N_ENSEMBLE=$(printf '%.0f' $(echo "${LOG10_N_ENSEMBLE}" | bc -l))
LOG10_N_NODES=$(printf    '%.0f' $(echo "${LOG10_N_NODES}"    | bc -l))
LOG10_N_TASKS=$(printf    '%.0f' $(echo "${LOG10_N_TASKS}"    | bc -l))
(( ENS_DIGITS  = 1 + LOG10_N_ENSEMBLE ))
(( NODE_DIGITS = 1 + LOG10_N_NODES    ))
(( TASK_DIGITS = 1 + LOG10_N_TASKS    ))
export ENS_FMT="%${ENS_DIGITS}.${ENS_DIGITS}i"
export NODE_FMT="%${NODE_DIGITS}.${NODE_DIGITS}i"
export TASK_FMT="%${TASK_DIGITS}.${TASK_DIGITS}i"
#---~---


#---~---
#   Make changes to some of the settings based on the host model.
#---~---
case "${HESM}" in
E3SM)
   #---~---
   # E3SM-FATES
   #---~---

   #--- Set CIME model.
   export CIME_MODEL="e3sm"
   #---~---

   #--- Set host land model. Set both upper case and lower case for when needed.
   export hlm="elm"
   export HLM="ELM"
   #---~---

   #--- Main path for host model
   export HOSTMODEL_PATH=$(dirname $(dirname ${WORK_PATH}))
   #---~---

   #--- Additional options for "create_newcase"
   export NEWCASE_OPTS=""
   #---~---

   #--- Main source path for FATES.
   export FATES_SRC_PATH="${HOSTMODEL_PATH}/components/elm/src/external_models/fates"
   #---~---

   #--- In case compilation settings are not defined, use the default settings.
   if [[ "${COMP}" == "" ]]
   then
      export COMP="IELMFATES"
   fi
   #---~---

   ;;
CTSM|CESM)
   #---~---
   # CESM-FATES or CTSM-FATES
   #---~---

   #--- Set CIME model.
   export CIME_MODEL="cesm"
   #---~---

   #--- Set host land model. Set both upper case and lower case for when needed.
   export hlm="clm"
   export HLM="CLM"
   #---~---


   #--- Main path for host model
   export HOSTMODEL_PATH=$(dirname $(dirname ${WORK_PATH}))
   #---~---

   #--- Additional options for "create_newcase"
   export NEWCASE_OPTS="--run-unsupported"
   #---~---

   #--- Main source path for FATES.
   export FATES_SRC_PATH="${HOSTMODEL_PATH}/src/fates"
   #---~---


   #--- In case compilation settings are not defined, use the default settings.
   if [[ "${COMP}" == "" ]]
   then
      export COMP="I2000Clm51FatesRs"
   fi
   #---~---

   ;;
esac
#---~---


#--- Define version of host model and FATES
export HLM_HASH="${HLM}-$(cd ${HOSTMODEL_PATH};   git log -n 1 --pretty=%h)"
export FATES_HASH="FATES-$(cd ${FATES_SRC_PATH}; git log -n 1 --pretty=%h)"
#---~---


#--- Define setting for single-point
export V_HLM_USRDAT_NAME="${HLM}_USRDAT_NAME"
export V_HLM_NAMELIST_OPTS="${HLM}_NAMELIST_OPTS"
#---~---


#--- Substitute wildcards in the resolution with the actual model
export RESOL=$(echo "${RESOL}" | sed s@"YYY"@"${HLM}"@g | sed s@"yyy"@"${hlm}"@g)
#---~---




#---~---
#   Retrieve site information.
#---~---
site_success=false
for i in ${!SITE_INFO[*]}
do
   site_now=${SITE_INFO[i]}
   export SITE_ID=$(echo ${site_now}   | awk '{print $1}')

   if [[ ${SITE_ID} -eq ${SITE_USE} ]]
   then
      # Load data and flag that we found the site information.
      export SITE_DESC=$(echo ${site_now}       | awk '{print $2}')
      export SITE_NAME=$(echo ${site_now}       | awk '{print $3}')
      export SITE_START_DATE=$(echo ${site_now} | awk '{print $4}')
      export SITE_STOP_N=$(echo ${site_now}     | awk '{print $5}')
      export SITE_DATM_FIRST=$(echo ${site_now} | awk '{print $6}')
      export SITE_DATM_LAST=$(echo ${site_now}  | awk '{print $7}')
      export SITE_CALENDAR=$(echo ${site_now}   | awk '{print $8}')

      #--- Append site settings to xml_settings.
      xml_settings+=("RUN_STARTDATE         ${SITE_START_DATE}"
                     "STOP_N                ${SITE_STOP_N}    "
                     "DATM_YR_START ${SITE_DATM_FIRST}"
                     "DATM_YR_END   ${SITE_DATM_LAST} ")
      #---~---

      #---~---
      #   Set derived quantities.
      #---~---
      # Site path.
      export SITE_PATH="${SITE_BASE_PATH}/${SITE_NAME}"
      # Domain file (it must be in the SITE_NAME sub-directory).
      #export HLM_USRDAT_DOMAIN="domain.lnd.${SITE_NAME}_navy.nc"
      # Surface data file (it must be in the SITE_NAME sub-directory).
      export HLM_USRDAT_SURDAT="surfdata_1x1pt-US-Var_v15-5_c20210819_originalfile.nc"
      #---~---


      #--- Update status and exit loop.
      site_success=true
      break
      #---~---
   fi
done
#---~---




#---~---
#   Retrieve configuration information.
#---~---
config_success=false
export CONFIG_ID_MAX=0
for i in ${!CONFIG_INFO[*]}
do
   config_now=${CONFIG_INFO[i]}
   export CONFIG_ID=$(echo ${config_now}   | awk '{print $1}')

   if [[ ${CONFIG_ID} -eq ${CONFIG_USE} ]]
   then
      # Load data and flag that we found the configuration information.
      export CONFIG_DESC=$(echo ${config_now}   | awk '{print $2}')
      export INV_SUFFIX=$(echo ${config_now}    | awk '{print $3}')
      export DDPHEN_MODEL=$(echo ${config_now}  | awk '{print $4}')
      export FATES_HYDRO=$(echo ${config_now}   | awk '{print $5}')
      export FATES_FIRE=$(echo ${config_now}    | awk '{print $6}')


      #--- Update settings as needed.
      prm_settings+=("fates_phen_drought_model   0   ${DDPHEN_MODEL}")
      hlm_settings+=("use_fates_planthydro           ${FATES_HYDRO} ")
      hlm_settings+=("fates_spitfire_mode            ${FATES_FIRE}  ")
      #---~---


      #--- Configuration was successful but keep looping to find the maximum ID.
      config_success=true
      #---~---
   fi


   #--- Update maximum ID
   if [[ ${CONFIG_ID} -gt ${CONFIG_ID_MAX} ]]
   then
      export CONFIG_ID_MAX=${CONFIG_ID}
   fi
   #---~---

done
#---~---



#---~---
#   Check for success. In case so, set additional variables that may depend on both
# site and configuration information. Otherwise, stop the shell.
#---~---
if ${site_success} && ${config_success}
then
   #---~---
   #   Set default case prefix
   #---~---
   (( SIMUL_ID = CONFIG_ID_MAX * SITE_USE - CONFIG_ID_MAX + CONFIG_USE ))
   export SIMUL_LABEL="$(printf '%4.4i' ${SIMUL_ID})"
   if [[ "${CASE_PREFIX}" == "" ]]
   then
      export CASE_PREFIX="S${SIMUL_LABEL}_${SITE_DESC}_${CONFIG_DESC}"
   fi
   #---~---



   #---~---
   #    In case the inventory/lidar initialisation is sought, provide the file name of the
   # control file specification (the control file should be in the
   # SITE_NAME sub-directory). Otherwise, do not set this variable (INVENTORY_BASE="")
   #
   #  For additional information, check
   # https://github.com/NGEET/fates/wiki/Model-Initialization-Modes#Inventory_Format_Type_1
   #---~---
   case "${INV_SUFFIX}" in
   NA|Na|na|NA)
      export INVENTORY_BASE=""
      ;;
   *)
      export INVENTORY_BASE="${SITE_NAME}_${INV_SUFFIX}.txt"
      ;;
   esac
   #---~---
else
   #---~---
   #   Settings were incorrect, stop the run.
   #---~---
   echo " "
   echo "---~---"
   echo " Invalid site and/or configuration settings:"
   echo ""
   echo " + SITE_USE : ${SITE_USE}"
   echo " + CONFIG_USE : ${CONFIG_USE}"
   echo ""
   echo " + Site settings failed : ${site_failed}"
   echo " + Model configuration settings failed : ${config_failed}"
   echo ""
   echo " Make sure that variables \"SITE_USE\" and \"CONFIG_USE\" are set to a value."
   echo "    listed in columns \"site_id\" of array \"SITE_INFO\", and \"config_id\" of"
   echo "    array \"CONFIG_INFO\", respectively."
   echo "---~---"
   exit 91
   #---~---
fi
#---~---


#---~---
#   Append github commit hash, or a simple host-model / FATES tag.
#---~---
if ${APPEND_GIT_HASH}
then
   export CASE_NAME="${CASE_PREFIX}_${HLM_HASH}_${FATES_HASH}"
else
   export CASE_NAME="${CASE_PREFIX}_${HLM}_FATES"
fi
#---~---


#---~---
#    Set paths for case and simulation.
#---~---
export CASE_PATH="${CASE_ROOT}/${CASE_NAME}"
export SIMUL_PATH="${SIMUL_ROOT}/${CASE_NAME}"
#---~---



#---~---
#  In case the case exists, warn user before assuming it's fine to delete files.
#---~---
if [[ -s ${CASE_PATH} ]] || [[ -s ${SIMUL_PATH} ]]
then
   #---~---
   #    Check with user if it's fine to delete existing case.
   #---~---
   echo    " Case directories (${CASE_NAME}) already exist, proceeding will delete them."
   echo -n " Proceed (y|N)?   "
   read proceed
   proceed=$(echo ${proceed} | tr '[:upper:]' '[:lower:]')
   #---~---


   #---~---
   #    We give one last chance for users to cancel before deleting the files.
   #---~---
   case "${proceed}" in
   y|yes)
      echo "---------------------------------------------------------------------"
      echo " FINAL WARNING!"
      echo " I will start deleting files in 5 seconds."
      echo " In case you change your mind, press Ctrl+C before the time is over."
      echo "---------------------------------------------------------------------"
      when=6
      echo -n " - "
      while [[ ${when} -gt 1 ]]
      do
         (( when = when - 1 ))
         echo -n " ${when}..."
         sleep 1
      done
      echo " Time is over!"



      #--- Delete files.
      /bin/rm -rvf ${CASE_PATH} ${SIMUL_PATH}
      #---~---

      ;;
   *)
      echo " - Script interrupted, files were kept."
      exit 0
      ;;
   esac
   #---~---
fi
#---~---



#---~---
#   Create basal directory for case and simulation.
#---~---
mkdir -p ${CASE_PATH}
mkdir -p ${SIMUL_PATH}
#---~---



#---~---
#   Define files and paths useful for the R script.
#---~---
export PARSET_PATH="${CASE_PATH}/ParamSettings"
export PARSET_BASE="ParamSet_${CASE_NAME}.csv"
export PARSET_FILE="${PARSET_PATH}/${PARSET_BASE}"
export NCDF4_OUT_PATH="${CASE_PATH}/EnsembleNetCDF"
export NCDF4_OUT_PREF="fates_params_${CASE_PATH}_ens"
#---~---


#--- Find base name to decide the parameter file path.
export FATES_PARAMS_BASE=$(basename "${FATES_PARAMS_FILE}")
#---~---

#--- Identify original parameter file
if [[ "${FATES_PARAMS_BASE}" == "" ]]
then
   FATES_PARAMS_ORIG="${FATES_SRC_PATH}/parameter_files/fates_params_default.cdl"
elif [[ "${FATES_PARAMS_BASE}" == "${FATES_PARAMS_FILE}" ]]
then
   FATES_PARAMS_ORIG="${SITE_PATH}/${FATES_PARAMS_BASE}"
else
   FATES_PARAMS_ORIG="${FATES_PARAMS_FILE}"
fi
#---~---


#--- Create a local parameter file.
echo " + Create local parameter file from $(basename ${FATES_PARAMS_ORIG})."
export FATES_PNETCDF_PATH="${CASE_PATH}/DefaultParamSet"
export FATES_PNETCDF_BASE="fates_params_${CASE_NAME}.nc"
export FATES_PNETCDF_CASE="${FATES_PNETCDF_PATH}/${FATES_PNETCDF_BASE}"
mkdir -p ${FATES_PNETCDF_PATH}
ncgen -o ${FATES_PNETCDF_CASE} ${FATES_PARAMS_ORIG}
#---~---


#---~---
#   Check whether or not to edit parameters
#---~---
if [[ ${#prm_settings[*]} -gt 0 ]]
then

   #--- Set python script for updating parameters.
   MODIFY_PARAMS_PY="${FATES_SRC_PATH}/tools/modify_fates_paramfile.py"
   #---~---
module load conda

   #--- Loop through the parameters to update.
   echo " + Create local parameter file."
   for p in ${!prm_settings[*]}
   do
      #--- Retrieve settings.
      prm_var=$(echo ${prm_settings[p]} | awk '{print $1}')
      prm_num=$(echo ${prm_settings[p]} | awk '{print $2}')
      prm_val=$(echo ${prm_settings[p]} | awk '{print $3}')
      #---~---


      #--- Update parameters, skipping the PFT setting in case it is zero (global).
      case ${prm_num} in
      0)
         conda run -n py3.9 ${MODIFY_PARAMS_PY} --var=${prm_var} --value=${prm_val}                        \
            --fin ${FATES_PNETCDF_CASE} --fout ${FATES_PNETCDF_CASE} --O
         ;;
      *)
         conda run -n py3.9 ${MODIFY_PARAMS_PY} --var=${prm_var} --pft=${prm_num} --value=${prm_val}       \
            --fin ${FATES_PNETCDF_CASE} --fout ${FATES_PNETCDF_CASE} --O
         ;;
      esac
      #---~---
   done
   #---~---
fi
#---~---
module unload conda
module load python/3.7.9

#---~---
#   Generate ensemble instructions.
#---~---
if [[ ${#ens_settings[*]} -gt 0 ]]
then
   #--- Create path for parameter settings
   mkdir -p ${PARSET_PATH}
   #---~---

   #--- Append header.
   parset_header="parameter,value_min,value_max,pft,organ"
   echo ${parset_header} > ${PARSET_FILE}
   #---~---

   #---~---
   #    Add instructions.
   #---~---
   for p in ${!ens_settings[*]}
   do
      #--- Append ensemble, replacing consecutive spaces with a single comma
      echo ${ens_settings[p]} | tr -s ' ' ',' >> ${PARSET_FILE}
      #---~---
   done
   #---~---

   #---~---
   #   Define path and prefix of the ensemble parameter files.
   #---~---
   export FATES_ENSEMBLE_PATH="${CASE_PATH}/EnsembleParamSet"
   export FATES_ENSEMBLE_PREF="fates_params_${CASE_NAME}"
   #---~---


else
   #---~---
   #   Ensemble settings cannot be empty for an ensemble simulation...
   #---~---
   echo " Variable \"ens_settings\" is empty. This is not acceptable for an ensemble run."
   exit 99
   #---~---
fi
#---~---



#---~---
#   Generate parameter correlation instructions.
#---~---
if [[ ${#cor_settings[*]} -gt 0 ]]
then
   #--- Define name for parameter correlation instructions.
   export PARCORR_BASE="ParamCorr_${CASE_NAME}.csv"
   export PARCORR_FILE="${PARSET_PATH}/${PARCORR_BASE}"
   #---~---


   #--- Create path for parameter settings
   mkdir -p ${PARSET_PATH}
   #---~---

   #--- Append header.
   parcorr_header="parameter_a,parameter_b,pft,organ,corr"
   echo ${parcorr_header} > ${PARCORR_FILE}
   #---~---

   #---~---
   #    Add instructions.
   #---~---
   for p in ${!cor_settings[*]}
   do
      #--- Append ensemble, replacing consecutive spaces with a single comma
      echo ${cor_settings[p]} | tr -s ' ' ',' >> ${PARCORR_FILE}
      #---~---
   done
   #---~---
else
   #---~---
   #   Skip parameter correlation...
   #---~---
   export PARCORR_BASE=""
   #---~---
fi
#---~---





#---~---
#   Create a local copy of the R script, in which we will update parameters.
#---~---
echo " + Prepare R script for generating ensemble paramater sets."
case "$(dirname ${ENS_R_TEMPLATE})" in
   .) ENS_R_TEMPLATE="${SOURCE_PATH}/${ENS_R_TEMPLATE}" ;;
esac
ENS_R_SCRIPT="${CASE_PATH}/Ensemble_Param_${CASE_NAME}.r"
/bin/cp -f ${ENS_R_TEMPLATE} ${ENS_R_SCRIPT}
#---~---


#---~---
#   Update R script with this case settings
#---~---
wcbef="^[ \t]*"
wcaft="[ \t]*\\=\(.*\)$"
#--- Define replacement
work_path_ln="work_path      = \"${CASE_PATH}\""
parset_path_ln="parset_path    = \"${PARSET_PATH}\""
parset_base_ln="parset_base    = \"${PARSET_BASE}\""
if [[ "${PARCORR_BASE}" == "" ]]
then
   parcorr_base_ln="parcorr_base   = NA_character_"
else
   parcorr_base_ln="parcorr_base   = \"${PARCORR_BASE}\""
fi
ncdf4_in_path_ln="ncdf4_in_path  = \"${FATES_PNETCDF_PATH}\""
ncdf4_in_base_ln="ncdf4_in_base  = \"${FATES_PNETCDF_BASE}\""
ncdf4_out_path_ln="ncdf4_out_path = \"${FATES_ENSEMBLE_PATH}\""
ncdf4_out_pref_ln="ncdf4_out_pref = \"${FATES_ENSEMBLE_PREF}\""
n_ensemble_ln="n_ensemble     = ${N_ENSEMBLE}"
tasks_per_node_ln="tasks_per_node = ${N_TASKS}"
sample_method_ln="sample_method  = \"${SAMPLE_METHOD}\""
seed_init_ln="seed_init      = ${SEED_INIT}"
lhs_eps_ln="lhs_eps        = ${LHS_EPS}"
lhs_maxit_ln="lhs_maxIt      = ${LHS_MAXIT}"
#--- Edit R script
sed -i".bck" s@"${wcbef}work_path${wcaft}"@"${work_path_ln}"@g           ${ENS_R_SCRIPT}
sed -i".bck" s@"${wcbef}parset_path${wcaft}"@"${parset_path_ln}"@g       ${ENS_R_SCRIPT}
sed -i".bck" s@"${wcbef}parset_base${wcaft}"@"${parset_base_ln}"@g       ${ENS_R_SCRIPT}
sed -i".bck" s@"${wcbef}parcorr_base${wcaft}"@"${parcorr_base_ln}"@g     ${ENS_R_SCRIPT}
sed -i".bck" s@"${wcbef}ncdf4_in_path${wcaft}"@"${ncdf4_in_path_ln}"@g   ${ENS_R_SCRIPT}
sed -i".bck" s@"${wcbef}ncdf4_in_base${wcaft}"@"${ncdf4_in_base_ln}"@g   ${ENS_R_SCRIPT}
sed -i".bck" s@"${wcbef}ncdf4_out_path${wcaft}"@"${ncdf4_out_path_ln}"@g ${ENS_R_SCRIPT}
sed -i".bck" s@"${wcbef}ncdf4_out_pref${wcaft}"@"${ncdf4_out_pref_ln}"@g ${ENS_R_SCRIPT}
sed -i".bck" s@"${wcbef}n_ensemble${wcaft}"@"${n_ensemble_ln}"@g         ${ENS_R_SCRIPT}
sed -i".bck" s@"${wcbef}tasks_per_node${wcaft}"@"${tasks_per_node_ln}"@g ${ENS_R_SCRIPT}
sed -i".bck" s@"${wcbef}seed_init${wcaft}"@"${seed_init_ln}"@g           ${ENS_R_SCRIPT}
sed -i".bck" s@"${wcbef}lhs_eps${wcaft}"@"${lhs_eps_ln}"@g               ${ENS_R_SCRIPT}
sed -i".bck" s@"${wcbef}lhs_maxIt${wcaft}"@"${lhs_maxit_ln}"@g           ${ENS_R_SCRIPT}
/bin/rm -f "${ENS_R_SCRIPT}.bck"
#---~---


#---~---
#   Run R to generate the ensemble files
#---~---
echo " + Run R script to generate ensemble paramater sets."
export RSCRIPT="/glade/work/xiugao/conda-envs/py3.9/bin/Rscript"
ENS_R_LOGFILE="${CASE_PATH}/Ensemble_Param_${CASE_NAME}.log"
${RSCRIPT} --no-restore --no-save ${ENS_R_SCRIPT} | tee ${ENS_R_LOGFILE}
SUCCESS_MESSAGE="SUCCESS! All ensemble parameter files were created!"
success=$(grep "${SUCCESS_MESSAGE}" ${ENS_R_LOGFILE} | wc -l | xargs)
if [[ ${success} -eq 0 ]]
then
   echo " R script failed. Check your input settings and the log file: "
   echo " cat ${ENS_R_LOGFILE}"
   exit 99
fi
#---~---



#---~---
#   To generate ensemble cases, we loop through nodes.  The idea is to have a series of
# single-node jobs with multiple tasks (ensemble members) in each of them.
#---~---
#export N_NODES=1
#export N_TASKS=36
NODE_CNT=0
while [[ ${NODE_CNT} -lt ${N_NODES} ]]
do
   (( NODE_CNT = NODE_CNT + 1 ))

   #---~---
   #   Set node (job) names.
   #---~---
   NODE_LABEL=$(printf "${NODE_FMT}" ${NODE_CNT})
   NODE_NAME="${CASE_PREFIX}_Node${NODE_LABEL}"
   export CASE_PATH_NODE="${CASE_PATH}/${NODE_NAME}"
   export SIMUL_PATH_NODE="${SIMUL_PATH}/${NODE_NAME}"
   echo " + ${NODE_LABEL}/${N_NODES}: Create case ${NODE_NAME}."
   #---~---



   #---~---
   #   Define how many tasks this job will run. This will be either the nominal number
   # of tasks per node, or the number of remaining tasks in case the number of ensemble
   # members is not an exact multiple of the number of tasks per node
   #---~---
   (( A_ENSEMBLE = 1 + ( NODE_CNT - 1 ) * N_TASKS ))
   (( Z_ENSEMBLE = A_ENSEMBLE + N_TASKS - 1       ))
   if [[ ${Z_ENSEMBLE} -gt ${N_ENSEMBLE} ]]
   then
      Z_ENSEMBLE=${N_ENSEMBLE}
   fi
   (( NODE_TASKS = Z_ENSEMBLE - A_ENSEMBLE + 1    ))
   echo "   - This will be a ${NODE_TASKS}-task job, running on a single node."
   echo "   - Ensemble members included in job: ${A_ENSEMBLE}-${Z_ENSEMBLE}."
   #---~---



   #--- Namelists for the host land model.
   export USER_NL_HLM_PREF="${CASE_PATH_NODE}/user_nl_${hlm}"
   export USER_NL_DATM_PREF="${CASE_PATH_NODE}/user_nl_datm_streams"
   #---~---


   #---~---
   #    Move to the main cime path then create the new case
   #---~---
   echo "   - Initialise case for this single-node job."
   cd ${WORK_PATH}
   ./create_newcase --case=${CASE_PATH_NODE} --res=${RESOL} --compset=${COMP}              \
      --mach=${MACH} --project=${PROJECT} ${NEWCASE_OPTS} --ninst=${NODE_TASKS}            \
      --multi-driver   --silent
   #---~---


   #---~---
   #     Set the CIME output to the main CIME path.
   #---~---
   echo "   - Update output paths and job run time."
   cd ${CASE_PATH_NODE}
   ./xmlchange CIME_OUTPUT_ROOT="${SIMUL_PATH}"
   ./xmlchange DOUT_S_ROOT="${SIMUL_PATH_NODE}"
   ./xmlchange PIO_DEBUG_LEVEL="${DEBUG_LEVEL}"
   ./xmlchange JOB_WALLCLOCK_TIME="${RUN_TIME}" --subgroup case.run
   ./xmlchange JOB_QUEUE="${PARTITION}"
   #---~---


   #---~---
   #     In case this is a user-defined site simulation, set the user-specified paths.
   # DATM_MODE must be set to CLM1PT, even when running E3SM-FATES.
   #---~---
   cd ${CASE_PATH_NODE}
   case "${RESOL}" in
   ?LM_USRDAT)
      echo "   - Update paths for surface and domain files."

      # Append site-specific surface data information to the namelist.
      HLM_SURDAT_FILE="${SITE_PATH}/${HLM_USRDAT_SURDAT}"

      ./xmlchange DATM_MODE="1PT"
      ./xmlchange CLM_CO2_TYPE="constant"
      ./xmlchange CCSM_CO2_PPMV=400
      ./xmlchange PTS_LON=239.05
      ./xmlchange PTS_LAT=38.41
      ./xmlchange CALENDAR="${SITE_CALENDAR}"
      ./xmlchange ${V_HLM_USRDAT_NAME}="${SITE_NAME}"
      ./xmlchange ${V_HLM_NAMELIST_OPTS}="fsurdat = '${HLM_SURDAT_FILE}'"
      #./xmlchange ATM_DOMAIN_PATH="${SITE_PATH}"
      #./xmlchange LND_DOMAIN_PATH="${SITE_PATH}"
      #./xmlchange ATM_DOMAIN_FILE="${HLM_USRDAT_DOMAIN}"
      #./xmlchange LND_DOMAIN_FILE="${HLM_USRDAT_DOMAIN}"
      ./xmlchange DIN_LOC_ROOT_CLMFORC="${SITE_BASE_PATH}"
      ;;
   esac
   #---~---


   #---~---
   #     Set the PE layout for a single-site run (unlikely that users would change this).
   #---~---
   echo "   - Configure Processing elements (PES)."
   cd ${CASE_PATH_NODE}
   ./xmlchange NTASKS_CPL=1
   ./xmlchange NTASKS_ATM=1
   ./xmlchange NTASKS_LND=1
   ./xmlchange NTASKS_ICE=1
   ./xmlchange NTASKS_OCN=1
   ./xmlchange NTASKS_ROF=1
   ./xmlchange NTASKS_GLC=1
   ./xmlchange NTASKS_WAV=1
   #./xmlchange NTASKS_IAC=1
   ./xmlchange NTASKS_ESP=1

   ./xmlchange NTHRDS_CPL=1
   ./xmlchange NTHRDS_ATM=1
   ./xmlchange NTHRDS_LND=1
   ./xmlchange NTHRDS_ICE=1
   ./xmlchange NTHRDS_OCN=1
   ./xmlchange NTHRDS_ROF=1
   ./xmlchange NTHRDS_GLC=1
   ./xmlchange NTHRDS_WAV=1
   #./xmlchange NTHRDS_IAC=1
   ./xmlchange NTHRDS_ESP=1
   #---~---


   #---~---
   #     Change additional XML configurations if needed.
   #---~---
   cd ${CASE_PATH_NODE}
   if [[ ${#xml_settings[*]} -gt 0 ]]
   then
      #--- Loop through the options to update.
      echo "   - Update XML settings."
      for x in ${!xml_settings[*]}
      do
         #--- Retrieve settings.
         xml_id=$(echo ${xml_settings[x]}  | awk '{print $1}')
         xml_id=$(echo ${xml_id}           | sed s@"YYY"@${HLM}@g | sed s@"yyy"@${hlm}@g)
         xml_val=$(echo ${xml_settings[x]} | awk '{print $2}')
         #---~---

         #--- Update settings.
         ./xmlchange ${xml_id}="${xml_val}"
         #---~---

      done
      #---~---
   else
      #--- No changes needed.
      echo "   - No XML changes required."
      #---~---
   fi
   #---~---



   #---~---
   #
   # WARNING! WARNING! WARNING! WARNING! WARNING! WARNING! WARNING! WARNING! WARNING!
   # WARNING! WARNING! WARNING! WARNING! WARNING! WARNING! WARNING! WARNING! WARNING!
   # WARNING! WARNING! WARNING! WARNING! WARNING! WARNING! WARNING! WARNING! WARNING!
   # WARNING! WARNING! WARNING! WARNING! WARNING! WARNING! WARNING! WARNING! WARNING!
   #
   #     This part modifies the stream file, in case incoming long wave radiation is not
   # available.  You should not need to change anything in here.
   #---~---
   # Find the first met driver.
   case "${RESOL}" in
   ?LM_USRDAT)
      echo -n "   - Look for incoming longwave radiation..."

      #--- Define files with meteorological driver settings.
      HLM_USRDAT_ORIG="${SIMUL_PATH_NODE}/run/datm.streams.txt.CLM1PT.${RESOL}"
      HLM_USRDAT_USER="${SIMUL_PATH_NODE}/user_datm.streams.txt.CLM1PT.${RESOL}"
      #---~---

      #--- Define meteorological driver path
      DATM_PATH="${SITE_PATH}/CLM1PT_data"
      #---~---


      ANY_METD_NC=$(/bin/ls -1 ${DATM_PATH}/????-??.nc 2> /dev/null | wc -l)
      if [[ ${ANY_METD_NC} -gt 0 ]]
      then
         #--- Load one netCDF file.
         METD_NC_1ST=$(/bin/ls -1 ${DATM_PATH}/????-??.nc 2> /dev/null | head -1)
         ANY_FLDS=$(ncdump -h ${METD_NC_1ST} 2> /dev/null | grep FLDS | wc -l)
         if [[ ${ANY_FLDS} -eq 0 ]]
         then
            #--- Incoming long wave radiation is missing, change the stream file
            echo " Not found! Remove variable from the local meteorological driver."
            /bin/cp ${HLM_USRDAT_ORIG} ${HLM_USRDAT_USER}
            sed -i".bck" '@FLDS@d' ${HLM_USRDAT_USER}
            /bin/rm -f "${HLM_USRDAT_USER}.bck"
            #---~---
         else
            echo "  Found it! Use data from the local meteorological driver."
         fi
         #---~---
      else
         #--- Report error.
         echo " FATAL ERROR!"
         echo " ANY_METD_NC = ${ANY_METD_NC}"
         echo " Meteorological drivers not found in ${DATM_PATH}".
         echo " Make sure all the met driver files are named as yyyy-mm.nc"
         exit 91
         #---~---
      fi
      #---~---
      ;;
   esac
   #---~---


   #--- Start setting up the case
   echo "   - Set up the case."
   cd ${CASE_PATH_NODE}
   ./case.setup --silent
   #---~---


   #---~---
   #   Loop through tasks, and generate the user file for each ensemble member. They
   # are mostly the same except for the parameter file.
   #---~---
   TASK_CNT=0
   while [[ ${TASK_CNT} -lt ${NODE_TASKS} ]]
   do
      (( TASK_CNT = TASK_CNT + 1 ))


      #---~---
      #   Set task (ensemble member) names.  Instances should always contain 4 digits.
      #---~---
      INST_LABEL=$(printf "%4.4i" ${TASK_CNT})
      TASK_LABEL=$(printf "${TASK_FMT}" ${TASK_CNT})
      USER_NL_HLM_TASK=${USER_NL_HLM_PREF}_${INST_LABEL}
      USER_NL_HLM_BASE=$(basename ${USER_NL_HLM_TASK})
      USER_NL_DATM_TASK=${USER_NL_DATM_PREF}_${INST_LABEL}
      USER_NL_DATM_BASE=$(basename ${USER_NL_DATM_TASK})
      echo "   - ${TASK_LABEL}/${NODE_TASKS}: Update namelists (${USER_NL_HLM_BASE})."
      #---~---


      #--- Parameter file for this ensemble member.
      export ENSEMBLE_LABEL="Node${NODE_LABEL}_Task${TASK_LABEL}"
      export FATES_ENSEMBLE_BASE="${FATES_ENSEMBLE_PREF}_${ENSEMBLE_LABEL}.nc"
      export FATES_ENSEMBLE_FILE="${FATES_ENSEMBLE_PATH}/${FATES_ENSEMBLE_BASE}"
      #---~---





      #---~---
      #     Include settings for the inventory initialisation.
      #---~---
      if [[ "${INVENTORY_BASE}" != "" ]]
      then

         #--- Set inventory file with full path.
         INVENTORY_FILE="${SITE_PATH}/${INVENTORY_BASE}"
         #---~---


         #--- Instruct the host land model to use the modified parameter set.
         touch ${USER_NL_HLM_TASK}
         echo "use_fates_inventory_init = .true."                   >> ${USER_NL_HLM_TASK}
         echo "fates_inventory_ctrl_filename = '${INVENTORY_FILE}'" >> ${USER_NL_HLM_TASK}
         #---~---

      fi
      #---~---



      #---~---
      #    Make sure that the axis mode is configured to cycle, so the meteorological
      # drivers are correctly recycled over time.
      #---~---
      case "${RESOL}" in
      ?LM_USRDAT)
         # Append time axis mode to the user namelist
         echo "CLM_USRDAT.vaira-1pt:taxmode = cycle" >> ${USER_NL_DATM_TASK}
         # Append MOSART input file to the user namelist
         # echo "frivinp_rtm = ' '" >> ${USER_NL_MOSART}
         ;;
      esac
      #---~---



      #---~---
      #   Instruct the host land model to use the modified parameter set.
      #---~---
      touch ${USER_NL_HLM_TASK}
      echo "fates_paramfile = '${FATES_ENSEMBLE_FILE}'" >> ${USER_NL_HLM_TASK}
      #---~---


      #---~---
      # Add other variables to the namelist of the host land model.
      #---~---
      if  [[ ${#hlm_settings[*]} -gt 0 ]]
      then
         #--- Loop through the options to update.
         for h in ${!hlm_settings[*]}
         do
            #--- Retrieve settings.
            hlm_now=${hlm_settings[h]}
            hlm_id=$(echo ${hlm_now}  | awk '{print $1}')
            hlm_id=$(echo ${hlm_id}   | sed s@"YYY"@${HLM}@g | sed s@"yyy"@${hlm}@g       )
            hlm_val=$(echo ${hlm_now} | awk '{for(i=2;i<=NF;++i)printf $i""FS ; print ""}')
            #---~---

            #--- Update namelist
            touch ${USER_NL_HLM_TASK}
            echo "${hlm_id} = ${hlm_val}" >> ${USER_NL_HLM_TASK}
            #---~---
         done
         #---~---
      fi
      #---~---


      #---~---
      # Add other variables to the namelist of the host land model.
      #---~---
      if  [[ ${#hlm_variables[*]} -gt 0 ]]
      then
         #---~---
         #   Initialise variables assuming no output, then update them.
         #---~---
         hlm_mlist=""
         hlm_dlist=""
         hlm_hlist=""
         #---~---


         #--- Loop through the options to update.
         n_month_add=0
         n_day_add=0
         n_hour_add=0
         for h in ${!hlm_variables[*]}
         do
            #--- Retrieve settings.
            hlm_now=${hlm_variables[h]}
            hlm_var=$(echo ${hlm_now}   | awk '{print $1}'                             )
            add_fates=$(echo ${hlm_now} | awk '{print $2}' | tr '[:upper:]' '[:lower:]')
            add_hlm=$(echo ${hlm_now}   | awk '{print $3}' | grep -i ${hlm} | wc -l    )
            add_month=$(echo ${hlm_now} | awk '{print $4}' | tr '[:upper:]' '[:lower:]')
            add_day=$(echo ${hlm_now}   | awk '{print $5}' | tr '[:upper:]' '[:lower:]')
            add_hour=$(echo ${hlm_now}  | awk '{print $6}' | tr '[:upper:]' '[:lower:]')
            #---~---


            #---~---
            #   We only add the variable if the variable is compatible with the host
            # land model and compatible with FATES simulations.
            #---~---
            if [[ ${add_hlm} -gt 0 ]]
            then
               case "${add_fates}" in
                  yes|both) add_var=true  ;;
                  *)        add_var=false ;;
               esac
            else
               add_var=false
            fi
            #---~---


            #---~---
            #    Append variable to the list in case the variable is fine for this
            # settings.  Then check which time scales to include.
            #---~---
            if ${add_var}
            then
               #---~---
               #   Monthly
               #---~---
               if [[ "${add_month}" == "yes" ]]
               then
                  #--- Increment variable counter
                  (( n_month_add = n_month_add + 1 ))
                  #---~---


                  #---~---
                  #    Append variable to the list. Make sure commas are added for all but
                  # the first.
                  #---~---
                  case ${n_month_add} in
                     1) hlm_mlist="${hlm_mlist} '${hlm_var}'" ;;
                     *) hlm_mlist="${hlm_mlist},'${hlm_var}'" ;;
                  esac
                  #---~---
               fi
               #---~---

               #---~---
               #   Daily
               #---~---
               if [[ "${add_day}" == "yes" ]]
               then
                  #--- Increment variable counter
                  (( n_day_add = n_day_add + 1 ))
                  #---~---


                  #---~---
                  #    Append variable to the list. Make sure commas are added for all but
                  # the first.
                  #---~---
                  case ${n_day_add} in
                     1) hlm_dlist="${hlm_dlist} '${hlm_var}'" ;;
                     *) hlm_dlist="${hlm_dlist},'${hlm_var}'" ;;
                  esac
                  #---~---
               fi
               #---~---

               #---~---
               #   Hourly
               #---~---
               if [[ "${add_hour}" == "yes" ]]
               then
                  #--- Increment variable counter
                  (( n_hour_add = n_hour_add + 1 ))
                  #---~---


                  #---~---
                  #    Append variable to the list. Make sure commas are added for all
                  # but the first.
                  #---~---
                  case ${n_hour_add} in
                     1) hlm_hlist="${hlm_hlist} '${hlm_var}'" ;;
                     *) hlm_hlist="${hlm_hlist},'${hlm_var}'" ;;
                  esac
                  #---~---
               fi
               #---~---
            fi
            #---~---
         done
         #---~---


         #---~---
         #    We only append the variable lists if at least one variable was included and the
         # output variable is to be included. Regardless, we always set monthly outputs as the
         # primary, to avoid generating large data sets for daily or hourly.
         #---~---
         hlm_nhtfrq="hist_nhtfrq = 0"
         hlm_mfilt="hist_mfilt  = 1"
         hlm_incl=1
         #---~---


         #---~---
         #   Check monthly. The settings will be always included, so the default output
         # is always monthly, even if nothing is written.
         #---~---
         if [[ ${n_month_add} -gt 0 ]]
         then
            #--- Add list of monthly variables to the output.
            hlm_mlist="hist_fincl1 = ${hlm_mlist}"
            touch ${USER_NL_HLM_TASK}
            echo ${hlm_mlist} >> ${USER_NL_HLM_TASK}
            #---~---
         fi
         #---~---


         #---~---
         #   Check daily, and add if any variable is to be in the output.
         #---~---
         if [[ ${n_day_add} -gt 0 ]]
         then
            #--- Add list of daily variables to the output.
            (( hlm_incl = hlm_incl + 1 ))
            hlm_dlist="hist_fincl${hlm_incl} = ${hlm_dlist}"
            touch ${USER_NL_HLM_TASK}
            echo ${hlm_dlist} >> ${USER_NL_HLM_TASK}
            #---~---

            #---~---
            #   Update frequency and steps.
            #---~---
            hlm_nhtfrq="${hlm_nhtfrq}, -24"
            hlm_mfilt="${hlm_mfilt}, 30"
            #---~---
         fi
         #---~---


         #---~---
         #   Check hourly, and add if any variable is to be in the output.
         #---~---
         if [[ ${n_hour_add} -gt 0 ]]
         then
            #--- Add list of daily variables to the output.
            (( hlm_incl = hlm_incl + 1 ))
            hlm_hlist="hist_fincl${hlm_incl} = ${hlm_hlist}"
            touch ${USER_NL_HLM_TASK}
            echo ${hlm_hlist} >> ${USER_NL_HLM_TASK}
            #---~---

            #---~---
            #   Update frequency and steps.
            #---~---
            hlm_nhtfrq="${hlm_nhtfrq}, -1"
            hlm_mfilt="${hlm_mfilt}, 720"
            #---~---
         fi
         #---~---


         #--- Append time table instructions
         touch ${USER_NL_HLM_TASK}
         echo ${hlm_nhtfrq} >> ${USER_NL_HLM_TASK}
         echo ${hlm_mfilt}  >> ${USER_NL_HLM_TASK}
         #---~---
      fi
      #---~---
   done
   #---~---


   #--- Start setting up the case
   echo "   - Preview namelists."
   cd ${CASE_PATH_NODE}
   ./preview_namelists --silent
   #---~---



   #--- Build case.
   echo "   - Build case."
   BUILD_LOG="${CASE_PATH_NODE}/status_case.build_$(date '+%y%m%d-%H%M%S')"
   cd ${CASE_PATH_NODE}
   ./case.build --silent --clean
   ./case.build 1> ${BUILD_LOG} 2>& 1
   #---~---




   #---~---
   #    Proceed to creating ensemble cases/simulations only if the template case was
   # succesfully built.
   #---~---
   IS_SUCCESS=$(grep "MODEL BUILD HAS FINISHED SUCCESSFULLY" ${BUILD_LOG} | wc -l | xargs)
   if [[ ${IS_SUCCESS} -eq 0 ]]
   then
      # Case building failed. Stop and report.
      echo ""
      echo ""
      echo ""
      echo "---------------------------------------------------------------------"
      echo " Case building was unsuccessful."
      echo " Check file ${BUILD_LOG} for additional information."
      echo "---------------------------------------------------------------------"
      exit 89
   fi
   #---~---
done
#---~---



#--- Go to the source path.
cd ${SOURCE_PATH}
#---~---



#---~---
#   Write a shell script that will launch all jobs.
#---~---
echo " + Set script for submitting all jobs."
SUB_SCRIPT="${CASE_PATH}/ensemble_submit.sh"
SUB_LOG="${SOURCE_PATH}/$(echo ${SOURCE_BASE} | sed s@"\\.sh$"@".log"@g)"
touch ${SUB_SCRIPT}
chmod u+x ${SUB_SCRIPT}
echo "#!/bin/bash -e"                                                  >> ${SUB_SCRIPT}
echo ""                                                                >> ${SUB_SCRIPT}
echo "# Main settings"                                                 >> ${SUB_SCRIPT}
echo "module load python/3.7.9"                                        >> ${SUB_SCRIPT}
echo "export SUB_LOG=\"${SUB_LOG}\""                                   >> ${SUB_SCRIPT}
echo "export N_NODES=${N_NODES}"                                       >> ${SUB_SCRIPT}
echo "export NODE_FMT=\"${NODE_FMT}\""                                 >> ${SUB_SCRIPT}
echo "export CASE_PATH=\"${CASE_PATH}\""                               >> ${SUB_SCRIPT}
echo "export CASE_PREFIX=\"${CASE_PREFIX}\""                           >> ${SUB_SCRIPT}
echo ""                                                                >> ${SUB_SCRIPT}
echo "# Submit the cases sequentially."                                >> ${SUB_SCRIPT}
echo "NODE_CNT=0"                                                      >> ${SUB_SCRIPT}
echo "while [[ \${NODE_CNT} -lt \${N_NODES} ]]"                        >> ${SUB_SCRIPT}
echo "do"                                                              >> ${SUB_SCRIPT}
echo "   # Update ensemble node member"                                >> ${SUB_SCRIPT}
echo "   (( NODE_CNT = NODE_CNT + 1 ))"                                >> ${SUB_SCRIPT}
echo "   NODE_LABEL=\$(printf \"\${NODE_FMT}\" \${NODE_CNT})"          >> ${SUB_SCRIPT}
echo ""                                                                >> ${SUB_SCRIPT}
echo "   # Set member case"                                            >> ${SUB_SCRIPT}
echo "   NODE_NAME=\"\${CASE_PREFIX}_Node\${NODE_LABEL}\""             >> ${SUB_SCRIPT}
echo "   NODE_PATH=\"\${CASE_PATH}/\${NODE_NAME}\""                    >> ${SUB_SCRIPT}
echo ""                                                                >> ${SUB_SCRIPT}
echo "   # Submit case"                                                >> ${SUB_SCRIPT}
echo "   echo \" + \${NODE_LABEL}/\${N_NODES}: Run \${NODE_NAME}...\"" >> ${SUB_SCRIPT}
echo "   cd \${NODE_PATH}"                                             >> ${SUB_SCRIPT}
echo "   ./case.submit --silent"                                       >> ${SUB_SCRIPT}
echo "done"                                                            >> ${SUB_SCRIPT}
echo ""                                                                >> ${SUB_SCRIPT}
#---~---



#---~---
#   Check whether to submit the case directly or to only show instructions on how to
# submit the ensemble.
#---~---
if ${AUTO_SUBMIT}
then
   #---~---
   #    Submit the job. Before we do this, give the user a few seconds in case they
   # change their minds.
   #---~---
   echo ""
   echo ""
   echo ""
   echo "---------------------------------------------------------------------"
   echo " CASES WERE SUCCESSFULLY BUILT, CONGRATULATIONS!"
   echo " I will start running the case in 10 seconds."
   echo " In case you change your mind, press Ctrl+C before the time is over."
   echo "---------------------------------------------------------------------"
   when=11
   echo -n " - "
   while [[ ${when} -gt 1 ]]
   do
      (( when = when - 1 ))
      echo -n " ${when}..."
      sleep 1
   done
   echo " Time is over!"
   #---~---


   #---~---
   #   Submit jobs.
   #---~---
   ${SUB_SCRIPT}
   #---~---
elif [[ ${IS_SUCCESS} -gt 0 ]]
then
   #---~---
   #    Case was successfully built. Give instructions on how to submit the job.
   #---~---
   echo ""
   echo ""
   echo ""
   echo "---------------------------------------------------------------------"
   echo " CASE WAS SUCCESSFULLY BUILT, CONGRATULATIONS!"
   echo " To submit the case, use the following command:"
   echo ""
   echo "${SUB_SCRIPT}"
   echo ""
   #---~---
fi
#---~---
