# RCT-only analyses (reviewer bullet: "an RCT-only analysis (14 RCTs) for each
# outcome where k allows").
#
# Uses the full analytic datasets (not the cohort-deduplicated Set B model
# inputs, where trial follow-up publications were collapsed and only 1-2 RCTs
# remain per outcome), restricted to randomised trials and deduplicated to one
# publication per trial cohort where needed. M1 random-slope specification.
# C2 outcomes have at most 2 RCTs each and are not estimable; reported as such.
#
# Outputs: _fits_rs/rct_only_*.rds and data/models/rct_only_results.csv.

suppressPackageStartupMessages({
  library(tidyverse)
  library(brms)
})

out_dir <- path.expand("~/ptcy-infection/_fits_rs")
dir.create(out_dir, showWarnings = FALSE)

studies <- read_csv("data/studies.csv", show_col_types = FALSE)
rct_ids <- studies |> filter(study_design == "RCT") |> pull(study_id)
cohort_of <- setNames(studies$cohort_id, studies$study_id)

spec <- tribble(
  ~key,          ~analytic_file,
  "c1_os",       "data/analytic/C1_overall_mortality_OS_event.csv",
  "c1_agvhd",    "data/analytic/C1_aGVHD_grade_II_IV.csv",
  "c1_cgvhd_ms", "data/analytic/C1_cGVHD_moderate_severe_NIH.csv",
  "c1_nrm",      "data/analytic/C1_NRM_NRM_overall.csv",
  "c1_cmv",      "data/analytic/C1_CMV_any_reactivation.csv"
)

priors_rs <- c(
  prior(normal(0, 2.5), class = b),
  prior(normal(0, 1.5), class = Intercept),
  prior(student_t(3, 0, 1), class = sd)
)

set.seed(2093)
seeds <- sample.int(10000, nrow(spec))

results <- list()
for (i in seq_len(nrow(spec))) {
  key <- spec$key[i]
  d <- read_csv(spec$analytic_file[i], show_col_types = FALSE) |>
    filter(study_id %in% rct_ids)
  # one publication per trial cohort: keep the largest
  d <- d |>
    mutate(cohort_id = cohort_of[as.character(study_id)]) |>
    group_by(cohort_id) |>
    slice_max(ptcy_n + comp_n, n = 1, with_ties = FALSE) |>
    ungroup()
  k <- n_distinct(d$study_id)
  if (k < 3) {
    cat("skip (k < 3):", key, "k =", k, "\n")
    results[[key]] <- tibble(outcome = key, k_rct = k, note = "not estimable (k < 3)")
    next
  }
  out_file <- file.path(out_dir, paste0("rct_only_", key, ".rds"))
  if (!file.exists(out_file)) {
    cat("fitting:", key, "k =", k, "\n")
    dat <- bind_rows(
      d |> transmute(study_id, ptcy_binary = 1, events_n = ptcy_e, denom_n = ptcy_n),
      d |> transmute(study_id, ptcy_binary = 0, events_n = comp_e, denom_n = comp_n)
    ) |> mutate(study_id = factor(study_id))
    fit <- brm(events_n | trials(denom_n) ~ ptcy_binary + (1 + ptcy_binary | study_id),
               data = dat, family = binomial(), prior = priors_rs,
               chains = 4, iter = 4000, warmup = 1000, seed = seeds[i],
               control = list(adapt_delta = 0.999, max_treedepth = 14), refresh = 0)
    saveRDS(fit, out_file)
  }
  fit <- readRDS(out_file)
  dr <- as_draws_df(fit)
  or <- exp(dr$b_ptcy_binary)
  results[[key]] <- tibble(
    outcome = key, k_rct = k,
    or_med = median(or), or_lo = quantile(or, .025), or_hi = quantile(or, .975),
    tau_slope = median(dr$sd_study_id__ptcy_binary),
    divergences = rstan::get_num_divergent(fit$fit), note = "")
}

res <- bind_rows(results) |>
  mutate(across(where(is.double), \(x) round(x, 3)))
write_csv(res, "data/models/rct_only_results.csv")
print(res, n = Inf)
cat("done\n")
