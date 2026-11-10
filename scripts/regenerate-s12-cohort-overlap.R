# Rebuild appendix figure S12 (cohort overlap map): publications per cohort for
# cohorts with more than one included publication, from data/studies.csv and
# data/cohorts.csv. The original generator was not kept, so the layout is
# matched by eye to the committed figure (8 x 7 in; log x axis; bars labelled
# with their counts).
# Writes figures/FigureS12_cohort_overlap_map.{png,pdf,svg}. Set `s12_out_dir`
# before sourcing to write somewhere else (for a preview).
# Run from project root: source("scripts/regenerate-s12-cohort-overlap.R")

library(dplyr)
library(readr)
library(ggplot2)

studies <- read_csv("data/studies.csv", show_col_types = FALSE)
cohorts <- read_csv("data/cohorts.csv", show_col_types = FALSE)

overlap <- studies |>
  count(cohort_id, name = "publications") |>
  filter(publications >= 2) |>
  left_join(mutate(cohorts, cohort_id = as.character(cohort_id)) |> select(cohort_id, cohort_label),
            by = "cohort_id") |>
  # largest cohort at the top; ties in reverse alphabetical order from the top
  arrange(publications, tolower(cohort_label)) |>
  mutate(cohort_label = factor(cohort_label, levels = cohort_label))
stopifnot(!anyNA(overlap$cohort_label))

x_breaks <- sort(unique(c(2, 3, 5, 10, 20, max(overlap$publications))))

fig_s12 <- ggplot(overlap, aes(x = publications, y = cohort_label)) +
  geom_col(fill = "#2B5C8A", width = 0.9) +
  geom_text(aes(label = publications), hjust = -0.5, size = 3, colour = "#2D2D2D") +
  scale_x_log10(breaks = x_breaks, limits = c(1, max(overlap$publications) * 1.3), expand = c(0, 0)) +
  labs(
    title = "Cohort overlap map",
    subtitle = sprintf("Publications per registry cohort (n = %d multi-publication cohorts)", nrow(overlap)),
    x = "Number of publications (log scale)", y = NULL
  ) +
  theme_minimal(base_size = 11, base_family = "Helvetica") +
  theme(
    plot.title = element_text(face = "bold", colour = "#1A2A3A", size = 14),
    plot.subtitle = element_text(colour = "#6B7D8D", size = 10),
    axis.text = element_text(colour = "#2D2D2D", size = 9.5),
    axis.title.x = element_text(colour = "#1A2A3A", size = 11),
    axis.line = element_line(colour = "#1A2A3A", linewidth = 0.4),
    axis.ticks.x = element_line(colour = "#1A2A3A", linewidth = 0.4),
    panel.grid.major.y = element_blank(),
    panel.grid.minor = element_blank(),
    panel.grid.major.x = element_line(colour = "#EBEBEB", linewidth = 0.4)
  )

out_dir <- if (exists("s12_out_dir")) s12_out_dir else "figures"
for (dev in c("png", "pdf", "svg")) {
  ggsave(file.path(out_dir, paste0("FigureS12_cohort_overlap_map.", dev)), fig_s12,
         width = 8, height = 7, dpi = 300, bg = "white",
         device = if (dev == "pdf") cairo_pdf else dev)
}
