# Regenerate the appendix S8 forest-plot series with the standard layout
# (events/N per arm + REML inverse-variance weights beside each study row).
#
# S8a panels are the frequentist REML concordance checks (REML pooled row,
# from data/models/freq_results_setB.csv); S8b-S8i carry the Bayesian M1
# pooled row from table 2; S8j is the four-panel comparison-3 summary with
# REML pooled rows, matching its previous role.
#
# Overwrites figures/FigureS8{a-j}_*.{png,pdf,svg}.

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(patchwork)
})

source("scripts/forest-lib.R")

freq <- read_csv("data/models/freq_results_setB.csv", show_col_types = FALSE)
reml_spec <- function(slug) {
  r <- freq |> filter(slug == !!slug)
  stopifnot(nrow(r) == 1)
  list(label = "REML pooled", or = r$freq_or, lo = r$freq_lo, hi = r$freq_hi)
}

# ── S8a: frequentist REML concordance (OS, CMV) ────────────────────────────
export_fig(
  forest("C1_overall_mortality_OS_event.csv", "c1_os",
         "Overall survival — PTCy vs CNI + MTX/MMF",
         pooled_spec = reml_spec("c1_os"),
         subtitle = "Frequentist REML concordance check for figure 2"),
  "FigureS8a_OS_forest_frequentist", w = 9, h = 9.5)

export_fig(
  forest("C1_CMV_any_reactivation.csv", "c1_cmv",
         "CMV reactivation — PTCy vs CNI + MTX/MMF",
         pooled_spec = reml_spec("c1_cmv"),
         subtitle = "Frequentist REML concordance check for figure 3"),
  "FigureS8a_CMV_forest_frequentist", w = 9, h = 7)

# ── S8b–S8i: secondary outcomes, Bayesian M1 pooled ────────────────────────
panels <- tribble(
  ~stem,                         ~analytic,                                        ~slug,          ~title,                                                        ~h,
  "FigureS8b_aGVHD_forest",      "C1_aGVHD_grade_II_IV.csv",                       "c1_agvhd",      "Acute GVHD grade II–IV — PTCy vs CNI + MTX/MMF",                8.5,
  "FigureS8c_NRM_forest",        "C1_NRM_NRM_overall.csv",                         "c1_nrm",        "Non-relapse mortality — PTCy vs CNI + MTX/MMF",                 5,
  "FigureS8d_RRM_forest",        "C1_relapse_related_mortality.csv",               "c1_rrm",        "Relapse-related mortality — PTCy vs CNI + MTX/MMF",             9.5,
  "FigureS8e_cGVHD_forest",      "C1_cGVHD_moderate_severe_NIH.csv",               "c1_cgvhd_ms",   "Chronic GVHD mod–severe — PTCy vs CNI + MTX/MMF",               6.5,
  "FigureS8f_BSI_forest",        "C1_BSI_any_pathogen.csv",                        "c1_bsi",        "Bloodstream infection, any pathogen — PTCy vs CNI + MTX/MMF",   3.5,
  "FigureS8g_IFI_forest",        "C1_IFI_any_EORTC_MSG_proven_probable_combined.csv", "c1_ifi_any",  "Invasive fungal infection, any — PTCy vs CNI + MTX/MMF",        3.5,
  "FigureS8h_BK_forest",         "C1_BK_virus_reactivation.csv",                   "c1_bk",         "BK virus reactivation — PTCy vs CNI + MTX/MMF",                 4.5,
  "FigureS8i_IRM_forest",        "C1_infection_related_mortality_IRM_any_cause_infectious.csv", "c1_irm", "Infection-related mortality — PTCy vs CNI + MTX/MMF",       5
)
for (i in seq_len(nrow(panels))) {
  r <- panels[i, ]
  export_fig(forest(r$analytic, r$slug, r$title), r$stem, w = 9, h = r$h)
}

# ── S8j: comparison 3, four panels with REML pooled ────────────────────────
c3_panels <- tribble(
  ~analytic,                  ~slug,       ~title,
  "C3_overall_mortality_OS_event.csv",  "c3_os",     "Overall survival — within-PTCy variants",
  "C3_NRM_NRM_overall.csv",             "c3_nrm",    "Non-relapse mortality — within-PTCy variants",
  "C3_aGVHD_grade_II_IV.csv",           "c3_agvhd",  "Acute GVHD grade II–IV — within-PTCy variants",
  "C3_cGVHD_moderate_severe_NIH.csv",   "c3_cgvhd",  "Chronic GVHD mod–severe — within-PTCy variants"
)
fig_s8j <- lapply(seq_len(nrow(c3_panels)), \(i) {
  r <- c3_panels[i, ]
  forest(r$analytic, r$slug, r$title, pooled_spec = reml_spec(r$slug),
         subtitle = "Comparison 3 (within-PTCy regimen variants)")
})
export_fig(Reduce(`/`, fig_s8j), "FigureS8j_C3_forest", w = 9, h = 9)

cat("done\n")
