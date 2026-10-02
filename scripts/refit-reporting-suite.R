# Reporting-suite refits on the post-adjudication datasets (2026-10-02):
#   1. RCT-only and observational-only M1 refits (C1 outcomes, k >= 3)
#   2. Comparator-backbone subgroups + formal backbone x PTCy interaction
#   3. Donor-type (delta-haplo) meta-regression + donor-matched restriction
#   4. OS hazard-ratio pooling + count-based M1 on the SAME HR-reporting subset
# All fits use the cmdstanr backend (rstan toolchain broken on this machine)
# and read this repo's adjudicated data. Outputs: _fits_rs/*.rds and
# data/models/{rct_only_results,comparator_backbone,donor_confounding,
# hr_same_subset}.csv
# Run: Rscript -e 'source("scripts/refit-reporting-suite.R")'

suppressPackageStartupMessages({
  library(tidyverse)
  library(brms)
  library(metafor)
})

out_dir <- path.expand("~/ptcy-infection/_fits_rs")
dir.create(out_dir, showWarnings = FALSE)

priors_rs <- c(
  prior(normal(0, 2.5), class = b),
  prior(normal(0, 1.5), class = Intercept),
  prior(student_t(3, 0, 1), class = sd)
)
num_div <- function(fit) {
  tryCatch(sum(fit$fit$diagnostic_summary()$num_divergent),
           error = function(e) rstan::get_num_divergent(fit$fit))
}
fit_m1 <- function(dat, seed, extra_rhs = "") {
  f <- as.formula(paste0("events_n | trials(denom_n) ~ ptcy_binary + tp_early ",
                         extra_rhs, "+ (1 + ptcy_binary | study_id)"))
  brm(f, data = dat, family = binomial(), prior = priors_rs,
      chains = 4, iter = 4000, warmup = 1000, seed = seed,
      control = list(adapt_delta = 0.99), refresh = 0, backend = "cmdstanr")
}
mk_long <- function(d, covs = NULL) {
  bind_rows(
    d |> transmute(study_id, tp_early, ptcy_binary = 1,
                   events_n = ptcy_e, denom_n = ptcy_n, across(all_of(covs))),
    d |> transmute(study_id, tp_early, ptcy_binary = 0,
                   events_n = comp_e, denom_n = comp_n, across(all_of(covs)))
  ) |> filter(!is.na(events_n)) |> mutate(study_id = factor(study_id))
}
summ_or <- function(fit, key, k, note = NA_character_) {
  dr <- as_draws_df(fit)
  or <- exp(dr$b_ptcy_binary)
  tibble(outcome = key, k = k, or_med = median(or), or_lo = quantile(or, .025),
         or_hi = quantile(or, .975),
         tau_slope = median(dr$sd_study_id__ptcy_binary),
         divergences = num_div(fit), note = note)
}
summ <- function(x) paste(round(x, 3), collapse = " ")

studies <- read_csv("data/studies.csv", show_col_types = FALSE)
arms <- read_csv("data/arms.csv", show_col_types = FALSE)
set.seed(6641)
seeds <- sample.int(10000, 60)
si <- 0
next_seed <- function() { si <<- si + 1; seeds[si] }

## ── 1. RCT-only and observational-only ─────────────────────────────
rct_ids <- studies |> filter(study_design == "RCT") |> pull(study_id)
cohort_of <- setNames(studies$cohort_id, studies$study_id)
rct_spec <- tribble(
  ~key,          ~analytic_file,
  "c1_os",       "data/analytic/C1_overall_mortality_OS_event.csv",
  "c1_agvhd",    "data/analytic/C1_aGVHD_grade_II_IV.csv",
  "c1_cgvhd_ms", "data/analytic/C1_cGVHD_moderate_severe_NIH.csv",
  "c1_nrm",      "data/analytic/C1_NRM_NRM_overall.csv",
  "c1_cmv",      "data/analytic/C1_CMV_any_reactivation.csv")

# Analytic files lack tp_early; derive it (0 = target timepoint, 1 = fallback)
target_tp <- c(c1_os = "D+365_1yr", c1_nrm = "D+365_1yr",
               c1_cgvhd_ms = "D+365_1yr", c1_agvhd = "D+100", c1_cmv = "D+100")

rct_res <- list()
for (i in seq_len(nrow(rct_spec))) {
  key <- rct_spec$key[i]
  d_all <- read_csv(rct_spec$analytic_file[i], show_col_types = FALSE) |>
    filter(!is.na(ptcy_e), !is.na(comp_e)) |>
    mutate(tp_early = as.integer(timepoint_used != target_tp[key])) |>
    mutate(cohort_id = cohort_of[as.character(study_id)]) |>
    group_by(cohort_id) |>
    slice_max(ptcy_n + comp_n, n = 1, with_ties = FALSE) |>
    ungroup()
  for (design in c("rct", "obs")) {
    d <- if (design == "rct") filter(d_all, study_id %in% rct_ids)
         else filter(d_all, !study_id %in% rct_ids)
    k <- n_distinct(d$study_id)
    out_key <- paste0(key, "_", design)
    if (k < 3) {
      rct_res[[out_key]] <- tibble(outcome = key, design = design, k = k,
                                   note = "not estimable (k < 3)")
      next
    }
    fit <- fit_m1(mk_long(d), next_seed())
    saveRDS(fit, file.path(out_dir, paste0("rep_", out_key, ".rds")))
    rct_res[[out_key]] <- summ_or(fit, key, k) |> mutate(design = design)
  }
}
rct_res <- bind_rows(rct_res)
write_csv(rct_res, "data/models/rct_only_results.csv")
cat("== RCT / observational ==\n"); print(rct_res, width = 200)

## ── 2. Comparator backbone: subgroups + interaction ────────────────
a_reg <- arms |> transmute(
  arm_id,
  backbone = case_when(mtx_used == "Y" & mmf_used != "Y" ~ "CNI+MTX",
                       mmf_used == "Y" & mtx_used != "Y" ~ "CNI+MMF",
                       mtx_used == "Y" & mmf_used == "Y" ~ "CNI+MTX+MMF",
                       TRUE ~ NA_character_))
ptcy_atg_arms <- arms |> filter(ptcy_used == "Y", atg_used == "Y") |> pull(arm_id)

bb_spec <- c("c1_os" = "data_c1_os.csv", "c1_agvhd" = "data_c1_agvhd.csv",
             "c1_cmv" = "data_c1_cmv.csv")
bb_res <- list()
for (key in names(bb_spec)) {
  d <- read_csv(file.path("data/models", bb_spec[key]), show_col_types = FALSE) |>
    left_join(a_reg, by = c("comp_arm_id" = "arm_id")) |>
    filter(!is.na(backbone)) |>
    # syntactic level names so interaction coefficient names are predictable
    mutate(backbone = factor(backbone,
                             levels = c("CNI+MTX", "CNI+MMF", "CNI+MTX+MMF"),
                             labels = c("CNI_MTX", "CNI_MMF", "CNI_MTX_MMF")))
  # subgroup refits
  for (bb in levels(d$backbone)) {
    ds <- d |> filter(backbone == bb)
    if (nrow(ds) < 3) {
      bb_res[[paste(key, bb)]] <- tibble(analysis = paste(key, "/", bb), k = nrow(ds),
                                         note = "not estimable (k < 3)")
      next
    }
    fit <- fit_m1(mk_long(ds), next_seed())
    saveRDS(fit, file.path(out_dir, paste0("rep_bb_", key, "_", bb, ".rds")))
    bb_res[[paste(key, bb)]] <- summ_or(fit, paste(key, "/", bb), nrow(ds))
  }
  # formal interaction model
  if (n_distinct(d$backbone) == 3 && nrow(d) >= 8) {
    dat <- mk_long(d, covs = "backbone")
    fit <- fit_m1(dat, next_seed(), extra_rhs = "+ backbone + ptcy_binary:backbone")
    saveRDS(fit, file.path(out_dir, paste0("rep_bb_interaction_", key, ".rds")))
    dr <- as_draws_df(fit)
    for (bb in c("CNI_MMF", "CNI_MTX_MMF")) {
      bnam <- paste0("b_ptcy_binary:backbone", bb)
      stopifnot(bnam %in% names(dr))
      ror <- exp(dr[[bnam]])
      bb_res[[paste(key, bb, "interaction")]] <- tibble(
        analysis = paste(key, "interaction: PTCy effect,", bb, "vs CNI+MTX"),
        k = n_distinct(dat$study_id), or_med = median(ror),
        or_lo = quantile(ror, .025), or_hi = quantile(ror, .975),
        tau_slope = median(dr$sd_study_id__ptcy_binary),
        divergences = num_div(fit),
        note = "ratio of odds ratios; 1 = same PTCy effect across backbones")
    }
  }
}
# C2 PTCy+ATG exclusion
c2_spec <- c("c2_agvhd" = "data_c2_agvhd.csv", "c2_cmv" = "data_c2_cmv.csv",
             "c2_os" = "data_c2_os.csv")
for (key in names(c2_spec)) {
  d <- read_csv(file.path("data/models", c2_spec[key]), show_col_types = FALSE) |>
    filter(!ptcy_arm_id %in% ptcy_atg_arms)
  if (nrow(d) < 3) next
  fit <- fit_m1(mk_long(d), next_seed())
  saveRDS(fit, file.path(out_dir, paste0("rep_", key, "_no_ptcy_atg.rds")))
  bb_res[[paste0(key, "_noatg")]] <- summ_or(fit, paste(key, "excluding PTCy+ATG-arm studies"), nrow(d))
}
bb_res <- bind_rows(bb_res)
write_csv(bb_res, "data/models/comparator_backbone.csv")
cat("== Backbone ==\n"); print(bb_res, width = 220)

## ── 3. Donor-type confounding ──────────────────────────────────────
a_haplo <- arms |> transmute(arm_id, haplo = suppressWarnings(as.numeric(donor_haplo_pct)))
donor_spec <- c("c1_os" = "data_c1_os.csv", "c1_rrm" = "data_c1_rrm.csv",
                "c1_agvhd" = "data_c1_agvhd.csv", "c1_cmv" = "data_c1_cmv.csv",
                "c1_nrm" = "data_c1_nrm.csv")
donor_res <- list()
for (key in names(donor_spec)) {
  wide <- read_csv(file.path("data/models", donor_spec[key]), show_col_types = FALSE) |>
    left_join(a_haplo, by = c("ptcy_arm_id" = "arm_id")) |>
    left_join(a_haplo, by = c("comp_arm_id" = "arm_id"), suffix = c("_ptcy", "_comp")) |>
    mutate(d_haplo = haplo_ptcy - haplo_comp)
  n_missing <- sum(is.na(wide$d_haplo))
  # meta-regression
  dat <- mk_long(wide, covs = "d_haplo") |>
    filter(!is.na(d_haplo)) |>
    mutate(d_haplo_c = d_haplo - mean(d_haplo))
  fit <- fit_m1(dat, next_seed(), extra_rhs = "+ d_haplo_c")
  saveRDS(fit, file.path(out_dir, paste0("rep_donor_metareg_", key, ".rds")))
  dr <- as_draws_df(fit)
  or <- exp(dr$b_ptcy_binary)
  donor_res[[paste0(key, "_metareg")]] <- tibble(
    outcome = key, analysis = "M1 + delta-haplo meta-regression",
    k = n_distinct(dat$study_id), n_excluded_missing = n_missing,
    or_med = median(or), or_lo = quantile(or, .025), or_hi = quantile(or, .975),
    beta_dhaplo = median(dr$b_d_haplo_c),
    beta_dhaplo_lo = quantile(dr$b_d_haplo_c, .025),
    beta_dhaplo_hi = quantile(dr$b_d_haplo_c, .975), divergences = num_div(fit))
  # donor-matched restriction
  ds <- wide |> filter(!is.na(d_haplo), abs(d_haplo) <= 15)
  if (nrow(ds) >= 3) {
    fit2 <- fit_m1(mk_long(ds), next_seed())
    saveRDS(fit2, file.path(out_dir, paste0("rep_donor_matched_", key, ".rds")))
    donor_res[[paste0(key, "_matched")]] <- summ_or(fit2, key, nrow(ds)) |>
      mutate(analysis = "M1 donor-matched (|delta| <= 15pp)",
             n_excluded_missing = n_missing)
  }
}
donor_res <- bind_rows(donor_res)
write_csv(donor_res, "data/models/donor_confounding.csv")
cat("== Donor ==\n"); print(donor_res, width = 220)

## ── 4. OS HR pooling + same-subset count-based M1 ──────────────────
oc <- read_csv("data/outcomes.csv", show_col_types = FALSE)
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
        TRUE ~ "unresolved"),
      tp_match = timepoint == timepoint_used,
      tp_dist = abs(as.numeric(timepoint_days_numeric) -
                      as.numeric(str_extract(timepoint_used, "\\d+")))) |>
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
    study_id = factor(study_id))

write_csv(hr_one |> select(comp, study_id, timepoint, hr_adjusted, orient,
                           hr_value, hr_ci_lower, hr_ci_upper),
          "data/models/hr_sensitivity_os.csv")

priors_hr <- c(prior(normal(0, 2.5), class = Intercept),
               prior(student_t(3, 0, 1), class = sd))
hr_res <- list()
for (cp in c("C1", "C2")) {
  hr_cp <- hr_one |> filter(comp == cp)
  fit <- brm(yi | se(sei) ~ 1 + (1 | study_id), data = hr_cp, prior = priors_hr,
             chains = 4, iter = 4000, warmup = 1000, seed = next_seed(),
             control = list(adapt_delta = 0.999, max_treedepth = 14),
             refresh = 0, backend = "cmdstanr")
  saveRDS(fit, file.path(out_dir, paste0("rep_hr_os_", tolower(cp), ".rds")))
  dr <- as_draws_df(fit)
  hr <- exp(dr$b_Intercept)
  # same-subset count-based M1 (studies with both an HR and valid counts)
  ana <- read_csv(sprintf("data/models/data_%s_os.csv", tolower(cp)),
                  show_col_types = FALSE) |>
    filter(study_id %in% hr_cp$study_id) |>
    filter(!is.na(ptcy_e), !is.na(comp_e))
  fit_c <- fit_m1(mk_long(ana), next_seed())
  saveRDS(fit_c, file.path(out_dir, paste0("rep_count_os_hrsubset_", tolower(cp), ".rds")))
  drc <- as_draws_df(fit_c)
  orc <- exp(drc$b_ptcy_binary)
  hr_res[[cp]] <- tibble(
    comp = cp, k_hr = nrow(hr_cp),
    hr_med = median(hr), hr_lo = quantile(hr, .025), hr_hi = quantile(hr, .975),
    tau_hr = median(dr$sd_study_id__Intercept),
    k_count_same_subset = n_distinct(ana$study_id),
    or_same_subset = median(orc), or_lo = quantile(orc, .025),
    or_hi = quantile(orc, .975),
    note = paste0("HR pool vs count-based M1 restricted to the same ",
                  "HR-reporting studies"))
}
hr_res <- bind_rows(hr_res)
write_csv(hr_res, "data/models/hr_same_subset.csv")
cat("== HR same-subset ==\n"); print(hr_res, width = 220)
cat("done\n")