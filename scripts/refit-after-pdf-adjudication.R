# Refit the Table 2 models affected by PDF adjudication (2026-10-02).
#
# PDF verification of uncertain_provenance rows confirmed that 8 arms
# (study 20 cGVHD; studies 198/66/299 OS; study 397 NRM) carried event counts
# back-derived from cumulative incidences. Those events were set to NA in
# data/models/*.csv, so the affected random-slope fits (the fits reported in
# Table 2) are rerun here against the corrected data, and Table2_setB.csv is
# updated. Specification matches scripts/refit-random-slope.R and
# scripts/export-prediction-intervals.R exactly, except that data are read
# from this repo's corrected data/models/ instead of the analysis repo.
#
# Run from project root: source("scripts/refit-after-pdf-adjudication.R")

suppressPackageStartupMessages({
  library(tidyverse)
  library(brms)
})

out_dir <- path.expand("~/ptcy-infection/_fits_rs")
dir.create(out_dir, showWarnings = FALSE)

mk_long <- function(d) {
  bind_rows(
    d |> transmute(study_id, tp_early, ptcy_binary = 1,
                   events_n = ptcy_e, denom_n = ptcy_n,
                   steroid_pct = ptcy_steroid_pct),
    d |> transmute(study_id, tp_early, ptcy_binary = 0,
                   events_n = comp_e, denom_n = comp_n,
                   steroid_pct = comp_steroid_pct)
  ) |>
    filter(!is.na(events_n)) |>  # CIF-derived pseudo-counts nulled 2026-10-02
    mutate(study_id = factor(study_id))
}

mk_data <- function(d, m2) {
  long <- mk_long(d)
  if (!m2) return(long)
  long |>
    filter(!is.na(steroid_pct)) |>
    mutate(steroid_pct_c = steroid_pct - mean(steroid_pct))
}

priors_rs <- c(
  prior(normal(0, 2.5), class = b),
  prior(normal(0, 1.5), class = Intercept),
  prior(student_t(3, 0, 1), class = sd)
)

spec <- tribble(
  ~key,          ~m2,    ~data_file,
  "c1_cgvhd_m1", FALSE,  "data_c1_cgvhd_ms.csv",
  "c1_os_m1",    FALSE,  "data_c1_os.csv",
  "c1_os_m2",    TRUE,   "data_c1_os.csv",
  "c2_os_m1",    FALSE,  "data_c2_os.csv",
  "c2_os_m2",    TRUE,   "data_c2_os.csv",
  "c3_nrm_m1",   FALSE,  "data_c3_nrm.csv"
)

set.seed(7311)
seeds <- sample.int(10000, nrow(spec))

results <- list()
for (i in seq_len(nrow(spec))) {
  row <- spec[i, ]
  cat("fitting:", row$key, "\n")
  dat <- read.csv(file.path("data/models", row$data_file)) |> mk_data(row$m2)
  rhs <- if (row$m2) {
    "events_n | trials(denom_n) ~ ptcy_binary + tp_early + steroid_pct_c + (1 + ptcy_binary | study_id)"
  } else {
    "events_n | trials(denom_n) ~ ptcy_binary + tp_early + (1 + ptcy_binary | study_id)"
  }
  # backend = cmdstanr: rstan on this machine fails to load compiled models
  # (TBB task_scheduler_init symbol error, 2026-10-02)
  fit <- brm(
    as.formula(rhs), data = dat, family = binomial(), prior = priors_rs,
    chains = 4, iter = 4000, warmup = 1000, seed = seeds[i],
    control = list(adapt_delta = 0.95), refresh = 0,
    backend = "cmdstanr"
  )
  num_div <- function(fit) {
    tryCatch(sum(fit$fit$diagnostic_summary()$num_divergent),
             error = function(e) rstan::get_num_divergent(fit$fit))
  }
  div <- num_div(fit)
  if (div > 0) {
    cat("  ", div, "divergences at adapt_delta 0.95; refitting at 0.99\n")
    fit <- brm(
      as.formula(rhs), data = dat, family = binomial(), prior = priors_rs,
      chains = 4, iter = 4000, warmup = 1000, seed = seeds[i],
      control = list(adapt_delta = 0.99), refresh = 0,
      backend = "cmdstanr"
    )
    div <- num_div(fit)
  }
  saveRDS(fit, file.path(out_dir, paste0("rs_", row$key, ".rds")))

  dr <- as_draws_df(fit)
  or <- exp(dr$b_ptcy_binary)
  theta_new <- dr$b_ptcy_binary + rnorm(nrow(dr), 0, dr$sd_study_id__ptcy_binary)
  pi_q <- quantile(exp(theta_new), c(.025, .975))
  results[[row$key]] <- tibble(
    key = row$key,
    k = n_distinct(dat$study_id),
    n_total = sum(dat$denom_n),
    or_med = median(or), or_lo = quantile(or, .025), or_hi = quantile(or, .975),
    tau_slope = median(dr$sd_study_id__ptcy_binary),
    pi_low = unname(pi_q[1]), pi_high = unname(pi_q[2]),
    max_rhat = max(summary(fit)$fixed$Rhat, na.rm = TRUE),
    divergences = div
  )
}

res <- bind_rows(results)
print(res, width = 200)

# Update Table2_setB.csv
keymap <- tribble(
  ~slug,        ~model,       ~key,
  "c1_cgvhd_ms", "m1",         "c1_cgvhd_m1",
  "c1_os",       "m1",         "c1_os_m1",
  "c1_os",       "m2_steroid", "c1_os_m2",
  "c2_os",       "m1",         "c2_os_m1",
  "c2_os",       "m2_steroid", "c2_os_m2",
  "c3_nrm",      "m1",         "c3_nrm_m1"
)
t2 <- read_csv("data/models/Table2_setB.csv", show_col_types = FALSE)
for (i in seq_len(nrow(keymap))) {
  r <- res |> filter(key == keymap$key[i])
  idx <- which(t2$slug == keymap$slug[i] & t2$model == keymap$model[i])
  t2$k[idx]         <- r$k
  t2$n_total[idx]   <- r$n_total
  t2$or_median[idx] <- round(r$or_med, 3)
  t2$ci_low[idx]    <- round(r$or_lo, 3)
  t2$ci_high[idx]   <- round(r$or_hi, 3)
  t2$tau[idx]       <- round(r$tau_slope, 3)
  t2$pi_low[idx]    <- round(r$pi_low, 3)
  t2$pi_high[idx]   <- round(r$pi_high, 3)
  t2$source[idx]    <- "random-slope refit 2026-10-02 post PDF adjudication"
}
write_csv(t2, "data/models/Table2_setB.csv")
write_csv(res, "data/models/refit_2026-10-02_pdf_adjudication.csv")
cat("done\n")