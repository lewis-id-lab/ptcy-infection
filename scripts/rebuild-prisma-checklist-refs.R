# Rebuild the page and line references of the PRISMA 2020 checklist
# (appendix S14) from the built PDFs, so they can be refreshed whenever the
# article or appendix changes length.
#
# Inputs: the article PDF (continuous line numbers) and the appendix PDF.
# Set `s14_article_pdf` / `s14_appendix_pdf` before sourcing to use other
# files; the defaults are the project outputs in _manuscript/.
# The script rewrites only the location column of the S14 table and the page
# counts in the sentence above it. Editing the checklist can itself move
# appendix pages, so rebuild the appendix PDF and run the script again until
# `s14_changed` is FALSE.
# Run from project root: source("scripts/rebuild-prisma-checklist-refs.R")

library(dplyr)
library(purrr)
library(stringr)
library(tibble)

article_pdf <- if (exists("s14_article_pdf")) s14_article_pdf else "_manuscript/index.pdf"
appendix_pdf <- if (exists("s14_appendix_pdf")) s14_appendix_pdf else "_manuscript/appendix.pdf"

art_pages <- pdftools::pdf_text(article_pdf)
app_pages <- pdftools::pdf_text(appendix_pdf)

# Article: one row per printed line, with its page and margin line number
art <- imap(art_pages, \(txt, p) tibble(page = p, raw = str_split(txt, "\n")[[1]])) |>
  list_rbind() |>
  mutate(line_no = as.integer(str_match(raw, "^\\s*(\\d{1,4})\\s{2,}\\S")[, 2]),
         text = str_trim(str_remove(raw, "^\\s*\\d{1,4}\\s{2,}"))) |>
  filter(!is.na(line_no))

at <- function(pattern) {
  hit <- filter(art, str_detect(text, pattern))
  if (nrow(hit) == 0) stop("anchor not found in article PDF: ", pattern)
  hit[1, ]
}
pl <- function(pattern) { h <- at(pattern); sprintf("p. %d, line %d", h$page, h$line_no) }
pages_of <- function(pages, pattern) {
  p <- which(str_detect(pages, pattern))
  if (!length(p)) stop("pattern not found: ", pattern)
  range(p)
}
pp <- function(r) if (r[1] == r[2]) sprintf("p. %d", r[1]) else sprintf("pp. %d–%d", r[1], r[2])
# a location at the start of a table cell needs "p\." so it is not read as a list
lead <- function(x) str_replace(x, "^p\\. ", "p\\\\. ")

summary_start <- at("^Summary$")
summary_end <- filter(art, line_no == at("^Research in context")$line_no - 1)
objective_start <- at("We therefore performed a systematic review")
objective_end <- at("^Methods$")$line_no - 1

methods <- pl("^Search strategy and selection criteria")
stats <- pl("^Statistical analysis$")
data_sharing <- pl("^Data sharing$")
limitations <- pl("^Limitations$")

table1 <- pp(pages_of(art_pages, "Comparator arms \\(n=\\d+\\)|CMV R\\+, %"))
table2 <- pp(pages_of(art_pages, "95% PI\\s+GRADE"))
fig <- map_int(1:4, \(i) pages_of(art_pages, fixed(sprintf("Figure %d:", i)))[1])
figs_2_4 <- pp(c(fig[2], fig[4]))

# Section headings are matched with their titles: "S9. " alone also occurs in
# running text ("... reported in S9. The ...")
headings <- c(
  S1 = "S1\\. Search strategy", S2 = "S2\\. Studies excluded", S3 = "S3\\. Characteristics",
  S4 = "S4\\. References of included", S5 = "S5\\. Risk of bias", S6 = "S6\\. Model specification",
  S7 = "S7\\. MCMC", S8 = "S8\\. Forest plots", S9 = "S9\\. Sensitivity analyses",
  S10 = "S10\\. Publication bias", S11 = "S11\\. GRADE", S12 = "S12\\. Cohort overlap",
  S13 = "S13\\. PROSPERO", S14 = "S14\\. PRISMA", S15 = "S15\\. Software"
)
S <- map_int(headings, \(pat) {
  p <- which(str_detect(app_pages, pat))
  if (!length(p)) stop("appendix section not found: ", pat)
  p[1]
})
s5_range <- pp(c(S[["S5"]], max(which(str_detect(app_pages, "RoB 2 summary for the 14 randomised")))))

loc <- c(
  "1" = sprintf("p. 1, line %d (title page)", at("^Post-transplant cyclophosphamide as graft")$line_no),
  "2" = sprintf("p. %d, line %d – p. %d, line %d (Summary)", summary_start$page, summary_start$line_no,
                summary_end$page, summary_end$line_no),
  "3" = sprintf("%s (Introduction); %s (Research in context)", pl("^Introduction$"), pl("^Research in context")),
  "4" = sprintf("p. %d, lines %d–%d (\"We therefore performed…\"); appendix p. %d (S13, PROSPERO CRD420261372156)",
                objective_start$page, objective_start$line_no, objective_end, S[["S13"]]),
  "5" = sprintf("%s (Methods — Search strategy and selection criteria); appendix p. %d (S2)", methods, S[["S2"]]),
  "6" = sprintf("%s; appendix p. %d (S1: EMBASE, PubMed/MEDLINE, SCOPUS, inception–April 2026); p. %d (figure 1)",
                methods, S[["S1"]], fig[1]),
  "7" = sprintf("appendix p. %d (S1, complete search strings per database)", S[["S1"]]),
  "8" = sprintf("%s (Methods: two reviewers in Covidence); p. %d (figure 1)", methods, fig[1]),
  "9" = sprintf("%s (Methods: structured extraction template, AI-assisted extraction with manual verification)", methods),
  "10" = sprintf("%s (Methods — Outcomes); %s (Table 1); appendix p. %d (S3–S4); extraction database (supplementary data)",
                 pl("^Outcomes$"), table1, S[["S3"]]),
  "11" = sprintf("%s (Methods: ROBINS-I, RoB 2, two reviewers); appendix p. %d (S5)", methods, S[["S5"]]),
  "12" = sprintf("%s (Methods — Statistical analysis, odds ratios at fixed timepoints); appendix p. %d (S9, hazard-ratio sensitivity)",
                 stats, S[["S9"]]),
  "13a" = sprintf("%s; appendix p. %d (S12, per-outcome attrition)", methods, S[["S12"]]),
  "13b" = sprintf("%s; appendix p. %d (S6); analytic code (Data sharing, %s)", stats, S[["S6"]], data_sharing),
  "13c" = sprintf("%s (Table 2); %s (Figures 2–4); appendix p. %d (S8)", table2, figs_2_4, S[["S8"]]),
  "13d" = sprintf("%s (Bayesian random-effects binomial-logistic models); appendix p. %d (S6, specification, priors, MCMC)",
                  stats, S[["S6"]]),
  "13e" = sprintf("%s (Table 2, τ and 95%% prediction intervals); appendix p. %d (S7); appendix p. %d (S9)",
                  table2, S[["S7"]], S[["S9"]]),
  "13f" = sprintf("appendix p. %d (S9: fixed study intercepts, matched M1/M2 sets, donor-type, RCT-only, serostatus/letermovir, comparator backbone, outcome definitions, τ-prior)", S[["S9"]]),
  "14" = sprintf("appendix p. %d (S10, RoBMA)", S[["S10"]]),
  "15" = sprintf("%s (Methods: GRADE); appendix p. %d (S11)", stats, S[["S11"]]),
  "16a" = sprintf("%s (Results — Search results and study characteristics); p. %d (figure 1)",
                  pl("^Search results and study characteristics"), fig[1]),
  "16b" = sprintf("appendix p. %d (S2, full-text exclusions with reasons)", S[["S2"]]),
  "17" = sprintf("%s (Table 1); appendix p. %d (S3–S4)", table1, S[["S3"]]),
  "18" = sprintf("%s (Results — Risk of bias); appendix %s (S5; figures S5a–S5c)", pl("^Risk of bias$"), s5_range),
  "19" = sprintf("%s (Figures 2–4); appendix p. %d (S8: per-study odds ratios, events/totals, weights); supplementary data files",
                 figs_2_4, S[["S8"]]),
  "20a" = sprintf("%s (Table 2); %s (Comparison 1); %s (Comparison 2); %s (Comparison 3)", table2,
                  pl("^PTCy versus CNI plus MTX or MMF"), pl("^PTCy versus ATG$"), pl("^Different PTCy-based regimens$")),
  "20b" = sprintf("%s (Sensitivity analyses); appendix p. %d (S9)", pl("^Sensitivity analyses$"), S[["S9"]]),
  "20c" = sprintf("appendix p. %d (S9)", S[["S9"]]),
  "20d" = sprintf("appendix p. %d (S10)", S[["S10"]]),
  "21" = sprintf("appendix p. %d (S10)", S[["S10"]]),
  "22" = sprintf("%s (Certainty of evidence); %s (Table 2, GRADE column); appendix p. %d (S11; all five GRADE domains per outcome, with imprecision assessed against pre-specified clinically meaningful thresholds of OR 0·80 for benefit and 1·25 for harm)",
                 pl("^Certainty of evidence$"), table2, S[["S11"]]),
  "23a" = sprintf("%s (Discussion)", pl("^Discussion$")),
  "23b" = sprintf("%s (Limitations)", limitations),
  "23c" = sprintf("%s; appendix p. %d (S12, cohort deduplication and duplicate-entry removal)", limitations, S[["S12"]]),
  "23d" = sprintf("%s (concluding paragraph of the Discussion)", pl("^In conclusion, PTCy-based")),
  "24a" = sprintf("%s (Methods); appendix p. %d (S13, PROSPERO CRD420261372156)", methods, S[["S13"]]),
  "24b" = sprintf("appendix p. %d (S13, all amendments listed)", S[["S13"]]),
  "24c" = sprintf("PROSPERO CRD420261372156; %s (Data sharing)", data_sharing),
  "25" = sprintf("%s (Role of the funding source: none)", pl("^Role of the funding source")),
  "26" = sprintf("%s (Declaration of interests)", pl("^Declaration of interests")),
  "27" = sprintf("%s (Data sharing: extraction database and analytic datasets on GitHub; manuscript source and notebooks on GitHub Pages); appendix p. %d (S15, software)",
                 data_sharing, S[["S15"]])
)
loc <- map_chr(loc, lead)

appendix <- readLines("appendix.qmd")
before <- appendix
tbl <- seq(grep("^\\| Section and topic \\| Item ", appendix), grep("^: PRISMA 2020 checklist for the review", appendix))
m <- str_match(appendix[tbl], "^(\\| [^|]*\\| ([0-9]+[a-f]?) \\| [^|]*\\| )(.*)( \\|)$")
rows <- !is.na(m[, 3])
stopifnot(setequal(m[rows, 3], names(loc)), sum(rows) == length(loc))
appendix[tbl][rows] <- str_c(m[rows, 2], loc[m[rows, 3]], m[rows, 5])

i <- grep("the article PDF \\(\\d+ pages, continuous line numbering\\) and this appendix \\(\\d+ pages", appendix)
stopifnot(length(i) == 1)
appendix[i] <- appendix[i] |>
  str_replace("the article PDF \\(\\d+ pages", sprintf("the article PDF (%d pages", length(art_pages))) |>
  str_replace("this appendix \\(\\d+ pages", sprintf("this appendix (%d pages", length(app_pages)))

s14_changed <- !identical(before, appendix)
if (s14_changed) writeLines(appendix, "appendix.qmd")
message("S14 references ", if (s14_changed) "updated" else "already current",
        " (article ", length(art_pages), " pages, appendix ", length(app_pages), " pages)")
