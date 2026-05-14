library(nlmixr2)
library(ggPMX)
library(ggplot2)

source("ggpmx_pkpd_patch.R")

pk.turnover.emax3 <- function() {
  ini({
    tktr <- log(1)
    tka <- log(1)
    tcl <- log(0.1)
    tv <- log(10)
    
    eta.ktr ~ 1
    eta.ka ~ 1
    eta.cl ~ 2
    eta.v ~ 1
    
    prop.err <- 0.1
    pkadd.err <- 0.1
    
    temax <- logit(0.8)
    tec50 <- log(0.5)
    tkout <- log(0.05)
    te0 <- log(100)
    
    eta.emax ~ 0.5
    eta.ec50 ~ 0.5
    eta.kout ~ 0.5
    eta.e0 ~ 0.5
    
    pdadd.err <- 10
  })
  
  model({
    ktr <- exp(tktr + eta.ktr)
    ka <- exp(tka + eta.ka)
    cl <- exp(tcl + eta.cl)
    v <- exp(tv + eta.v)
    
    emax <- expit(temax + eta.emax)
    ec50 <- exp(tec50 + eta.ec50)
    kout <- exp(tkout + eta.kout)
    e0 <- exp(te0 + eta.e0)
    
    DCP <- center / v
    PD <- 1 - emax * DCP / (ec50 + DCP)
    
    effect(0) <- e0
    kin <- e0 * kout
    
    d/dt(depot) <- -ktr * depot
    d/dt(gut) <- ktr * depot - ka * gut
    d/dt(center) <- ka * gut - cl / v * center
    d/dt(effect) <- kin * PD - kout * effect
    
    cp <- center / v
    
    cp ~ prop(prop.err) + add(pkadd.err)
    effect ~ add(pdadd.err) | pca
  })
}

ui <- nlmixr(pk.turnover.emax3)

ui$multipleEndpoint

summary(warfarin)

fit.TOS <- nlmixr(
  pk.turnover.emax3,
  warfarin,
  est = "saem",
  control = list(print = 0),
  table = list(cwres = TRUE, npde = TRUE)
)


ep_pk <- ggPMX::pmx_endpoint(
  code = "cp",
  label = "PK concentration"
)

ep_pd <- ggPMX::pmx_endpoint(
  code = "pca",
  label = "PD effect"
)

pmx_pk <- ggPMX::pmx_nlmixr(
  fit = fit.TOS,
  dvid = "CMT",
  endpoint = ep_pk,
  vpc = TRUE,
  vpc_n = 300,
  vpc_seed = 123
)


pmx_pd <- ggPMX::pmx_nlmixr(
  fit = fit.TOS,
  dvid = "CMT",
  endpoint = ep_pd,
  vpc = TRUE,
  vpc_n = 300,
  vpc_seed = 123
)


p_ind_pk <- pmx_pk |>
  ggPMX::pmx_plot_individual(
    which_pages = 1,
    labels = list(
      title = "PK Individual Fits",
      subtitle = "Endpoint cp",
      x = "Time",
      y = "Concentration"
    )
  )

p_ind_pk

p_ind_pd <- pmx_pd |>
  ggPMX::pmx_plot_individual(
    which_pages = 1,
    labels = list(
      title = "PD Individual Fits",
      subtitle = "Endpoint pca",
      x = "Time",
      y = "Effect"
    )
  )

p_ind_pd

p_vpc_pk <- pmx_pk |>
  ggPMX::pmx_plot_vpc(
    labels = list(
      title = "PK VPC",
      subtitle = "Endpoint cp",
      x = "Time",
      y = "Concentration"
    )
  )

p_vpc_pk

p_vpc_pd <- pmx_pd |>
  ggPMX::pmx_plot_vpc(
    labels = list(
      title = "PD VPC",
      subtitle = "Endpoint pca",
      x = "Time",
      y = "Effect"
    )
  )

p_vpc_pd


