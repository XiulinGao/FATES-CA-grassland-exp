## FRAP-WRF-domain-burnt-fraction.R
## this is a R script to grid FRAP burned area onto
## 9km WRF domain for the CA region. Burned area
## then is calculated to burned fraction to compare to FATES output

## Author: Xiulin Gao
## Author email: xiulingao@lbl.gov
## date: 2022-10-13

library(raster)
library(sp)
library(sf)
library(tidyverse)
library(ncdf4)
library(stars)

wrf_path    = file.path("~/Google Drive/My Drive/9km-WRF-1980-2020/1981-01.nc")
frap_path   = file.path("~/Documents/frap-fire/Data/fire20_1.gdb")
mask_path   = file.path("~/Google Drive/My Drive/CA-grassland-simulationDoc/wrf-landmask/wrf_CA_grass_ngb80.nc")

wgs = "+init=EPSG:4326"
wrf_proj = "+proj=lcc +lat_1=30 +lat_0=38 
               +lon_0=-70 +lat_2=60 +R=6370000 
            +datum=WGS84 +units=m +no_defs"
my_theme = theme_bw() + theme(panel.ontop=TRUE, panel.background=element_blank())

wrf_t = nc_open(wrf_path)
tobt  = ncvar_get(wrf_t,"TBOT")
XLONG = ncvar_get(wrf_t,"LONGXY")
XLAT  = ncvar_get(wrf_t, "LATIXY")
nc_close(wrf_t)
tobt  = tobt[,,1]
tobt_vec = as.vector(tobt)
x_vec    = as.vector(XLONG)
y_vec    = as.vector(XLAT)
wrf_df   = as.data.frame(cbind(x_vec,y_vec,tobt_vec))
id       = 1:nrow(wrf_df)
wrf_df$cellid = id


wrf_sf   = st_as_sf(wrf_df, coords=c("x_vec","y_vec"), crs=wgs)
#wrf_grid = st_make_grid(wrf_sf,n=c(147,151),crs=wrf_proj)


## create a raster that is close to the WRF domain but in regular grids
wrf_extnt = raster::extent(-130.2749,-108.9862,28.62024,45.71207)
wrf_rs    = raster(wrf_extnt,ncols=147,nrows=151,crs=wgs)
vals      = 1:ncell(wrf_rs)
wrf_rs    = setValues(wrf_rs,vals)
plot(wrf_rs)
plot(wrf_sf,add=TRUE)


layers      = st_layers(dsn=frap_path) 
wldfire     = st_read(frap_path, layer = layers$name[1])
frap_yrs    = unique(wldfire$YEAR_[!is.na(wldfire$YEAR_)])

all_bfrac = data.frame()
for (n in frap_yrs){
  yr_now             = n
  frap_now           = wldfire  %>% filter(YEAR_==yr_now)
  
  if(length(unique(st_geometry_type(st_geometry(frap_now))))>1){
    
    frap_now      = sf::st_cast(frap_now, "MULTIPOLYGON")
    frap_now      = sf::as_Spatial(frap_now)}else{
    frap_now      = sf::as_Spatial(frap_now)}
  
  bfrac              = exactextracr::coverage_fraction(wrf_rs,st_combine(st_as_sf(frap_now)))
  bfrac_df           = data.frame(rasterToPoints(bfrac[[1]]))
  names(bfrac_df)[3] = "bfrac"
  bfrac_df$year      = yr_now
  all_bfrac          = rbind(all_bfrac, bfrac_df)
  #f_out              = paste0("bfrac_",yr_now,".tif")
  #writeRaster(bfrac, filename=file.path(frap_path,f_out))
}
data.table::fwrite(all_bfrac,file.path(frap_path,"allBfrac_0.144by0.113.csv"))

## Search for the nearest WRF grid for each cell of burned fraction

nn_pt            = RANN::nn2(wrf_df[,1:2], all_bfrac[,1:2],k=1)
all_bfrac$wrf_id = as.vector(nn_pt$nn.idx)
all_bfrac$dist   = as.vector(nn_pt$nn.dists)
filt_bfrac       = all_bfrac %>% filter(dist<0.05)
years            = unique(filt_bfrac$year)

wrf_bfrac        = data.frame(lon=NA, lat=NA, year=NA, bfrac=NA)
for(y in years){
  yr_now = y
  bfrac_now = filt_bfrac %>% filter(year==yr_now)
  bfrac_now = bfrac_now                           %>% 
              mutate(lon = wrf_df$x_vec[wrf_id]
                    ,lat = wrf_df$y_vec[wrf_id])  %>% 
              dplyr::select(lon,lat,year,bfrac)   %>% 
              group_by(lon,lat,year)              %>% 
              summarize_all(mean,na.rm=TRUE)      %>% 
              ungroup()
  wrf_bfrac = rbind(wrf_bfrac,bfrac_now)
}

wrf_bfrac  = wrf_bfrac  %>% filter(!is.na(bfrac))
data.table::fwrite(wrf_bfrac,file.path(frap_path,"Bfrac-resampled-OnWRFDomain.csv"))


##filter burnt fraction for only grasslands (herb cover >=80%)
mask = nc_open(mask_path)
mk_lon = ncvar_get(mask,"lsmlon")
mk_lat = ncvar_get(mask,"lsmlat")
landmk = ncvar_get(mask,"landmask")
mk_lon = as.vector(mk_lon)
mk_lat = as.vector(mk_lat)
landmk = as.vector(landmk)
dummy  = nc_close(mask)
mask   = data.frame(lon=mk_lon,lat=mk_lat,mask=landmk)
mask   = mask %>% filter(mask==1)
grass_bfrac = wrf_bfrac
grass_bfrac = grass_bfrac                         %>% 
              left_join(mask,by=c("lon","lat"))   %>% 
              filter(!is.na(mask))
data.table::fwrite(grass_bfrac,file.path(frap_path,"Bfrac-WRF-grassonly.csv"))
gsbfrac_amean = grass_bfrac                         %>% 
                dplyr::select(lon,lat,bfrac)        %>% 
                group_by(lon,lat)                   %>% 
                summarize_all(mean,na.rm=TRUE)

### plot 
wrf_dfil = gsbfrac_amean 
wrf_xy   = wrf_df %>% select(x_vec,y_vec) %>% rename(lon=x_vec,lat=y_vec)
wrf_dfil = wrf_xy      %>% left_join(wrf_dfil,by=c("lon","lat"))

#wrf_dfil = wrf_dfil                                         %>% 
#           mutate(bfrac_fil = ifelse(is.na(mask),NA,bfrac))

fil_var  = matrix(wrf_dfil$bfrac, nrow=147,ncol=151)
x_arr    = matrix(wrf_dfil$lon,nrow=147,ncol=151)
y_arr    = matrix(wrf_dfil$lat,nrow=147,ncol=151)
wrf_star = st_as_stars(fil_var)
wrf_star = st_as_stars(wrf_star, curvilinear=list(X1=x_arr,X2=y_arr), crs=wgs)
wrf_sf   = st_as_sf(wrf_star,as_points=FALSE,na.rm=FALSE)
ca_co    = USAboundaries::us_counties(resolution = "high", states = "CA")

##plot to see how the active domain looks like

ggplot() + geom_sf(data=wrf_sf,colour="grey50", aes(fill=A1),lwd=0)+
  coord_sf(crs=st_crs(wrf_proj)) + 
  my_theme +scale_fill_continuous(low="thistle2", high="darkred", 
                                  guide="colorbar",na.value="grey50")+
  geom_sf(data = ca_co, color = alpha("black", alpha=0.2),lwd=0.1,fill=NA) +
  geom_point(aes(x=-120.9508,y=38.4133), colour=alpha("blue",0.6), size=0.2)



