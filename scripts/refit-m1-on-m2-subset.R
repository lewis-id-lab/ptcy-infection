# Matched-set M1 refits: M1 on the M2 steroid complete-case studies.
#
# Reviewer: M1/M2 comparisons must use the same study set. The reported M1
# uses all studies with outcome data; M2 drops studies without arm-level
# steroid exposure, so attenuation from M1 to M2 confounds steroid adjustment
# with a changed study set. This script refits the random-slope M1
# specification on each outcome's M2 complete-case subset and exports a
# side-by-side table (full-set M1, matched-set M1, M2) so the manuscript can
# report how much attenuation is due to the covariate versus the subset.
#
# Resumable: existing fits are skipped. Outputs: _fits_rs/m1subset_*.rds and
# data/models/m1_m2_matched.csv.

suppressPackageStartupMessages({
  library(tidyverse)
  library(brms)
})

analysis_dir <- path.expand("~/ptcy_metaanalys")
setb_dir <- file.path(analysis_dir, "03_models/set_b")
p9_dir <- file.path(analysis_dir, "03_models/post_block9")
out_dir <- path.expand("~/ptcy-infection/_fits_rs")
dir.create(out_dir, showWarnings = FALSE)

mk_long <- function(d) {
  bind_rows(
    d |> transmute(study_id, tp_early, ptcy_binary = 1,
                   events_n = ptcy_e, denom_n = ptcy_n,
                   steroid_pct = ptcy_steroid_pct),
    d |> transmute(study_id, tp_early, ptcy_binary = 0,
                   events_n = comp_e, denom_n = comp_n,
                   steroid_pct = comp_steroid_pct)
  ) |> mutate(study_id = factor(study_id))
}

# M1 random-slope specification; data filtered to each outcome's M2 subset.
spec <- tribble(
  ~key,        ~dir,      ~data_file,
  "c1_os",     setb_dir,  "data_c1_os.csv",
  "c1_rrm",    setb_dir,  "data_c1_rrm.csv",
  "c1_nrm",    p9_dir,    "data_c1_nrm.csv",
  "c1_cmv",    p9_dir,    "data_c1_cmv.csv",
  "c2_os",     setb_dir,  "data_c2_os.csv",
  "c2_cmv",    setb_dir,  "data_c2_cmv.csv"
)

priors_rs <- c(
  prior(normal(0, 2.5), class = b),
  prior(normal(0, 1.5), class = Intercept),
  prior(student_t(3, 0, 1), class = sd)
)

set.seed(8214)
seeds <- sample.int(10000, nrow(spec))

for (i in seq_len(nrow(spec))) {
  key <- spec$key[i]
  out_file <- file.path(out_dir, paste0("m1subset_", key, ".rds"))
  if (file.exists(out_file)) { cat("skip (exists):", key, "\n"); next }
  cat("fitting:", key, "\n")
  dat <- read.csv(file.path(spec$dir[i], spec$data_file[i])) |>
    mk_long() |>
    filter(!is.na(steroid_pct))   # M2 complete-case subset
  fit <- brm(
    events_n | trials(denom_n) ~ ptcy_binary + tp_early + (1 + ptcy_binary | study_id),
    data = dat, family = binomial(), prior = priors_rs,
    chains = 4, iter = 4000, warmup = 1000, seed = seeds[i],
    control = list(adapt_delta = 0.99, max_treedepth = 12), refresh = 0
  )
  saveRDS(fit, out_file)
  cat("  divergences:", rstan::get_num_divergent(fit$fit), "\n")
}

# Side-by-side: full-set M1 (reported), matched-set M1, M2 (reported).
summ <- function(fit, label) {
  dr <- as_draws_df(fit)
  or <- exp(dr$b_ptcy_binary)
  tibble(model = label, k = n_distinct(fit$data$study_id),
         or_med = median(or), or_lo = quantile(or, .025), or_hi = quantile(or, .975),
         tau_slope = median(dr$sd_study_id__ptcy_binary),
         divergences = rstan::get_num_divergent(fit$fit))
}

m2_key <- c(c1_os = "c1_os_m2", c1_rrm = "c1_rrm_m2", c1_nrm = "c1_nrm_m2",
            c1_cmv = "c1_cmv_m2", c2_os = "c2_os_m2", c2_cmv = "c2_cmv_m2")

res <- map_dfr(spec$key, \(key) {
  bind_rows(
    summ(readRDS(file.path(out_dir, paste0("rs_", key, "_m1.rds"))), "M1 full set"),
    summ(readRDS(file.path(out_dir, paste0("m1subset_", key, ".rds"))), "M1 matched set"),
    summ(readRDS(file.path(out_dir, paste0("rs_", m2_key[[key]], ".rds"))), "M2")
  ) |> mutate(outcome = key, .before = 1)
}) |> mutate(across(where(is.double), \(x) round(x, 3)))

write_csv(res, "data/models/m1_m2_matched.csv")
print(res, n = Inf)
cat("done\n")
