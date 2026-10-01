# Comparator-backbone sensitivity (reviewer bullet: separate CNI+MTX from
# CNI+MMF comparators; say where PTCy+ATG arms were placed).
#
#   (a) C1 M1 refitted within comparator-backbone subgroups (CNI+MTX only,
#       CNI+MMF only, CNI+MTX+MMF) for OS, aGVHD and CMV where k >= 3.
#   (b) C2 refits excluding studies whose PTCy arm also received ATG
#       (PTCy+ATG arms are placed in the PTCy group of all three comparisons;
#       in C2 they dilute the PTCy-vs-ATG contrast, so this checks them).
#
# Outputs: _fits_rs/backbone_*.rds and data/models/comparator_backbone.csv.

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
a_reg <- arms |> transmute(
  arm_id,
  backbone = case_when(mtx_used == "Y" & mmf_used != "Y" ~ "CNI+MTX",
                       mmf_used == "Y" & mtx_used != "Y" ~ "CNI+MMF",
                       mtx_used == "Y" & mmf_used == "Y" ~ "CNI+MTX+MMF",
                       TRUE ~ NA_character_))
ptcy_atg_arms <- arms |> filter(ptcy_used == "Y", atg_used == "Y") |> pull(arm_id)

mk_long <- function(d) {
  bind_rows(
    d |> transmute(study_id, tp_early, ptcy_binary = 1,
                   events_n = ptcy_e, denom_n = ptcy_n),
    d |> transmute(study_id, tp_early, ptcy_binary = 0,
                   events_n = comp_e, denom_n = comp_n)
  ) |> mutate(study_id = factor(study_id))
}

priors_rs <- c(
  prior(normal(0, 2.5), class = b),
  prior(normal(0, 1.5), class = Intercept),
  prior(student_t(3, 0, 1), class = sd)
)

c1_spec <- tribble(
  ~key,       ~dir,      ~data_file,
  "c1_os",    setb_dir,  "data_c1_os.csv",
  "c1_agvhd", p9_dir,    "data_c1_agvhd.csv",
  "c1_cmv",   p9_dir,    "data_c1_cmv.csv"
)
c2_spec <- tribble(
  ~key,       ~dir,      ~data_file,
  "c2_agvhd", setb_dir,  "data_c2_agvhd.csv",
  "c2_cmv",   setb_dir,  "data_c2_cmv.csv",
  "c2_os",    setb_dir,  "data_c2_os.csv"
)

rhs <- "events_n | trials(denom_n) ~ ptcy_binary + tp_early + (1 + ptcy_binary | study_id)"

set.seed(9158)
seeds <- sample.int(10000, 20)
s <- 0
results <- list()

# (a) backbone subgroups
for (i in seq_len(nrow(c1_spec))) {
  key <- c1_spec$key[i]
  d <- read.csv(file.path(c1_spec$dir[i], c1_spec$data_file[i])) |>
    left_join(a_reg, by = c("comp_arm_id" = "arm_id"))
  for (bb in c("CNI+MTX", "CNI+MMF", "CNI+MTX+MMF")) {
    dd <- d |> filter(backbone == bb) |> mk_long()
    k <- n_distinct(dd$study_id)
    label <- paste(key, bb, sep = " / ")
    if (k < 3) {
      results[[label]] <- tibble(analysis = label, k = k, note = "not estimable (k < 3)")
      next
    }
    s <- s + 1
    f <- file.path(out_dir, sprintf("backbone_%s_%s.rds", key, gsub("[^A-Za-z]", "", bb)))
    if (!file.exists(f)) {
      cat("fitting:", label, "k =", k, "\n")
      fit <- brm(as.formula(rhs), data = dd, family = binomial(), prior = priors_rs,
                 chains = 4, iter = 4000, warmup = 1000, seed = seeds[s],
                 control = list(adapt_delta = 0.99, max_treedepth = 12), refresh = 0)
      saveRDS(fit, f)
    }
    fit <- readRDS(f)
    dr <- as_draws_df(fit)
    or <- exp(dr$b_ptcy_binary)
    results[[label]] <- tibble(analysis = label, k = k,
                               or_med = median(or), or_lo = quantile(or, .025),
                               or_hi = quantile(or, .975),
                               tau_slope = median(dr$sd_study_id__ptcy_binary),
                               divergences = rstan::get_num_divergent(fit$fit), note = "")
  }
}

# (b) C2 excluding PTCy+ATG-arm studies
for (i in seq_len(nrow(c2_spec))) {
  key <- c2_spec$key[i]
  d <- read.csv(file.path(c2_spec$dir[i], c2_spec$data_file[i]))
  n_with <- n_distinct(d$study_id[d$ptcy_arm_id %in% ptcy_atg_arms])
  dd <- d |> filter(!ptcy_arm_id %in% ptcy_atg_arms) |> mk_long()
  k <- n_distinct(dd$study_id)
  label <- paste(key, "excluding PTCy+ATG-arm studies")
  if (k < 3) {
    results[[label]] <- tibble(analysis = label, k = k,
                               n_ptcy_atg_studies = n_with, note = "not estimable (k < 3)")
    next
  }
  s <- s + 1
  f <- file.path(out_dir, sprintf("backbone_%s_noptcyatg.rds", key))
  if (!file.exists(f)) {
    cat("fitting:", label, "k =", k, "\n")
    fit <- brm(as.formula(rhs), data = dd, family = binomial(), prior = priors_rs,
               chains = 4, iter = 4000, warmup = 1000, seed = seeds[s],
               control = list(adapt_delta = 0.99, max_treedepth = 12), refresh = 0)
    saveRDS(fit, f)
  }
  fit <- readRDS(f)
  dr <- as_draws_df(fit)
  or <- exp(dr$b_ptcy_binary)
  results[[label]] <- tibble(analysis = label, k = k,
                             n_ptcy_atg_studies = n_with,
                             or_med = median(or), or_lo = quantile(or, .025),
                             or_hi = quantile(or, .975),
                             tau_slope = median(dr$sd_study_id__ptcy_binary),
                             divergences = rstan::get_num_divergent(fit$fit), note = "")
}

res <- bind_rows(results) |>
  mutate(across(where(is.double), \(x) round(x, 3)))
write_csv(res, "data/models/comparator_backbone.csv")
print(res, n = Inf)
cat("done\n")
