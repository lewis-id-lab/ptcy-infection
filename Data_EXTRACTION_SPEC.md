# EXTRACTION_SPEC — per-paper instructions for the AI extractor

**Schema version:** 1.2 (blocks 1–9) / 1.3 (RRM + BK backfill)
**Provenance note:** the copy of this file used in May 2026 was held in the session's scratch directory and was not archived. This version is reconstructed from the archived schema documents (v1.0–v1.3), the pilot and block summaries, and the workbook codebook. It is intended to be equivalent in content. Where the original wording is uncertain, the rule as applied (verifiable from the extracted data) is given.

Each extractor instance receives this document, one PDF, the current `cohort_overlap_map.json`, and a `study_id`. It returns one JSON object matching `schema/extraction_record.schema.json` and nothing else.

---

## 0. Ground rules

1. Extract only what the paper reports. Do not infer, impute or estimate values except for the single derivation rule in §5.3. If a value is not reported, use `NR`; if it is reported ambiguously, use `UNCL`; if it does not apply, use `NA`.
2. Every categorical field must use a value from `schema/codebook.csv`. Do not invent synonyms (`IFD_mold` is not `IFI_mold`; `any_grade` is not a valid NRM subtype).
3. Copy outcome definitions verbatim into `definition_text`, including the grading or diagnostic system (MAGIC, Mount Sinai, Glucksberg, IBMTR, NIH 2014, Seattle, EORTC/MSG 2008/2020).
4. Record where each outcome value came from (`data_source`: table, figure text, KM/CIF curve, narrative text) and its quality (`data_quality_flag`: direct, derived, estimated_from_figure, back_calculated).
5. Do not change, merge or re-label arms to fit the comparisons. Record the arms as the paper defines them and set eligibility flags; the consolidation step decides what enters each model.
6. Provisional IDs: use the supplied `study_id`; label arms `A1, A2, …`; label new cohorts by `cohort_label` only (global `cohort_id` is assigned at consolidation).

## 1. Eligibility triage (do first; stop if excluded)

Return `{"study_id": N, "excluded": true, "exclusion_reason": "<code>", "paper_label": "<First author Year>", "notes": "..."}` when any applies:

| Code | Criterion |
|---|---|
| `conference_abstract` | 1–2 pages, no Methods/Results sections, meeting supplement |
| `narrative_review` | review, editorial, commentary, letter without original data |
| `systematic_review_not_primary_study` | systematic review or meta-analysis |
| `duplicate` | same paper already in corpus under another filename |
| `protocol_only` | trial protocol without results |
| `non_eligible_population` | paediatric-only, non-malignant indication other than SAA, second transplant only |
| `single_arm_descriptive_excluded` | no PTCy vs non-PTCy (or within-PTCy variant) contrast; single-arm series |
| `pre_PTCy_era` | no PTCy arm at all |
| `full_text_not_obtainable` / `language_not_english` | as stated |
| `mislabeled_file` | PDF content does not match filename; describe the actual paper in `notes` |

Eligible studies: adults (≥18) with haematological malignancy or SAA, first allogeneic HCT, ≥20 patients per arm, at least one PTCy-containing arm and at least one comparator (or within-PTCy variant) arm, outcomes extractable separately by arm, peer-reviewed full text.

## 2. Cohort assignment

1. Search `cohort_overlap_map.json` by registry (CIBMTR, EBMT working party, JSTCT, GETH-TC, DRST …), institution and enrolment years.
2. If the study's patients are, or plausibly overlap with, an existing cohort, reference that `cohort_label` and set `studies.cohort_overlap_status` (`none` / `overlap_subset_of` / `overlap_superset_of` / `partial_overlap`) and `overlap_with_study_ids` if known.
3. Otherwise emit a new cohort: `cohort_label` (snake_case ≤40 chars, e.g. `MDACC_Alousi_PTCy_RIC_PhaseII`), `cohort_description`, `registry_or_source`, enrolment start/end year, `total_unique_patients`.
4. `primary_for_cohort`: `Y` if this is the publication of record for the cohort; `partial` if primary for specific outcomes only (list them, e.g. `IFI`); `N` if superseded. Rule: one publication per cohort per outcome — the most recent/complete with longest follow-up.

## 3. `studies` row

Fields in `schema/fields_studies.csv`. Notes:
- `study_design`: `RCT` / `prospective_cohort` / `retrospective_cohort` / `registry` / `case_control`. Design drives the RoB tool (RCT → `RoB2`, else `ROBINS-I`).
- `era_category` from the enrolment midpoint: `pre_2018` / `post_2018` / `mixed`.
- `region`: `EU` / `NA` / `Asia` / `SA` / `Oceania` / `Africa` / `multinational`.
- `extractor_initials = "AI"`, `extraction_date` = run date, `verifier_initials = "PEND"`, `verification_date = "PEND"`.

## 4. `arms` rows (one per treatment arm; 93 fields in `schema/fields_arms.csv`)

- `arm_role`: `PTCy_arm` or `comparator_arm`. For within-PTCy comparisons (Comparison 3) label the reference regimen (standard-dose PTCy, HLA-identical donor, no added ATG) as `comparator_arm`.
- Comparison eligibility (set `Y`/`N` for each; an arm can be eligible for more than one):
  - **C1** PTCy ± CNI/MMF **vs** CNI + MTX or MMF with **no ATG and no ex-vivo T-cell depletion**.
  - **C2** PTCy-based **vs** ATG-based (any ATG dose, ± CNI/MTX/MMF).
  - **C3** within-PTCy variants: dose (50 mg/kg ×2 vs reduced), schedule, PTCy ± ATG, PTCy ± sirolimus/abatacept, donor-type contrasts where both arms receive PTCy.
- Percentage blocks (disease, donor, graft, conditioning, HLA, CMV serostatus) must each sum to ≤100.
- PTCy detail: `ptcy_dose_mg_kg_per_dose`, `ptcy_n_doses`, `ptcy_days_post_transplant` (e.g. `3,4`), `ptcy_total_dose_mg_kg`, `ptcy_dose_category` (`standard_50x2` / `reduced_25x2` / `reduced_40x2` / `reduced_other` / `single_dose`).
- ATG detail: `atg_agent`, `atg_total_dose_mg_kg`, `atg_dose_category` (`low_le_4.5_rabbit` / `standard_4.5_to_10_rabbit` / `high_gt_10_rabbit_ATLG` / `horse`), `atg_timing`.
- Supportive care: `letermovir_use` (`none` / `select_high_risk` / `all_patients` / `era_proxy_only`), `letermovir_era_proxy`, antifungal agent and mould activity, antibacterial and PJP prophylaxis, CMV monitoring method/frequency/pre-emptive threshold.
- Immunosuppression-exposure covariates: `systemic_steroid_for_gvhd_exposure_pct` (see §5.3), `second_line_gvhd_therapy_exposure_pct`. `steroid_exposure_duration_days_median` is deprecated: always `NR`.

## 5. `outcomes` rows (one per arm × category × subtype × timepoint)

### 5.1 Categories, subtypes and protocol timepoints

| Category | Subtypes (primary in bold) | Primary timepoint | Sensitivity |
|---|---|---|---|
| `BSI` | **`any_pathogen`**, `gram_neg`, `gram_pos`, `MDR_gram_neg`, `Sepsis-3`, `CTCAE_grade_ge_3` | D+30 | D+100 |
| `CMV` | **`any_reactivation`**, `clinically_significant_csCMV`, `CMV_end_organ_disease` | D+100 | D+180 |
| `IFI_mold` | **`EORTC_MSG_proven_probable`**, `EORTC_MSG_proven_only`, `investigator_reported`, `aspergillus_only`, `mucormycosis_only` | D+180 | D+365_1yr |
| `IFI_yeast` | **`EORTC_MSG_proven_probable`**, `EORTC_MSG_proven_only`, `investigator_reported`, `candidemia_only` | D+180 | D+365_1yr |
| `IFI_any` | `EORTC_MSG_proven_probable_combined`, `investigator_reported_any` | D+180 | D+365_1yr |
| `infection_related_mortality` | **`IRM_any_cause_infectious`**, `IRM_bacterial`, `IRM_viral`, `IRM_fungal` | D+365_1yr | D+100 |
| `NRM` | **`NRM_overall`** | D+365_1yr | D+100 |
| `relapse_related_mortality` (v1.3) | **`RRM_any_cause_relapse`** | D+365_1yr | D+730_2yr, end_of_followup |
| `other_infection` | `EBV_reactivation`, `EBV_PTLD`, `HHV6_reactivation`, **`BK_hemorrhagic_cystitis`** (v1.3 target), `adenovirus`, `respiratory_viral_LRTI`, `other` | D+100 | D+180, D+365_1yr |
| `aGVHD` | **`grade_II_IV`**, **`grade_III_IV`** (both flagged primary), `grade_IV_only`, `any_grade` | D+100 | D+180 |
| `cGVHD` | **`moderate_severe_NIH`**, `any_NIH`, `extensive_Seattle`, `limited_Seattle` | D+365_1yr | D+730_2yr |
| `steroid_refractory_aGVHD` | `SR_any` | D+180 | — |
| `steroid_refractory_cGVHD` | `SR_any` | D+365_1yr | — |
| `second_line_GVHD_therapy_use` | **`any_second_line`**, `ruxolitinib`, `ECP`, `MMF_addition`, `belumosudil`, `ibrutinib`, `other` | D+365_1yr | — |
| `overall_mortality` | **`OS_event`** (deaths, not survivors) | D+365_1yr | D+730_2yr, end_of_followup |
| `engraftment_failure` | `primary_graft_failure`, `secondary_graft_failure` | D+30 / D+100 | — |

Timepoint vocabulary: `D+30`, `D+100`, `D+180`, `D+365_1yr`, `D+730_2yr`, `end_of_followup`, `other` (give `timepoint_days_numeric`). Set `is_primary_timepoint` and `is_primary_definition` per this table. Extract every reported timepoint, not only the primary.

### 5.2 Required cells per row

`denominator_n`, `event_count`, `timepoint`, `timepoint_days_numeric`, `competing_risks_handled` (`Y_CIF` / `N_KM_or_crude` / `NR`), `ascertainment_method`, `definition_text`, `data_source`, `data_quality_flag`.

- `event_count` is the number of patients with the event as reported. If the paper gives only a cumulative-incidence percentage, record it in `cumulative_incidence_pct` with `ci_lower_pct`, `ci_upper_pct`, `ci_method`, and set `event_count = NR`. Do **not** multiply a CIF percentage by n to manufacture a count.
- `denominator_n` should equal `arms.n_patients`; if a different denominator is used (matched subset, evaluable patients) record it and explain in `extraction_notes`.
- Hazard ratios: `hr_value`, `hr_ci_lower`, `hr_ci_upper`, `hr_comparator_arm_id`, `hr_adjusted`.
- Rate-only reporting (e.g. BSI episodes per 1,000 patient-days): `incidence_rate_value`, `incidence_rate_unit`, `person_time_total`, `person_time_unit`, with `event_count` as episodes if given.
- `overall_mortality` rows record **deaths** (`event_count = n − survivors` only when both are stated explicitly; otherwise `NR`).

### 5.3 The single permitted derivation

`arms.systemic_steroid_for_gvhd_exposure_pct`:
1. If reported directly (GVHD-treatment or supportive-care table) → record it.
2. Else if aGVHD `grade_II_IV` cumulative incidence at D+100 is reported → set the field to that percentage (1 decimal) and append `systemic_steroid_for_gvhd_exposure_pct back_calculated_from_aGVHD_II_IV` to `arms.extraction_notes`.
3. Else `NR`.

### 5.4 Subgroup outcomes (`outcomes_subgroup`)

Only when the paper itself reports an outcome stratified within an arm by a pre-specified moderator: `donor_type`, `graft_source`, `conditioning_intensity`, `letermovir_era`, `antifungal_class`, `ptcy_dose`, `cmv_serostatus_DR`, `enrollment_era`, `region`, `atg_dose_category`, `agvhd_status`, `cgvhd_status`, `steroid_exposure_status`. Same fields as `outcomes` plus `moderator_variable`, `moderator_value`, `parent_outcome_id` (provisional).

## 6. `rob` row (first reviewer)

- RCT → `RoB2`: d1 randomisation, d2 deviations from intended interventions, d3 missing outcome data, d4 outcome measurement, d5 selective reporting; judgements `low` / `some_concerns` / `high`.
- Otherwise → `ROBINS-I`: d1 confounding, d2 selection, d3 intervention classification, d4 deviations, d5 missing data, d6 outcome measurement, d7 selective reporting; judgements `low` / `moderate` / `serious` / `critical` / `NI`.
- `overall_judgement` and `justification_text` for every domain rated worse than low. `reviewer = "RL"` (first-pass row; verifier and consensus rows are added by humans).

## 7. Output

Return a single JSON object conforming to `schema/extraction_record.schema.json`:

```json
{
  "study_id": 2,
  "excluded": false,
  "cohort": {"cohort_label": "BMT_CTN_1703", "new": false},
  "study": { ...studies fields... },
  "arms": [ {"arm_label_provisional": "A1", ...arms fields...}, ... ],
  "outcomes": [ {"arm_label_provisional": "A1", ...outcomes fields...}, ... ],
  "outcomes_subgroup": [ ... ],
  "rob": { ...rob fields... },
  "extraction_notes": "free text: anomalies, denominators, anything the verifier should look at"
}
```

No prose outside the JSON. If a required value cannot be found, use the missingness code; never omit a required key.

## 8. Targeted backfill variant (schema v1.3, 2026-05-30)

For the RRM + BK pass the extractor received the existing `arm_id`s for the paper and was instructed to emit **only** new `outcomes` rows for `relapse_related_mortality` / `RRM_any_cause_relapse` and `other_infection` / `BK_hemorrhagic_cystitis` attached to those `arm_id`s, with no study, arm, cohort or rob content. A paper reporting neither returns an empty `outcomes` array with a `not_reported` note.
