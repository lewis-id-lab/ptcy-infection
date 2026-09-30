# Re-run RoBMA publication-bias model-averaging on the cohort-deduplicated
# (Set B) datasets, replacing the pre-deduplication fits used in appendix S10.
# All outcomes with k >= 6 are fitted. Resumable: existing RDS files are
# skipped. Set `keys` before sourcing to run a subset.

suppressPackageStartupMessages({
  library(tidyverse)
  library(metafor)
  library(RoBMA)
})

analysis_dir <- path.expand("~/ptcy_metaanalys")
sb <- file.path(analysis_dir, "03_models/set_b")
p9 <- file.path(analysis_dir, "03_models/post_block9")
out_dir <- path.expand("~/ptcy-infection/_fits_rs/robma")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

spec <- tribble(
  ~key,            ~dir, ~data_file,
  "c1_os",         sb,   "data_c1_os.csv",
  "c1_nrm",        p9,   "data_c1_nrm.csv",
  "c1_rrm",        sb,   "data_c1_rrm.csv",
  "c1_agvhd",      p9,   "data_c1_agvhd.csv",
  "c1_cgvhd_ms",   sb,   "data_c1_cgvhd_ms.csv",
  "c1_cgvhd_any",  p9,   "data_c1_cgvhd_any.csv",
  "c1_cmv",        p9,   "data_c1_cmv.csv",
  "c1_bsi",        p9,   "data_c1_bsi.csv",
  "c1_ifi",        p9,   "data_c1_ifi_any.csv",
  "c1_bk",         p9,   "data_c1_bk.csv",
  "c1_irm",        sb,   "data_c1_irm.csv",
  "c2_os",         sb,   "data_c2_os.csv",
  "c2_agvhd",      sb,   "data_c2_agvhd.csv",
  "c2_cgvhd_ms",   p9,   "data_c2_cgvhd_ms.csv",
  "c2_cmv",        sb,   "data_c2_cmv.csv",
  "c2_rrm",        p9,   "data_c2_rrm.csv",
  "c2_irm",        p9,   "data_c2_irm.csv"
)

if (!exists("keys")) keys <- spec$key

set.seed(6391)
seeds <- sample.int(10000, nrow(spec))

results <- list()
for (i in seq_len(nrow(spec))) {
  row <- spec[i, ]
  if (!row$key %in% keys) next
  out_file <- file.path(out_dir, paste0("robma_", row$key, ".rds"))
  if (file.exists(out_file)) {
    cat("skip (exists):", row$key, "\n")
    next
  }
  cat("fitting RoBMA:", row$key, "\n")
  d <- read.csv(file.path(row$dir, row$data_file))
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
    # model-averaged estimate: posterior mean, reported on OR scale
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
}

if (length(results)) {
  res <- bind_rows(results)
  write_csv(res, file.path(out_dir, "robma_summary.csv"))
  print(res, n = Inf)
}
cat("done\n")
