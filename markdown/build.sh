#!/bin/sh
# build.sh — Convert Markdown to accessible HTML5 via Pandoc
# Usage: ./build.sh [-m mathjax|mathml] <input.md> [output.html]
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Parse options ──
math_mode="mathml"

while getopts "m:" opt; do
  case "$opt" in
    m) math_mode="$OPTARG" ;;
    *) echo "Usage: $0 [-m mathjax|mathml] <input.md> [output.html]" >&2
       exit 1 ;;
  esac
done
shift $((OPTIND - 1))

case "$math_mode" in
  mathjax) math_flag="--mathjax" ;;
  mathml)  math_flag="--mathml"  ;;
  *)
    echo "Error: unknown math mode '$math_mode' (use mathjax or mathml)" >&2
    exit 1 ;;
esac

# ── Validate input ──
if [ -z "$1" ]; then
  echo "Usage: $0 [-m mathjax|mathml] <input.md> [output.html]" >&2
  exit 1
fi

input="$1"
if [ ! -f "$input" ]; then
  echo "Error: $input not found" >&2
  exit 1
fi

output="${2:-${input%.md}.${math_mode}.html}"

echo ":: Converting $input → $output (math: $math_mode)"

pandoc "$input" \
  -o "$output" \
  --standalone \
  $math_flag \
  --css=style.css

# ── Ensure style.css is next to the output ──
output_dir="$(cd "$(dirname "$output")" && pwd)"
if [ "$output_dir" != "$SCRIPT_DIR" ]; then
  cp "$SCRIPT_DIR/style.css" "$output_dir/style.css"
  echo ":: Copied style.css → $output_dir/"
fi

echo ":: Done → $output"
