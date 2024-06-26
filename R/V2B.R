#' Volume-to-biomass conversion
#'
#' @description Implementation of the model-based, volume-to-biomass conversion equations by Boudewyn et al. (2007).
#' Note - only scenarios 1 and 2 are currently implemented.
#' @param volume Gross merchantable volume/ha of all live trees
#' Note - Originally, parameters for BC were for net merchantable volume (not gross). That has been updated in 2015 when new improved coefficients were made available. Therefore, BC input data should also use **gross** merchantable volume from now on.
#' @param species Species code in the NFI standard (e.g. POPU.TRE) 
#' @param jurisdiction A two-letter code depicting jurisdiction (e.g. "AB")
#' @param ecozone ecozone number (1-15). Call 'CodesEcozones' for a list of ecozones names and codes - also available in table 2 of appendix 7 of Boudewyn et al (2007).
#' 
#' @return A list containing aboveground biomass values. Column names correspond to variable names
#' used in Boudewyn et al. 2007: 
#' \describe{
#' \item{\code{b_m}}{Total stem wood biomass of merchantable-sized live trees (biomass includes stumps and tops), in metric tonnes per ha.}
#' \item{\code{b_n}}{stem wood biomass of live, nonmerchantable-sized trees (tonnes/ha)}
#' \item{\code{b_mn}}{b_m + b_n}
#' \item{\code{b_s}}{stem wood biomass of live, sapling-sized trees (tonnes/ha)}
#' \item{\code{b_total}}{Total tree biomass}
#' \item{\code{b_bark}}{Total bark biomass}
#' \item{\code{b_branches}}{Total branch biomass}
#' \item{\code{b_foliage}}{Total foliage biomass}
#' }
#' 
#' @references 
#' Boudewyn, P.A.; Song, X.; Magnussen, S.; Gillis, M.D. (2007). Model-based, volume-to-biomass conversion for forested and vegetated land in Canada. Natural Resources Canada, Canadian Forest Service, Pacific Forestry Centre, Victoria, BC. Information Report BC-X-411. 112 p.
#' 
#' @examples
#' V2B(350, species = "PINU.CON",jurisdiction = "BC", ecozone=4)
#' 
#' @export

V2B <- function(volume, 
                species, 
                jurisdiction, 
                ecozone) {
  
  #checks
  
  if(!is.numeric(volume))         stop("'volume' must be type numeric")
  if(!is.character(species))      stop("'species' must be type character")
  if(!is.character(jurisdiction)) stop("'jurisdiction' must be type character")
  if(!is.numeric(ecozone))        stop("'ecozone' must be type numeric")
  
  
  
  
  
  
  #convert 'species' to: genus, species, variety
  species <- stringr::str_split(species, "\\.")[[1]]
  
  if(length(species) >= 2) {
    genus <- species[1]
    spp <- species[2] 
    variety  <- species[3]
  } else {
    stop("Wrong species format")
  }
  
  
  #get parameters
  B <- CTAE:::V2Bgetparams(
                          genus = genus,
                          species = spp,
                          variety = variety,
                          jurisdiction = jurisdiction,
                          ecozone = ecozone
                          )
  
  B3 <- B$B3
  B4 <- B$B4
  B5 <- B$B5
  B6 <- B$B6vol
  
  
  
  #Calculations:
  
  #Merchantable-sized tree stem wood biomass (Eq1, based on a and b parameters from Table 3)
  b_m <- B3$a * volume ^ B3$b #total stem wood biomass of merchantable-sized live trees (biomass includes stumps and tops)
  
  
  #Nonmerchantable-sized tree stem wood biomass
  # nonmerchfactor (Eq2, based on a, b, and k parameters from Table 4)
  nonmerchfactor = B4$k + B4$a * b_m ^ B4$b
  
  #check if nonmerchfactor is below the upper cap value
  nonmerchfactor <- ifelse(nonmerchfactor > B4$cap, B4$cap, nonmerchfactor)
  
  
  b_nm <- nonmerchfactor  * b_m
  b_n <- b_nm - b_m #stem wood biomass of live, nonmerchantable-sized trees (tonnes/ha)
  
  
  #Sapling-sized tree stem wood biomass
  # Not all species have sapling factor. Check whether the species in question has.
  # If not assign zero to it.
  if(!is.null(B5)){
  # saplingfactor (Eq3, based on a, b, and k parameters from Table 5))
  saplingfactor = B5$k + B5$a * b_nm ^ B5$b
  
  #check if samplingfactor is below the upper cap value
  saplingfactor <- ifelse(saplingfactor > B5$cap, B5$cap, saplingfactor)
  
  b_snm = saplingfactor * b_nm
  b_s = b_snm - b_nm #stem wood biomass of live, sapling-sized trees
  } else {
    b_s <- 0
  }
  
  #Proportions of total tree biomass in stemwood, stem bark, branch and foliage for live trees of all sizes
  # Equations 4-7
  lvol <- log(volume+5)
  
  p_a <- exp(B6$a1 + B6$a2 * volume + B6$a3 * lvol)
  p_b <- exp(B6$b1 + B6$b2 * volume + B6$b3 * lvol)
  p_c <- exp(B6$c1 + B6$c2 * volume + B6$c3 * lvol)
  p_abc <- 1 + p_a + p_b + p_c
  
  Pstemwood =  1 / p_abc
  Pbark =      p_a / p_abc
  Pbranches =  p_b / p_abc
  Pfoliage =   p_c / p_abc
  
  #total tree biomass
  b_total <- (b_m + b_n + b_s) / Pstemwood
  
  #total bark biomass
  b_bark <- b_total * Pbark
  
  #total branch biomass 
  b_branches <- b_total * Pbranches
  
  #total foliage biomass
  b_foliage <- b_total * Pfoliage
  
  # r <- tibble(b_m, b_n, b_nm, b_s, 
  #             # Pstemwood, Pbark, Pbranches, Pfoliage, 
  #             b_total, b_bark, b_branches, b_foliage)
  
  r <- list(b_m = b_m, 
            b_n = b_n, 
            b_nm = b_nm, 
            b_s = b_s, 
            b_total = b_total, 
            b_bark = b_bark, 
            b_branches = b_branches, 
            b_foliage = b_foliage
    
  )
  return(r)
}




#internal not exported
V2Bgetparams <- function(genus, 
                         species, 
                         variety=NA, 
                         jurisdiction, 
                         ecozone
                         
) {
  
  
  V2B_params_t3 <- parameters_V2B[[1]]
  V2B_params_t4 <- parameters_V2B[[2]]
  V2B_params_t5 <- parameters_V2B[[3]]
  V2B_params_t6_vol <- parameters_V2B[[4]]
  V2B_params_t6_bio <- parameters_V2B[[5]]
  V2B_params_t7_vol <- parameters_V2B[[6]]
  V2B_params_t7_bio <- parameters_V2B[[7]]
  
  
  
  #checks
  
  
  
  
  
  #get the parameters 
  B3 <- 
    V2B_params_t3 |> 
    dplyr::filter(juris_id == !!jurisdiction, 
           genus == !!genus,
           species == !!species,
           ecozone == !!ecozone )
  
  if(!is.na(variety)) {
    B3 <- B3 |> dplyr::filter(variety == !!variety)
  } else {
    B3 <- B3 |> dplyr::filter(is.na(variety))
  }
  
  #must be one row 
  if(nrow(B3) != 1) stop("Error in parameter selection.")
  
  
  B4 <- V2B_params_t4 |>  
    
    dplyr::filter(juris_id == !!jurisdiction, 
           ecozone == !!ecozone,
           genus == !!genus,
           species == !!species
    )
  if(!is.na(variety)) {
    B4 <- B4 |> dplyr::filter(variety == !!variety)
  } else {
    B4 <- B4 |> dplyr::filter(is.na(variety))
  }
  
  if(nrow(B4) != 1) stop("Error in parameter selection.")
  
  
  B5 <- V2B_params_t5 |>    #saplingfactor params. Not available for all models.
    dplyr::filter(juris_id == !!jurisdiction, 
           genus == !!genus,
           ecozone == !!ecozone )
  if(nrow(B5) != 1) {
    message("No parameter available for sapling tree model. Set to zero.")
    B5 <- NULL
  }
  
  B6vol <- V2B_params_t6_vol |>  
    dplyr::filter(juris_id == !!jurisdiction, 
           ecozone == !!ecozone,
           genus == !!genus,
           species == !!species
    )
  
  if(!is.na(variety)) {
    B6vol <- B6vol |> dplyr::filter(variety == !!variety)
  } else {
    B6vol <- B6vol |> dplyr::filter(is.na(variety))
  }
  
  B6bio <- V2B_params_t6_bio |>  
    dplyr::filter(juris_id == !!jurisdiction, 
                  ecozone == !!ecozone,
                  genus == !!genus,
                  species == !!species
    )
  
  if(!is.na(variety)) {
    B6bio <- B6bio |> dplyr::filter(variety == !!variety)
  } else {
    B6bio <- B6bio |> dplyr::filter(is.na(variety))
  }
  
  B7vol <- V2B_params_t7_vol |> dplyr::filter(
                                genus == !!genus,
                                species == !!species,
                                juris_id == jurisdiction,
                                ecozone == !!ecozone
                                )
  if (!is.na(variety)) {
    B7vol <- dplyr::filter(B7vol, variety == !!variety)
  } else {
    B7vol <- dplyr::filter(B7vol, is.na(variety))
  }
  
  B7bio <- V2B_params_t7_bio |> dplyr::filter(
    genus == !!genus,
    species == !!species,
    juris_id == jurisdiction,
    ecozone == !!ecozone
  )
  if (!is.na(variety)) {
    B7bio <- dplyr::filter(B7bio, variety == !!variety)
  } else {
    B7bio <- dplyr::filter(B7bio, is.na(variety))
  }
  
  if(nrow(B6vol) != 1) stop("Error in parameter selection.")
  if(nrow(B6bio) != 1) stop("Error in parameter selection.")
  
  B <- list(
    B3 = B3,
    B4 = B4,
    B5 = B5,
    B6vol = B6vol,
    B6bio = B6bio,
    B7vol = B7vol,
    B7bio = B7bio
  )
  
  return(B)
  
}
