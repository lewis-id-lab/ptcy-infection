# Refit c3_nrm_m1 at adapt_delta 0.999 to clear residual divergences
# (7 of 12000 transitions at 0.99 in the 2026-10-02 post-adjudication refit).
# Updates _fits_rs/rs_c3_nrm_m1.rds and the c3_nrm row of Table2_setB.csv.
# Run from project root: Rscript -e 'source("scripts/refit-c3nrm-0999.R")'

suppressPackageStartupMessages({
  library(tidyverse)
  library(brms)
})

d <- read.csv("data/models/data_c3_nrm.csv")
dat <- bind_rows(
  d |> transmute(study_id, tp_early, ptcy_binary = 1,
                 events_n = ptcy_e, denom_n = ptcy_n),
  d |> transmute(study_id, tp_early, ptcy_binary = 0,
                 events_n = comp_e, denom_n = comp_n)
) |>
  filter(!is.na(events_n)) |>
  mutate(study_id = factor(study_id))

priors_rs <- c(
  prior(normal(0, 2.5), class = b),
  prior(normal(0, 1.5), class = Intercept),
  prior(student_t(3, 0, 1), class = sd)
)

fit <- brm(
  events_n | trials(denom_n) ~ ptcy_binary + tp_early + (1 + ptcy_binary | study_id),
  data = dat, family = binomial(), prior = priors_rs,
  chains = 4, iter = 4000, warmup = 1000, seed = 7311,
  control = list(adapt_delta = 0.999, max_treedepth = 12), refresh = 0,
  backend = "cmdstanr"
)
div <- tryCatch(sum(fit$fit$diagnostic_summary()$num_divergent),
                error = function(e) rstan::get_num_divergent(fit$fit))
cat("divergences:", div, "\n")

saveRDS(fit, file.path(path.expand("~/ptcy-infection/_fits_rs"), "rs_c3_nrm_m1.rds"))

dr <- as_draws_df(fit)
or <- exp(dr$b_ptcy_binary)
theta_new <- dr$b_ptcy_binary + rnorm(nrow(dr), 0, dr$sd_study_id__ptcy_binary)
pi_q <- quantile(exp(theta_new), c(.025, .975))

t2 <- read_csv("data/models/Table2_setB.csv", show_col_types = FALSE)
idx <- which(t2$slug == "c3_nrm" & t2$model == "m1")
t2$k[idx]         <- n_distinct(dat$study_id)
t2$n_total[idx]   <- sum(dat$denom_n)
t2$or_median[idx] <- round(median(or), 3)
t2$ci_low[idx]    <- round(quantile(or, .025), 3)
t2$ci_high[idx]   <- round(quantile(or, .975), 3)
t2$tau[idx]       <- round(median(dr$sd_study_id__ptcy_binary), 3)
t2$pi_low[idx]    <- round(pi_q[1], 3)
t2$pi_high[idx]   <- round(pi_q[2], 3)
t2$source[idx]    <- "random-slope refit 2026-10-02 post PDF adjudication (adapt_delta 0.999)"
write_csv(t2, "data/models/Table2_setB.csv")
print(t2[idx, ], width = 200)
cat("done\n")