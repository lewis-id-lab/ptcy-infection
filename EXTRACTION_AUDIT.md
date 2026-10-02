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

## Timepoint & definition-consistency audit (2026-10-02, second checklist)

**1-2. Target timepoints, windows, and actual timepoints per synthesis.**
Target (preferred) timepoints are encoded by `tp_early = 0` in the model
datasets: aGVHD D+100 (fallback D+180); CMV D+100 (fallback D+180, EoF);
BSI D+100 (fallback EoF); cGVHD/NRM/OS/RRM D+365 (fallback D+730, EoF);
BK D+100 (fallback D+180, D+365). Actual timepoints per pooled synthesis are
tabulated in `data/models/timepoint_sensitivity.csv`; heterogeneity is
substantial for CMV (14/22 rows end-of-follow-up), OS (23/34 rows fallback),
and RRM (31/34 fallback).

**3. Restricted-window sensitivity** (`scripts/refit-restricted-windows.R`,
`data/models/timepoint_sensitivity.csv`): refits using target-timepoint rows
only. Shifts of note: c1_bsi (culture-confirmed D+100 subset, k 6->4)
OR 1.42 -> 2.17 [0.88-4.34]; c1_ifi_any (strict EORTC probable/proven,
k 6->4) 0.63 -> 0.44; c1_cgvhd_ms (1-yr only, k 19->10) 0.41 -> 0.33;
c1_cmv (D+100 only, k 22->5) 1.23 -> 1.11; c1_os (1-yr only, k 34->10)
0.78 -> 0.80. c2_os/c3_os cannot be restricted (k = 2 target rows).

**4. Fallback indicator adequacy.** tp_early coefficients
(`data/models/tp_early_coefficients.csv`) are mostly compatible with zero
but very wide (e.g., c1_bsi 0.10 [-2.0-2.2]); the indicator does not
demonstrably absorb time differences for sparse outcomes, so the
restricted-window estimates above are the more credible check.

**5. CMV separation.** Extraction keeps any_reactivation (191 rows),
clinically_significant_csCMV (31), and CMV_end_organ_disease (63) as
distinct subtypes. The pooled C1 CMV synthesis is any_reactivation only;
a csCMV sensitivity exists (k = 8, OR 0.94 [0.49-1.71] vs 1.20
any-reactivation; `data/models/cmv_definitions.csv`). Caveat: some pooled
"any_reactivation" rows use csCMV-like definitions (e.g., study 166
"requiring preemptive therapy", thresholds 500-1000 copies/mL), and CMV
end-organ disease has no pooled analysis (too sparse).

**6. BK separation.** Only BK-associated haemorrhagic cystitis was ever
extracted (149 rows); no viruria or viraemia subtypes exist in the
database, so no mixing is possible at the synthesis level. This is a
coverage limitation to state in the manuscript.

**7. BSI/IFI definition consistency.** BSI pooled rows: 4/6 culture-confirmed
first-episode definitions; studies 216 and 432 have vague definitions
("no specific definition", "bacterial infection AE not specifically BSI") —
both fall outside the D+100 target window, so the restricted c1_bsi
estimate (2.17) is also the definition-comparable one. IFI pooled rows:
study 167 includes 'possible' IFD and study 399 is fungal-attributed
mortality, not IFI incidence; the restricted c1_ifi estimate (0.44)
excludes both.

**8. Censoring/competing-risk handling** is recorded per row
(`competing_risks_handled`, `ci_method`): GVHD/NRM/RRM predominantly
Gray CIF or crude cause-of-death proportions; OS predominantly KM.
A residual set of pooled arms whose counts derived from censored
estimators was PDF-verified (41 arms, 13 studies): 31 confirmed derived
(events nulled; 14 Table 2 models refit) and 10 corrected to
observed_count (studies 2, 122, 144, 299*, 397, 399). *299: conflicting
verdicts; kept as derived (conservative). Resulting Table 2 changes:
c1_os m1 OR 0.776 -> 0.729 [0.581-0.890] (k 33->29);
c2_os m1 0.887 -> 0.751 [0.426-1.28] (k 7->6);
c3_os m1 0.92 -> 1.05 [0.487-1.879] (k 6->5);
c3_agvhd m1 0.44 -> 0.31 [0.064-1.46] (k 7->5);
c1_cmv m1 1.23 -> 1.20 [0.869-1.65] (k 22->21);
c1_nrm, c2_agvhd, c3_cgvhd, c3_nrm, c1_cgvhd_ms: <=0.03 OR shift.
All refits 0 divergences, Rhat 1.00
(`data/models/refit_2026-10-02_censored_pool.csv`).

**BSI primary analysis change (2026-10-02).** The restricted-window,
culture-confirmed D+100 subset (k = 4, studies 6/9/88/166) was promoted to
the primary c1_bsi analysis (`scripts/promote-restricted-bsi.R`): OR 2.17
[0.86-4.39], tau 0.43, PI [0.35-9.99] replaces the full-window k = 6 estimate
(1.42 [0.58-2.99]) in Table2_setB.csv; the full-window estimate remains in
timepoint_sensitivity.csv. Main-text, GRADE, concordance, absolute-effects,
and outcome-flow mentions updated; Figure 4 BSI panel now shows the 4-study
subset. Stale by design (flagged, not updated): the RoBMA model-averaged BSI
row (appendix S10, still k = 6) and CMV/OS text numbers affected by the
censored-pool refits (c1_os 0.776 -> 0.729; c1_cmv 1.23 -> 1.20) outside the
BSI sentences. Appendix also gained a "BK virus outcome scope" subsection
stating the BK outcome is haemorrhagic cystitis only (no viruria/viraemia),
and the Figure 4 BK panel was retitled accordingly.

**Text/table synchronisation (2026-10-02).** index.qmd text and the static
Table 2 were synchronised to the post-adjudication estimates: c1_os 0.73
[0.58-0.89] (k = 29), c2_os 0.75 [0.43-1.28] (k = 6), c1_cmv 1.20
[0.87-1.65] (k = 21), c1_nrm 0.84 [0.48-1.28] (k = 11); derived quantities
recomputed (OS -68 deaths/1000 at 35% baseline; CMV +46 reactivations/1000
at 48%; indirect C1:C2 CMV ratio 1.41 [0.76-2.54] from the refit
posteriors). The appendix RoBMA table dropped the BSI row (primary analysis
now k = 4; publication-bias model-averaging not interpretable) with an
explanatory note, including the caveat that the remaining RoBMA fits predate
the censored-pool exclusions. Note: appendix GRADE/absolute-effects tables
for OS, NRM, RRM, aGVHD, CMV, and cGVHD still carry pre-adjudication point
estimates where those changed by <= 0.03 (c1_rrm, c2_agvhd) or moderately
(c1_os 0.78->0.73; c1_nrm 0.81->0.84; c3_* ); a full appendix table refresh
was completed 2026-10-02: the GRADE table was refreshed to post-adjudication
estimates (k, OR, τ updated for 12 rows; the aGVHD C1 publication-bias cell
now cites RoBMA rather than the pre-adjudication Egger/trim-and-fill), and
the absolute-effects table was recomputed from the current pooled ORs and
comparator-arm baseline risks (notable shifts: OS C1 −68 [−111 to −26] per
1000; aGVHD C2 baseline 44->40%, −138 [−266 to +38]; CMV C1 +46 [−35 to
+123]). The RoBMA ensemble was refitted on the post-adjudication datasets
for all 17 outcomes with k >= 6 (`scripts/refit-robma-adjudicated.R`,
`_fits_rs/robma_adj/`): qualitative conclusions unchanged — bias evidence
only for C1 OS (BF_bias 18.6 -> 10.4; adjusted OR 0.97 [0.71-1.16]) and C1
aGVHD (10.9; 0.96 [0.57-1.38]); BK effect evidence 12.0 -> 9.5 (adjusted
1.97 [1.00-3.13]); cGVHD mod-sev effect evidence 5.4. The S10 table,
interpretation paragraph, and GRADE publication-bias cells were updated
accordingly. The funnel-plot asymmetry tests were subsequently recomputed on
the post-adjudication datasets (2026-10-02,
`scripts/recompute-pub-bias.R`, `data/models/pub_bias_results.csv`):
OS C1 Egger p = 0.025 (Begg/Peters ns), trim-and-fill 6 imputed, 0.75 ->
0.86 [0.70-1.07]; aGVHD unchanged pattern (Egger 0.023, Begg 0.018, tf
0.61 -> 0.83); no other outcome asymmetric. The S10 paragraph was updated,
closing the last pre-adjudication analysis.

## Reporting-emphasis audit (2026-10-02, third checklist)

Executed via `scripts/refit-reporting-suite.R` on the post-adjudication
datasets; outputs in data/models/{rct_only_results,comparator_backbone,
donor_confounding,hr_sensitivity_os,hr_same_subset}.csv.

1. **HR prominence + same-subset comparison.** OS HR pooling rerun (C1 HR
   0.88 [0.66-1.14], k = 14; C2 0.60 [0.27-1.10], k = 4). New analysis:
   count-based M1 restricted to the same HR-reporting studies — C1 OR 0.75
   [0.57-0.93] (k = 13), so the HR attenuation persists on the same subset
   and is attributable to adjustment/estimand, not subset composition.
   A sentence reporting the HR analysis was added to the main-text
   discussion.
2. **RCT vs observational separation.** Material finding: after removal of
   CIF-derived counts, trial-only analyses are no longer estimable for any
   C1 outcome (trials report KM/CIF almost exclusively; at most 2 trials
   per outcome retain observed counts). Earlier trial-only estimates
   (e.g., OS 0.79 [0.59-1.08], k = 7) were built partly on pseudo-counts
   and are superseded. Observational-only estimates now reported instead
   (OS 0.79 [0.63-0.96], k = 26; aGVHD 0.60, k = 27; cGVHD 0.48, k = 14;
   NRM 0.91, k = 10; CMV 1.01, k = 7), with explicit statement that trial
   evidence with observed counts cannot carry the conclusions. Appendix
   RCT section rewritten accordingly.
3. **Comparator backbone + formal interaction.** Subgroups refit; new
   backbone x PTCy interaction models show differences are NOT resolved
   (OS: CNI+MMF vs MTX ratio 1.82 [0.76-4.53]; MTX+MMF vs MTX 1.46
   [0.87-2.54]; aGVHD 1.08/1.58; CMV 0.77/0.70). The appendix text claiming
   benefit "concentrated" against CNI+MTX and "absent" against CNI+MMF was
   rewritten to state that one interval excluding 1 while another does not
   is not evidence of a differential effect.
4. **Donor-type covariates.** Refitted (k values now match Table 2).
   Verified: 95% arm-level availability, zero exclusions in pooled sets,
   missing values never zero-filled (complete-case). Documented in the
   appendix paragraph.
5. **Baseline confounders.** Availability table added to the appendix:
   donor 95%, conditioning 89%, graft source 85%, steroid 76%, disease
   risk 59%, CMV serostatus 47%, D+/R- 31%, era 100%; conditioning, graft
   source and disease risk are not adjusted for (residual-confounding
   limitation now stated).
6. **Steroid M2** already framed exploratory (post-hoc amendment) with the
   87% GVHD-derived-proxy caveat documented; no change needed.
7. **Subgroup-inference language** fixed per item 3; the CMV C1-vs-C2
   indirect-comparison text was already properly hedged ("does not
   resolve").

## Letermovir/CMV-prophylaxis audit (2026-10-02, fourth checklist)

Executed via `scripts/refit-cmv-letermovir-adj.R` and the adjudicated
sensitivity-subset refits (data/models/cmv_letermovir.csv,
cmv_sensitivity_subsets_adj.csv).

1. **28/44 reconciliation.** The appendix's "directly reported letermovir
   use for 28 of 44" was wrong: those 28 arms are **confirmed non-use**;
   16 are not reported; zero C1 CMV model arms have recorded use
   (database-wide recorded use, 37 arms, touches no model arm). Appendix
   corrected; missing vs confirmed non-use now distinguished explicitly.
2. **Missing vs confirmed non-use** — stated in the appendix text.
3. **Enrolment dates vs actual exposure.** The enrolment-era proxy model
   was refit on adjudicated data (OR 1.20 [0.86-1.67], k = 21; era
   coefficient -0.79 [-1.74-0.15]); the direct-use meta-regression was
   found unidentifiable (no use variation: all reported arms are non-use,
   13 studies/26 arms) and is now reported descriptively instead.
4. **Publication-year labelling.** The "post-2020" subset is
   publication-year-defined (17 publications; enrolment 2000-2024, mostly
   pre-letermovir-era; 0/34 arms with recorded use). Refit on adjudicated
   data: k = 16, OR 1.43 [0.97-2.06]. Abstract, results, methods, and
   discussion relabelled "studies published from 2020 onward"; the
   abstract's "increased post-2020 after introduction of letermovir"
   attribution removed.
5. **Comparator-class interaction** retained as inconclusive in the main
   interpretation (already present; unchanged).
6. **csCMV framing.** Appendix and main text now treat the csCMV estimate
   (0.94 [0.49-1.71], k = 8) as uncertain — "compatible with anything
   from a halving to a 71% increase" — not as evidence of no increase.
7. **Incidental fixes in the same passages:** the results-paragraph RCT
   sentence was contradictory (superseded trial estimates presented as
   current); replaced with the post-adjudication statement plus
   observational-only numbers. Donor-matched OS number updated
   (0.58 [0.41-0.78], k = 21). Figure S9a regenerated from the refit
   posteriors.

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
