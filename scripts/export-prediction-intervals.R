# Export 95% prediction intervals for every pooled OR in Table 2.
#
# Lancet reviewers expect a prediction interval beside each random-effects
# pooled estimate. For each random-slope fit (_fits_rs/rs_*.rds, the fits
# reported in Table 2) the predictive distribution of the PTCy effect in a
# new study is b_ptcy + N(0, tau_slope); the 95% prediction interval is the
# 2.5%/97.5% quantiles of its exponential. Results are appended to
# data/models/Table2_setB.csv as pi_low/pi_high so the source notebook and
# the article table cannot drift from the model output.

suppressPackageStartupMessages({
  library(tidyverse)
  library(brms)
})

fit_dir <- path.expand("~/ptcy-infection/_fits_rs")

keymap <- tribble(
  ~slug, ~model, ~key,
  "c1_os","m1","c1_os_m1", "c1_os","m2_steroid","c1_os_m2",
  "c1_rrm","m1","c1_rrm_m1", "c1_rrm","m2_steroid","c1_rrm_m2",
  "c1_irm","m1","c1_irm_m1", "c1_cgvhd_ms","m1","c1_cgvhd_m1",
  "c1_cgvhd_any","m1","c1_cgvhdany_m1", "c1_nrm","m1","c1_nrm_m1",
  "c1_nrm","m2_steroid","c1_nrm_m2", "c1_agvhd","m1","c1_agvhd_m1",
  "c1_cmv","m1","c1_cmv_m1", "c1_cmv","m2_steroid","c1_cmv_m2",
  "c1_bsi","m1","c1_bsi_m1", "c1_ifi_any","m1","c1_ifi_m1",
  "c1_bk","m1","c1_bk_m1", "c2_os","m1","c2_os_m1",
  "c2_os","m2_steroid","c2_os_m2", "c2_agvhd","m1","c2_agvhd_m1",
  "c2_cmv","m1","c2_cmv_m1", "c2_cmv","m2_steroid","c2_cmv_m2",
  "c2_rrm","m1","c2_rrm_m1", "c2_bk","m1","c2_bk_m1",
  "c2_irm","m1","c2_irm_m1", "c2_cgvhd_ms","m1","c2_cgvhd_m1",
  "c3_os","m1","c3_os_m1", "c3_agvhd","m1","c3_agvhd_m1",
  "c3_nrm","m1","c3_nrm_m1", "c3_rrm","m1","c3_rrm_m1",
  "c3_cgvhd","m1","c3_cgvhd_m1"
)

pi <- map_dfr(seq_len(nrow(keymap)), \(i) {
  f <- file.path(fit_dir, paste0("rs_", keymap$key[i], ".rds"))
  if (!file.exists(f)) stop("missing fit: ", f)
  dr <- as_draws_df(readRDS(f))
  theta_new <- dr$b_ptcy_binary + rnorm(nrow(dr), 0, dr$sd_study_id__ptcy_binary)
  q <- quantile(exp(theta_new), c(.025, .975))
  tibble(slug = keymap$slug[i], model = keymap$model[i],
         pi_low = unname(q[1]), pi_high = unname(q[2]))
})

t2 <- read_csv("data/models/Table2_setB.csv", show_col_types = FALSE)
t2 <- t2 |>
  select(-any_of(c("pi_low", "pi_high"))) |>
  left_join(pi, by = c("slug", "model"))
if (any(is.na(t2$pi_low))) stop("unmatched rows: ",
                                paste(t2$slug[is.na(t2$pi_low)], collapse = ", "))
write_csv(t2, "data/models/Table2_setB.csv")
print(t2 |> select(slug, model, or_median, ci_low, ci_high, tau, pi_low, pi_high) |>
        mutate(across(where(is.double), \(x) round(x, 2))), n = Inf)
cat("done\n")
