#!/bin/sh
# Usage: ./fix-a11y.sh file.html
# Fixes tex4ht accessibility issue in-place:
#   Add role="presentation" to equation-layout tables (<table class='equation'>)
#   so screen readers don't announce them as data tables.
#
# Note: tex4ht does NOT emit theorem titles as <h6> (it uses inline spans),
# so the <h6> rewrite from latexml/fix-a11y.sh is unnecessary here.
set -e

if [ -z "$1" ]; then
  echo "Usage: $0 <file.html>" >&2
  exit 1
fi

tmpfile=$(mktemp)

awk '
  {
    # Match <table ...class="...equation..."...> in either single or double quotes.
    # Skip if role= is already present.
    # (No \b: BSD awk on macOS does not support word boundaries; the surrounding
    # context — class quote + the only equation-* class tex4ht emits — is enough.)
    if (match($0, /<table [^>]*class=['\''"][^'\''"]*equation/) && !match($0, /<table [^>]*role=/)) {
      sub(/<table /, "<table role=\"presentation\" ", $0)
    }
    print
  }
' "$1" > "$tmpfile" && mv "$tmpfile" "$1"
