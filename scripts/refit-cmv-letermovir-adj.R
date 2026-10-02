# Refit CMV letermovir/serostatus sensitivity models on the post-adjudication
# C1 CMV dataset (2026-10-02). Mirrors scripts/refit-cmv-letermovir.R, with two
# corrections: data read from this repo's adjudicated data_c1_cmv.csv, and the
# "direct letermovir use" meta-regression is reported descriptively because
# every arm with a reported status is a confirmed NON-user (no use variation),
# so the covariate is unidentifiable.
# Run: Rscript -e 'source("scripts/refit-cmv-letermovir-adj.R")'

suppressPackageStartupMessages({
  library(tidyverse)
  library(brms)
})

p9_dir <- file.path(path.expand("~/ptcy_metaanalys"), "03_models/post_block9")
out_dir <- path.expand("~/ptcy-infection/_fits_rs")

arms <- read_csv("data/arms.csv", show_col_types = FALSE)
a_cov <- arms |> transmute(
  arm_id,
  let_any = case_when(letermovir_use %in% c("all_patients", "select_high_risk") ~ 1L,
                      letermovir_use == "none" ~ 0L, TRUE ~ NA_integer_),
  era_post2018 = case_when(letermovir_era_proxy == "post_2018" ~ 1L,
                           letermovir_era_proxy %in% c("pre_2018", "mixed_spans_era") ~ 0L,
                           TRUE ~ NA_integer_),
  rpos = suppressWarnings(as.numeric(cmv_recipient_pos_pct)))

d <- read_csv("data/models/data_c1_cmv.csv", show_col_types = FALSE)

wide <- d |>
  left_join(a_cov, by = c("ptcy_arm_id" = "arm_id")) |>
  left_join(a_cov, by = c("comp_arm_id" = "arm_id"), suffix = c("_ptcy", "_comp")) |>
  mutate(d_rpos = rpos_ptcy - rpos_comp)
dat <- bind_rows(
  wide |> transmute(study_id, tp_early, d_rpos, let_any = let_any_ptcy,
                    era_post2018 = era_post2018_ptcy, ptcy_binary = 1,
                    events_n = ptcy_e, denom_n = ptcy_n),
  wide |> transmute(study_id, tp_early, d_rpos, let_any = let_any_comp,
                    era_post2018 = era_post2018_comp, ptcy_binary = 0,
                    events_n = comp_e, denom_n = comp_n)
) |> filter(!is.na(events_n)) |> mutate(study_id = factor(study_id))

priors_rs <- c(prior(normal(0, 2.5), class = b),
               prior(normal(0, 1.5), class = Intercept),
               prior(student_t(3, 0, 1), class = sd))
num_div <- function(fit) {
  tryCatch(sum(fit$fit$diagnostic_summary()$num_divergent),
           error = function(e) rstan::get_num_divergent(fit$fit))
}
fit_one <- function(dd, rhs, file, seed) {
  fit <- brm(as.formula(rhs), data = dd, family = binomial(), prior = priors_rs,
             chains = 4, iter = 4000, warmup = 1000, seed = seed,
             control = list(adapt_delta = 0.99), refresh = 0, backend = "cmdstanr")
  saveRDS(fit, file)
  fit
}
summ <- function(fit, label, covar = NULL) {
  dr <- as_draws_df(fit)
  or <- exp(dr$b_ptcy_binary)
  tibble(analysis = label, k = n_distinct(fit$data$study_id),
         or_med = median(or), or_lo = quantile(or, .025), or_hi = quantile(or, .975),
         covariate = covar %||% "",
         cov_beta = if (!is.null(covar)) median(dr[[paste0("b_", covar)]]) else NA_real_,
         cov_lo = if (!is.null(covar)) quantile(dr[[paste0("b_", covar)]], .025) else NA_real_,
         cov_hi = if (!is.null(covar)) quantile(dr[[paste0("b_", covar)]], .975) else NA_real_,
         divergences = num_div(fit))
}
`%||%` <- function(a, b) if (is.null(a)) b else a

set.seed(9182)
base <- "events_n | trials(denom_n) ~ ptcy_binary + tp_early + (1 + ptcy_binary | study_id)"

# (a) era proxy
d_a <- dat |> filter(!is.na(era_post2018))
f_a <- fit_one(d_a, paste(base, "+ era_post2018"),
               file.path(out_dir, "cmv_let_era_adj.rds"), sample.int(10000, 1))
# (c) serostatus difference
d_c <- dat |> filter(!is.na(d_rpos)) |> mutate(d_rpos_c = d_rpos - mean(d_rpos))
f_c <- fit_one(d_c, paste(base, "+ d_rpos_c"),
               file.path(out_dir, "cmv_let_rpos_adj.rds"), sample.int(10000, 1))

# (b) direct use: descriptive only (no use variation)
d_b <- dat |> filter(!is.na(let_any))
cat("direct-use subset: k =", n_distinct(d_b$study_id),
    " studies;", sum(d_b$let_any == 1), "arms with use;",
    sum(d_b$let_any == 0), "arms confirmed non-use\n")

fit_base <- readRDS(file.path(out_dir, "rs_c1_cmv_m1.rds"))
res <- bind_rows(
  summ(fit_base, "M1 reported (any reactivation)"),
  summ(f_a, "M1 + letermovir era (post-2018 enrolment)", "era_post2018"),
  tibble(analysis = "Arm-level letermovir use (reported subset; all confirmed non-use)",
         k = n_distinct(d_b$study_id), or_med = NA, or_lo = NA, or_hi = NA,
         covariate = "let_any", cov_beta = NA, cov_lo = NA, cov_hi = NA,
         divergences = NA_integer_),
  summ(f_c, "M1 + between-arm CMV R+% difference", "d_rpos_c")
) |> mutate(across(where(is.double), \(x) round(x, 3)))
write_csv(res, "data/models/cmv_letermovir.csv")
print(res, width = 220)

# (d) adoption check in the publication-2020-onward cohort
post2020 <- read_csv(file.path(p9_dir, "data_c1_cmv_post2020.csv"), show_col_types = FALSE)
adoption <- bind_rows(post2020 |> transmute(study_id, arm_id = ptcy_arm_id),
                      post2020 |> transmute(study_id, arm_id = comp_arm_id)) |>
  left_join(arms |> select(arm_id, letermovir_use, letermovir_era_proxy), by = "arm_id")
cat("\nPublication-2020-onward CMV cohort arms:", nrow(adoption), "\n")
print(adoption |> count(letermovir_use, letermovir_era_proxy))
cat("done\n")