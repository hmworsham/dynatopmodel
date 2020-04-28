# ********************************************************************
# main routine for the Dynamic TOPMODEL for the areal groupings identified by a catchment analysis
# see Beven and Freer (2001), Metcalfe et al. (2015) for a description of the model
# *********************************************
# Notes on units:
# lengths are in m and times in hrs, coverted if necessary
# rainfall and pe in m/hr (will be converted from mm/hr as usual convention)
# storage in rain equivalent units e.g. m
# base flows expressed as specific fluxes per plan area: m^3/hr per m^2
# input flows expressed as total flux (m^3/hr)
# ****************************************************************************************************************
# Summary of model parameters
# ----------------------------------------------------------------------------------------------------------------
# Parameter                                         Units         Typical values (see Beven and Freer, 2001 (1), Beven 1997, Page et al 2006 (2))                                                                  Lower             Upper
# ----------------------------------------------------------------------------------------------------------------
# m     :   form of exponential decline in          m             0.005             0.025
#           conductivity
# sdmax:    max root zone storage                   m             0.005 (2)         0.2 (2)
# srz0:   initial root zone storage               -             0                 0.3
# ln_to  :   lateral saturated transmissivity        m^2/hr-1      -7 (2)            8
# sd_max  :   max effective deficit of saturated zone m             0.1               0.8
# td    :   unsaturated zone time delay             hr/m          0.1 (1, 2)        40 (2)
# ****************************************************************************************************************
#' Run Dynamic TOPMODEL against hydrometric data and a catchment discretisation
#' @details The grouping (HRU) table may be generated by the discretise method and includes each indexed channel as separate group. See Metcalfe et al. (2015) for descriptions of the parameters maintained in this table.
#' @details Evapotranspiration input can be generated using the approx.pe.ts method
#' @export run.dtm
#' @import deSolve
#' @import xts
#' @author Peter Metcalfe
#' @param groups Data frame of areal group definitions along with their hydrological parameters (see Metcalfe et al., 2015)
#' @param weights If the discretisation has n groups, this holds the n x n flux distribution (weighting) matrix defining downslope
#' @param rain A time series of rainfall data in m/hr. One column per gauge if multiple gauges used.
#' @param routing data.frame  Channel routing table comprises a two-column data.frame or matrix. Its first column should be average flow distance to the outlet in m, the second the proportions of the catchment channel network within each distance category. Can be generated by make.routing.table
#' @param qobs Optional time series of observation data
#' @param qt0 Initial specific discharge (m/hr)
#' @param pe Time series of potential evapotranspiration, at the same time step as rainfall data
#' @param dt Time step (hours). Defaults to the interval used by the rainfall data
#' @param ichan Integer index of the "channel" group. Defaults to 1
#' @param i.out For multi-channel systems, the index of the outlet reach
#' @param sim.start Optional start time for simulation in any format that can be coerced into a POSIXct instance. Defaults to start of rainfall data
#' @param sim.end Optional end time of simulation in any format that can be coerced into a POSIXct instance. Defaults to end of rainfall data
#' @param disp.par List of graphical routing parameters. A set of defaults are retrieved by calling disp.par()
#' @param ntt Number of inner time steps used in subsurface routing algorithm
#' @param dqds Function to supply a custom flux-storage relationship as the kinematic wave celerity. If not supplied then exponential relationship used.
#' @param upstream_inputs xts A list of any upstream hydrographs in addition to hillslope runoff feeding into the river network
#' @param Wsurf matrix  Surface routing matrix. Defines routing of overland flow downslope between units. By default identical to subsurface routing matrix by default, but can be altered to reflect modified connectivity of certain areas with the hillslope
#' @param Wover matrix  Optional surface overflow routing matrix. Defines routing of overland flow from a unit that has run out of surface excess storage capacity. Identical to surface routing matrix by default. Can be altered to reflect an overflow channel for a runoff storage area, for example.
#' @param ... Any further arguments will be treated as graphical parameters as documented in get.disp.par
#' @return qsim: time series of specific discharges (m/hr) at the specified time interval. can be converted to absolute discharges by multiplying by catch.area
#' @return catch.area: the catchment area in m^2, calculated from the areas in the groups table
#' @return data.in: a list comprising the parameters supplied to the call
#' @return datetime sim.start Start of simulation
#' @return sim.end  datetime   End time of simulation
#' @return fluxes: a list comprising, for each response unit the specific base flows qbf, specific upslope inputs qin, drainage fluxes quz, and any overland flow qof, all in m/hr
#' @return storages: a list comprising, for each response unit, root zone and unsaturated storage, total storage deficit and surface storages (all m)
#' @note If rain, pe or observation data differ in time period, use aggregate_xts to coerce the relevant series to the desired  time interval
#' @seealso aggregate_xts
#' @seealso discretise
#' @references Metcalfe, P., Beven, K., & Freer, J. (2015). Dynamic TOPMODEL: a new implementation in R and its sensitivity to time and space steps. Environmental Modelling & Software, 72, 155-172.

#' @examples
#'\dontrun{
#' require(dynatopmodel)
#' data(brompton)
#'
#' # Examine the November 2012 event that flooded the village (see Metcalfe et al., 2017)
#' sel <- "2012-11-23 12:00::2012-12-01"
#' # Precalculated discretisation
#' disc <- brompton$disc
#' groups <- disc$groups
#' rain <- brompton$rain[sel]
#' # to 15 minute intervals
#' rain <- disaggregate_xts(rain, dt = 15/60)
#' # Reduce PE, seems a bit on high side and resulted in a weighting factor for the rainfall
#' pe <- brompton$pe[sel]/2
#' qobs <- brompton$qobs[sel]
#'
#' # Here we apply the same parameter values to all groups.
#' # we could also consider a discontinuity at the depth of subsurface drains (~1m)
#' # or in areas more remote from the channel that do not contribute fast subsurface
#' # flow via field drainage
#' groups <- disc$groups
#' groups$m <- 0.0044
#' # Simulate impermeable clay soils
#' groups$td <-  33
#' groups$ln_t0 <- 1.15
#' groups$srz_max <- 0.1
#' qobs <- brompton$qobs[sel]
#' qt0 <- as.numeric(qobs[1,])
#' # initial root zone storage - almost full due to previous event
#' groups$srz0 <- 0.98
#' # Quite slow channel flow, which might be expected with the shallow and reedy
#' # low bedslope reaches with very rough banks comprising the major channel
#' groups$vchan <- 400
#' groups$vof <- 50
#' # Rain is supplied at hourly intervals: convert to 15 minutes
#' rain <- disaggregate_xts(rain, dt = 15/60)
#' weights <- disc$weights
#' # Output goes to a new window
#' graphics.off()
#' x11()
#'
#' # Initial discharge from the observations
#' qt0 <- as.numeric(qobs[1,])
#'
#' # Run the model across the November 2012 storm event
#' # using a 15 minute interval
#' run <- run.dtm(groups=groups,
#'                weights=weights,
#'                rain=rain,
#'                pe=pe,
#'                qobs=qobs,
#'                qt0=qt0,
#'                routing=brompton$routing,
#'                graphics.show=TRUE, max.q=2.4)
#' }
#'
run.dtm <- function(groups,
                    weights,
                    rain,
                    routing,
                    upstream_inputs=NULL,
                    qobs=NULL,
                    qt0=1e-4,
                    pe=NULL,
                    dt=NULL,
                    ntt=2,
					          ichan=1,
					          Wsurf=weights,  # surface flow matrix
					          Wover=weights, # overflow matrix
                    i.out=ichan[1],
                    dqds=NULL,
                    sim.start=NA,
                    sim.end=NA,
                    disp.par = get.disp.par(),
					          ...)
{
	# any other parameters are assumed to control the output
	disp.par <- merge.lists(disp.par, list(...))
  start.time <- Sys.time()

  # setup input variable for run using supplied data, and copy the updated values back to
  # to the current environment
  data.in <- init.input(groups, dt, ntt,
  			weights, rain, pe, routing,
  			ichan=ichan, i.out=i.out, qobs=qobs,
  			qt0=qt0,
  			dqds=dqds,
        disp.par,
        sim.start,
  			sim.end,
        calling.env=environment())

  # add in any hydrographs from upstream
  upstream_inputs <- init_upstream_inputs(upstream_inputs, groups, dt=dt)

  catch.area <- sum(groups$area)
  storage.in <- current.storage(groups, stores, ichan)
  text.out <- stdout()

  ngroup <- nrow(groups)

  w <- weights
  a <- groups$area
  N <- nrow(w)
  # complementary weighting matrix, scaled by groups' areas
  A <- as.matrix(diag(1/a, N, N) %*% t(w) %*% diag(a, N, N) - identity.matrix(N))

  # split rain and pe between gauges
  rain.dist <- as.matrix(rain[,pmin(groups$gauge.id, ncol(rain))]  )
  pe.dist <-   as.matrix(pe[,pmin(groups$gauge.id, ncol(rain))]  )

  # apply any rain, overland flow or evapotranspiration multipliers for each of the HRU
  pe.dist <- t(apply(pe.dist, MARGIN=1, function(x)x*groups$pe_fact))
  rain.dist <- t(apply(rain.dist, MARGIN=1, function(x)x*groups$rain_fact))

  # empty times series for storage within the channel unit
  chan.storage <- pe-pe
  # surface excess
  stores$ex[ichan] <- 0
  ex <- stores$ex

  # total overland flow contribution to channels
  Qof <- Qr[,ichan]
  ngroup <- nrow(groups)
  max_it <- nrow(rain)
  tms <- index(rain)
  for(it in 1:max_it)
  {
 #   if(any(flows$qof>0)){browser()}
    st <- Sys.time()
  	tm <- tms[it]

  	# distribute any surface storage from previous time step downslope
  	if(any(stores$ex[] > 0))
  	{
  	  # treating channel storage as surface excess
  	  stores$ex <- distribute_surface_excess_storage(groups,
  	                                                 W=Wsurf,
  	                                                 Wover=Wover,
  	                                                 ex=stores$ex,
  	                                                 dt=dt,
  	                                                 fun=dsdt.lin,
  	                                                 ichan=ichan)
  	}

  	# additional overland input to channel ()
  	Qof[it,] <- stores$ex[ichan]/dt * groups$area[ichan]

  	# Overland flow into channel gets routed to outlet immediately alongside
  	# subsurface inputs)
  	stores$ex[ichan] <-0

    # inputs from distributed storage assuming linear relationship between specific
  	# discharge and surface storage
  	qof <- stores$ex*groups$vof / groups$area

  	# Allocate rainfall to groups using specified gauge specified, adding any
  	# overland flow from distributed from step. This allows for "run on"
    flows$rain <-  rain.dist[it,] #+ qof

    # reset the channel storages for next iteration
 #   stores$ex[] <- 0

    # subsurface flux routing and deficit update
    updated <- update.subsurface(groups,
   							flows=flows,
   							stores=stores,
   							w=weights,
                pe = pe.dist[it,],
                tm=tm,
                ntt=ntt,
                dt=dt,
                ichan=ichan,
   							A=A,
                dqds=dqds)

   flows <- updated$flows
   # add in
   stores <- updated$stores
   ex[] <- 0
   # specific overland flow
   # assumming linear relationship between discharge and storage
   flows$qof <- stores$ex*groups$vof

   # add input from overland flow to total channel inputs
   flows$qin[ichan] <- flows$qin[ichan] + Qof[it,]

   # route to outlet and update current
   Qr <- route.channel.flows(groups, flows,
                             stores,
                             delays=routing,
   													 chan.store=chan.storage,
                             weights, Qr, it, dt, ichan)

   for(upstream_input in upstream_inputs)
   {
     # add in any time-shifted hydrographs from gauge upstream of the catchment
     Qr[it,] <- Qr[it,] + as.numeric(upstream_input$qshift[it,])
     # note that routing is to catchment outlet, not merely to point where input joins
     # river network
   }

   # Flows between HRUs and drainage
   fluxes[it,,]<- as.matrix(flows[, c("qbf", "qin", "uz", "rain", "ae", "ex", "qof")])

   # specific discharge (m/hr)
   qr <- Qr/catch.area

   # SUmmarise storages
   storages[it,,]<- as.matrix(stores[, c("srz", "suz", "sd", "ex")])

  # overall actual evap
  evap[it,"ae"] <- weighted.mean(flows$ae, groups$area)

  # chan.storage <- as.numeric(chan.storage-Qr[it,]+sum(flows$qin[ichan]))
  # chan.storages[it,] <- chan.storage
  # discharges, rain and ae in mm/hr
	disp.results(it,
    tm=tm,
    qr=qr*1000,
    rain=rain*1000,
    evap=evap*1000,
    groups=groups,
    flows=flows,
    stores=stores,
    qobs=qobs*1000,
    ichan=ichan,
    text.out=text.out,
    log.msg="",
    start = sim.start,
    end = sim.end,
    disp.par=disp.par)

    flows[, c("pex", "ex", "exus")] <- 0

    dur <- difftime(Sys.time(), st)
    # removing the excess storage
	#	stores$ex[]<- 0
  }  # next it

  # collecting the results together
  # convert fluxes to a named list of time series
  fluxes <- apply(fluxes, MARGIN=3, function(x){list(x)})
  fluxes <- lapply(fluxes, function(x)xts(x[[1]], order.by=tms))

  names(fluxes) <- c("qbf", "qin", "uz", "rain", "ae", "ex", "qof")

  # total ovf is amount transferred to outlet (includes rain directly to channel?)
  # in this formulation all excess flow is routed immediately and then removed
  # ovf <-   dt*sum(Qof)/catch.area
  mass.out <- sum(Qr*dt)

  # converting storages to a list
  storages <- apply(storages, MARGIN=3, function(x){list(x)})
  storages <- lapply(storages, function(x)xts(x[[1]], order.by=tms))
  names(storages) <- c("srz", "suz", "sd", "ex")

 	# water balance checks
  # output discharge
  Q_out <- sum(Qr*dt)
  tot_in <- sum(rain*catch.area)*dt
  # total of absolute output from catchment
  tot_out <- Q_out+ sum(evap[,"ae"])*catch.area*dt
  # storage gained (subtract deficit gained )
  sd.gain <- (as.numeric(storages$srz[it,-ichan])-as.numeric(storages$srz[1,-ichan]))*groups$area[-1]

  sd.gain <- sd.gain - (as.numeric(storages$sd[it,-ichan])-as.numeric(storages$sd[1,-ichan]))*groups$area[-1]

  if(disp.par$stats.show)
  {
    message("Time at peak is ", time_at_peak(qr))
    if(!is.null(qobs))message("NSE is ", NSE(qr, qobs))
    # total overland flow into  channel (doesn't matter where it ends up after that)            ]
    message("Total overland flow contribution is ", round(sum(Qof)/catch.area*1000), " mm/hr")
    message("Total discharge was ", round(sum(Qr[])/catch.area*1000), " mm/hr")
    message("Run took ", round(difftime(Sys.time(), start.time, units = "s"), 1), " seconds")
  }

  # list of relevant results
  return(list("qsim"=qr,  # specific
              "Qsim"=Qr,   # total
              "start"=sim.start,
              "end"=sim.end,
              "fluxes"=fluxes,
              "storages"=storages,
  						"weights"=weights,  # the flux distributiom matrix
  						"dt"=dt,
              "qobs"=qobs,
              "ae"=evap[,"ae"],
              "Qof"=Qof,
  						"tot_in"=tot_in,
  						"tot_out"=tot_out,
  						"prop_ovf"=sum(Qof)/sum(Qr),   # proportion of discharge due to saturated overland flow
  						"groups"=groups,
              "rain"=rain,
  						 run.par=list(tms=tms),
               catch.area=catch.area))
}




