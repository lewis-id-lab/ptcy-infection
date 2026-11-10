# Remove three duplicate database entries (DECISIONS.md, 2026-11-10; checklist
# A7). Each is a second entry of a publication already in the database under
# another study identifier (same DOI):
#   51  = duplicate of 50  (Barkhordar 2022, 10.3389/fimmu.2022.921293)
#   123 = duplicate of 122 (Dybko 2023, 10.3390/ijms24065764)
#   290 = duplicate of 187 (Jo 2024, 10.1111/bjh.19372)
# Rows are dropped from every data file keyed by study_id; nothing else in
# those files is changed. The PRISMA flow follows the precedent of the Wu 2025
# duplicate (appendix S12): the entries move from "included" to full-text
# exclusions as duplicate publications.
# Run once from project root: source("scripts/remove-duplicate-entries.R")

library(dplyr)
library(readr)
library(stringr)

drop_ids <- c("51", "123", "290")

# Read and write everything as text so untouched rows stay byte-identical
read_chr <- function(f) {
  read_csv(f, col_types = cols(.default = col_character()), na = character(), progress = FALSE)
}

files <- c(
  "data/studies.csv", "data/arms.csv", "data/outcomes.csv", "data/rob.csv",
  "data/Table_S4a_study_characteristics.csv", "data/Table_S4b_arm_characteristics.csv",
  "data/extraction_audit_flags.csv", "data/models/data_c1_rrm.csv",
  "data/analytic/C1_aGVHD_grade_II_IV.csv", "data/analytic/C1_aGVHD_grade_III_IV.csv",
  "data/analytic/C1_CMV_any_reactivation.csv", "data/analytic/C1_NRM_NRM_overall.csv",
  "data/analytic/C1_overall_mortality_OS_event.csv"
)

removed <- vapply(files, \(f) {
  d <- read_chr(f)
  keep <- !d$study_id %in% drop_ids
  write_csv(d[keep, ], f, na = "")
  sum(!keep)
}, integer(1))
print(removed)

# Cross-references to the removed identifiers in the overlap field
fix_overlap <- function(f) {
  d <- read_chr(f)
  if (!"overlap_with_study_ids" %in% names(d)) return(invisible())
  d <- d |>
    mutate(overlap_with_study_ids = case_when(
      study_id == "49" & overlap_with_study_ids == "50;51" ~ "50",
      study_id == "122" & overlap_with_study_ids == "123,124" ~ "124",
      study_id == "124" & overlap_with_study_ids == "122,123" ~ "122",
      .default = overlap_with_study_ids
    ))
  write_csv(d, f, na = "")
}
fix_overlap("data/studies.csv")
fix_overlap("data/Table_S4a_study_characteristics.csv")

# PRISMA flow: 3 fewer included studies, 3 more duplicate publications excluded
flow <- read_chr("data/prisma_flow.csv")
set_n <- function(d, key, from, to) {
  i <- which(d$data == key)
  stopifnot(length(i) == 1, d$n[i] == from)
  d$n[i] <- to
  d
}
flow <- flow |>
  set_n("new_studies", "250", "247") |>
  set_n("total_studies", "250", "247") |>
  set_n("total_studies_ma", "105", "104")
i <- which(flow$data == "dbr_excluded")
stopifnot(str_detect(flow$n[i], "Duplicate publication, 14;"))
flow$n[i] <- str_replace(flow$n[i], "Duplicate publication, 14;", "Duplicate publication, 17;")
write_csv(flow, "data/prisma_flow.csv", na = "")

# Appendix S4 reference list
s4 <- readLines("appendix-s4-references.md")
is_dup <- str_detect(s4, str_c("^\\|\\s*(", str_c(drop_ids, collapse = "|"), ")\\s*\\|"))
stopifnot(sum(is_dup) == 3)
writeLines(s4[!is_dup], "appendix-s4-references.md")
