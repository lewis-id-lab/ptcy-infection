# Adjudication of 15 conflicting duplicate extraction groups (2026-10-02),
# verified against source PDFs in PTCY_files/. Decisions:
#
# Completeness-only groups (same values, one row more complete):
#   keep the more complete row: studies 134 (arm 153), 45 (arms 46/47),
#   379 (arm 416), 407 (arm 450)
# PDF-adjudicated groups:
#   136 Fox 2024: Table 2 HC grade >=2 = 22/82 (26.8%) and 13/89 (14.6%) ->
#     keep 3686/3687; drop 1070/1071 (BK-subset denominators, 18 [36%], 5 [9.1%])
#   297 Noviello 2023: HHV-6 reactivation 130/208 (CI 57%) keep 2132;
#     52/208 is clinically relevant HHV-6 infection (CI 24%) -> relabel 2134 subtype
#   327 Saade 2022: 41/409 BKHC (abstract) -> keep 2345; drop 3775
#   346 Carreira 2023: Table 2 grade2-4 = 77+60 = 137, grade3-4 = 60 ->
#     keep 2546 (grade 2-4) and 2547 (relabel subtype HC grade 3-4);
#     drop 3788/3789
#   366 Steiner 2024: "cystitis 29% vs 16% at day 100" (percentages only) ->
#     keep 3799 (12/74) / 3800 (21/73) as percentage_derived_count; drop 2685/2686
#   426 Garcia-Cadenas 2021: "viral HC 27.5% vs 7.8%" -> 11/40, 6/77 ->
#     keep 3201/3202 as percentage_derived_count; drop 3858/3859
#   433 Lazana 2026: "3 of 63 (4.7%) study group" -> keep 3285; drop 3866 (denom 33 wrong)
#
# Run from project root: source("scripts/adjudicate-conflicts.R")

library(tidyverse)

out <- read_csv("data/outcomes.csv", show_col_types = FALSE,
                col_types = cols(.default = col_character()))
n0 <- nrow(out)

drop_ids <- c(
  # completeness-only: drop the less complete row of each pair
  out |>
    filter(study_id %in% c("134", "45", "379", "407"),
           outcome_subtype %in% c("BK_hemorrhagic_cystitis", "any_reactivation")) |>
    group_by(study_id, arm_id, outcome_category, outcome_subtype, timepoint) |>
    filter(n() > 1) |>
    mutate(.comp = rowSums(!is.na(pick(everything())) & pick(everything()) != "NR")) |>
    arrange(.comp, .by_group = TRUE) |>
    slice_head(n = 1) |>
    ungroup() |> pull(outcome_id),
  # PDF-adjudicated drops
  c("1070", "1071",   # 136: subset-denominator BK cystitis rows
    "3775",           # 327: NR duplicate
    "3788", "3789",   # 346: NR duplicates
    "2685", "2686",   # 366: NR duplicates
    "3858", "3859",   # 426: NR duplicates
    "3866")           # 433: wrong denominator
)

out <- out |>
  filter(!outcome_id %in% drop_ids) |>
  mutate(
    # 297: row 2134 is a different outcome (clinically relevant infection)
    outcome_subtype = if_else(outcome_id == "2134",
                              "clinically_relevant_HHV6_infection", outcome_subtype),
    # 346: row 2547 is the grade 3-4 variant
    outcome_subtype = if_else(outcome_id == "2547",
                              "hemorrhagic_cystitis_grade_3_4", outcome_subtype),
    # 366/426: counts derived from reported percentages
    input_class = if_else(outcome_id %in% c("3799", "3800", "3201", "3202"),
                          "percentage_derived_count", input_class),
    data_quality_flag = if_else(outcome_id %in% c("3799", "3800", "3201", "3202"),
                                "derived", data_quality_flag),
    extraction_notes = case_when(
      outcome_id == "2134" ~ paste0(coalesce(extraction_notes, ""),
        " [Adjudicated 2026-10-02 vs PDF: distinct outcome from HHV6 reactivation (130/208); this row is clinically relevant HHV-6 infection, 52/208, CI 24% at D+100.]"),
      outcome_id == "2546" ~ paste0(coalesce(extraction_notes, ""),
        " [Adjudicated 2026-10-02 vs PDF Table 2: 137 = grade 2 (77) + grade 3-4 (60) of 228 total HC; count is 'ever' not D+100; D+100 reported as CIF 11.1%.]"),
      outcome_id == "2547" ~ paste0(coalesce(extraction_notes, ""),
        " [Adjudicated 2026-10-02 vs PDF Table 2: grade 3-4 HC = 60/960 ever; D+100 CIF 4.9%.]"),
      outcome_id %in% c("3799", "3800") ~ paste0(coalesce(extraction_notes, ""),
        " [Adjudicated 2026-10-02 vs PDF: paper reports percentages only ('29% vs 16% at day 100'); counts derived, treat as percentage_derived_count.]"),
      outcome_id %in% c("3201", "3202") ~ paste0(coalesce(extraction_notes, ""),
        " [Adjudicated 2026-10-02 vs PDF: paper reports '27.5% vs 7.8%' viral HC; counts derived (11/40, 6/77; 17 total matches paper's 17 patients, 14.5%).]"),
      TRUE ~ extraction_notes)
  )

stopifnot(nrow(out) == n0 - length(drop_ids))
write_csv(out, "data/outcomes.csv")
message("Dropped ", length(drop_ids), " rows; n = ", nrow(out))

# Post-check: no key-duplicates with conflicting event counts remain
out |>
  count(study_id, arm_id, outcome_category, outcome_subtype, timepoint) |>
  filter(n > 1)