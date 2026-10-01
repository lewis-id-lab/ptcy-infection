# Donor-type confounding analyses (reviewer bullet: 47% haplo in PTCy arms vs
# 15% in comparator arms).
#
# Two analyses for the five main C1 outcomes:
#   (a) meta-regression: M1 specification + the between-arm difference in
#       haploidentical-donor percentage (study-level covariate), testing
#       whether within-study donor imbalance predicts the PTCy effect;
#   (b) donor-matched restriction: M1 refitted on studies with |delta haplo|
#       <= 15 percentage points.
#
# Note: within-study delta-haplo has median 0 across outcomes, so most of the
# marginal 47% vs 15% imbalance is BETWEEN studies, which the random/fixed
# study intercepts absorb. Outputs: _fits_rs/donor_*.rds and
# data/models/donor_confounding.csv.

suppressPackageStartupMessages({
  library(tidyverse)
  library(brms)
})

analysis_dir <- path.expand("~/ptcy_metaanalys")
setb_dir <- file.path(analysis_dir, "03_models/set_b")
p9_dir <- file.path(analysis_dir, "03_models/post_block9")
out_dir <- path.expand("~/ptcy-infection/_fits_rs")
dir.create(out_dir, showWarnings = FALSE)

arms <- read_csv("data/arms.csv", show_col_types = FALSE)
a_haplo <- arms |> transmute(arm_id, haplo = suppressWarnings(as.numeric(donor_haplo_pct)))

spec <- tribble(
  ~key,       ~dir,      ~data_file,
  "c1_os",    setb_dir,  "data_c1_os.csv",
  "c1_rrm",   setb_dir,  "data_c1_rrm.csv",
  "c1_agvhd", p9_dir,    "data_c1_agvhd.csv",
  "c1_cmv",   p9_dir,    "data_c1_cmv.csv",
  "c1_nrm",   p9_dir,    "data_c1_nrm.csv"
)

mk_long <- function(d) {
  wide <- d |>
    left_join(a_haplo, by = c("ptcy_arm_id" = "arm_id")) |>
    left_join(a_haplo, by = c("comp_arm_id" = "arm_id"), suffix = c("_ptcy", "_comp")) |>
    mutate(d_haplo = haplo_ptcy - haplo_comp)
  bind_rows(
    wide |> transmute(study_id, tp_early, d_haplo, ptcy_binary = 1,
                      events_n = ptcy_e, denom_n = ptcy_n),
    wide |> transmute(study_id, tp_early, d_haplo, ptcy_binary = 0,
                      events_n = comp_e, denom_n = comp_n)
  ) |> mutate(study_id = factor(study_id))
}

priors_rs <- c(
  prior(normal(0, 2.5), class = b),
  prior(normal(0, 1.5), class = Intercept),
  prior(student_t(3, 0, 1), class = sd)
)

set.seed(5546)
seeds <- sample.int(10000, 2 * nrow(spec))

fits <- list()
for (i in seq_len(nrow(spec))) {
  key <- spec$key[i]
  dat <- mk_long(read.csv(file.path(spec$dir[i], spec$data_file[i]))) |>
    filter(!is.na(d_haplo))

  # (a) meta-regression on delta haplo
  f1 <- file.path(out_dir, paste0("donor_metareg_", key, ".rds"))
  if (!file.exists(f1)) {
    cat("fitting metareg:", key, "\n")
    dd <- dat |> mutate(d_haplo_c = d_haplo - mean(d_haplo))
    fit <- brm(events_n | trials(denom_n) ~ ptcy_binary + tp_early + d_haplo_c +
                 (1 + ptcy_binary | study_id),
               data = dd, family = binomial(), prior = priors_rs,
               chains = 4, iter = 4000, warmup = 1000, seed = seeds[2 * i - 1],
               control = list(adapt_delta = 0.99, max_treedepth = 12), refresh = 0)
    saveRDS(fit, f1)
  }

  # (b) donor-matched restriction
  f2 <- file.path(out_dir, paste0("donor_matched_", key, ".rds"))
  if (!file.exists(f2)) {
    cat("fitting matched:", key, "\n")
    fit <- brm(events_n | trials(denom_n) ~ ptcy_binary + tp_early +
                 (1 + ptcy_binary | study_id),
               data = filter(dat, abs(d_haplo) <= 15), family = binomial(),
               prior = priors_rs,
               chains = 4, iter = 4000, warmup = 1000, seed = seeds[2 * i],
               control = list(adapt_delta = 0.99, max_treedepth = 12), refresh = 0)
    saveRDS(fit, f2)
  }
  fits[[key]] <- list(metareg = f1, matched = f2, n_studies = n_distinct(dat$study_id),
                      n_matched = n_distinct(dat$study_id[abs(dat$d_haplo) <= 15]),
                      med_delta = median(dat$d_haplo))
}

summ_or <- function(f, label) {
  fit <- readRDS(f)
  dr <- as_draws_df(fit)
  or <- exp(dr$b_ptcy_binary)
  tibble(analysis = label,
         k = n_distinct(fit$data$study_id),
         or_med = median(or), or_lo = quantile(or, .025), or_hi = quantile(or, .975),
         beta_dhaplo = if ("b_d_haplo_c" %in% names(dr))
           median(dr$b_d_haplo_c) else NA_real_,
         beta_dhaplo_lo = if ("b_d_haplo_c" %in% names(dr))
           quantile(dr$b_d_haplo_c, .025) else NA_real_,
         beta_dhaplo_hi = if ("b_d_haplo_c" %in% names(dr))
           quantile(dr$b_d_haplo_c, .975) else NA_real_,
         divergences = rstan::get_num_divergent(fit$fit))
}

res <- map_dfr(names(fits), \(key) {
  x <- fits[[key]]
  bind_rows(
    summ_or(file.path(out_dir, paste0("rs_", key, "_m1.rds")), "M1 reported"),
    summ_or(x$metareg, "M1 + delta-haplo meta-regression"),
    summ_or(x$matched, "M1 donor-matched (|delta| <= 15pp)")
  ) |> mutate(outcome = key, median_delta_haplo = x$med_delta, .before = 1)
}) |> mutate(across(where(is.double), \(x) round(x, 3)))

write_csv(res, "data/models/donor_confounding.csv")
print(res, n = Inf)
cat("done\n")
