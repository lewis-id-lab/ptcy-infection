# Regenerate all fit-dependent figures and the pooled-estimate CSV after the
# switch to the random-slope primary model (random study intercept + random
# PTCy-effect slope, fitted by scripts/refit-random-slope.R).
#
# Outputs:
#   data/models/Table2_setB.csv        pooled estimates for notebooks/forest-plots.qmd
#   figures/FigureS7b/c/d, S9a         appendix figures from the new fits
#   figures/Figure4_infections_forest  main-text infection panels (BSI/IFI/BK)
#
# S8 frequentist forests are data-driven and unaffected by the model switch;
# they are not rebuilt here (see scripts/regenerate-appendix-s7-s8.R).

suppressPackageStartupMessages({
  library(tidyverse)
  library(brms)
  library(bayesplot)
  library(metafor)
  library(patchwork)
})

analysis_dir <- path.expand("~/ptcy_metaanalys")
p9_dir <- file.path(analysis_dir, "03_models/post_block9")
rs_dir <- path.expand("~/ptcy-infection/_fits_rs")
fig_dir <- path.expand("~/ptcy-infection/figures")
proj_dir <- path.expand("~/ptcy-infection")

# JAMA theme + palette from the analysis website's shared setup
website_dir <- file.path(analysis_dir, "05_website")
old_wd <- setwd(website_dir)
source("_common.R")
setwd(old_wd)

studies_df <- read_csv(file.path(analysis_dir, "02_extraction/studies.csv"),
                       show_col_types = FALSE)

rs <- function(key) readRDS(file.path(rs_dir, paste0("rs_", key, ".rds")))

save3 <- function(p, stem, w, h) {
  ggsave(file.path(fig_dir, paste0(stem, ".png")), p, width = w, height = h, dpi = 320)
  ggsave(file.path(fig_dir, paste0(stem, ".pdf")), p, width = w, height = h,
         device = cairo_pdf)
  ggsave(file.path(fig_dir, paste0(stem, ".svg")), p, width = w, height = h)
  invisible(stem)
}

# ── 1. Pooled-estimate CSV for the forest-plot notebook ──
# 2026-10-02: SKIPPED by default — Table2_setB.csv is now maintained by
# scripts/refit-after-pdf-adjudication.R (which also carries prediction
# intervals and per-fit provenance stamps). Set WRITE_TABLE2=1 to restore the
# old behaviour of rebuilding the whole table from the rs fits (no PI columns).
write_table2 <- identical(Sys.getenv("WRITE_TABLE2"), "1")
csv_map <- tribble(
  ~slug,          ~model,        ~key,
  "c1_os",        "m1",          "c1_os_m1",
  "c1_os",        "m2_steroid",  "c1_os_m2",
  "c1_rrm",       "m1",          "c1_rrm_m1",
  "c1_rrm",       "m2_steroid",  "c1_rrm_m2",
  "c1_irm",       "m1",          "c1_irm_m1",
  "c1_cgvhd_ms",  "m1",          "c1_cgvhd_m1",
  "c1_cgvhd_any", "m1",          "c1_cgvhdany_m1",
  "c1_nrm",       "m1",          "c1_nrm_m1",
  "c1_nrm",       "m2_steroid",  "c1_nrm_m2",
  "c1_agvhd",     "m1",          "c1_agvhd_m1",
  "c1_cmv",       "m1",          "c1_cmv_m1",
  "c1_cmv",       "m2_steroid",  "c1_cmv_m2",
  "c1_bsi",       "m1",          "c1_bsi_m1",
  "c1_ifi_any",   "m1",          "c1_ifi_m1",
  "c1_bk",        "m1",          "c1_bk_m1",
  "c2_os",        "m1",          "c2_os_m1",
  "c2_os",        "m2_steroid",  "c2_os_m2",
  "c2_agvhd",     "m1",          "c2_agvhd_m1",
  "c2_cmv",       "m1",          "c2_cmv_m1",
  "c2_cmv",       "m2_steroid",  "c2_cmv_m2",
  "c2_rrm",       "m1",          "c2_rrm_m1",
  "c2_bk",        "m1",          "c2_bk_m1",
  "c2_irm",       "m1",          "c2_irm_m1",
  "c2_cgvhd_ms",  "m1",          "c2_cgvhd_m1",
  "c3_os",        "m1",          "c3_os_m1",
  "c3_agvhd",     "m1",          "c3_agvhd_m1",
  "c3_nrm",       "m1",          "c3_nrm_m1",
  "c3_rrm",       "m1",          "c3_rrm_m1",
  "c3_cgvhd",     "m1",          "c3_cgvhd_m1"
)

if (write_table2) {
  pooled_new <- pmap_dfr(csv_map, function(slug, model, key) {
    fit <- rs(key)
    dr <- as_draws_df(fit)
    or <- exp(dr$b_ptcy_binary)
    tibble(
      slug = slug, model = model,
      k = n_distinct(fit$data$study_id),
      n_total = sum(fit$data$denom_n),
      or_median = median(or),
      ci_low = unname(quantile(or, 0.025)),
      ci_high = unname(quantile(or, 0.975)),
      tau = median(dr$sd_study_id__ptcy_binary),
      source = "random-slope refit 2026-09-30"
    )
  })
  write_csv(pooled_new, file.path(proj_dir, "data/models/Table2_setB.csv"))
  cat("wrote data/models/Table2_setB.csv:", nrow(pooled_new), "rows\n")
} else {
  cat("skip Table2 rewrite (WRITE_TABLE2 != 1); figures only\n")
}

# ── 2. Figure S7b: traces, b (top) and effect-SD (bottom), OS and CMV ──
color_scheme_set(c(jama_navy, jama_blue, jama_steel, jama_light_blue,
                   jama_grey, jama_dark))
trace_grid <- function(fit, title) {
  list(
    mcmc_trace(fit, regex_pars = "b_.*ptcy_binary") +
      labs(title = title, subtitle = "b_ptcy_binary") +
      theme_jama(base_size = 9) + theme(legend.position = "none"),
    mcmc_trace(fit, regex_pars = "sd_study_id__ptcy_binary") +
      labs(subtitle = "sd of PTCy effect (tau)") +
      theme_jama(base_size = 9) + theme(legend.position = "none")
  )
}
os_panels <- trace_grid(rs("c1_os_m1"), "OS M1")
cmv_panels <- trace_grid(rs("c1_cmv_m1"), "CMV M1")
fig_s7b <- (os_panels[[1]] | cmv_panels[[1]]) / (os_panels[[2]] | cmv_panels[[2]])
save3(fig_s7b, "FigureS7b_trace_plots", 10, 6)

# ── 3. Figure S7c: posteriors of the between-study SD of the PTCy effect ──
tau_models <- c("OS", "NRM", "aGVHD", "CMV", "BSI", "IFI")
tau_keys <- c("c1_os_m1", "c1_nrm_m1", "c1_agvhd_m1", "c1_cmv_m1",
              "c1_bsi_m1", "c1_ifi_m1")
tau_data <- map2_dfr(tau_keys, tau_models, function(k, nm) {
  tibble(Outcome = nm,
         tau = as_draws_df(rs(k))$sd_study_id__ptcy_binary)
})
set.seed(8471)
tau_data <- bind_rows(
  tau_data,
  tibble(Outcome = "Prior", tau = abs(rt(12000, df = 3)))
) |>
  mutate(Outcome = factor(Outcome, levels = c(tau_models, "Prior")))

fig_s7c <- ggplot(tau_data, aes(x = tau, y = Outcome, fill = Outcome)) +
  ggridges::geom_density_ridges(alpha = 0.55, scale = 1.2, colour = jama_dark,
                                linewidth = 0.3) +
  scale_fill_manual(values = c(
    "OS" = jama_navy, "NRM" = jama_blue, "aGVHD" = jama_steel,
    "CMV" = jama_light_blue, "BSI" = jama_grey, "IFI" = "#b8860b",
    "Prior" = jama_light_grey
  )) +
  labs(x = "Between-study SD of the PTCy effect (tau)", y = NULL) +
  coord_cartesian(xlim = c(0, 3)) +
  theme_jama() +
  theme(legend.position = "none")
save3(fig_s7c, "FigureS7c_tau_posteriors", 8, 5)

# ── 4. Figure S7d: posterior predictive checks ──
set.seed(2914)
ppc_points <- function(fit, outcome) {
  yrep <- posterior_predict(fit, ndraws = 500)
  d <- fit$data
  tibble(outcome = outcome,
         obs = d$events_n / d$denom_n,
         pred = colMeans(yrep) / d$denom_n)
}
ppc_c1 <- bind_rows(
  ppc_points(rs("c1_os_m1"), "OS"), ppc_points(rs("c1_nrm_m1"), "NRM"),
  ppc_points(rs("c1_agvhd_m1"), "aGVHD"), ppc_points(rs("c1_cmv_m1"), "CMV"),
  ppc_points(rs("c1_bsi_m1"), "BSI"), ppc_points(rs("c1_ifi_m1"), "IFI"),
  ppc_points(rs("c1_rrm_m1"), "RRM"), ppc_points(rs("c1_bk_m1"), "BK"),
  ppc_points(rs("c1_irm_m1"), "IRM")
)
ppc_c2 <- bind_rows(
  ppc_points(rs("c2_os_m1"), "OS"), ppc_points(rs("c2_nrm_m1"), "NRM"),
  ppc_points(rs("c2_agvhd_m1"), "aGVHD"), ppc_points(rs("c2_cmv_m1"), "CMV"),
  ppc_points(rs("c2_rrm_m1"), "RRM"), ppc_points(rs("c2_bk_m1"), "BK")
)
ppc_plot <- function(dat, title) {
  ggplot(dat, aes(x = obs, y = pred)) +
    geom_abline(slope = 1, intercept = 0, linetype = "dashed",
                colour = jama_grey, linewidth = 0.4) +
    geom_point(alpha = 0.5, size = 0.9, colour = jama_navy) +
    facet_wrap(~ outcome, scales = "free") +
    labs(x = "Observed event proportion",
         y = "Posterior predictive mean", title = title) +
    theme_jama(base_size = 9)
}
save3(ppc_plot(ppc_c1, "Posterior predictive checks — comparison 1"),
      "FigureS7d_i_ppc_C1", 9, 7)
save3(ppc_plot(ppc_c2, "Posterior predictive checks — comparison 2"),
      "FigureS7d_ii_ppc_C2", 9, 6)

# ── 5. Figure S9a: CMV sensitivity posteriors (OR scale) ──
cmv_specs <- c("Primary model (k = 22)" = "c1_cmv_m1",
               "Post-2020 (k = 17)" = "c1_cmv_post2020_m1",
               "Haploidentical-dominant (k = 12)" = "c1_cmv_haplo_m1")
cmv_draws <- imap_dfr(cmv_specs, function(key, nm) {
  tibble(model = nm, or = exp(as_draws_df(rs(key))$b_ptcy_binary))
}) |>
  mutate(model = factor(model, levels = names(cmv_specs)))
cmv_pts <- cmv_draws |>
  group_by(model) |>
  summarise(med = median(or), lo = quantile(or, .025), hi = quantile(or, .975),
            .groups = "drop")

fig_s9a <- ggplot(cmv_draws, aes(x = or, y = model)) +
  ggridges::geom_density_ridges(fill = jama_light_blue, alpha = 0.6,
                                colour = jama_dark, linewidth = 0.3) +
  geom_pointrange(data = cmv_pts,
                  aes(x = med, y = model, xmin = lo, xmax = hi),
                  colour = jama_navy, size = 0.4, linewidth = 0.6,
                  inherit.aes = FALSE) +
  geom_vline(xintercept = 1, linetype = "dashed", colour = jama_grey,
             linewidth = 0.4) +
  labs(x = "Odds ratio for CMV reactivation (posterior)", y = NULL,
       caption = "Points: posterior median with 95% CrI.") +
  theme_jama(base_size = 10)
save3(fig_s9a, "FigureS9a_CMV_sensitivity", 8, 4.5)

# ── 6. Figure 4: BSI / IFI / BK panels with posterior density strips ──
infection_panel <- function(key, data_file, title, panel_tag) {
  fit <- rs(key)
  dat <- read.csv(file.path(p9_dir, data_file))
  es <- escalc(measure = "OR", ai = ptcy_e, n1i = ptcy_n, ci = comp_e,
               n2i = comp_n, data = dat, add = 0.5, to = "only0") |>
    merge(studies_df[, c("study_id", "first_author", "pub_year")],
          by = "study_id", all.x = TRUE)
  es$slab <- make.unique(paste0(es$first_author, " (", es$pub_year, ")"),
                         sep = " – ")
  es <- es[order(es$yi), ]
  es$slab <- factor(es$slab, levels = es$slab)

  draws <- exp(as_draws_df(fit)$b_ptcy_binary)
  pooled <- tibble(med = median(draws), lo = quantile(draws, .025),
                   hi = quantile(draws, .975))
  dens <- density(draws, n = 512)
  ddf <- tibble(or = dens$x, d = dens$y)

  # Match the main-text forest figures (notebooks/forest-plots.qmd): crimson
  # markers on a clean white field, Lancet Haematology style
  lancet_red  <- "#b20d35"
  lancet_dark <- "#2d2d2d"
  lancet_grey <- "#8c8c8c"
  theme_lancet <- function(base_size = 9) {
    theme_minimal(base_size = base_size) +
      theme(panel.grid = element_blank(),
            axis.line.x = element_line(colour = lancet_dark, linewidth = .4),
            axis.ticks.x = element_line(colour = lancet_dark, linewidth = .3),
            axis.text = element_text(colour = lancet_dark),
            axis.title.x = element_text(colour = lancet_dark, size = rel(.9)),
            plot.title = element_text(face = "bold", colour = lancet_dark,
                                      hjust = 0, size = rel(1.05)),
            plot.subtitle = element_text(colour = lancet_grey, hjust = 0,
                                         size = rel(.85)),
            plot.title.position = "plot",
            plot.background = element_rect(fill = "white", colour = NA),
            panel.background = element_rect(fill = "white", colour = NA))
  }

  p_dens <- ggplot(ddf, aes(or, d)) +
    geom_area(fill = lancet_red, alpha = 0.25) +
    geom_vline(xintercept = 1, linetype = "dashed", colour = lancet_grey,
               linewidth = 0.35) +
    coord_cartesian(xlim = range(c(ddf$or, 1))) +
    labs(title = title, subtitle = sprintf(
      "k = %d, N = %s, pooled OR %.2f [%.2f–%.2f], tau = %.2f",
      n_distinct(fit$data$study_id),
      format(sum(fit$data$denom_n), big.mark = " "),
      pooled$med, pooled$lo, pooled$hi,
      median(as_draws_df(fit)$sd_study_id__ptcy_binary)),
      tag = panel_tag) +
    theme_lancet() +
    theme(axis.text.x = element_blank(), axis.title.x = element_blank(),
          axis.line.x = element_blank(), axis.ticks.x = element_blank(),
          axis.text.y = element_blank(), axis.title.y = element_blank(),
          axis.ticks.y = element_blank(),
          plot.tag = element_text(face = "bold", size = 14))

  pd <- bind_rows(
    es |> transmute(slab = as.character(slab), or = exp(yi),
                    lo = exp(yi - 1.96 * sqrt(vi)),
                    hi = exp(yi + 1.96 * sqrt(vi)), pooled = FALSE),
    tibble(slab = "Bayesian pooled (M1)", or = pooled$med, lo = pooled$lo,
           hi = pooled$hi, pooled = TRUE)
  )
  pd$slab <- factor(pd$slab, levels = c("Bayesian pooled (M1)", levels(es$slab)))

  p_for <- ggplot(pd, aes(or, slab)) +
    geom_vline(xintercept = 1, linetype = "dashed", colour = lancet_grey,
               linewidth = 0.35) +
    geom_pointrange(data = filter(pd, !pooled), aes(xmin = lo, xmax = hi),
                    shape = 15, size = 0.3, linewidth = 0.4, colour = lancet_red) +
    geom_pointrange(data = filter(pd, pooled), aes(xmin = lo, xmax = hi),
                    shape = 18, size = 0.8, linewidth = 0.7, colour = lancet_red) +
    scale_x_log10() +
    labs(x = "Odds ratio (log scale)", y = NULL) +
    theme_lancet() +
    theme(axis.text.y = element_text(size = rel(0.85)))

  p_dens / p_for + plot_layout(heights = c(1, 4))
}

f4a <- infection_panel("c1_bsi_m1", "data_c1_bsi.csv", "Bloodstream infection", "A.")
f4b <- infection_panel("c1_ifi_m1", "data_c1_ifi_any.csv",
                       "Invasive fungal infection", "B.")
f4c <- infection_panel("c1_bk_m1", "data_c1_bk.csv", "BK virus reactivation", "C.")
fig4 <- wrap_plots(f4a, f4b, f4c, ncol = 1)
save3(fig4, "Figure4_infections_forest", 8, 12)

cat("done\n")
