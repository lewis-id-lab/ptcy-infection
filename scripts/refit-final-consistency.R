# Final consistency refits (2026-10-02, post read-through):
#   1. M1-on-M2-subset matched comparisons (6 outcomes) — the M2 steroid
#      complete-case subsets on the post-adjudication data, replacing the
#      stale m1_m2_matched.csv.
#   2. τ-prior sensitivity for C1 BSI (k = 4 restricted primary) and C1 IFI
#      (k = 6), replacing the stale prior_sensitivity_tau.csv BSI rows.
# Run: Rscript -e 'source("scripts/refit-final-consistency.R")'

suppressPackageStartupMessages({
  library(tidyverse)
  library(brms)
})

out_dir <- path.expand("~/ptcy-infection/_fits_rs")
priors_rs <- c(prior(normal(0, 2.5), class = b),
               prior(normal(0, 1.5), class = Intercept),
               prior(student_t(3, 0, 1), class = sd))
num_div <- function(fit) {
  tryCatch(sum(fit$fit$diagnostic_summary()$num_divergent),
           error = function(e) rstan::get_num_divergent(fit$fit))
}
mk_long <- function(d) {
  bind_rows(
    d |> transmute(study_id, tp_early, ptcy_binary = 1, events_n = ptcy_e,
                   denom_n = ptcy_n, steroid_pct = ptcy_steroid_pct),
    d |> transmute(study_id, tp_early, ptcy_binary = 0, events_n = comp_e,
                   denom_n = comp_n, steroid_pct = comp_steroid_pct)) |>
    filter(!is.na(events_n)) |> mutate(study_id = factor(study_id))
}
fit_one <- function(dat, rhs, seed, sd_prior = NULL) {
  pri <- if (is.null(sd_prior)) priors_rs else
    c(prior(normal(0, 2.5), class = b), prior(normal(0, 1.5), class = Intercept),
      prior_string(paste0("student_t(3, 0, ", sd_prior, ")"), class = "sd"))
  brm(as.formula(rhs), data = dat, family = binomial(), prior = pri,
      chains = 4, iter = 4000, warmup = 1000, seed = seed,
      control = list(adapt_delta = 0.99), refresh = 0, backend = "cmdstanr")
}
summ <- function(fit, label, k_note = NULL) {
  dr <- as_draws_df(fit)
  or <- exp(dr$b_ptcy_binary)
  tibble(outcome = label, k = n_distinct(fit$data$study_id),
         n_total = sum(fit$data$denom_n),
         or_med = median(or), or_lo = quantile(or, .025), or_hi = quantile(or, .975),
         tau_slope = median(dr$sd_study_id__ptcy_binary), divergences = num_div(fit))
}

set.seed(3359)
## ── 1. M1 on M2 complete-case subsets ──
m2_spec <- c(c1_os = "data_c1_os.csv", c1_rrm = "data_c1_rrm.csv",
             c1_nrm = "data_c1_nrm.csv", c1_cmv = "data_c1_cmv.csv",
             c2_os = "data_c2_os.csv", c2_cmv = "data_c2_cmv.csv")
m2_labels <- c(c1_os = "C1 Overall survival", c1_rrm = "C1 Relapse-related mortality",
               c1_nrm = "C1 Non-relapse mortality", c1_cmv = "C1 CMV reactivation",
               c2_os = "C2 Overall survival", c2_cmv = "C2 CMV reactivation")
t2 <- read_csv("data/models/Table2_setB.csv", show_col_types = FALSE)
matched <- map_dfr(names(m2_spec), function(key) {
  d <- read_csv(file.path("data/models", m2_spec[key]), show_col_types = FALSE)
  long <- mk_long(d)
  m2 <- long |> filter(!is.na(steroid_pct))
  fit <- fit_one(m2, "events_n | trials(denom_n) ~ ptcy_binary + tp_early + (1 + ptcy_binary | study_id)",
                 sample.int(10000, 1))
  saveRDS(fit, file.path(out_dir, paste0("rep_m1_matched_", key, ".rds")))
  full <- t2 |> filter(slug == key, model == "m1")
  bind_rows(
    tibble(outcome = m2_labels[key], model = "M1 full set", k = full$k,
           n_total = full$n_total, or_med = full$or_median, or_lo = full$ci_low,
           or_hi = full$ci_high, tau_slope = full$tau, divergences = 0L),
    summ(fit, m2_labels[key]) |> mutate(model = "M1 matched set"),
    { m2r <- t2 |> filter(slug == key, model == "m2_steroid")
      tibble(outcome = m2_labels[key], model = "M2", k = m2r$k, n_total = m2r$n_total,
             or_med = m2r$or_median, or_lo = m2r$ci_low, or_hi = m2r$ci_high,
             tau_slope = m2r$tau, divergences = 0L) }
  )
}) |> select(outcome, model, k, n_total, or_med, or_lo, or_hi, tau_slope, divergences)
write_csv(matched, "data/models/m1_m2_matched.csv")
print(matched, width = 200)

## ── 2. τ-prior sensitivity (BSI restricted k=4; IFI k=6) ──
tau_res <- list()
for (cfg in list(list(slug = "c1_bsi", file = "data_c1_bsi.csv", label = "C1 BSI", restricted = TRUE),
                 list(slug = "c1_ifi_any", file = "data_c1_ifi_any.csv", label = "C1 IFI", restricted = FALSE))) {
  d <- read_csv(file.path("data/models", cfg$file), show_col_types = FALSE)
  if (cfg$restricted) d <- d |> filter(tp_early == 0)
  dat <- mk_long(d)
  for (sdp in c(0.5, 1, 2)) {
    fit <- fit_one(dat, "events_n | trials(denom_n) ~ ptcy_binary + (1 + ptcy_binary | study_id)",
                   sample.int(10000, 1), sd_prior = sdp)
    saveRDS(fit, file.path(out_dir, paste0("rep_tau_", cfg$slug, "_", sdp, ".rds")))
    dr <- as_draws_df(fit)
    or <- exp(dr$b_ptcy_binary)
    tau_res[[paste(cfg$slug, sdp)]] <- tibble(
      outcome = cfg$label, sd_prior = sdp, k = n_distinct(dat$study_id),
      or_med = median(or), or_lo = quantile(or, .025), or_hi = quantile(or, .975),
      tau_slope = median(dr$sd_study_id__ptcy_binary), divergences = num_div(fit))
  }
}
tau_res <- bind_rows(tau_res)
write_csv(tau_res, "data/models/prior_sensitivity_tau.csv")
print(tau_res, width = 200)
cat("done\n")