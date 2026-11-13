# EXPLORATORY, POST HOC (see DECISIONS.md, 2026-11-13): two-stage pooling of
# C1 overall survival on the log hazard-ratio scale, to include studies the
# observed-counts rule excludes. Not in the manuscript.
#
# One log HR (PTCy vs C1 comparator) per study, from the first available of:
#   1. a reported HR with 95% CI whose reference arm is a C1 arm on the other
#      side of the contrast (adjusted preferred, then timepoint nearest one
#      year, then larger arm pair) -- construction of hr-exploratory-os-nrm.R;
#   2. Kaplan-Meier mortality estimates with 95% CIs in both arms at the same
#      timepoint (nearest one year): log(-log S_P) - log(-log S_C), each SE from
#      the CI transformed to the complementary log-log scale;
#   3. observed counts in both arms at the same timepoint (input classes found
#      in the pooled count models): same contrast, delta-method SE
#      var = (1 - S) / (n S (log S)^2), 0.5 added to events and 1 to n when an
#      arm has 0 or n events.
# The survival percentage field stores mortality (100 - survival): 132 of 135
# rows with both a count and a percentage agree on that reading.
# Cohort deduplication: the designated primary publication of each cohort
# (data/cohorts.csv) if it has an estimate, otherwise the largest other
# publication with one (flagged).
# Not checked against source papers: HR direction and adjustment, KM
# direction for values above 60%, CI methods.
# Run from project root: source("scripts/hr-twostage-os-c1.R")

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(purrr)
  library(tidyr)
  library(brms)
  library(metafor)
})

# Outcome settings. Defaults are overall survival; set these before sourcing to
# run another outcome (CMV, 2026-11-13: category "CMV", subtype
# "any_reactivation", target 100 days, tag "cmv", seed 3391, and
# ts_ptcy_arm = c("4" = 4) to use Goldsmith 2021 SibCy vs SibCNI). For a
# cumulative-incidence outcome the contrast is a ratio of cumulative
# (subdistribution) hazards; reported HRs may be cause-specific.
if (!exists("ts_category")) ts_category <- "overall_mortality"
if (!exists("ts_subtype")) ts_subtype <- "OS_event"
if (!exists("ts_target_days")) ts_target_days <- 365
if (!exists("ts_tag")) ts_tag <- "os"
if (!exists("ts_seed")) ts_seed <- 5583
# named vector: study_id -> the PTCy arm to use when a study has several
if (!exists("ts_ptcy_arm")) ts_ptcy_arm <- integer(0)

num <- function(x) suppressWarnings(as.numeric(x))
cloglog_s <- function(s) log(-log(s))
z <- qnorm(0.975)

studies <- read_csv("data/studies.csv", show_col_types = FALSE, guess_max = 5000)
arms <- read_csv("data/arms.csv", show_col_types = FALSE, guess_max = 5000)
outcomes <- read_csv("data/outcomes.csv", show_col_types = FALSE, guess_max = 5000)
cohorts <- read_csv("data/cohorts.csv", show_col_types = FALSE, col_types = cols(.default = "c")) |>
  mutate(primary_publication_study_id = num(primary_publication_study_id))
studies <- mutate(studies, cohort_id = as.character(cohort_id))

c1_arms <- arms |>
  filter(comparison_1_eligible == "Y", arm_role %in% c("PTCy_arm", "comparator_arm")) |>
  transmute(study_id, arm_id, side = if_else(arm_role == "PTCy_arm", "ptcy", "comp"), n_arm = num(n_patients)) |>
  filter(!(side == "ptcy" & as.character(study_id) %in% names(ts_ptcy_arm) &
             arm_id != ts_ptcy_arm[as.character(study_id)]))

os <- outcomes |>
  filter(outcome_category == ts_category, outcome_subtype == ts_subtype) |>
  select(-cohort_id) |>
  inner_join(c1_arms, by = c("study_id", "arm_id")) |>
  mutate(tp_days = num(timepoint_days_numeric), pct = num(cumulative_incidence_pct),
         lo = num(ci_lower_pct), hi = num(ci_upper_pct),
         e = num(event_count), n = num(denominator_n))

universe <- os |>
  summarise(paired = any(side == "ptcy") && any(side == "comp"), .by = study_id) |>
  filter(paired) |>
  pull(study_id)

# 1. reported hazard ratios -------------------------------------------------
hr_src <- os |>
  mutate(hr = num(hr_value), hlo = num(hr_ci_lower), hhi = num(hr_ci_upper), ref_arm = num(hr_comparator_arm_id)) |>
  filter(!is.na(hr), !is.na(hlo), !is.na(hhi), hr > 0, hlo > 0, hhi > hlo) |>
  inner_join(c1_arms |> select(study_id, ref_arm = arm_id, ref_side = side, ref_n = n_arm),
             by = c("study_id", "ref_arm")) |>
  filter(ref_side != side) |>
  mutate(yi = if_else(side == "ptcy", log(hr), -log(hr)),
         sei = (log(hhi) - log(hlo)) / (2 * z),
         adjusted = grepl("^adj", tolower(coalesce(hr_adjusted, ""))),
         pair_n = n_arm + ref_n) |>
  arrange(desc(adjusted), coalesce(abs(tp_days - ts_target_days), 1e6), desc(pair_n)) |>
  slice_head(n = 1, by = study_id) |>
  transmute(study_id, source = "reported HR", yi, sei, timepoint, adjusted, pair_n,
            km_high_mortality = FALSE)

# arm pairs at the same timepoint, largest pair first
pair_up <- function(d) {
  inner_join(d |> filter(side == "ptcy"), d |> filter(side == "comp"),
             by = c("study_id", "timepoint", "tp_days"), suffix = c("_p", "_c"),
             relationship = "many-to-many") |>
    mutate(pair_n = coalesce(n_p, n_arm_p) + coalesce(n_c, n_arm_c)) |>
    arrange(coalesce(abs(tp_days - ts_target_days), 1e6), desc(pair_n)) |>
    slice_head(n = 1, by = study_id)
}

# 2. Kaplan-Meier mortality with CIs ----------------------------------------
km_src <- os |>
  filter(!is.na(pct), !is.na(lo), !is.na(hi), lo > 0, hi < 100, lo <= pct, pct <= hi) |>
  distinct(study_id, arm_id, timepoint, .keep_all = TRUE) |>
  select(study_id, arm_id, side, timepoint, tp_days, pct, lo, hi, n, n_arm) |>
  pair_up() |>
  mutate(th_p = cloglog_s(1 - pct_p / 100), th_c = cloglog_s(1 - pct_c / 100),
         se_p = (cloglog_s(1 - hi_p / 100) - cloglog_s(1 - lo_p / 100)) / (2 * z),
         se_c = (cloglog_s(1 - hi_c / 100) - cloglog_s(1 - lo_c / 100)) / (2 * z)) |>
  transmute(study_id, source = "Kaplan-Meier with CI", yi = th_p - th_c, sei = sqrt(se_p^2 + se_c^2),
            timepoint, adjusted = FALSE, pair_n, km_high_mortality = pct_p > 60 | pct_c > 60)

# 3. observed counts --------------------------------------------------------
count_classes <- c("observed_count", "percentage_derived_count", "other_reconstruction")
cnt_src <- os |>
  filter(input_class %in% count_classes, !is.na(e), !is.na(n), n > 0, e <= n) |>
  distinct(study_id, arm_id, timepoint, .keep_all = TRUE) |>
  select(study_id, arm_id, side, timepoint, tp_days, e, n, n_arm) |>
  pair_up() |>
  mutate(fix = e_p %in% c(0, n_p) | e_c %in% c(0, n_c),
         across(c(e_p, e_c), \(x) if_else(fix, x + 0.5, x)),
         across(c(n_p, n_c), \(x) if_else(fix, x + 1, x)),
         s_p = 1 - e_p / n_p, s_c = 1 - e_c / n_c,
         v_p = (1 - s_p) / (n_p * s_p * log(s_p)^2), v_c = (1 - s_c) / (n_c * s_c * log(s_c)^2)) |>
  transmute(study_id, source = "observed counts", yi = cloglog_s(s_p) - cloglog_s(s_c), sei = sqrt(v_p + v_c),
            timepoint, adjusted = FALSE, pair_n, km_high_mortality = FALSE)

# one estimate per study, then one study per cohort ---------------------------
build <- function(priority) {
  bind_rows(hr_src, km_src, cnt_src) |>
    filter(study_id %in% universe, source %in% priority, is.finite(yi), is.finite(sei), sei > 0) |>
    mutate(rank = match(source, priority)) |>
    arrange(rank) |>
    slice_head(n = 1, by = study_id) |>
    left_join(select(studies, study_id, first_author, pub_year, study_design, cohort_id), by = "study_id") |>
    left_join(select(cohorts, cohort_id, primary_publication_study_id), by = "cohort_id") |>
    mutate(cohort_key = coalesce(as.character(cohort_id), paste0("study_", study_id)),
           designated_primary = is.na(primary_publication_study_id) | study_id == primary_publication_study_id) |>
    arrange(desc(designated_primary), desc(pair_n)) |>
    slice_head(n = 1, by = cohort_key) |>
    mutate(study = factor(study_id))
}

main <- build(c("reported HR", "Kaplan-Meier with CI", "observed counts"))
sets <- list(
  "Main: reported HR > KM with CI > counts" = main,
  "Designated cohort-primary publications only" = filter(main, designated_primary),
  "Excluding KM-derived estimates with mortality > 60% in an arm" = filter(main, !km_high_mortality),
  "Unadjusted only: KM with CI > counts (no reported HRs)" = build(c("Kaplan-Meier with CI", "observed counts")),
  "Randomised trials only" = filter(main, study_design == "RCT")
)

priors_hr <- c(prior(normal(0, 2.5), class = Intercept), prior(student_t(3, 0, 1), class = sd))
set.seed(ts_seed)
seeds <- sample.int(10000, length(sets))
template <- brm(yi | se(sei) ~ 1 + (1 | study), data = main, prior = priors_hr,
                chains = 0, backend = "cmdstanr", refresh = 0, silent = 2)

fit_one <- function(d, seed) {
  if (nrow(d) < 3) return(tibble(k = nrow(d), note = "not estimable (k < 3)"))
  fit <- update(template, newdata = d, chains = 4, iter = 4000, warmup = 1000, seed = seed,
                control = list(adapt_delta = 0.999, max_treedepth = 14), refresh = 0, recompile = FALSE, silent = 2)
  dr <- as_draws_df(fit); h <- exp(dr$b_Intercept); sm <- summary(fit)
  set.seed(seed)
  h_new <- exp(rnorm(nrow(dr), dr$b_Intercept, dr$sd_study__Intercept))
  reml <- rma(yi, sei = sei, data = d, method = "REML")
  tibble(k = nrow(d), k_rct = sum(d$study_design == "RCT"),
         k_reported_hr = sum(d$source == "reported HR"), k_km = sum(d$source == "Kaplan-Meier with CI"),
         k_counts = sum(d$source == "observed counts"), k_substitute_publication = sum(!d$designated_primary),
         hr = median(h), hr_lo = quantile(h, .025), hr_hi = quantile(h, .975), p_hr_below_1 = mean(h < 1),
         pi_lo = quantile(h_new, .025), pi_hi = quantile(h_new, .975), tau = median(dr$sd_study__Intercept),
         reml_hr = exp(reml$b[1]), reml_lo = exp(reml$ci.lb), reml_hi = exp(reml$ci.ub), reml_i2 = reml$I2,
         rhat_max = max(sm$fixed$Rhat, sm$random$study$Rhat),
         divergences = sum(subset(nuts_params(fit), Parameter == "divergent__")$Value),
         note = NA_character_)
}

twostage_results <- imap(sets, \(d, nm) fit_one(d, seeds[match(nm, names(sets))]) |> mutate(set = nm, .before = 1)) |>
  list_rbind()
twostage_universe <- length(universe)

write_csv(mutate(twostage_results, across(where(is.double), \(x) round(x, 3))),
          sprintf("audit/hr_twostage_%s_c1_results_2026-11-13.csv", ts_tag))
write_csv(main |> select(study_id, first_author, pub_year, study_design, cohort_id, designated_primary,
                         source, timepoint, adjusted, yi, sei, pair_n, km_high_mortality) |>
            mutate(hr = round(exp(yi), 3), across(c(yi, sei), \(x) round(x, 4))),
          sprintf("audit/hr_twostage_%s_c1_inputs_2026-11-13.csv", ts_tag))
print(twostage_results, width = Inf)
