# Extraction audit remediation (2026-10-02):
# 1. Add explicit `input_class` provenance column to data/outcomes.csv
# 2. Regenerate data/analytic/C*.csv with NA event counts where the source
#    reports only a cumulative incidence (removes CIF-derived pseudo-counts)
#
# Run from project root: source("scripts/add-input-class-and-clean-analytic.R")

library(tidyverse)

nr  <- function(x) is.na(x) | x %in% c("NR", "", "NA")
has <- function(x) !nr(x)

## ------------------------------------------------------------------
## 1. input_class for outcomes.csv
## ------------------------------------------------------------------

out <- read_csv("data/outcomes.csv", show_col_types = FALSE,
                col_types = cols(.default = col_character()))

num <- function(x) suppressWarnings(parse_number(x))

out_classed <- out |>
  mutate(
    .denom = num(denominator_n),
    .events = num(event_count),
    .cif_implied = num(cumulative_incidence_pct) / 100 * .denom,
    .prop_implied = num(proportion_reported_pct) / 100 * .denom,
    .tol = pmax(0.6, 0.01 * .denom),
    .matches_cif = !is.na(.cif_implied) & abs(.events - .cif_implied) <= .tol,
    .matches_prop = !is.na(.prop_implied) & abs(.events - .prop_implied) <= .tol,
    .from_km = data_source == "figure_KM_curve",
    input_class = case_when(
      # No event count: classify the bare quantity that was extracted
      nr(event_count) & .from_km                       ~ "kaplan_meier_derived",
      nr(event_count) & has(hr_value) & nr(cumulative_incidence_pct) & nr(proportion_reported_pct) ~ "hr_only",
      nr(event_count) & has(cumulative_incidence_pct)  ~ "cumulative_incidence_only",
      nr(event_count) & has(proportion_reported_pct)   ~ "percentage_only",
      nr(event_count) & has(incidence_rate_value)      ~ "incidence_rate_only",
      nr(event_count)                                  ~ "no_numeric_data",
      # Event count present, directly observed
      data_quality_flag == "direct" & !.from_km        ~ "observed_count",
      # Event count present, reconstructed: classify the reconstruction path
      .from_km                                         ~ "kaplan_meier_derived_count",
      .matches_cif & !.matches_prop                    ~ "cumulative_incidence_derived_count",
      .matches_prop                                    ~ "percentage_derived_count",
      TRUE                                             ~ "other_reconstruction"
    )
  ) |>
  select(-starts_with("."))

stopifnot(nrow(out_classed) == nrow(out))
write_csv(out_classed, "data/outcomes.csv")

message("input_class distribution:")
print(count(out_classed, input_class, sort = TRUE))

## ------------------------------------------------------------------
## 2. Remove CIF-derived pseudo-counts from analytic datasets
## ------------------------------------------------------------------

# Source lookup: does an extracted event count exist for this arm/outcome/timepoint?
lookup <- out_classed |>
  distinct(study_id, arm_id, outcome_category, outcome_subtype, timepoint,
           .keep_all = TRUE) |>
  transmute(study_id = as.numeric(study_id), arm_id, outcome_category,
            outcome_subtype, timepoint, src_event = event_count)

analytic_files <- list.files("data/analytic", pattern = "^C\\d_.*\\.csv$",
                             full.names = TRUE)

clean_one <- function(f) {
  d <- read_csv(f, show_col_types = FALSE)
  if (!all(c("ptcy_arm_id", "comp_arm_id") %in% names(d))) {
    message("SKIP (no arm id columns): ", basename(f))
    return(invisible(NULL))
  }
  d <- d |> mutate(across(c(ptcy_arm_id, comp_arm_id), as.character))

  p <- d |> left_join(lookup, by = c("study_id",
      "ptcy_arm_id" = "arm_id", "category" = "outcome_category",
      "subtype" = "outcome_subtype", "timepoint_used" = "timepoint"))
  c <- d |> left_join(lookup, by = c("study_id",
      "comp_arm_id" = "arm_id", "category" = "outcome_category",
      "subtype" = "outcome_subtype", "timepoint_used" = "timepoint"))

  n_ptcy <- sum(!is.na(d$ptcy_e) & nr(p$src_event))
  n_comp <- sum(!is.na(d$comp_e) & nr(c$src_event))

  # Where the extraction database has no event count, any analytic count is a
  # reconstruction (verified 2026-10-02: 100% were round(CIF/100 * N)) -> NA
  d$ptcy_e[!is.na(d$ptcy_e) & nr(p$src_event)] <- NA_real_
  d$comp_e[!is.na(d$comp_e) & nr(c$src_event)] <- NA_real_

  write_csv(d, f)
  message(sprintf("%-55s nulled ptcy_e: %3d  comp_e: %3d", basename(f), n_ptcy, n_comp))
}

invisible(map(analytic_files, clean_one))
