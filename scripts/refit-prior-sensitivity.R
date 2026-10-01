# tau-prior sensitivity for the sparse (k = 6) C1 outcomes BSI and IFI.
#
# With k = 6 the Student t(3, 0, 1) prior on the between-study SDs could in
# principle be influential (appendix S6 flags this). This script refits the
# reported random-slope M1 specification for C1 BSI and C1 IFI with a
# narrower (t(3, 0, 0.5)) and a wider (t(3, 0, 2)) SD prior and exports the
# pooled OR, CrI and tau for comparison with the base model.
#
# Resumable: fits already present are skipped. Outputs:
# _fits_rs/priorsens_*.rds and data/models/prior_sensitivity_tau.csv.

suppressPackageStartupMessages({
  library(tidyverse)
  library(brms)
})

p9_dir <- file.path(path.expand("~/ptcy_metaanalys"), "03_models/post_block9")
out_dir <- path.expand("~/ptcy-infection/_fits_rs")
dir.create(out_dir, showWarnings = FALSE)

mk_long <- function(d) {
  bind_rows(
    d |> transmute(study_id, tp_early, ptcy_binary = 1,
                   events_n = ptcy_e, denom_n = ptcy_n),
    d |> transmute(study_id, tp_early, ptcy_binary = 0,
                   events_n = comp_e, denom_n = comp_n)
  ) |> mutate(study_id = factor(study_id))
}

rhs <- events_n | trials(denom_n) ~ ptcy_binary + tp_early + (1 + ptcy_binary | study_id)

variants <- tribble(
  ~tag,     ~sd_scale,
  "narrow", 0.5,
  "wide",   2
)

keys <- c(c1_bsi_m1 = "data_c1_bsi.csv", c1_ifi_m1 = "data_c1_ifi_any.csv")

set.seed(3407)
seeds <- sample.int(10000, length(keys) * nrow(variants))

results <- list()
i <- 0
for (key in names(keys)) {
  dat <- read.csv(file.path(p9_dir, keys[[key]])) |> mk_long()
  for (v in seq_len(nrow(variants))) {
    i <- i + 1
    tag <- variants$tag[v]
    out_file <- file.path(out_dir, sprintf("priorsens_%s_%s.rds", key, tag))
    if (file.exists(out_file)) { cat("skip (exists):", key, tag, "\n"); next }
    cat("fitting:", key, tag, "\n")
    # do.call so the SD prior reaches prior() as a literal string: this brms
    # version records unevaluated calls verbatim into the Stan program.
    priors_v <- c(
      prior(normal(0, 2.5), class = b),
      prior(normal(0, 1.5), class = Intercept),
      do.call("prior", list(sprintf("student_t(3, 0, %s)", variants$sd_scale[v]),
                            class = "sd"))
    )
    fit <- brm(rhs, data = dat, family = binomial(), prior = priors_v,
               chains = 4, iter = 4000, warmup = 1000, seed = seeds[i],
               control = list(adapt_delta = 0.99, max_treedepth = 12), refresh = 0)
    saveRDS(fit, out_file)
  }
}

# Summarise base (t(3,0,1), from the reported fits) and both variants.
summ <- function(fit, key, prior_tag) {
  dr <- as_draws_df(fit)
  or <- exp(dr$b_ptcy_binary)
  tibble(key = key, sd_prior = prior_tag,
         or_med = median(or), or_lo = quantile(or, .025), or_hi = quantile(or, .975),
         tau_slope = median(dr$sd_study_id__ptcy_binary),
         divergences = rstan::get_num_divergent(fit$fit))
}

res <- map_dfr(names(keys), \(key) {
  base <- summ(readRDS(file.path(out_dir, paste0("rs_", key, ".rds"))), key, "t(3, 0, 1) [base]")
  vars <- map_dfr(variants$tag, \(tag)
    summ(readRDS(file.path(out_dir, sprintf("priorsens_%s_%s.rds", key, tag))),
         key, sprintf("t(3, 0, %s)", variants$sd_scale[variants$tag == tag])))
  bind_rows(base, vars)
}) |> mutate(across(where(is.double), \(x) round(x, 3)))

write_csv(res, "data/models/prior_sensitivity_tau.csv")
print(res, n = Inf)
cat("done\n")
