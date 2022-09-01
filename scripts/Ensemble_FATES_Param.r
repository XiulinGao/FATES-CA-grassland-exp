#-----------------------------------------------------------------------------------------
#    Script Ensemble_FATES_Params.r
#
#    Developed by Chonggang Xu   < c x u -@- l a n l -.- g o v >
#       Modified by Marcos Longo < m l o n g o -@- l b l -.- g o v >
#                   07 Jun 2022 08:53 PDT
#
#    This script generates a suite of parameter samples using uniform distribution, using
# a Latin hypercube sampling with the option to account for variable correlation.
#
# Script requirements:
# - Package 'ncdf4' and package 'lhs' (version 1.1.6 or later). For installing the
#   most up-to-date lhs version, check instructions at https://bertcarnell.github.io/lhs/
# - A "default" parameter file with the intended PFTs, already converted to NetCDF4.
# - A csv file containing the ensemble instructions. The csv file should contain the
#   following columns (case sensitive). Other columns are fine but will be ignored.
#   * parameter -- Parameter names for the ensemble. These must be valid parameter names
#                  compatible with the provided NetCDF file
#   * value_min -- Minimum value allowed for each parameter.
#   * value_max -- Maximum value allowed for each parameter.
#   * pft       -- PFT for which the parameter should be updated. Set this
#                  value to NA in case the parameter is global, or to zero if this should
#                  be applied to all PFTs.
#   * org       -- First organ for which the parameter should be updated. Set this value
#                  to NA in case the parameter is NOT organ-specific, or to zero if this
#                  value should be applied to all PFTs
#
# Script optional inputs:
# - A csv file containing parameter correlation information. Only correlations that are
#   relevant should be provided, and only the "upper triangle" or "lower triangle" of 
#   the correlation should be given (excluding the diagonal). If a correlation between
#   two variables is not provided, the script will treat the parameters as uncorrelated.
#   The csv file should contain the following columns (case sensitive). Other columns are
#   fine but they will be ignored.
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
#-----------------------------------------------------------------------------------------



#---~---
#   Reset R before running the script
#---~---
# Unload all packages
suppressWarnings({
   plist = names(sessionInfo()$otherPkgs)
   if (length(plist) > 0){
      dummy = sapply(X=paste0("package:",plist),FUN=detach,character.only=TRUE,unload=TRUE)
   }#end if (length(plist) > 0)
   # Remove all variables, reset warnings, close plots and clean up memory
   rm(list=ls())
   options(warn=0)
   invisible(graphics.off())
   invisible(gc())
})#end suppressWarnings
#---~---



#---~---
#    Path and file settings. Most files are set in two variables (path and base). We do
# this to make the integration of this R script with external calls a bit easier.
#
# home_path      - Home directory (useful when changing machines)
# work_path      - Base directory where parameters and settings are located
# parset_path    - Path where parameter instruction files are located.
# parset_base    - Input file where parameter instruction is located (without path)
# parcorr_base   - Input file where parameter correlations are located (without path).
#                  If no correlation file exists, set this variable to NA_character_.
# ncdf4_in_path  - Input NetCDF path
# ncdf4_in_base  - Input NetCDF file name (no path, we will append ncdf4_in_path)
# ncdf4_out_path - Path where output NetCDF files are to be written
# ncdf4_out_pref - Prefix for output NetCDF file. Do not include path or the ".nc"
#                  extension. The ensemble identifier will be included along with the
#                  ".nc" extension.
#---~---
home_path      = path.expand("~")
work_path      = file.path(home_path,"Documents","CA-grassland-simuDoc")
parset_path    = file.path(work_path,"ensemble-param-base")
parset_base    = "global-varying-params.csv"
#parset_base    = "test.csv"
parcorr_base   = "parameter-corr.csv"
ncdf4_in_path  = file.path(home_path,"Documents","CA-grassland-simuDoc","ensemble-param-base")
ncdf4_in_base  = c("fates_c3g_avba_base1.nc","fates_c3g_brdi_base2.nc","fates_c3g_genl_base3.nc") #for parallel ensemble
ncdf4_out_path = file.path(work_path,"EnsembleParamSet","general-allom-group-params")
ncdf4_out_pref = substr(ncdf4_in_base[2],11,20)
n_pft=1
#---~---



#---~---
#   Ensemble settings
#
# n_ensemble     -- Number of ensemble members to run
# tasks_per_node -- Number of ensemble
# seed_init      -- Seed number for random generator. Setting the seed to a known
#                   number allows full reproducibility of the code. For a completely
#                   (non-reproducible) random sampling, set the seed to NA_real_.
# lhs_eps        -- Tolerance for deviation between prescribed matrix and the result for
#                   correlated Latin Hypercube Sampling (ignored otherwise).  Very strict
#                   tolerances may cause convergence failure if the number of samples is
#                   large.
# lhs_maxIt      -- Maximum number of iterations before giving up on building the Latin
#                   hypercube when accounting for correlations (ignored otherwise). Set to
#                   0 to let the algorithm define it. If negative, the method will never
#                   give up until convergence, but this risks running indefinitely in case
#                   the method fails to converge.
#---~---
n_ensemble     = 1500 # Number of ensemble realisations
tasks_per_node = 36  # Ensemble realisations per node (job)
seed_init      = 6
lhs_eps        = 0.025
lhs_maxIt      = 1000L
#---~---



#---~---
#   Should the script produce detailed information on parameter ensembles.  Set this to
# TRUE if testing/developing the script, but in most cases it is better to set it to FALSE.
#---~---
verbose = FALSE
#---~---



#---~---
#---~---
#---~---
#   Changes beyond this point are for script development only.
#---~---
#---~---
#---~---


#---~---
#   Load packages needed by this script.
#---~---
cat (" + Load packages.\n")
fine.packages = c( ncdf4     = require(ncdf4    ,quietly=TRUE,warn.conflicts=FALSE)
                 , MASS      = require(MASS     ,quietly=TRUE,warn.conflicts=FALSE)
                 , pse       = require(pse      ,quietly=TRUE,warn.conflicts=FALSE)
                 )#end fine.packages
if (! all(fine.packages)){
   cat (" List of required packages, and the success status loading them:\n")
   print(fine.packages)
   stop(" Some packages are missing and must be installed.")
}#end if (! all(fine.packages))
#---~---


#---~---
#   In case a seed number was provided, set it here so script results are
# reproducible.
#---~---
if (! is.na(seed_init)) dummy = set.seed(seed_init)
#---~---

#---~---
#   Set input files with full path.
#---~---
parset_file   = file.path(parset_path  ,parset_base  )
ncdf4_in_file = file.path(ncdf4_in_path,ncdf4_in_base[3])
if ( ! file.exists(ncdf4_in_file) ){
   cat ("------------------------------------------------------------------\n")
   cat (" Reference NetCDF file not found!\n"                                 )
   cat (" - NCDF4_IN_PATH = ",ncdf4_in_path,".\n",sep=""                      )
   cat (" - NCDF4_IN_BASE = ",ncdf4_in_base,".\n",sep=""                      )
   cat ("------------------------------------------------------------------\n")
   stop(" This script requires a valid input parameter file in NetCDF format.")
}#end if ( ! file.exists(ncdf4_in_file) )
#---~---


#---~---
#   Make sure the output directory exists.
#---~---
dummy = dir.create(ncdf4_out_path,recursive=TRUE,showWarnings=FALSE)
#---~---


#---~---
#   Set standardised format for ensemble member flags.
#---~---
n_nodes      = ceiling(n_ensemble/tasks_per_node)
node_digits  = 1L + round(log10(n_nodes))
task_digits  = 1L + round(log10(tasks_per_node))
ens_digits   = 1L + round(log10(n_ensemble))
ens_fmt      = paste0("%",ens_digits,".",ens_digits,"i")
task_fmt     = paste0(  "Node%",node_digits,".", node_digits,"i"
                     ,"_Task%",task_digits,".",task_digits,"i"
                     )#end paste0
#---~---


#---~---
#   Read the parameter instructions
#---~---
if (file.exists(parset_file)){
   cat (" + Read parameter settings.\n")
   param_config        = read.csv(file=parset_file,header=TRUE,stringsAsFactors=FALSE)

   #---~---
   #   Add a few useful columns.
   #---~---
   param_config$pft_var = is.finite(param_config$pft)
   param_config$all_pft = param_config$pft_var & (param_config$pft == 0L)
   param_config$org_var = is.finite(param_config$organ)
   param_config$all_org = param_config$org_var & (param_config$organ == 0L)
   #---~---

   #---~---
   #   Name for correlation matrix
   #---~---
   pft_suffix             = ifelse( test = (! param_config$pft_var) | param_config$all_pft
                                  , yes  = ""
                                  , no   = sprintf("_P%2.2i",param_config$pft)
                                  )#end ifelse
   organ_suffix           = ifelse( test = (! param_config$org_var) | param_config$all_org
                                  , yes  = ""
                                  , no   = sprintf("_O%2.2i",param_config$organ)
                                  )#end ifelse
   param_config$corr_name = paste0(param_config$parameter,pft_suffix,organ_suffix)
   #---~---



   n_param             = nrow(param_config)
}else{
   cat ("-----------------------------------------------------------------\n"       )
   cat ("   Parameter configuration file is missing! Check configuration.\n"        )
   cat (" - parset_path = \"",parset_path,"\"\n"                             ,sep="")
   cat (" - parset_base = \"",parset_base,"\"\n"                             ,sep="")
   cat ("-----------------------------------------------------------------\n"       )
   stop(" Parameter instruction file is missing.")
}#end if (file.exists(parset_file))
#---~---



#---~---
#   Check whether or not to account for correlations
#---~---
parcorr_file = ifelse( test = is.na(parcorr_base)
                     , yes  = NA_character_
                     , no   = file.path(parset_path,parcorr_base)
                     )#end ifelse
if (is.na(parcorr_file)){
   #---~---
   #   Use sample as is, ignoring correlations.
   #---~---
   cat (" + No parameter correlation provided. Assume uncorrelated samples.\n"        )
   param_corr           = diag(nrow = n_param)
   dimnames(param_corr) = list(param_config$correlation,param_config$correlation)
   #---~---
}else if (file.exists(parcorr_file)){
   #---~---
   #   Read in the correlation information.
   #---~---
   corr_config = read.csv(file=parcorr_file,header=TRUE,stringsAsFactors=FALSE)
   n_corr      = nrow(corr_config)
   #---~---

   #---~---
   #   Add a few useful columns.
   #---~---
   corr_config$pft_var = is.finite(corr_config$pft)
   corr_config$all_pft = corr_config$pft_var & (corr_config$pft == 0L)
   corr_config$org_var = is.finite(corr_config$organ)
   corr_config$all_org = corr_config$org_var & (corr_config$organ == 0L)
   #---~---


   #---~---
   #   Build the correlation matrix.  Because the same parameter may appear multiple 
   # times in the parameter configuration (due to multiple PFTs or multiple organs),
   # we go through each line of the correlation configuration.
   #---~---
   param_corr           = matrix(data=0.,nrow=n_param,ncol=n_param)
   dimnames(param_corr) = list(param_config$corr_name,param_config$corr_name)
   for (m in sequence(n_corr)){
      #--- Retrieve parameters
      a_parameter = corr_config$parameter_a[m]
      b_parameter = corr_config$parameter_b[m]
      ab_pft      = corr_config$pft        [m]
      ab_organ    = corr_config$organ      [m]
      ab_corr     = corr_config$corr       [m]
      ab_pft_var  = corr_config$pft_var    [m]
      ab_all_pft  = corr_config$all_pft    [m]
      ab_org_var  = corr_config$org_var    [m]
      ab_all_org  = corr_config$all_org    [m]
      #---~---


      #---~---
      #   Retrieve rows and columns
      #---~---
      rsel = param_config$parameter %in% a_parameter
      csel = param_config$parameter %in% b_parameter
      psel = param_config$pft       %in% ab_pft
      osel = param_config$organ     %in% ab_organ
      #--- Restrict correlation for PFTs
      if (ab_pft_var){
         rsel = rsel & ( psel | (! param_config$pft_var ) | ab_all_pft )
         csel = csel & ( psel | (! param_config$pft_var ) | ab_all_pft )
      }#end if
      #--- Restrict correlation for organs
      if (ab_org_var){
         rsel = rsel & ( osel | (! param_config$org_var ) | ab_all_org )
         csel = csel & ( osel | (! param_config$org_var ) | ab_all_org )
      }#end if
      #---~---



      #---~---
      #   Update correlation for rows and columns, taking the correlation matrix symmetry
      # into account.
      #---~---
      param_corr[rsel,csel] = ab_corr
      param_corr[csel,rsel] = ab_corr
      #---~---

   }#end for (i in sequence(n_corr))
   #--- Update the diagonal, which should always be 1.
   diag(param_corr) = 1.
   #---~---
}else{
   cat ("-------------------------------------------------------------------\n"       )
   cat ("   Parameter correlation file is missing! In case you do not\n"              )
   cat (" want to provide correlation, set \"parcorr_base = NA_character_\".\n"       )
   cat ("\n"                                                                          )
   cat ("   Current settings:\n"                                                      )
   cat (" - parset_path  = \"",parset_path,"\"\n"                              ,sep="")
   cat (" - parcorr_base = \"",parcorr_base,"\"\n"                             ,sep="")
   cat ("-------------------------------------------------------------------\n"       )
   stop(" Parameter correlation file is missing.")
}#end if
#---~---




#---~---
#   Build normalised (quantile) sampling for all parameters.  The sampling from package
# LHS requires at least n_param + 2 realisations. If the requested number is less, we 
# impose the minimum for the Latin Hypercube and randomly pick a subset afterwards.
#---~---
cat (" + Build normalised samples for all parameters.\n")
if (is.na(parcorr_file)){
   #---~---
   #   Run a default Latin Hypercube sample of uncorrelated variables.
   #---~---
   param_sample = LHS( factors = param_config$corr_name
                     , N       = pmax(n_ensemble,n_param+2L)
                     , q       = rep(x="qunif",times=n_param)
                     , method  = "random"
                     )#end LHS
   #---~---
}else{
   #---~---
   #   Run a default Latin Hypercube sample whilst accounting for correlation.
   #---~---
   param_sample = LHS( factors = param_config$corr_name
                     , N       = pmax(n_ensemble,n_param+2L)
                     , q       = rep(x="qunif",times=n_param)
                     , method  = "HL"
                     , opts    = list( COR   = param_corr
                                     , eps   = lhs_eps
                                     , maxIt = lhs_maxIt
                                     )#end list
                     )#end LHS
   #---~---
}#end if (sample_method %in% "default")
 #---~---



#---~---
#    Retrieve the quantiles and trim the hypercube to match the sought number of 
# ensembles.
#---~---
cat (" + Build normalised samples for all parameters.\n")
n_sample    = nrow(param_sample$data)
idx_use     = sort(sample(x=n_sample,size=n_ensemble,replace=FALSE))
param_quant = param_sample$data[idx_use,,drop=FALSE]
#---~---



#---~---
#   Scale quantiles to parameter units
#---~---
cat (" + Scale quantiles to the parameter range.\n")
add0        = matrix( data     = param_config$value_min
                    , nrow     = n_ensemble
                    , ncol     = n_param
                    , byrow    = TRUE
                    , dimnames = list(NULL,param_config$corr_name)
                    )#end matrix
mult        = matrix( data     = param_config$value_max-param_config$value_min
                    , nrow     = n_ensemble
                    , ncol     = n_param
                    , byrow    = TRUE
                    , dimnames = list(NULL,param_config$corr_name)
                    )#end matrix
add0        = as.data.frame(add0)
mult        = as.data.frame(mult)
param_table = add0 + mult * param_quant
param_table$fates_leaf_slamax = param_table$fates_leaf_slatop
#---~---




#---~---
#   Loop through all ensemble iterations to make NetCDF files
#---~---
cat (" + Generate NetCDF for each ensemble realisation.\n")
for (e in sequence(n_ensemble)){
   #---~---
   #   Configure ensemble file
   #---~---
   node            = ceiling(e/tasks_per_node)
   task           = 1 + ((e-1)%%tasks_per_node)
   ens_label      = sprintf(ens_fmt,e)
   task_label     = sprintf(task_fmt,node,task)
   ncdf4_out_base = paste0(ncdf4_out_pref,"_",task_label,".nc")
   ncdf4_out_file = file.path(ncdf4_out_path,ncdf4_out_base)
   cat("   - ",ens_label,"/",n_ensemble,": Generate file ",ncdf4_out_base,".\n",sep="")
   #---~---


   #---~---
   #   Create ensemble file, then open it
   #---~---
   dummy    = file.copy(ncdf4_in_file,ncdf4_out_file,overwrite=TRUE)
   nc_conn  = nc_open(ncdf4_out_file,write=TRUE)
   nc_nvars = nc_conn$nvars
   nc_ndims = nc_conn$ndims
   nc_dlist = rep(NA_character_,times=nc_ndims)
   nc_vlist = rep(NA_character_,times=nc_nvars)
   for (d in sequence(nc_ndims)) nc_dlist[d] = nc_conn$dim[[d]]$name
   for (v in sequence(nc_nvars)) nc_vlist[v] = nc_conn$var[[v]]$name
   #---~---


   #---~---
   #    We only update values that are in the NetCDF file. In case there is any
   # parameter missing, we warn the user.
   #---~---
   p_change = which(  param_config$parameter %in% nc_vlist)
   p_miss   = which(! param_config$parameter %in% nc_vlist)
   if (length(p_miss) > 0L){
      cat("     > The following parameters do not exist in the parameter file!:\n")
      for (p in p_miss) cat("       ~ ",param_config$parameter[p],"\n",sep="")
   }#end if (length(p_miss) > 0L)
   #---~---

   #---~---
   #   Loop through parameters and update values
   #---~---
   for (p in p_change){
      #---~---
      #   Shorter names
      #---~---
      p_parameter = param_config$parameter [p]
      p_corr_name = param_config$corr_name [p]
      p_pft       = param_config$pft       [p]
      p_organ     = param_config$organ     [p]
      p_pft_var   = param_config$pft_var   [p]
      p_all_pft   = param_config$all_pft   [p]
      p_org_var   = param_config$org_var   [p]
      p_all_org   = param_config$all_org   [p]
      #---~---

      #---~---
      #   Retrieve parameter value (original and new value).
      #---~---
      p_out_value = ncvar_get(nc_conn,p_parameter,collapse_degen=FALSE)
      p_new_value = param_table[[p_corr_name]][e]
      #---~---


      #---~---
      #   Set indices for PFT and organs in case they are needed.
      #---~---
      if (p_pft_var) p_pft_idx = if(p_all_pft){sequence(dim(p_out_value)[1])}else{p_pft  }
      if (p_org_var) p_org_idx = if(p_all_org){sequence(dim(p_out_value)[2])}else{p_organ}
      #---~---


      #---~---
      #   Update parameter
      #---~---
      if (verbose){
         cat("     > Update parameter ",p_parameter," ("
                                       ,sprintf("%g",signif(p_new_value,4)),").\n",sep="")
      }#end if (verbose)
      #---~---
      if (p_org_var){
         #---~---
         #   PFT- and organ-specific parameter. Update only the sought PFTs and organs.
         #---~---
        if(n_pft>1){p_out_value[p_pft_idx,p_org_idx] = p_new_value}else{
          p_out_value[p_org_idx] = p_new_value
        }
         
         #---~---
      }else if (p_pft_var){
         #---~---
         #   PFT-specific parameter. Update only the sought PFTs.
         #---~---
        if(n_pft>1){p_out_value[p_pft_idx] = p_new_value}else{
          p_out_value = p_new_value 
        }
         
         #---~---
      }else{
         #---~---
         #    Global value. We multiply the original value by 0 to preserve the
         # original dimensions.
         #---~---
         p_out_value = p_new_value + 0. * p_out_value
         #---~---
      }#end if (p_global)
      #---~---


      #---~---
      #   Update value in the NetCDF file
      #---~---
      dummy = ncvar_put(nc_conn,p_parameter,p_out_value)
      #---~---
   }#end for (p in p_change)
   #---~---


   #---~---
   #   Close file
   #---~---
   dummy = nc_close(nc_conn)
   #---~---
}#end for (e in sequence(n_ensemble))
#---~---


#---~---
#   Write a message confirming success. Please keep this message, it is useful for
# tracking whether or not the script ran fine when this script is called externally.
#---~---
cat("\n")
cat("-----------------------------------------------------\n")
cat(" SUCCESS! All ensemble parameter files were created! \n")
cat("-----------------------------------------------------\n")
cat("\n")
#---~---

