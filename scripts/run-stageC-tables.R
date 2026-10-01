# Stage C: regenerate all derived tables after removing duplicate study 401.
# Sources the corrected data files; overwrites the derived CSVs and prints the
# numbers needed for the manuscript text updates.

suppressPackageStartupMessages({
  library(tidyverse)
  library(brms)
})

# ── 1. Table2_setB.csv: update the c1_os rows from the new fits ────────────
t2 <- read_csv("data/models/Table2_setB.csv", show_col_types = FALSE)
upd <- function(t2, fit_file, model_label) {
  fit <- readRDS(fit_file)
  dr <- as_draws_df(fit)
  or <- exp(dr$b_ptcy_binary)
  long <- fit$data
  k <- n_distinct(long$study_id)
  n_total <- sum(long$denom_n)
  t2 |>
    mutate(across(c(k, n_total, or_median, ci_low, ci_high, tau),
                  \(x) as.numeric(x))) |>
    mutate(
      k = if_else(slug == "c1_os" & model == model_label, k, k),
      n_total = if_else(slug == "c1_os" & model == model_label, n_total, n_total),
      or_median = if_else(slug == "c1_os" & model == model_label, median(or), or_median),
      ci_low = if_else(slug == "c1_os" & model == model_label, quantile(or, .025), ci_low),
      ci_high = if_else(slug == "c1_os" & model == model_label, quantile(or, .975), ci_high),
      tau = if_else(slug == "c1_os" & model == model_label,
                    median(dr$sd_study_id__ptcy_binary), tau)
    )
}
t2 <- t2 |>
  upd("_fits_rs/rs_c1_os_m1.rds", "m1") |>
  upd("_fits_rs/rs_c1_os_m2.rds", "m2_steroid")
write_csv(t2, "data/models/Table2_setB.csv")

# ── 2. Prediction intervals (rewrites Table2_setB.csv with pi columns) ─────
source("scripts/export-prediction-intervals.R")

# ── 3. fe_sensitivity_setB.csv rebuild ──────────────────────────────────────
fe <- read_csv("_fits_rs/fe_summary.csv", show_col_types = FALSE)
t2 <- read_csv("data/models/Table2_setB.csv", show_col_types = FALSE)
keymap <- tribble(
  ~slug, ~model, ~key,
  "c1_os","m1","c1_os_m1", "c1_os","m2_steroid","c1_os_m2",
  "c1_rrm","m1","c1_rrm_m1", "c1_rrm","m2_steroid","c1_rrm_m2",
  "c1_irm","m1","c1_irm_m1", "c1_cgvhd_ms","m1","c1_cgvhd_m1",
  "c1_cgvhd_any","m1","c1_cgvhdany_m1", "c1_nrm","m1","c1_nrm_m1",
  "c1_nrm","m2_steroid","c1_nrm_m2", "c1_agvhd","m1","c1_agvhd_m1",
  "c1_cmv","m1","c1_cmv_m1", "c1_cmv","m2_steroid","c1_cmv_m2",
  "c1_bsi","m1","c1_bsi_m1", "c1_ifi_any","m1","c1_ifi_m1",
  "c1_bk","m1","c1_bk_m1", "c2_os","m1","c2_os_m1",
  "c2_os","m2_steroid","c2_os_m2", "c2_agvhd","m1","c2_agvhd_m1",
  "c2_cmv","m1","c2_cmv_m1", "c2_cmv","m2_steroid","c2_cmv_m2",
  "c2_rrm","m1","c2_rrm_m1", "c2_bk","m1","c2_bk_m1",
  "c2_irm","m1","c2_irm_m1", "c2_cgvhd_ms","m1","c2_cgvhd_m1",
  "c3_os","m1","c3_os_m1", "c3_agvhd","m1","c3_agvhd_m1",
  "c3_nrm","m1","c3_nrm_m1", "c3_rrm","m1","c3_rrm_m1",
  "c3_cgvhd","m1","c3_cgvhd_m1"
)
fe_out <- keymap |>
  left_join(t2 |> select(slug, model, or_median, ci_low, ci_high, tau),
            by = c("slug", "model")) |>
  left_join(fe |> select(key, k, or_med, or_lo, or_hi, tau_slope), by = "key") |>
  transmute(slug, model, key, k,
            reported_or = round(or_median, 3), reported_lo = round(ci_low, 3),
            reported_hi = round(ci_high, 3), reported_tau = round(tau, 3),
            fe_or = round(or_med, 3), fe_lo = round(or_lo, 3),
            fe_hi = round(or_hi, 3), fe_tau = round(tau_slope, 3),
            abs_log_or_shift = round(abs(log(or_med) - log(or_median)), 3))
write_csv(fe_out, "data/models/fe_sensitivity_setB.csv")

# ── 4. outcome_flow.csv ────────────────────────────────────────────────────
oc <- read_csv("data/outcomes.csv", show_col_types = FALSE)
arms <- read_csv("data/arms.csv", show_col_types = FALSE)
p9 <- path.expand("~/ptcy_metaanalys/03_models/post_block9")
val <- function(x) !is.na(suppressWarnings(as.numeric(x)))
arm_info <- arms |> select(arm_id, arm_role, comparison_1_eligible,
                           comparison_2_eligible, comparison_3_eligible)
occ <- oc |>
  mutate(has_val = val(event_count) | val(cumulative_incidence_pct) |
           val(proportion_reported_pct) | val(hr_value)) |>
  filter(has_val) |>
  left_join(arm_info, by = "arm_id")
comp_arm_ids <- list(
  comparison_1_eligible = arm_info |> filter(arm_role == "comparator_arm", comparison_1_eligible == "Y") |> pull(arm_id),
  comparison_2_eligible = arm_info |> filter(arm_role == "comparator_arm", comparison_2_eligible == "Y") |> pull(arm_id),
  comparison_3_eligible = arm_info |> filter(arm_role == "comparator_arm", comparison_3_eligible == "Y") |> pull(arm_id)
)
t2_map <- tribble(
  ~comp, ~outcome, ~cat, ~sub, ~elig,
  "C1","Overall survival","overall_mortality","OS_event","comparison_1_eligible",
  "C1","Non-relapse mortality","NRM","NRM_overall","comparison_1_eligible",
  "C1","Relapse-related mortality","relapse_related_mortality","RRM_any_cause_relapse","comparison_1_eligible",
  "C1","Acute GVHD II–IV","aGVHD","grade_II_IV","comparison_1_eligible",
  "C1","Chronic GVHD mod–severe","cGVHD","moderate_severe_NIH","comparison_1_eligible",
  "C1","Chronic GVHD any","cGVHD","any_NIH","comparison_1_eligible",
  "C1","CMV reactivation","CMV","any_reactivation","comparison_1_eligible",
  "C1","Bloodstream infection","BSI","any_pathogen","comparison_1_eligible",
  "C1","Invasive fungal infection","IFI_any","EORTC_MSG_proven_probable_combined","comparison_1_eligible",
  "C1","BK virus","other_infection","BK_hemorrhagic_cystitis","comparison_1_eligible",
  "C1","Infection-related mortality","infection_related_mortality","IRM_any_cause_infectious","comparison_1_eligible",
  "C2","Overall survival","overall_mortality","OS_event","comparison_2_eligible",
  "C2","Non-relapse mortality","NRM","NRM_overall","comparison_2_eligible",
  "C2","Relapse-related mortality","relapse_related_mortality","RRM_any_cause_relapse","comparison_2_eligible",
  "C2","Acute GVHD II–IV","aGVHD","grade_II_IV","comparison_2_eligible",
  "C2","Chronic GVHD mod–severe","cGVHD","moderate_severe_NIH","comparison_2_eligible",
  "C2","CMV reactivation","CMV","any_reactivation","comparison_2_eligible",
  "C2","BK virus","other_infection","BK_hemorrhagic_cystitis","comparison_2_eligible",
  "C2","Infection-related mortality","infection_related_mortality","IRM_any_cause_infectious","comparison_2_eligible",
  "C3","Overall survival","overall_mortality","OS_event","comparison_3_eligible",
  "C3","Non-relapse mortality","NRM","NRM_overall","comparison_3_eligible",
  "C3","Relapse-related mortality","relapse_related_mortality","RRM_any_cause_relapse","comparison_3_eligible",
  "C3","Acute GVHD II–IV","aGVHD","grade_II_IV","comparison_3_eligible",
  "C3","Chronic GVHD mod–severe","cGVHD","moderate_severe_NIH","comparison_3_eligible"
)
model_files <- c(
  paste0("data/models/data_", c("c1_os","c1_rrm","c1_irm","c1_cgvhd_ms","c2_os","c2_agvhd","c2_cmv"), ".csv"),
  file.path(p9, paste0("data_", c("c1_nrm","c1_agvhd","c1_cmv","c1_bsi","c1_ifi_any","c1_bk","c1_cgvhd_any",
                                  "c2_nrm","c2_rrm","c2_bk","c2_irm","c2_cgvhd_ms",
                                  "c3_os","c3_agvhd","c3_nrm","c3_rrm","c3_cgvhd"), ".csv")))
flowtbl <- t2_map |>
  mutate(k_extracted = pmap_int(list(cat, sub, elig), \(ct, sb, el) {
    dd <- occ |> filter(outcome_category == ct, outcome_subtype == sb)
    ptcy_st <- dd |> filter(arm_role == "PTCy_arm") |> pull(study_id) |> unique()
    comp_st <- dd |> filter(arm_id %in% comp_arm_ids[[el]]) |> pull(study_id) |> unique()
    length(intersect(ptcy_st, comp_st))
  })) |>
  select(comp, outcome, k_extracted)
pooled_keys <- t2_map |>
  mutate(key = paste0(tolower(comp), "_",
                      recode(outcome, "Overall survival" = "os", "Non-relapse mortality" = "nrm",
                             "Relapse-related mortality" = "rrm", "Acute GVHD II–IV" = "agvhd",
                             "Chronic GVHD mod–severe" = "cgvhd_ms", "Chronic GVHD any" = "cgvhd_any",
                             "CMV reactivation" = "cmv", "Bloodstream infection" = "bsi",
                             "Invasive fungal infection" = "ifi_any", "BK virus" = "bk",
                             "Infection-related mortality" = "irm")))
flowtbl <- flowtbl |>
  mutate(k_pooled = pmap_int(list(comp, outcome), \(cp, oc_) {
    k <- pooled_keys$key[pooled_keys$comp == cp & pooled_keys$outcome == oc_]
    f <- model_files[grepl(paste0("data_", k, ".csv"), model_files)]
    if (!length(f)) return(NA_integer_)
    n_distinct(read_csv(f, show_col_types = FALSE)$study_id)
  }))
write_csv(flowtbl, "data/models/outcome_flow.csv")

# ── 5. absolute_effects.csv ────────────────────────────────────────────────
base_risk <- function(f, arm = "comp") {
  d <- read_csv(f, show_col_types = FALSE)
  median(d[[paste0(arm, "_e")]] / d[[paste0(arm, "_n")]], na.rm = TRUE)
}
rd_calc <- function(or, p0) (or * p0 / (1 - p0 + or * p0) - p0) * 1000
sof <- tribble(
  ~outcome, ~comp, ~file, ~or_med, ~or_lo, ~or_hi,
  "Overall survival (mortality)", "C1", "data/models/data_c1_os.csv", 0.760, 0.613, 0.934,
  "Overall survival (mortality)", "C2", "data/models/data_c2_os.csv", 0.750, 0.418, 1.314,
  "Non-relapse mortality", "C1", file.path(p9, "data_c1_nrm.csv"), 0.810, 0.456, 1.219,
  "Acute GVHD II–IV", "C1", file.path(p9, "data_c1_agvhd.csv"), 0.583, 0.435, 0.768,
  "Acute GVHD II–IV", "C2", "data/models/data_c2_agvhd.csv", 0.509, 0.239, 1.021,
  "CMV reactivation", "C1", file.path(p9, "data_c1_cmv.csv"), 1.224, 0.901, 1.652,
  "CMV reactivation", "C2", "data/models/data_c2_cmv.csv", 0.861, 0.502, 1.417,
  "Bloodstream infection", "C1", file.path(p9, "data_c1_bsi.csv"), 1.424, 0.569, 2.980,
  "Invasive fungal infection", "C1", file.path(p9, "data_c1_ifi_any.csv"), 0.630, 0.190, 2.617
) |> mutate(p0 = map_dbl(file, base_risk),
            rd = rd_calc(or_med, p0), rd_lo = rd_calc(or_lo, p0), rd_hi = rd_calc(or_hi, p0))
write_csv(sof |> select(outcome, comp, p0, or_med, or_lo, or_hi, rd, rd_lo, rd_hi),
          "data/models/absolute_effects.csv")

# ── 6. Numbers needed for text updates ─────────────────────────────────────
studies <- read_csv("data/studies.csv", show_col_types = FALSE)
coh <- read_csv("data/cohorts.csv", show_col_types = FALSE)
rob <- read_csv("data/rob.csv", show_col_types = FALSE)
sa_ids <- studies |> filter(study_design == "single_arm_descriptive_excluded") |> pull(study_id)

cat("\n=== TEXT NUMBERS ===\n")
cat("studies total:", nrow(studies), "\n")
cat("comparative studies:", sum(studies$study_design != "single_arm_descriptive_excluded"), "\n")
arms2 <- arms |> mutate(n = suppressWarnings(as.numeric(n_patients)))
cat("arms total:", nrow(arms), "| comparative arms:", sum(!arms$study_id %in% sa_ids), "\n")
cat("patients total:", sum(arms2$n, na.rm = TRUE),
    "| comparative:", sum(arms2$n[!arms2$study_id %in% sa_ids], na.rm = TRUE), "\n")
coh_inc <- coh |> filter(cohort_id %in% studies$cohort_id)
cat("unique patients:", sum(as.numeric(coh_inc$total_unique_patients), na.rm = TRUE),
    "across", nrow(coh_inc), "cohorts\n")

mi_sets <- list(
  C1 = model_files[grepl("c1_", model_files)] |> map(\(f) read_csv(f, show_col_types = FALSE)$study_id) |> unlist() |> unique(),
  C2 = model_files[grepl("c2_", model_files)] |> map(\(f) read_csv(f, show_col_types = FALSE)$study_id) |> unlist() |> unique(),
  C3 = model_files[grepl("c3_", model_files)] |> map(\(f) read_csv(f, show_col_types = FALSE)$study_id) |> unlist() |> unique()
)
cat("model-input unions: C1", length(mi_sets$C1), "C2", length(mi_sets$C2),
    "C3", length(mi_sets$C3), "unique", length(unique(unlist(mi_sets))),
    "multi", sum(sapply(unique(unlist(mi_sets)), \(id) sum(sapply(mi_sets, \(s) id %in% s))) >= 2), "\n")

rob211 <- rob |>
  left_join(studies |> select(study_id, study_design), by = "study_id") |>
  filter(!study_design %in% c("RCT", "single_arm_descriptive_excluded"))
cat("ROBINS-I comparative observational:", n_distinct(rob211$study_id), "\n")
print(rob211 |> count(overall_judgement))
print(rob211 |>
        tidyr::pivot_longer(d1:d7, names_to = "domain", values_to = "judgement") |>
        count(domain, judgement = coalesce(judgement, "not recorded")) |>
        tidyr::pivot_wider(names_from = judgement, values_from = n, values_fill = 0))
cat("design counts:\n"); print(studies |> count(study_design))
cat("done\n")
