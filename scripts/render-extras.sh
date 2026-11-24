#!/usr/bin/env bash
# Build the two documents the project render cannot produce itself:
#
#   * the supplementary appendix -- a manuscript project renders only its article
#     and notebooks, and ignores `project: render:`. The appendix is a separate
#     document by design: the journal wants it as its own file.
#
#   # Outputs are moved into the project output directory so everything sits together.
set -euo pipefail

# The hook fires again when we call `quarto render` below; bail out on re-entry.
if [[ -n "${PTCY_RENDERING_EXTRAS:-}" ]]; then
  exit 0
fi
export PTCY_RENDERING_EXTRAS=1

# Only on a full project render. During `quarto preview` Quarto re-renders on every
# save, and rebuilding a 31-page PDF each time makes the preview unusable.
if [[ "${QUARTO_PROJECT_RENDER_ALL:-0}" != "1" ]]; then
  echo "[extras] incremental render - skipping (use 'quarto render' for a full build)"
  exit 0
fi

cd "$(dirname "$0")/.."
OUT="${QUARTO_PROJECT_OUTPUT_DIR:-_manuscript}"
mkdir -p "$OUT"

# appendix.qmd is registered as a manuscript notebook so it appears in the
# site's Notebooks section, and Quarto renders registered notebooks only to
# their HTML preview -- a direct `--to tct-*` render silently
# produces nothing. Render the submission copies from a staging copy outside
# the project instead.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp appendix.qmd references.bib appendix-s4-references.md "$STAGE"/
cp -r _extensions figures appendix-figures "$STAGE"/
# files pulled in with {{< include >}} (e.g. appendix-s4-references.md)
shopt -s nullglob
includes=(appendix-*.md)
shopt -u nullglob
(( ${#includes[@]} )) && cp "${includes[@]}" "$STAGE"/

for fmt in docx pdf; do
  echo "[extras] rendering appendix.qmd -> tct-$fmt"
  (cd "$STAGE" && quarto render appendix.qmd --to "tct-$fmt" --quiet)
  mv -f "$STAGE/appendix.$fmt" "$OUT/appendix.$fmt"
  echo "[extras] wrote $OUT/appendix.$fmt"
done

# Highlights: a separate editable file with "Highlights" in its name (TCT).
cp highlights.qmd "$STAGE"/
echo "[extras] rendering highlights.qmd -> tct-docx"
(cd "$STAGE" && quarto render highlights.qmd --to tct-docx --quiet)
mv -f "$STAGE/highlights.docx" "$OUT/Highlights.docx"
echo "[extras] wrote $OUT/Highlights.docx"

# (The Lancet typeset preview, index-preview.pdf, is not built for Transplantation
# and Cellular Therapy, which has no equivalent.)
