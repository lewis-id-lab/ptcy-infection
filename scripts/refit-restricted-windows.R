# Restricted-window (and definition-comparable) sensitivity refits, 2026-10-02.
#
# The pooled M1 models include a preferred/fallback timepoint indicator
# (tp_early: 0 = preferred target timepoint, 1 = fallback). This script:
#   A. extracts the tp_early coefficient from each existing M1 fit
#      (does the fallback indicator absorb time differences?);
#   B. refits each outcome restricted to its target timepoint
#      (tp_early == 0 only), plus definition-comparable subsets:
#      - c1_bsi: target D+100 rows are exactly the culture-confirmed BSIs
#      - c1_ifi_any: also drop study 167 (includes 'possible' IFD) and
#        study 399 (fungal-attributed mortality, not IFI incidence)
# and writes data/models/timepoint_sensitivity.csv.
#
# Run from project root: Rscript -e 'source("scripts/refit-restricted-windows.R")'

suppressPackageStartupMessages({
  library(tidyverse)
  library(brms)
})

rs_dir <- path.expand("~/ptcy-infection/_fits_rs")

# ── A. tp_early coefficients from existing M1 fits ──
m1_keys <- c("c1_os_m1", "c1_rrm_m1", "c1_irm_m1", "c1_cgvhd_m1", "c1_nrm_m1",
             "c1_agvhd_m1", "c1_cmv_m1", "c1_bsi_m1", "c1_ifi_m1", "c1_bk_m1",
             "c2_os_m1", "c2_agvhd_m1", "c2_cmv_m1", "c2_nrm_m1", "c2_rrm_m1",
             "c2_bk_m1", "c2_irm_m1", "c2_cgvhd_m1",
             "c3_os_m1", "c3_agvhd_m1", "c3_nrm_m1", "c3_rrm_m1", "c3_cgvhd_m1")

tp_coef <- map_dfr(m1_keys, function(key) {
  f <- file.path(rs_dir, paste0("rs_", key, ".rds"))
  if (!file.exists(f)) return(NULL)
  dr <- as_draws_df(readRDS(f))
  b <- dr$b_tp_early
  tibble(key = key, b_early_med = median(b), b_early_lo = quantile(b, .025),
         b_early_hi = quantile(b, .975), pr_same_dir = mean(b > 0))
})

# ── B. Restricted refits ──
priors_rs <- c(
  prior(normal(0, 2.5), class = b),
  prior(normal(0, 1.5), class = Intercept),
  prior(student_t(3, 0, 1), class = sd)
)

spec <- tribble(
  ~key,          ~data_file,              ~drop_studies,
  "c1_agvhd",    "data_c1_agvhd.csv",     numeric(0),
  "c1_cmv",      "data_c1_cmv.csv",       numeric(0),
  "c1_bsi",      "data_c1_bsi.csv",       numeric(0),   # target rows = culture-confirmed
  "c1_ifi",      "data_c1_ifi_any.csv",   c(167, 399),  # 'possible' IFD; fungal mortality
  "c1_bk",       "data_c1_bk.csv",        numeric(0),
  "c1_nrm",      "data_c1_nrm.csv",       numeric(0),
  "c1_os",       "data_c1_os.csv",        numeric(0),
  "c1_cgvhd",    "data_c1_cgvhd_ms.csv",  numeric(0),
  "c1_rrm",      "data_c1_rrm.csv",       numeric(0),
  "c2_os",       "data_c2_os.csv",        numeric(0),
  "c3_os",       "data_c3_os.csv",        numeric(0),
  "c3_nrm",      "data_c3_nrm.csv",       numeric(0)
)

set.seed(2693)
seeds <- sample.int(10000, nrow(spec))

num_div <- function(fit) {
  tryCatch(sum(fit$fit$diagnostic_summary()$num_divergent),
           error = function(e) rstan::get_num_divergent(fit$fit))
}

res <- pmap_dfr(spec, function(key, data_file, drop_studies) {
  d <- read.csv(file.path("data/models", data_file))
  full_n <- nrow(d)
  d <- d |>
    filter(tp_early == 0, !study_id %in% drop_studies)
  if (nrow(d) < 3) {
    return(tibble(key = key, k_full = full_n, k_restricted = nrow(d),
                  note = "too few studies to refit"))
  }
  dat <- bind_rows(
    d |> transmute(study_id, ptcy_binary = 1, events_n = ptcy_e, denom_n = ptcy_n),
    d |> transmute(study_id, ptcy_binary = 0, events_n = comp_e, denom_n = comp_n)
  ) |> filter(!is.na(events_n)) |> mutate(study_id = factor(study_id))

  fit <- brm(events_n | trials(denom_n) ~ ptcy_binary + (1 + ptcy_binary | study_id),
             data = dat, family = binomial(), prior = priors_rs,
             chains = 4, iter = 4000, warmup = 1000, seed = seeds[which(spec$key == key)],
             control = list(adapt_delta = 0.99), refresh = 0, backend = "cmdstanr")
  div <- num_div(fit)
  if (div > 0) {
    fit <- brm(events_n | trials(denom_n) ~ ptcy_binary + (1 + ptcy_binary | study_id),
               data = dat, family = binomial(), prior = priors_rs,
               chains = 4, iter = 4000, warmup = 1000,
               seed = seeds[which(spec$key == key)],
               control = list(adapt_delta = 0.999), refresh = 0, backend = "cmdstanr")
    div <- num_div(fit)
  }
  dr <- as_draws_df(fit)
  or <- exp(dr$b_ptcy_binary)
  tibble(key = key, k_full = full_n, k_restricted = n_distinct(dat$study_id),
         or_med = median(or), or_lo = quantile(or, .025), or_hi = quantile(or, .975),
         tau = median(dr$sd_study_id__ptcy_binary), divergences = div)
})

# Full-model M1 estimates for comparison
t2 <- read_csv("data/models/Table2_setB.csv", show_col_types = FALSE)
slug_map <- c(c1_agvhd = "c1_agvhd", c1_cmv = "c1_cmv", c1_bsi = "c1_bsi",
              c1_ifi = "c1_ifi_any", c1_bk = "c1_bk", c1_nrm = "c1_nrm",
              c1_os = "c1_os", c1_cgvhd = "c1_cgvhd_ms", c1_rrm = "c1_rrm",
              c2_os = "c2_os", c3_os = "c3_os", c3_nrm = "c3_nrm")
full <- t2 |> filter(model == "m1") |>
  select(key = slug, full_or = or_median, full_lo = ci_low, full_hi = ci_high)

out <- res |> mutate(slug = slug_map[key]) |>
  left_join(full, by = c("slug" = "key"))
write_csv(out, "data/models/timepoint_sensitivity.csv")
write_csv(tp_coef, "data/models/tp_early_coefficients.csv")

print(tp_coef |> mutate(across(where(is.numeric), ~ round(.x, 3))), n = 25, width = 200)
print(out |> mutate(across(where(is.numeric), ~ round(.x, 3))), width = 220)
cat("done\n")