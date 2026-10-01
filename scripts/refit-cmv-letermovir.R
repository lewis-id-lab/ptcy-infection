# CMV confounding analyses (reviewer bullet: adjust for CMV serostatus and
# letermovir at arm level; publication year is a weak letermovir proxy).
#
# For C1 CMV reactivation (the outcome where the claim matters):
#   (a) meta-regression on the letermovir ERA proxy (enrollment post-2018 vs
#       earlier/mixed) — arm-level, enrollment-based rather than
#       publication-year-based;
#   (b) meta-regression on directly extracted arm-level letermovir use
#       (any use vs none) on the subset where it was reported;
#   (c) meta-regression on the between-arm difference in CMV recipient
#       seropositivity (R+%), on the subset with serostatus data;
#   (d) descriptive check of the Discussion's "widespread letermovir
#       adoption" claim in the post-2020 sensitivity cohort.
#
# Outputs: _fits_rs/cmv_let_*.rds and data/models/cmv_letermovir.csv.

suppressPackageStartupMessages({
  library(tidyverse)
  library(brms)
})

p9_dir <- file.path(path.expand("~/ptcy_metaanalys"), "03_models/post_block9")
out_dir <- path.expand("~/ptcy-infection/_fits_rs")
dir.create(out_dir, showWarnings = FALSE)

arms <- read_csv("data/arms.csv", show_col_types = FALSE)
a_cov <- arms |> transmute(
  arm_id,
  let_any = case_when(letermovir_use %in% c("all_patients", "select_high_risk") ~ 1L,
                      letermovir_use == "none" ~ 0L, TRUE ~ NA_integer_),
  era_post2018 = case_when(letermovir_era_proxy == "post_2018" ~ 1L,
                           letermovir_era_proxy %in% c("pre_2018", "mixed_spans_era") ~ 0L,
                           TRUE ~ NA_integer_),
  rpos = suppressWarnings(as.numeric(cmv_recipient_pos_pct)))

d <- read_csv(file.path(p9_dir, "data_c1_cmv.csv"), show_col_types = FALSE)

mk_long <- function(d) {
  wide <- d |>
    left_join(a_cov, by = c("ptcy_arm_id" = "arm_id")) |>
    left_join(a_cov, by = c("comp_arm_id" = "arm_id"), suffix = c("_ptcy", "_comp")) |>
    mutate(d_rpos = rpos_ptcy - rpos_comp)
  bind_rows(
    wide |> transmute(study_id, tp_early, d_rpos, let_any = let_any_ptcy,
                      era_post2018 = era_post2018_ptcy, ptcy_binary = 1,
                      events_n = ptcy_e, denom_n = ptcy_n),
    wide |> transmute(study_id, tp_early, d_rpos, let_any = let_any_comp,
                      era_post2018 = era_post2018_comp, ptcy_binary = 0,
                      events_n = comp_e, denom_n = comp_n)
  ) |> mutate(study_id = factor(study_id))
}

dat <- mk_long(d)

priors_rs <- c(
  prior(normal(0, 2.5), class = b),
  prior(normal(0, 1.5), class = Intercept),
  prior(student_t(3, 0, 1), class = sd)
)

fit_one <- function(dd, rhs, file, seed) {
  if (file.exists(file)) return(invisible())
  cat("fitting:", basename(file), "\n")
  fit <- brm(as.formula(rhs), data = dd, family = binomial(), prior = priors_rs,
             chains = 4, iter = 4000, warmup = 1000, seed = seed,
             control = list(adapt_delta = 0.99, max_treedepth = 12), refresh = 0)
  saveRDS(fit, file)
}

set.seed(7712)
seeds <- sample.int(10000, 3)

base <- "events_n | trials(denom_n) ~ ptcy_binary + tp_early + (1 + ptcy_binary | study_id)"
# (a) era proxy, all studies with proxy data
d_a <- dat |> filter(!is.na(era_post2018))
fit_one(d_a, paste(base, "+ era_post2018"),
        file.path(out_dir, "cmv_let_era.rds"), seeds[1])
# (b) direct letermovir use, reported subset
d_b <- dat |> filter(!is.na(let_any))
fit_one(d_b, paste(base, "+ let_any"),
        file.path(out_dir, "cmv_let_direct.rds"), seeds[2])
# (c) serostatus difference, subset with R+% for both arms
d_c <- dat |> filter(!is.na(d_rpos)) |> mutate(d_rpos_c = d_rpos - mean(d_rpos))
fit_one(d_c, paste(base, "+ d_rpos_c"),
        file.path(out_dir, "cmv_let_rpos.rds"), seeds[3])

summ <- function(file, label, extra = NULL) {
  fit <- readRDS(file)
  dr <- as_draws_df(fit)
  or <- exp(dr$b_ptcy_binary)
  covar <- setdiff(grep("^b_", names(dr), value = TRUE),
                   c("b_ptcy_binary", "b_tp_early", "b_Intercept"))
  tibble(analysis = label, k = n_distinct(fit$data$study_id),
         or_med = median(or), or_lo = quantile(or, .025), or_hi = quantile(or, .975),
         covariate = paste(covar, collapse = ","),
         cov_beta = if (length(covar)) median(dr[[covar[1]]]) else NA_real_,
         cov_lo = if (length(covar)) quantile(dr[[covar[1]]], .025) else NA_real_,
         cov_hi = if (length(covar)) quantile(dr[[covar[1]]], .975) else NA_real_,
         divergences = rstan::get_num_divergent(fit$fit))
}

fit_base <- readRDS(file.path(out_dir, "rs_c1_cmv_m1.rds"))
dr <- as_draws_df(fit_base)
or <- exp(dr$b_ptcy_binary)
res <- bind_rows(
  tibble(analysis = "M1 reported (any reactivation)", k = n_distinct(fit_base$data$study_id),
         or_med = median(or), or_lo = quantile(or, .025), or_hi = quantile(or, .975),
         covariate = "", cov_beta = NA_real_, cov_lo = NA_real_, cov_hi = NA_real_,
         divergences = 0L),
  summ(file.path(out_dir, "cmv_let_era.rds"), "M1 + letermovir era (post-2018 enrolment)"),
  summ(file.path(out_dir, "cmv_let_direct.rds"), "M1 + arm-level letermovir use (reported subset)"),
  summ(file.path(out_dir, "cmv_let_rpos.rds"), "M1 + between-arm CMV R+% difference")
) |> mutate(across(where(is.double), \(x) round(x, 3)))

write_csv(res, "data/models/cmv_letermovir.csv")
print(res, n = Inf)

# (d) adoption check in the post-2020 sensitivity cohort
post2020 <- read_csv(file.path(p9_dir, "data_c1_cmv_post2020.csv"), show_col_types = FALSE)
adoption <- bind_rows(post2020 |> transmute(study_id, arm_id = ptcy_arm_id),
                      post2020 |> transmute(study_id, arm_id = comp_arm_id)) |>
  left_join(arms |> select(arm_id, letermovir_use, letermovir_era_proxy), by = "arm_id")
cat("\nPost-2020 CMV cohort arms:", nrow(adoption), "\n")
print(adoption |> count(letermovir_use, letermovir_era_proxy))
cat("done\n")
