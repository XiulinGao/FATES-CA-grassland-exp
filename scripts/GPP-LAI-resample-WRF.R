## GPP-LAI-resample-WRF.R

## this script is for resampling 0.05 degree GPP and LAI data (2000-2020)
## onto WRF domain 

library(raster)
library(sp)
library(ncdf4)
library(tidyverse)

# Domain and mask file
wrf_path    = file.path("~/Google Drive/My Drive/9km-WRF-1980-2020/1981-01.nc")
mask_path   = file.path("~/Google Drive/My Drive/CA-grassland-simulationDoc/wrf-landmask/wrf_CA_grass_ngb80.nc")
outmain     = file.path("~/Google Drive/My Drive/CA-grassland-simulationDoc/benchmark/CA-GPP-LAI-005degree")
lai_out     = file.path(outmain,"LAI-monthly")
gpp_out     = file.path(outmain,"GPP-monthly")
wgs      = "+init=EPSG:4326"

#GPP and LAI  files
gpp_main    = file.path("~/Google Drive/My Drive/CA-grassland-simulationDoc/benchmark/SIF-GPP-global0.05degree-monthly")
lai_main    = file.path("~/Google Drive/My Drive/CA-grassland-simulationDoc/benchmark/LAI-monthly-pt05degree")
gpp_files   = list.files(gpp_main,pattern=".tif$")
lai_files   = list.files(lai_main,pattern=".nc$")
gpp_paths   = file.path(gpp_main,gpp_files)
lai_paths   = file.path(lai_main,lai_files)

## First we crop and mask GPP and LAI data to be only 
## in CA region at 0.05 degree, save files for future use

# LAI dimension
nc_zero = nc_open(lai_paths[1])
lons  = ncvar_get(nc_zero, "lon")
nlon  = length(lons)
lats  = ncvar_get(nc_zero,"lat")
nlat  = length(lats)
dummy = nc_close(nc_zero)
lons_rep = rep(lons, time = nlat)
lats_rep = rep(lats, each = nlon)
months   = sequence(12)
lonmax   = -114.725
lonmin   = -124.775
latmin   = 32.225
latmax   = 42.775
caext    = extent(-124.5, -114, 32.5, 42) 
ca_rs    = raster(caext,res=0.05)
wrf_extnt = raster::extent(-130.2749,-108.9862,28.62024,45.71207)
wrf_rs    = raster(wrf_extnt,nrows=147,ncols=151,crs=wgs)
vals      = 1:ncell(wrf_rs)
wrf_rs    = setValues(wrf_rs,vals)


### LAI resample
process_lai <- function(filename){
  year   = substring(filename,114,117)
  nc_now = nc_open(filename)
  var_now = ncvar_get(nc_now, "lai",collapse_degen=TRUE)
  var_list = lapply(seq(dim(var_now)[3]), function(x) var_now[, , x])
  dummy    = nc_close(nc_now)
  lai_yr <- tibble()
  
  for(m in sequence(12)){
    var <- unlist(var_list[m])
    lai <- tibble(lon = lons_rep,
                  lat = lats_rep,
                  lai = var)
    lai <- lai %>% filter(lon>=lonmin & lon<=lonmax)
    lai <- lai %>% filter(lat>=latmin & lat<=latmax)
    var_ras <- rasterFromXYZ(lai, res= 0.05, crs=wgs, digits=3)
    f_out <- paste0("CA-LAI-005dg-",year,"-",m,".tif")
    writeRaster(var_ras,filename=file.path(lai_out,f_out),format="GTiff",overwrite=TRUE)
    var_ras <- crop(var_ras, wrf_rs)
    var_wrf <- resample(var_ras,wrf_rs,method="bilinear")
    var_dat <- as.data.frame(var_wrf, xy=TRUE)
    var_dat <- var_dat %>% mutate(year = year,
                                  month = m)
    lai_yr <- bind_rows(lai_yr, var_dat)
  }
  return(lai_yr)
}




concat_lai_dir <- function(path) { 
  files <- list.files(path, pattern = ".nc$", full.names = TRUE)
  dat <- lapply(files,process_lai)
  return(bind_rows(dat))
}

## ONLY RUN ONCE
#lai_dt <- concat_lai_dir(lai_main)
#fwrite(lai_dt, file = file.path(lai_out,"CA-LAI-onWRFDomain-monthly_2000-2020.csv"))


## GPP resample

scalf = 0.01 # scale factor for the monthly GPP data

process_gpp <- function(filename){
  year  = substring(filename,117,120)
  month = substring(filename,123,124)
  date  = make_date(year=year,month=month)
  cmon.day = days_in_month(date)
  gpp_now = raster(filename)
  gpp_now = crop(gpp_now,caext)
  gpp_now[gpp_now==65535] <- NA #water body to NA
  gpp_now[gpp_now==65534] <- NA #snow cover to NA
  gpp_now = gpp_now*scalf 
  gpp_now = gpp_now/cmon.day #GPP now in gC/(m2*month), convert to gC/(m2*day) so comparable to FATES  
  f_out   = paste0("CA-GPP-005degree-",year,"-",month,".tif")
  writeRaster(gpp_now,filename=file.path(gpp_out,f_out),format="GTiff",overwrite=TRUE)
  gpp_now = crop(gpp_now, wrf_rs)
  gpp_wrf = resample(gpp_now,wrf_rs,method="bilinear")
  var_dat = as.data.frame(gpp_wrf, xy=TRUE)
  names(var_dat)[3] = 'GPP'
  var_dat <- var_dat %>% mutate(year = year,
                                month = month)
  return(var_dat)
}

concat_gpp_dir <- function(path) { 
  files <- list.files(path, pattern = ".tif$", full.names = TRUE)
  dat <- lapply(files,process_gpp)
  return(bind_rows(dat))
}

## ONLY RUN ONCE
#gpp_dt <- concat_gpp_dir(gpp_main)
#fwrite(gpp_dt, file = file.path(gpp_out,"CA-GPP-onWRFDomain-monthly_2000-2020.csv"))



## Then we map GPP and LAI onto the exact WRF grids by 
## searching for the nearest cell for each WRF grid

wrf_t = nc_open(wrf_path)
XLONG = ncvar_get(wrf_t,"LONGXY")
XLAT  = ncvar_get(wrf_t, "LATIXY")
nc_close(wrf_t)
x_vec    = as.vector(XLONG)
y_vec    = as.vector(XLAT)
wrf_df   = as.data.frame(cbind(x_vec,y_vec))


yrs = unique(lai_dt$year)
nyr = length(yrs)

val = gpp_dt 
names(val)[3] = "var"
wrf_lai = data.frame()
wrf_gpp = data.frame()
for(y in sequence(nyr)){
  yr_now  = yrs[y]
  val_now = val %>% filter(year==yr_now)
  mos     = unique(val_now$month)
  nmo     = length(mos)
  
  for(m in sequence(nmo)){
    mo_now = mos[m]
    val_sub = val_now %>% filter(month==mo_now)
    wrf_qry       = wrf_df
    nn_pt         = RANN::nn2(val_sub[,1:2], wrf_qry[,1:2],k=1)
    wrf_qry$id    = as.vector(nn_pt$nn.idx)
    wrf_qry       = wrf_qry                       %>% 
                    mutate(var   = val_sub$var[id]
                          ,year  = yr_now
                          ,month = mo_now)        %>% 
                    rename(lon=x_vec,lat=y_vec)   %>% 
                    dplyr::select(lon,lat,year,month,var)
    
    wrf_gpp = rbind(wrf_gpp,wrf_qry)
  }
}

wrf_lai = wrf_lai %>% rename(lai = var)
fwrite(wrf_lai,file.path(outmain,"LAI-onWRFgrids.csv"))
wrf_gpp = wrf_gpp %>% rename(gpp = var)
fwrite(wrf_gpp,file.path(outmain,"GPP-onWRFgrids.csv"))


### filter GPP and LAI to only grasslands

mask   = nc_open(mask_path)
mk_lon = ncvar_get(mask,"lsmlon")
mk_lat = ncvar_get(mask,"lsmlat")
landmk = ncvar_get(mask,"landmask")
mk_lon = as.vector(mk_lon)
mk_lat = as.vector(mk_lat)
landmk = as.vector(landmk)
dummy  = nc_close(mask)
mask   = data.frame(lon=mk_lon,lat=mk_lat,mask=landmk)
mask   = mask %>% filter(mask==1)
grass_lai = wrf_lai
grass_lai = grass_lai                           %>% 
            left_join(mask,by=c("lon","lat"))   %>% 
            filter(!is.na(mask))
data.table::fwrite(grass_lai,file.path(outmain,"LAI-WRF-grassonly.csv"))

grass_gpp = wrf_gpp
grass_gpp = grass_gpp                           %>% 
            left_join(mask,by=c("lon","lat"))   %>% 
            filter(!is.na(mask))
data.table::fwrite(grass_gpp,file.path(outmain,"GPP-WRF-grassonly.csv"))






