# PTCy and infection risk after allo-HSCT — Lancet Haematology manuscript

A [Quarto manuscript](https://quarto.org/docs/manuscripts/) project for:

> Stanzani M, Kontoyiannis DP, Lewis RE. *Post-transplant cyclophosphamide as
> graft-versus-host disease prophylaxis after allogeneic haematopoietic stem-cell
> transplantation: a systematic review and Bayesian meta-analysis of infection risk.*

One source, three outputs: a submission `.docx`, a reviewer `.pdf`, and a manuscript
website that publishes the computational notebooks alongside the article.

## Quick start

```bash
quarto render      # article + appendix + preview, into _manuscript/
quarto preview     # live preview while editing
```

`quarto render` produces all four submission files:

| File | |
|:--|:--|
| `_manuscript/index.docx` | article, Word — the submission file |
| `_manuscript/index.pdf` | article, PDF with line numbers |
| `_manuscript/appendix.docx` | supplementary appendix, Word |
| `_manuscript/appendix.pdf` | supplementary appendix, PDF |
| `_manuscript/index-preview.pdf` | typeset reading copy — *not for submission* |

plus `_manuscript/index.html`, the manuscript website, which links the notebooks and
offers the other formats for download.

The appendix is a separate document because the journal wants it as its own file. A
manuscript project renders only its article and notebooks and ignores
`project: render:`, so the appendix is built by a post-render hook,
`scripts/render-appendix.sh`. It runs on a full `quarto render` only — during
`quarto preview` a 31-page PDF rebuild on every save would make the preview unusable.

To rebuild one thing on its own:

```bash
quarto render index.qmd    --to lancet-haematology-docx   # article only
quarto render appendix.qmd --to lancet-haematology-pdf    # appendix only
```

A single-file render writes its output to the project root rather than `_manuscript/`;
that is Quarto's behaviour, and the hook is what tidies the appendix into place on a
full render.

## If the site's download buttons misbehave

Clicking **PDF** on the manuscript website can fail with *"The address wasn't
understood — chrome-extension://mhjfbmdgcfjbbpaeojofohoefgiehjai/index.html"*.

That address is Chrome's built-in PDF viewer. Chrome follows a plain
`<a href="index.pdf">` into the viewer rather than downloading it, and the page's URL
becomes an internal `chrome-extension://` one. If anything then hands that URL to
another application — an `--app=` window delegating an out-of-scope navigation, an
external-protocol prompt — the receiving browser cannot open it, because that scheme
only exists inside Chrome.

`assets/force-download.html` marks the format links as downloads, which keeps Chrome's
viewer out of the loop entirely. If you still hit it, skip the website — it is a
convenience, not the deliverable. The submission files are plain files:

```bash
evince _manuscript/index.pdf
evince _manuscript/appendix.pdf
xdg-open _manuscript/index.docx
```

Or serve the site over HTTP instead of opening it from disk, which avoids `file://`
handling quirks as well:

```bash
quarto preview
```

## Layout

```
index.qmd                     the article
appendix.qmd                  the supplementary appendix
references.bib                bibliography (recovered from the Zotero fields in the ODT)
_quarto.yml                   project config: formats, notebook list, post-render hook
scripts/render-extras.sh      builds the appendix and preview on a full render

_extensions/lancet-haematology-preview/
  _extension.yml              typeset preview format (two-column, journal livery)
  lancet-preview.tex          geometry, colours, masthead, panel, title block
  lancet-preview.lua          lifts Summary full width, floats the panel
  partials/before-body.tex    the opening title block

_extensions/lancet-haematology/
  _extension.yml              the custom journal format
  the-lancet.csl              Lancet reference style (Vancouver, numbered)
  lancet-reference.docx       Word styling: 12pt Times, double spaced, line numbers
  lancet-haematology.lua      house-style filter + word-count check
  styles.css                  screen preview

notebooks/                    computational notebooks, published with the article
  study-characteristics.qmd   rebuilds table 1 from the extraction database
  pooled-estimates.qmd        formats table 2 from the exported model posteriors
  forest-plots.qmd            redraws the forest plots from event counts
  prisma-flow.qmd             builds figure 1 with the PRISMA2020 package

data/prisma_flow.csv          the PRISMA2020 counts template, filled in

data/                         extraction database and analytic datasets
  studies.csv arms.csv rob.csv outcomes.csv cohorts.csv
  analytic/                   per-outcome paired datasets (C1/C2/C3 × outcome)
  models/                     exported posterior summaries (Set B)
figures/                      every figure in png + pdf + svg
```

## The `lancet-haematology` format

A Quarto [journal format extension](https://quarto.org/docs/journals/formats.html) that
contributes three outputs. Select one with `--to lancet-haematology-docx`,
`-pdf`, or `-html`.

**What it sets:**

| | |
|:--|:--|
| References | The Lancet CSL — numbered in order of first appearance, `1 Author A, Author B, et al. Title. *Journal* 2023; **5:** 1739–48.` |
| Word file | 12 pt Times New Roman, double spaced, ragged right, continuous line numbers, page numbers |
| PDF | A4, 1 inch margins, 12 pt, double spaced, `lineno` line numbers |
| Images | Picks the right rendition per format automatically — PNG into Word, PDF into LaTeX, SVG on screen — so figures are written without a file extension |
| Language | `en-GB` |

**Word counts.** Every render prints the Summary and body word counts against the
journal's limits:

```
[lancet-haematology] word count
  Summary     366 words (limit 300)  OVER by 66
  Body       3102 words (limit 4500)
```

Reference lists, tables, figure legends, and the Research in context panel are excluded,
matching how the journal counts. Adjust the limits under `lancet:` in
`_extensions/lancet-haematology/_extension.yml`.

**Middle-dot decimals.** The Lancet sets decimals as `0·79`, not `0.79`. The prose here
already uses middle dots, so the conversion is off by default. If you paste in new
numbers with plain decimal points, set `middot: true` in the extension and the filter
will convert them (it skips version-like runs such as `2.23.0`).

## The typeset preview

`_manuscript/index-preview.pdf` approximates the printed journal: two columns on
the 210 x 282 mm trim, the crimson masthead and rules, affiliations in the opening
page's left margin, the Research in context panel as a tinted full-width float, and
the journal's footer line.

**It is not a submission format.** Journals want a plain manuscript — one column,
double spaced, line numbered — which is what `_manuscript/index.pdf` is. Use the
preview to judge length and to see how the article reads in print; send the plain one.

Two things it necessarily gets wrong. The journal sets Shaker2Lancet and
ScalaLancetPro, both proprietary; Lato and XCharter stand in. And the article's
tables and figures drop to a single column at the "Tables" heading, because pandoc
emits tables as `longtable`, which LaTeX cannot typeset in two-column mode — the
journal also runs its large tables full width, so this reads as intended.

Colours are sampled from the reference PDF rather than guessed: crimson `#B20D35`,
panel tint `#F7DFDF`.

## Figure style

Figures use the same crimson. The forest plots (`notebooks/forest-plots.qmd`) drop
the gridlines, mark study rows with crimson squares and the pooled estimate with a
crimson diamond, and set titles in the sans face. The PRISMA diagram
(`notebooks/prisma-flow.qmd`) takes the crimson title bar and tinted stage rails.

One wrinkle worth knowing if you edit the PRISMA colours: the `PRISMA2020` package
writes its colour arguments into the Graphviz source unquoted, so a hex value is a
DOT syntax error and only X11 colour names get through. The notebook therefore
builds with the defaults and rewrites the colours in the generated DOT. The white
title-bar text has to be set on the title node itself — putting `fontcolor` in the
`node [...]` defaults block turns every label in the diagram white.

## Where the content came from

- **Text, tables, figure legends** — `ptcy_lancethameamtology.odt`.
- **Bibliography** — recovered from the Zotero CSL-JSON embedded in that ODT's citation
  fields. Only 12 references were live Zotero fields; see *Known gaps* below.
- **Figure 1** — built by the `prisma-flow` notebook with
  [PRISMA2020](https://github.com/prisma-flowdiagram/PRISMA2020) from
  `data/prisma_flow.csv`. The version in the analysis repository was a Mermaid
  flowchart that did not follow the standard layout.
- **Figures, data, model output** —
  [github.com/Russlewisbo/ptcy_metaanalys](https://github.com/Russlewisbo/ptcy_metaanalys),
  vendored into `figures/` and `data/` so this project renders standalone.

## Known gaps

Carried over from the source document, and flagged as `TODO` comments in the `.qmd`
files where they belong:

1. **The bibliography was incomplete** — the ODT contained 12 live Zotero references,
   all in the Introduction and Research in context. Discussion citations have since been
   added (the ten prior comparative meta-analyses, the letermovir phase 3 trial, and the
   mechanism references); export the full library from Zotero or EndNote if further
   citations are needed.
2. **Declaration of interests is a per-author placeholder** — MS and REL declare no
   competing interests; DPK's disclosures must be completed before submission (TODO in
   `index.qmd`, with his recent public disclosures summarised there).
3. **AI-assistance tool naming is resolved** — Claude Code (Anthropic, Inc.) for PDF
   data extraction and Posit Assistant (Posit, Inc.) for R-code debugging, named
   consistently in the Methods and the AI declaration.
4. **The final search date is not recorded.** The Methods said "April 31, 2026", a date
   that does not exist; it reads "April 30, 2026" here pending confirmation from the
   Covidence export log.
5. **S10 publication bias** and **S14 PRISMA checklist** are marked incomplete in the
   source appendix.

## Which analysis the article reports

The article reports **Set B**, the cohort-deduplicated analysis: one publication per
cohort contributes to each outcome, so no patient is counted twice within an outcome.
The pooled estimates come from `data/models/Table2_setB.csv`, and the
`pooled-estimates` notebook renders table 2 straight from that file.

Deduplication changed seven outcomes. The rest are identical to the pre-deduplication
fits, and `Table2_setB.csv` records which is which in its `source` column.

| Outcome | Before | Set B (reported) |
|:--|:--|:--|
| C1 overall survival, M1 | k=40, OR 0·79 (0·73–0·85) | k=29, OR 0·73 (0·58–0·89) |
| C1 overall survival, M2 | k=40, OR 0·86 (0·77–0·96) | k=24, OR 0·95 (0·70–1·29) |
| C1 relapse-related mortality | k=38, OR 0·84 (0·76–0·93) | k=34, OR 0·87 (0·76–0·99) |
| C1 chronic GVHD mod–severe | k=21, OR 0·33 (0·29–0·36) | k=18, OR 0·41 (0·23–0·72) |
| C1 infection-related mortality | k=16, OR 1·35 (1·16–1·57) | k=13, OR 1·02 (0·67–1·50) |
| C2 overall survival | k=10, OR 0·81 (0·74–0·90) | k=6, OR 0·75 (0·43–1·28) |
| C2 acute GVHD | k=9, OR 0·58 (0·44–0·77) | k=7, OR 0·53 (0·23–1·17) |
| C2 CMV reactivation | k=13, OR 0·92 (0·73–1·15) | k=12, OR 0·86 (0·51–1·42) |

### One conclusion changed, and needs the co-authors' sign-off

The C1 survival mediation result **reversed**. Before deduplication, adjusting for
steroid exposure attenuated the survival benefit but left it intact (M2 0·86
[0·77–0·96]), and the paper argued for a residual direct survival effect beyond GVHD
suppression. Under Set B, adjustment removes the benefit entirely (M2 0·95 [0·70–1·29],
on 24 of the 29 studies).

The Discussion and the Research in context panel have been rewritten to say what the Set
B numbers say — that the survival gain travels the GVHD–steroid pathway while the CMV
and bacteraemia costs travel a separate T-cell-depletion pathway. That is a real change
of scientific claim, not a wording change, and it is marked with `TODO` comments at both
sites in `index.qmd`. **Confirm it before submission.**

Two smaller consequences, both now addressed: C1 infection-related mortality includes
the null under Set B (1·02 [0·67–1·50]; the 1·19 [1·00–1·43] recorded here earlier was
an interim value superseded by the 2026-09-30 random-slope refit), and the Results
wording already reads "showed no excess". The three amendment-added secondary outcomes
(BK virus reactivation, infection-related mortality, relapse-related mortality) have
been formally GRADE-rated in appendix S11 under the same framework — LOW for BK virus
C1 and relapse-related mortality C1 (intervals exclude the null, low heterogeneity),
VERY LOW for the remainder — so the "very low certainty" claims in the abstract,
Research in context panel, and Discussion are scoped to the pre-specified outcomes.
The S11 GRADE profiles were reassessed against the deduplicated estimates on
2026-09-30.

### Figures

`Figure2_OS_forest_setB` and `Figure3a`/`Figure3b_CMV_..._setB` are regenerated from the
Set B datasets by the `forest-plots` notebook, because the originals in the analysis
repository were drawn from the pre-deduplication fits and would have contradicted table
2. They are plainer than the originals — no posterior density above the pooled row. To
get the polished styling back, re-run the repository's plotting code against
`03_models/set_b/` and drop the results into `figures/` under the same names.

Figure 1 (PRISMA) and figure 4 (BSI, IFI, BK) are untouched: none of those outcomes was
affected by deduplication.

Appendix S7 (MCMC diagnostics) and S8 (supplementary forest plots) are still the
pre-deduplication versions. A scope note at the head of `appendix.qmd` says so, and a
`TODO` there records what to regenerate.

## Requirements

- Quarto ≥ 1.4 (built with 1.10.18)
- R with `dplyr`, `tidyr`, `readr`, `stringr`, `ggplot2`, `knitr` — for the notebooks
- `PRISMA2020` for figure 1. It needs `DiagrammeRsvg` → `V8` → libv8, which Arch does
  not package. If `install.packages("V8")` fails at the configure step, use the
  package's own fallback, which needs no root:
  `Sys.setenv(DOWNLOAD_STATIC_LIBV8 = 1); install.packages("V8")`
- A LaTeX installation for the PDF output (`quarto install tinytex` if you have none)

The notebooks deliberately avoid `brms` and `metafor`: they read exported posterior
summaries rather than re-fitting the models, so the project renders in seconds on a
machine that has never installed Stan. Re-fitting lives in the analysis repository.
