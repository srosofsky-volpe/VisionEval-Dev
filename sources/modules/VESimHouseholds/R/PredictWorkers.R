#' @include CreateEstimationDatasets.R
NULL

#================
#PredictWorkers.R
#================

#<doc>
## PredictWorkers Module
#### September 6, 2018
#
#This module assigns workers by age to households and to noninstitutional group quarters population. It is a simple model which predicts workers as a function of the age composition of household members. There is no responsiveness to jobs or how changes in the job market and demographics might change the worker age composition, but the user may use optional inputs to exogenously adjust relative employment rates by age group, Azone, and year. These optional input values specify by age group, Azone, and year the proportions of persons in the age group and Azone who are workers relative to the proportions in the model estimation year.
#
### Model Parameter Estimation
#This model has just one parameter object, a matrix of the probability that a person in each age group in a specified household type is a worker. The defined household types are the same as the types defined for the CreateHouseholds module.
#
#This probability matrix is created from Census public use microsample (PUMS) data that is compiled by the CreateEstimationDatasets.R script into a R dataset (HhData_df) when the VESimHouseholds package is built. The data that is supplied with the VESimHouseholds package downloaded from the official VisionEval repository may be used, but it is preferrable to use data for the region being modeled. How this is done is explained in the documentation for the *CreateEstimationDatasets.R* script.
#
#To calculate this probability matrix, the numbers of workers by age group and household type and the numbers of persons by age group and household type are tabulated (weighted by the household weights in the PUMS data). The probability that a person is a worker is calculated by dividing the worker tabulation by the population tabulation.
#
### How the Module Works
#The number of workers in each age group of each household is determined through random sampling using the probability for the age group and household type. For example, if a household is of the type *2-0-2-0-0-0*, and the probability that a person of age 20-29 in this household type is a worker is 0.7, then two random samples are taken for this household with a probability of success of 0.7 to determine the number of workers in this age group in the household.
#
#If the user has supplied optional inputs for the ratio of employment for the age group in the forecast year relative to the year of the model estimation dataset, that input is multiplied by the estimated worker probability to determine the sampling probability. For example, if the year of the model estimation data is 2000 and the forecast year is 2010, and if the user specifies that the employment rate of 20-29 year olds in 2010 was 95% of the employment rate of that age group in 2000, then the worker probability in the example above (0.7) is multiplied by 0.95 to calculate the sampling probability.
#</doc>


#=============================================
#SECTION 1: ESTIMATE AND SAVE MODEL PARAMETERS
#=============================================
#The worker model predicts workers as a function of the household type:
#i.e. the number of persons in each of 6 age groups in the household. It is a
#simple stochastic model where the probability that a person in an age group in
#a household type is a worker is the ratio of workers to persons in that age
#group and household type. For the noninstitutionalized group quarters
#population, the probability is the ratio of workers to persons by age group.

#Define a function to estimate worker model parameters
#-----------------------------------------------------

calcWorkerProportions <- function(HhData_df) {
  GQ_df <- HhData_df[HhData_df$HhType == "Grp",]
  Hh_df <- HhData_df[HhData_df$HhType == "Reg",]
  load("data/HtProb_HtAp.rda")
  Ag <-
    c("Age0to14",
      "Age15to19",
      "Age20to29",
      "Age30to54",
      "Age55to64",
      "Age65Plus")
  Wk <- gsub("Age", "Wkr", Ag[-1])
  # #Calculate the worker proportions by age group
  # NumWkr_Wk <- colSums(Hh_df[,Wk]) + colSums(GQ_df[,Wk])
  # PropWkr_Wk <- NumWkr_Wk / sum(NumWkr_Wk)
  #Create vector of household type names
  HhType_ <-
    apply(Hh_df[, Ag], 1, function(x)
      paste(x, collapse = "-"))
  #Limit Hh_df to selected household types
  Hh_df <- Hh_df[HhType_ %in% rownames(HtProb_HtAp),]
  SelHhType_ <- HhType_[HhType_ %in% rownames(HtProb_HtAp)]
  #Apply household weights to persons by age
  WtHhPop_df <- sweep(Hh_df[, c(Ag, Wk)], 1, Hh_df$HhWeight, "*")
  #Tabulate persons by age group and worker group by household type
  HhAgWkTab_ls <- lapply(WtHhPop_df, function(x) {
    tapply(x, SelHhType_, function(x)
      sum(as.numeric(x)))
  })
  HhAgWkTab_df <- data.frame(do.call(cbind, HhAgWkTab_ls))
  #Calculate the proportion of persons by age who are workers by household type
  PropHhWkr_HtAg <-
    as.matrix(HhAgWkTab_df[,Wk]) / as.matrix(HhAgWkTab_df[,Ag[-1]])
  PropHhWkr_HtAg[is.nan(PropHhWkr_HtAg)] <- 0
  colnames(PropHhWkr_HtAg) <- Ag[-1]
  #Calculate the proportion of group quarters persons by age who are workers
  PropGQWkr_Ag <- colSums(GQ_df[,Wk]) / colSums(GQ_df[,Ag[-1]])
  #Add the group quarters proportions to the household matrix
  PropHhWkr_HtAg <- rbind(PropHhWkr_HtAg, Grp = PropGQWkr_Ag)
  #Return matrix of proportions
  PropHhWkr_HtAg
}

#Create and save household and group quarters worker proportions
#---------------------------------------------------------------
load("data/Hh_df.rda")
PropHhWkr_HtAg <- calcWorkerProportions(Hh_df)
#' Worker proportions
#'
#' A dataset that contains proportion of workers by age group by household
#' type for the regular household population and proportion of workers by age
#' group for noninstitutional group quarters population.
#'
#' @format A a matrix of the proportion of persons in age group who are workers
#' for each household type.:
#' @source PredictWorkers.R script.
"PropHhWkr_HtAg"
visioneval::savePackageDataset(PropHhWkr_HtAg, overwrite = TRUE)


#================================================
#SECTION 2: DEFINE THE MODULE DATA SPECIFICATIONS
#================================================

#Define the data specifications
#------------------------------
PredictWorkersSpecifications <- list(
  #Level of geography module is applied at
  RunBy = "Region",
  #Specify input data
  Inp = items(
    item(
      NAME =
        items("RelEmp15to19",
              "RelEmp20to29",
              "RelEmp30to54",
              "RelEmp55to64",
              "RelEmp65Plus"),
      FILE = "azone_relative_employment.csv",
      TABLE = "Azone",
      GROUP = "Year",
      TYPE = "double",
      UNITS = "proportion",
      NAVALUE = -1,
      SIZE = 0,
      PROHIBIT = c("< 0"),
      ISELEMENTOF = "",
      UNLIKELY = "",
      TOTAL = "",
      DESCRIPTION =
        items("Ratio of workers to persons age 15 to 19 in model year vs. in estimation data year",
              "Ratio of workers to persons age 20 to 29 in model year vs. in estimation data year",
              "Ratio of workers to persons age 30 to 54 in model year vs. in estimation data year",
              "Ratio of workers to persons age 55 to 64 in model year vs. in estimation data year",
              "Ratio of workers to persons age 65 or older in model year vs. in estimation data year"),
      OPTIONAL = TRUE # It turns out it's not really optional.
    )
  ),
  #Specify data to be loaded from data store
  Get = items(
    item(
      NAME =
        items("Age0to14",
              "Age15to19",
              "Age20to29",
              "Age30to54",
              "Age55to64",
              "Age65Plus"),
      TABLE = "Household",
      GROUP = "Year",
      TYPE = "people",
      UNITS = "PRSN",
      PROHIBIT = c("NA", "< 0"),
      ISELEMENTOF = ""
    ),
    item(
      NAME =
        items("RelEmp15to19",
              "RelEmp20to29",
              "RelEmp30to54",
              "RelEmp55to64",
              "RelEmp65Plus"),
      TABLE = "Azone",
      GROUP = "Year",
      TYPE = "double",
      UNITS = "proportion",
      PROHIBIT = c("< 0"),
      ISELEMENTOF = "",
      OPTIONAL = TRUE
    ),
    item(
      NAME = "HhType",
      TABLE = "Household",
      GROUP = "Year",
      TYPE = "character",
      UNITS = "category",
      NAVALUE = "NA",
      PROHIBIT = "",
      ISELEMENTOF = ""
    ),
    item(
      NAME = "Azone",
      TABLE = "Household",
      GROUP = "Year",
      TYPE = "character",
      UNITS = "ID",
      NAVALUE = "NA",
      PROHIBIT = "",
      ISELEMENTOF = ""
    ),
    item(
      NAME = "Azone",
      TABLE = "Azone",
      GROUP = "Year",
      TYPE = "character",
      UNITS = "ID",
      PROHIBIT = "",
      ISELEMENTOF = ""
    )
  ),
  #Specify data to saved in the data store
  Set = items(
    item(
      NAME =
        items("Wkr15to19",
              "Wkr20to29",
              "Wkr30to54",
              "Wkr55to64",
              "Wkr65Plus"),
      TABLE = "Household",
      GROUP = "Year",
      TYPE = "people",
      UNITS = "PRSN",
      NAVALUE = -1,
      PROHIBIT = c("NA", "< 0"),
      ISELEMENTOF = "",
      SIZE = 0,
      DESCRIPTION =
        items("Workers in 15 to 19 year old age group",
              "Workers in 20 to 29 year old age group",
              "Workers in 30 to 54 year old age group",
              "Workers in 55 to 64 year old age group",
              "Workers in 65 or older age group")
    ),
    item(
      NAME = "Workers",
      TABLE = "Household",
      GROUP = "Year",
      TYPE = "people",
      UNITS = "PRSN",
      NAVALUE = -1,
      PROHIBIT = c("NA", "< 0"),
      ISELEMENTOF = "",
      SIZE = 0,
      DESCRIPTION = "Total workers"
    ),
    item(
      NAME = "NumWkr",
      TABLE = "Azone",
      GROUP = "Year",
      TYPE = "people",
      UNITS = "PRSN",
      NAVALUE = -1,
      PROHIBIT = c("NA", "< 0"),
      ISELEMENTOF = "",
      SIZE = 0,
      DESCRIPTION = "Number of workers residing in the zone"
    )
  )
)

#Save the data specifications list
#---------------------------------
#' Specifications list for PredictWorkers module
#'
#' A list containing specifications for the PredictWorkers module.
#'
#' @format A list containing 4 components:
#' \describe{
#'  \item{RunBy}{the level of geography that the module is run at}
#'  \item{Inp}{module inputs to be saved to the datastore}
#'  \item{Get}{module inputs to be read from the datastore}
#'  \item{Set}{module outputs to be written to the datastore}
#' }
#' @source PredictWorkers.R script.
"PredictWorkersSpecifications"
visioneval::savePackageDataset(PredictWorkersSpecifications, overwrite = TRUE)


#=======================================================
#SECTION 3: DEFINE FUNCTIONS THAT IMPLEMENT THE SUBMODEL
#=======================================================
#This function predicts the number of workers in each of 6 age groups in each
#household and tallies the total number of workers in the household. It uses
#the matrix of worker proportions by household type and age group as choice
#probabilities for determining the number of workers by age group for each
#household. The relative employment value for each age group, which is the
#employment rate for the age group relative to the employment rate for the
#model estimation year data is used to adjust the relative employment to reflect
#changes in relative employment for other years. For example, the great
#recession of 2007 to 2012 hit the millenial generation particularly hard.

#Main module function that predicts workers by age for each household
#--------------------------------------------------------------------
#' Main module function to predict workers by age for each household
#'
#' \code{PredictWorkers} predicts the number of workers by age group for each
#' household and tallies the total number of workers for each household.
#'
#' This function predicts the number of workers for each household. Household
#' workers are assigned to 5 age groups: 15-19, 20-29, 30-54, 55-64, and 65Plus.
#'
#' @param L A list containing the components listed in the Get specifications
#' for the module.
#' @return A list containing the components specified in the Set
#' specifications for the module.
#' @name PredictWorkers
#' @import visioneval
#' @include CreateEstimationDatasets.R CreateHouseholds.R
#' @export
PredictWorkers <- function(L) {
  #Define dimension name vectors
  Ag <-
    c("Age15to19", "Age20to29", "Age30to54", "Age55to64", "Age65Plus")
  Wk <- gsub("Age", "Wkr", Ag)
  Re <- gsub("Age", "RelEmp", Ag)
  Az <- as.vector(L$Year$Azone$Azone)
  #Fix seed as synthesis involves sampling
  set.seed(L$G$Seed)
  #Calculate total number of households
  NumHh <- length(L$Year$Household$HhType)
  #Initialize output list
  Out_ls <- initDataList()
  Out_ls$Year$Household <-
    list(
      Workers = integer(NumHh),
      Wkr15to19 = integer(NumHh),
      Wkr20to29 = integer(NumHh),
      Wkr30to54 = integer(NumHh),
      Wkr55to64 = integer(NumHh),
      Wkr65Plus = integer(NumHh)
    )
  Out_ls$Year$Azone <-
    list(
      NumWkr = integer(length(L$Year$Azone))
    )
  #Initialize Errors vector
  Errors_ <- character(0)
  #Define function to predict total number of workers for by household given
  #N_ is a vector of the number of persons in the age group by household
  #P_ is the the worker probability for the age group
  #W is the total number of workers
  getNumWkr <- function(N_, P_, W) {
    NumHh <- length(N_)
    NumWkr_Hh <- setNames(integer(NumHh), 1:NumHh) #Initialize count of workers
    HhIdx_Pr <- rep(1:length(N_), N_) #Vector of persons with household index
    PrsnProb_Pr <- rep(P_, N_) #Probability that each person is a worker
    WkrIdx_ <- sample(HhIdx_Pr, W, prob = PrsnProb_Pr ) #Sample household index
    WkrTab_ <- table(WkrIdx_) #Tabulate household index
    NumWkr_Hh[names(WkrTab_)] <- WkrTab_
    NumWkr_Hh
  }
  #Iterate through age groups and Azones and identify number of workers by
  #age group for each household
  PropHhWkr_HtAg <- loadPackageDataset("PropHhWkr_HtAg","VESimHouseholds")
  for (i in 1:length(Ag)) {
    NumWkr_Hh <- integer(NumHh)
    for (az in Az) {
      IsAz <- L$Year$Household$Azone == az
      NumWkr_Hh[IsAz] <- local({
        NumPrsn_ <- L$Year$Household[[Ag[i]]][IsAz]
        HhType_ <- L$Year$Household$HhType[IsAz]
        Probs_ <- PropHhWkr_HtAg[HhType_, Ag[i]]
        TotPrsn <- sum(NumPrsn_)
        RelEmp <- L$Year$Azone[[Re[i]]][L$Year$Azone$Azone == az]
        if (is.null(RelEmp)) RelEmp <- 1
        TotWkr <- round(sum(NumPrsn_ * Probs_) * RelEmp)
        if (TotWkr > TotPrsn) {
          #catch error
          MaxVal <- TotPrsn / sum(NumPrsn_ * Probs_)
          Msg <- paste0(
            "Error during run of PredictWorkers module! ",
            "The value of ", Re[i], " for Azone ", az,
            " will result in more workers than people in that age category. ",
            "The maximum value of ", Re[i], " must be less than ",
            round(MaxVal, 2), ".")
          Errors_ <<- c(Errors_, Msg)
          NA
        } else {
          NumWkr_ <- integer(length(NumPrsn_))
          DoPredict_ <- NumPrsn_ > 0 & Probs_ > 0
          NumWkr_[DoPredict_] <-
            getNumWkr(NumPrsn_[DoPredict_], Probs_[DoPredict_], TotWkr)
          NumWkr_
        }
      })
      rm(IsAz)
    }
    Out_ls$Year$Household[[Wk[i]]] <- NumWkr_Hh
    rm(az)
  }
  rm(i)
  #Add error messages if any
  if (length(Errors_) != 0) {
    addErrorMsg("Out_ls", Errors_)
  }
  #Calculate the total number of workers
  Out_ls$Year$Household$Workers <-
    mapply(sum,
           Out_ls$Year$Household$Wkr15to19,
           Out_ls$Year$Household$Wkr20to29,
           Out_ls$Year$Household$Wkr30to54,
           Out_ls$Year$Household$Wkr55to64,
           Out_ls$Year$Household$Wkr65Plus)
  #Calculate the total number of workers by Azone
  Out_ls$Year$Azone$NumWkr <-
    tapply(Out_ls$Year$Household$Workers, L$Year$Household$Azone, sum)[Az]
  #Return the results
  Out_ls
}


#===============================================================
#SECTION 4: MODULE DOCUMENTATION AND AUXILLIARY DEVELOPMENT CODE
#===============================================================
#Run module automatic documentation
#----------------------------------
documentModule("PredictWorkers")

#Test code to check specifications, loading inputs, and whether datastore
#contains data needed to run module. Return input list (L) to use for developing
#module functions
#-------------------------------------------------------------------------------
# #Load packages and test functions
# library(visioneval)
# library(filesstrings)
# source("tests/scripts/test_functions.R")
# #Set up test environment
# TestSetup_ls <- list(
#   TestDataRepo = "../Test_Data/VE-RSPM",
#   DatastoreName = "Datastore.tar",
#   LoadDatastore = TRUE,
#   TestDocsDir = "verspm",
#   ClearLogs = TRUE,
#   # SaveDatastore = TRUE
#   SaveDatastore = FALSE
# )
# setUpTests(TestSetup_ls)
# #Run test module
# TestDat_ <- testModule(
#   ModuleName = "PredictWorkers",
#   LoadDatastore = TRUE,
#   SaveDatastore = FALSE,
#   DoRun = FALSE
# )
# L <- TestDat_$L
# R <- PredictWorkers(L)
