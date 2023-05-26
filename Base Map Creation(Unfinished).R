#ackage Calls
library(httr)
library(jsonlite)
library(dplyr)
library(ggmap)
library(rgdal)
library(htmltools)
library(mapview)
library(htmlwidgets)
library(openxlsx)
library(sf)
library(rgeos)
library(readxl)
library(writexl)
library(openxlsx)
library(data.table)
library(janitor)
library(lubridate)
library(stringr)
library(leaflet)
library(GISTools)
library(ggplot2)
#USEFUL TEXT CLEANING FUNCTIONS
trim <- function(x) gsub("^\\s+|\\s+$", "", x)
space <- function(x) gsub(",([[:alpha:]])", ", \\1",x)
singlespace<- function(x) gsub("  "," ",x)
misspell_clean <-function(dirtydf,refdf,dirtycol,refcol) {
  dirvec<-pull(dirtydf[dirtycol])
  refvec<-pull(refdf[refcol])
  for (i in 1:nrow(dirtydf)){
    dirvec[i] <- agrep(dirvec[i],refvec,value = TRUE,ignore.case = TRUE)[1] 
  }
  dirtydf[dirtycol]<-dirvec
  dirtydf}
datify<- function(x) {
  prop <- as.numeric(x)
  for (i in 1:length(prop)){
    if (!is.na(prop[i])){
      x[i]<-as.character(format(as.Date(excel_numeric_to_date(prop[i]), origin="1899-12-30"),'%m/%d/%Y'))
    }
  }
  x}
##CREATES MAIN DATAFRAME
#
#
  #Import current assignments and cleans column names(NEEDS NEW PATH)
  current_assignments <- read_xlsx(.../"Active.xlsx")
  colnames(current_assignments)[2] <- 'County'
  current_assignments <- current_assignments[1:172,]

  #Import past assignments and delete unnecessary columns(NEEDS NEW PATH)
    past_assignments <- read_xlsx(.../"Current Master Caseload 2020.xlsx", sheet = 1, col_names = TRUE, trim_ws = TRUE)
  #Heuristic Clean(Needs to be double-checked)  
  past_assignments <- past_assignments[1:167,c(2,3,5,6)]
  colnames(past_assignments)[2]<- 'Client'
  past_assignments[past_assignments$Client == 'Blanchart, Josephine',][2]<-'Blanchard, Josephine'
  #Import master legal docket(NEEDS NEW PATH AND FREQUENT UPDATING)
  master_legal <- read_xlsx(".../Master Legal Docket.xlsx", sheet = 1, col_names =  TRUE, trim_ws = TRUE)
  #This creates a new column of data in the form "First Initial. Last Name" to match clients
  #The following section creates this column for past assignment dataframe
  pa_name_splits <- strsplit(past_assignments$Client, ',')
  pa_last_name <- lapply(pa_name_splits, `[[`, 1) %>%
  lapply(function(x) trim(x)) %>%
  lapply(function(x) str_replace_all(x, "[(,)]", ""))
  pa_first_initial <- lapply(pa_name_splits, `[[`, 2 ) %>%
  lapply(function(x) trim(x)) %>%
  lapply(function(x) str_replace_all(x, "[(,)]", "")) %>%
  lapply(function(x) substr(x,1,1)) %>%
  lapply(function(x) paste(x, '.', sep = ''))
  pa_trunc_name <- paste(pa_first_initial, pa_last_name, sep =' ')
  past_assignments$trunc_name<-pa_trunc_name
  #The next  section creates is for the current assignment dataframe
  ca_name_splits <- strsplit(current_assignments$Client, ',')
  ca_last_name <- lapply(ca_name_splits, `[[`, 1) %>%
  lapply(function(x) trim(x)) %>%
  lapply(function(x) str_replace_all(x, "[(,)]", ""))
  ca_first_initial <- lapply(ca_name_splits, `[[`, 2 ) %>%
  lapply(function(x) trim(x)) %>%
  lapply(function(x) str_replace_all(x, "[(,)]", "")) %>%
  lapply(function(x) substr(x,1,1)) %>%
  lapply(function(x) paste(x, '.', sep = ''))
  ca_trunc_name <- paste(ca_first_initial, ca_last_name, sep =' ')
  current_assignments$trunc_name<-ca_trunc_name
  #Creation of desired fused dataframe of past assignment information with current team assignments
  ward_info_master <- left_join(current_assignments, past_assignments, by = 'trunc_name')
  ward_info_master <- ward_info_master[!is.na(ward_info_master$Client.y),]
  #Stylizing this new dataframe
  ward_info_master <- ward_info_master[c(7:10,6,1:5)]
  colnames(ward_info_master) <- c('Case Index','Client Name', 'Former Case Manager', 'Former Attorney', 'trunc_name', 'Drop Client', 'County', 'Current Attorney', 'Current Case Manager', 'Current Finanical Assistant')
  ward_info_master <- ward_info_master[-6] 
  #Heuristic Missing Data Cleaning(WILL BECOME OUTDATED) to add clients missing/misformatted in past caseloads
  Ridley <- c("100192-07","Ridley Jr., Edward", "Tonya", "Sarah", "E. Ridley Jr.", "Kings", "John", "Tonya", "Joel")
  Rodney <- c("5140-19","Rosser, Rodney", NA, NA, "R. Rosser", 'Queens', "Anne",	"Rose",	"Pat")
  ward_info_master<-rbind(ward_info_master, Ridley, Rodney)
  ward_info_master<-ward_info_master[-5]
  ward_info_master <- ward_info_master[!(ward_info_master$`Client Name`== 'Ridley, Jr. Edward'),]
  ward_info_master <- ward_info_master[!(ward_info_master$`Client Name`== 'Rosser, Charisse'),]
  #Assigns team number based on staff assignments
  ward_info_master$Team_number<- ifelse(ward_info_master$`Current Case Manager`=='Anthony', 1, 
                                      ifelse(ward_info_master$`Current Case Manager`=='Hamilton',2,
                                             ifelse(ward_info_master$`Current Case Manager`=='Danielle',3,
                                                    ifelse(ward_info_master$`Current Case Manager`=='Rose',4,
                                                           ifelse(ward_info_master$`Current Attorney`=='Sarah'& ward_info_master$`Current Finanical Assistant`=='Holly',5,
                                                                  ifelse(ward_info_master$`Current Case Manager`=='Mara',6,
                                                                         ifelse(ward_info_master$`Current Case Manager`=='Rachel',7,
                                                                                ifelse(ward_info_master$`Current Case Manager`=='Tonya',8,
                                                                                       ifelse(ward_info_master$`Current Case Manager`=='Bella',9, NA)))))))))
  ward_info_master <- left_join(ward_info_master, master_legal[c(2,7)], by = c('Case Index' = 'Index #'))

#
####
  #### Address Cleaning
  #Open Addresses and ward info from EMS(NEEDS PATH)
  address_list<-read.csv(".../Address List.csv", stringsAsFactors = FALSE)
  open_list <- read.csv(".../Open Status.csv", stringsAsFactors = FALSE)
  
  #Scraping desired columns from Address Info(Mildly Heuristic; Double Check column names and numbers)
  morph <- left_join(address_list, open_list, by = c('X_010_FIRST_NAME' = 'X_010_FIRST_NAME', 'X_030_LAST_NAME' = 'X_020_LAST_NAME'))
  morph$X_030_CASE_NUMBER <- trim(morph$X_030_CASE_NUMBER)
  active_address_list <- left_join(ward_info_master, morph[3:8], by = c('Case Index' = 'X_030_CASE_NUMBER'))
  colnames(active_address_list)<- c('Case Index', 'Client Name', 'Former Case Manager', 'Former Attorney', 'County', 'Current Attorney', 'Current Case Manager', 'Current Financial Assistant', 'Team Number', 'Commission Date','Address 1', 'Address 2', 'City', 'State', 'Zip')
  #Morphing current table formatting into desired formatting for addresses
  for (i in 1:nrow(active_address_list)){
    if (!is.na(as.numeric(substr(active_address_list$`Address 1`[i],1,1)))){
      active_address_list$`Address 2`[i] <- active_address_list$`Address 1`[i]
      active_address_list$`Address 1`[i] <- NA
    }
  }
  colnames(active_address_list)[11]<-'Facility Name'
  uncut_al <- active_address_list
  #Cleaning and standardizing address info by correcting frequently mispelled/abbreviations
  for (i in 1:nrow(active_address_list)){
    active_address_list$`Address 2`[i]<- gsub(",","",active_address_list$`Address 2`[i])
    if (grepl(' Street ', active_address_list$`Address 2`[i])) {
      active_address_list$`Address 2`[i]<- substr(active_address_list$`Address 2`[i],1, regexpr(' Street ', active_address_list$`Address 2`[i])[1]+6)}
    if (grepl(' street ', active_address_list$`Address 2`[i])) {
      active_address_list$`Address 2`[i]<- substr(active_address_list$`Address 2`[i],1, regexpr(' street ', active_address_list$`Address 2`[i])[1]+6)}
    if (grepl(' St. ', active_address_list$`Address 2`[i])) {
      active_address_list$`Address 2`[i]<- substr(active_address_list$`Address 2`[i],1, regexpr(' St. ', active_address_list$`Address 2`[i])[1]+2)}
    if (grepl(' St ', active_address_list$`Address 2`[i])) {
      active_address_list$`Address 2`[i]<- substr(active_address_list$`Address 2`[i],1, regexpr(' St ', active_address_list$`Address 2`[i])[1]+2)}
    if (grepl(' Avenue ', active_address_list$`Address 2`[i])) {
      active_address_list$`Address 2`[i]<- substr(active_address_list$`Address 2`[i],1, regexpr(' Avenue ', active_address_list$`Address 2`[i])[1]+6)}
    if (grepl(' Avenue. ', active_address_list$`Address 2`[i])) {
      active_address_list$`Address 2`[i]<- substr(active_address_list$`Address 2`[i],1, regexpr(' Avenue. ', active_address_list$`Address 2`[i])[1]+6)}
    if (grepl(' Blvd ', active_address_list$`Address 2`[i])) {
      active_address_list$`Address 2`[i]<- substr(active_address_list$`Address 2`[i],1, regexpr(' Blvd ', active_address_list$`Address 2`[i])[1]+4)}
    if (grepl(' Road ', active_address_list$`Address 2`[i])) {
      active_address_list$`Address 2`[i]<- substr(active_address_list$`Address 2`[i],1, regexpr(' Road ', active_address_list$`Address 2`[i])[1]+4)}
    if (grepl(' Road-', active_address_list$`Address 2`[i])) {
      active_address_list$`Address 2`[i]<- substr(active_address_list$`Address 2`[i],1, regexpr(' Road-', active_address_list$`Address 2`[i])[1]+4)}
    if (grepl(' Rd ', active_address_list$`Address 2`[i])) {
      active_address_list$`Address 2`[i]<- substr(active_address_list$`Address 2`[i],1, regexpr(' Rd ', active_address_list$`Address 2`[i])[1]+2)}
    if (grepl(' Ave ', active_address_list$`Address 2`[i])) {
      active_address_list$`Address 2`[i]<- substr(active_address_list$`Address 2`[i],1, regexpr(' Ave ', active_address_list$`Address 2`[i])[1]+3)}
    if (grepl(' Parkway ', active_address_list$`Address 2`[i])) {
      active_address_list$`Address 2`[i]<- substr(active_address_list$`Address 2`[i],1, regexpr(' Parkway ', active_address_list$`Address 2`[i])[1]+7)}
    if (grepl(' Oval ', active_address_list$`Address 2`[i])) {
      active_address_list$`Address 2`[i]<- substr(active_address_list$`Address 2`[i],1, regexpr(' Oval ', active_address_list$`Address 2`[i])[1]+4)}
    if (grepl(' Drive ', active_address_list$`Address 2`[i])) {
      active_address_list$`Address 2`[i]<- substr(active_address_list$`Address 2`[i],1, regexpr(' Drive ', active_address_list$`Address 2`[i])[1]+5)}
    if (grepl(' Ave. ', active_address_list$`Address 2`[i])) {
      active_address_list$`Address 2`[i]<- substr(active_address_list$`Address 2`[i],1, regexpr(' Ave. ', active_address_list$`Address 2`[i])[1]+5)}
  }
  #Manual Data Cleaning to heurisitcally cover gaps in previous step
  active_address_list[active_address_list$`Client Name`=='Drayton, Isabel',][12]<-'98 St Marks Place'
  active_address_list[active_address_list$`Client Name`=='Phillips, Aurea',][12]<-'185 Ave C'
  #Creates a database that will be geocoded by Google's API
  geocode_list <- active_address_list
  geocode_list$Address <- str_c(geocode_list$`Address 2`, geocode_list$City, geocode_list$State, sep = ' ')
  ####
  #### Geocoding Address List
  #Register Google API key and specify target dataframe to be encoded
  register_google(key = 'AIzaSyCeM0A73f9u54Y6Pk39u9uQsIw_47raz80')
  Active_Client_Geocode <- geocode_list
  #Filtering Data to map only NYC residents
  Active_Client_Geocode <- Active_Client_Geocode %>%
    filter(State == 'NY') %>%
    filter(City != 'Yonkers')
  #Geocoding using the Google API
  for (i in 1:nrow(Active_Client_Geocode)){
    if (!is.na(Active_Client_Geocode$Address[i])){
      query <- geocode(Active_Client_Geocode$Address[i])
      Active_Client_Geocode$Latitude[i]<- query[2]               
      Active_Client_Geocode$Longitude[i] <- query[1]
    }
  }
  #Translating county names into boroughs
  Active_Client_Geocode$Borough <- Active_Client_Geocode$County
  for (i in 1:nrow(Active_Client_Geocode)){
    if (!is.na(Active_Client_Geocode$Borough[i])){  
      if (Active_Client_Geocode$Borough[i] == 'Kings'){
        Active_Client_Geocode$Borough[i] <- 'Brooklyn'
      }
      if (Active_Client_Geocode$Borough[i] == 'Richmond'){
        Active_Client_Geocode$Borough[i] <- 'Staten Island'
      }
      if (Active_Client_Geocode$Borough[i] == 'New York'){
        Active_Client_Geocode$Borough[i] <- 'Manhattan'
      }}
  }
  ####
  #### Mapping
#Import relevant demographic data and join(NEEDS NEW PATH)
active_client_race<- read_xlsx(".../Active Clients Race Info.xlsx",col_names = TRUE, trim_ws = TRUE)
active_client_religion<- read_xlsx(".../Active Clients Religion Info.xlsx",col_names = TRUE, trim_ws = TRUE)
Active_Client_Geocode<-left_join(Active_Client_Geocode,active_client_race)
#Using point-in-point algorithm to collect aggregates by borough and district
countvector <- {}
for (i in 1:length(as.character(boroughs$boro_name))){
  countvector <- append(countvector, nrow(Active_Client_Geocode[Active_Client_Geocode$Borough == as.character(boroughs$boro_name[i]),]))
}
boroughs@data$count<-countvector
client_points<-st_as_sf(Active_Client_Geocode[c(17,18)],coords = c("Longitude", "Latitude"),crs = "+proj=longlat +datum=WGS84")
client_points<-as_Spatial(client_points)
countvector <- poly.counts(pts = client_points, polys = city_council_districts)
city_council_districts$counts<-countvector
#Define color pallettes
borcol<-colorFactor(topo.colors(5), boroughs$boro_name)
boroughcolors <- colorNumeric(palette = 'Blues', domain = boroughs$count )
cccolors <- colorNumeric(palette = 'Reds', domain = city_council_districts$counts)
pal <- colorFactor(c('red','orange','yellow','green','blue','purple','pink','#239C37', 'Brown'), domain = c(1,2,3,4,5,6,7,8,9))
#Map Creation
Client_Residence_Map <- leaflet(Active_Client_Geocode) %>%
  addProviderTiles(providers$CartoDB.Positron, group = 'Street View')%>%
  addPolygons(data = boroughs,
              fillColor = ~boroughcolors(boroughs$count),
              fillOpacity = 1,v
              group = 'Aggregates by Borough of Commission',
              label =  boroughs$count)%>%
  addPolygons(data = city_council_districts,
              fillColor = ~cccolors(city_council_districts$counts),
              fillOpacity = 1,
              color = 'grey',
              group = 'Aggregates by City Council District',
              label = paste('City Council District ', city_council_districts$coun_dist,': ', city_council_districts$counts," clients", sep = '')
              )%>%
  addPolygons(data = city_council_districts,
              fillColor = ~cccolors(city_council_districts$counts),
              fillOpacity = 0,
              color = 'grey',
              group = 'Aggregates by Borough of Commission',
              
  )%>%
  addCircleMarkers(lng = as.numeric(Active_Client_Geocode$Longitude),
                 lat = as.numeric(Active_Client_Geocode$Latitude),
                 label = Active_Client_Geocode$`Client Name`,
                 radius = 3,
                 group = 'Clients',
                 color = ~pal(`Team Number`),
                 opacity = 1,
                 
                )%>%
  addMarkers(lng = as.numeric(Active_Client_Geocode[!is.na(Active_Client_Geocode$`Facility Name`),]$Longitude),
                   lat = as.numeric(Active_Client_Geocode[!is.na(Active_Client_Geocode$`Facility Name`),]$Latitude),
                   label = Active_Client_Geocode[!is.na(Active_Client_Geocode$`Facility Name`),]$`Facility Name`,
                   group = 'Facilities')%>%
  addLayersControl(
    baseGroups = c('Basemap','Aggregates by Borough of Commission','Aggregates by City Council District'),
    overlayGroups = c("Clients", 'Facilities', 'Street View'),
    options = layersControlOptions(collapsed = TRUE)
  )%>%
  addLegend("bottomright", pal = pal, values = 1:9,
            labFormat = labelFormat(prefix = "Team "),
            opacity = 1,
            group = 'Clients'
  )%>%
  addLegend("bottomleft", pal = cccolors, values = min(city_council_districts$counts):max(city_council_districts$counts),
            opacity = 1,
            group = 'Aggregates by City Council District',
            title = 'Number of Clients'
  )%>%
 
  hideGroup('Facilities')%>%
  hideGroup('Aggregates by Borough of Commission')%>%
  hideGroup('Aggregates by City of Council District')

Client_Residence_Map
#Export
saveWidget(Client_Residence_Map, 'C:/Carlyle/Reference Pool/ClientResidenceMap')

