library(shiny)
library(shinyjs)
library(shinyBS)
library(ggplotify)
library(RColorBrewer)
library(reshape)
library(ggplot2)
source("path_grid_plot.R")
source("enrich_functions.R")
source("goHier.R")
source("kegg_mats.R")
library(org.Hs.eg.db)
library(org.Mm.eg.db)
library(tibble)
library(gProfileR)
library(readxl)
library(DT)
library(randomcoloR)
library(shinycssloaders)
set.seed(12)

load(file ="updated_kegg_hierarhcy.RData")
load("mm_reactome_hierarchy.RData")
load("hm_reactome_hierarchy.RData")
reduced_kegg_hierarchy = kegg_hierarchy

shinyServer(function(input, output,session) {
  gVars <- shiny::reactiveValues(
    KEGG_MAT=NULL,
    lev1_h = NULL,
    lev2_h = NULL,
    lev3_h = NULL,
    n_groups = NULL,
    hierarchy = NULL,
    GList = NULL,
    pheno = NULL, #original pheno, used as backup
    exp_ann = NULL,
    reduced_kegg_hierarchy = NULL,
    toPlot = NULL,
    toPlotMap = NULL,
    clust_mat = NULL,
    samplesID = NULL,
    nSamples = NULL,
    nPath = NULL
    #gVars$noEnrich = NULL
  )
  
  output$chose_lev1 <- renderUI({
    print("Render gui")
    selectInput("lev1", "Level 1", gVars$lev1_h,multiple = TRUE,selected = "All")
  })
  
  output$nClust <- renderUI({
    if(is.null(gVars$KEGG_MAT)){
      opt = c("N/A")
    }else{
      opt = 1:nrow(gVars$KEGG_MAT)
    }
    selectInput("nc", "Number of clusters", opt,multiple = FALSE,selected = 1)
  })
  
  output$chose_lev2 <- renderUI({
    # print(input$lev1)
    print("inside chose lev 2")
    
    need(input$lev1 != "", "Please select a level 1 object")
    
    if(is.null(input$lev1)){
      selectInput("lev2", "Level 2", gVars$lev2_h,multiple = TRUE,selected = "All")
    }else{
      if("All" %in% input$lev1){
        print("all in lev1")
        
        selectInput("lev2", "Level 2", gVars$lev2_h,multiple = TRUE,selected = "All")
      }else{
        if(length(input$lev1)==1){
          print("length is 1")
          #selectInput("lev2", "Level 2", as.list(lev2_h[[input$lev1]]),multiple = TRUE)
          selectInput("lev2", "Level 2", as.list(c("All",gVars$lev2_h[[input$lev1]])),multiple = TRUE,selected = "All")
          
        }else{
          print("length is greater than 1")
          #selectInput("lev2", "Level 2", lev2_h[input$lev1],multiple = TRUE)
          selectInput("lev2", "Level 2", c("All",gVars$lev2_h[input$lev1]),multiple = TRUE,selected = "All")
          
        }
      }      
    }
  })
  
  output$chose_lev3 <- renderUI({
    print("inside chose lev 2")
    need(input$lev1 != "", "Please select a level 1 object")
    need(input$lev2 != "", "Please select a level 2 object")
    
    if(is.null(input$lev2)){
      selectInput("lev3", "Level 3", gVars$lev3_h,multiple = TRUE,selected = "All")
    }else{
      if("All" %in% input$lev2){
        print("all in lev1")
        
        selectInput("lev3", "Level 3", gVars$lev3_h,multiple = TRUE,selected = "All")
      }else{
        if(length(input$lev2)==1){
          print("length is 1")
          selectInput("lev3", "Level 3", as.list(c("All",gVars$lev3_h[[input$lev2]])),multiple = TRUE,selected = "All")
        }else{
          print("length is greater than 1")
          selectInput("lev3", "Level 3", c("All",gVars$lev3_h[input$lev2]),multiple = TRUE,selected = "All")
        }
      }      
    }
  })
  
  output$selectColumn <- renderUI({
    selectInput("colID","Select samples",c("All",rownames(gVars$KEGG_MAT)),multiple=TRUE,selected = "All")
  })
  
  # output$valueType <- renderUI({
  #   radioButtons("MapValueType","Choose Values Type",
  #                choices = c(Pvalue = "PVAL", FoldChange="FC",FoldChange_PValue  = "FCPV"),
  #                selected = "FC")
  # })
  
  DATA <- reactive({
    # input$file1 will be NULL initially. After the user selects
    # and uploads a file, head of that data file by default,
    # or all rows if selected, will be shown.
    
    if(is.null(input$file1)){
      return(NULL)
    }
    #nSample = as.numeric(input$nSample)
    DTa = NULL
    # when reading semicolon separated files,
    # having a comma separator causes `read.csv` to error
    tryCatch(
      {
        DF = read_excel_allsheets(filename = input$file1$datapath,tibble = FALSE)
        print(head(DF[[1]]))      
        
        GList = DF[1:(length(DF)-1)]
        print("after GList")
        print(length(GList))
        GList = convert_genes(organism = input$organism, GList=GList, annType = input$idtype)
        
        print("gene converted")
        Mp = DF[[length(DF)]]
        pheno = cbind(Mp[,2],Mp[,1])
        gVars$GList = GList
        gVars$pheno = pheno
        gVars$exp_ann = gVars$pheno
        
        print(gVars$pheno)
        
        DTa = matrix("",ncol = length(GList),nrow = max(unlist(lapply(GList, FUN = nrow))))
        for(i in 1:(length(DF)-1)){
          DTa[1:nrow(GList[[i]]),i]=GList[[i]][,1]
        }
        
        print(dim(DTa))
        
        colnames(DTa) = names(GList)
      },
      error = function(e) {
        # return a safeError if a parsing error occurs
        shinyjs::info(e$message)
      }
    )
    if(is.null(DTa)){
      return(NULL)
    }else{
      return(DTa)
    }
  })
  
  
  
  #output$results <- DT::renderDataTable(
  #  mtcars,
  #  options = list(scrollX = TRUE)
  #)
  
  output$contents <- DT::renderDataTable({ #renderTable
    print("Inside contents")
    
    DF = DATA()
    shiny::validate(need(expr = !is.null(DF),message = "Waiting for input file!") )
    
    # if(input$disp == "head") {
    #   print("header")
    #   return(head(DF))
    # }
    # else {
    #   return(DF)
    # }
    
    DT::datatable(DF, options = list(scrollX = TRUE))
    #return(DF)
    
  })
  
  output$updatedTable <- renderText({
    print("updata table")
    DF = DATA()
    shiny::validate(need(expr = !is.null(DF),message = "") )
    
    x = paste("Number of genes for each sample: ",sep="")
    return(x)
  })
  
  output$colSums <- DT::renderDataTable({
    print("Inside colSums")
    
    
    DF = DATA()
    shiny::validate(need(expr = !is.null(DF),message = "") )
    
    M = matrix("",1,ncol = ncol(DF))
    for(i in 1:ncol(DF)){
      M[1,i]= sum(DF[,i]!="")
    }
    colnames(M) = colnames(DF)
    DT::datatable(M, options = list(scrollX = TRUE))
    
    #return(M)
  })
  
  
  observeEvent(input$computePathways,{
    shinyjs::html(id="loadingText", "COMPUTING ENRICHMENT")
    shinyjs::show(id="loading-content")
    print("I'm working....")
    req(input$computePathways)
    req(input$organism)
    req(input$idtype)
    #req(input$fileType)
    gVars$toPlot <- NULL # refresh plot map in the Plot Maps tab
    gVars$clust_mat <- NULL
    gVars$KEGG_MAT <- NULL

    
    DAT = DATA()    
    if(input$organism == "Mouse"){          
      org = "mmu"
      reactome_hierarchy = mm_reactome_hierarchy
      reactome_hierarchy$ID = unlist(reactome_hierarchy$Pathway)
      org_enrich = "mmusculus"
      reactome_hierarchy[,1] = mouse_map[reactome_hierarchy[,1],2]
      reactome_hierarchy[,2] = mouse_map[unlist(reactome_hierarchy[,2]),2]
      reactome_hierarchy[,3] = mouse_map[unlist(reactome_hierarchy[,3]),2]
    }else{
      org = "hsa"
      reactome_hierarchy = hm_reactome_hierarchy
      reactome_hierarchy$ID = unlist(reactome_hierarchy$Pathway)
      reactome_hierarchy[,1] = human_map[reactome_hierarchy[,1],2]
      reactome_hierarchy[,2] = human_map[unlist(reactome_hierarchy[,2]),2]
      reactome_hierarchy[,3] = human_map[unlist(reactome_hierarchy[,3]),2]
      org_enrich = "hsapiens"
    }
    
    ####### remove reactome duplicates
    reactome_hierarchy=unique(reactome_hierarchy)
    
    # Compute enrichment
    
    annType = input$EnrichType
    GOType = input$GOType
    
    #annType = "KEGG"
    #GOType = "BP"
    
    if(annType=="KEGG"){
      #EnrichDatList = all_KEGG  
      gVars$hierarchy = kegg_hierarchy
      type_enrich = "KEGG"
      
    }
    if(annType=="REACTOME"){
      #EnrichDatList = all_REACT 
      type_enrich = "REAC"
      gVars$hierarchy = reactome_hierarchy
      
    }
    if(annType=="GO"){
      if(GOType == "BP"){
        #EnrichDatList = all_GO_BP
        #create geograph object
        makeGOGraph(ont = "bp") -> geograph
        #convert graphNEL into igraph
        igraph.from.graphNEL(geograph) -> igraphgeo
        #make igraph object undirected
        igraphgeo = as.undirected(igraphgeo)
        #set root as BP root term
        root = "GO:0008150"
        type_enrich = "GO:BP"
        
      }
      if(GOType == "CC"){
        #EnrichDatList = all_GO_CC
        makeGOGraph(ont = "cc") -> geograph
        igraph.from.graphNEL(geograph) -> igraphgeo
        igraphgeo = as.undirected(igraphgeo)
        root="GO:0005575"
        type_enrich = "GO:CC"
        
      }
      if(GOType == "MF"){
        #EnrichDatList = all_GO_MF
        makeGOGraph(ont = "mf") -> geograph
        igraph.from.graphNEL(geograph) -> igraphgeo
        igraphgeo = as.undirected(igraphgeo)
        root="GO:0003674"
        type_enrich = "GO:MF"
        
      }
    }
    
    
    EnrichDatList = lapply(gVars$GList,enrich,type_enrich,org_enrich,as.numeric(input$pvalueTh),input$pcorrection)
    #save(EnrichDatList,file = "demo/EnrichDatList.RData")

    if(input$EnrichType == "GO"){
      #find the list of term into  the enriched list
      res2 = filterGO(EnrichDatList,go_type = input$GOType)
      EnrichDatList = res2$EnrichDatList
      go_terms = res2$goTerm
      print("compute GO hierarchy")
      
      #Compute all the shortest path between the root to the go_terms
      asp = all_shortest_paths(graph = igraphgeo,from = root, to = go_terms)
      
      #reduce the shortest path to length 3 to build a 3 level hierarchy
      go_hierarchy = matrix("",nrow = length(asp$res),ncol = 3)
      
      for(i in 1:length(asp$res)){
        nn = names(asp$res[[i]])
        nn = nn[2:length(nn)]
        if(length(nn)<3){
          nn2 = rep(nn[length(nn)],3)
          nn2[1:length(nn)] = nn
        }else{
          nn2 = c(nn[1:2],nn[length(nn)])
        }
        go_hierarchy[i,] =nn2   
      }
      
      go_hierarchy = unique(go_hierarchy)
      colnames(go_hierarchy) = c("level1","level2","level3")
      go_hierarchy = as.data.frame(go_hierarchy)
      go_hierarchy$ID = go_hierarchy[,3]
      
      idx = which(is.na(go_hierarchy[,1]))
      if(length(idx)>0){
        go_hierarchy = go_hierarchy[-idx,]
      }
      go_hierarchy[,1] = Term(GOTERM[as.character(go_hierarchy[,1])])
      go_hierarchy[,2] = Term(GOTERM[as.character(go_hierarchy[,2])])
      go_hierarchy[,3] = Term(GOTERM[as.character(go_hierarchy[,3])])
      
      # colnames(hier_names) = c("Level1","Level2","Pathway")
      gVars$hierarchy = go_hierarchy
      print(gVars$hierarchy)

    }
    
    print(head(gVars$hierarchy))
    
    NCol = ncol(gVars$GList[[1]])
    print("NCol -------- >>>>> ")
    print(NCol)
    
    #if(input$fileType %in% "GenesOnly"){
    if(input$MapValueType == "PVAL"){
      print("only genes")
      M = kegg_mat_p(EnrichDatList,hierarchy = gVars$hierarchy)
    }else{
      
      if(NCol==1){
        shinyjs::info("No Modification provided! Enrichment will be performed by using only pvalues")
        M = kegg_mat_p(EnrichDatList,hierarchy = gVars$hierarchy)
        
      }else{
        M1 = kegg_mat_p(EnrichDatList,hierarchy = gVars$hierarchy)
        M2 = kegg_mat_fc(EnrichDatList = EnrichDatList,hierarchy = gVars$hierarchy,GList = gVars$GList, summ_fun=get(input$aggregation))
        
        print("LOGGGGG")
        
        # if(input$MapValueType == "PVAL"){
        #   M = M1
        # }
        if(input$MapValueType == "FC"){
          M = M2
        }
        if(input$MapValueType == "FCPV"){
          M = M2 * -log(M1)
        }
        rownames(M) = rownames(M1)
        colnames(M) = colnames(M1)
      }

    }

    gVars$KEGG_MAT = M
    
    hierarchy <- collapse_paths(kegg_hierarchy =gVars$hierarchy,kegg_mat_cell = gVars$KEGG_MAT, collapse_level = 3)
    mat <- hierarchy[[1]]
    hier <- hierarchy[[2]]
    
    print(hier)
    
    gVars$lev1_h = as.list(c("All",unique(as.character(hier[,1]))))
    
    gVars$lev2_h = list("All" = "All")
    for(i in unique(hier[,1])){
      gVars$lev2_h[[i]] = as.character(unique(hier[which(hier[,1] %in% i),2]))
    }
    
    gVars$lev3_h = list("All" = "All")
    for(i in unique(hier[,2])){
      gVars$lev3_h[[i]] = as.character(unique(hier[which(hier[,2] %in% i),3]))
    }
    
    on.exit({
      print("inside on exit")
      shinyjs::hide(id="loading-content", anim=TRUE, animType="fade")    
    })
    
    output$updatedPat <- renderText({
      DF = DATA()
      shiny::validate(need(expr = !is.null(DF),message = "") )
      
      x = paste("Pathway computed! Number of pathways for each sample: ")
      
      return(x)
    })
    
    output$colSumsPat <- DT::renderDataTable({
      DF = gVars$KEGG_MAT
      shiny::validate(need(expr = !is.null(DF),message = "") )
      
      M = matrix("",1,ncol = nrow(DF))
      for(i in 1:nrow(DF)){
        M[1,i]= sum(is.na(DF[i,])==FALSE)
      }
      colnames(M) = rownames(DF)
      #print(M)
      DT::datatable(M, options = list(scrollX = TRUE))
      
      #if(sum(M) ==0) gVars$noEnrich = TRUE
      
    })
    
    updateTabsetPanel(session = session,inputId = "page_id", selected = "PlotMaps")
  })
  
  output$heatmap <- renderPlot({
    shiny::validate(need(expr = !is.null(gVars$toPlot),message = "No data to plot"))
    print(class(gVars$toPlot))
    print(as.ggplot(gVars$toPlot))

  }, width = function(){
    if(!is.null(gVars$nSamples)){
      #
      mwidth = (gVars$length_path * 15) + (gVars$nSamples * 20)
      print(paste("MY sample IS ---->", gVars$nSamples))
      print(paste("MY path len IS ---->", gVars$length_path))
      print(paste("MY WIDTH IS ---->", mwidth))
      
      mwidth = max(600, mwidth)
      
      return(mwidth)
    }else{
      return("auto")
    }
  },  height = function(){
    
    if(!is.null(gVars$nPath)){
      mysize = (gVars$nPath* 20 ) + 10 * max(sapply(gVars$exp_ann,nchar))
      print(paste("MY HEIGHT IS ---->", mysize))
      
      print(paste("MY path IS ---->", gVars$nPath))
      mysize = min(max(600, mysize),30e3)
      
      return(mysize)
    }else{
      return("auto")
    }
  })
  


  observeEvent(input$do, {
    
    shinyjs::html(id="loadingText", "Rendering Map")
    shinyjs::show(id="loading-content")
    on.exit({
      print("inside on exit")
      shinyjs::hide(id="loading-content", anim=TRUE, animType="fade")    
    })
    # print("input lev1 is the following ---->")
    # print(input$lev1)
    need(is.null(input$lev1), "Please select a level 1 object")
    need(is.null(input$lev2), "Please select a level 2 object")
    need(is.null(input$lev3), "Please select a level 3 object")
    need(is.null(input$lev1), "Please select a level 1 object")
    need(is.null(input$lev2), "Please select a level 2 object")
    need(is.null(input$lev3), "Please select a level 3 object")
    
    print("INSIDE RENDER PLOT ----->>>>")
    print("Inside object event input$do")
    

    l1 = input$lev1
    l2 = input$lev2
    l3 = input$lev3
    
#    print(head(gVars$hierarchy))
    gVars$reduced_kegg_hierarchy = update_hierarchy(kegg_hierarchy = gVars$hierarchy ,l1,l2,l3)
#    print("Reduced Kegg hierarchy -->")
#    print(head(gVars$reduced_kegg_hierarchy))
    
    gVars$samplesID = input$colID
    
#    print(gVars$samplesID)
    
    if(!is.null(gVars$clust_mat)){
      # print("I did cluster")
      if("All" %in% gVars$samplesID){
        #  print("I WANT ALL SAMPLES")
        gVars$toPlotMap =gVars$clust_mat
      }else{
        gVars$toPlotMap = gVars$clust_mat[rownames(gVars$clust_mat) %in% gVars$samplesID,]
      }
    }else{
      if("All" %in% gVars$samplesID){
        #  print("I WANT ALL SAMPLES")
        gVars$toPlotMap = gVars$KEGG_MAT
      }else{
        gVars$toPlotMap = gVars$KEGG_MAT[rownames(gVars$KEGG_MAT) %in% gVars$samplesID,]
      }
      
    }
    
    #controlla anche la selezione di righe e colonne
    #gVars$toPlot = plot_function(gcl = gVars$clust_mat,kegg_h = gVars$reduced_kegg_hierarchy,plt_mat = gVars$toPlotMap,input_n=as.numeric(input$level))
      
    
    kegg_nano_1 <- collapse_paths(kegg_hierarchy = gVars$reduced_kegg_hierarchy,kegg_mat_cell = gVars$toPlotMap, collapse_level = as.numeric(input$level))
    #extract collapsed matrix and collapsed hierarachy
    mat <- kegg_nano_1[[1]]
    hier <- kegg_nano_1[[2]]

    shiny::validate(need(expr = ncol(mat)>0, message = "No result for the enrichment or the filters are too restrictive. Please enlarge your selection"))

    # print("Matrix dimension -->")
    # print(dim(mat))
    # print("Hierarchy dimension -->")
    # print(dim(hier))
    #plot the collapsed matrix

    if(is.null(gVars$clust_mat)){
      gVars$exp_ann = gVars$pheno#cbind(c(rep(1:5,5),1),rownames(mat))
      if("All" %in% gVars$samplesID == FALSE){
        gVars$exp_ann = gVars$exp_ann[gVars$exp_ann[,2] %in% gVars$samplesID,]
      }
    }

    xxx = gVars$exp_ann
    #save(mat, hier,xxx,file="demo/demo.RData")

    ############################   DISCRETIZE MAT if user chose "discrete and there are negative and positve values"
    ############################
    mat_to_Plot=mat
    print("mat_to_Plot dim ------------------->")
    print(dim(mat_to_Plot))
    gVars$nSamples = nrow(mat_to_Plot)
    gVars$nPath = ncol(mat_to_Plot)
    
    MLP = max(unlist(lapply(X = colnames(mat_to_Plot),FUN = nchar)))
    gVars$length_path = MLP
    
    print("maximum character length ------------------->")
    print(MLP)
    
    
    if (input$continuous=="discrete"){
      mat_to_Plot[mat_to_Plot<0]=-1
      mat_to_Plot[mat_to_Plot>0]=1
      isDiscrete = T
    }else{
      isDiscrete = F
    }
    ########################################################
    #gVars$toPlot = plot_grid(path_mat = mat_to_Plot,path_hier = hier,experiment_ann =  gVars$exp_ann,discrete =  isDiscrete,level_col = as.numeric(input$level),square_colors=c(),color_leg=c(),path_text_size = 12,treat_text_size = 12)
    if(input$doGrouping){
      print("grouping selected")
      
      print(dim(mat_to_Plot))
      
      print(gVars$exp_ann)
      
      #print(mat_to_Plot[1:5,1:5])      
      gVars$toPlot = plot_grid(path_mat = mat_to_Plot,path_hier = hier,experiment_ann =  gVars$exp_ann,discrete =  isDiscrete,level_col = max(1,as.numeric(input$level)-1),square_colors=c(),color_leg=c(),path_text_size = 12,treat_text_size = 12, asRatio=(input$aspectRatio))
    }else{
      print("grouping NOT selected")
      level_n = max(1,as.numeric(input$level)-1)
      fake_hier = hier
      fake_hier[,level_n] = rep("",nrow(fake_hier))
     
      gVars$toPlot = plot_grid(path_mat = mat_to_Plot,path_hier = fake_hier,experiment_ann = gVars$exp_ann ,discrete =  isDiscrete,level_col =level_n,square_colors=c(),color_leg=c(),path_text_size = 12,treat_text_size = 12, asRatio=(input$aspectRatio))
      
    }
    
    #check for display size, pop up message if too large
    if(!is.null(gVars$nPath) && ((gVars$nPath* 20 ) + 10 * max(sapply(gVars$exp_ann,nchar))) > 30e3){
      print("exceeding dimensions")
      shinyjs::info("Warning: too many functional categories, the map might not be readable. Download the PDF for better resolution image.")
    }
    
    print("afterPLOTSPLOTSPLOTSPLOTSPLOTSPLOTSPLOTS")
  })
  
#   output$downloadData <- downloadHandler(
#     filename = paste(tempdir(),"/maps.pdf",sep=""),
#     content = function(file) {
#       dimMat=gVars$dimMat # This stuff here was added
#       rCount = gVars$nPath
#       cCount = gVars$nSamples
#       print(rCount)
#       print(cCount)
#       wt = 30 #changed from 7 to 30/15
#       ht = 15
#       if ((val1 <- round(cCount/3))>ht){
#         ht = val1
#       }
#       if ((val2 <- round(rCount/3))>wt){
#         wt = val2
#       }
#       #pdf("www/map.pdf",width = 13,height = 20)
#       cat("height: ", ht, "\n")
#       cat("width: ", wt, "\n")
# print(wt)
# print(ht)
#       pdf("www/map.pdf",width = wt,height = ht)
#       plot(gVars$toPlot)
#       dev.off()
# 
#       file.copy("www/map.pdf", file)
#     }
#   )

  
  output$downloadData <- downloadHandler(
    filename = paste(tempdir(),"/maps.pdf",sep=""),
  
    content = function(file) {
      wd = as.numeric(input$img_width)
      hi = as.numeric(input$img_height)
      
      pdf("www/map.pdf",width = wd,height = hi)
      plot(gVars$toPlot)
      dev.off()

      file.copy("www/map.pdf", file)
    }
  )
  
  
  observeEvent(input$resetCluster,{
    
    shinyjs::html(id="loadingText", "Rendering Map")
    shinyjs::show(id="loading-content")
    on.exit({
      print("inside on exit")
      shinyjs::hide(id="loading-content", anim=TRUE, animType="fade")    
    })
    gVars$exp_ann = gVars$pheno#cbind(c(rep(1:5,5),1),rownames(gVars$KEGG_MAT))
    gVars$clust_mat = NULL
    
    if("All" %in% gVars$samplesID){
      #  print("I WANT ALL SAMPLES")
      gVars$toPlotMap = gVars$KEGG_MAT
    }else{
      gVars$toPlotMap = gVars$KEGG_MAT[rownames(gVars$KEGG_MAT) %in% gVars$samplesID,]
    }
    
    
    #gVars$toPlotMap = gVars$toPlotMap
    #gVars$toPlot = plot_function(gcl = gVars$clust_mat,kegg_h = gVars$reduced_kegg_hierarchy,plt_mat = gVars$toPlotMap,input_n=as.numeric(input$level))
    kegg_nano_1 <- collapse_paths(kegg_hierarchy = gVars$reduced_kegg_hierarchy,kegg_mat_cell = gVars$toPlotMap, collapse_level = as.numeric(input$level))
    #extract collapsed matrix and collapsed hierarachy
    mat <- kegg_nano_1[[1]]
    hier <- kegg_nano_1[[2]]
    
    shiny::validate(need(expr = ncol(mat)>0, message = "No result for the enrichment or the filters are too restrictive. Please enlarge your selection"))
    
    print("Matrix dimension -->")
    print(dim(mat))
    print("Hierarchy dimension -->")
    print(dim(hier))
    #plot the collapsed matrix
    
    if(is.null(gVars$clust_mat)){
      gVars$exp_ann = gVars$pheno#cbind(c(rep(1:5,5),1),rownames(mat))
      if("All" %in% gVars$samplesID == FALSE){
        gVars$exp_ann = gVars$exp_ann[gVars$exp_ann[,2] %in% gVars$samplesID,]
      }
    }
    
    xxx = gVars$exp_ann
    #save(mat, hier,xxx,file="demo/demo.RData")
    
    ############################   DISCRETIZE MAT if user chose "discrete and there are negative and positve values"
    ############################
    mat_to_Plot=mat
    
    if (input$continuous=="discrete"){
      mat_to_Plot[mat_to_Plot<0]=-1
      mat_to_Plot[mat_to_Plot>0]=1
      isDiscrete = T
    }else{
      isDiscrete = F
    }
    ########################################################

    #gVars$toPlot = plot_grid(path_mat = mat_to_Plot,path_hier = hier,experiment_ann =  gVars$exp_ann,discrete =  isDiscrete,level_col = max(1,as.numeric(input$level)-1),square_colors=c(),color_leg=c(),path_text_size = 12,treat_text_size = 12)
    
    if(input$doGrouping){
      print("grouping selected")
      gVars$toPlot = plot_grid(path_mat = mat_to_Plot,path_hier = hier,experiment_ann =  gVars$exp_ann,discrete =  isDiscrete,level_col = max(1,as.numeric(input$level)-1),square_colors=c(),color_leg=c(),path_text_size = 12,treat_text_size = 12, asRatio=(input$aspectRatio))
    }else{
      print("grouping NOT selected")
      level_n = max(1,as.numeric(input$level)-1)
      fake_hier = hier
      fake_hier[,level_n] = rep("",nrow(fake_hier))
      
      gVars$toPlot = plot_grid(path_mat = mat_to_Plot,path_hier = fake_hier,experiment_ann = gVars$exp_ann ,discrete =  isDiscrete,level_col =level_n,square_colors=c(),color_leg=c(),path_text_size = 12,treat_text_size = 12, asRatio=(input$aspectRatio))
      
    }
    print("after PLOTS in reset cluster")  
})
  
  observeEvent(input$doCluster,{
    
    shinyjs::html(id="loadingText", "Rendering Map")
    shinyjs::show(id="loading-content")
    on.exit({
      print("inside on exit")
      shinyjs::hide(id="loading-content", anim=TRUE, animType="fade")    
    })
    
    print("Clustering columns")
    M=gVars$KEGG_MAT
    #save(M,file = "demo/M.RData")
    #Jaccard index distance
    
    D = matrix(data = 0,nrow = nrow(M),ncol = nrow(M))
    rownames(D) = colnames(D) = rownames(M)
    for(i in 1:(nrow(M)-1)){
      pi= colnames(M)[!is.na(M[i,])]
      for(j in (i+1):nrow(M)){
        pj= colnames(M)[!is.na(M[j,])]
        D[i,j] = D[j,i] = length(intersect(pi,pj))/length(union(pi,pj))    
      }
    }
    idx= which(rowSums(!is.na(M)) == 0)
    print(idx)
    
    if(length(idx)>0){
      D[idx,] = 0
      D[,idx] = 0
      D[idx,idx] = 1
    }
    diag(D) = 1
    
    D1 = matrix(data = 0,nrow = nrow(M),ncol = nrow(M))
    rownames(D1) = colnames(D1) = rownames(M)
    
    for(i in 1:(nrow(M)-1)){
      idx1 = which(!is.na(M[i,]))
      print(idx1)
      for(j in (i+1):nrow(M)){
        idx2 = which(!is.na(M[j,]))
        print(idx2)
        idx = intersect(idx1,idx2)
        print(idx)
        
        if(length(idx)>0){
          D1[i,j] = D1[j,i] = as.numeric(dist(t(cbind(M[i,idx],M[j,idx]))))
        }
        
      }
    }
    
    D = 1-D
    
    #View(D)
    
    print(class(D1))
    print(dim(D1))
    
    range01 <- function(x){(x-min(x))/(max(x)-min(x))}
    D1 = range01(D1)
    print(class(D1))
    print(dim(D1))
    
    #View(D1)
    
    if(input$Distance %in% "euclidean"){
      DD = D1
    }else{
      if(input$Distance %in% "jaccard"){
        DD = D
      }else{
        DD = (D + D1)/2
      }
    }
    
    print(class(DD))
    print(dim(DD))
    #View(DD)
    
    hls = hclust(as.dist(DD),method = input$ClusterMethod)
    #plot(hls)
    
    output$hclust_plot = renderPlot({
      plot(hls,xlab="", sub="",hang = -1)
      if(as.numeric(input$nc)>1){
        rect.hclust(tree = hls,k = as.numeric(input$nc))
      }
    })
    
    print(rownames(gVars$KEGG_MAT))
    print(hls$order)
    gVars$clust_mat = gVars$KEGG_MAT[hls$order,]

    
    cat("CHECK ROWNAMES -->")
    print(rownames(gVars$clust_mat))
    nClust = as.numeric(input$nc)
    
    cls = cutree(hls,k=nClust)
    cls = cls[hls$order]
    
    cat("CLUSTERING RESULTS -->")
    print(cls)
    
    gVars$exp_ann = cbind(cls,names(cls))#nrow(gVars$KEGG_MAT)
    
    if("All" %in% gVars$samplesID == FALSE){
      gVars$exp_ann = gVars$exp_ann[gVars$exp_ann[,2] %in% gVars$samplesID,]
    }
    
    print(gVars$exp_ann)
    gVars$toPlotMap = gVars$clust_mat
    #gVars$toPlot = plot_function(kegg_h = gVars$reduced_kegg_hierarchy,plt_mat = gVars$clust_mat,input_n=as.numeric(input$level))
    kegg_nano_1 <- collapse_paths(kegg_hierarchy = gVars$reduced_kegg_hierarchy,kegg_mat_cell = gVars$toPlotMap, collapse_level = as.numeric(input$level))
    #extract collapsed matrix and collapsed hierarachy
    mat <- kegg_nano_1[[1]]
    hier <- kegg_nano_1[[2]]
    
    shiny::validate(need(expr = ncol(mat)>0, message = "No result for the enrichment or the filters are too restrictive. Please enlarge your selection"))
    
    print("Matrix dimension -->")
    print(dim(mat))
    print("Hierarchy dimension -->")
    print(dim(hier))
    #plot the collapsed matrix
    
    if(is.null(gVars$clust_mat)){
      gVars$exp_ann = gVars$pheno#cbind(c(rep(1:5,5),1),rownames(mat))
      if("All" %in% gVars$samplesID == FALSE){
        gVars$exp_ann = gVars$exp_ann[gVars$exp_ann[,2] %in% gVars$samplesID,]
      }
    }
    
    xxx = gVars$exp_ann
    #save(mat, hier,xxx,file="demo/demo.RData")
    
    ############################   DISCRETIZE MAT if user chose "discrete and there are negative and positve values"
    ############################
    mat_to_Plot=mat
    
    if (input$continuous=="discrete"){
      mat_to_Plot[mat_to_Plot<0]=-1
      mat_to_Plot[mat_to_Plot>0]=1
      isDiscrete = T
    }else{
      isDiscrete = F
    }
    ########################################################

    #gVars$toPlot = plot_grid(path_mat = mat_to_Plot,path_hier = hier,experiment_ann =  gVars$exp_ann,discrete =  isDiscrete,level_col = max(1,as.numeric(input$level)-1),square_colors=c(),color_leg=c(),path_text_size = 12,treat_text_size = 12)
    
    if(input$doGrouping){
      print("grouping selected")
      gVars$toPlot = plot_grid(path_mat = mat_to_Plot,path_hier = hier,experiment_ann =  gVars$exp_ann,discrete =  isDiscrete,level_col = max(1,as.numeric(input$level)-1),square_colors=c(),color_leg=c(),path_text_size = 12,treat_text_size = 12, asRatio=(input$aspectRatio))
    }else{
      print("grouping NOT selected")
      level_n = max(1,as.numeric(input$level)-1)
      fake_hier = hier
      fake_hier[,level_n] = rep("",nrow(fake_hier))
      
      gVars$toPlot = plot_grid(path_mat = mat_to_Plot,path_hier = fake_hier,experiment_ann = gVars$exp_ann ,discrete =  isDiscrete,level_col =level_n,square_colors=c(),color_leg=c(),path_text_size = 12,treat_text_size = 12, asRatio=(input$aspectRatio))
      
    }
    
    print("after PLOTS in clustering")
  })
  # ##Hide the loading message when the rest of the server function has executed
  # Sys.sleep(1)
  # shinyjs::hide(id="loading-content", anim=TRUE, animType="fade")    
  
  observe({
    M = DATA()
    if(is.null(M)){
      shinyjs::disable("computePathways")
    }else{
      shinyjs::enable("computePathways")
     
      
    }
    
    if(is.null(gVars$KEGG_MAT)){
      shinyjs::disable("do")
      shinyjs::disable("downloadData")
      shinyjs::disable("doCluster")
      shinyjs::disable("resetCluster")
    }else{
      shinyjs::enable("do")
      shinyjs::enable("downloadData")
      shinyjs::enable("doCluster")
      shinyjs::enable("resetCluster")
    }
  })
  
})
