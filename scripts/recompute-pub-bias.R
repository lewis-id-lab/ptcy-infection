# Recompute funnel-plot asymmetry tests on the post-adjudication datasets
# (2026-10-02), replacing the pre-adjudication pub_bias_results.csv cited in
# appendix S10. Same methods as the original: REML pooled OR, Egger's
# regression test (standard), Peters' sample-size test, Begg's rank test,
# and Duval–Tweedie trim-and-fill. C1 outcomes only, as before.
# Run from project root: Rscript -e 'source("scripts/recompute-pub-bias.R")'

suppressPackageStartupMessages({
  library(tidyverse)
  library(metafor)
})

spec <- tribble(
  ~outcome,                  ~data_file,
  "Overall survival",        "data_c1_os.csv",
  "Non-relapse mortality",   "data_c1_nrm.csv",
  "Relapse-related mortality", "data_c1_rrm.csv",
  "aGVHD grade II–IV",       "data_c1_agvhd.csv",
  "CMV any-reactivation",    "data_c1_cmv.csv",
  "Infection-related mortality", "data_c1_irm.csv",
  "BK virus reactivation",   "data_c1_bk.csv")

res <- pmap_dfr(spec, function(outcome, data_file) {
  d <- read_csv(file.path("data/models", data_file), show_col_types = FALSE) |>
    filter(!is.na(ptcy_e), !is.na(comp_e))
  es <- escalc(measure = "OR", ai = ptcy_e, n1i = ptcy_n, ci = comp_e,
               n2i = comp_n, data = d, add = 0.5, to = "only0")
  r <- rma(es)
  egger <- regtest(r, model = "rma", predictor = "sei")
  peters <- regtest(r, model = "rma", predictor = "sqrtninv")
  begg <- ranktest(r)
  tf <- trimfill(r)
  tibble(
    Outcome = outcome, k = nrow(es),
    raw_OR = as.numeric(exp(r$beta)),
    egger_std_p = egger$zval |> (\(z) 2 * pnorm(-abs(z)))(),
    peters_p = peters$zval |> (\(z) 2 * pnorm(-abs(z)))(),
    begg_p = begg$pval,
    tf_k_imp = tf$k0,
    tf_adj_or = as.numeric(exp(tf$beta)),
    tf_adj_lo = exp(tf$ci.lb), tf_adj_hi = exp(tf$ci.ub))
})

write_csv(res, "data/models/pub_bias_results.csv")
print(res |> mutate(across(where(is.numeric), ~ signif(.x, 3))), width = 200)
cat("done\n")