# Hazard-ratio sensitivity analysis for overall survival (reviewer response).
#
# The primary OS analysis pools odds ratios of death at fixed timepoints, one
# timepoint per study. Reviewers asked for an HR-based sensitivity analysis.
# This script pools the OS hazard ratios recorded during extraction
# (data/outcomes.csv) two-stage:
#
#   * one HR per study: multivariable-adjusted preferred; the row matching the
#     analytic timepoint preferred, else the closest reported timepoint;
#   * direction harmonised to "PTCy vs comparator, death as the event",
#     inverting HRs extracted comparator-first;
#   * Bayesian normal-normal random-effects pooling of log HRs with known SEs
#     (same weakly-informative prior family as the primary models), plus a
#     frequentist REML concordance check (project convention).
#
# Restricted to the cohort-deduplicated (Set B) C1/C2 OS study sets.
# Outputs: _fits_rs/hr_os_{c1,c2}.rds, data/models/hr_sensitivity_os.csv.

suppressPackageStartupMessages({
  library(tidyverse)
  library(brms)
  library(metafor)
})

out_dir <- path.expand("~/ptcy-infection/_fits_rs")
dir.create(out_dir, showWarnings = FALSE)

oc <- read_csv("data/outcomes.csv", show_col_types = FALSE)

# One direction-harmonised HR per Set B study -------------------------------
hr_one <- map_dfr(c("c1", "c2"), \(cp) {
  ana <- read_csv(sprintf("data/models/data_%s_os.csv", cp), show_col_types = FALSE)
  oc |>
    filter(outcome_category == "overall_mortality",
           !is.na(hr_value), !is.na(hr_ci_lower), !is.na(hr_ci_upper)) |>
    inner_join(ana |> select(study_id, ptcy_arm_id, comp_arm_id, timepoint_used),
               by = "study_id", relationship = "many-to-many") |>
    mutate(
      orient = case_when(
        arm_id == ptcy_arm_id & hr_comparator_arm_id == comp_arm_id ~ "ptcy_vs_comp",
        arm_id == comp_arm_id & hr_comparator_arm_id == ptcy_arm_id ~ "comp_vs_ptcy",
        TRUE ~ "unresolved"
      ),
      tp_match = timepoint == timepoint_used,
      tp_dist = abs(as.numeric(timepoint_days_numeric) -
                      as.numeric(str_extract(timepoint_used, "\\d+")))
    ) |>
    filter(orient != "unresolved") |>
    mutate(comp = toupper(cp))
}) |>
  arrange(study_id, hr_adjusted != "adjusted", !tp_match,
          coalesce(tp_dist, 1e6), desc(as.numeric(timepoint_days_numeric))) |>
  group_by(study_id) |> slice(1) |> ungroup() |>
  mutate(across(c(hr_value, hr_ci_lower, hr_ci_upper),
                \(x) suppressWarnings(as.numeric(x)))) |>
  filter(!is.na(hr_value), !is.na(hr_ci_lower), !is.na(hr_ci_upper)) |>
  mutate(
    yi = if_else(orient == "ptcy_vs_comp", log(hr_value), -log(hr_value)),
    sei = (log(hr_ci_upper) - log(hr_ci_lower)) / (2 * qnorm(0.975)),
    study_id = factor(study_id)
  )

write_csv(
  hr_one |> select(comp, study_id, timepoint, hr_adjusted, orient,
                   hr_value, hr_ci_lower, hr_ci_upper),
  "data/models/hr_sensitivity_os.csv"
)

# Two-stage pooling ----------------------------------------------------------
priors_hr <- c(
  prior(normal(0, 2.5), class = Intercept),
  prior(student_t(3, 0, 1), class = sd)
)

set.seed(6183)
seeds <- sample.int(10000, 2)
fits <- map(set_names(c("C1", "C2")), \(cp) {
  brm(yi | se(sei) ~ 1 + (1 | study_id),
      data = filter(hr_one, comp == cp), prior = priors_hr,
      chains = 4, iter = 4000, warmup = 1000, seed = seeds[match(cp, c("C1", "C2"))],
      control = list(adapt_delta = 0.999, max_treedepth = 14), refresh = 0)
})
iwalk(fits, \(f, cp) saveRDS(f, file.path(out_dir, paste0("hr_os_", tolower(cp), ".rds"))))

bayes <- imap_dfr(fits, \(f, cp) {
  dr <- as_draws_df(f)
  hr <- exp(dr$b_Intercept)
  tibble(comp = cp, method = "Bayesian normal-normal",
         hr_med = median(hr), hr_lo = quantile(hr, .025), hr_hi = quantile(hr, .975),
         tau = median(dr$sd_study_id__Intercept),
         divergences = rstan::get_num_divergent(f$fit))
})

reml <- map_dfr(c("C1", "C2"), \(cp) {
  r <- rma(yi, sei = sei, data = filter(hr_one, comp == cp), method = "REML")
  tibble(comp = cp, method = "REML (metafor)",
         hr_med = exp(r$beta[1]), hr_lo = exp(r$ci.lb), hr_hi = exp(r$ci.ub),
         tau = sqrt(r$tau2), divergences = NA_integer_)
})

res <- bind_rows(bayes, reml) |>
  mutate(k = map_int(comp, \(cp) sum(hr_one$comp == cp)), .after = comp) |>
  mutate(across(where(is.double), \(x) round(x, 3)))
print(res)
cat("done\n")
