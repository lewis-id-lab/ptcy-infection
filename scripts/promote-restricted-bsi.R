# Promote the restricted-window BSI estimate to the primary c1_bsi analysis
# (2026-10-02). Rationale: the D+100 target-window subset (studies 6, 9, 88,
# 166; k = 4) is also the definition-clean subset (culture-confirmed first BSI
# episode), whereas the two end-of-follow-up rows (studies 216, 432) carry
# vague definitions. The full-window estimate (k = 6, OR 1.42 [0.58-2.99])
# remains documented in data/models/timepoint_sensitivity.csv.
#
# Saves the restricted fit as _fits_rs/rs_c1_bsi_m1.rds (canonical fit
# consumed by figures and export-prediction-intervals.R) and updates the
# c1_bsi m1 row of Table2_setB.csv.
#
# Run from project root: Rscript -e 'source("scripts/promote-restricted-bsi.R")'

suppressPackageStartupMessages({
  library(tidyverse)
  library(brms)
})

d <- read.csv("data/models/data_c1_bsi.csv") |> filter(tp_early == 0)
dat <- bind_rows(
  d |> transmute(study_id, ptcy_binary = 1, events_n = ptcy_e, denom_n = ptcy_n),
  d |> transmute(study_id, ptcy_binary = 0, events_n = comp_e, denom_n = comp_n)
) |> filter(!is.na(events_n)) |> mutate(study_id = factor(study_id))

priors_rs <- c(
  prior(normal(0, 2.5), class = b),
  prior(normal(0, 1.5), class = Intercept),
  prior(student_t(3, 0, 1), class = sd)
)

fit <- brm(events_n | trials(denom_n) ~ ptcy_binary + (1 + ptcy_binary | study_id),
           data = dat, family = binomial(), prior = priors_rs,
           chains = 4, iter = 4000, warmup = 1000, seed = 2693,
           control = list(adapt_delta = 0.99), refresh = 0, backend = "cmdstanr")
div <- tryCatch(sum(fit$fit$diagnostic_summary()$num_divergent),
                error = function(e) rstan::get_num_divergent(fit$fit))
cat("divergences:", div, "\n")
saveRDS(fit, file.path(path.expand("~/ptcy-infection/_fits_rs"), "rs_c1_bsi_m1.rds"))

dr <- as_draws_df(fit)
or <- exp(dr$b_ptcy_binary)
theta_new <- dr$b_ptcy_binary + rnorm(nrow(dr), 0, dr$sd_study_id__ptcy_binary)
pi_q <- quantile(exp(theta_new), c(.025, .975))

t2 <- read_csv("data/models/Table2_setB.csv", show_col_types = FALSE)
idx <- which(t2$slug == "c1_bsi" & t2$model == "m1")
t2$k[idx]         <- n_distinct(dat$study_id)
t2$n_total[idx]   <- sum(dat$denom_n)
t2$or_median[idx] <- round(median(or), 3)
t2$ci_low[idx]    <- round(quantile(or, .025), 3)
t2$ci_high[idx]   <- round(quantile(or, .975), 3)
t2$tau[idx]       <- round(median(dr$sd_study_id__ptcy_binary), 3)
t2$pi_low[idx]    <- round(pi_q[1], 3)
t2$pi_high[idx]   <- round(pi_q[2], 3)
t2$source[idx]    <- "restricted-window primary analysis 2026-10-02 (culture-confirmed D+100 BSI, k=4)"
write_csv(t2, "data/models/Table2_setB.csv")

cat(sprintf("c1_bsi primary (restricted): k=%d, N=%d, OR %.2f [%.2f-%.2f], tau %.2f, PI [%.2f-%.2f]\n",
            n_distinct(dat$study_id), sum(dat$denom_n), median(or),
            quantile(or, .025), quantile(or, .975),
            median(dr$sd_study_id__ptcy_binary), pi_q[1], pi_q[2]))
cat("done\n")