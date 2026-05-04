#!/bin/sh
# Usage: ./fix-a11y.sh file.html
# Fixes LaTeXML accessibility issues in-place:
#   1. Converts <h6> theorem titles to <span> (heading hierarchy)
#   2. Adds role="presentation" to equation layout tables
set -e

if [ -z "$1" ]; then
  echo "Usage: $0 <file.html>" >&2
  exit 1
fi

tmpfile=$(mktemp)

awk '
  # Fix 1: <h6> theorem titles → <span>, only when class contains ltx_title_theorem
  {
    if (match($0, /<h6 [^>]*ltx_title_theorem/)) {
      sub(/<h6 /, "<span ", $0)
      in_theorem_h6++
    }
    # Only replace </h6> if we have an open theorem-title tag to close
    if (in_theorem_h6 > 0 && match($0, /<\/h6>/)) {
      sub(/<\/h6>/, "</span>", $0)
      in_theorem_h6--
    }
    # Fix 2: Add role="presentation" to equation layout tables (skip if already present)
    if (match($0, /<table [^>]*ltx_eqn_table/) && !match($0, /role="/)) {
      sub(/<table /, "<table role=\"presentation\" ", $0)
    }
    print
  }
' "$1" > "$tmpfile" && mv "$tmpfile" "$1"
