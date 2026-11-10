# Refit cascade after removing duplicate entry 51 (= study 50, Barkhordar 2022)
# from the C1 relapse-related mortality (RRM) model set (DECISIONS.md,
# 2026-11-10). Study 51 entered no other model, so only C1 RRM analyses change.
# Follows the precedent of scripts/run-stageB-cascade.R and
# scripts/run-stageC-tables.R (duplicate study 401): stale fits are moved
# aside, the resumable scripts refit only what is missing, and only the C1 RRM
# rows of the derived tables are rewritten, so no other reported number moves
# by Monte Carlo noise.
# Run once from project root: source("scripts/run-rrm-cascade-duplicate-removal.R")

suppressPackageStartupMessages({
  library(tidyverse)
  library(brms)
  library(metafor)
})
# RoBMA is called by namespace only: attaching it masks brms::prior()

fit_dir <- "_fits_rs"
stale_dir <- file.path(fit_dir, "_stale_duplicate_removal_2026-11-10")
dir.create(file.path(stale_dir, "robma_adj"), recursive = TRUE, showWarnings = FALSE)
stale <- c("rs_c1_rrm_m1.rds", "rs_c1_rrm_m2.rds", "fe_c1_rrm_m1.rds", "fe_c1_rrm_m2.rds",
           "rep_donor_metareg_c1_rrm.rds", "rep_donor_matched_c1_rrm.rds", "rep_m1_matched_c1_rrm.rds",
           "robma_adj/robma_c1_rrm.csv.rds")
for (f in stale) {
  if (file.exists(file.path(fit_dir, f))) file.rename(file.path(fit_dir, f), file.path(stale_dir, f))
}

rrm <- read_csv("data/models/data_c1_rrm.csv", show_col_types = FALSE)
stopifnot(!51 %in% rrm$study_id, nrow(rrm) == 33)

# ── Stage B: primary and fixed-intercept refits (existing resumable scripts) ─
run_keys <- function(script, keys) {
  env <- new.env()
  env$keys <- keys
  source(script, local = env)
  invisible(env)
}
run_keys("scripts/refit-random-slope.R", c("c1_rrm_m1", "c1_rrm_m2"))
run_keys("scripts/refit-fixed-intercept.R", c("c1_rrm_m1", "c1_rrm_m2"))

# ── Shared helpers (specifications copied from refit-reporting-suite.R and
#    refit-final-consistency.R) ──────────────────────────────────────────────
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
    d |> transmute(study_id, tp_early, ptcy_binary = 1, events_n = ptcy_e, denom_n = ptcy_n,
                   steroid_pct = ptcy_steroid_pct, across(all_of(covs))),
    d |> transmute(study_id, tp_early, ptcy_binary = 0, events_n = comp_e, denom_n = comp_n,
                   steroid_pct = comp_steroid_pct, across(all_of(covs)))
  ) |> filter(!is.na(events_n)) |> mutate(study_id = factor(study_id))
}
or_summary <- function(fit) {
  dr <- as_draws_df(fit)
  or <- exp(dr$b_ptcy_binary)
  list(k = n_distinct(fit$data$study_id), n_total = sum(fit$data$denom_n),
       or_med = median(or), or_lo = unname(quantile(or, .025)), or_hi = unname(quantile(or, .975)),
       tau = median(dr$sd_study_id__ptcy_binary), div = num_div(fit), draws = dr)
}
# Fits are cached so that the script can be re-run after an interruption
cached_fit <- function(file, fit_fun) {
  path <- file.path(fit_dir, file)
  if (file.exists(path)) return(readRDS(path))
  fit <- fit_fun()
  saveRDS(fit, path)
  fit
}
set.seed(7392)
new_seeds <- sample.int(10000, 3)

# ── Donor-type confounding (meta-regression and donor-matched restriction) ──
arms <- read_csv("data/arms.csv", show_col_types = FALSE)
a_haplo <- arms |> transmute(arm_id, haplo = suppressWarnings(as.numeric(donor_haplo_pct)))
wide <- rrm |>
  left_join(a_haplo, by = c("ptcy_arm_id" = "arm_id")) |>
  left_join(a_haplo, by = c("comp_arm_id" = "arm_id"), suffix = c("_ptcy", "_comp")) |>
  mutate(d_haplo = haplo_ptcy - haplo_comp)
dat_mr <- mk_long(wide, covs = "d_haplo") |>
  filter(!is.na(d_haplo)) |>
  mutate(d_haplo_c = d_haplo - mean(d_haplo))
fit_mr <- cached_fit("rep_donor_metareg_c1_rrm.rds", \() fit_m1(dat_mr, new_seeds[1], extra_rhs = "+ d_haplo_c"))
matched_donor <- wide |> filter(!is.na(d_haplo), abs(d_haplo) <= 15)
fit_dm <- cached_fit("rep_donor_matched_c1_rrm.rds", \() fit_m1(mk_long(matched_donor), new_seeds[2]))

s_mr <- or_summary(fit_mr)
s_dm <- or_summary(fit_dm)
donor <- read_csv("data/models/donor_confounding.csv", show_col_types = FALSE)
i_mr <- which(donor$outcome == "c1_rrm" & str_detect(donor$analysis, "meta-regression"))
i_dm <- which(donor$outcome == "c1_rrm" & str_detect(donor$analysis, "donor-matched"))
stopifnot(length(i_mr) == 1, length(i_dm) == 1)
donor[i_mr, c("k", "n_excluded_missing", "or_med", "or_lo", "or_hi", "beta_dhaplo", "beta_dhaplo_lo",
              "beta_dhaplo_hi", "divergences")] <- list(
  s_mr$k, sum(is.na(wide$d_haplo)), s_mr$or_med, s_mr$or_lo, s_mr$or_hi,
  median(s_mr$draws$b_d_haplo_c), quantile(s_mr$draws$b_d_haplo_c, .025),
  quantile(s_mr$draws$b_d_haplo_c, .975), s_mr$div)
donor[i_dm, c("k", "n_excluded_missing", "or_med", "or_lo", "or_hi", "divergences", "tau_slope")] <- list(
  nrow(matched_donor), sum(is.na(wide$d_haplo)), s_dm$or_med, s_dm$or_lo, s_dm$or_hi, s_dm$div, s_dm$tau)
write_csv(donor, "data/models/donor_confounding.csv")

# ── M1 on the M2 (steroid complete-case) subset ────────────────────────────
fit_ms <- cached_fit("rep_m1_matched_c1_rrm.rds", \() fit_m1(mk_long(rrm) |> filter(!is.na(steroid_pct)), new_seeds[3]))

# ── Table 2 rows, with prediction intervals for the two refitted models ────
s_m1 <- or_summary(readRDS(file.path(fit_dir, "rs_c1_rrm_m1.rds")))
s_m2 <- or_summary(readRDS(file.path(fit_dir, "rs_c1_rrm_m2.rds")))
s_ms <- or_summary(fit_ms)
pred_int <- function(s, seed) {
  set.seed(seed)
  unname(quantile(exp(s$draws$b_ptcy_binary + rnorm(nrow(s$draws), 0, s$draws$sd_study_id__ptcy_binary)),
                  c(.025, .975)))
}
pi_m1 <- pred_int(s_m1, 5518)
pi_m2 <- pred_int(s_m2, 5519)

t2 <- read_csv("data/models/Table2_setB.csv", show_col_types = FALSE)
set_t2 <- function(t2, model, s, pi) {
  i <- which(t2$slug == "c1_rrm" & t2$model == model)
  stopifnot(length(i) == 1)
  t2[i, c("k", "n_total", "or_median", "ci_low", "ci_high", "tau", "source", "pi_low", "pi_high")] <- list(
    s$k, s$n_total, s$or_med, s$or_lo, s$or_hi, s$tau,
    "random-slope refit 2026-11-10 after removal of duplicate entry 51", pi[1], pi[2])
  t2
}
t2 <- t2 |> set_t2("m1", s_m1, pi_m1) |> set_t2("m2_steroid", s_m2, pi_m2)
write_csv(t2, "data/models/Table2_setB.csv")

matched <- read_csv("data/models/m1_m2_matched.csv", show_col_types = FALSE)
set_matched <- function(d, model, s) {
  i <- which(d$outcome == "C1 Relapse-related mortality" & d$model == model)
  stopifnot(length(i) == 1)
  d[i, c("k", "n_total", "or_med", "or_lo", "or_hi", "tau_slope", "divergences")] <- list(
    s$k, s$n_total, s$or_med, s$or_lo, s$or_hi, s$tau, s$div)
  d
}
matched <- matched |>
  set_matched("M1 full set", s_m1) |>
  set_matched("M1 matched set", s_ms) |>
  set_matched("M2", s_m2)
write_csv(matched, "data/models/m1_m2_matched.csv")

# ── Fixed-intercept sensitivity table rows ─────────────────────────────────
fe <- read_csv(file.path(fit_dir, "fe_summary.csv"), show_col_types = FALSE)
fe_tab <- read_csv("data/models/fe_sensitivity_setB.csv", show_col_types = FALSE)
for (m in c("m1", "m2_steroid")) {
  key <- if (m == "m1") "c1_rrm_m1" else "c1_rrm_m2"
  rep <- if (m == "m1") s_m1 else s_m2
  f <- fe[fe$key == key, ]
  i <- which(fe_tab$key == key)
  stopifnot(nrow(f) == 1, length(i) == 1)
  fe_tab[i, c("k", "reported_or", "reported_lo", "reported_hi", "reported_tau", "fe_or", "fe_lo", "fe_hi",
              "fe_tau", "abs_log_or_shift")] <- list(
    f$k, round(rep$or_med, 3), round(rep$or_lo, 3), round(rep$or_hi, 3), round(rep$tau, 3),
    round(f$or_med, 3), round(f$or_lo, 3), round(f$or_hi, 3), round(f$tau_slope, 3),
    round(abs(log(f$or_med) - log(rep$or_med)), 3))
}
write_csv(fe_tab, "data/models/fe_sensitivity_setB.csv")

# ── Frequentist REML concordance row and funnel-plot tests ─────────────────
es <- escalc(measure = "OR", ai = ptcy_e, n1i = ptcy_n, ci = comp_e, n2i = comp_n,
             data = rrm, add = 0.5, to = "only0")
reml <- rma(es)
freq <- read_csv("data/models/freq_results_setB.csv", show_col_types = FALSE)
i <- which(freq$slug == "c1_rrm")
stopifnot(length(i) == 1)
freq[i, c("k", "freq_or", "freq_lo", "freq_hi", "I2", "tau_freq", "Q_p")] <- list(
  reml$k, exp(reml$beta[1]), exp(reml$ci.lb), exp(reml$ci.ub), reml$I2, sqrt(reml$tau2), reml$QEp)
write_csv(freq, "data/models/freq_results_setB.csv")
source("scripts/recompute-pub-bias.R", local = new.env())

# ── RoBMA (seed as assigned by scripts/refit-robma-adjudicated.R: third of 17) ─
set.seed(4186)
robma_seed <- sample.int(10000, 17)[3]
robma_fit <- cached_fit("robma_adj/robma_c1_rrm.csv.rds", \() {
  RoBMA::RoBMA(yi = es$yi, vi = es$vi, measure = "OR", seed = robma_seed, parallel = TRUE)
})
rs <- summary(robma_fit)
robma_row <- tibble(
  key = "c1_rrm.csv", k = nrow(es),
  or_mean = exp(rs$estimates["mu", "Mean"]), or_lo = exp(rs$estimates["mu", "0.025"]),
  or_hi = exp(rs$estimates["mu", "0.975"]),
  bf_effect = as.numeric(rs$inclusion_components["Effect", "inclusion_BF"]),
  bf_bias = as.numeric(rs$inclusion_components["Publication Bias", "inclusion_BF"]),
  postprob_effect = as.numeric(rs$inclusion_components["Effect", "post_prob"]),
  postprob_bias = as.numeric(rs$inclusion_components["Publication Bias", "post_prob"]),
  rhat_max = max(rs$estimates[, "R_hat"], na.rm = TRUE), ess_min = min(rs$estimates[, "ESS"], na.rm = TRUE)
)
robma_tab <- read_csv(file.path(fit_dir, "robma_adj", "robma_adj_summary.csv"), show_col_types = FALSE)
robma_tab <- rows_update(robma_tab, robma_row, by = "key")
write_csv(robma_tab, file.path(fit_dir, "robma_adj", "robma_adj_summary.csv"))

# ── Timepoint tables: the restricted (preferred-timepoint) RRM set does not
#    contain study 51 (a fallback-timepoint row), so only the full-model
#    columns and the fallback coefficient change ────────────────────────────
tp <- read_csv("data/models/timepoint_sensitivity.csv", show_col_types = FALSE)
i <- which(tp$key == "c1_rrm")
stopifnot(length(i) == 1, sum(rrm$tp_early == 0) == tp$k_restricted[i])
tp[i, c("k_full", "full_or", "full_lo", "full_hi")] <- list(nrow(rrm), s_m1$or_med, s_m1$or_lo, s_m1$or_hi)
write_csv(tp, "data/models/timepoint_sensitivity.csv")
tpc <- read_csv("data/models/tp_early_coefficients.csv", show_col_types = FALSE)
i <- which(tpc$key == "c1_rrm_m1")
b <- s_m1$draws$b_tp_early
tpc[i, c("b_early_med", "b_early_lo", "b_early_hi", "pr_same_dir")] <- list(
  median(b), quantile(b, .025), quantile(b, .975), mean(b > 0))
write_csv(tpc, "data/models/tp_early_coefficients.csv")

# ── Per-outcome attrition ──────────────────────────────────────────────────
source("scripts/manuscript-counts.R")
cnt <- manuscript_counts()
flow <- read_csv("data/models/outcome_flow.csv", show_col_types = FALSE)
label_map <- c("Acute GVHD II–IV" = "Acute GVHD II-IV", "Chronic GVHD mod–severe" = "Chronic GVHD mod-severe",
               "BK virus" = "BK haemorrhagic cystitis")
flow <- flow |>
  mutate(lookup = str_c("Paired-arm records, ", comp, " ", coalesce(label_map[outcome], outcome)),
         k_new = as.numeric(cnt$value[match(lookup, cnt$quantity)]))
stopifnot(!anyNA(flow$k_new))
flow <- flow |>
  mutate(k_extracted = k_new,
         k_pooled = if_else(comp == "C1" & outcome == "Relapse-related mortality", nrow(rrm), k_pooled)) |>
  select(comp, outcome, k_extracted, k_pooled)
write_csv(flow, "data/models/outcome_flow.csv")

# ── Numbers for the manuscript ─────────────────────────────────────────────
p0 <- median(rrm$comp_e / rrm$comp_n)
rd <- function(or) (or * p0 / (1 - p0 + or * p0) - p0) * 1000
diag <- summary(readRDS(file.path(fit_dir, "rs_c1_rrm_m1.rds")))
diag_rows <- rbind(diag$fixed, diag$random$study_id)
rrm_numbers <- list(
  m1 = s_m1[c("k", "n_total", "or_med", "or_lo", "or_hi", "tau", "div")], pi_m1 = pi_m1,
  m2 = s_m2[c("k", "n_total", "or_med", "or_lo", "or_hi", "tau", "div")],
  m1_matched = s_ms[c("k", "n_total", "or_med", "or_lo", "or_hi", "tau", "div")],
  donor_metareg = c(s_mr[c("k", "or_med", "or_lo", "or_hi")],
                    beta = list(quantile(s_mr$draws$b_d_haplo_c, c(.5, .025, .975)))),
  donor_matched = s_dm[c("k", "or_med", "or_lo", "or_hi")],
  fixed_intercept = fe[fe$key %in% c("c1_rrm_m1", "c1_rrm_m2"), ],
  reml = c(k = reml$k, or = exp(reml$beta[1]), lo = exp(reml$ci.lb), hi = exp(reml$ci.ub), I2 = reml$I2),
  robma = robma_row,
  baseline_risk = p0, abs_diff = c(rd(s_m1$or_med), rd(s_m1$or_lo), rd(s_m1$or_hi)),
  diagnostics = c(max_rhat = max(diag_rows$Rhat, na.rm = TRUE), min_bulk = min(diag_rows$Bulk_ESS, na.rm = TRUE),
                  min_tail = min(diag_rows$Tail_ESS, na.rm = TRUE), divergences = s_m1$div)
)
saveRDS(rrm_numbers, file.path(fit_dir, "rrm_numbers_duplicate_removal_2026-11-10.rds"))
