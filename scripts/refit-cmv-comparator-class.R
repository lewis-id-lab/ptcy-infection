# Formal test of the C1 vs C2 CMV difference (reviewer bullet: "Test the C1 v
# C2 CMV difference formally ... Two separate pooled ORs in different
# populations cannot establish CNI < PTCy < ATG").
#
# Meta-regression on comparator class: the C1 and C2 CMV datasets are pooled
# and the model includes a comparator-class main effect and a
# PTCy-by-comparator-class interaction. The interaction (delta) is the formal
# estimate of the difference in the PTCy effect between comparator classes.
# C3 is a within-PTCy comparison and is not included.
#
# Outputs: _fits_rs/cmv_comparator_class.rds and
# data/models/cmv_comparator_class.csv.

suppressPackageStartupMessages({
  library(tidyverse)
  library(brms)
})

analysis_dir <- path.expand("~/ptcy_metaanalys")
setb_dir <- file.path(analysis_dir, "03_models/set_b")
p9_dir <- file.path(analysis_dir, "03_models/post_block9")
out_dir <- path.expand("~/ptcy-infection/_fits_rs")
dir.create(out_dir, showWarnings = FALSE)

mk_long <- function(d, c2) {
  bind_rows(
    d |> transmute(study_id, tp_early, c2, ptcy_binary = 1,
                   events_n = ptcy_e, denom_n = ptcy_n),
    d |> transmute(study_id, tp_early, c2, ptcy_binary = 0,
                   events_n = comp_e, denom_n = comp_n)
  )
}

dat <- bind_rows(
  read.csv(file.path(p9_dir, "data_c1_cmv.csv")) |> mk_long(0L),
  read.csv(file.path(setb_dir, "data_c2_cmv.csv")) |> mk_long(1L)
) |> mutate(study_id = factor(study_id))

priors_rs <- c(
  prior(normal(0, 2.5), class = b),
  prior(normal(0, 1.5), class = Intercept),
  prior(student_t(3, 0, 1), class = sd)
)

set.seed(8863)
out_file <- file.path(out_dir, "cmv_comparator_class.rds")
if (!file.exists(out_file)) {
  cat("fitting comparator-class meta-regression, k =", n_distinct(dat$study_id), "\n")
  fit <- brm(
    events_n | trials(denom_n) ~ ptcy_binary * c2 + tp_early +
      (1 + ptcy_binary | study_id),
    data = dat, family = binomial(), prior = priors_rs,
    chains = 4, iter = 4000, warmup = 1000,
    control = list(adapt_delta = 0.99, max_treedepth = 12), refresh = 0
  )
  saveRDS(fit, out_file)
}

fit <- readRDS(out_file)
dr <- as_draws_df(fit)

# PTCy effect in C1 (b_ptcy_binary), in C2 (b + interaction), and the difference
or_c1 <- exp(dr$b_ptcy_binary)
or_c2 <- exp(dr$b_ptcy_binary + dr$`b_ptcy_binary:c2`)
ratio <- exp(dr$`b_ptcy_binary:c2`)

res <- bind_rows(
  tibble(quantity = "PTCy effect vs CNI-based (C1)", or_med = median(or_c1),
         or_lo = quantile(or_c1, .025), or_hi = quantile(or_c1, .975)),
  tibble(quantity = "PTCy effect vs ATG (C2)", or_med = median(or_c2),
         or_lo = quantile(or_c2, .025), or_hi = quantile(or_c2, .975)),
  tibble(quantity = "Difference (C2 vs C1, ratio of ORs)", or_med = median(ratio),
         or_lo = quantile(ratio, .025), or_hi = quantile(ratio, .975))
) |> mutate(
  k = n_distinct(dat$study_id),
  prob_c1_greater = mean(or_c1 > or_c2),
  divergences = rstan::get_num_divergent(fit$fit),
  .before = 1
) |> mutate(across(where(is.double), \(x) round(x, 3)))

write_csv(res, "data/models/cmv_comparator_class.csv")
print(res)
cat("done\n")
