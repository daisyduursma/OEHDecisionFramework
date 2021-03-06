#
# This is a Shiny web application. You can run the application by clicking
# the 'Run App' button above.
#
# Find out more about building applications with Shiny here:
#
#    http://shiny.rstudio.com/
#

library(shiny)
#get test data
library(rgdal)
require(cluster) 
library(leaflet)
library(leaflet.extras)
library(sp)

source("AppFunctions/extractEnviroData.R", local = T)
source("AppFunctions/plotEnviroHists.R", local = T)
source("AppFunctions/ClusterAnalysis.R", local = T)



  
# Define UI for application that draws a histogram
ui <- fluidPage(
   
   # Application title
   titlePanel("Cluster analysis"),
   
   # Sidebar to select inputs
   sidebarLayout(
     sidebarPanel(
       selectInput("tmax", "Avg. annual Tmax", c("yes","no")),
       selectInput("rain", "Avg. annual rainfall", c("yes","no")),
       selectInput("rainVar", "Avg. annual rainfall variability", c("yes","no")), 
       selectInput("elev", "Elevation", c("yes","no")),
       selectInput("soils", "Soil type", c("yes","no")),
       numericInput('clusters', 'Cluster count',2,
                    min = 2, max = 9)
     ),
     
     mainPanel( 
       # Choices for the drop-downs menu, colour the points by selected variable in map, "cluster", "tmax", etc. are the names in the data after the cluster analysis is run
       vars <- c(
          "Cluster" = "cluster",
          "Avg. annual Tmax" = "tmax",
          "Avg. annual rainfall" = "rain",
          "Avg. annual rainfall variability" = "rainVar",
          "Elevation" = "elev",
          "Soil type" = "soil"
       ),
       
       #sets location for base leaflet map and make dropdown menu to select the backgroudn map
       leafletOutput('ClusterPlot'),
       absolutePanel(top = 45, right = 20, width = 150, draggable = TRUE,
                     selectInput("bmap", "Select base map", 
                                 choices =  c("Base map",
                                              "Satellite imagery"), 
                                 selected = "Base map"),
                     selectInput("variable", "Display Variable", vars)
                     
                     )
     )
   )
   
)








# Define server logic required to draw a histogram
server <- function(input, output) {
  ################## in the real app this aleady  exists
          #get the data set up
          source("AppFunctions/extractEnviroData.R", local = T)
          sp<-"Acacia acanthoclada"
          spdat<-read.csv("AppEnvData/SpeciesObservations/SOSflora.csv",header=TRUE)
          spdat<-subset(spdat,Scientific==sp)
          sites<-readOGR("AppEnvData/ManagmentSites/OEHManagmentSites.shp")
        
          spdat$lat <- spdat[, "Latitude_G"]
          spdat$long <- spdat[, "Longitude_"]
          dat<-EnvExtract(spdat$lat,spdat$long)
        
          #select site data
          coords <- dat[,c("long","lat")]
          coordinates(coords) <-c("long","lat")
          proj4string(coords)<-crs(sites)
        
          managmentSite <- sites[sites$SciName == sp,]
          EnvDat<-cbind(dat,over(coords,managmentSite,returnList = FALSE))
  ################################ 
  #perform cluster analysis
  variablesUSE <- c("soil", "elev", "rain", "tmax", "rainVar") #this needs to be reacitve
  clusters<-4 #this needs to be reactive
  clusDat<-  EnvCluserData(EnvDat,variablesUSE,clusters) #make reactive
  
  
  
  # generate two set of unique location IDs
  #the unique id’s are needed to color the locations we select. 
  clusDat$locationID <- paste0(as.character(1:nrow(clusDat)), "_ID")
  clusDat$secondLocationID <- paste0(clusDat$LocationID, "_selectedLayer")
  
  #######################
  #make coordinates from the clusDat, this will be used when selecting points for SOS managment sites
  ClusCoordinates <- SpatialPointsDataFrame( clusDat[,c('long', 'lat')] , clusDat)#reactive?
  
  
  # list to store the selections for tracking
  data_of_click <- reactiveValues(clickedMarker = list())
  
  #make empty leaflet plot, this has the boundaries of the species data, but no points
  output$ClusterPlot <- renderLeaflet({
       #get base map name
       if(input$bmap== "Base map"){
         mapType<-"OpenStreetMap.Mapnik"
       }
       if(input$bmap== "Satellite imagery"){
         mapType<-"Esri.WorldImagery"
       }
       #main map
       leaflet() %>%
         addProviderTiles(mapType) %>%
         fitBounds(min(clusDat$long), min(clusDat$lat), max(clusDat$long), max(clusDat$lat))
   })
  
  #set colouring options for factors and numeric variables
  observe({
    colorBy <- input$variable
    if (colorBy == "tmax" |colorBy =="rain" |colorBy =="elev") {
      # Color and palette if the values are  continuous.
      colorData <- clusDat[[colorBy]]
      pal <- colorBin("viridis", colorData, 7, pretty = FALSE)
     } else {
     colorData <- clusDat[[colorBy]]
    pal <- colorFactor("viridis", colorData)
    }

    #updating points on map based on selected variable and menu to draw polygons
    leafletProxy("ClusterPlot", data = clusDat) %>% #adds points to the graph
      clearShapes() %>%
      addCircles(~long, ~lat, 
                 radius=5000,
                 fillOpacity=1, 
                 fillColor=pal(colorData),
                 weight = 2,
                 stroke = T,
                 layerId = as.character(clusDat$locationID),
                 highlightOptions = highlightOptions(color = "deeppink",
                                                     fillColor="deeppink",
                                                     opacity = 1.0,
                                                     weight = 2,
                                                     bringToFront = TRUE)) %>%
      addLegend("bottomleft", pal=pal, values=colorData, 
                layerId="colorLegend")%>% #legend for varibales
      
      addDrawToolbar( #toolbar to drawshapes
                targetGroup='Selected',
                polylineOptions=FALSE,
                markerOptions = FALSE,
                polygonOptions = drawPolygonOptions(shapeOptions=drawShapeOptions(fillOpacity = 0
                                                                                  ,color = 'black'
                                                                                  ,weight = 3)),
                rectangleOptions = drawRectangleOptions(shapeOptions=drawShapeOptions(fillOpacity = 0
                                                                                      ,color = 'black'
                                                                                      ,weight = 3)),
                circleOptions = drawCircleOptions(shapeOptions = drawShapeOptions(fillOpacity = 0
                                                                                  ,color = 'black'
                                                                                  ,weight = 3)),
                editOptions = editToolbarOptions(edit = FALSE, selectedPathOptions = selectedPathOptions()))

  })
  
  
  ############subsetting obseration to get those inside the polygons ##################
  observeEvent(input$mymap_draw_new_feature,{#tells r-shiny that if the user draws a shape return all teh uighe locations based on the location ID
    #Only add new layers for bounded locations
    found_in_bounds <- findLocations(shape = input$mymap_draw_new_feature
                                     , location_coordinates = ClusCoordinates
                                     , location_id_colname = "locationID")
    
    for(id in found_in_bounds){
      if(id %in% data_of_click$clickedMarker){
        # don't add id
      } else {
        # add id
        data_of_click$clickedMarker<-append(data_of_click$clickedMarker, id, 0)
      }
    }
    
    # look up clusDat by ids found
    selected <- subset(clusDat, locationID %in% data_of_click$clickedMarker)
    
    proxy <- leafletProxy("ClusterPlot")
    proxy %>%  addCircles(data = selected,
                         radius = 6000,
                         lat = selected$lat,
                         lng = selected$long,
                         fillColor = "red",
                         fillOpacity = 1,
                         color = "red",
                         weight = 3,
                         stroke = T,
                         layerId = as.character(selected$secondLocationID),
                         highlightOptions = highlightOptions(color = "purple",
                                                             opacity = 1.0,
                                                             weight = 2,
                                                             bringToFront = TRUE))
    
  })

#   ############################################### section four ##################################################
  observeEvent(input$mymap_draw_deleted_features,{
    # loop through list of one or more deleted features/ polygons
    for(feature in input$mymap_draw_deleted_features$features){

      # get ids for locations within the bounding shape
      bounded_layer_ids <- findLocations(shape = feature
                                         , location_coordinates = ClusCoordinates
                                         , location_id_colname = "secondLocationID")


      # remove second layer representing selected locations
      proxy <- leafletProxy("ClusterPlot")
      proxy %>% removeShape(layerId = as.character(bounded_layer_ids))

      first_layer_ids <- subset(clusDat, secondLocationID %in% bounded_layer_ids)$locationID

      data_of_click$clickedMarker <- data_of_click$clickedMarker[!data_of_click$clickedMarker
                                                                 %in% first_layer_ids]
    }
  })
# },


  
}


findLocations <- function(shape, location_coordinates, location_id_colname){
  
  # derive polygon coordinates and feature_type from shape input
  polygon_coordinates <- shape$geometry$coordinates
  feature_type <- shape$properties$feature_type
  
  if(feature_type %in% c("rectangle","polygon")) {
    
    # transform into a spatial polygon
    drawn_polygon <- Polygon(do.call(rbind,lapply(polygon_coordinates[[1]],function(x){c(x[[1]][1],x[[2]][1])})))
    
    # use 'over' from the sp package to identify selected locations
    selected_locs <- sp::over(location_coordinates
                              , sp::SpatialPolygons(list(sp::Polygons(list(drawn_polygon),"drawn_polygon"))))
    
    # get location ids
    x = (location_coordinates[which(!is.na(selected_locs)), location_id_colname])
    
    selected_loc_id = as.character(x[[location_id_colname]])
    
    return(selected_loc_id)
    
  } else if (feature_type == "circle") {
    
    center_coords <- matrix(c(polygon_coordinates[[1]], polygon_coordinates[[2]])
                            , ncol = 2)
    
    # get distances to center of drawn circle for all locations in location_coordinates
    # distance is in kilometers
    dist_to_center <- spDistsN1(location_coordinates, center_coords, longlat=TRUE)
    
    # get location ids
    # radius is in meters
    x <- location_coordinates[dist_to_center < shape$properties$radius/1000, location_id_colname]
    
    selected_loc_id = as.character(x[[location_id_colname]])
    
    return(selected_loc_id)
  }
}


# Run the application 
shinyApp(ui = ui, server = server)

