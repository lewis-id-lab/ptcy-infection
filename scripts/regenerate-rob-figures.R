# Regenerate the ROBINS-I appendix figures on the settled 211-study denominator.
#
# The vendored figures came from the analysis-repo draft, which plotted all
# 227 ROBINS-I rows (including the 16 single-arm descriptive studies), while
# the S5 table and the revised text use the 211 comparative observational
# studies. This script rebuilds FigureS5a (traffic light) and FigureS5b
# (domain summary) from data/rob.csv on the 211-study denominator, with the
# same styling as the originals. Studies without a recorded domain judgement
# (the same 7 studies missing D6/D7) are shown as "No information" cells, so
# the 204-row completeness gap is visible rather than hidden.
#
# Overwrites figures/FigureS5a_ROBINS_traffic_light.{png,pdf,svg} and
# figures/FigureS5b_ROBINS_domain_summary.{png,pdf,svg}.

suppressPackageStartupMessages({
  library(tidyverse)
})

rob <- read_csv("data/rob.csv", show_col_types = FALSE)
studies <- read_csv("data/studies.csv", show_col_types = FALSE)

robins <- rob |>
  filter(rob_tool == "ROBINS-I") |>
  left_join(studies |> select(study_id, first_author, pub_year, study_design),
            by = "study_id") |>
  filter(study_design != "single_arm_descriptive_excluded")
stopifnot(n_distinct(robins$study_id) == 210)

domain_cols <- c("d1", "d2", "d3", "d4", "d5", "d6", "d7")
judgement_colours <- c("low" = "#4CAF50", "moderate" = "#FFB74D",
                       "serious" = "#EF5350", "critical" = "#B71C1C",
                       "NI" = "#BDBDBD")
judgement_symbols <- c("low" = "+", "moderate" = "−", "serious" = "!",
                       "critical" = "×", "NI" = "?")

theme_jama <- function(base_size = 11) {
  theme_minimal(base_size = base_size) %+replace%
    theme(
      text = element_text(family = "sans", colour = "#2d2d2d"),
      plot.title = element_text(size = rel(1.15), face = "bold",
                                colour = "#1a2a3a", hjust = 0,
                                margin = margin(b = 8)),
      plot.subtitle = element_text(size = rel(0.9), colour = "#6b7d8d",
                                   hjust = 0, margin = margin(b = 10))
    )
}

save_fig <- function(plot, name, width, height, dpi = 300) {
  ggsave(file.path("figures", paste0(name, ".png")), plot,
         width = width, height = height, dpi = dpi, bg = "white")
  ggsave(file.path("figures", paste0(name, ".pdf")), plot,
         width = width, height = height)
  ggsave(file.path("figures", paste0(name, ".svg")), plot,
         width = width, height = height)
}

# ── Figure S5a: traffic light (one row per study) ─────────────────────────
traffic_long <- robins |>
  select(rob_id, study_id, all_of(domain_cols), overall_judgement,
         first_author, pub_year) |>
  rename(Overall = overall_judgement) |>
  mutate(slab = paste0(first_author, " (", pub_year, ")"),
         slab = make.unique(slab, sep = " – ")) |>
  select(rob_id, slab, all_of(domain_cols), Overall) |>
  pivot_longer(cols = c(all_of(domain_cols), "Overall"),
               names_to = "domain", values_to = "judgement") |>
  mutate(
    domain = factor(domain, levels = c(domain_cols, "Overall"),
                    labels = c("D1", "D2", "D3", "D4", "D5", "D6", "D7",
                               "Overall")),
    judgement = ifelse(is.na(judgement) | judgement == "", "NI", judgement),
    judgement = factor(judgement,
                       levels = c("low", "moderate", "serious", "critical",
                                  "NI")),
    symbol = judgement_symbols[as.character(judgement)]
  )

# Order rows by overall-judgement severity, "No information" just behind
# critical, alphabetical within each group (matches the original).
severity_rank <- c("critical" = 1, "serious" = 2, "NI" = 3, "moderate" = 4,
                   "low" = 5)
study_order <- traffic_long |>
  filter(domain == "Overall") |>
  distinct(slab, judgement) |>
  mutate(rank = severity_rank[as.character(judgement)]) |>
  arrange(rank, slab)
traffic_long$slab <- factor(traffic_long$slab,
                            levels = rev(study_order$slab))

fig_s5a <- ggplot(traffic_long, aes(x = domain, y = slab, fill = judgement)) +
  geom_tile(colour = "white", linewidth = 0.3) +
  geom_text(aes(label = symbol), size = 2.2, colour = "white",
            fontface = "bold") +
  scale_fill_manual(values = judgement_colours, name = "Judgement",
                    drop = FALSE,
                    labels = c("Low", "Moderate", "Serious", "Critical",
                               "No information")) +
  scale_x_discrete(position = "top") +
  labs(x = NULL, y = NULL) +
  theme_jama(base_size = 8) +
  theme(
    axis.text.y = element_text(size = rel(0.55)),
    axis.text.x = element_text(size = rel(0.9), face = "bold"),
    panel.grid = element_blank(),
    legend.position = "bottom"
  )
save_fig(fig_s5a, "FigureS5a_ROBINS_traffic_light", width = 8, height = 30)

# ── Figure S5b: domain-level summary ──────────────────────────────────────
summary_long <- robins |>
  select(rob_id, all_of(domain_cols)) |>
  pivot_longer(all_of(domain_cols), names_to = "domain",
               values_to = "judgement") |>
  mutate(judgement = ifelse(is.na(judgement) | judgement == "", "NI",
                            judgement)) |>
  count(domain, judgement) |>
  mutate(
    domain = factor(domain, levels = domain_cols,
                    labels = c("D1 Confounding", "D2 Selection",
                               "D3 Classification", "D4 Deviations",
                               "D5 Missing data", "D6 Measurement",
                               "D7 Reporting")),
    judgement = factor(judgement,
                       levels = c("low", "moderate", "serious", "critical",
                                  "NI"))
  )

fig_s5b <- ggplot(summary_long, aes(x = n, y = fct_rev(domain),
                                    fill = judgement)) +
  geom_col(position = "fill", width = 0.7) +
  scale_fill_manual(values = judgement_colours, name = "Judgement",
                    drop = FALSE,
                    labels = c("Low", "Moderate", "Serious", "Critical",
                               "No information")) +
  scale_x_continuous(labels = scales::percent) +
  labs(x = NULL, y = NULL,
       title = "ROBINS-I domain-level summary (n = 211)") +
  theme_jama(base_size = 10)
save_fig(fig_s5b, "FigureS5b_ROBINS_domain_summary", width = 8, height = 4)

cat("regenerated FigureS5a/S5b on n =", n_distinct(robins$study_id),
    "studies; NI cells:", sum(traffic_long$judgement == "NI"), "\n")
