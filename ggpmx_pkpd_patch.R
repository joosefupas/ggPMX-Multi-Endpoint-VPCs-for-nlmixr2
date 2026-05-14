# ggpmx_pkpd_optionB_patch.R

suppressPackageStartupMessages({
  library(data.table)
  library(ggPMX)
  library(ggplot2)
})

ggpmx_endpoint_code <- function(endpoint) {
  if (is.null(endpoint)) {
    return(NULL)
  }
  
  if (inherits(endpoint, "pmxEndpointClass")) {
    return(as.character(endpoint$code))
  }
  
  as.character(endpoint)
}

ggpmx_scalar_dvid <- function(dvid) {
  if (is.null(dvid) || isFALSE(dvid) || length(dvid) < 1) {
    return(NULL)
  }
  
  dvid <- as.character(dvid)[1]
  
  if (is.na(dvid) || identical(dvid, "")) {
    return(NULL)
  }
  
  dvid
}

ggpmx_filter_endpoint_dt <- function(x, dvid = NULL, endpoint = NULL) {
  code <- ggpmx_endpoint_code(endpoint)
  dvid <- ggpmx_scalar_dvid(dvid)
  
  if (is.null(code) || is.null(dvid) || !is.data.frame(x)) {
    return(x)
  }
  
  x <- data.table::as.data.table(data.table::copy(x))
  nms <- names(x)
  
  # Exact endpoint column.
  if (dvid %in% nms) {
    keep <- as.character(x[[dvid]]) %in% code
    return(x[which(keep)])
  }
  
  # Case-insensitive endpoint column.
  dvid_alt <- nms[tolower(nms) == tolower(dvid)]
  
  if (length(dvid_alt) >= 1) {
    data.table::setnames(x, old = dvid_alt[1], new = dvid)
    keep <- as.character(x[[dvid]]) %in% code
    return(x[which(keep)])
  }
  
  # Unnamed endpoint column, as seen in nlmixr finegrid IND.
  unnamed <- which(is.na(nms) | nms == "")
  
  if (length(unnamed) > 0) {
    for (j in unnamed) {
      vals <- unique(as.character(x[[j]]))
      vals <- vals[!is.na(vals)]
      
      if (any(vals %in% code)) {
        data.table::setnames(x, old = j, new = dvid)
        keep <- as.character(x[[dvid]]) %in% code
        return(x[which(keep)])
      }
    }
  }
  
  x
}

ggpmx_fix_endpoint_controller <- function(ctr) {
  ctr2 <- ctr$clone(deep = TRUE)
  
  ctr2$input <- ggpmx_filter_endpoint_dt(
    ctr2$input,
    dvid = ctr2$dvid,
    endpoint = ctr2$endpoint
  )
  
  if (is.list(ctr2$data)) {
    ctr2$data <- lapply(
      ctr2$data,
      ggpmx_filter_endpoint_dt,
      dvid = ctr2$dvid,
      endpoint = ctr2$endpoint
    )
  }
  
  if (!is.null(ctr2$sim) && !is.null(ctr2$sim$sim)) {
    ctr2$sim$sim <- ggpmx_filter_endpoint_dt(
      ctr2$sim$sim,
      dvid = ctr2$dvid,
      endpoint = ctr2$endpoint
    )
  }
  
  ctr2
}

ggpmx_endpoint_merge_by_auto <- function(dx, inn) {
  by <- c("ID", "TIME")
  
  endpoint_candidates <- c(
    "DVID",
    "CMT",
    "YTYPE",
    "Endpoint",
    "endpoint",
    "dvid",
    "cmt",
    "ytype"
  )
  
  common_endpoint <- intersect(
    endpoint_candidates,
    intersect(names(dx), names(inn))
  )
  
  if (length(common_endpoint) >= 1) {
    by <- c(by, common_endpoint[1])
  }
  
  by
}

ggpmx_merge_sim_input_endpoint_aware <- function(dx, inn, sys = "nlmixr") {
  dx <- data.table::as.data.table(data.table::copy(dx))
  inn <- data.table::as.data.table(data.table::copy(inn))
  
  if (identical(sys, "nlmixr")) {
    if ("ID" %in% names(inn) && inherits(inn$ID, "factor")) {
      if ("ID" %in% names(dx)) {
        ID <- dx$ID
        attr(ID, "levels") <- levels(inn$ID)
        attr(ID, "class") <- "factor"
        dx$ID <- ID
      }
    }
  }
  
  by <- ggpmx_endpoint_merge_by_auto(dx, inn)
  
  message("Endpoint-aware VPC merge by: ", paste(by, collapse = ", "))
  
  missing_dx <- setdiff(by, names(dx))
  missing_inn <- setdiff(by, names(inn))
  
  if (length(missing_dx) > 0) {
    stop(
      "Merge column(s) missing in simulation data: ",
      paste(missing_dx, collapse = ", ")
    )
  }
  
  if (length(missing_inn) > 0) {
    stop(
      "Merge column(s) missing in input data: ",
      paste(missing_inn, collapse = ", ")
    )
  }
  
  n_before <- nrow(inn)
  
  inn <- unique(
    inn,
    by = by
  )
  
  n_after <- nrow(inn)
  
  if (n_after < n_before) {
    warning(
      paste0(
        "Collapsed input metadata from ",
        n_before,
        " to ",
        n_after,
        " rows using merge keys: ",
        paste(by, collapse = ", "),
        "."
      ),
      call. = FALSE
    )
  }
  
  merge(
    dx,
    inn,
    by = by,
    all.x = TRUE,
    allow.cartesian = FALSE
  )
}

ggpmx_add_nlmixr_vpc_to_controller <- function(
    ctr,
    fit,
    n = 300,
    seed = 1009,
    pred = FALSE,
    sim_data = NULL,
    verbose = TRUE
) {
  ctr2 <- ctr$clone(deep = TRUE)
  
  ctr2 <- ggpmx_fix_endpoint_controller(ctr2)
  
  dvid <- ctr2$dvid
  endpoint <- ctr2$endpoint
  
  if (verbose) {
    message("Creating endpoint-aware VPC data")
    message("Endpoint column: ", dvid)
    message("Endpoint code: ", paste(ggpmx_endpoint_code(endpoint), collapse = ", "))
  }
  
  if (is.null(sim_data)) {
    sim_data <- nlmixr2est::vpcSim(
      fit,
      n = n,
      seed = seed,
      pred = pred
    )
  }
  
  sim_data <- data.table::as.data.table(data.table::copy(sim_data))
  
  drop_cols <- intersect(
    c("rxLambda", "rxYj", "rxLow", "rxHi"),
    names(sim_data)
  )
  
  if (length(drop_cols) > 0) {
    sim_data[, (drop_cols) := NULL]
  }
  
  sim_data <- ggpmx_filter_endpoint_dt(
    sim_data,
    dvid = dvid,
    endpoint = endpoint
  )
  
  if ("sim" %in% names(sim_data) && !"DV" %in% names(sim_data)) {
    data.table::setnames(sim_data, "sim", "DV")
  }
  
  sim_obj <- ggPMX::pmx_sim(
    data = sim_data,
    idv = "time",
    irun = "sim.id"
  )
  
  dx <- sim_obj[["sim"]]
  
  inn <- data.table::as.data.table(data.table::copy(ctr2$input))
  
  if (ctr2$dv %in% names(inn)) {
    inn[, (ctr2$dv) := NULL]
  }
  
  ctr2$data[["sim"]] <- ggpmx_merge_sim_input_endpoint_aware(
    dx = dx,
    inn = inn,
    sys = ctr2$config$sys
  )
  
  ctr2$sim <- sim_obj
  
  ctr2
}

ggpmx_plot_vpc_direct <- function(
    ctr,
    type = c("percentile", "scatter"),
    bin = NULL,
    strat.facet = NULL,
    facets = NULL,
    pi = ggPMX::pmx_vpc_pi(),
    ci = ggPMX::pmx_vpc_ci(),
    obs = ggPMX::pmx_vpc_obs(),
    rug = ggPMX::pmx_vpc_rug(),
    labels = list(
      title = "Visual Predictive Check",
      subtitle = "",
      x = "TIME",
      y = "DV"
    ),
    is.legend = TRUE,
    is.footnote = TRUE,
    ...
) {
  type <- match.arg(type)
  
  if (is.null(ctr$sim)) {
    stop("Controller has no sim object.")
  }
  
  if (is.null(ctr$data$sim)) {
    stop("Controller has no data$sim.")
  }
  
  x <- ggPMX::pmx_vpc(
    type = type,
    idv = ctr$sim[["idv"]],
    obs = obs,
    pi = pi,
    ci = ci,
    rug = rug,
    bin = bin,
    labels = labels,
    facets = facets,
    is.legend = is.legend,
    is.footnote = is.footnote,
    dname = "sim",
    ...
  )
  
  x$input <- data.table::as.data.table(data.table::copy(ctr$input))
  x$dx <- data.table::as.data.table(data.table::copy(ctr$data$sim))
  x$strat.facet <- strat.facet
  
  idv <- ctr$sim[["idv"]]
  irun <- ctr$sim[["irun"]]
  dv <- ctr$dv
  
  missing_input <- setdiff(c(idv, dv), names(x$input))
  missing_sim <- setdiff(c(idv, irun, dv), names(x$dx))
  
  if (length(missing_input) > 0) {
    stop(
      "Input is missing required column(s): ",
      paste(missing_input, collapse = ", ")
    )
  }
  
  if (length(missing_sim) > 0) {
    stop(
      "Simulation data is missing required column(s): ",
      paste(missing_sim, collapse = ", ")
    )
  }
  
  x <- ggPMX:::.vpc_x(x, ctr)
  
  if (is.null(x$gp$labels)) {
    x$gp$labels <- labels
  }
  
  if (is.null(x$gp$labels$title) || is.na(x$gp$labels$title)) {
    x$gp$labels$title <- labels$title
  }
  
  if (is.null(x$gp$labels$subtitle) || is.na(x$gp$labels$subtitle)) {
    x$gp$labels$subtitle <- labels$subtitle
  }
  
  if (is.null(x$gp$labels$x) || is.na(x$gp$labels$x)) {
    x$gp$labels$x <- labels$x
  }
  
  if (is.null(x$gp$labels$y) || is.na(x$gp$labels$y)) {
    x$gp$labels$y <- labels$y
  }
  
  x <- ggPMX:::vpc_legend.(x)
  x <- ggPMX:::vpc_footnote.(x)
  
  p <- ggPMX:::vpc.plot(x)
  
  p + ggplot2::labs(
    title = x$gp$labels$title,
    subtitle = x$gp$labels$subtitle,
    x = x$gp$labels$x,
    y = x$gp$labels$y
  )
}


ggpmx_install_pkpd_patch <- function(force = FALSE) {
  ns <- asNamespace("ggPMX")
  
  current_pmx_nlmixr <- get("pmx_nlmixr", envir = ns)
  
  if (
    !force &&
    isTRUE(attr(current_pmx_nlmixr, "ggpmx_pkpd_patch"))
  ) {
    message("ggPMX PKPD nlmixr patch already installed.")
    return(invisible(TRUE))
  }
  
  if (!exists(".ggpmx_original_pmx_nlmixr", envir = .GlobalEnv, inherits = FALSE)) {
    assign(
      ".ggpmx_original_pmx_nlmixr",
      get("pmx_nlmixr", envir = ns),
      envir = .GlobalEnv
    )
  }
  
  if (!exists(".ggpmx_original_pmx_plot_vpc", envir = .GlobalEnv, inherits = FALSE)) {
    assign(
      ".ggpmx_original_pmx_plot_vpc",
      get("pmx_plot_vpc", envir = ns),
      envir = .GlobalEnv
    )
  }
  
  if (!exists(".ggpmx_original_merge_dx_inn_by_id_time", envir = .GlobalEnv, inherits = FALSE)) {
    assign(
      ".ggpmx_original_merge_dx_inn_by_id_time",
      get("merge_dx_inn_by_id_time", envir = ns),
      envir = .GlobalEnv
    )
  }
  
  original_pmx_nlmixr <- get(".ggpmx_original_pmx_nlmixr", envir = .GlobalEnv)
  original_pmx_plot_vpc <- get(".ggpmx_original_pmx_plot_vpc", envir = .GlobalEnv)
  
  patched_pmx_nlmixr <- function(
    fit,
    dvid,
    conts,
    cats,
    strats,
    endpoint,
    settings,
    vpc = FALSE,
    vpc_n = 300,
    vpc_seed = 1009,
    vpc_pred = FALSE,
    ...
  ) {
    args <- list(
      fit = fit,
      vpc = FALSE
    )
    
    if (!missing(dvid)) {
      args$dvid <- dvid
    }
    
    if (!missing(conts)) {
      args$conts <- conts
    }
    
    if (!missing(cats)) {
      args$cats <- cats
    }
    
    if (!missing(strats)) {
      args$strats <- strats
    }
    
    if (!missing(endpoint)) {
      args$endpoint <- endpoint
    }
    
    if (!missing(settings)) {
      args$settings <- settings
    }
    
    ctr <- do.call(original_pmx_nlmixr, args)
    
    ctr <- ggpmx_fix_endpoint_controller(ctr)
    
    if (isTRUE(vpc)) {
      ctr <- ggpmx_add_nlmixr_vpc_to_controller(
        ctr = ctr,
        fit = fit,
        n = vpc_n,
        seed = vpc_seed,
        pred = vpc_pred,
        verbose = TRUE
      )
    }
    
    ctr
  }
  
  patched_pmx_plot_vpc <- function(
    ctr,
    type,
    idv,
    obs,
    pi,
    ci,
    rug,
    bin,
    is.legend,
    sim_blq,
    dname,
    filter,
    strat.facet,
    facets,
    strat.color,
    trans,
    pmxgpar,
    labels,
    axis.title,
    axis.text,
    ranges,
    is.smooth,
    smooth,
    is.band,
    band,
    is.draft,
    draft,
    is.identity_line,
    identity_line,
    scale_x_log10,
    scale_y_log10,
    color.scales,
    is.footnote,
    ...
  ) {
    mc <- match.call(expand.dots = TRUE)
    mc[[1]] <- original_pmx_plot_vpc
    
    res <- try(
      eval(mc, parent.frame()),
      silent = TRUE
    )
    
    if (!inherits(res, "try-error") && !is.null(res)) {
      return(res)
    }
    
    if (is.null(ctr$sim) || is.null(ctr$data$sim)) {
      if (inherits(res, "try-error")) {
        stop(res)
      }
      
      return(NULL)
    }
    
    type_val <- if (missing(type)) "percentile" else type
    bin_val <- if (missing(bin)) NULL else bin
    strat_val <- if (missing(strat.facet)) NULL else strat.facet
    facets_val <- if (missing(facets)) NULL else facets
    
    pi_val <- if (missing(pi)) ggPMX::pmx_vpc_pi() else pi
    ci_val <- if (missing(ci)) ggPMX::pmx_vpc_ci() else ci
    obs_val <- if (missing(obs)) ggPMX::pmx_vpc_obs() else obs
    rug_val <- if (missing(rug)) ggPMX::pmx_vpc_rug() else rug
    
    legend_val <- if (missing(is.legend)) TRUE else is.legend
    footnote_val <- if (missing(is.footnote)) TRUE else is.footnote
    
    labels_val <- if (missing(labels) || is.null(labels)) {
      endpoint_label <- ""
      
      if (!is.null(ctr$endpoint) && inherits(ctr$endpoint, "pmxEndpointClass")) {
        endpoint_label <- ctr$endpoint$label
      }
      
      if (is.null(endpoint_label) || identical(endpoint_label, "")) {
        endpoint_label <- ggpmx_endpoint_code(ctr$endpoint)
      }
      
      list(
        title = "Visual Predictive Check",
        subtitle = paste0("Endpoint ", endpoint_label),
        x = ctr$sim[["idv"]],
        y = ctr$dv
      )
    } else {
      labels
    }
    
    ggpmx_plot_vpc_direct(
      ctr = ctr,
      type = type_val,
      bin = bin_val,
      strat.facet = strat_val,
      facets = facets_val,
      pi = pi_val,
      ci = ci_val,
      obs = obs_val,
      rug = rug_val,
      labels = labels_val,
      is.legend = legend_val,
      is.footnote = footnote_val,
      ...
    )
  }
  
  attr(patched_pmx_nlmixr, "ggpmx_pkpd_patch") <- TRUE
  attr(patched_pmx_plot_vpc, "ggpmx_pkpd_patch") <- TRUE
  
  assignInNamespace(
    x = "merge_dx_inn_by_id_time",
    value = ggpmx_merge_sim_input_endpoint_aware,
    ns = "ggPMX"
  )
  
  assignInNamespace(
    x = "pmx_nlmixr",
    value = patched_pmx_nlmixr,
    ns = "ggPMX"
  )
  
  assignInNamespace(
    x = "pmx_plot_vpc",
    value = patched_pmx_plot_vpc,
    ns = "ggPMX"
  )
  
  message("Installed ggPMX PKPD nlmixr patch for this R session.")
  
  invisible(TRUE)
}

ggpmx_uninstall_pkpd_patch <- function() {
  if (exists(".ggpmx_original_pmx_nlmixr", envir = .GlobalEnv, inherits = FALSE)) {
    assignInNamespace(
      x = "pmx_nlmixr",
      value = get(".ggpmx_original_pmx_nlmixr", envir = .GlobalEnv),
      ns = "ggPMX"
    )
  }
  
  if (exists(".ggpmx_original_pmx_plot_vpc", envir = .GlobalEnv, inherits = FALSE)) {
    assignInNamespace(
      x = "pmx_plot_vpc",
      value = get(".ggpmx_original_pmx_plot_vpc", envir = .GlobalEnv),
      ns = "ggPMX"
    )
  }
  
  if (exists(".ggpmx_original_merge_dx_inn_by_id_time", envir = .GlobalEnv, inherits = FALSE)) {
    assignInNamespace(
      x = "merge_dx_inn_by_id_time",
      value = get(".ggpmx_original_merge_dx_inn_by_id_time", envir = .GlobalEnv),
      ns = "ggPMX"
    )
  }
  
  message("Restored original ggPMX functions for this R session.")
  
  invisible(TRUE)
}

if (isTRUE(getOption("ggpmx.pkpd.autoinstall", TRUE))) {
  ggpmx_install_pkpd_patch()
}
