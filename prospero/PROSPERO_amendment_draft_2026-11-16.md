---
title: "PROSPERO CRD420261372156: draft amendment and status update"
subtitle: "Draft for RL, prepared 16 November 2026. Not yet filed."
---

# How to use this document

Part A is the status update. Part B is the amendment text, written to be pasted into the record. Part C lists items that need a decision or
a check before filing; some of them could change Part B.

Text in **[square brackets, bold]** must be filled in or confirmed by RL before filing. The "When decided" lines are taken from the dated
decision record (`DECISIONS.md`, from 10 November 2026), the git history of the manuscript (first commit 3 September 2026) and
`EXTRACTION_AUDIT.md`. Where those sources do not show when a decision was made, the line says so. For decisions made before
10 November, the date is that of the first file version in which the change appears, so the decision may have been made earlier.

Sources compared: the registered protocol (`~/ptcy_metaanalys/PTCy_PROSPERO_Protocol_Final.docx`, version 2, 17 April 2026; on
12 November RL confirmed that its outcome and analysis sections match the public record verbatim; that the other sections also match is
an assistant inference, not checked) against the manuscript (`index.qmd`) and appendix (`appendix.qmd`) as of 16 November 2026.

PROSPERO's current form may use different field names or have length limits; adjust the layout to fit.

# Part A. Review status

**Current review status:** Completed but not published.

**Anticipated publication date:** **[date]**

**Free-text explanation (suggested):**

> Searches, screening, data extraction, risk-of-bias assessment and synthesis are complete. The manuscript is
> **[in preparation for submission / submitted]** to **[journal]**. Deviations from the registered protocol are recorded in the amendment
> of **[filing date]** and are reported in the manuscript's supplementary appendix (section S13).

**Stage of review:** mark all stages (preliminary searches, piloting of study selection, formal screening, data extraction, risk-of-bias
assessment, data analysis) as started and completed.

# Part B. Amendment text

## Summary (for the "reason for amendment" or equivalent field)

> This amendment records deviations from the registered protocol (version 2, 17 April 2026). Unless stated otherwise, they were decided
> after data extraction had begun. Several were decided after pooled estimates had been seen; this is stated for each item. The registered
> primary outcomes (bacterial bloodstream infection, CMV reactivation, invasive fungal infection) are unchanged and are reported as the
> registered primary outcomes. Outcomes added after registration, including overall survival, are reported as additions and not as
> pre-specified outcomes. All deviations are also reported in the published supplementary appendix.

## Changes to searching, selection and data collection

1. **Information sources.** *Registered:* PubMed/MEDLINE, Embase, Cochrane CENTRAL and Web of Science Core Collection. *Done:* PubMed,
   Embase and Scopus were searched (to 30 April 2026). CENTRAL and the Web of Science Core Collection were not searched as databases;
   Web of Science was used for forward citation tracking only. *Reason:* **[RL]**. *When decided:* when the searches were run, before
   screening.

2. **Date limit.** *Registered:* publications from 2010 onwards (search filter and exclusion criterion). *Done:* databases were searched
   from inception with no date limit. No included study was published before 2010. *Reason:* **[RL]**. *When decided:* when the searches
   were run, before screening.

3. **Single-arm studies.** *Registered:* single-arm studies excluded. *Done:* 26 single-arm descriptive studies were retained in the
   review for descriptive tabulation only; they were not eligible for any pooled analysis. *Reason:* **[RL]**. *When decided:* **[RL]**.

4. **Data extraction.** *Registered:* extraction by the lead reviewer, with 100% independent verification by the co-lead reviewer.
   *Done:* data were extracted from the PDF source documents by an AI model (Claude Opus 4.8, Anthropic) using a purpose-built extraction
   script and specification, and all extracted values were verified manually by both investigators against the source publications.
   *Reason:* **[RL]**. *When decided:* before extraction began.

5. **Risk-of-bias disagreements.** *Registered:* resolved by consensus. *Done:* resolved by a third investigator (DPK). *When decided:*
   **[RL]**.

## Changes to outcomes

6. **Outcomes added.** Overall survival, acute GVHD grade II–IV, moderate-to-severe chronic GVHD (NIH), relapse-related mortality, and
   BK virus–associated haemorrhagic cystitis were added. Overall survival was designated the main analysis outcome because survival was
   more completely reported than the registered infection outcomes (comparison 1 studies with paired-arm records: overall survival 113,
   CMV 44, bloodstream infection 13, invasive fungal infection 7). *When decided:* after data extraction. All five outcomes, with overall
   survival as the main outcome, are in the earliest manuscript version (3 September 2026). **[RL: were any pooled estimates seen before
   overall survival was designated the main outcome?]**

7. **Bloodstream infection.** *Registered:* any-pathogen bacterial bloodstream infection by day +30 (primary timepoint). *Done:* the
   primary analysis is culture-confirmed bacterial bloodstream infection by day +100, because only one comparison 1 study reported paired
   observed counts at day +30. Any-pathogen bloodstream infection is reported as a sensitivity analysis. *When decided:* 2 October 2026,
   during the post-adjudication data audit, after pooled estimates had been seen.

8. **Invasive fungal infection.** *Registered:* EORTC/MSG proven or probable, stratified as invasive mould and invasive yeast disease,
   day +180. *Done:* any proven or probable invasive fungal infection (mould and yeast combined) at the latest reported timepoint, because
   few studies reported mould (two) or yeast (one) disease separately or reported at day +180 (one). The pooled set includes one study
   whose definition includes possible infection and one reporting fungal-attributed mortality. *When decided:* after data extraction;
   **[RL: date, and whether before or after pooled estimates were seen]**.

## Changes to the analysis

9. **Model and priors.** *Registered:* binomial model with arm-specific random effects by cohort, priors N(0, 1·5) on the log odds ratio
   and half-Normal(0, 0·5) on the between-study SD. *Done:* binomial model with a random study intercept and a random PTCy-effect slope by
   study, and an indicator for fallback timepoints; cohort overlap handled by deduplication (one publication per cohort per outcome, as
   registered). Priors N(0, 2·5) on regression coefficients, N(0, 1·5) on the intercept, Student-t(3, 0, 1) on the between-study SDs.
   *Reason:* early analyses with a common-effect specification masked between-study heterogeneity for the infection outcomes. *When
   decided:* after pooled estimates from the earlier specification had been seen; the random-slope models were fitted on 30 September
   2026. The Student-t priors are in the earliest manuscript version (3 September 2026).

10. **Observed event counts only.** Event counts derived from cumulative-incidence or Kaplan–Meier estimates, rather than reported as
    observed counts, were excluded from pooling. *Reason:* derived counts disagreed with reported counts during data verification, and
    such estimates allow for censoring and competing risks, so they do not recover event numbers. *When decided:* 2 October 2026, after
    data verification, when pooled estimates had been seen.

11. **Steroid-adjustment model.** An exploratory model adding arm-level systemic corticosteroid exposure as a covariate was added. It is
    reported in the appendix only and labelled exploratory. *When decided:* after data extraction; it is in the earliest manuscript
    version (3 September 2026).

12. **GRADE imprecision thresholds.** Odds ratio thresholds of 0·80 (benefit) and 1·25 (harm) were defined at the analysis stage.
    *When decided:* at the analysis stage, **[RL: before or after pooled estimates were seen]**.

13. **Prior sensitivity analysis.** *Registered:* re-runs with half-Cauchy(0, 0·5) and half-Normal(0, 1·0) priors on the between-study
    SD. *Done:* re-runs with Student-t(3, 0, 0·5) and Student-t(3, 0, 2) priors, bracketing the adopted Student-t(3, 0, 1) prior, for the
    sparse outcomes (comparison 1 bloodstream infection and invasive fungal infection) only. *When decided:* 12 November 2026, after all
    pooled estimates had been seen.

14. **Pooling of hazard ratios.** *Registered:* time-to-event data (hazard ratios, cumulative incidence functions) to be treated as
    narrative or supporting data and not pooled. *Done:* two post hoc pooled hazard-ratio analyses of overall survival are reported in the
    appendix: a hazard-ratio sensitivity analysis, and a two-stage analysis that includes studies excluded from the primary model by the
    observed-counts rule (item 10), with publication-bias assessment by RoBMA. *Reason:* to examine the evidence excluded by the
    observed-counts rule. *When decided:* the two-stage analysis was specified on 13 November 2026, after all other results had been seen;
    **[RL: date of the hazard-ratio sensitivity analysis]**.

15. **Additional post hoc sensitivity and subgroup analyses**, all reported in the appendix and labelled as post hoc or exploratory:
    fixed (stratified) study intercepts; donor-type confounding (meta-regression on the between-arm difference in haploidentical-donor
    percentage, and a donor-matched restriction); randomised-trials-only and observational-only models; comparator-backbone subgroups and
    exclusion of PTCy+ATG arms (comparison 2); alternative CMV outcome definitions; BK virus outcome scope; an indirect comparison of
    comparison 1 and comparison 2 effects; and a comparator-class meta-regression for CMV. *When decided:* after pooled estimates had been
    seen.

## Registered methods not carried out

16. **Outcomes not analysed.** Investigator-reported invasive fungal infection and severe bacterial infection (Sepsis-3 or CTCAE
    grade ≥3) were not analysed. CMV end-organ disease was too sparsely reported to pool.

17. **Sensitivity analyses not performed.** Inclusion of conference abstracts; restriction to studies rated low or moderate risk of bias;
    parallel Poisson/negative-binomial model for incidence rates per patient-time.

18. **Meta-regression not performed** on graft source, conditioning intensity, antimould prophylaxis regimen, PTCy dose, region, and ATG
    dose category within comparison 2. Donor type, letermovir era and use, CMV serostatus distribution, and publication era were examined
    only in modified form (between-arm haploidentical-donor difference, enrolment-era proxy, recipient serostatus difference, and
    restriction to publications from 2020 onward).

19. **Contact with study authors.** *Registered:* two contact attempts for missing critical data. **[RL: confirm. The extraction database
    records no author contact for any of the 247 included studies.]**

# Part C. Check before filing

These are not amendment text. Some could add items to Part B or change the statement that the analysis is finished.

1. **Comparison 1 comparators with ATG (unresolved).** The registered protocol and the manuscript Methods define comparison 1 as having no
   ATG. The 10 November decision record found that this rule was never applied in code: 90 of 163 comparison 1 comparator arms record ATG
   use (68 yes, 22 mixed), and 37 of 148 comparison 1 PTCy arms do. The re-extraction worklist
   (`audit/worklist_c1_comparator_atg_2026-11-10.csv`, 90 arms in 81 studies) has not been worked through. Either the arms are checked
   against the papers and the models refitted, or the definition actually used is reported as a deviation. Until then, describing the
   analysis as finished is premature.

2. **Arms with fewer than 20 patients.** The protocol excludes studies with fewer than 20 patients per arm. In `data/arms.csv`, 20 arms in
   15 studies record fewer than 20 patients. It is not yet checked whether any of these are in pooled analyses or whether the rule was
   applied per study rather than per arm. Not checked against the papers.

3. **Methods in the protocol that the repository does not document:** PRESS peer review of the search strategy; the kappa calibration on
   the first 50 records; the third reviewer and the co-lead's recusal from her own institution's publications; the 100% verification of
   extraction by the co-lead. If any were not done, add them to "Registered methods not carried out".

4. **Full-text exclusions (protocol section 3.4.2).** The registered protocol states that full-text exclusion reasons will be recorded. The
   study-level list for appendix S2 is still waiting for the Covidence export; the PRISMA count of 218 includes three entries moved there
   by assistant inference (DECISIONS.md, 10 November). This does not affect the amendment but may change the flow diagram.

5. **Title.** The registered title ("Infection Outcomes with Post-Transplant Cyclophosphamide versus Non-PTCy Graft-versus-Host Disease
   Prophylaxis in Adult Allogeneic Hematopoietic Cell Transplantation…") differs in wording from the manuscript title. The content is
   consistent; changing the registered title is optional.

6. **After filing:** update appendix S13 ("They are not recorded in the PROSPERO record", `appendix.qmd` line 656) to cite the amendment
   date, add the deviations in items 1–5 and 14–15 of Part B that S13 does not yet list, update PRISMA item 24c in S14, and add a dated entry
   to `DECISIONS.md`.
