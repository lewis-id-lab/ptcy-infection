# Re-extraction worklists for checking against source papers (DECISIONS.md,
# 2026-11-10). Built from stored fields only.
#   1. randomised trials without a usable ("matched") hazard ratio for overall
#      survival or non-relapse mortality;
#   2. C1-eligible comparator arms with ATG recorded as used or mixed.
# Run from project root: source("scripts/reextraction-worklist.R")

library(dplyr)
library(readr)
library(tidyr)
library(stringr)

num <- function(x) suppressWarnings(as.numeric(x))
collapse_unique <- function(x) str_c(unique(x[!is.na(x)]), collapse = "; ")

studies <- read_csv("data/studies.csv", show_col_types = FALSE, guess_max = 5000)
arms <- read_csv("data/arms.csv", show_col_types = FALSE, guess_max = 5000)
outcomes <- read_csv("data/outcomes.csv", show_col_types = FALSE, guess_max = 5000)

# 1. Trials -------------------------------------------------------------------
# "matched": numeric HR with both bounds and a stated reference arm in the same
# study; "unmatched": numeric HR with bounds but no usable reference arm
hr_status <- outcomes |>
  filter((outcome_category == "overall_mortality" & outcome_subtype == "OS_event") |
           (outcome_category == "NRM" & outcome_subtype == "NRM_overall")) |>
  mutate(
    outcome = if_else(outcome_category == "NRM", "nrm", "os"),
    has_hr = !is.na(num(hr_value)) & !is.na(num(hr_ci_lower)) & !is.na(num(hr_ci_upper)),
    has_ref = num(hr_comparator_arm_id) %in% arms$arm_id & num(hr_comparator_arm_id) != arm_id
  ) |>
  summarise(
    hr = case_when(any(has_hr & has_ref) ~ "matched", any(has_hr) ~ "unmatched", .default = "none"),
    other_data = collapse_unique(input_class),
    .by = c(study_id, outcome)
  ) |>
  pivot_wider(names_from = outcome, values_from = c(hr, other_data), names_glue = "{outcome}_{.value}")

trial_arms <- arms |>
  summarise(
    arms = str_c(str_c(arm_label_in_paper, " (n=", n_patients, ")"), collapse = " | "),
    c1 = any(comparison_1_eligible == "Y"), c2 = any(comparison_2_eligible == "Y"),
    c3 = any(comparison_3_eligible == "Y"),
    .by = study_id
  ) |>
  mutate(eligible_for = pmap_chr(list(c1, c2, c3), \(a, b, c) str_c(c("C1", "C2", "C3")[c(a, b, c)], collapse = ", ")))

trials_worklist <- studies |>
  filter(study_design == "RCT") |>
  left_join(hr_status, by = "study_id") |>
  left_join(select(trial_arms, study_id, eligible_for, arms), by = "study_id") |>
  mutate(across(c(os_hr, nrm_hr), \(x) coalesce(x, "no outcome row"))) |>
  filter(os_hr != "matched" | nrm_hr != "matched") |>
  transmute(
    study_id, first_author, pub_year, journal, doi, title, eligible_for, arms,
    os_hr, os_other_data, nrm_hr, nrm_other_data, cohort_id, primary_for_cohort,
    # to be completed against the paper
    os_hr_found = NA, os_hr_ci = NA, os_hr_reference_arm = NA, os_hr_adjusted = NA,
    nrm_hr_found = NA, nrm_hr_ci = NA, nrm_hr_type = NA, checked_by = NA, notes = NA
  ) |>
  arrange(first_author, pub_year)

# 2. C1 comparator arms with ATG ---------------------------------------------
pooled_c1 <- read_csv("audit/pooled_studies_audit_2026-11-10.csv", show_col_types = FALSE) |>
  filter(comparison == 1) |>
  pull(study_id)

atg_worklist <- arms |>
  filter(comparison_1_eligible == "Y", arm_role == "comparator_arm", atg_used %in% c("Y", "mixed")) |>
  left_join(select(studies, study_id, first_author, pub_year, journal, doi, title, study_design), by = "study_id") |>
  transmute(
    study_id, first_author, pub_year, journal, doi, study_design,
    pooled_in_c1 = study_id %in% pooled_c1,
    arm_id, arm_label_in_paper, n_patients, donor_predominant,
    atg_used, atg_agent, atg_total_dose_mg_kg, atg_timing,
    cni_used, mtx_used, mmf_used, ptcy_used,
    also_c2_eligible = comparison_2_eligible,
    title,
    # to be completed against the paper
    atg_confirmed = NA, atg_pct_of_arm = NA, correct_comparison = NA, checked_by = NA, notes = NA
  ) |>
  arrange(desc(pooled_in_c1), first_author, pub_year, arm_id)

dir.create("audit", showWarnings = FALSE)
write_csv(trials_worklist, "audit/worklist_trials_without_hr_2026-11-10.csv", na = "")
write_csv(atg_worklist, "audit/worklist_c1_comparator_atg_2026-11-10.csv", na = "")
