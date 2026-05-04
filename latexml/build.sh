#!/bin/sh
# build.sh — Convert LaTeX to accessible HTML5 via LaTeXML
# Usage: ./build.sh <input.tex> [output.html]
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -z "$1" ]; then
  echo "Usage: $0 <input.tex> [output.html]" >&2
  exit 1
fi

input="$1"
output="${2:-${input%.tex}.html}"

echo ":: Converting $input → $output"

latexmlc \
  --pmml --cmml --mathtex --unicodemath --index \
  --css="$SCRIPT_DIR/latex-style.css" \
  "$input" --dest="$output"

echo ":: Applying accessibility fixes"
"$SCRIPT_DIR/fix-a11y.sh" "$output"

echo ":: Done → $output"
