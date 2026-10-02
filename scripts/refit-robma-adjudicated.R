# RoBMA publication-bias model-averaging on the post-adjudication datasets
# (2026-10-02). Reads this repo's data/models/*.csv (CIF/KM-derived arms
# nulled; NA rows dropped), fits every outcome with k >= 6 complete pairs.
# BSI (k = 4) and other k < 6 outcomes are not fitted — publication-bias
# model-averaging is not interpretable at that k.
# Resumable. Run: Rscript -e 'source("scripts/refit-robma-adjudicated.R")'

suppressPackageStartupMessages({
  library(tidyverse)
  library(metafor)
  library(RoBMA)
})

out_dir <- path.expand("~/ptcy-infection/_fits_rs/robma_adj")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

data_files <- c("data_c1_os.csv", "data_c1_nrm.csv", "data_c1_rrm.csv",
                "data_c1_agvhd.csv", "data_c1_cgvhd_ms.csv",
                "data_c1_cgvhd_any.csv", "data_c1_cmv.csv",
                "data_c1_ifi_any.csv", "data_c1_bk.csv", "data_c1_irm.csv",
                "data_c2_os.csv", "data_c2_agvhd.csv", "data_c2_cgvhd_ms.csv",
                "data_c2_cmv.csv", "data_c2_rrm.csv", "data_c2_irm.csv",
                "data_c3_rrm.csv")

# Outcomes untouched by adjudication are not vendored in this repo; read
# those from the analysis repo's post_block9 (identical data).
p9 <- "/Users/russelllewis/main/ptcy_metaanalys/03_models/post_block9"
data_path <- function(f) {
  p <- file.path("data/models", f)
  if (file.exists(p)) p else file.path(p9, f)
}

spec <- map_dfr(data_files, function(f) {
  d <- read_csv(data_path(f), show_col_types = FALSE) |>
    filter(!is.na(ptcy_e), !is.na(comp_e))
  tibble(key = str_remove(f, "^data_|\\.csv$"), data_file = f, k = nrow(d))
}) |> filter(k >= 6)
print(spec)

set.seed(4186)
seeds <- sample.int(10000, nrow(spec))

results <- list()
for (i in seq_len(nrow(spec))) {
  row <- spec[i, ]
  out_file <- file.path(out_dir, paste0("robma_", row$key, ".rds"))
  if (file.exists(out_file)) {
    cat("skip (exists):", row$key, "\n")
    next
  }
  cat("fitting RoBMA:", row$key, " (k =", row$k, ")\n")
  d <- read_csv(data_path(row$data_file), show_col_types = FALSE) |>
    filter(!is.na(ptcy_e), !is.na(comp_e))
  es <- escalc(measure = "OR", ai = ptcy_e, n1i = ptcy_n, ci = comp_e,
               n2i = comp_n, data = d, add = 0.5, to = "only0")
  fit <- RoBMA(yi = es$yi, vi = es$vi, measure = "OR",
               seed = seeds[i], parallel = TRUE)
  saveRDS(fit, out_file)

  s <- summary(fit, type = "ensemble")
  comp <- s$inclusion_components
  est <- s$estimates
  results[[row$key]] <- tibble(
    key = row$key, k = nrow(es),
    or_mean = exp(est["mu", "Mean"]),
    or_lo = exp(est["mu", "0.025"]),
    or_hi = exp(est["mu", "0.975"]),
    bf_effect = comp["Effect", "inclusion_BF"],
    bf_bias = comp["Publication Bias", "inclusion_BF"],
    postprob_effect = comp["Effect", "post_prob"],
    postprob_bias = comp["Publication Bias", "post_prob"],
    rhat_max = max(est[, "R_hat"], na.rm = TRUE),
    ess_min = min(est[, "ESS"], na.rm = TRUE)
  )
  print(results[[row$key]])
}

if (length(results)) {
  res <- bind_rows(results)
  write_csv(res, file.path(out_dir, "robma_adj_summary.csv"))
  print(res, n = Inf, width = 200)
}
cat("done\n")