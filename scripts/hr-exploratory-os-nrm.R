# EXPLORATORY, POST HOC (see DECISIONS.md, 2026-11-10): hazard-ratio pooling for
# overall survival and non-relapse mortality, comparisons 1 and 2.
#
# This is not the primary analysis and not the pre-existing HR sensitivity
# analysis (scripts/hr-sensitivity-os.R, restricted to the Set B model sets).
# Construction used here:
#   * every study with a C1- or C2-eligible PTCy arm and comparator arm (arm
#     eligibility flags in data/arms.csv), not only studies in the model files;
#   * only "matched" hazard ratios: numeric HR with both interval bounds whose
#     stated reference arm is an eligible arm on the other side of the contrast;
#   * one HR per study: adjusted preferred, then the timepoint closest to one
#     year, then the larger arm pair;
#   * one study per cohort_id (primary_for_cohort == "Y" preferred, then size);
#   * direction harmonised to PTCy vs comparator;
#   * Bayesian normal-normal random effects on log HR with the priors of
#     scripts/hr-sensitivity-os.R, plus a REML check.
# Not checked against source papers: HR direction, adjustment set, and whether
# NRM hazard ratios are cause-specific or subdistribution.
# Run from project root: source("scripts/hr-exploratory-os-nrm.R")

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(purrr)
  library(tidyr)
  library(stringr)
  library(brms)
  library(metafor)
})

num <- function(x) suppressWarnings(as.numeric(x))

studies <- read_csv("data/studies.csv", show_col_types = FALSE, guess_max = 5000)
arms <- read_csv("data/arms.csv", show_col_types = FALSE, guess_max = 5000)
outcomes <- read_csv("data/outcomes.csv", show_col_types = FALSE, guess_max = 5000)

outcome_defs <- tribble(
  ~outcome, ~outcome_category,   ~outcome_subtype,
  "OS",     "overall_mortality", "OS_event",
  "NRM",    "NRM",               "NRM_overall"
)

eligible_arms <- arms |>
  select(study_id, arm_id, arm_role, atg_used, n_patients, comparison_1_eligible, comparison_2_eligible) |>
  pivot_longer(matches("^comparison_"), names_to = "comparison", values_to = "eligible") |>
  filter(eligible == "Y") |>
  transmute(study_id, arm_id, comparison = str_c("C", str_extract(comparison, "\\d")),
            side = if_else(arm_role == "PTCy_arm", "ptcy", "comp"), atg_used, n_patients)

hr_candidates <- outcomes |>
  # cohort membership is taken from studies.csv below
  select(-cohort_id) |>
  inner_join(outcome_defs, by = c("outcome_category", "outcome_subtype")) |>
  mutate(hr = num(hr_value), lo = num(hr_ci_lower), hi = num(hr_ci_upper),
         ref_arm = num(hr_comparator_arm_id), tp_days = num(timepoint_days_numeric)) |>
  filter(!is.na(hr), !is.na(lo), !is.na(hi), !is.na(ref_arm), hr > 0, lo > 0, hi > lo) |>
  inner_join(eligible_arms, by = c("study_id", "arm_id"), relationship = "many-to-many") |>
  inner_join(
    eligible_arms |> rename(ref_arm = arm_id, ref_side = side, ref_atg_used = atg_used, ref_n = n_patients),
    by = c("study_id", "comparison", "ref_arm")
  ) |>
  filter(ref_side != side) |>
  mutate(
    yi = if_else(side == "ptcy", log(hr), -log(hr)),
    sei = (log(hi) - log(lo)) / (2 * qnorm(0.975)),
    adjusted = str_detect(str_to_lower(coalesce(hr_adjusted, "")), "^adj"),
    pair_n = n_patients + ref_n,
    # stored ATG fields: neither arm has ATG recorded (the written C1 definition)
    no_atg_recorded = atg_used == "N" & ref_atg_used == "N",
    # point estimate far from the log-scale centre of its interval
    ci_asymmetric = abs(log(hr) - (log(lo) + log(hi)) / 2) > 0.2
  )

hr_one <- hr_candidates |>
  arrange(desc(adjusted), coalesce(abs(tp_days - 365), 1e6), desc(pair_n)) |>
  slice_head(n = 1, by = c(study_id, comparison, outcome)) |>
  left_join(select(studies, study_id, first_author, pub_year, study_design, cohort_id, primary_for_cohort),
            by = "study_id") |>
  mutate(cohort_key = coalesce(as.character(cohort_id), str_c("study_", study_id))) |>
  arrange(coalesce(primary_for_cohort, "") != "Y", desc(pair_n)) |>
  slice_head(n = 1, by = c(cohort_key, comparison, outcome)) |>
  mutate(study = factor(study_id)) |>
  arrange(comparison, outcome, first_author, pub_year)

analysis_sets <- bind_rows(
  hr_one |> mutate(set = "all matched HRs"),
  hr_one |> filter(comparison == "C1", no_atg_recorded) |> mutate(set = "no ATG recorded in either arm"),
  # Added after the first results were seen: the cohort rule lets a subset
  # report stand in for its parent study when the parent has no HR recorded
  # (Abedin 2025, age >= 70 subset of BMT CTN 1703, OS HR 0.08).
  hr_one |> filter(coalesce(primary_for_cohort, "") != "N") |> mutate(set = "excluding non-primary cohort reports")
) |>
  nest(data = -c(comparison, outcome, set))

priors_hr <- c(
  prior(normal(0, 2.5), class = Intercept),
  prior(student_t(3, 0, 1), class = sd)
)

set.seed(4127)
analysis_sets$seed <- sample.int(10000, nrow(analysis_sets))

template <- brm(
  yi | se(sei) ~ 1 + (1 | study), data = analysis_sets$data[[1]], prior = priors_hr,
  chains = 0, backend = "cmdstanr", refresh = 0
)

fit_one <- function(data, seed) {
  fit <- update(template, newdata = data, chains = 4, iter = 4000, warmup = 1000, seed = seed,
                control = list(adapt_delta = 0.999, max_treedepth = 14), refresh = 0, recompile = FALSE)
  draws <- as_draws_df(fit)
  hr_draws <- exp(draws$b_Intercept)
  reml <- rma(yi, sei = sei, data = data, method = "REML")
  diag <- summary(fit)
  tibble(
    k = nrow(data), k_rct = sum(data$study_design == "RCT"), k_adjusted = sum(data$adjusted),
    hr = median(hr_draws), hr_lo = quantile(hr_draws, 0.025), hr_hi = quantile(hr_draws, 0.975),
    p_hr_below_1 = mean(hr_draws < 1),
    tau = median(draws$sd_study__Intercept),
    tau_lo = quantile(draws$sd_study__Intercept, 0.025), tau_hi = quantile(draws$sd_study__Intercept, 0.975),
    rhat_max = max(diag$fixed$Rhat, diag$random$study$Rhat),
    ess_bulk_min = min(diag$fixed$Bulk_ESS, diag$random$study$Bulk_ESS),
    divergences = sum(subset(nuts_params(fit), Parameter == "divergent__")$Value),
    reml_hr = exp(reml$beta[1]), reml_lo = exp(reml$ci.lb), reml_hi = exp(reml$ci.ub),
    reml_tau = sqrt(reml$tau2), reml_i2 = reml$I2
  )
}

hr_results <- analysis_sets |>
  mutate(res = map2(data, seed, fit_one)) |>
  select(-data, -seed) |>
  unnest(res)

dir.create("audit", showWarnings = FALSE)
write_csv(mutate(hr_results, across(where(is.double), \(x) round(x, 3))), "audit/hr_exploratory_2026-11-10.csv")
write_csv(
  hr_one |> select(comparison, outcome, study_id, first_author, pub_year, study_design, cohort_id,
                   arm_id, ref_arm, side, timepoint, hr_adjusted, hr, lo, hi, yi, sei, pair_n,
                   atg_used, ref_atg_used, no_atg_recorded, ci_asymmetric),
  "audit/hr_exploratory_inputs_2026-11-10.csv"
)
