# ggPMX PKPD Endpoint Patch for nlmixr2

Endpoint-aware diagnostic plotting workflow for `nlmixr2` PK/PD models using `ggPMX`.

This repository provides a small patch layer that helps `ggPMX` handle multi-endpoint `nlmixr2` models, especially for separate PK and PD individual plots and visual predictive checks.

## Overview

Multi-endpoint PK/PD models often contain more than one observation type, for example:

- `cp`: PK concentration endpoint
- `pca`: PD effect endpoint

This patch makes it easier to create endpoint-specific `ggPMX` controllers from a single `nlmixr2` fit object.

It supports:

- separate PK and PD individual plots
- separate PK and PD VPCs
- endpoint-filtered prediction datasets
- endpoint-filtered simulation datasets
- endpoint-aware merging of VPC simulations and observed metadata

## Files

### `ggpmx_pkpd_patch.R`

Patch script for the current R session.

It modifies selected `ggPMX` behavior after sourcing. The patch is applied automatically when the file is sourced.

```r
source("ggpmx_pkpd_patch.R")
```

The patch does not permanently modify the installed `ggPMX` package. Restarting R restores the original package behavior unless the patch is sourced again.

### `01_warfarin_pkpd_ggpmx_example.R`

Example script using the built-in `warfarin` dataset from `nlmixr2`.

The script:

- defines a joint PK/PD turnover Emax model
- fits the model with `nlmixr2`
- creates separate `ggPMX` controllers for PK and PD
- generates endpoint-specific individual plots
- generates endpoint-specific VPCs

## Requirements

Required R packages:

```r
library(nlmixr2)
library(ggPMX)
library(ggplot2)
library(data.table)
```

Install packages if needed:

```r
install.packages(c("ggplot2", "data.table", "ggPMX"))
install.packages("nlmixr2")
```

## Quick start

Source the patch:

```r
source("ggpmx_pkpd_patch.R")
```

Fit or load a multi-endpoint `nlmixr2` model:

```r
fit_nm <- readRDS("fit_nm.RDS")
```

Define PK and PD endpoints:

```r
ep_pk <- ggPMX::pmx_endpoint(
  code = "cp",
  label = "PK concentration"
)

ep_pd <- ggPMX::pmx_endpoint(
  code = "pca",
  label = "PD effect"
)
```

Create endpoint-specific `ggPMX` controllers:

```r
pmx_pk <- ggPMX::pmx_nlmixr(
  fit = fit_nm,
  dvid = "CMT",
  endpoint = ep_pk,
  vpc = TRUE,
  vpc_n = 300,
  vpc_seed = 123
)

pmx_pd <- ggPMX::pmx_nlmixr(
  fit = fit_nm,
  dvid = "CMT",
  endpoint = ep_pd,
  vpc = TRUE,
  vpc_n = 300,
  vpc_seed = 123
)
```

Generate individual plots:

```r
pmx_pk |> ggPMX::pmx_plot_individual()

pmx_pd |> ggPMX::pmx_plot_individual()
```

Generate VPCs:

```r
pmx_pk |> ggPMX::pmx_plot_vpc()

pmx_pd |> ggPMX::pmx_plot_vpc()
```

## Example endpoints

For the Warfarin PK/PD example:

```r
table(fit_nm$CMT)
```

Typical endpoint values are:

```text
cp   PK concentration
pca  PD effect
```

These are passed to `pmx_endpoint()`:

```r
ep_pk <- ggPMX::pmx_endpoint(
  code = "cp",
  label = "PK concentration"
)

ep_pd <- ggPMX::pmx_endpoint(
  code = "pca",
  label = "PD effect"
)
```

## Checking endpoint separation

After creating the controllers, check that each controller contains only one endpoint.

```r
table(pmx_pk$data$IND$CMT, useNA = "ifany")
table(pmx_pd$data$IND$CMT, useNA = "ifany")
```

Expected:

```text
pmx_pk: cp only
pmx_pd: pca only
```

Check the VPC simulation data:

```r
table(pmx_pk$data$sim$CMT, useNA = "ifany")
table(pmx_pd$data$sim$CMT, useNA = "ifany")
```

Expected:

```text
pmx_pk: cp only
pmx_pd: pca only
```

## Saving plots

```r
dir.create("figures", showWarnings = FALSE)

p_ind_pk <- pmx_pk |> ggPMX::pmx_plot_individual()
p_ind_pd <- pmx_pd |> ggPMX::pmx_plot_individual()

p_vpc_pk <- pmx_pk |> ggPMX::pmx_plot_vpc()
p_vpc_pd <- pmx_pd |> ggPMX::pmx_plot_vpc()

ggplot2::ggsave(
  "figures/individual_PK.png",
  p_ind_pk,
  width = 14,
  height = 10,
  dpi = 600,
  bg = "white"
)

ggplot2::ggsave(
  "figures/individual_PD.png",
  p_ind_pd,
  width = 14,
  height = 10,
  dpi = 600,
  bg = "white"
)

ggplot2::ggsave(
  "figures/vpc_PK.png",
  p_vpc_pk,
  width = 12,
  height = 8,
  dpi = 600,
  bg = "white"
)

ggplot2::ggsave(
  "figures/vpc_PD.png",
  p_vpc_pd,
  width = 12,
  height = 8,
  dpi = 600,
  bg = "white"
)
```

## Recommended repository structure

```text
ggPMX-pkpd-endpoint-patch/
├── README.md
├── ggpmx_pkpd_patch.R
├── 01_warfarin_pkpd_ggpmx_example.R
└── figures/
```

## Notes

This patch is intended as a practical prototype for endpoint-aware `ggPMX` support with `nlmixr2` PK/PD models.

It is useful when a single fitted model contains multiple observation endpoints and separate diagnostic plots are needed for each endpoint.

The patch is session-based. It uses `assignInNamespace()` to modify selected `ggPMX` functions while the R session is active.

## Disclaimer

This is an experimental workflow intended for model diagnostics and development. Validate all plots and outputs before using them in formal reports or submissions.
