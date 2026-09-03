#!/usr/bin/env bash
# Build the supplementary appendix alongside the article.
#
# A Quarto manuscript project renders only its article and notebooks -- it ignores
# `project: render:` -- so the appendix has to be rendered by this post-render hook
# instead. It is a separate document by design: the journal wants the appendix as its
# own file, not as a tail section of the article.
#
# Outputs are moved into the project output directory so that everything a submission
# needs sits in one place.
set -euo pipefail

# The hook fires again when we call `quarto render` below; bail out on re-entry.
if [[ -n "${PTCY_RENDERING_APPENDIX:-}" ]]; then
  exit 0
fi
export PTCY_RENDERING_APPENDIX=1

# Only on a full project render. During `quarto preview` Quarto re-renders on every
# save, and rebuilding a 31-page PDF each time makes the preview unusable.
if [[ "${QUARTO_PROJECT_RENDER_ALL:-0}" != "1" ]]; then
  echo "[appendix] incremental render - skipping (use 'quarto render' for a full build)"
  exit 0
fi

cd "$(dirname "$0")/.."
OUT="${QUARTO_PROJECT_OUTPUT_DIR:-_manuscript}"
mkdir -p "$OUT"

for fmt in docx pdf; do
  echo "[appendix] rendering appendix.qmd -> lancet-haematology-$fmt"
  quarto render appendix.qmd --to "lancet-haematology-$fmt" --quiet
  mv -f "appendix.$fmt" "$OUT/appendix.$fmt"
  echo "[appendix] wrote $OUT/appendix.$fmt"
done
