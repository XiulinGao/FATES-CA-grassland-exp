### mask-wrf-domain.R
### using 2016 nlcd herbaceous cover data for the western US to mask WRF domain to
### where only cells with herbaceous cover >= 80% 
### Author: Xiulin Gao
### author-email: xiulingao@lbl.gov
### Date: 2022-08-15

library(raster)
library(sp)
library(ncdf4)
library(tidyverse)

##### here we copy one of these WRF forcing and mask out domains where annual herb cover <80 #####
nlcd        = raster("~/Google Drive/My Drive/NLCD-herbaceous/rcmap_herbaceous_2016.img")
wrf_path    = file.path("~/Google Drive/My Drive/9km-WRF-1980-2020/1981-01.nc")
nlcd_proj   = crs(nlcd)
nlcd_crs    = "+proj=aea +lat_0=23 +lon_0=-96 +lat_1=29.5 +lat_2=45.5 +x_0=0 +y_0=0 +datum=WGS84 +units=m
+no_defs"
wgs      = "+init=EPSG:4326"
wrf_proj = "+proj=lcc +lat_1=30 +lat_0=38 
               +lon_0=-70 +lat_2=60 +R=6370000 
            +datum=WGS84 +units=m +no_defs"
my_theme = theme_bw() + theme(panel.ontop=TRUE, panel.background=element_blank())

author_name  = "Xiulin Gao"
author_email = "xiulingao@lbl.gov"
undef        = -9999.0000


wrf_t = nc_open(wrf_path)
tobt  = ncvar_get(wrf_t,"TBOT")
XLONG = ncvar_get(wrf_t,"LONGXY")
XLAT  = ncvar_get(wrf_t, "LATIXY")
nc_close(wrf_t)
tobt     = tobt[,,1]
tobt_vec = as.vector(tobt)
x_vec    = as.vector(XLONG)
y_vec    = as.vector(XLAT)
wrf_df   = as.data.frame(cbind(x_vec,y_vec,tobt_vec))
id       = 1:nrow(wrf_df)
wrf_df$cellid = id



wrf_extnt = raster::extent(-130.2749,-108.9862,28.62024,45.71207)
wrf_poly  = as(wrf_extnt,"SpatialPolygons")
sp::proj4string(wrf_poly) = wgs
wrf_nlcd  = spTransform(wrf_poly,crs(nlcd_proj))
nlcd_wrf  = crop(nlcd,extent(wrf_nlcd))
nlcd_wrf  = mask(nlcd_wrf, wrf_nlcd)
nlcd150_wrf = aggregate(nlcd_wrf, fact=5, fun=mean)
#writeRaster(nlcd150_wrf,file.path(paste0(wrf_path,"wrf-extent-masked-annual-herb_150mres.img")))
nlcd80_wrf  = nlcd150_wrf
#nlcd85_wrf  = nlcd150_wrf
nlcd80_wrf[nlcd80_wrf[]<80] = NA


nlcd80_wgs = projectRaster(nlcd80_wrf, crs=wgs)


#we resample nlcd data to a rectilinear grids that has a similar dimension and extent
#as wrf domain, so we can search for the nearest neighbor

wrf_rs    = raster(wrf_extnt,ncols=147,nrows=151,crs=wgs)

# using both bilinear and nearest neighbor methods for resample
nlcd_mean = resample(nlcd80_wgs, wrf_rs, method="bilinear")
nlcd_ngb  = resample(nlcd80_wgs, wrf_rs, method="ngb") 
# ngb works better given the resulted central valley region is almost all NA



nlcdherb_ngb  = as.data.frame(nlcd_ngb,xy=TRUE)
nlcdherb_mean = as.data.frame(nlcd_mean,xy=TRUE)



wrf_qry        = wrf_df %>% dplyr::select(x_vec,y_vec,cellid,tobt_vec)
wrf_qry$mask80 = 0

#search for the nearest neighbor in wrf for each corresponding filtered nlcd cell
nn_pt        = RANN::nn2(nlcdherb_ngb[,1:2],wrf_qry[,1:2],k=1) 
wrf_qry$id   = as.vector(nn_pt$nn.idx) #add resulted row index of wrf to nlcd
wrf_qry$dist = as.vector(nn_pt$nn.dists)

wrf_qry = wrf_qry                                     %>% 
          mutate(cover = nlcdherb_ngb$layer[id])      %>% 
          mutate(mask80 = ifelse(is.na(cover),0,1))   %>% 
          mutate(mask80 = ifelse(y_vec>=34 & y_vec<=40 & x_vec>=-124.5 & x_vec<=-114.5
                                ,mask80,0))


wrf_dfil = wrf_qry                                     %>%  
           dplyr::select(x_vec,y_vec,mask80,tobt_vec)  %>% 
           rename(lon=x_vec,lat=y_vec)                 %>% 
           mutate(tobt_vec = ifelse(mask80==0,NA,tobt_vec))


fil_var   = matrix(wrf_dfil$tobt_vec, nrow=147,ncol=151)
x_arr     = matrix(wrf_dfil$lon,nrow=147,ncol=151)
y_arr     = matrix(wrf_dfil$lat,nrow=147,ncol=151)
wrf_star  = st_as_stars(fil_var)
wrf_star  = st_as_stars(wrf_star, curvilinear=list(X1=x_arr,X2=y_arr), crs=wgs)
wrf_sf    = st_as_sf(wrf_star,as_points=FALSE,na.rm=FALSE)
ca_co     = USAboundaries::us_counties(resolution = "high", states = "CA")

##plot to see how the active domain looks like

ggplot() + geom_sf(data=wrf_sf,colour="grey50", aes(fill=A1),lwd=0)+
  coord_sf(crs=st_crs(wrf_proj)) + 
  my_theme +scale_fill_continuous(low="thistle2", high="darkred", 
                                  guide="colorbar",na.value="grey50")+
  geom_sf(data = ca_co, color = alpha("black", alpha=0.2),lwd=0.1,fill=NA) +
  geom_point(aes(x=-120.9508,y=38.4133), colour=alpha("blue",0.6), size=0.2)

## tried using both 85% and 80% grass cover as thresholds,
## looks like 80% threshold is the best as it is more inclusive

land_mask80 <- array(wrf_qry$mask80,dim=c(147,151))
land_mkdif80 <- land_mask80


## create new nc file as land mask
xx  = ncdim_def( name="lon"   ,units="",vals= sequence(147)  ,create_dimvar=FALSE)
yy  = ncdim_def( name="lat"   ,units="",vals= sequence(151)  ,create_dimvar=FALSE)
nc_xy  = list   (xx,yy)
xy     = c(147,151)
file_name = file.path("Google Drive/My Drive/wrf_CA_grass_ngb80.nc")
nc_vlist        = list()
nc_vlist$LONGXY = ncvar_def(  name      = "lsmlon"
                             , units    = "degrees_east"
                             , dim      = nc_xy
                             , missval  = undef
                             , longname = "longitude"
)#end ncvar_def
nc_vlist$LATIXY = ncvar_def( name       = "lsmlat"
                             , units    = "degrees_north"
                             , dim      = nc_xy
                             , missval  = undef
                             , longname = "latitude"
)#end ncvar_def
nc_vlist$mask1   = ncvar_def( name      = "landmask"
                             , units    = "unitless"
                             , dim      = nc_xy
                             , missval  = undef
                             , longname = "mask for land domain, 1 being cell active"
)#end ncvar_def
nc_vlist$mask2   = ncvar_def( name      = "mod_lnd_props"
                             , units    = "unitless"
                             , dim      = nc_xy
                             , missval  = undef
                             , longname = "mask for modifying land property, 1 being active land cell"
)#end ncvar_def

### define global attributes

att_template = list( title            = "To be replaced when looping through months"
                     , date_created   = paste0(as.character(now(tzone="UTC")), "UTC")
                     , source_code    = "mask-wrf-domain.R"
                     , code_notes     = "land mask for WRF domain created using NLCD herb cover >=80"
                     , code_developer = paste0( author_name
                                                ," <"
                                                , author_email
                                                ,">"
                     )#end paste0
                     , file_author    = paste0(author_name," <",author_email,">")
)#end list

nc_new <- nc_create(filename=file_name,vars=nc_vlist,verbose=FALSE)
dummy = ncvar_put(nc=nc_new,varid="lsmlon",vals=array(data=x_vec,dim=xy))
dummy = ncvar_put(nc=nc_new,varid="lsmlat", vals=array(data=y_vec, dim=xy))
dummy = ncvar_put(nc=nc_new, varid ="landmask",vals=land_mask80)
dummy = ncvar_put(nc=nc_new, varid ="mod_lnd_props",vals=land_mkdif80)


nc_title   = "Land mask for WRF domain with herbaceous cover >=80%"
att_global = modifyList( x = att_template, val = list( title = nc_title ))


# Loop through global attributes
for (l in seq_along(att_global)){
  # Current attribute information
  att_name  = names(att_global)[l]
  att_value = att_global[[l]]
  
  # Add attribute 
  dummy = ncatt_put(nc=nc_new,varid=0,attname=att_name,attval=att_value)
}#end for (l in seq_along(att_global))
nc_close(nc_new)
