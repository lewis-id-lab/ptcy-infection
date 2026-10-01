# CMV outcome-definition sensitivity (reviewer bullet: any reactivation vs
# clinically significant CMV infection behave differently under letermovir).
#
# Builds a paired-arm dataset for clinically significant CMV (csCMV) from the
# extraction database — one row per study at the preferred timepoint (day +100
# when available), event counts back-calculated from percentages where counts
# are missing, per the main pipeline's conventions — and fits the M1
# random-slope specification. Compared against the reported any-reactivation
# estimate. C1 comparators only (csCMV reporting in C2 is too sparse).
#
# Outputs: _fits_rs/cmv_cscmv.rds and data/models/cmv_definitions.csv.

suppressPackageStartupMessages({
  library(tidyverse)
  library(brms)
})

out_dir <- path.expand("~/ptcy-infection/_fits_rs")
dir.create(out_dir, showWarnings = FALSE)

oc <- read_csv("data/outcomes.csv", show_col_types = FALSE)
arms <- read_csv("data/arms.csv", show_col_types = FALSE)
studies <- read_csv("data/studies.csv", show_col_types = FALSE)

cs <- oc |>
  filter(outcome_category == "CMV", outcome_subtype == "clinically_significant_csCMV") |>
  mutate(across(c(event_count, denominator_n, cumulative_incidence_pct,
                  proportion_reported_pct),
                \(x) suppressWarnings(as.numeric(x)))) |>
  inner_join(arms |> select(arm_id, arm_role, comparison_1_eligible), by = "arm_id") |>
  filter(comparison_1_eligible == "Y")

# event count: direct, else back-calculate from percentage x denominator
cs <- cs |>
  mutate(events = case_when(
    !is.na(event_count) ~ event_count,
    !is.na(denominator_n) & !is.na(cumulative_incidence_pct) ~
      round(denominator_n * cumulative_incidence_pct / 100),
    !is.na(denominator_n) & !is.na(proportion_reported_pct) ~
      round(denominator_n * proportion_reported_pct / 100),
    TRUE ~ NA_real_))

# one row per study x arm: prefer D+100, then the primary timepoint
paired <- cs |>
  filter(!is.na(events), !is.na(denominator_n)) |>
  arrange(study_id, arm_role, timepoint != "D+100", is_primary_timepoint != "Y") |>
  group_by(study_id, arm_role) |> slice(1) |> ungroup() |>
  pivot_wider(id_cols = study_id, names_from = arm_role,
              values_from = c(events, denominator_n, timepoint),
              names_glue = "{ifelse(arm_role == 'PTCy_arm', 'ptcy', 'comp')}_{.value}") |>
  filter(!is.na(ptcy_events), !is.na(comp_events))

cat("csCMV paired studies:", nrow(paired), "\n")
print(paired |> left_join(studies |> select(study_id, first_author, pub_year), by = "study_id") |>
        select(study_id, first_author, pub_year, ptcy_events, ptcy_denominator_n,
               comp_events, comp_denominator_n), n = Inf)

priors_rs <- c(
  prior(normal(0, 2.5), class = b),
  prior(normal(0, 1.5), class = Intercept),
  prior(student_t(3, 0, 1), class = sd)
)

out_file <- file.path(out_dir, "cmv_cscmv.rds")
if (!file.exists(out_file) && nrow(paired) >= 3) {
  cat("fitting csCMV model\n")
  dat <- bind_rows(
    paired |> transmute(study_id, ptcy_binary = 1, events_n = ptcy_events,
                        denom_n = ptcy_denominator_n),
    paired |> transmute(study_id, ptcy_binary = 0, events_n = comp_events,
                        denom_n = comp_denominator_n)
  ) |> mutate(study_id = factor(study_id))
  set.seed(4630)
  fit <- brm(events_n | trials(denom_n) ~ ptcy_binary + (1 + ptcy_binary | study_id),
             data = dat, family = binomial(), prior = priors_rs,
             chains = 4, iter = 4000, warmup = 1000,
             control = list(adapt_delta = 0.999, max_treedepth = 14), refresh = 0)
  saveRDS(fit, out_file)
}

fit <- readRDS(out_file)
dr <- as_draws_df(fit)
or_cs <- exp(dr$b_ptcy_binary)

fit_any <- readRDS(file.path(out_dir, "rs_c1_cmv_m1.rds"))
dr_any <- as_draws_df(fit_any)
or_any <- exp(dr_any$b_ptcy_binary)

res <- bind_rows(
  tibble(definition = "Clinically significant CMV infection (csCMV)",
         k = n_distinct(fit$data$study_id),
         or_med = median(or_cs), or_lo = quantile(or_cs, .025), or_hi = quantile(or_cs, .975),
         tau_slope = median(dr$sd_study_id__ptcy_binary),
         divergences = rstan::get_num_divergent(fit$fit)),
  tibble(definition = "Any CMV reactivation (reported M1)",
         k = n_distinct(fit_any$data$study_id),
         or_med = median(or_any), or_lo = quantile(or_any, .025), or_hi = quantile(or_any, .975),
         tau_slope = median(dr_any$sd_study_id__ptcy_binary), divergences = 0L)
) |> mutate(across(where(is.double), \(x) round(x, 3)))

write_csv(res, "data/models/cmv_definitions.csv")
print(res)
cat("done\n")
