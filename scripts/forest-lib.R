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

# Transplantation and Cellular Therapy: grayscale (color is charged in print),
# Arial lettering.
fig_ink  <- "#000000"
fig_grey <- "#666666"
fig_font <- "Arial"

theme_forest <- function(base_size = 9, base_family = fig_font) {
  theme_minimal(base_size = base_size, base_family = base_family) +
    theme(panel.grid        = element_blank(),
          axis.line.x       = element_line(colour = fig_ink, linewidth = .4),
          axis.ticks.x      = element_line(colour = fig_ink, linewidth = .3),
          axis.ticks.length.x = unit(2.5, "pt"),
          axis.text         = element_text(colour = fig_ink),
          axis.title.x      = element_text(colour = fig_ink, size = rel(.9),
                                           margin = margin(t = 6)),
          plot.title        = element_text(face = "bold", colour = fig_ink,
                                           hjust = 0, size = rel(1.05)),
          plot.subtitle     = element_text(colour = fig_grey, hjust = 0,
                                           size = rel(.85)),
          plot.caption      = element_text(colour = fig_grey, hjust = 0,
                                           size = rel(.75)),
          plot.tag          = element_text(face = "bold", size = rel(1.3)),
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
forest <- function(analytic_file, slug, title = NULL, subtitle = NULL,
                   pooled_spec = NULL, study_filter = NULL,
                   caption = TRUE, tag = NULL,
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
                          p$k, format(p$n_total, big.mark = ","), p$tau)
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
               colour = fig_grey, linewidth = .35) +
    geom_pointrange(data = filter(pd, !pooled & slab != HEADER),
                    aes(xmin = lo, xmax = hi),
                    shape = 15, size = .3, linewidth = .4, colour = fig_ink) +
    geom_pointrange(data = filter(pd, pooled),
                    aes(xmin = lo, xmax = hi),
                    shape = 18, size = .95, linewidth = .8, colour = fig_ink) +
    # plain numbers on the axis (no 1e-02 notation)
    scale_x_log10(labels = \(x) format(x, scientific = FALSE, drop0trailing = TRUE, trim = TRUE)) +
    # drop = FALSE keeps the (empty) header row so this panel's rows stay
    # aligned 1:1 with the side panel, which draws the header text
    scale_y_discrete(labels = \(x) ifelse(x == HEADER, "", x), drop = FALSE) +
    # Article figures carry no title or caption on the image (TCT puts both in
    # the legend); appendix panels keep them.
    labs(x = "Odds ratio (log scale)", y = NULL, title = title,
         subtitle = subtitle, tag = tag,
         caption = if (isTRUE(caption))
           paste0("Study rows: raw per-study OR with Wald 95% CI (0.5 correction for zero cells). ",
                  "Weights: REML inverse-variance. Diamond: ", pooled_spec$label, ".")) +
    theme_forest() +
    theme(axis.text.y = element_text(size = rel(.85)))

  side <- ggplot(pd, aes(y = slab)) +
    geom_text(aes(x = 1, label = ev_p), size = 2.4, colour = fig_ink, family = fig_font) +
    geom_text(aes(x = 2, label = ev_c), size = 2.4, colour = fig_ink, family = fig_font) +
    geom_text(aes(x = 3, label = wt), size = 2.4, colour = fig_ink, family = fig_font) +
    scale_x_continuous(limits = c(0.4, 3.6), expand = c(0, 0)) +
    scale_y_discrete(labels = \(x) ifelse(x == HEADER, "", x), drop = FALSE) +
    labs(x = NULL, y = NULL) +
    theme_forest() +
    theme(axis.text = element_blank(),
          axis.ticks = element_blank(),
          axis.ticks.x = element_blank(),
          axis.ticks.length = unit(0, "pt"),
          axis.line.x = element_blank(),
          # study labels are drawn once, on the forest panel
          axis.text.y = element_blank(),
          plot.caption = element_blank())

  main + side + plot_layout(widths = c(2.5, 1.9))
}

# Writes PNG (300 dpi, for Word and the web build), PDF (vector, fonts embedded),
# SVG (web) and TIFF (600 dpi, LZW) -- TCT asks for 600-dpi art in EPS/PDF or TIFF.
# Default width 7.5 in is the journal's two-column (190 mm) figure.
export_fig <- function(plot, stem, w = 7.5, h = 8,
                       here = \(...) file.path(if (basename(getwd()) == "notebooks") ".." else ".", ...)) {
  # Appendix figures (FigureS*, TableS*) go to their own folder.
  dir <- if (grepl("^(Figure|Table)S", stem)) "appendix-figures" else "figures"
  out <- \(ext) here(dir, paste0(stem, ".", ext))
  ggsave(out("png"), plot, width = w, height = h, dpi = 300, device = ragg::agg_png, bg = "white")
  ggsave(out("pdf"), plot, width = w, height = h, device = cairo_pdf, bg = "white")
  ggsave(out("svg"), plot, width = w, height = h, device = svglite::svglite, bg = "white")
  ggsave(out("tiff"), plot, width = w, height = h, dpi = 600, device = ragg::agg_tiff,
         compression = "lzw", bg = "white")
  invisible(stem)
}
