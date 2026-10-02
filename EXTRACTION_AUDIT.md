# Extraction Audit: Reconstructed-Input Verification

Date: 2026-10-02. Scope: `data/outcomes.csv` (3,883 rows), `data/analytic/C*.csv`, `data/models/data_c*.csv`.
Machine-readable flags: [data/extraction_audit_flags.csv](data/extraction_audit_flags.csv).

## 1. Input classification (per row, outcomes.csv)

| Input class | n rows |
|---|---|
| CIF only (cumulative-incidence estimate) | 1,252 |
| Observed count (n/N reported) | 1,101 |
| Count + CIF (both present) | 634 |
| CIF + HR (censored-data quantities) | 510 |
| Proportion + CIF only | 171 |
| HR only | 96 |
| Percentage only (no count) | 50 |
| Definition only / no numeric data | 65 |
| Incidence rate only | 4 |

`data_quality_flag` already encodes provenance: direct 3,195 / derived 602 /
computed_from_other_fields 34 / back_calculated 27 / estimated_from_figure 25.
`data_source`: table 2,103 / narrative_text 1,339 / figure_text 283 /
figure_KM_curve 115 / computed 37 / other 6. Source table/figure and follow-up
timepoint are recorded per row (`data_source`, `extraction_notes`, `timepoint`).

## 2. Count/proportion/CIF consistency

Of 1,737 rows with usable count + denominator:

- 1,438 counts match the reported raw proportion (or match both).
- 170 counts match the CIF-implied value with no raw proportion reported —
  these are candidates for censored-probability-as-count; most are flagged
  `direct`, meaning the paper reported the percentage itself (count/N),
  but they deserve manual review where the paper labels the % a cumulative incidence.
- 129 match neither (median abs deviation 2.8 pp; mostly rounding, denominator
  drift, or proportions relative to deaths rather than arm N — see §6).

## 3. Hazard ratios converted to arm-specific event counts

**No HR-to-count conversions found.** 96 rows are HR-only (no arm counts); all
are excluded from count-based pooling by construction. HR-derived OS values feed
only the dedicated HR sensitivity analysis (`data/models/hr_sensitivity_os.csv`).

## 4. Censored survival probabilities treated as binomial counts

**Major finding, confined to `data/analytic/`:** 450 analytic rows (886 arms)
contain event counts that do not exist in the extraction database; 100% verify
as `round(CIF/100 × N)`. By outcome: aGVHD II–IV 112, OS 108, aGVHD III–IV 82,
cGVHD mod/sev 65, NRM 60, CMV 15, BSI 5, IFI-mold 2, IRM 1. Example: study 338
BSI D+30 has no event counts in outcomes.csv (CIF 43.2%/13.6% only) but appears
in `C1_BSI_any_pathogen.csv` as 41/95 and 24/177.

Additionally, 12 analytic rows (mostly cGVHD/OS at 1–2 yr) have counts tracking
the CIF even though the crude proportion diverges by >1.5 pp.

**Mitigating finding:** the final model input datasets (`data/models/data_c*.csv`,
472 arms across 17 outcomes) contain **zero** pseudo-counts — every pooled
event count traces to a source-extracted `event_count`. The pseudo-counts sit
in the pre-filter analytic pool only. Recommend documenting that the
extraction→pooling attrition (`outcome_flow.csv`) specifically removed
CIF-only studies, and guarding against accidental re-inclusion.

## 5. BSI numerators: patients vs episodes

Pooled BSI studies (6, 9, 66, 88, 338 in C1 Set B) all use patient-level first
events (e.g., study 9: "Only the first episode of BSI was counted as an event";
study 338: "First bacterial BSI episode"). Episode/rate-based studies (5, 382:
per-1000-patient-day rates; 89: no counts) have `NA` events in the analytic
files and are excluded from pooling. No episode-count numerators leak into
pooled data.

## 6. Relapse-related mortality: deaths attributable to relapse

All 162 RRM rows are subtype `RRM_any_cause_relapse`; definitions consistently
reference cause-of-death classification (death from recurrence/persistence of
disease), not relapse incidence. No conflation detected. Caveat: study 437
(arms 489/490) records `proportion_reported_pct` as the share of **deaths**
(18.2%, 42.9%), not of arm N (2/16 = 12.5%, 3/17 = 17.6%) — counts are correct
but the proportion field mixes denominators. Study 299 RRM is a narrative
count only (no formal CIF).

## 7. Incidental finding: duplicate rows in outcomes.csv

53 exact duplicate outcome rows (50 BK hemorrhagic cystitis, 1 CMV end-organ
disease, 1 CMV any-reactivation, 1 HHV6) — same arm, timepoint, values repeated.
No effect on pooled data if deduplication keys on arm/timepoint, but worth
cleaning.

## Recommended actions

1. ~~Add an `input_class` column to outcomes.csv~~ **Done** (2026-10-02,
   `scripts/add-input-class-and-clean-analytic.R`): observed_count 1,438 /
   cumulative_incidence_only 1,854 / percentage_derived_count 238 /
   kaplan_meier_derived 95 / kaplan_meier_derived_count 20 / hr_only 85 /
   percentage_only 50 / cumulative_incidence_derived_count 17 /
   other_reconstruction 27 / incidence_rate_only 4 / no_numeric_data 55.
2. Document in the appendix that CIF-only studies were excluded from binomial
   pooling (the mechanism behind the pseudo-counts found in `data/analytic/`).
3. ~~Regenerate `data/analytic/` with NA events where the source reports only
   CIF~~ **Done** (2026-10-02, same script): 444 ptcy + 442 comp pseudo-counts
   nulled across 27 files; post-check confirms zero remaining. Three files
   lacking arm-id columns were skipped (C2_IFI_mold, C3_BSI, C3_IFI_mold) —
   none feed pooled models.
4. ~~Fix study 437 proportion fields~~ **Done** (2026-10-02,
   `scripts/fix-437-dedupe-review170.R`): outcome 3873 changed 18.2% -> 12.5%
   (2/16) and 3876 changed 42.9% -> 17.6% (3/17), with provenance notes;
   input_class set to observed_count.
5. ~~Remove the duplicate outcomes.csv rows~~ **Done, with a refinement**
   (2026-10-02, same script): the 53 key-duplicates split into 38 groups of
   genuine re-extraction duplicates (39 rows removed, keeping the most complete
   row) and 15 groups of *conflicting* duplicates with different values. Of the
   15, eight differ only in completeness; seven have genuinely conflicting event
   counts (studies 136, 297, 327, 346, 366, 426, 433 — all BK cystitis/HHV6).
   None of the seven feed any pooled model dataset (verified against
   data/models/data_c*.csv). All conflicting rows are flagged in
   extraction_notes and need source-PDF adjudication.
6. ~~Manually review the 170 CIF-consistent counts~~ **Done, now fully
   adjudicated against source PDFs** (2026-10-02). First pass (internal
   review): 33 rows reclassified as derived, 36 confirmed observed, 99 marked
   `uncertain_count_provenance`. Second pass (PDF verification of all 99
   uncertain rows plus the 15 conflicting duplicate groups, using
   `PTCY_files/` PDFs and `scripts/adjudicate-conflicts.R`):
   - Conflicting duplicates: all 15 groups resolved (see flags CSV);
     15 rows dropped; Noviello 2134 relabelled clinically_relevant_HHV6;
     Carreira 2547 relabelled grade 3-4 HC.
   - Uncertain rows: 66 verified as explicitly reported counts
     (-> observed_count); 31 confirmed CIF/percentage-derived
     (-> cumulative_incidence_derived_count / kaplan_meier_derived_count);
     2 remain unclear (study 208 NRM).
   - **Material consequence:** 8 of the confirmed CIF-derived arms feed 5
     rows in the pooled model datasets (study 20 cGVHD; studies 198, 66, 299
     OS; study 397 NRM). Their events have been set to NA in
     data/models/data_c1_cgvhd_ms.csv, data_c1_os.csv, data_c2_os.csv,
     data_c3_nrm.csv (and the corresponding analytic files), so any refit
     will exclude them. **Refit completed** (2026-10-02,
     `scripts/refit-after-pdf-adjudication.R`, cmdstanr backend after an
     rstan/TBB toolchain failure): Table2_setB.csv updated —
     c1_cgvhd_ms m1 k 19->18, OR 0.396->0.412 [0.233-0.716];
     c1_os m1 k 34->33, OR 0.760->0.776 [0.628-0.948];
     c1_os m2 k 27->26, OR 0.953->0.979 [0.721-1.31];
     c2_os m1 k 9->7, OR 0.750->0.887 [0.481-1.66];
     c2_os m2 k 8->6, OR 0.895->0.967 [0.451-2.24];
     c3_nrm m1 k 5->4, OR 0.510->0.480 [0.138-1.62].
     No conclusion changes direction or significance. c3_nrm was
     subsequently refit at adapt_delta 0.999 (`scripts/refit-c3nrm-0999.R`):
     0 divergences, OR 0.481 [0.139-1.71].
   - **Fit reconstruction (2026-10-02):** the original _fits_rs/*.rds files
     (2026-09-30) were not present on this machine; all 29 random-slope fits
     were reconstructed with the cmdstanr backend from the same data and
     specification (`scripts/refit-random-slope.R`). The rebuilt Table 2
     matches the previous values to within MCMC noise (max |delta OR| =
     0.011 across unaffected outcomes). Table2_setB.csv was then rebuilt from
     the complete fit set with prediction intervals recomputed
     (`scripts/export-prediction-intervals.R`); provenance stamps updated.
   - **Figures/tables regenerated (2026-10-02):** Figure 2 (OS), 3a/3b
     (CMV), 4 (BSI/IFI/BK), S7b/c/d, S9a via
     `scripts/regenerate-figures-rs.R`; notebooks
     `pooled-estimates.qmd` (Table 2) and `forest-plots.qmd` re-rendered.
