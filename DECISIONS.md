# Decision record

Dated record of decisions that change the analysis, the data, or the
repository history. Entries are not rewritten; a later entry that supersedes
an earlier one points back to it. Each entry says what had been seen when the
decision was made, and whether a statement is a human check or an assistant
inference.

## 2026-11-10 — Merge of origin/main into the local revision

- **Decision (RL):** commit the merge "as it stands".
- **What was done:** local `main` (two "revision" commits) had diverged from
  `origin/main` (three commits: word-count trims, Research in context
  changes, S4 build fix). Nine conflicts in `index.qmd` were resolved hunk by
  hunk, keeping non-overlapping additions from both sides. Merge commit
  `fd512ca`.
- **Status of the resolutions:** proposed by the assistant, accepted without
  a line-by-line human check. Three were flagged for review and are still
  open: (1) the clause "was not attributable to letermovir" was deleted in the
  local revision and came back through the remote text; (2) the conclusion
  still says "BK virus reactivation" although the outcome is BK
  virus–associated haemorrhagic cystitis; (3) the merged text keeps both
  sides' additions, so it is longer than either.
- **What had been seen:** the pre-submission review of 27 Oct 2026. The
  revision checklist of 10 Nov 2026 had not yet been read when the
  resolutions were proposed; several resolutions keep wording that the
  checklist asks to be rewritten (survival benefit, depletion-depth gradient,
  "extend across donor types").

## 2026-11-10 — Word files removed from unpushed history

- **Decision (RL):** leave three Word files out of the push to the public
  repository: `PTCy Pre-submission Review.docx`,
  `PTCy_infection_22.10.2026-final.docx` (contains tracked changes and a
  comment), `appendix_final.docx`.
- **What was done:** the two unpushed local commits were rewritten to drop the
  files (`f6e3b45` → `37253a5`, `9492b95` → `57406bc`); nothing already on
  GitHub was rewritten. The files remain on disk, untracked. The original
  commits are kept on the local branch `backup/pre-docx-removal-2026-11-10`,
  which must not be pushed.
- **Check:** pattern scan and opening lines only (assistant, not a full
  read): no patient-level data or identifier-like text found in the three
  files.

## 2026-11-10 — Revision checklist received; audit and feasibility counts run

- **Input:** `PTCy_revision_checklist.md` (review of the 6 Nov Word files,
  dated 10 Nov 2026). No analysis decision has been taken on it yet.
- **Nothing in the models, data or manuscript numbers was changed.** Two
  read-only scripts were added and run:
  - `scripts/audit-pooled-studies.R` →
    `audit/pooled_studies_audit_2026-11-10.csv` (checklist A6/A7): the 105
    pooled studies (112 study × comparison rows, defined by the meta-analysis
    column of appendix S4), with stored regimen, ATG, donor, disease and
    duplicate fields and automatic flags. The flags are assistant inferences
    from stored extraction fields; no source paper was checked. The
    adjudication columns are empty and are for a human to complete.
  - `scripts/a1-feasibility.R` → `audit/a1_feasibility_2026-11-10.csv`
    (checklist A1): counts of studies with hazard ratios or
    cumulative-incidence estimates per outcome and comparison. Counts only;
    no model was fitted and no pooled estimate under any alternative
    construction has been seen.
- **Seen at this point (relevant to any later change of primary analysis):**
  the current observed-count results in the manuscript; the existing
  hazard-ratio sensitivity analysis for overall survival (C1 k = 14, HR 0·88,
  0·66–1·14); the checklist's critique. A decision to make hazard ratios the
  primary analysis (A1/A2) would be post hoc and made with these in view.
- **Open decisions (RL and co-authors):** primary estimand (A1/A2); review
  framing (A8); eligibility rules for ATG in C1 arms, cord-blood comparators,
  aplastic anaemia, preprints, single-arm studies; definition or removal of
  C3.

## 2026-11-10 — Body word limit set to 3500

- **Change:** `body-words` in `_extensions/lancet-haematology/_extension.yml`
  changed from 4500 to 3500.
- **Basis:** the Lancet formatting guidelines for systematic reviews and
  meta-analyses (July 2025) give 3500 words for the main text and 300 for the
  summary. The 4500 figure in the Lancet journals' author information applies
  to randomised trials. The Lancet Haematology author page itself could not
  be opened (HTTP 403), so this rests on the group-wide guideline, not on a
  journal-specific page; confidence moderate to high. An editor's reply or
  the journal page would settle it.
- **Count at merge commit `fd512ca`** (Quarto 1.9.35; the README says the
  project was built with 1.10.18, which is not installed): summary 298, body
  3924. The counter includes Methods and the "Role of the funding source"
  subsection and excludes Research in context, tables, figure legends and
  citations.

## 2026-11-10 — Pushed to GitHub

- `main` pushed to `origin/main` at `902a8e6` (merge `fd512ca` plus the
  decision record, audit scripts and outputs, and the word-limit change).
  Only `main` was pushed. Pre-push scan of the pushed diff: no Word, Excel
  or R data files; no identifier-like text or e-mail addresses in added
  lines.

## 2026-11-10 — Why C1 contains comparators with ATG (assistant inference)

- **Finding:** the "no ATG" part of the C1 definition was written down but
  never enforced in code.
  - The definition is in the upstream schema
    (`~/ptcy_metaanalys/PTCy_MA_database_schema_v1.0.md`, line 108) and in
    the extractor instructions (`extraction_protocol/EXTRACTION_SPEC.md`,
    §4): C1 is CNI + MTX or MMF with no ATG and no ex-vivo T-cell depletion.
  - `comparison_1_eligible` was set per arm by the AI extractor at
    extraction. The JSON schema the extractor wrote to describes the field
    only as "PTCy vs CNI+MTX/MMF".
  - The only validation rule on the flags (R4 in `validate.py` and
    `export_to_csv.R`) checks that each eligible arm has an eligible
    comparator in the same study. Neither validator refers to `atg_used`.
  - No script found in `03_models/` or `PTCY_analysis/` upstream, or in
    `scripts/` here, filters on `atg_used` when building the C1 model sets;
    they select on the flag alone.
- **Size:** of 163 C1-eligible comparator arms in `data/arms.csv`, 68 have
  `atg_used = Y` and 22 `mixed`; of 148 C1-eligible PTCy arms, 27 are `Y` and
  10 `mixed`. All 90 flagged comparator arms come from studies recorded as
  extracted in May 2026 and verified.
- **Status:** inference from a text search of the upstream directory, not an
  exhaustive read (the two conversation exports were not read). Confidence
  that no programmatic check existed: high. Whether the stored `atg_used`
  values are themselves right is unknown; checking the flagged arms against
  the papers would settle it.

## 2026-11-10 — Exploratory hazard-ratio pooling, OS and NRM, C1 and C2 (post hoc)

- **Status: exploratory and post hoc.** Requested by RL after the revision
  checklist (A1/A2) and after the feasibility counts above. Not a primary
  analysis, not pre-specified, and not the existing HR sensitivity analysis
  (`scripts/hr-sensitivity-os.R`, Set B studies only, C1 k = 14). Nothing in
  the manuscript was changed.
- **Seen before it was run:** the observed-count results in the manuscript,
  the existing HR sensitivity result (C1 OS 0·88, 0·66–1·14), the checklist,
  and the C1 audit showing ATG recorded in many C1 arms.
- **Construction** (`scripts/hr-exploratory-os-nrm.R`): all studies with C1-
  or C2-eligible arms by the stored flags; only hazard ratios with both
  interval bounds whose stated reference arm is an eligible arm on the other
  side; one HR per study (adjusted preferred, then closest to one year, then
  larger arm pair); one study per `cohort_id`; direction harmonised to PTCy
  versus comparator; Bayesian normal-normal random effects with the priors of
  the existing HR script; REML check. Outputs:
  `audit/hr_exploratory_2026-11-10.csv` and
  `audit/hr_exploratory_inputs_2026-11-10.csv`.
- **Sets fixed before results were seen:** "all matched HRs", and for C1 "no
  ATG recorded in either arm".
- **Set added after results were seen:** "excluding non-primary cohort
  reports". Reason: the main BMT CTN 1703 report (study 2) has no hazard
  ratio in the database, so the cohort rule let its age ≥ 70 subset report
  (Abedin 2025, study 12; OS HR 0·08, 0·02–0·33, n = 96) stand in for the
  trial.
- **Results (HR, 95% CrI; k; trials):**
  - C1 OS: all 0·87 (0·77–0·99), k = 54, 5 trials; excluding non-primary
    0·89 (0·79–1·00), k = 53; no ATG recorded 0·84 (0·69–1·00), k = 21.
  - C1 NRM: all 0·85 (0·71–1·01), k = 47, 3 trials; excluding non-primary
    0·86 (0·73–1·03), k = 46; no ATG recorded 0·82 (0·62–1·07), k = 16.
  - C2 OS: 0·74 (0·57–0·90), k = 18, no trials.
  - C2 NRM: 0·88 (0·61–1·20), k = 17, no trials.
  - REML estimates agree to within 0·01; I² 67–82%; no divergences,
    R-hat 1·00.
- **Not done / not checked:** hazard-ratio direction, adjustment sets and
  timepoints against source papers; whether NRM hazard ratios are
  cause-specific or subdistribution; small-study effects; prediction
  intervals; the trials with no hazard ratio stored (BMT CTN 1703 main
  report, Brissot 2024, Fuchs 2021, Koura 2025, Zu 2023). HOVON-96 (Broers
  2022) has no C1- or C2-eligible arm by the stored flags.

## 2026-11-10 — Exploratory HR models: prediction intervals and small-study effects added (post hoc)

- **Status:** exploratory, post hoc, requested by RL after the pooled
  hazard ratios above had been seen. Same construction and script
  (`scripts/hr-exploratory-os-nrm.R`); the pooled estimates are unchanged.
- **Added:** 95% prediction intervals (from the posterior of the mean and
  between-study SD); Egger-type random-effects regression of log HR on its
  standard error (`metafor::regtest`, overall survival sets only); funnel
  plot `audit/hr_exploratory_funnel_os_2026-11-10.png`.
- **Overall survival:**
  - C1 all matched (k = 54): prediction interval 0·41–1·90; Egger z = −2·54,
    p = 0·011.
  - C1 excluding non-primary cohort reports (k = 53): prediction interval
    0·42–1·80; Egger z = −1·65, p = 0·10. The difference from the row above
    is one study (Abedin 2025).
  - C1 no ATG recorded (k = 21): prediction interval 0·39–1·76; Egger
    z = −2·93, p = 0·003.
  - C2 (k = 18): prediction interval 0·34–1·53; Egger z = −3·98, p < 0·001.
  - Regression estimates at zero standard error: C1 1·19 (0·92–1·54), C2
    1·22 (0·94–1·58). These are extrapolations, not corrected estimates.
- **Reading:** five Egger tests on overlapping sets, uncorrected. Asymmetry
  is a small-study effect and has several possible causes (selective
  reporting of hazard ratios, heterogeneity, confounding that differs by
  study size); it is not by itself evidence of publication bias.
- **Worklists for re-extraction** (`scripts/reextraction-worklist.R`):
  `audit/worklist_trials_without_hr_2026-11-10.csv` (10 of 14 trials lack a
  matched hazard ratio for overall survival or non-relapse mortality) and
  `audit/worklist_c1_comparator_atg_2026-11-10.csv` (90 arms, 81 studies).

## 2026-11-10 — Three duplicate database entries removed (checklist A7)

- **Decision (RL):** remove entries 51, 123 and 290, each a second entry of a
  publication already in the database (same DOI as 50, 122 and 187), and
  update the manuscript.
- **What was done** (`scripts/remove-duplicate-entries.R`): rows for the three
  identifiers dropped from `studies`, `arms`, `outcomes`, `rob`, tables
  S4a/S4b, the audit flags, five C1 analytic files, `data_c1_rrm.csv` and the
  appendix S4 reference list; overlap cross-references in studies 49, 122 and
  124 updated. Untouched rows are byte-identical.
- **Not identical extractions (assistant observation, not checked against
  the papers):**
  - 122 and 123 have different arm structures for the same paper: 122 has one
    PTCy arm (n = 110) against ATG (n = 35), flagged C2; 123 splits PTCy into
    haploidentical (n = 110) and MMUD (n = 17) arms and was flagged C1. The
    retained entry (122) therefore has 17 fewer patients. Which split is
    right needs the paper.
  - 50 and 51 carry different ROBINS-I overall judgements for the same paper
    (serious and moderate). The retained entry (50) is "serious".
- **PRISMA flow (assistant inference from precedent):** following the Wu 2025
  duplicate (appendix S12), the three entries were moved from "included" to
  full-text exclusions as duplicate publications (215 → 218; duplicate
  publication 14 → 17; included 250 → 247), so the flow still reconciles to
  465 reports assessed. Whether Covidence held these as separate reports was
  not checked; the Covidence export would settle it.
- **Counts:** 247 studies, 516 arms, 175 570 patients (221 comparative
  studies, 511 arms, 175 182 patients); 104 pooled (C1 71, C2 27, C3 13, 7
  in more than one); ROBINS-I 207 (141 serious, 66 moderate). Every
  database-derived count is recomputed by `scripts/manuscript-counts.R`; the
  before/after list is `audit/duplicate_removal_count_changes_2026-11-10.csv`.
  Unique patients after cohort deduplication (111 214) is unchanged.
- **Model affected:** only C1 relapse-related mortality, where entries 50 and
  51 were both pooled with identical counts. Refitted without 51
  (`scripts/run-rrm-cascade-duplicate-removal.R`), same specification and
  seed as the reported fit:
  - M1: k 34 → 33; OR 0·87 (0·76–0·99) → 0·86 (0·75–0·98); τ 0·08; prediction
    interval 0·64–1·17.
  - M2 0·84 (0·70–1·01), k = 26; matched-set M1 0·86 (0·73–1·01).
  - REML 0·85 (0·76–0·96); fixed-intercept 0·85 (0·74–0·97); donor
    meta-regression 0·86 (0·75–0·98); donor-matched 0·85 (0·65–1·08), k = 17.
  - RoBMA 0·95 (0·78–1·00), BF for effect 0·62, for bias 1·0. This one row
    was fitted with RoBMA 4.1.1; the appendix states 4.0.0 for the others.
  - Donor, matched-set and RoBMA refits used new seeds for the first two
    (the original seed sequence is not recoverable for a single model) and
    the original seed for RoBMA.
  - Only the C1 RRM rows of the derived CSVs were rewritten; other rows were
    restored to their committed text so no other number moves by formatting
    or Monte Carlo noise. Stale fits are kept in
    `_fits_rs/_stale_duplicate_removal_2026-11-10/`.
- **Figures regenerated:** figure 1 (PRISMA), S5a/S5b (ROBINS-I, n = 207),
  S8d (RRM forest).
- **Known to be stale after this change:**
  - Figures S7c and S7d(i) (τ posteriors and posterior predictive checks,
    which include the C1 RRM fit) and S12 (cohort overlap map) were not
    regenerated.
  - Appendix S9 "175 of the 202 steroid-complete arms (87%)" and the CMV
    serostatus availability percentages (47%, 31%) could not be reproduced
    from the data with the formulas tried, so they were left as they were.
  - The Set A (pre-deduplication) C1 RRM row (k = 38) was not refitted; the
    Set A data are outside this repository.
  - `audit/pooled_studies_audit_2026-11-10.csv` and the worklists predate
    the removal and still list entries 51 and 123.

## 2026-11-10 — A3 survival wording applied; figure S7d(i) regenerated

- **Decision (RL):** apply the three proposed A3 passages to `index.qmd`
  (Summary Interpretation, Research in context Implications, conclusion):
  a survival benefit is stated as not demonstrated. The supporting numbers
  are the manuscript's existing analyses (pooled hazard ratio 0·88,
  0·66–1·14; publication-bias-adjusted 0·97, 0·71–1·16; prediction interval
  0·29–1·82), not the exploratory hazard-ratio models of this date.
  Wording drafted by the assistant. Other A3 items (Results "better overall
  survival", Discussion "68 fewer deaths per 1000", "extend across donor
  types") and A4/A5/A9 wording in the same passages are unchanged.
- **Word counts after the change** (Quarto 1.9.35): summary 300 (limit 300),
  body 3952 (limit 3500).
- **Figures:**
  - S7d(i) (posterior predictive checks, C1) regenerated with the refitted
    C1 RRM model. It needs the gitignored fits in `_fits_rs/` and the theme
    file `~/ptcy_metaanalys/05_website/_common.R`, so it cannot be rebuilt
    from this repository alone.
  - S7c (τ posteriors) does not include the RRM model (OS, NRM, aGVHD, CMV,
    BSI, IFI only), so it was not stale. This corrects the entry above.
  - S12 (cohort overlap map) was not regenerated: no script that produces it
    was found in this repository or in `~/ptcy_metaanalys`. The committed
    file dates from the initial project commit.

## 2026-11-10 — Body of index.qmd cut to the 3500-word limit; S12 rebuild script

- **Decision (RL):** cut about 450 words from the body, starting with the
  passages the checklist marks as movable to the appendix. The choice of the
  other cuts was the assistant's and has not been reviewed.
- **Cuts where the detail remains in the appendix:** per-outcome attrition
  sentence (S12); prior, sampler and convergence details (S6, S7);
  steroid-adjustment model description (S9, S13); hazard-ratio sensitivity
  method (S9); RoB 2 measurement-domain sentence (S5); comparator-backbone
  subgroup estimates (S9); letermovir cohort detail (S9); GRADE imprecision
  detail for acute GVHD (S11).
- **Cuts of repeated or explanatory text:** second statement that single-arm
  studies were not pooled; why donor type matters; EBV/HHV-6 sentence
  shortened; sparse-outcome limitation shortened (this also removes "probably
  narrower than they should be", checklist B12).
- **Cuts that change content (checklist A3 and B14):**
  - "about 68 fewer deaths per 1000 patients by one year" removed.
  - "This offers a plausible explanation for how PTCy could be associated
    with better survival despite concerns about infection" removed.
  - "extend across donor types, conditioning regimens, and geographic
    settings" removed.
  - The infection-reporting subsection was shortened to two sentences and
    its heading dropped. Its first sentence now says 104 of 247 studies
    could be pooled for any outcome, instead of saying they had sufficient
    information on infectious complications.
- **Not changed:** the Discussion opening and the Results still say "better
  overall survival", which no longer matches the Summary and conclusion.
- **Figure S12:** `scripts/regenerate-s12-cohort-overlap.R` rebuilds the
  cohort overlap map from `data/studies.csv` and `data/cohorts.csv`. The rule
  (cohorts with two or more included publications) reproduces the 25 bars of
  the committed figure on the pre-removal data. A preview on the corrected
  data (24 cohorts) is at `audit/FigureS12_preview_2026-11-10.png`; the
  committed figure has not been replaced.

## 2026-11-10 — Figure S12 replaced

- **Decision (RL), after seeing the preview:** the committed figure S12
  files were replaced by the output of
  `scripts/regenerate-s12-cohort-overlap.R` (24 multi-publication cohorts).
  This supersedes the statement in the previous entry that the committed
  figure had not been replaced.

## 2026-11-10 — "Better overall survival" reworded in Results and Discussion

- **Decision (RL):** bring the Results survival paragraph and the Discussion
  opening into line with the conclusion. Results now says "lower odds of
  death" for the primary estimate; the Discussion opening says a survival
  benefit was not demonstrated. Wording by the assistant.
- **Left as they are:** "possibly better survival" in the benefit–risk
  paragraph of the Discussion, and "strengthened rather than weakened the
  survival association" in the sensitivity analyses.
- **Checklist Part B reviewed against the current files** (no edits made):
  B14 no longer applies; B12 partly applies; B15 does not apply to the CMV
  sets and could not be checked for BK; the other sixteen still apply.

## 2026-11-10 — Checklist B5–B7 corrected in the appendix; B3/B4 traced (no refit)

- **B5–B7 (counts only, no estimate changed; assistant, checked against the
  saved fits):** the stored k values counted input rows, including rows
  without event counts that the models drop.
  - C2 overall survival excluding PTCy+ATG-arm studies: k 9 → 6. The fit
    contains the same six studies as the primary C2 survival model, so this
    exclusion removes no pooled study.
  - C2 acute GVHD excluding PTCy+ATG-arm studies: k 6 → 5 (studies 24 and 49
    excluded from the seven pooled). Same cause; found while fixing B5.
  - C1 CMV letermovir text: 44 arms / 28 confirmed non-use → 42 / 26.
  - `data/models/comparator_backbone.csv` still holds k = 9 and 6.
- **B3/B4 (finding, not fixed):** the trial-only and observational-only
  models (`scripts/refit-reporting-suite.R`, section 1) were not fitted on
  the primary model sets. They read `data/analytic/*.csv`, not
  `data/models/data_c1_*.csv`, and keep the largest study per cohort
  instead of the designated primary publication.
  - CMV: the analytic file holds only 21 studies, 7 with event counts; 13
    observational studies in the primary CMV model are absent from it.
  - Overall survival: studies 9 and 281 are fitted in place of 338 and 52
    (same cohorts), and study 180 has no counts in the analytic file.
  - Chronic GVHD: study 180 has no counts and study 375 is absent.
  - Acute GVHD and non-relapse mortality match the primary observational
    sets.
  - By stored study design the primary sets hold 27, 27, 16, 10 and 20
    observational studies (OS, aGVHD, cGVHD, NRM, CMV) and 2, 1, 2, 1 and 1
    trials; the appendix states 0 trials for CMV.

## 2026-11-10 — comparator_backbone.csv k corrected

- `data/models/comparator_backbone.csv`: k for the two C2 PTCy+ATG-exclusion
  rows corrected to the number of studies in the saved fits (acute GVHD 6 →
  5; overall survival 9 → 6), matching the appendix. Estimates unchanged.

## 2026-11-10 — Observational-only models refitted on the primary sets (checklist B3/B4)

- **Decision (RL):** refit the observational-only models for C1 overall
  survival, chronic GVHD (moderate–severe) and CMV on the primary model
  inputs (`data/models/data_c1_*.csv`, rows with event counts in both arms)
  with randomised trials removed. Same M1 specification, priors and sampler
  settings as the reported observational-only fits; new seeds.
  Script: `scripts/refit-obs-only-primary-sets.R`; output
  `audit/obs_only_refit_2026-11-10.csv`.
- **Seen before the refit:** the reported observational-only estimates, the
  primary estimates, and the finding above that the reported fits used
  different study sets.
- **Results (OR, 95% CrI; reported → refit):**
  - Overall survival: 0·79 (0·63–0·96), k = 26 → 0·73 (0·58–0·90), k = 27.
  - Chronic GVHD: 0·48 (0·27–0·86), k = 14 → 0·47 (0·27–0·81), k = 16.
  - CMV: 1·01 (0·64–1·64), k = 7 → 1·21 (0·87–1·66), k = 20.
  - No divergences; R-hat ≤ 1·002.
- **Reading:** each refit differs from its primary model only by the removal
  of one or two small trials, so it is close to the primary estimate by
  construction (primary: 0·73, 0·41 and 1·20). It shows that the trials do
  not drive the pooled estimates; it is not independent support for them.
  The CMV trial removed is Koura 2025 (study 432; 25 and 15 patients), so
  the appendix statement that no trial contributes to CMV is wrong.
- **Not changed yet:** `index.qmd`, `appendix.qmd`,
  `data/models/rct_only_results.csv` and the earlier fits. The manuscript
  still quotes the reported values, including in the Results sensitivity
  paragraph.
- **Appendix wording (RL):** the PTCy+ATG exclusion sentence in S9 now says
  that no study pooled for C2 overall survival contained such an arm, so
  that row repeats the primary model and is not a sensitivity analysis.

## 2026-11-10 — Observational-only refits adopted in the manuscript

- **Decision (RL), after seeing old versus new estimates:** the refits on
  the primary model sets replace the reported observational-only values for
  C1 overall survival (0·73, 0·58–0·90, k = 27), chronic GVHD (0·47,
  0·27–0·81, k = 16) and CMV (1·21, 0·87–1·66, k = 20) in `index.qmd`,
  appendix S9 and `data/models/rct_only_results.csv`. The CMV trial count is
  corrected from 0 to 1. Acute GVHD and non-relapse mortality are unchanged.
- The S9 text now says these analyses use the primary model sets, not the
  full analytic datasets. The earlier fits (`rep_c1_*_obs.rds`) are kept;
  the adopted fits are `rep_c1_*_obs_primaryset.rds`.

## 2026-11-10 — Full render; two formatting faults from the duplicate-removal edit found and fixed

- **Full `quarto render` (Quarto 1.9.35):** article HTML, Word and PDF and
  the appendix Word and PDF built. The typeset preview PDF failed: the
  LaTeX font package XCharter is not installed in TinyTeX. No tracked file
  was changed by the render.
- **Fault introduced by the assistant in commit `46af767`:** the script that
  applied the count replacements left a stray blank line in two places.
  In `index.qmd` it split the figure 1 legend, so figure 1 was not built as
  a figure and `@fig-prisma` did not resolve. In `appendix.qmd` it split
  the Set A / Set B table in S12 after the relapse-related mortality row.
  Both blank lines are removed; the article renders without the
  cross-reference warning and the appendix Word file builds. Earlier
  article renders in this session were checked only for word counts and
  errors, not warnings, which is why this was missed.

## 2026-11-10 — Preview PDF builds; rendered Word files checked against source

- **LaTeX packages installed (at RL's request):** `xcharter` and `lato`,
  from the frozen TeX Live 2025 repository
  (`ftp.math.utah.edu/pub/tex/historic/systems/texlive/2025/tlnet-final`),
  because the local TinyTeX is TeX Live 2025 and the current mirrors serve
  2026. TinyTeX itself was not upgraded.
- **Full `quarto render` (Quarto 1.9.35) at commit `3459815`:** exit code 0,
  no Quarto warnings or errors; article HTML, Word and PDF, appendix Word
  and PDF, and the typeset preview PDF all built. No tracked file changed.
  The preview's LaTeX log has 124 overfull-box messages (layout only).
- **Word files checked by the assistant by reading the document XML, not by
  eye:** Table 1 (40 rows), Table 2 (25 rows) and the two appendix S12
  tables (25 and 9 rows) match the source cell for cell. Figure 1 is built
  as a figure with one caption. No unresolved cross-references in the Word
  files or the three PDFs. Page layout, fonts and figure sizes were not
  checked.
- **Noted, not changed:** the article PDF is 35 pages and the appendix PDF
  104 pages; the PRISMA checklist in S14 cites a 31-page article and a
  72-page appendix, so its page and line references are stale.
