# Database-derived counts quoted in index.qmd and appendix.qmd, recomputed from
# the data files so that a change to the database can be traced to every
# number it moves. manuscript_counts(dir) reads studies/arms/outcomes/rob/
# cohorts from `dir` and the pooled flags from an appendix S4 reference table.
# Formulas follow notebooks/study-characteristics.qmd and
# scripts/run-stageC-tables.R.

library(dplyr)
library(readr)
library(tidyr)
library(stringr)
library(purrr)

manuscript_counts <- function(dir = "data", s4_file = "appendix-s4-references.md") {
  rd <- function(f) read_csv(file.path(dir, f), show_col_types = FALSE, guess_max = 10000, progress = FALSE)
  studies <- rd("studies.csv")
  arms <- rd("arms.csv")
  outcomes <- rd("outcomes.csv")
  rob <- rd("rob.csv")
  cohorts <- rd("cohorts.csv")

  as_num <- function(x) {
    if (is.numeric(x)) return(x)
    suppressWarnings(as.numeric(sub("^[^0-9.-]*(-?[0-9.]+).*$", "\\1", x)))
  }
  val <- function(x) !is.na(suppressWarnings(as.numeric(x)))
  pct <- function(n, d) sprintf("%d (%d%%)", n, round(100 * n / d))
  med_iqr <- function(x, d = 1) {
    x <- as_num(x)
    x <- x[!is.na(x)]
    q <- quantile(x, c(.25, .5, .75))
    sprintf("%.*f (%.*f-%.*f)", d, q[2], d, q[1], d, q[3])
  }
  out <- list()
  add <- function(name, value) out[[name]] <<- as.character(value)

  single_ids <- studies$study_id[studies$study_design == "single_arm_descriptive_excluded"]
  comparative <- filter(studies, !study_id %in% single_ids)
  comp_arms <- filter(arms, !study_id %in% single_ids)
  n_comp <- nrow(comparative)

  add("Studies included", nrow(studies))
  add("Comparative studies", n_comp)
  add("Single-arm descriptive studies", length(single_ids))
  add("Arms, all studies", nrow(arms))
  add("Arms, comparative studies", nrow(comp_arms))
  add("PTCy arms, comparative studies", sum(comp_arms$arm_role == "PTCy_arm"))
  add("Comparator arms, comparative studies", sum(comp_arms$arm_role == "comparator_arm"))
  add("Patients, all studies", sum(arms$n_patients, na.rm = TRUE))
  add("Patients, comparative studies", sum(comp_arms$n_patients, na.rm = TRUE))
  add("Unique patients after cohort deduplication",
      sum(as.numeric(cohorts$total_unique_patients[cohorts$cohort_id %in% studies$cohort_id]), na.rm = TRUE))

  design <- count(comparative, study_design)
  for (d in c("RCT", "retrospective_cohort", "registry", "prospective_cohort")) {
    add(str_c("Design: ", d), pct(design$n[design$study_design == d], n_comp))
  }
  add("Publication year, median (IQR)", med_iqr(comparative$pub_year, 0))
  add("Follow-up months, median (IQR)", med_iqr(comparative$follow_up_median_months, 0))

  # Risk of bias, comparative observational studies (ROBINS-I)
  robins <- rob |>
    left_join(select(studies, study_id, study_design), by = "study_id") |>
    filter(!study_design %in% c("RCT", "single_arm_descriptive_excluded"))
  n_robins <- n_distinct(robins$study_id)
  add("ROBINS-I studies assessed", n_robins)
  for (j in c("serious", "moderate")) {
    add(str_c("ROBINS-I overall ", j), pct(sum(robins$overall_judgement == j, na.rm = TRUE), n_robins))
  }
  domains <- robins |>
    pivot_longer(d1:d7, names_to = "domain", values_to = "judgement") |>
    count(domain, judgement)
  for (dm in str_c("d", 1:7)) {
    g <- function(j) sum(domains$n[domains$domain == dm & domains$judgement %in% j])
    add(str_c("ROBINS-I ", toupper(dm), " low / moderate / serious"),
        str_c(g("low"), " / ", g("moderate"), " / ", g("serious")))
  }
  add("ROBINS-I D6 or D7 not recorded", sum(is.na(robins$d6) | is.na(robins$d7)))

  # Table 1 arm-level rows (comparative studies)
  by_role <- function(f) {
    p <- f(filter(comp_arms, arm_role == "PTCy_arm"))
    c <- f(filter(comp_arms, arm_role == "comparator_arm"))
    str_c(p, " | ", c)
  }
  num_rows <- c("Patients per arm" = "n_patients", "Age, years" = "age_median_years", "Male, %" = "pct_male",
                "CMV R+, %" = "cmv_recipient_pos_pct", "Steroid exposure, %" = "systemic_steroid_for_gvhd_exposure_pct")
  for (nm in names(num_rows)) {
    add(str_c("Table 1 ", nm, " (PTCy | comparator)"),
        by_role(\(a) med_iqr(a[[num_rows[[nm]]]], if (nm == "Patients per arm") 0 else 1)))
  }
  cat_row <- function(col, levels, label) {
    by_role(\(a) {
      n <- sum(a[[col]] %in% levels)
      pct(n, nrow(a))
    }) |> add(name = label)
  }
  all_levels <- function(col, named) setdiff(unique(comp_arms[[col]]), named)
  cat_row("donor_predominant", "haplo", "Table 1 Donor haploidentical (PTCy | comparator)")
  cat_row("donor_predominant", "MUD", "Table 1 Donor MUD (PTCy | comparator)")
  cat_row("donor_predominant", "MMUD", "Table 1 Donor MMUD (PTCy | comparator)")
  cat_row("donor_predominant", "MSD", "Table 1 Donor MSD (PTCy | comparator)")
  cat_row("donor_predominant", all_levels("donor_predominant", c("haplo", "MUD", "MMUD", "MSD")),
          "Table 1 Donor mixed/other/NR (PTCy | comparator)")
  cat_row("graft_predominant", "PBSC", "Table 1 Graft PBSC (PTCy | comparator)")
  cat_row("graft_predominant", "BM", "Table 1 Graft BM (PTCy | comparator)")
  cat_row("graft_predominant", "UCB", "Table 1 Graft UCB (PTCy | comparator)")
  cat_row("graft_predominant", all_levels("graft_predominant", c("PBSC", "BM", "UCB")),
          "Table 1 Graft mixed/NR (PTCy | comparator)")
  cat_row("conditioning_predominant", "RIC", "Table 1 Conditioning RIC (PTCy | comparator)")
  cat_row("conditioning_predominant", "MAC", "Table 1 Conditioning MAC (PTCy | comparator)")
  cat_row("conditioning_predominant", "NMA", "Table 1 Conditioning NMA (PTCy | comparator)")
  cat_row("conditioning_predominant", all_levels("conditioning_predominant", c("RIC", "MAC", "NMA")),
          "Table 1 Conditioning mixed/NR (PTCy | comparator)")

  # Pooled studies, from the meta-analysis column of appendix S4
  s4 <- read_delim(s4_file, delim = "|", skip = 2, col_names = c("x", "study_id", "reference", "ma", "y"),
                   col_types = "ccccc", trim_ws = TRUE)
  flagged <- filter(s4, ma != "—")
  add("S4 reference rows", nrow(s4))
  add("Studies pooled (any comparison)", nrow(flagged))
  add("Studies descriptive only", nrow(s4) - nrow(flagged))
  for (cmp in c("C1", "C2", "C3")) add(str_c("Studies pooled in ", cmp), sum(str_detect(flagged$ma, cmp)))
  add("Studies pooled in more than one comparison", sum(str_detect(flagged$ma, ",")))

  # Studies with paired-arm records per outcome (scripts/run-stageC-tables.R, section 4)
  arm_info <- select(arms, arm_id, arm_role, matches("^comparison_\\d_eligible$"))
  occ <- outcomes |>
    filter(val(event_count) | val(cumulative_incidence_pct) | val(proportion_reported_pct) | val(hr_value)) |>
    left_join(arm_info, by = "arm_id")
  flow_map <- tribble(
    ~outcome, ~cat, ~sub, ~comps,
    "Overall survival", "overall_mortality", "OS_event", 1:3,
    "Non-relapse mortality", "NRM", "NRM_overall", 1:3,
    "Relapse-related mortality", "relapse_related_mortality", "RRM_any_cause_relapse", 1:3,
    "Acute GVHD II-IV", "aGVHD", "grade_II_IV", 1:3,
    "Chronic GVHD mod-severe", "cGVHD", "moderate_severe_NIH", 1:3,
    "Chronic GVHD any", "cGVHD", "any_NIH", 1L,
    "CMV reactivation", "CMV", "any_reactivation", 1:2,
    "Bloodstream infection", "BSI", "any_pathogen", 1L,
    "Invasive fungal infection", "IFI_any", "EORTC_MSG_proven_probable_combined", 1L,
    "BK haemorrhagic cystitis", "other_infection", "BK_hemorrhagic_cystitis", 1:2,
    "Infection-related mortality", "infection_related_mortality", "IRM_any_cause_infectious", 1:2
  )
  for (i in seq_len(nrow(flow_map))) {
    dd <- filter(occ, outcome_category == flow_map$cat[i], outcome_subtype == flow_map$sub[i])
    ptcy_st <- unique(dd$study_id[dd$arm_role == "PTCy_arm"])
    for (cmp in flow_map$comps[[i]]) {
      el <- str_c("comparison_", cmp, "_eligible")
      comp_st <- unique(dd$study_id[dd$arm_role == "comparator_arm" & dd[[el]] == "Y"])
      add(str_c("Paired-arm records, C", cmp, " ", flow_map$outcome[i]), length(intersect(ptcy_st, comp_st)))
    }
  }

  # Other database-wide counts quoted in appendix S9
  ptcy_atg <- filter(arms, ptcy_used == "Y", atg_used == "Y")
  add("PTCy+ATG arms, database-wide", nrow(ptcy_atg))
  add("PTCy+ATG arms, C1 / C2 / C3 eligible",
      str_c(sum(ptcy_atg$comparison_1_eligible == "Y"), " / ", sum(ptcy_atg$comparison_2_eligible == "Y"), " / ",
            sum(ptcy_atg$comparison_3_eligible == "Y")))
  add("Arms with recorded letermovir use", sum(arms$letermovir_use %in% c("all_patients", "select_high_risk")))
  avail <- function(col) sprintf("%d of %d (%d%%)", sum(val(arms[[col]])), nrow(arms), round(100 * mean(val(arms[[col]]))))
  add("Arms with haploidentical-donor percentage", avail("donor_haplo_pct"))
  add("Arms with MAC percentage", avail("conditioning_mac_pct"))
  add("Arms with PBSC percentage", avail("graft_pbsc_pct"))
  add("Arms with steroid exposure", avail("systemic_steroid_for_gvhd_exposure_pct"))
  add("Arms without steroid exposure",
      sprintf("%d of %d (%d%%)", sum(!val(arms$systemic_steroid_for_gvhd_exposure_pct)), nrow(arms),
              round(100 * mean(!val(arms$systemic_steroid_for_gvhd_exposure_pct)))))
  add("Arms with high-risk disease percentage", avail("disease_risk_high_pct"))
  add("Arms with CMV recipient serostatus", avail("cmv_recipient_pos_pct"))
  add("Arms with CMV D+/R- serostatus", avail("cmv_DposRneg_pct"))

  tibble(quantity = names(out), value = unlist(out))
}
