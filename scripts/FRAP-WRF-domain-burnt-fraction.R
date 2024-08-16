## FRAP-WRF-domain-burnt-fraction.R
## this is a R script to grid FRAP burned area onto
## 9km WRF domain for the CA region. Burned area
## then is calculated to burned fraction to compare to FATES output

## Author: Xiulin Gao
## Author email: xiulingao@lbl.gov
## date: 2022-10-15

library(sp)
library(raster)
library(sf)
library(tidyverse)
library(ncdf4)
library(stars)

wrf_path    = file.path("~/Google Drive/My Drive/9km-WRF-1980-2020/1981-01.nc")
frap_path   = file.path("~/Documents/frap-fire/Data/fire20_1.gdb")
mask_path   = file.path("~/Google Drive/My Drive/CA-grassland-simulationDoc/wrf-landmask/wrf_CA_grass_ngb80.nc")
short_path  = file.path("~/Google Drive/My Drive/CA-grassland-simulationDoc/benchmark/RDS-2013-0009_5.gdb/Data/FPA_FOD_20210617.gdb")


wgs = "+init=EPSG:4326"
wrf_proj = "+proj=lcc +lat_1=30 +lat_0=38 
               +lon_0=-70 +lat_2=60 +R=6370000 
            +datum=WGS84 +units=m +no_defs"

gg_device  = c("png")     # Output devices to use (Check ggsave for acceptable formats)
gg_depth   = 600          # Plot resolution (dpi)
gg_ptsz    = 18           # Font size
gg_ptszl   = 26
gg_width   = 17.5         # Plot width (units below)
gg_widthn  = 14.5
gg_height  = 8.5          # Plot height (units below)
gg_units   = "in"         # Units for plot size
   

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
wrf_rs    = raster(wrf_extnt,ncols=151,nrows=147,crs=wgs)
vals      = 1:ncell(wrf_rs)
wrf_rs    = setValues(wrf_rs,vals)
plot(wrf_rs)
plot(wrf_sf,add=TRUE)
wrf_area  = area(wrf_rs)


layers      = st_layers(dsn=frap_path) 
wldfire     = st_read(frap_path, layer = layers$name[1])
frap_yrs    = unique(wldfire$YEAR_[!is.na(wldfire$YEAR_)])
frap_proj   = crs(wldfire)

## use coverage_fraction to calculate cell area fraction
## covered by each FRAP polygon
## reference: https://gis.stackexchange.com/questions/359277/rasterization-of-polygons-calculation-of-the-area-covered

all_bfrac = data.frame()
all_barea = data.frame()
for (n in frap_yrs){
  yr_now             = n
  frap_now           = wldfire  %>% filter(YEAR_==yr_now)
  
  if(length(unique(st_geometry_type(st_geometry(frap_now))))>1){
    
    frap_now      = sf::st_cast(frap_now, "MULTIPOLYGON")
    frap_now      = sf::as_Spatial(frap_now)}else{
    frap_now      = sf::as_Spatial(frap_now)}
  
  bfrac              = exactextractr::coverage_fraction(wrf_rs,st_combine(st_as_sf(frap_now)))
  bfrac_df           = data.frame(rasterToPoints(bfrac[[1]]))
  names(bfrac_df)[3] = "bfrac"
  bfrac_df$year      = yr_now
  all_bfrac          = rbind(all_bfrac, bfrac_df)
  
  barea              = bfrac[[1]]*wrf_area
  barea_df           = data.frame(rasterToPoints(barea[[1]]))
  barea_df$year      = yr_now
  names(barea_df)[3] ="barea"
  all_barea          = rbind(all_barea,barea_df)
  #f_out              = paste0("bfrac_",yr_now,".tif")
  #writeRaster(bfrac, filename=file.path(frap_path,f_out))
}

data.table::fwrite(all_bfrac,file.path(frap_path,"allBfrac_0.144by0.113.csv"))
data.table::fwrite(all_barea,file.path(frap_path,"allBArea_0.144by0.113.csv"))


bfrac_annual = all_bfrac                      %>% 
               filter(year %in% simu_time)    %>% 
               group_by(x,y)                  %>% 
               summarize(bfrac=mean(bfrac,na.rm=TRUE)) %>% ungroup()

ggplot(data=bfrac_annual,aes(x,y,fill=bfrac)) +
  geom_raster() +
  my_theme +scale_fill_continuous(low="royalblue4", high="red", 
                                  guide="colorbar",na.value="grey50")+
  borders(database="state",regions="CA",color="black") + coord_quickmap() +
  labs(x="",y="") + guides(fill=guide_legend(title="Annual Burned Fraction"))

## Search for the nearest WRF grid for each cell of annual burned fraction

nn_pt         = RANN::nn2(bfrac_annual[,1:2], wrf_df[,1:2],k=1)
wrf_df$id     = as.vector(nn_pt$nn.idx)
wrf_df$dist   = as.vector(nn_pt$nn.dists)


wrf_ambfrac          = wrf_df                              %>% 
                      mutate(bfrac=bfrac_annual$bfrac[id]) %>% 
                      dplyr::select(x_vec,y_vec,bfrac)     %>% 
                      rename(lon=x_vec,lat=y_vec)          
                      
## also do a yearly burned fraction for WRF domain if we are 
## interested in comparing year by year

years            = unique(all_bfrac$year)
wrf_fire         = data.frame()
for(y in years){
  yr_now = y
  bfrac_now     = all_bfrac %>% filter(year==yr_now)
  barea_now     = all_barea %>% filter(year==yr_now)
  wrf_qry       = wrf_df
  nn_pt         = RANN::nn2(bfrac_now[,1:2], wrf_qry[,1:2],k=1)
  wrf_qry$id    = as.vector(nn_pt$nn.idx)
  wrf_qry       = wrf_qry                             %>% 
                  mutate(bfrac = bfrac_now$bfrac[id]
                        ,barea = barea_now$barea[id]
                        ,year  = yr_now)              %>% 
                  rename(lon=x_vec,lat=y_vec)         %>% 
                  dplyr::select(lon,lat,year,barea,bfrac)
                  
  wrf_fire = rbind(wrf_fire,wrf_qry)
}

wrf_fire  = wrf_fire  %>% filter(!is.na(bfrac))
data.table::fwrite(wrf_fire,file.path(frap_path,"Bfrac-resampled-OnWRFDomain2.csv"))


##filter burnt fraction for only grasslands (herb cover >=80%)
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
total_area = nrow(mask)*9*9

grass_frap  = wrf_fire
grass_frap  = grass_frap                         %>% 
              left_join(mask,by=c("lon","lat"))   %>% 
              filter(!is.na(mask))
data.table::fwrite(grass_frap,file.path(frap_path,"Bfrac-WRF-grassonly_FRAP.csv"))

gsbfrac_amean1 = grass_frap                         %>% 
                filter(year%in%simu_time)           %>% 
                dplyr::select(lon,lat,bfrac)        %>% 
                group_by(lon,lat)                   %>% 
                summarize_all(mean,na.rm=TRUE)      %>% 
                ungroup()  
gsbfrac_amean2 = wrf_ambfrac                        %>%
                 left_join(mask,by=c("lon","lat"))  %>% 
                 filter(!is.na(mask))
                 
  
  
  
allbfrac_amean = wrf_fire                           %>% 
                 filter(year%in%simu_time)          %>% 
                 dplyr::select(lon,lat,barea,bfrac) %>% 
                 group_by(lon,lat)                  %>% 
                 summarize_all(mean,na.rm=TRUE)     %>% 
                 ungroup()        



      
               

### plot 
wrf_dfil = allbfrac_amean  

wrf_xy   = wrf_df %>% select(x_vec,y_vec) %>% rename(lon=x_vec,lat=y_vec)
wrf_dfil = wrf_xy                                     %>% 
           left_join(wrf_dfil,by=c("lon","lat"))      %>% 
           mutate(bfrac=ifelse(bfrac==0,NA,bfrac))   


fil_var  = matrix(wrf_dfil$bfrac, nrow=147,ncol=151)
x_arr    = matrix(wrf_dfil$lon,nrow=147,ncol=151)
y_arr    = matrix(wrf_dfil$lat,nrow=147,ncol=151)
wrf_star = st_as_stars(fil_var)
wrf_star = st_as_stars(wrf_star, curvilinear=list(X1=x_arr,X2=y_arr), crs=wgs)
wrf_sf   = st_as_sf(wrf_star,as_points=FALSE,na.rm=FALSE)
ca_co    = USAboundaries::us_counties(resolution = "high", states = "CA")


gg_now = ggplot() + geom_sf(data=wrf_sf, aes(fill=A1),color=NA)+
  coord_sf(crs=st_crs(wgs)) + 
  scale_fill_continuous(low="blue", high="red", guide="colorbar",na.value="white")+
  geom_sf(data = ca_co, color = alpha("black", alpha=1),lwd=0.1,fill=NA) +
  labs(x="",y="") +
  #guides(fill=guide_legend(title=desc.unit(desc=h_short,unit=untab[[h_unit]],dxpr=TRUE))) +
  guides(fill=guide_legend(title="Annual burned fraction(yr-1)")) +
  theme( legend.position  = "right"
         , legend.title     = element_text(size=gg_ptsz*0.85)
         , legend.text      = element_text(size=gg_ptsz*0.85)
         , panel.background = element_blank()
         , panel.border     = element_rect(linewidth = 1.6, fill=NA)
         , axis.text.x      = element_text( size   = gg_ptsz*0.85
                                            , margin           = unit(rep(0.35,times=4),"cm"))#end element_text
         , axis.text.y      = element_text( size   = gg_ptsz*0.85
                                            , margin           = unit(rep(0.35,times=4),"cm")
         )#end element_text
         , axis.ticks.length = unit(-0.25,"cm")
  ) #end theme

ggsave(gg_now, filename="short-frap-combinbf.png",path="~/Desktop/",width=gg_widthn*0.6,height=gg_height*0.6,dpi=gg_depth,device=gg_device[1])


## find the nearest point for Vaira Ranch (38.4133,-120.9508)
point           = data.frame(lon=-120.9508,lat=38.4133)
nearest         = RANN::nn2(all_bfrac[,1:2],point,k=1)
bfrac_site      = all_bfrac
bfrac_site$id   = as.vector(nearest$nn.idx)
bfrac_site      = bfrac_site                     %>% 
                  filter(x==x[id]&y==y[id])  

bfrac_site        = bfrac_site                   %>% 
                    filter(year %in% simu_time)   
data.table::fwrite(bfrac_site,
                   "~/Google Drive/My Drive/CA-grassland-simulationDoc/benchmark/FRAP/site-nearest-fire.csv")


## fire return interval
#fri_extnt = extent(-373237.5,539438.2,-604727.6,518283.7)
#fri_rs = raster(fri_extnt,resolution=120,crs=frap_proj)

#all_fri = data.frame(lon=NA, lat=NA, year=NA, bfrac=NA)
#for (n in frap_yrs){
#  yr_now             = n
#  frap_now           = wldfire  %>% filter(YEAR_==yr_now)
  
#  if(length(unique(st_geometry_type(st_geometry(frap_now))))>1){
    
#    frap_now      = sf::st_cast(frap_now, "MULTIPOLYGON")
#    frap_now      = sf::as_Spatial(frap_now)}else{
#    frap_now      = sf::as_Spatial(frap_now)}
  
#  fri                = exactextractr::coverage_fraction(fri_rs,st_combine(st_as_sf(frap_now)))
#  fri_df             = data.frame(rasterToPoints(fri[[1]]))
#  names(fri_df)[3]   = "bfrac"
#  fri_df$year        = yr_now
#  fri_df             = fri_df %>% mutate(fire_num = ifelse(bfrac>=1,floor(bfrac),0))
#  all_fri            = rbind(all_fri, fri_df) #will crash, too large. Just output single year and then combine them
#}


## 1. read and resample GPP and LAI onto 



### Using the Short fire database: https://www.fs.usda.gov/rds/archive/Catalog/RDS-2013-0009.5


layers      = st_layers(dsn=short_path) 
fire_short  = st_read(short_path, layer = layers$name[1])
short_ca    = fire_short %>% filter(STATE=="CA")
short_yrs    = unique(short_ca$FIRE_YEAR[!is.na(short_ca$FIRE_YEAR)])
short_proj   = crs(short_ca)
short_ca     = short_ca                                  %>% 
               dplyr::select(FOD_ID,FPA_ID,FIRE_YEAR,
                             NWCG_CAUSE_CLASSIFICATION,
                             LATITUDE,LONGITUDE,
                             FIRE_SIZE,Shape)

## convert fire size to km2 from acer
ac2km = 0.00404686
short_ca    = short_ca %>% mutate(FIRE_SIZE = FIRE_SIZE*ac2km)

wrfbf_short      = data.frame()
for(y in short_yrs){
  yr_now = y
  bfrac_now     = short_ca %>% filter(FIRE_YEAR==yr_now)
  bfrac_now     = as.data.frame(bfrac_now)
  bfrac_now     = bfrac_now                                     %>% 
                  dplyr::select(LONGITUDE,LATITUDE,FIRE_SIZE)   
  rs_now        = rasterize(x=bfrac_now[,1:2]
                           ,y=wrf_rs
                           ,field=bfrac_now[,3]
                           ,fun=function(x,...){sum(x)},na.rm=TRUE)
  #rs_area       = area(rs_now)
  #rs_frac       = rs_now/rs_area
  df_now        = as.data.frame(rs_now,xy=TRUE)
  wrf_qry       = wrf_df
  nn_pt         = RANN::nn2(df_now[,1:2], wrf_qry[,1:2],k=1)
  wrf_qry$id    = as.vector(nn_pt$nn.idx)
  wrf_qry       = wrf_qry                             %>% 
                  mutate(barea = df_now$layer[id]
                        ,year  = yr_now)              %>% 
                  rename(lon=x_vec,lat=y_vec)         %>% 
                  dplyr::select(lon,lat,year,barea)
  wrfbf_short = rbind(wrfbf_short,wrf_qry)
}

wrfbf_short  = wrfbf_short  %>% filter(!is.na(barea))
data.table::fwrite(wrfbf_short,file.path(frap_path,"BArea-resampled-OnWRFDomain_SHORT.csv"))


## as WRF grids are in 9km by 9km cell, so we can directly calculate total cell area


grass_short = wrfbf_short
grass_short = grass_short             %>% 
  left_join(mask,by=c("lon","lat"))   %>% 
  filter(!is.na(mask))                
  
data.table::fwrite(grass_short,file.path(frap_path,"BArea-WRF-grassonly_SHORT.csv"))

tfrac_short = grass_short                                  %>% 
        group_by(year)                                     %>% 
        summarize(barea = sum(barea,na.rm=TRUE))           %>% 
        ungroup()                                          %>% 
        mutate(bfrac = barea/total_area
              ,source = "SHORT")             
        

short_time = unique(tfrac_short$year)

## calculate FRAP summed burned fraction using absolute burned area 
## so we can compare to SHORT data

tfrac_frap  = grass_frap                        %>% 
  group_by(year)                                %>% 
  summarize(barea = sum(barea,na.rm=TRUE))      %>% 
  ungroup()                                     %>% 
  mutate(bfrac = barea/total_area)              %>% 
 # filter(year %in% short_time)                  %>% 
  mutate(year = as.numeric(year)
        ,source="FRAP")

### combined burned area from SHORT and FRAP using 300 acer as threshold
short_sm    = grass_short                       %>% 
              mutate(barea = barea*247.105)     %>% 
              filter(barea<300)                 %>% 
              mutate(barea = barea/247.105)     %>% 
              mutate(lon=round(lon,5)
                    ,lat=round(lat,5))
com_two      = grass_frap                       %>% 
               mutate(lon=round(lon,5)
                     ,lat=round(lat,5))         %>% 
               rename(barea_f = barea)          %>% 
               left_join(short_sm,
                         by=c("lon","lat","year")) %>% 
              group_by(lon,lat,year)            %>% 
              summarize(tbarea = sum(barea_f,barea,na.rm=TRUE)) %>% 
              ungroup()                        %>% 
              group_by(year)                   %>% 
              summarize(barea=sum(tbarea))     %>% 
              mutate(bfrac = barea/total_area) %>% 
              ungroup()                        %>% 
              #filter(year %in% short_time)     %>% 
              mutate(source="COMBINE")
tfrac = rbind(tfrac_frap,tfrac_short,com_two)  

gg_now = ggplot(tfrac,aes(year,bfrac,colour=source)) + geom_line()+
         labs(x="",y="Total annual burned fraction") +
  theme_grey( base_size = gg_ptsz, base_family = "Helvetica",base_line_size= 0.5,base_rect_size =0.5)+
  theme(   legend.position   = "right" 
         , legend.title = element_blank()
         , legend.text = element_text(size=gg_ptsz-5)
         , panel.background = element_rect(linewidth  = 1.6, fill = NA)
         , panel.border = element_rect(linewidth = 1.6, fill=NA)
         , axis.text.x   = element_text( size   = gg_ptsz
                                         , margin = unit(rep(0.35,times=4),"cm"))#end element_text
         , axis.text.y       = element_text( size   = gg_ptsz
                                             , margin = unit(rep(0.35,times=4),"cm")
         )#end element_text
         , axis.ticks.length = unit(-0.25,"cm")
         ) #end theme
ggsave(gg_now, filename="short-frap-annualBF.png",path="~/Google Drive/My Drive/all/regional-runs",
       width=gg_widthn*0.6,height=gg_height*0.6,dpi=gg_depth,device=gg_device[1])
data.table::fwrite(tfrac,file.path(frap_path,"total-annual-BF-grasslands-3sources.csv"))

### we can combine frap and short by only selecting small size grass fire (<300 acer, threshold of FRAP)   
### from SHORT observations

grass_short = grass_short                      %>% 
              mutate(barea = barea*247.105)    %>% #km2 to acer
              filter(barea<300)                %>% 
              mutate(barea = barea/247.105
                    ,bfrac_short = barea/81)   %>% # WRF cell is 9km*9km 
              select(lon,lat,year,bfrac_short)
comba = grass_frap                                         %>% 
        left_join(grass_short,by=c("lon","lat","year"))    %>% 
        group_by(lon,lat,year)                             %>% 
        mutate(tfrac = sum(bfrac,bfrac_short,na.rm=TRUE))  %>% 
        ungroup()
data.table::fwrite(comba,file.path(frap_path,"annual-BF-grasslands-2sourcesCombined_bylonlat.csv"))  



              

