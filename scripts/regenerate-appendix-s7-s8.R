# Regenerate appendix S7 (MCMC diagnostics) and S8 (frequentist forest plots)
# from the cohort-deduplicated (Set B) fits in the analysis repository.
#
# Only outcomes affected by cohort deduplication need Set B fits: C1 OS, C1 RRM,
# C1 cGVHD (moderate-severe), C1 IRM, C2 OS, C2 aGVHD, C2 CMV. Everything else
# resolves to the post_block9 fits, which are identical to Set B for those
# outcomes. Writes figures to ptcy-infection/figures/ as png/pdf/svg and prints
# the S7 diagnostics values for the affected models (transcribed into
# appendix.qmd by hand).

suppressPackageStartupMessages({
  library(tidyverse)
  library(brms)
  library(bayesplot)
  library(metafor)
  library(patchwork)
})

analysis_dir <- path.expand("~/ptcy_metaanalys")
sb_dir <- file.path(analysis_dir, "03_models/set_b")
p9_dir <- file.path(analysis_dir, "03_models/post_block9")
fig_dir <- path.expand("~/ptcy-infection/figures")

# forest_study(), theme_jama() and the JAMA palette live in the website's shared
# setup; it resolves paths relative to 05_website, so source it from there.
website_dir <- file.path(analysis_dir, "05_website")
old_wd <- setwd(website_dir)
source("_common.R")
setwd(old_wd)

studies_df <- read_csv(
  file.path(analysis_dir, "02_extraction/studies.csv"),
  show_col_types = FALSE
)

# ── Fit registry ──
fit_paths <- c(
  # Set B (cohort-deduplicated) — affected outcomes
  c1_os      = file.path(sb_dir, "m1_c1_os.rds"),
  c1_os_m2   = file.path(sb_dir, "m2_c1_os.rds"),
  c1_rrm     = file.path(sb_dir, "m1_c1_rrm.rds"),
  c1_irm     = file.path(sb_dir, "m1_c1_irm.rds"),
  c1_cgvhd   = file.path(sb_dir, "m1_c1_cgvhd_ms.rds"),
  c2_os      = file.path(sb_dir, "m1_c2_os.rds"),
  c2_os_m2   = file.path(sb_dir, "m2_c2_os.rds"),
  c2_agvhd   = file.path(sb_dir, "m1_c2_agvhd.rds"),
  c2_cmv     = file.path(sb_dir, "m1_c2_cmv.rds"),
  c2_cmv_m2  = file.path(sb_dir, "m2_c2_cmv.rds"),
  # post_block9 — outcomes unaffected by deduplication (true brmsfit objects;
  # the `*_brms_clean.rds` files in the same directory are cached draws frames)
  c1_nrm     = file.path(p9_dir, "m1_c1_nrm.rds"),
  c1_agvhd   = file.path(p9_dir, "m1_c1_agvhd.rds"),
  c1_cmv     = file.path(p9_dir, "m1_c1_cmv.rds"),
  c1_bsi     = file.path(p9_dir, "m1_c1_bsi.rds"),
  c1_ifi     = file.path(p9_dir, "m1_c1_ifi_any.rds"),
  c1_bk      = file.path(p9_dir, "m1_c1_bk.rds"),
  c2_nrm     = file.path(p9_dir, "m1_c2_nrm.rds"),
  c2_rrm     = file.path(p9_dir, "m1_c2_rrm.rds"),
  c2_bk      = file.path(p9_dir, "m1_c2_bk.rds")
)
missing <- fit_paths[!file.exists(fit_paths)]
if (length(missing)) {
  stop("Missing fits:\n", paste0(" - ", names(missing), ": ", missing, collapse = "\n"))
}
fits <- lapply(fit_paths, readRDS)

# ── S7 tables: diagnostics for the models whose rows change ──
diag_row <- function(m, label) {
  s <- summary(m)
  all_rows <- rbind(s$fixed, s$random$study_id)
  tibble(
    Model = label,
    max_rhat = max(all_rows$Rhat, na.rm = TRUE),
    min_bulk_ess = min(all_rows$Bulk_ESS, na.rm = TRUE),
    min_tail_ess = min(all_rows$Tail_ESS, na.rm = TRUE),
    divergences = rstan::get_num_divergent(m$fit)
  )
}

affected <- c(
  "C1 OS M1" = "c1_os", "C1 OS M2" = "c1_os_m2",
  "C1 RRM M1" = "c1_rrm", "C1 IRM M1" = "c1_irm",
  "C2 OS M1" = "c2_os", "C2 OS M2" = "c2_os_m2",
  "C2 aGVHD M1" = "c2_agvhd", "C2 CMV M1" = "c2_cmv", "C2 CMV M2" = "c2_cmv_m2"
)
diag_tbl <- imap_dfr(affected, ~ diag_row(fits[[.x]], .y))
diag_tbl |>
  mutate(across(c(max_rhat), ~ round(.x, 4)),
         across(c(min_bulk_ess, min_tail_ess), as.integer)) |>
  as.data.frame() |>
  print()

# ── S7b: trace plots, OS M1 (left) and CMV M1 (right), b (top) and tau (bottom)
color_scheme_set(c(jama_navy, jama_blue, jama_steel, jama_light_blue,
                   jama_grey, jama_dark))
trace_grid <- function(fit, title) {
  list(
    mcmc_trace(fit, regex_pars = "b_.*ptcy_binary") +
      labs(title = title, subtitle = "b_ptcy_binary") +
      theme_jama(base_size = 9) +
      theme(legend.position = "none"),
    mcmc_trace(fit, regex_pars = "sd_study_id") +
      labs(subtitle = "sd_study_id__Intercept (tau)") +
      theme_jama(base_size = 9) +
      theme(legend.position = "none")
  )
}
os_panels <- trace_grid(fits$c1_os, "OS M1")
cmv_panels <- trace_grid(fits$c1_cmv, "CMV M1")
fig_s7b <- (os_panels[[1]] | cmv_panels[[1]]) /
  (os_panels[[2]] | cmv_panels[[2]])

ggsave(file.path(fig_dir, "FigureS7b_trace_plots.png"), fig_s7b,
  width = 10, height = 6, dpi = 320)
ggsave(file.path(fig_dir, "FigureS7b_trace_plots.pdf"), fig_s7b, device = cairo_pdf,
  width = 10, height = 6)
ggsave(file.path(fig_dir, "FigureS7b_trace_plots.svg"), fig_s7b,
  width = 10, height = 6)

# ── S7c: tau posterior densities, C1 M1 models, with half-t(3,0,1) prior ──
tau_models <- c("OS", "NRM", "aGVHD", "CMV", "BSI", "IFI")
tau_keys <- c("c1_os", "c1_nrm", "c1_agvhd", "c1_cmv", "c1_bsi", "c1_ifi")
tau_data <- map2_dfr(tau_keys, tau_models, function(k, nm) {
  tibble(Outcome = nm, tau = as_draws_df(fits[[k]])$sd_study_id__Intercept)
})
set.seed(8471)
prior_draws <- abs(rt(12000, df = 3)) # half-Student t(3, 0, 1)
tau_data <- bind_rows(tau_data, tibble(Outcome = "Prior", tau = prior_draws)) |>
  mutate(Outcome = factor(Outcome, levels = c(tau_models, "Prior")))

fig_s7c <- ggplot(tau_data, aes(x = tau, y = Outcome, fill = Outcome)) +
  ggridges::geom_density_ridges(alpha = 0.55, scale = 1.2, colour = jama_dark,
                                linewidth = 0.3) +
  scale_fill_manual(values = c(
    "OS" = jama_navy, "NRM" = jama_blue, "aGVHD" = jama_steel,
    "CMV" = jama_light_blue, "BSI" = jama_grey, "IFI" = "#b8860b",
    "Prior" = jama_light_grey
  )) +
  labs(x = "Between-study SD (tau)", y = NULL) +
  theme_jama() +
  theme(legend.position = "none")

ggsave(file.path(fig_dir, "FigureS7c_tau_posteriors.png"), fig_s7c,
  width = 8, height = 5, dpi = 320)
ggsave(file.path(fig_dir, "FigureS7c_tau_posteriors.pdf"), fig_s7c, device = cairo_pdf,
  width = 8, height = 5)
ggsave(file.path(fig_dir, "FigureS7c_tau_posteriors.svg"), fig_s7c,
  width = 8, height = 5)

# ── S7d: posterior predictive checks — observed vs predictive-mean proportion ──
set.seed(2914)
ppc_points <- function(m, outcome) {
  yrep <- posterior_predict(m, ndraws = 500)
  d <- m$data
  tibble(
    outcome = outcome,
    obs = d$events_n / d$denom_n,
    pred = colMeans(yrep) / d$denom_n
  )
}

ppc_c1 <- bind_rows(
  ppc_points(fits$c1_os, "OS"), ppc_points(fits$c1_nrm, "NRM"),
  ppc_points(fits$c1_agvhd, "aGVHD"), ppc_points(fits$c1_cmv, "CMV"),
  ppc_points(fits$c1_bsi, "BSI"), ppc_points(fits$c1_ifi, "IFI"),
  ppc_points(fits$c1_rrm, "RRM"), ppc_points(fits$c1_bk, "BK"),
  ppc_points(fits$c1_irm, "IRM")
)
ppc_c2 <- bind_rows(
  ppc_points(fits$c2_os, "OS"), ppc_points(fits$c2_nrm, "NRM"),
  ppc_points(fits$c2_agvhd, "aGVHD"), ppc_points(fits$c2_cmv, "CMV"),
  ppc_points(fits$c2_rrm, "RRM"), ppc_points(fits$c2_bk, "BK")
)

ppc_plot <- function(dat, title) {
  ggplot(dat, aes(x = obs, y = pred)) +
    geom_abline(slope = 1, intercept = 0, linetype = "dashed",
                colour = jama_grey, linewidth = 0.4) +
    geom_point(alpha = 0.5, size = 0.9, colour = jama_navy) +
    facet_wrap(~ outcome, scales = "free") +
    labs(x = "Observed event proportion",
         y = "Posterior predictive mean",
         title = title) +
    theme_jama(base_size = 9)
}
fig_s7d1 <- ppc_plot(ppc_c1, "Posterior predictive checks — comparison 1")
fig_s7d2 <- ppc_plot(ppc_c2, "Posterior predictive checks — comparison 2")

ggsave(file.path(fig_dir, "FigureS7d_i_ppc_C1.png"), fig_s7d1,
  width = 9, height = 7, dpi = 320)
ggsave(file.path(fig_dir, "FigureS7d_i_ppc_C1.pdf"), fig_s7d1, device = cairo_pdf,
  width = 9, height = 7)
ggsave(file.path(fig_dir, "FigureS7d_i_ppc_C1.svg"), fig_s7d1,
  width = 9, height = 7)
ggsave(file.path(fig_dir, "FigureS7d_ii_ppc_C2.png"), fig_s7d2,
  width = 9, height = 6, dpi = 320)
ggsave(file.path(fig_dir, "FigureS7d_ii_ppc_C2.pdf"), fig_s7d2, device = cairo_pdf,
  width = 9, height = 6)
ggsave(file.path(fig_dir, "FigureS7d_ii_ppc_C2.svg"), fig_s7d2,
  width = 9, height = 6)

# ── S8: frequentist REML forests for the four affected C1 outcomes ──
s8_specs <- tribble(
  ~slug,        ~data_file,               ~fig_name,                      ~title,
  "c1_os",      "data_c1_os.csv",         "FigureS8a_OS_forest_frequentist",  "Overall Survival",
  "c1_rrm",     "data_c1_rrm.csv",        "FigureS8d_RRM_forest",         "Relapse-Related Mortality",
  "c1_cgvhd_ms", "data_c1_cgvhd_ms.csv",  "FigureS8e_cGVHD_forest",       "Chronic GVHD Moderate-Severe",
  "c1_irm",     "data_c1_irm.csv",        "FigureS8i_IRM_forest",         "Infection-Related Mortality"
)

freq_check <- read.csv(file.path(sb_dir, "freq_results_setB.csv"))

for (i in seq_len(nrow(s8_specs))) {
  spec <- s8_specs[i, ]
  dat <- read.csv(file.path(sb_dir, spec$data_file))
  p <- forest_study(dat, studies_df, spec$title, "C1: PTCy vs CNI+MTX/MMF")
  h <- max(5, nrow(dat) * 0.35 + 2)
  ggsave(file.path(fig_dir, paste0(spec$fig_name, ".png")), p,
    width = 10, height = h, dpi = 320, limitsize = FALSE)
  ggsave(file.path(fig_dir, paste0(spec$fig_name, ".pdf")), p, device = cairo_pdf,
    width = 10, height = h, limitsize = FALSE)
  ggsave(file.path(fig_dir, paste0(spec$fig_name, ".svg")), p,
    width = 10, height = h, limitsize = FALSE)

  # Concordance check against the recorded Set B frequentist results
  es <- escalc(measure = "OR", ai = ptcy_e, n1i = ptcy_n, ci = comp_e,
               n2i = comp_n, data = dat, add = 0.5, to = "only0")
  fit <- rma(yi, vi, data = es, method = "REML")
  ref <- freq_check[freq_check$slug == spec$slug & freq_check$source == "set_b", ]
  cat(sprintf(
    "%s: k=%d  REML OR %.3f [%.3f, %.3f]  (recorded: %.3f [%.3f, %.3f])\n",
    spec$slug, fit$k, exp(coef(fit)), exp(fit$ci.lb), exp(fit$ci.ub),
    ref$freq_or, ref$freq_lo, ref$freq_hi
  ))
}

cat("\nDone. Figures written to", fig_dir, "\n")
