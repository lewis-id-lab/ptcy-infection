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
