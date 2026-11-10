# A6/A7 audit: one row per pooled study x comparison, with the stored regimen,
# ATG, donor, disease and duplicate fields, and automatic flags for breaches of
# the written C1/C2/C3 definitions. Flags come from stored fields only (no
# source papers were checked); every flag needs human adjudication.
# Run from project root: source("scripts/audit-pooled-studies.R")

library(dplyr)
library(readr)
library(purrr)
library(tidyr)
library(stringr)

num <- function(x) suppressWarnings(as.numeric(x))
collapse_unique <- function(x) str_c(unique(x[!is.na(x)]), collapse = "; ")

studies <- read_csv("data/studies.csv", show_col_types = FALSE, guess_max = 5000)
arms <- read_csv("data/arms.csv", show_col_types = FALSE, guess_max = 5000)

# The 105 pooled studies are defined by the meta-analysis column of appendix S4
pooled <- read_delim(
  "appendix-s4-references.md", delim = "|", skip = 2,
  col_names = c("x", "study_id", "reference", "ma", "y"),
  col_types = "ccccc", trim_ws = TRUE
) |>
  filter(ma != "—") |>
  transmute(study_id = as.integer(study_id), s4_flag = ma) |>
  separate_longer_delim(s4_flag, ", ") |>
  transmute(study_id, comparison = as.integer(str_remove(s4_flag, "C")))

# Arm pairs actually used in the repository's primary model input files
model_files <- list.files("data/models", pattern = "^data_c[123]_", full.names = TRUE) |>
  str_subset("_sens_", negate = TRUE)
model_rows <- map(model_files, \(f) {
  read_csv(f, show_col_types = FALSE) |>
    mutate(outcome = str_remove(str_remove(basename(f), "^data_c[123]_"), "\\.csv$"))
}) |>
  list_rbind() |>
  filter(!is.na(ptcy_e), !is.na(comp_e))

model_arms <- model_rows |>
  select(study_id, comparison, outcome, PTCy = ptcy_arm_id, comparator = comp_arm_id) |>
  pivot_longer(c(PTCy, comparator), names_to = "side", values_to = "arm_id") |>
  distinct(study_id, comparison, side, arm_id)

model_outcomes <- model_rows |>
  summarise(outcomes_in_repo_models = str_c(sort(unique(outcome)), collapse = ", "),
            .by = c(study_id, comparison))

# Where a study is not in the repository model files, fall back to all arms
# flagged eligible for that comparison
eligible_arms <- arms |>
  select(study_id, arm_id, arm_role, matches("^comparison_\\d_eligible$")) |>
  pivot_longer(matches("^comparison_"), names_to = "comparison", values_to = "eligible") |>
  filter(eligible == "Y") |>
  transmute(study_id, comparison = as.integer(str_extract(comparison, "\\d")),
            side = if_else(arm_role == "PTCy_arm", "PTCy", "comparator"), arm_id)

audit_arms <- pooled |>
  left_join(model_outcomes, by = c("study_id", "comparison")) |>
  mutate(arm_source = if_else(is.na(outcomes_in_repo_models), "eligibility flags", "model files")) |>
  left_join(
    bind_rows(mutate(model_arms, arm_source = "model files"),
              mutate(eligible_arms, arm_source = "eligibility flags")),
    by = c("study_id", "comparison", "arm_source"),
    relationship = "many-to-many"
  ) |>
  left_join(arms, by = c("study_id", "arm_id"))

regimen <- function(ptcy, atg, atg_agent, cni, mtx, mmf, siro, other) {
  part <- function(flag, label) case_when(flag == "Y" ~ label, flag == "mixed" ~ str_c(label, "(mixed)"), .default = NA)
  atg_label <- if_else(!is.na(atg_agent) & !atg_agent %in% c("NR", "NA"), str_c("ATG[", atg_agent, "]"), "ATG")
  pmap_chr(
    list(part(ptcy, "PTCy"), part(atg, atg_label), part(cni, "CNI"), part(mtx, "MTX"),
         part(mmf, "MMF"), part(siro, "sirolimus"),
         if_else(!is.na(other) & !other %in% c("NR", "NA", "N"), other, NA)),
    \(...) str_c(na.omit(c(...)), collapse = " + ")
  )
}

side_summary <- audit_arms |>
  mutate(
    regimen = regimen(ptcy_used, atg_used, atg_agent, cni_used, mtx_used, mmf_used,
                      sirolimus_used, other_immunosuppressant_description),
    ucb = donor_predominant == "UCB" | graft_predominant == "UCB" |
      coalesce(num(donor_ucb_pct) >= 50, FALSE) | coalesce(num(graft_ucb_pct) >= 50, FALSE)
  ) |>
  summarise(
    arm_ids = collapse_unique(arm_id),
    label = collapse_unique(arm_label_in_paper),
    n = sum(n_patients[!duplicated(arm_id)], na.rm = TRUE),
    regimen = collapse_unique(regimen),
    ptcy_used = collapse_unique(ptcy_used),
    atg_used = collapse_unique(atg_used),
    cni_used = collapse_unique(cni_used),
    donor = collapse_unique(donor_predominant),
    graft = collapse_unique(graft_predominant),
    cord_blood = any(ucb, na.rm = TRUE),
    saa_pct_max = suppressWarnings(max(num(disease_saa_pct), na.rm = TRUE)),
    age_median = collapse_unique(age_median_years),
    age_min = suppressWarnings(min(num(age_range_min), na.rm = TRUE)),
    age_max = suppressWarnings(max(num(age_range_max), na.rm = TRUE)),
    .by = c(study_id, comparison, arm_source, outcomes_in_repo_models, side)
  ) |>
  mutate(across(c(saa_pct_max, age_min, age_max), \(x) if_else(is.finite(x), x, NA)))

wide <- side_summary |>
  pivot_wider(
    id_cols = c(study_id, comparison, arm_source, outcomes_in_repo_models),
    names_from = side,
    values_from = c(arm_ids, label, n, regimen, ptcy_used, atg_used, cni_used, donor, graft,
                    cord_blood, saa_pct_max, age_median, age_min, age_max),
    names_glue = "{side}_{.value}"
  )

# Duplicate DOIs across the whole included set
dup_doi <- studies |>
  mutate(doi_key = str_to_lower(str_trim(doi))) |>
  filter(!is.na(doi_key), !doi_key %in% c("nr", "na", "")) |>
  mutate(n_same = n(), duplicate_doi_with = map_chr(study_id, \(id) str_c(setdiff(study_id, id), collapse = ", ")),
         .by = doi_key) |>
  filter(n_same > 1) |>
  select(study_id, duplicate_doi_with)

has <- function(x, values) str_detect(coalesce(x, ""), str_c("(^|; )(", str_c(values, collapse = "|"), ")($|; )"))
flag_if <- function(cond, text) if_else(coalesce(cond, FALSE), text, NA_character_)

audit <- wide |>
  left_join(select(studies, study_id, first_author, pub_year, journal, doi, title, study_design,
                   cohort_id, cohort_overlap_status, overlap_with_study_ids, primary_for_cohort),
            by = "study_id") |>
  left_join(dup_doi, by = "study_id") |>
  mutate(
    preprint = str_detect(coalesce(doi, ""), "^10\\.(21203|1101)/") |
      str_detect(str_to_lower(coalesce(journal, "")), "research square|medrxiv|biorxiv|preprint"),
    flags = pmap_chr(
      list(
        flag_if(comparison == 1 & has(PTCy_atg_used, c("Y", "mixed")), "C1: PTCy arm has ATG"),
        flag_if(comparison == 1 & has(comparator_atg_used, c("Y", "mixed")), "C1: comparator has ATG"),
        flag_if(comparison == 1 & has(comparator_cni_used, "N"), "C1: comparator without CNI"),
        flag_if(comparison %in% 1:2 & has(comparator_ptcy_used, c("Y", "mixed")), "comparator has PTCy"),
        flag_if(comparison == 2 & !has(comparator_atg_used, "Y"), "C2: comparator ATG not recorded as used"),
        flag_if(comparison == 2 & has(PTCy_atg_used, c("Y", "mixed")), "C2: PTCy arm also has ATG"),
        flag_if(comparison == 3 & has(comparator_ptcy_used, "N"), "C3: comparator has no PTCy"),
        flag_if(comparison == 3 & PTCy_regimen == comparator_regimen & PTCy_donor != comparator_donor,
                "C3: same regimen, donor differs (donor comparison?)"),
        flag_if(is.na(PTCy_arm_ids) | is.na(comparator_arm_ids), "arm pair not identifiable from stored flags"),
        flag_if(PTCy_cord_blood | comparator_cord_blood, "cord blood arm"),
        flag_if(pmax(PTCy_saa_pct_max, comparator_saa_pct_max, na.rm = TRUE) >= 50, "aplastic anaemia majority"),
        flag_if(pmax(PTCy_age_max, comparator_age_max, na.rm = TRUE) < 18 |
                  pmax(num(PTCy_age_median), num(comparator_age_median), na.rm = TRUE) < 18, "paediatric cohort"),
        flag_if(pmin(PTCy_age_min, comparator_age_min, na.rm = TRUE) < 18, "includes patients under 18"),
        flag_if(preprint, "preprint"),
        flag_if(!is.na(duplicate_doi_with), str_c("duplicate DOI with study ", duplicate_doi_with)),
        flag_if(!cohort_overlap_status %in% c("none", NA), str_c("cohort overlap: ", cohort_overlap_status)),
        flag_if(arm_source == "eligibility flags", "not in repository model files")
      ),
      \(...) str_c(na.omit(c(...)), collapse = " | ")
    ),
    definition_breach = str_detect(flags, "C1:|C2:|C3:|comparator has PTCy|cord blood|aplastic|paediatric cohort|preprint|duplicate DOI"),
    # to be completed by a human adjudicator against the source paper
    adjudicated_comparison = NA_character_,
    adjudication_decision = NA_character_,
    adjudicator_initials = NA_character_,
    adjudication_notes = NA_character_
  ) |>
  arrange(desc(definition_breach), comparison, first_author, pub_year) |>
  select(
    study_id, first_author, pub_year, study_design, comparison, definition_breach, flags,
    PTCy_label, PTCy_regimen, PTCy_atg_used, PTCy_donor, PTCy_graft, PTCy_n,
    comparator_label, comparator_regimen, comparator_atg_used, comparator_donor, comparator_graft, comparator_n,
    PTCy_saa_pct_max, comparator_saa_pct_max, PTCy_age_median, comparator_age_median, PTCy_age_min, comparator_age_min,
    outcomes_in_repo_models, arm_source, PTCy_arm_ids, comparator_arm_ids,
    doi, duplicate_doi_with, cohort_id, cohort_overlap_status, overlap_with_study_ids, primary_for_cohort,
    title, adjudicated_comparison, adjudication_decision, adjudicator_initials, adjudication_notes
  )

dir.create("audit", showWarnings = FALSE)
write_csv(audit, "audit/pooled_studies_audit_2026-11-10.csv", na = "")
