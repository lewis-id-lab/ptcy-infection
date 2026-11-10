# Observational-only M1 refits on the primary model sets (DECISIONS.md,
# 2026-11-10; checklist B3/B4).
#
# The observational-only models reported in appendix S9 were fitted by
# scripts/refit-reporting-suite.R (section 1) from data/analytic/*.csv with a
# largest-study-per-cohort rule, so their study sets differ from the primary
# models for C1 overall survival, chronic GVHD and CMV. This script refits
# those three on the primary model inputs (data/models/data_c1_*.csv, rows
# with event counts in both arms) with randomised trials removed. Model
# specification, priors and sampler settings are those of the reporting suite.
# Acute GVHD and non-relapse mortality already used the primary sets and are
# not refitted.
#
# Writes _fits_rs/rep_<key>_obs_primaryset.rds and
# audit/obs_only_refit_2026-11-10.csv. It does not overwrite
# data/models/rct_only_results.csv or the earlier fits.
# Run from project root: source("scripts/refit-obs-only-primary-sets.R")

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(purrr)
  library(brms)
})

fit_dir <- "_fits_rs"
studies <- read_csv("data/studies.csv", show_col_types = FALSE)
rct_ids <- studies$study_id[studies$study_design == "RCT"]

priors_rs <- c(
  prior(normal(0, 2.5), class = b),
  prior(normal(0, 1.5), class = Intercept),
  prior(student_t(3, 0, 1), class = sd)
)
num_div <- function(fit) {
  tryCatch(sum(fit$fit$diagnostic_summary()$num_divergent),
           error = function(e) rstan::get_num_divergent(fit$fit))
}
mk_long <- function(d) {
  bind_rows(
    d |> transmute(study_id, tp_early, ptcy_binary = 1, events_n = ptcy_e, denom_n = ptcy_n),
    d |> transmute(study_id, tp_early, ptcy_binary = 0, events_n = comp_e, denom_n = comp_n)
  ) |> mutate(study_id = factor(study_id))
}
or_row <- function(fit) {
  dr <- as_draws_df(fit)
  or <- exp(dr$b_ptcy_binary)
  s <- summary(fit)
  rows <- rbind(s$fixed, s$random$study_id)
  tibble(k = n_distinct(fit$data$study_id), n_total = sum(fit$data$denom_n),
         or_med = median(or), or_lo = quantile(or, .025), or_hi = quantile(or, .975),
         tau_slope = median(dr$sd_study_id__ptcy_binary),
         max_rhat = max(rows$Rhat, na.rm = TRUE), min_bulk_ess = min(rows$Bulk_ESS, na.rm = TRUE),
         divergences = num_div(fit))
}

spec <- tribble(
  ~key,          ~model_file,            ~old_fit,
  "c1_os",       "data_c1_os.csv",       "rep_c1_os_obs.rds",
  "c1_cgvhd_ms", "data_c1_cgvhd_ms.csv", "rep_c1_cgvhd_ms_obs.rds",
  "c1_cmv",      "data_c1_cmv.csv",      "rep_c1_cmv_obs.rds"
)
set.seed(9164)
spec$seed <- sample.int(10000, nrow(spec))

obs_refit <- pmap(spec, function(key, model_file, old_fit, seed) {
  primary <- read_csv(file.path("data/models", model_file), show_col_types = FALSE) |>
    filter(!is.na(ptcy_e), !is.na(comp_e))
  d <- filter(primary, !study_id %in% rct_ids)
  out_file <- file.path(fit_dir, paste0("rep_", key, "_obs_primaryset.rds"))
  fit <- if (file.exists(out_file)) {
    readRDS(out_file)
  } else {
    f <- brm(events_n | trials(denom_n) ~ ptcy_binary + tp_early + (1 + ptcy_binary | study_id),
             data = mk_long(d), family = binomial(), prior = priors_rs,
             chains = 4, iter = 4000, warmup = 1000, seed = seed,
             control = list(adapt_delta = 0.99), refresh = 0, backend = "cmdstanr")
    saveRDS(f, out_file)
    f
  }
  bind_rows(
    or_row(readRDS(file.path(fit_dir, old_fit))) |> mutate(version = "reported (analytic files)"),
    or_row(fit) |> mutate(version = "refit (primary set, trials removed)")
  ) |>
    mutate(outcome = key, k_primary = nrow(primary), trials_removed = nrow(primary) - nrow(d), .before = 1)
}) |>
  list_rbind() |>
  relocate(version, .after = outcome)

dir.create("audit", showWarnings = FALSE)
write_csv(mutate(obs_refit, across(where(is.double), \(x) round(x, 4))), "audit/obs_only_refit_2026-11-10.csv")
