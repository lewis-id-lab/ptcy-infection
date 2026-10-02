# Shared forest-plot library for the PTCy meta-analysis manuscript.
#
# Single source of truth for the per-study + pooled forest panels used by
# notebooks/forest-plots.qmd (article figures 2-4) and
# scripts/regenerate-s8-figures.R (appendix figure S8 series).
#
# Panels show raw per-study odds ratios with Wald 95% CIs (0.5 continuity
# correction for zero cells), per-arm events/N, and REML inverse-variance
# weights. The pooled row is the Bayesian M1 posterior from
# data/models/Table2_setB.csv by default, or any explicitly supplied
# estimate (used for the REML concordance panels).

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(stringr)
  library(ggplot2)
  library(metafor)
  library(patchwork)
})

lancet_red  <- "#b20d35"
lancet_dark <- "#2d2d2d"
lancet_grey <- "#8c8c8c"

theme_forest <- function(base_size = 10) {
  theme_minimal(base_size = base_size) +
    theme(panel.grid        = element_blank(),
          axis.line.x       = element_line(colour = lancet_dark, linewidth = .4),
          axis.ticks.x      = element_line(colour = lancet_dark, linewidth = .3),
          axis.ticks.length.x = unit(2.5, "pt"),
          axis.text         = element_text(colour = lancet_dark),
          axis.title.x      = element_text(colour = lancet_dark, size = rel(.9),
                                           margin = margin(t = 6)),
          plot.title        = element_text(face = "bold", colour = lancet_dark,
                                           hjust = 0, size = rel(1.05)),
          plot.subtitle     = element_text(colour = lancet_grey, hjust = 0,
                                           size = rel(.85)),
          plot.caption      = element_text(colour = lancet_grey, hjust = 0,
                                           size = rel(.75)),
          plot.title.position   = "plot",
          plot.caption.position = "plot",
          plot.background  = element_rect(fill = "white", colour = NA),
          panel.background = element_rect(fill = "white", colour = NA))
}

# Wald log-OR and CI from a 2x2 table, with 0.5 added only where a cell is zero.
study_or <- function(d) {
  d |>
    mutate(zero = ptcy_e == 0 | comp_e == 0 |
                  ptcy_e == ptcy_n | comp_e == comp_n,
           a = ptcy_e + 0.5 * zero, b = ptcy_n - ptcy_e + 0.5 * zero,
           c = comp_e + 0.5 * zero, d2 = comp_n - comp_e + 0.5 * zero,
           yi = log((a / b) / (c / d2)),
           sei = sqrt(1/a + 1/b + 1/c + 1/d2),
           or = exp(yi), lo = exp(yi - 1.96 * sei), hi = exp(yi + 1.96 * sei)) |>
    filter(is.finite(or), is.finite(lo), is.finite(hi))
}

# Set B is the adopted analysis: prefer the vendored model input for a slug,
# falling back to the full analytic dataset for outcomes deduplication left
# untouched.
resolve_data <- function(analytic_file, slug,
                         here = \(...) file.path(if (basename(getwd()) == "notebooks") ".." else ".", ...)) {
  setb <- here("data", "models", paste0("data_", slug, ".csv"))
  if (file.exists(setb)) return(setb)
  here("data", "analytic", analytic_file)
}

POOLED <- "Bayesian pooled (M1)"
HEADER <- "column_header"

# One forest panel. `pooled_spec` optionally overrides the pooled row:
# list(label = "REML pooled", or = ., lo = ., hi = .).
forest <- function(analytic_file, slug, title, subtitle = NULL,
                   pooled_spec = NULL, study_filter = NULL,
                   here = \(...) file.path(if (basename(getwd()) == "notebooks") ".." else ".", ...)) {
  f <- resolve_data(analytic_file, slug, here)
  if (!file.exists(f)) { message("missing: ", analytic_file); return(invisible(NULL)) }
  message("  ", slug, " <- ", sub("^.*/", "", f))

  studies <- read_csv(here("data", "studies.csv"), show_col_types = FALSE) |>
    select(study_id, first_author, pub_year)
  es <- read_csv(f, show_col_types = FALSE) |>
    { \(d) if (!is.null(study_filter)) filter(d, study_id %in% study_filter) else d }() |>
    study_or() |>
    left_join(studies, by = "study_id") |>
    mutate(slab = sprintf("%s (%s)", first_author, pub_year))
  es$slab <- make.unique(es$slab, sep = " – ")

  # REML inverse-variance weights (the frequentist concordance convention)
  es$wt <- as.numeric(weights(rma(yi, sei = sei, data = es, method = "REML",
                                  control = list(silent = TRUE))))

  if (is.null(pooled_spec)) {
    p <- read_csv(here("data", "models", "Table2_setB.csv"),
                  show_col_types = FALSE) |>
      filter(slug == !!slug, model == "m1")
    stopifnot(nrow(p) == 1)
    pooled_spec <- list(label = POOLED, or = p$or_median,
                        lo = p$ci_low, hi = p$ci_high)
    if (is.null(subtitle)) {
      subtitle <- sprintf("k = %d, N = %s, τ = %.2f",
                          p$k, format(p$n_total, big.mark = " "), p$tau)
    }
  }

  pd <- bind_rows(
    es |>
      arrange(yi) |>
      transmute(slab, or, lo, hi,
                ev_p = sprintf("%d/%d", ptcy_e, ptcy_n),
                ev_c = sprintf("%d/%d", comp_e, comp_n),
                wt = sprintf("%.1f", wt), pooled = FALSE),
    tibble(slab = pooled_spec$label, or = pooled_spec$or,
           lo = pooled_spec$lo, hi = pooled_spec$hi,
           ev_p = "—", ev_c = "—", wt = "—", pooled = TRUE)
  )
  hdr <- tibble(slab = HEADER, or = NA_real_, lo = NA_real_, hi = NA_real_,
                ev_p = "PTCy events/N", ev_c = "Comparator events/N",
                wt = "Weight (%)", pooled = FALSE)
  pd <- bind_rows(pd, hdr) |>
    mutate(slab = factor(slab, levels = c(es$slab[order(es$yi)],
                                          pooled_spec$label, HEADER)))

  main <- ggplot(pd, aes(or, slab)) +
    geom_vline(xintercept = 1, linetype = "dashed",
               colour = lancet_grey, linewidth = .35) +
    geom_pointrange(data = filter(pd, !pooled & slab != HEADER),
                    aes(xmin = lo, xmax = hi),
                    shape = 15, size = .3, linewidth = .4, colour = lancet_red) +
    geom_pointrange(data = filter(pd, pooled),
                    aes(xmin = lo, xmax = hi),
                    shape = 18, size = .95, linewidth = .8, colour = lancet_red) +
    scale_x_log10() +
    scale_y_discrete(labels = \(x) ifelse(x == HEADER, "", x)) +
    labs(x = "Odds ratio (log scale)", y = NULL, title = title,
         subtitle = subtitle,
         caption = paste0("Study rows: raw per-study OR with Wald 95% CI (0·5 correction for zero cells). ",
                          "Weights: REML inverse-variance. Diamond: ",
                          pooled_spec$label, ".")) +
    theme_forest() +
    theme(axis.text.y = element_text(size = rel(.85)))

  side <- ggplot(pd, aes(y = slab)) +
    geom_text(aes(x = 1, label = ev_p), size = 2.4, colour = lancet_dark) +
    geom_text(aes(x = 2, label = ev_c), size = 2.4, colour = lancet_dark) +
    geom_text(aes(x = 3, label = wt), size = 2.4, colour = lancet_dark) +
    scale_x_continuous(limits = c(0.4, 3.6), expand = c(0, 0)) +
    scale_y_discrete(labels = \(x) ifelse(x == HEADER, "", x)) +
    labs(x = NULL, y = NULL) +
    theme_forest() +
    theme(axis.text = element_blank(),
          axis.ticks = element_blank(),
          axis.ticks.length = unit(0, "pt"),
          axis.line.x = element_blank(),
          axis.text.y = element_text(size = rel(.85)),
          plot.caption = element_blank())

  main + side + plot_layout(widths = c(2.5, 1.9))
}

export_fig <- function(plot, stem, w = 9, h = 9,
                       here = \(...) file.path(if (basename(getwd()) == "notebooks") ".." else ".", ...)) {
  for (dev in c("png", "pdf", "svg")) {
    ggsave(here("figures", paste0(stem, ".", dev)), plot,
           width = w, height = h, dpi = 300, device = dev, bg = "white")
  }
  invisible(stem)
}
