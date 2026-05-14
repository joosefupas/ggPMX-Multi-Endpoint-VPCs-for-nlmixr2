# ggPMX PKPD Endpoint Patch for nlmixr2

This repository contains a session-level patch that extends the practical use of `ggPMX` with multi-endpoint `nlmixr2` PK/PD models.

The main goal is to make `ggPMX::pmx_nlmixr()` and `ggPMX::pmx_plot_vpc()` work more reliably when a single `nlmixr2` fit contains more than one endpoint, for example:

- `cp`: PK concentration endpoint
- `pca`: PD effect endpoint

The patch is designed to support endpoint-specific diagnostics from the same fitted model object.

## Core problem

In multi-endpoint PK/PD models, a fitted `nlmixr2` object may contain observations from more than one endpoint at the same subject and time.

For example:

```text
ID   TIME   CMT
1    24     cp
1    24     pca
```

This is valid PK/PD data, but it can cause problems when plotting diagnostics if the endpoint is not included in filtering, grouping, or merging operations.

Two main issues were addressed.

### 1. Individual plot endpoint mixing

`ggPMX` may create an individual prediction dataset that contains both endpoints. In some cases, the endpoint column is carried as an unnamed column.

This can lead to individual prediction lines that connect PK and PD values in the same subject panel.

The resulting plot may show artificial vertical oscillations because the line jumps between endpoints on different scales.

The patch fixes this by:

- detecting the endpoint column
- handling exact, case-insensitive, and unnamed endpoint columns
- filtering controller datasets to the selected endpoint
- ensuring the `IND` dataset used for individual plots contains only the requested endpoint

### 2. VPC simulation merge issue

For VPCs, simulated data are merged with observed metadata.

The original merge logic uses:

```r
by = c("ID", "TIME")
```

This is insufficient for PK/PD models because `ID + TIME` may not be unique when multiple endpoints are present.

The patch makes this merge endpoint-aware.

If an endpoint column such as `CMT` or `DVID` is present in both datasets, the merge key becomes:

```r
by = c("ID", "TIME", "CMT")
```

or equivalently:

```r
by = c("ID", "TIME", "DVID")
```

depending on the endpoint column available.

This prevents PK and PD records from being incorrectly joined during VPC construction.

## What the patch does

The patch modifies selected `ggPMX` behavior in the active R session.

It does not permanently modify the installed `ggPMX` package.

When sourced, the patch:

```r
source("ggpmx_pkpd_patch.R")
```

automatically installs patched versions of selected functions.

## Main technical components

### `ggpmx_endpoint_code()`

Extracts the endpoint code from either:

- a `pmxEndpointClass` object
- a character endpoint code
- a numeric endpoint code

Example:

```r
ep_pk <- ggPMX::pmx_endpoint(
  code = "cp",
  label = "PK concentration"
)
```

The function extracts:

```r
"cp"
```

### `ggpmx_scalar_dvid()`

Normalizes the endpoint-identifying column name.

For example:

```r
"CMT"
```

or:

```r
"DVID"
```

It returns `NULL` if no valid endpoint column is supplied.

### `ggpmx_filter_endpoint_dt()`

Filters a data frame or data table to a selected endpoint.

It supports three cases:

1. Endpoint column exists exactly:

```r
CMT
```

2. Endpoint column exists with different case:

```r
cmt
```

3. Endpoint column is unnamed, which can happen in the `ggPMX` individual prediction dataset.

This is important because one observed issue was:

```r
names(pmx_pk$data$IND)
```

returning something like:

```r
"ID" "TIME" "" "IPRED" "PRED" "DV"
```

where the unnamed column contained endpoint values such as:

```r
cp
pca
```

The patch detects this situation, renames the column to the endpoint identifier, and filters it.

### `ggpmx_fix_endpoint_controller()`

Applies endpoint filtering across the main parts of a `ggPMX` controller:

- `ctr$input`
- `ctr$data$predictions`
- `ctr$data$IND`
- `ctr$data$eta`
- `ctr$sim$sim`, when present

This ensures that a PK controller contains only PK rows and a PD controller contains only PD rows.

### `ggpmx_endpoint_merge_by_auto()`

Builds an endpoint-aware merge key for VPC simulation data.

Default key:

```r
c("ID", "TIME")
```

If a common endpoint column is found in both datasets, it appends the endpoint column.

Candidate endpoint columns include:

```r
DVID
CMT
YTYPE
Endpoint
endpoint
dvid
cmt
ytype
```

For example, if both datasets contain `CMT`, the merge key becomes:

```r
c("ID", "TIME", "CMT")
```

### `ggpmx_merge_sim_input_endpoint_aware()`

Replaces the non-endpoint-aware VPC merge.

It:

1. Converts simulation and input metadata to `data.table`
2. Determines the correct merge key
3. Collapses duplicated input metadata rows by the merge key
4. Merges simulation data and input metadata safely

This avoids many-to-many joins caused by multiple endpoints at the same time.

### `ggpmx_add_nlmixr_vpc_to_controller()`

Adds endpoint-aware VPC simulation data to a `ggPMX` controller.

It:

1. Clones the controller
2. Filters the controller to one endpoint
3. Runs `nlmixr2est::vpcSim()`
4. Filters the simulation data to the selected endpoint
5. Renames simulated response from `sim` to `DV`
6. Builds a `pmx_sim` object
7. Performs endpoint-aware merging with observed metadata
8. Stores the result in:

```r
ctr$data$sim
```

and:

```r
ctr$sim
```

### `ggpmx_plot_vpc_direct()`

Provides a fallback VPC plotting route.

This function directly constructs the VPC plot using internal `ggPMX` VPC utilities after the endpoint-aware VPC dataset has been created.

It is used when the standard `ggPMX::pmx_plot_vpc()` machinery does not return a plot for the patched controller.

### Patched `ggPMX::pmx_nlmixr()`

The patch wraps the original `ggPMX::pmx_nlmixr()`.

The patched version:

1. Calls the original function with `vpc = FALSE`
2. Filters the resulting controller by endpoint
3. Optionally creates endpoint-aware VPC simulation data if `vpc = TRUE`

This allows calls such as:

```r
pmx_pk <- ggPMX::pmx_nlmixr(
  fit = fit.TOS,
  dvid = "CMT",
  endpoint = ep_pk,
  vpc = TRUE,
  vpc_n = 300,
  vpc_seed = 123
)
```

### Patched `ggPMX::pmx_plot_vpc()`

The patch also wraps `ggPMX::pmx_plot_vpc()`.

The patched function first tries the original `ggPMX` plotting method.

If that fails or returns `NULL`, it falls back to the direct VPC plotting function:

```r
ggpmx_plot_vpc_direct()
```

This allows the usual user-facing syntax:

```r
pmx_pk |> ggPMX::pmx_plot_vpc()
```

instead of requiring a separate custom plotting call.

## Installation in the current R session

Source the patch file:

```r
source("ggpmx_pkpd_patch.R")
```

The patch auto-installs when sourced.

To check that the patch is active:

```r
attr(get("pmx_nlmixr", envir = asNamespace("ggPMX")), "ggpmx_pkpd_patch")

attr(get("pmx_plot_vpc", envir = asNamespace("ggPMX")), "ggpmx_pkpd_patch")
```

Both should return:

```r
TRUE
```

## Example workflow

Define endpoints:

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

Create endpoint-specific controllers:

```r
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

## Validation checks

After creating the controllers, confirm that each controller contains only the intended endpoint.

For individual plot data:

```r
table(pmx_pk$data$IND$CMT, useNA = "ifany")

table(pmx_pd$data$IND$CMT, useNA = "ifany")
```

Expected:

```text
pmx_pk: cp only
pmx_pd: pca only
```

For VPC simulation data:

```r
table(pmx_pk$data$sim$CMT, useNA = "ifany")

table(pmx_pd$data$sim$CMT, useNA = "ifany")
```

Expected:

```text
pmx_pk: cp only
pmx_pd: pca only
```

Check prediction scales:

```r
range(pmx_pk$data$IND$IPRED, na.rm = TRUE)

range(pmx_pd$data$IND$IPRED, na.rm = TRUE)
```

The PK range should be on the concentration scale, while the PD range should be on the effect scale.

## Why this matters

Without endpoint-aware filtering and merging, diagnostic plots can silently mix endpoints.

For individual plots, this can create misleading saw-tooth prediction lines because PK and PD values are connected in the same line.

For VPCs, this can create duplicated or inflated simulation datasets because simulation rows are merged to observed metadata using only `ID` and `TIME`.

The patch reduces these risks by making endpoint handling explicit in both plot preparation and VPC simulation processing.

## Limitations

This is a prototype patch.

It modifies functions in the active R session using `assignInNamespace()`.

It does not permanently change the installed `ggPMX` package.

The patch should be validated for each modeling workflow before use in formal reporting.

## Uninstalling the patch in the current session

If needed, restore the original functions:

```r
ggpmx_uninstall_pkpd_patch()
```

Restarting R also restores the original `ggPMX` behavior.

