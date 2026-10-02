# Round-3 adjudication (2026-10-02): PDF-verified provenance for the 41 pooled
# arms whose input_class was cumulative_incidence_derived_count or
# kaplan_meier_derived_count.
#   - 31 arms confirmed derived -> events nulled in data/models/*.csv and
#     data/analytic/*.csv; affected models refit; Table2_setB.csv updated.
#   - 10 arms confirmed reported counts -> input_class corrected to
#     observed_count (studies 2, 122, 144, 299, 397 NRM/OS, 399).
# Run from project root: Rscript -e 'source("scripts/adjudicate-censored-pool.R")'

suppressPackageStartupMessages({
  library(tidyverse)
  library(brms)
})

txt_dir <- "/Users/russelllewis/main/ptcy_metaanalys/pdf_text"
verdicts <- bind_rows(
  read_csv(file.path(txt_dir, "results_censA.csv"), show_col_types = FALSE),
  read_csv(file.path(txt_dir, "results_censB.csv"), show_col_types = FALSE)) |>
  mutate(across(c(study_id, arm_id), as.character),
         arm_id = str_trim(arm_id), category = str_trim(category),
         timepoint = str_trim(timepoint))

# ── 1. Update outcomes.csv input_class per verdict ──
out <- read_csv("data/outcomes.csv", show_col_types = FALSE,
                col_types = cols(.default = col_character()))
out <- out |>
  left_join(verdicts |>
              select(study_id, arm_id, category, timepoint, verdict, evidence),
            by = c("study_id", "arm_id",
                   "outcome_category" = "category", "timepoint")) |>
  mutate(
    input_class = case_when(
      verdict == "reported_count" ~ "observed_count",
      verdict == "derived_from_cif_or_pct" & ci_method == "Kaplan_Meier" ~ "kaplan_meier_derived_count",
      verdict == "derived_from_cif_or_pct" ~ "cumulative_incidence_derived_count",
      TRUE ~ input_class),
    data_quality_flag = if_else(verdict == "derived_from_cif_or_pct", "derived",
                                data_quality_flag),
    extraction_notes = if_else(
      !is.na(verdict),
      paste0(coalesce(extraction_notes, ""),
             " [PDF-verified (pool audit) 2026-10-02: ", verdict, ". ",
             str_trunc(coalesce(evidence, ""), 120), "]"),
      extraction_notes)) |>
  select(-verdict, -evidence)
write_csv(out, "data/outcomes.csv")

# ── 2. Null events for confirmed-derived arms in model + analytic datasets ──
derived <- verdicts |> filter(verdict == "derived_from_cif_or_pct")
null_in <- function(path, arm_cols = c("ptcy_arm_id", "comp_arm_id"),
                    ev_cols = c("ptcy_e", "comp_e")) {
  d <- read_csv(path, show_col_types = FALSE)
  if (!all(arm_cols %in% names(d))) return(0L)
  n_changed <- 0L
  for (i in seq_len(nrow(derived))) {
    r <- derived[i, ]
    for (j in seq_along(arm_cols)) {
      idx <- which(d$study_id == as.numeric(r$study_id) &
                   as.character(d[[arm_cols[j]]]) == r$arm_id &
                   d$timepoint_used == r$timepoint &
                   d$category == r$category)
      if (length(idx) && !is.na(d[[ev_cols[j]]][idx])) {
        d[[ev_cols[j]]][idx] <- NA_real_
        n_changed <- n_changed + 1L
      }
    }
  }
  if (n_changed) write_csv(d, path)
  n_changed
}
model_csvs <- list.files("data/models", pattern = "^data_c\\d.*\\.csv$", full.names = TRUE)
an_csvs <- list.files("data/analytic", pattern = "^C\\d_.*\\.csv$", full.names = TRUE)
n_model <- sum(map_int(model_csvs, null_in))
n_an <- sum(map_int(an_csvs, null_in))
cat("nulled events: models", n_model, ", analytic", n_an, "\n")

# ── 3. Refit affected Table 2 models ──
# Affected files = model datasets containing at least one derived arm
affected_files <- map_chr(model_csvs, function(f) {
  d <- read_csv(f, show_col_types = FALSE)
  hit <- any(paste(d$study_id, d$ptcy_arm_id, d$category, d$timepoint_used) %in%
             paste(derived$study_id, derived$arm_id, derived$category, derived$timepoint)) ||
         any(paste(d$study_id, d$comp_arm_id, d$category, d$timepoint_used) %in%
             paste(derived$study_id, derived$arm_id, derived$category, derived$timepoint))
  if (hit) basename(f) else NA_character_
}) |> discard(is.na)
cat("affected model datasets:", paste(affected_files, collapse = ", "), "\n")
# map file -> (slug, data_file)
fits_needed <- tribble(
  ~key,          ~m2,    ~data_file,
  "c1_os_m1",    FALSE,  "data_c1_os.csv",
  "c1_os_m2",    TRUE,   "data_c1_os.csv",
  "c2_os_m1",    FALSE,  "data_c2_os.csv",
  "c2_os_m2",    TRUE,   "data_c2_os.csv",
  "c3_os_m1",    FALSE,  "data_c3_os.csv",
  "c1_nrm_m1",   FALSE,  "data_c1_nrm.csv",
  "c1_nrm_m2",   TRUE,   "data_c1_nrm.csv",
  "c3_nrm_m1",   FALSE,  "data_c3_nrm.csv",
  "c1_cgvhd_m1", FALSE,  "data_c1_cgvhd_ms.csv",
  "c3_cgvhd_m1", FALSE,  "data_c3_cgvhd.csv",
  "c1_cmv_m1",   FALSE,  "data_c1_cmv.csv",
  "c1_cmv_m2",   TRUE,   "data_c1_cmv.csv",
  "c2_agvhd_m1", FALSE,  "data_c2_agvhd.csv",
  "c3_agvhd_m1", FALSE,  "data_c3_agvhd.csv"
) |> filter(data_file %in% affected_files)

priors_rs <- c(
  prior(normal(0, 2.5), class = b),
  prior(normal(0, 1.5), class = Intercept),
  prior(student_t(3, 0, 1), class = sd)
)
mk_data <- function(d, m2) {
  long <- bind_rows(
    d |> transmute(study_id, tp_early, ptcy_binary = 1, events_n = ptcy_e,
                   denom_n = ptcy_n, steroid_pct = ptcy_steroid_pct),
    d |> transmute(study_id, tp_early, ptcy_binary = 0, events_n = comp_e,
                   denom_n = comp_n, steroid_pct = comp_steroid_pct)) |>
    filter(!is.na(events_n)) |>
    mutate(study_id = factor(study_id))
  if (!m2) return(long)
  long |> filter(!is.na(steroid_pct)) |>
    mutate(steroid_pct_c = steroid_pct - mean(steroid_pct))
}
num_div <- function(fit) {
  tryCatch(sum(fit$fit$diagnostic_summary()$num_divergent),
           error = function(e) rstan::get_num_divergent(fit$fit))
}

set.seed(5147)
seeds <- sample.int(10000, nrow(fits_needed))
rs_dir <- path.expand("~/ptcy-infection/_fits_rs")

res <- list()
for (i in seq_len(nrow(fits_needed))) {
  row <- fits_needed[i, ]
  cat("fitting:", row$key, "\n")
  dat <- read.csv(file.path("data/models", row$data_file)) |> mk_data(row$m2)
  rhs <- if (row$m2) {
    "events_n | trials(denom_n) ~ ptcy_binary + tp_early + steroid_pct_c + (1 + ptcy_binary | study_id)"
  } else {
    "events_n | trials(denom_n) ~ ptcy_binary + tp_early + (1 + ptcy_binary | study_id)"
  }
  fit <- brm(as.formula(rhs), data = dat, family = binomial(), prior = priors_rs,
             chains = 4, iter = 4000, warmup = 1000, seed = seeds[i],
             control = list(adapt_delta = 0.99), refresh = 0, backend = "cmdstanr")
  div <- num_div(fit)
  if (div > 0) {
    fit <- brm(as.formula(rhs), data = dat, family = binomial(), prior = priors_rs,
               chains = 4, iter = 4000, warmup = 1000, seed = seeds[i],
               control = list(adapt_delta = 0.999), refresh = 0, backend = "cmdstanr")
    div <- num_div(fit)
  }
  saveRDS(fit, file.path(rs_dir, paste0("rs_", row$key, ".rds")))
  dr <- as_draws_df(fit)
  or <- exp(dr$b_ptcy_binary)
  theta_new <- dr$b_ptcy_binary + rnorm(nrow(dr), 0, dr$sd_study_id__ptcy_binary)
  pi_q <- quantile(exp(theta_new), c(.025, .975))
  res[[row$key]] <- tibble(
    key = row$key, k = n_distinct(dat$study_id), n_total = sum(dat$denom_n),
    or_med = median(or), or_lo = quantile(or, .025), or_hi = quantile(or, .975),
    tau_slope = median(dr$sd_study_id__ptcy_binary),
    pi_low = unname(pi_q[1]), pi_high = unname(pi_q[2]),
    max_rhat = max(summary(fit)$fixed$Rhat, na.rm = TRUE), divergences = div)
}
res <- bind_rows(res)
print(res, width = 200)

# ── 4. Update Table2_setB.csv ──
keymap <- tribble(
  ~slug,        ~model,       ~key,
  "c1_os",      "m1",         "c1_os_m1",
  "c1_os",      "m2_steroid", "c1_os_m2",
  "c2_os",      "m1",         "c2_os_m1",
  "c2_os",      "m2_steroid", "c2_os_m2",
  "c3_os",      "m1",         "c3_os_m1",
  "c1_nrm",     "m1",         "c1_nrm_m1",
  "c1_nrm",     "m2_steroid", "c1_nrm_m2",
  "c3_nrm",     "m1",         "c3_nrm_m1",
  "c1_cgvhd_ms","m1",         "c1_cgvhd_m1",
  "c3_cgvhd",   "m1",         "c3_cgvhd_m1",
  "c1_cmv",     "m1",         "c1_cmv_m1",
  "c1_cmv",     "m2_steroid", "c1_cmv_m2",
  "c2_agvhd",   "m1",         "c2_agvhd_m1",
  "c3_agvhd",   "m1",         "c3_agvhd_m1"
)
t2 <- read_csv("data/models/Table2_setB.csv", show_col_types = FALSE)
for (i in seq_len(nrow(keymap))) {
  r <- res |> filter(key == keymap$key[i])
  if (!nrow(r)) next
  idx <- which(t2$slug == keymap$slug[i] & t2$model == keymap$model[i])
  t2$k[idx]         <- r$k
  t2$n_total[idx]   <- r$n_total
  t2$or_median[idx] <- round(r$or_med, 3)
  t2$ci_low[idx]    <- round(r$or_lo, 3)
  t2$ci_high[idx]   <- round(r$or_hi, 3)
  t2$tau[idx]       <- round(r$tau_slope, 3)
  t2$pi_low[idx]    <- round(r$pi_low, 3)
  t2$pi_high[idx]   <- round(r$pi_high, 3)
  t2$source[idx]    <- "random-slope refit 2026-10-02 post censored-pool adjudication"
}
write_csv(t2, "data/models/Table2_setB.csv")
write_csv(res, "data/models/refit_2026-10-02_censored_pool.csv")
cat("done\n")