#!/usr/bin/env bash
# Build the two documents the project render cannot produce itself:
#
#   * the supplementary appendix -- a manuscript project renders only its article
#     and notebooks, and ignores `project: render:`. The appendix is a separate
#     document by design: the journal wants it as its own file.
#
#   * the typeset preview -- a project can carry only one pdf format, and that
#     slot belongs to the plain submission PDF. Rendering a second pdf format in
#     the same pass makes Quarto try to move both to _manuscript/index.pdf.
#
# Outputs are moved into the project output directory so everything sits together.
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

for fmt in docx pdf; do
  echo "[extras] rendering appendix.qmd -> lancet-haematology-$fmt"
  quarto render appendix.qmd --to "lancet-haematology-$fmt" --quiet
  mv -f "appendix.$fmt" "$OUT/appendix.$fmt"
  echo "[extras] wrote $OUT/appendix.$fmt"
done

# The typeset reading copy. Its own output-file keeps it clear of index.pdf.
echo "[extras] rendering index.qmd -> lancet-haematology-preview-pdf"
quarto render index.qmd --to lancet-haematology-preview-pdf --quiet
echo "[extras] wrote $OUT/index-preview.pdf"
