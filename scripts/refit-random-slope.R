# Random-slope (effect-heterogeneity) sensitivity refits.
#
# The primary M1/M2 models carry a random study intercept only, so the PTCy
# coefficient is a common (fixed) effect and its CrI ignores between-study
# heterogeneity in the treatment effect. This script refits every C1/C2 M1 and
# M2 model with (1 + ptcy_binary | study_id) so the appendix can report how
# estimates and intervals change when effect heterogeneity is acknowledged.
#
# Resumable: fits already present in the output directory are skipped, so the
# script can be run in batches. Usage: source this file, or set the `keys`
# variable first to restrict which models are fitted in this session.

suppressPackageStartupMessages({
  library(tidyverse)
  library(brms)
})

analysis_dir <- path.expand("~/ptcy_metaanalys")
setb_dir <- file.path(analysis_dir, "03_models/set_b")
p9_dir <- file.path(analysis_dir, "03_models/post_block9")
# NB: fits are saved inside the manuscript project (the R session sandbox
# blocks writes to the analysis repo); excluded from git and from the render.
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
  ) |>
    mutate(study_id = factor(study_id))
}

mk_data <- function(d, m2) {
  long <- mk_long(d)
  if (!m2) return(long)
  # M2: drop arms missing steroid exposure, then mean-centre (matches the
  # original M2 construction: verified against m2_c1_os$data below)
  long |>
    filter(!is.na(steroid_pct)) |>
    mutate(steroid_pct_c = steroid_pct - mean(steroid_pct))
}

priors_rs <- c(
  prior(normal(0, 2.5), class = b),
  prior(normal(0, 1.5), class = Intercept),
  prior(student_t(3, 0, 1), class = sd)
)

spec <- tribble(
  ~key,            ~m2,    ~dir,      ~data_file,
  # Set B (cohort-deduplicated)
  "c1_os_m1",      FALSE,  setb_dir,  "data_c1_os.csv",
  "c1_os_m2",      TRUE,   setb_dir,  "data_c1_os.csv",
  "c1_rrm_m1",     FALSE,  setb_dir,  "data_c1_rrm.csv",
  "c1_rrm_m2",     TRUE,   setb_dir,  "data_c1_rrm.csv",
  "c1_irm_m1",     FALSE,  setb_dir,  "data_c1_irm.csv",
  "c1_cgvhd_m1",   FALSE,  setb_dir,  "data_c1_cgvhd_ms.csv",
  "c2_os_m1",      FALSE,  setb_dir,  "data_c2_os.csv",
  "c2_os_m2",      TRUE,   setb_dir,  "data_c2_os.csv",
  "c2_agvhd_m1",   FALSE,  setb_dir,  "data_c2_agvhd.csv",
  "c2_cmv_m1",     FALSE,  setb_dir,  "data_c2_cmv.csv",
  "c2_cmv_m2",     TRUE,   setb_dir,  "data_c2_cmv.csv",
  # post_block9 (unaffected by deduplication)
  "c1_nrm_m1",     FALSE,  p9_dir,    "data_c1_nrm.csv",
  "c1_nrm_m2",     TRUE,   p9_dir,    "data_c1_nrm.csv",
  "c1_agvhd_m1",   FALSE,  p9_dir,    "data_c1_agvhd.csv",
  "c1_cmv_m1",     FALSE,  p9_dir,    "data_c1_cmv.csv",
  "c1_cmv_m2",     TRUE,   p9_dir,    "data_c1_cmv.csv",
  "c1_bk_m1",      FALSE,  p9_dir,    "data_c1_bk.csv",
  "c1_cgvhdany_m1", FALSE, p9_dir,    "data_c1_cgvhd_any.csv",
  "c2_nrm_m1",     FALSE,  p9_dir,    "data_c2_nrm.csv",
  "c2_rrm_m1",     FALSE,  p9_dir,    "data_c2_rrm.csv",
  "c2_bk_m1",      FALSE,  p9_dir,    "data_c2_bk.csv",
  "c2_irm_m1",     FALSE,  p9_dir,    "data_c2_irm.csv",
  "c2_cgvhd_m1",   FALSE,  p9_dir,    "data_c2_cgvhd_ms.csv",
  # fitted earlier interactively; rows included so the summary covers them
  "c1_bsi_m1",     FALSE,  p9_dir,    "data_c1_bsi.csv",
  "c1_ifi_m1",     FALSE,  p9_dir,    "data_c1_ifi_any.csv",
  # C3 (within-PTCy variants) — same contrast structure
  "c3_os_m1",      FALSE,  p9_dir,    "data_c3_os.csv",
  "c3_agvhd_m1",   FALSE,  p9_dir,    "data_c3_agvhd.csv",
  "c3_nrm_m1",     FALSE,  p9_dir,    "data_c3_nrm.csv",
  "c3_rrm_m1",     FALSE,  p9_dir,    "data_c3_rrm.csv",
  "c3_cgvhd_m1",   FALSE,  p9_dir,    "data_c3_cgvhd.csv",
  # pre-specified CMV sensitivity cohorts cited in the abstract
  "c1_cmv_post2020_m1", FALSE, p9_dir, "data_c1_cmv_post2020.csv",
  "c1_cmv_haplo_m1",    FALSE, p9_dir, "data_c1_cmv_haplo.csv"
)

if (!exists("keys")) keys <- spec$key

set.seed(4820)
seeds <- sample.int(10000, nrow(spec))

results <- list()
for (i in seq_len(nrow(spec))) {
  row <- spec[i, ]
  if (!row$key %in% keys) next
  out_file <- file.path(out_dir, paste0("rs_", row$key, ".rds"))
  if (file.exists(out_file)) {
    cat("skip (exists):", row$key, "\n")
    next
  }
  cat("fitting:", row$key, "\n")
  # 2026-10-02: prefer this repo's data/models/ (Set B copies, PDF-adjudicated);
  # fall back to the analysis repo's post_block9 for files not vendored here.
  data_path <- file.path("data/models", row$data_file)
  if (!file.exists(data_path)) data_path <- file.path(p9_dir, row$data_file)
  dat <- read.csv(data_path) |> mk_data(row$m2)
  rhs <- if (row$m2) {
    "events_n | trials(denom_n) ~ ptcy_binary + tp_early + steroid_pct_c + (1 + ptcy_binary | study_id)"
  } else {
    "events_n | trials(denom_n) ~ ptcy_binary + tp_early + (1 + ptcy_binary | study_id)"
  }
  # backend = cmdstanr: rstan on this machine fails to load compiled models
  # (TBB task_scheduler_init symbol error, 2026-10-02)
  num_div <- function(fit) {
    tryCatch(sum(fit$fit$diagnostic_summary()$num_divergent),
             error = function(e) rstan::get_num_divergent(fit$fit))
  }
  fit <- brm(
    as.formula(rhs), data = dat, family = binomial(), prior = priors_rs,
    chains = 4, iter = 4000, warmup = 1000, seed = seeds[i],
    control = list(adapt_delta = 0.95), refresh = 0,
    backend = "cmdstanr"
  )
  div <- num_div(fit)
  if (div > 0) {
    cat("  ", div, "divergences at adapt_delta 0.95; refitting at 0.99\n")
    fit <- brm(
      as.formula(rhs), data = dat, family = binomial(), prior = priors_rs,
      chains = 4, iter = 4000, warmup = 1000, seed = seeds[i],
      control = list(adapt_delta = 0.99), refresh = 0,
      backend = "cmdstanr"
    )
    div <- num_div(fit)
  }
  saveRDS(fit, out_file)

  dr <- as_draws_df(fit)
  or <- exp(dr$b_ptcy_binary)
  s <- summary(fit)
  all_rows <- rbind(s$fixed, s$random$study_id)
  results[[row$key]] <- tibble(
    key = row$key,
    k = n_distinct(dat$study_id),
    or_med = median(or), or_lo = quantile(or, .025), or_hi = quantile(or, .975),
    tau_slope = median(dr$sd_study_id__ptcy_binary),
    max_rhat = max(all_rows$Rhat, na.rm = TRUE),
    min_bulk_ess = min(all_rows$Bulk_ESS, na.rm = TRUE),
    divergences = div
  )
}

if (length(results)) {
  res <- bind_rows(results)
  write_csv(res, file.path(out_dir, "rs_summary.csv"))
  print(res, n = Inf)
}
cat("done\n")
