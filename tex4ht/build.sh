#!/bin/sh
# build.sh — Convert LaTeX to accessible HTML5 via tex4ht (make4ht)
# Usage: ./build.sh [-m mathjax|mathml] <input.tex> [output.html]
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Parse options ──
math_mode="mathml"

while getopts "m:" opt; do
  case "$opt" in
    m) math_mode="$OPTARG" ;;
    *) echo "Usage: $0 [-m mathjax|mathml] <input.tex> [output.html]" >&2
       exit 1 ;;
  esac
done
shift $((OPTIND - 1))

case "$math_mode" in
  mathjax|mathml) ;;
  *)
    echo "Error: unknown math mode '$math_mode' (use mathjax or mathml)" >&2
    exit 1 ;;
esac

# ── Validate input ──
if [ -z "$1" ]; then
  echo "Usage: $0 [-m mathjax|mathml] <input.tex> [output.html]" >&2
  exit 1
fi

input="$1"
if [ ! -f "$input" ]; then
  echo "Error: $input not found" >&2
  exit 1
fi

output="${2:-${input%.tex}.${math_mode}.html}"
output_dir="$(cd "$(dirname "$output")" 2>/dev/null && pwd || echo "$PWD")"

echo ":: Converting $input → $output (math: $math_mode)"

# ── Stage style.css in output_dir BEFORE make4ht runs ──
# config.cfg's \Configure{AddCss}{style.css} resolves the file by relative
# name during compilation; it must exist in the working directory.
if [ "$output_dir" != "$SCRIPT_DIR" ]; then
  cp "$SCRIPT_DIR/style.css" "$output_dir/style.css"
fi

# ── Run make4ht ──
make4ht \
  -c "$SCRIPT_DIR/config.cfg" \
  -f html5 \
  -d "$output_dir" \
  -s \
  "$input" \
  "$math_mode"

# ── Rename output if user specified a different name ──
basename_out="$(basename "${input%.tex}.html")"
if [ "$(basename "$output")" != "$basename_out" ]; then
  mv "$output_dir/$basename_out" "$output"
fi

echo ":: Applying accessibility fixes"
"$SCRIPT_DIR/fix-a11y.sh" "$output"

echo ":: Done → $output"
