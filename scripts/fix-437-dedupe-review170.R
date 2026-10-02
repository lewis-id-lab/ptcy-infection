# Extraction audit remediation, round 2 (2026-10-02):
# 1. Study 437 RRM: proportion_reported_pct held share-of-deaths, not in-arm %
# 2. Remove near-duplicate outcomes.csv rows (re-extraction artifacts)
# 3. Structured review of 170 CIF-consistent counts (source PDFs unavailable):
#    reclassify provenance where notes admit derivation; flag ambiguous rows
#
# Run from project root: source("scripts/fix-437-dedupe-review170.R")

library(tidyverse)

nr  <- function(x) is.na(x) | x %in% c("NR", "", "NA")
num <- function(x) suppressWarnings(parse_number(x))

out <- read_csv("data/outcomes.csv", show_col_types = FALSE,
                col_types = cols(.default = col_character()))
n0 <- nrow(out)

## ------------------------------------------------------------------
## 1. Study 437 RRM proportions: share of deaths -> in-arm proportion
## ------------------------------------------------------------------
# outcome 3873: 2/16 = 12.5% (was 18.2 = 2/11 deaths)
# outcome 3876: 3/17 = 17.6% (was 42.9 = 3/7 deaths)
out <- out |>
  mutate(
    proportion_reported_pct = case_when(
      outcome_id == "3873" ~ "12.5",
      outcome_id == "3876" ~ "17.6",
      TRUE ~ proportion_reported_pct),
    input_class = case_when(
      outcome_id %in% c("3873", "3876") ~ "observed_count",
      TRUE ~ input_class),
    extraction_notes = case_when(
      outcome_id == "3873" ~ paste0(coalesce(extraction_notes, ""),
        " [Corrected 2026-10-02: proportion changed from 18.2% (share of deaths, 2/11) to in-arm 12.5% (2/16).]"),
      outcome_id == "3876" ~ paste0(coalesce(extraction_notes, ""),
        " [Corrected 2026-10-02: proportion changed from 42.9% (share of deaths, 3/7) to in-arm 17.6% (3/17).]"),
      TRUE ~ extraction_notes))

## ------------------------------------------------------------------
## 2. Remove near-duplicate rows (same arm/outcome/timepoint/values)
## ------------------------------------------------------------------
key_cols <- c("study_id", "arm_id", "outcome_category", "outcome_subtype",
              "timepoint", "denominator_n", "event_count",
              "cumulative_incidence_pct", "proportion_reported_pct")

dup_groups <- out |>
  mutate(.n_complete = rowSums(!is.na(pick(everything())) &
                                pick(everything()) != "NR")) |>
  group_by(across(all_of(key_cols))) |>
  filter(n() > 1) |>
  # Keep the most complete row; tie-break to the smaller outcome_id (original)
  arrange(desc(.n_complete), suppressWarnings(as.numeric(outcome_id)),
          .by_group = TRUE) |>
  mutate(.keep_row = row_number() == 1) |>
  ungroup()

drop_ids <- dup_groups |> filter(!.keep_row) |> pull(outcome_id)
message("Removing ", length(drop_ids), " near-duplicate rows across ",
        dup_groups |> filter(!.keep_row) |> distinct(across(all_of(key_cols))) |> nrow(),
        " duplicate groups")
out <- out |> filter(!outcome_id %in% drop_ids)

## ------------------------------------------------------------------
## 3. Review the 170 CIF-consistent counts
## ------------------------------------------------------------------
out <- out |>
  mutate(
    .denom = num(denominator_n), .ev = num(event_count),
    .cif_imp = num(cumulative_incidence_pct) / 100 * .denom,
    .prop_imp = num(proportion_reported_pct) / 100 * .denom,
    .tol = pmax(0.6, 0.01 * .denom),
    .cif_consistent = !is.na(.ev) & !is.na(.cif_imp) &
      abs(.ev - .cif_imp) <= .tol &
      (is.na(.prop_imp) | abs(.ev - .prop_imp) > .tol),
    .notes = coalesce(extraction_notes, ""),
    .admits_derivation = str_detect(.notes,
      regex("derived|computed|calculated|rounded|back.?calcul|\\d+(\\.\\d+)?% ?[x×] ?\\d+|\\d+ ?[x×] ?0?\\.", ignore_case = TRUE)),
    .explicit_count = str_detect(.notes,
      regex("\\d+ ?/ ?\\d+|n \\(%\\)|\\d+ patients|reported (as )?\\d+", ignore_case = TRUE)),
    input_class = case_when(
      .cif_consistent & .admits_derivation & ci_method == "Kaplan_Meier" ~ "kaplan_meier_derived_count",
      .cif_consistent & .admits_derivation ~ "cumulative_incidence_derived_count",
      .cif_consistent & !.explicit_count ~ "uncertain_count_provenance",
      TRUE ~ input_class),
    data_quality_flag = case_when(
      .cif_consistent & .admits_derivation ~ "derived",
      TRUE ~ data_quality_flag),
    extraction_notes = case_when(
      .cif_consistent & .admits_derivation ~ paste0(.notes,
        " [Reclassified 2026-10-02: count is CIF-derived, not an observed count; treat as reconstructed in any pooling.]"),
      .cif_consistent & !.explicit_count ~ paste0(.notes,
        " [FLAGGED 2026-10-02: count matches CIF x N but notes neither document a reported count nor admit derivation; verify against source PDF before pooling.]"),
      TRUE ~ extraction_notes)
  ) |>
  select(-starts_with("."))

stopifnot(nrow(out) == n0 - length(drop_ids))
write_csv(out, "data/outcomes.csv")

message("\nFinal input_class distribution:")
print(count(out, input_class, sort = TRUE))
message("\nRows removed: ", length(drop_ids), "; final n = ", nrow(out))