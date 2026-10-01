# Fixed-intercept (stratified) sensitivity refits.
#
# The reported M1/M2 models carry a random study intercept. A random study
# intercept lets between-study contrasts leak into the PTCy coefficient and
# does not preserve within-study randomisation in RCTs (Senn 2010, Stat Med).
# This script refits every C1/C2 model reported in Table 2 with FIXED study
# intercepts (0 + study_id) plus a random PTCy-effect slope, so the treatment
# effect is identified purely from within-study contrasts, as in two-stage
# meta-analysis of odds ratios. C3 (within-PTCy variants) models are refitted
# under the same specification so the sensitivity analysis is uniform across
# Table 2.
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
  # M2: drop arms missing steroid exposure, then mean-centre
  long |>
    filter(!is.na(steroid_pct)) |>
    mutate(steroid_pct_c = steroid_pct - mean(steroid_pct))
}

# class = b prior also covers the study-specific intercepts; the logit-scale
# baseline risks are comfortably within N(0, 2.5).
priors_fe <- c(
  prior(normal(0, 2.5), class = b),
  prior(student_t(3, 0, 1), class = sd)
)

# All C1/C2 rows of Table 2 (slug -> rs-spec key mapping).
spec <- tribble(
  ~key,            ~m2,    ~dir,      ~data_file,
  "c1_os_m1",      FALSE,  setb_dir,  "data_c1_os.csv",
  "c1_os_m2",      TRUE,   setb_dir,  "data_c1_os.csv",
  "c1_rrm_m1",     FALSE,  setb_dir,  "data_c1_rrm.csv",
  "c1_rrm_m2",     TRUE,   setb_dir,  "data_c1_rrm.csv",
  "c1_irm_m1",     FALSE,  setb_dir,  "data_c1_irm.csv",
  "c1_cgvhd_m1",   FALSE,  setb_dir,  "data_c1_cgvhd_ms.csv",
  "c1_cgvhdany_m1", FALSE, p9_dir,    "data_c1_cgvhd_any.csv",
  "c1_nrm_m1",     FALSE,  p9_dir,    "data_c1_nrm.csv",
  "c1_nrm_m2",     TRUE,   p9_dir,    "data_c1_nrm.csv",
  "c1_agvhd_m1",   FALSE,  p9_dir,    "data_c1_agvhd.csv",
  "c1_cmv_m1",     FALSE,  p9_dir,    "data_c1_cmv.csv",
  "c1_cmv_m2",     TRUE,   p9_dir,    "data_c1_cmv.csv",
  "c1_bsi_m1",     FALSE,  p9_dir,    "data_c1_bsi.csv",
  "c1_ifi_m1",     FALSE,  p9_dir,    "data_c1_ifi_any.csv",
  "c1_bk_m1",      FALSE,  p9_dir,    "data_c1_bk.csv",
  "c2_os_m1",      FALSE,  setb_dir,  "data_c2_os.csv",
  "c2_os_m2",      TRUE,   setb_dir,  "data_c2_os.csv",
  "c2_agvhd_m1",   FALSE,  setb_dir,  "data_c2_agvhd.csv",
  "c2_cmv_m1",     FALSE,  setb_dir,  "data_c2_cmv.csv",
  "c2_cmv_m2",     TRUE,   setb_dir,  "data_c2_cmv.csv",
  "c2_rrm_m1",     FALSE,  p9_dir,    "data_c2_rrm.csv",
  "c2_bk_m1",      FALSE,  p9_dir,    "data_c2_bk.csv",
  "c2_irm_m1",     FALSE,  p9_dir,    "data_c2_irm.csv",
  "c2_cgvhd_m1",   FALSE,  p9_dir,    "data_c2_cgvhd_ms.csv",
  # C3 (within-PTCy variants) — same contrast structure
  "c3_os_m1",      FALSE,  p9_dir,    "data_c3_os.csv",
  "c3_agvhd_m1",   FALSE,  p9_dir,    "data_c3_agvhd.csv",
  "c3_nrm_m1",     FALSE,  p9_dir,    "data_c3_nrm.csv",
  "c3_rrm_m1",     FALSE,  p9_dir,    "data_c3_rrm.csv",
  "c3_cgvhd_m1",   FALSE,  p9_dir,    "data_c3_cgvhd.csv"
)

if (!exists("keys")) keys <- spec$key

set.seed(6183)
seeds <- sample.int(10000, nrow(spec))

for (i in seq_len(nrow(spec))) {
  row <- spec[i, ]
  if (!row$key %in% keys) next
  out_file <- file.path(out_dir, paste0("fe_", row$key, ".rds"))
  if (file.exists(out_file)) {
    cat("skip (exists):", row$key, "\n")
    next
  }
  cat("fitting:", row$key, "\n")
  dat <- read.csv(file.path(row$dir, row$data_file)) |> mk_data(row$m2)
  rhs <- if (row$m2) {
    "events_n | trials(denom_n) ~ 0 + study_id + ptcy_binary + tp_early + steroid_pct_c + (0 + ptcy_binary | study_id)"
  } else {
    "events_n | trials(denom_n) ~ 0 + study_id + ptcy_binary + tp_early + (0 + ptcy_binary | study_id)"
  }
  fit <- brm(
    as.formula(rhs), data = dat, family = binomial(), prior = priors_fe,
    chains = 4, iter = 4000, warmup = 1000, seed = seeds[i],
    control = list(adapt_delta = 0.95, max_treedepth = 12), refresh = 0
  )
  div <- rstan::get_num_divergent(fit$fit)
  if (div > 0) {
    cat("  ", div, "divergences at adapt_delta 0.95; refitting at 0.99\n")
    fit <- brm(
      as.formula(rhs), data = dat, family = binomial(), prior = priors_fe,
      chains = 4, iter = 4000, warmup = 1000, seed = seeds[i],
      control = list(adapt_delta = 0.99, max_treedepth = 12), refresh = 0
    )
    div <- rstan::get_num_divergent(fit$fit)
  }
  saveRDS(fit, out_file)
  cat("  divergences:", div, "\n")
}

# Summarise every fe_*.rds present, including fits skipped above.
summ_fe <- function(fit, key, k) {
  dr <- as_draws_df(fit)
  or <- exp(dr$b_ptcy_binary)
  s <- summary(fit)
  all_rows <- rbind(s$fixed, s$random$study_id)
  tibble(
    key = key, k = k,
    or_med = median(or), or_lo = quantile(or, .025), or_hi = quantile(or, .975),
    tau_slope = median(dr$sd_study_id__ptcy_binary),
    max_rhat = max(all_rows$Rhat, na.rm = TRUE),
    min_bulk_ess = min(all_rows$Bulk_ESS, na.rm = TRUE),
    divergences = rstan::get_num_divergent(fit$fit)
  )
}

fe_files <- list.files(out_dir, pattern = "^fe_.*\\.rds$", full.names = TRUE)
res <- map_dfr(fe_files, \(f) {
  key <- sub("^fe_(.*)\\.rds$", "\\1", basename(f))
  row <- spec[spec$key == key, ]
  fit <- readRDS(f)
  k <- n_distinct(fit$data$study_id)
  summ_fe(fit, key, k)
}) |> arrange(key)

write_csv(res, file.path(out_dir, "fe_summary.csv"))
print(res, n = Inf)
cat("done\n")
