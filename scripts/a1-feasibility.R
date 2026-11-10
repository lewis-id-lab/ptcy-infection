# A1 feasibility count: for each outcome and comparison, how many studies could
# enter a model from hazard ratios or cumulative-incidence estimates, against
# the current observed-count models. Counts only; no model is fitted.
# Based on stored fields in data/outcomes.csv; nothing was checked against
# source papers, so these are upper bounds.
# Run from project root: source("scripts/a1-feasibility.R")

library(dplyr)
library(readr)
library(tidyr)
library(stringr)

num <- function(x) suppressWarnings(as.numeric(x))

studies <- read_csv("data/studies.csv", show_col_types = FALSE, guess_max = 5000)
arms <- read_csv("data/arms.csv", show_col_types = FALSE, guess_max = 5000)
outcomes <- read_csv("data/outcomes.csv", show_col_types = FALSE, guess_max = 5000)

outcome_defs <- tribble(
  ~outcome,                        ~outcome_category,             ~outcome_subtype,                     ~flow_label,
  "Overall survival",              "overall_mortality",           "OS_event",                           "Overall survival",
  "Non-relapse mortality",         "NRM",                         "NRM_overall",                        "Non-relapse mortality",
  "Relapse-related mortality",     "relapse_related_mortality",   "RRM_any_cause_relapse",              "Relapse-related mortality",
  "Acute GVHD II-IV",              "aGVHD",                       "grade_II_IV",                        "Acute GVHD II–IV",
  "Chronic GVHD mod-severe",       "cGVHD",                       "moderate_severe_NIH",                "Chronic GVHD mod–severe",
  "CMV reactivation",              "CMV",                         "any_reactivation",                   "CMV reactivation",
  "Bloodstream infection",         "BSI",                         "any_pathogen",                       "Bloodstream infection",
  "Invasive fungal infection",     "IFI_any",                     "EORTC_MSG_proven_probable_combined", "Invasive fungal infection",
  "BK haemorrhagic cystitis",      "other_infection",             "BK_hemorrhagic_cystitis",            "BK virus",
  "Infection-related mortality",   "infection_related_mortality", "IRM_any_cause_infectious",           "Infection-related mortality"
)

eligible_arms <- arms |>
  select(study_id, arm_id, arm_role, matches("^comparison_\\d_eligible$")) |>
  pivot_longer(matches("^comparison_"), names_to = "comparison", values_to = "eligible") |>
  filter(eligible == "Y") |>
  transmute(study_id, arm_id, comparison = str_c("C", str_extract(comparison, "\\d")),
            side = if_else(arm_role == "PTCy_arm", "ptcy", "comp"))

arm_rows <- outcomes |>
  inner_join(outcome_defs, by = c("outcome_category", "outcome_subtype")) |>
  inner_join(eligible_arms, by = c("study_id", "arm_id"), relationship = "many-to-many") |>
  mutate(
    has_count = input_class == "observed_count" & !is.na(num(event_count)) & !is.na(num(denominator_n)),
    has_cif = !is.na(num(cumulative_incidence_pct)),
    has_cif_interval = has_cif & !is.na(num(ci_lower_pct)) & !is.na(num(ci_upper_pct)),
    has_hr = !is.na(num(hr_value)) & !is.na(num(hr_ci_lower)) & !is.na(num(hr_ci_upper))
  )

# A hazard ratio is "matched" when its stated reference arm is an eligible arm
# on the other side of the same comparison
hr_matched <- arm_rows |>
  filter(has_hr) |>
  mutate(ref_arm = num(hr_comparator_arm_id)) |>
  inner_join(rename(eligible_arms, ref_arm = arm_id, ref_side = side),
             by = c("study_id", "comparison", "ref_arm")) |>
  filter(ref_side != side) |>
  distinct(study_id, comparison, outcome)

# Both sides must report at the same timepoint for an arm-based contrast
both_sides <- function(flag) {
  arm_rows |>
    filter({{ flag }}) |>
    distinct(study_id, comparison, outcome, timepoint, side) |>
    summarise(sides = n_distinct(side), .by = c(study_id, comparison, outcome, timepoint)) |>
    filter(sides == 2) |>
    distinct(study_id, comparison, outcome)
}

per_study <- both_sides(TRUE) |>
  mutate(extracted = TRUE) |>
  full_join(mutate(both_sides(has_count), counts = TRUE), by = c("study_id", "comparison", "outcome")) |>
  full_join(mutate(both_sides(has_cif_interval), cif_interval = TRUE), by = c("study_id", "comparison", "outcome")) |>
  full_join(mutate(both_sides(has_cif), cif_point = TRUE), by = c("study_id", "comparison", "outcome")) |>
  full_join(mutate(distinct(filter(arm_rows, has_hr), study_id, comparison, outcome), hr_any = TRUE),
            by = c("study_id", "comparison", "outcome")) |>
  full_join(mutate(hr_matched, hr_matched = TRUE), by = c("study_id", "comparison", "outcome")) |>
  mutate(across(c(extracted, counts, cif_interval, cif_point, hr_any, hr_matched), \(x) coalesce(x, FALSE))) |>
  left_join(select(studies, study_id, study_design), by = "study_id") |>
  mutate(rct = study_design == "RCT")

flow <- read_csv("data/models/outcome_flow.csv", show_col_types = FALSE) |>
  select(comparison = comp, flow_label = outcome, k_pooled_now = k_pooled)

feasibility <- per_study |>
  summarise(
    k_any_data = n(),
    k_counts = sum(counts),
    k_hr_matched = sum(hr_matched),
    k_hr_any = sum(hr_any),
    k_cif_interval = sum(cif_interval),
    k_cif_point = sum(cif_point),
    k_hr_or_cif_interval = sum(hr_matched | cif_interval),
    k_any_route = sum(counts | hr_matched | cif_interval),
    rct_any_data = sum(rct),
    rct_counts = sum(rct & counts),
    rct_hr_matched = sum(rct & hr_matched),
    rct_cif_interval = sum(rct & cif_interval),
    rct_any_route = sum(rct & (counts | hr_matched | cif_interval)),
    .by = c(comparison, outcome)
  ) |>
  left_join(outcome_defs |> select(outcome, flow_label), by = "outcome") |>
  left_join(flow, by = c("comparison", "flow_label")) |>
  mutate(outcome = factor(outcome, levels = outcome_defs$outcome)) |>
  arrange(comparison, outcome) |>
  select(comparison, outcome, k_pooled_now, k_counts, k_hr_matched, k_hr_any, k_cif_interval, k_cif_point,
         k_hr_or_cif_interval, k_any_route, k_any_data, starts_with("rct_"))

dir.create("audit", showWarnings = FALSE)
write_csv(feasibility, "audit/a1_feasibility_2026-11-10.csv", na = "")
write_csv(per_study, "audit/a1_feasibility_per_study_2026-11-10.csv", na = "")
