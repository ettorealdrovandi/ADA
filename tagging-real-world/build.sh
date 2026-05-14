#!/bin/bash
# build.sh — Defensive build pipeline: real-world LaTeX → tagged PDF/UA-1 or PDF/UA-2 (default UA-2)
#
# Copies the input tree to an output directory and applies transformation
# phases on the COPIES so the originals are never modified. Compiles the
# result with lualatex-dev for full PDF/UA tagging support. The UA flavour
# is selectable via --ua=1|--ua=2 (default 2).
#
# Usage: ./build.sh [OPTIONS] <input.tex> [output-dir]
# See --help for options.
#
# Environment variables:
#   INCLUDE_ONLY  comma-separated list of subfile basenames for \includeonly
#                 (e.g. INCLUDE_ONLY=graph_intro,gr_connect ./build.sh ...)

set -eo pipefail

# ── Globals ─────────────────────────────────────────────────────────
script_name="$(basename "$0")"
current_phase=0
current_phase_name="(setup)"
dry_run=0
only_phases=""
skip_phases=""
stop_after_phase=99
ua_flavour="2"

# ── Logging / error helpers ─────────────────────────────────────────
log_phase()  { current_phase="$1"; current_phase_name="$2"; echo ""; echo "── Phase $1: $2 ──"; }
log_info()   { echo "  · $1"; }
log_change() { echo "  · $1"; }
log_skip()   { echo "  · skipped ($1)"; }
log_warn()   { echo "  ! $1" >&2; }
die()        { echo "" >&2; echo "✗ Phase $current_phase ($current_phase_name) failed: $1" >&2; exit 1; }

on_error() {
  local ec=$?
  echo "" >&2
  echo "✗ Phase $current_phase ($current_phase_name) aborted (exit $ec)" >&2
  exit $ec
}
trap on_error ERR

# ── Phase gating ────────────────────────────────────────────────────
phase_enabled() {
  local n="$1"
  if [ -n "$only_phases" ]; then
    case ",$only_phases," in
      *",$n,"*) ;;
      *) return 1 ;;
    esac
  fi
  if [ -n "$skip_phases" ]; then
    case ",$skip_phases," in
      *",$n,"*) return 1 ;;
    esac
  fi
  return 0
}

# Run a sed -i '' expression and announce the change if the file's
# checksum actually changed. Avoids noisy "applied X to Y" messages
# when the pattern matched nothing.
sed_inplace() {
  local expr="$1" file="$2" desc="$3"
  local before after
  before="$(cksum < "$file")"
  sed -i '' "$expr" "$file"
  after="$(cksum < "$file")"
  [ "$before" != "$after" ] && log_change "$(basename "$file"): $desc"
  return 0
}

# Same idea for an awk transform that writes back to the file.
awk_inplace() {
  local script="$1" file="$2" desc="$3"
  local before after
  before="$(cksum < "$file")"
  awk "$script" "$file" > "$file.tmp" && mv "$file.tmp" "$file"
  after="$(cksum < "$file")"
  [ "$before" != "$after" ] && log_change "$(basename "$file"): $desc"
  return 0
}

# ── Help ────────────────────────────────────────────────────────────
usage() {
  cat <<'EOF'
Usage: build.sh [OPTIONS] <input.tex> [output-dir]

Build a tagged PDF/UA (UA-2 by default, UA-1 with --ua=1) from a
real-world LaTeX source. The input tree is copied to output-dir
(default: <input_dir>/tagged_output) and defensive transformations
are applied on the copies. Originals are never modified.

Options:
  --ua=1|--ua=2        PDF/UA flavour to target (default: 2). UA-1 omits
                       the MathML-embedding tagging-setup line; both
                       flavours embed math alt-text via tagpdfsetup.
  --only=N[,N...]      Run only the listed phase numbers
  --skip=N[,N...]      Skip the listed phases
  --stop-after=N       Run through phase N and exit (no compile)
  --dry-run            Run all transform phases, print a diff against
                       originals, then exit without compiling
  -h, --help           Show this help

Environment:
  INCLUDE_ONLY=a,b     Inject \includeonly{a,b} for selective compilation

Phases:
  1.  Setup (copy source tree)
  2.  Strip sub-file standalone preambles
  3.  \input → \include
  4.  amsbook → book
  5.  Strip structural hacks
  6.  Legacy LaTeX fixes ($$, stray \\, align \\\\, \vfill\eject, geometry, tikz decoration shim)
  7.  Clean preamble
  8.  Inject \DocumentMetadata
  9.  Inject unicode-math + font setup
  10. Math font commands (\mathbb → \symbb, etc.)
  11. Colorblind-friendly color scheme
  12. Compile (latexmk + lualatex-dev)
  13. PDF/UA validation
EOF
}

# ── CLI parsing ─────────────────────────────────────────────────────
positional=()
while [ $# -gt 0 ]; do
  case "$1" in
    --ua=*)
      ua_flavour="${1#--ua=}"
      case "$ua_flavour" in
        1|2) ;;
        *) echo "Error: --ua must be 1 or 2 (got '$ua_flavour')" >&2; exit 2 ;;
      esac
      shift ;;
    --only=*)        only_phases="${1#--only=}"; shift ;;
    --skip=*)        skip_phases="${1#--skip=}"; shift ;;
    --stop-after=*)  stop_after_phase="${1#--stop-after=}"; shift ;;
    --dry-run)       dry_run=1; shift ;;
    -h|--help)       usage; exit 0 ;;
    --*)             echo "Unknown option: $1" >&2; usage; exit 2 ;;
    *)               positional+=("$1"); shift ;;
  esac
done
if [ ${#positional[@]} -gt 0 ]; then
  set -- "${positional[@]}"
else
  set --
fi

if [ $# -lt 1 ]; then
  usage
  exit 2
fi

input="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
input_dir="$(dirname "$input")"
basename_tex="$(basename "$input")"

if [ ! -f "$input" ]; then
  echo "Error: $input not found" >&2
  exit 1
fi

output_dir="${2:-$input_dir/tagged_output}"
mkdir -p "$output_dir"
master="$output_dir/$basename_tex"

# ── Derived UA flavour settings ─────────────────────────────────────
pdfstandard="ua-${ua_flavour}"
if [ "$ua_flavour" = "1" ]; then
  pdfversion="1.7"
else
  pdfversion="2.0"
fi
echo "  PDF/UA flavour: ${pdfstandard} (pdf ${pdfversion})"

# ── Phase 1: Setup ──────────────────────────────────────────────────
if phase_enabled 1; then
  log_phase 1 "Setup"
  log_info "copying source files to $output_dir"
  for ext in tex png jpg pdf svg PNG; do
    for f in "$input_dir"/*."$ext"; do
      [ -f "$f" ] && cp "$f" "$output_dir/"
    done
  done
fi
[ "$stop_after_phase" = "1" ] && exit 0

# ── Phase 2: Strip sub-file standalone preambles ────────────────────
# Sub-files wrap their preamble + \begin{document} in \begin{comment}...\end{comment}.
# Some files have %\begin{comment} (broken — preamble leaks). Drop everything
# from BOF through \end{comment}. Idempotent: re-running on a stripped file
# finds no \end{comment} and skips it.
if phase_enabled 2; then
  log_phase 2 "Strip sub-file standalone preambles"
  for texfile in "$output_dir"/*.tex; do
    [ "$texfile" = "$master" ] && continue
    [ -f "$texfile" ] || continue
    if grep -q '\\end{comment}' "$texfile"; then
      sed_inplace '1,/\\end{comment}/d' "$texfile" "stripped preamble block"
    fi
    sed_inplace '/^[[:space:]]*\\end{document}/d' "$texfile" "removed \\end{document}"
  done
fi
[ "$stop_after_phase" = "2" ] && exit 0

# ── Phase 3: \input → \include ──────────────────────────────────────
# \include supports \includeonly for selective compilation and inserts its
# own \clearpage, so we also strip redundant \vfill\eject immediately after.
if phase_enabled 3; then
  log_phase 3 "\\input → \\include"
  sed_inplace 's/\\input{\([^}]*\)\.tex}/\\include{\1}/g' "$master" "converted \\input to \\include"
  sed_inplace '/\\include{/{ n; /\\vfill\\eject/d; }' "$master" "removed \\vfill\\eject after \\include"

  if [ -n "${INCLUDE_ONLY:-}" ]; then
    log_info "limiting compilation to: $INCLUDE_ONLY"
    if ! grep -q '\\includeonly' "$master"; then
      sed -i '' "/^\\\\begin{document}/i\\
\\\\includeonly{${INCLUDE_ONLY}}\\
" "$master"
      log_change "$(basename "$master"): added \\includeonly"
    fi
  fi
fi
[ "$stop_after_phase" = "3" ] && exit 0

# ── Phase 4: amsbook → book ─────────────────────────────────────────
# amsbook's \@starttoc / \@tocline / \@tocwrite internals conflict with the
# tagging infrastructure's patches to \chapter*, \contentsline, etc.
if phase_enabled 4; then
  log_phase 4 "amsbook → book"
  if grep -q '{amsbook}' "$master"; then
    sed_inplace 's/\(\\documentclass\[.*\]\){amsbook}/\1{book}/' "$master" "amsbook → book (with options)"
    sed_inplace 's/\\documentclass{amsbook}/\\documentclass{book}/' "$master" "amsbook → book"
    if ! grep -q '\\usepackage{amsmath,mathtools,amsthm}' "$master"; then
      sed -i '' '/^\\documentclass.*{book}/a\
\\usepackage{amsmath,mathtools,amsthm}\
' "$master"
      log_change "$(basename "$master"): added amsmath/mathtools/amsthm (book doesn't autoload them)"
    fi
  else
    log_skip "no amsbook class found"
  fi
fi
[ "$stop_after_phase" = "4" ] && exit 0

# ── Phase 5: Strip structural hacks ─────────────────────────────────
if phase_enabled 5; then
  log_phase 5 "Strip structural hacks"
  for texfile in "$output_dir"/*.tex; do
    [ -f "$texfile" ] || continue
    sed_inplace '/\\@tocline/d' "$texfile" "removed \\@tocline redefinitions"
    sed_inplace '/\\usepackage{enumerate}/d' "$texfile" "removed enumerate package"
    sed_inplace 's/\\begin{enumerate}\[[^]]*\]/\\begin{enumerate}/g' "$texfile" "stripped enumerate optional args"
  done
fi
[ "$stop_after_phase" = "5" ] && exit 0

# ── Phase 6: Legacy LaTeX fixes ─────────────────────────────────────
# lualatex-dev exposes legacy patterns that pdflatex tolerated. We fix
# them on the copy so the originals never need editing. See README.md
# §"Legacy fixes" for the catalog.
if phase_enabled 6; then
  log_phase 6 "Legacy LaTeX fixes"

  for texfile in "$output_dir"/*.tex; do
    [ -f "$texfile" ] || continue

    # 6a. $$ ... $$ → \[ ... \] (plain-TeX display math, deprecated; broken
    # under tagging). Pair-toggle awk that tracks inline-math state so it
    # can distinguish display-math $$ from a close-then-open inline ($X$$Y$
    # typo). Skips inside verbatim-, code-, and picture-family envs (where
    # $$ may be a literal token rather than display math — e.g. forest's
    # [$$ ...] empty-node placeholder syntax) and inside LaTeX % line
    # comments. \X escape sequences are passed through opaquely.
    awk_inplace '
      BEGIN { in_verb = 0; in_math = 0; tog = 0 }
      /\\begin\{(verbatim|Verbatim|BVerbatim|LVerbatim|SaveVerbatim|lstlisting|minted|alltt|comment|forest|tikzpicture)\*?\}/ { in_verb++; print; next }
      /\\end\{(verbatim|Verbatim|BVerbatim|LVerbatim|SaveVerbatim|lstlisting|minted|alltt|comment|forest|tikzpicture)\*?\}/   { if (in_verb > 0) in_verb--; print; next }
      {
        if (in_verb > 0) { print; next }
        line = $0; out = ""; i = 1; L = length(line)
        while (i <= L) {
          c = substr(line, i, 1)
          if (c == "\\") {
            if (i+1 <= L) { out = out substr(line, i, 2); i += 2 }
            else          { out = out c; i += 1 }
            continue
          }
          if (c == "%") { out = out substr(line, i); i = L + 1; continue }
          if (c == "$") {
            if (i+1 <= L && substr(line, i+1, 1) == "$") {
              if (in_math) {
                out = out "$$"; i += 2
              } else {
                nxt = (i+2 > L) ? "" : substr(line, i+2, 1)
                if (nxt == "$") {
                  printf "  ! %s:%d: $$$ sequence near col %d — left unchanged\n", FILENAME, NR, i > "/dev/stderr"
                  out = out "$$$"; i += 3
                } else if (tog == 0) {
                  out = out "\\["; tog = 1; i += 2
                } else {
                  out = out "\\]"; tog = 0; i += 2
                }
              }
            } else {
              in_math = 1 - in_math
              out = out "$"; i += 1
            }
          } else {
            out = out c; i += 1
          }
        }
        print out
      }
      END {
        if (tog != 0) printf "  ! %s: unbalanced $$ at EOF — last opener left unmatched\n", FILENAME > "/dev/stderr"
      }
    ' "$texfile" '$$ → \[/\] (pair-toggle)'

    # 6b. \\\\ (double line break) inside align/align* → \\.
    # Empty lines inside math envs are invalid, but \\\\ produces an empty
    # row that recent kernels reject. Range-restricted sed.
    sed_inplace '/\\begin{align}/,/\\end{align}/s/\\\\\\\\/\\\\/g'     "$texfile" "collapsed \\\\\\\\ in align"
    sed_inplace '/\\begin{align\*}/,/\\end{align\*}/s/\\\\\\\\/\\\\/g' "$texfile" "collapsed \\\\\\\\ in align*"

    # 6c. Standalone \hfill, \hfill\\, \hfill\\\\ on their own line are
    # fragile spacing hacks (often used after a heading) that the tagging
    # infrastructure can't classify. Delete the line.
    sed_inplace '/^[[:space:]]*\\hfill\(\\\\\)\{0,2\}[[:space:]]*$/d' "$texfile" "removed standalone \\hfill[\\\\]"

    # 6d. Trailing \\ at end of a line, where the FOLLOWING line is one
    # of: blank, \item, \end{...}, \begin{...}, sectioning command. In
    # any of those positions the \\ has "no line to end" and newer LaTeX
    # raises a fatal error. Two-line lookahead via awk.
    awk_inplace '
      function next_is_structural(s) {
        return (s ~ /^[[:space:]]*$/) ||
               (s ~ /^[[:space:]]*\\item([^a-zA-Z]|$)/) ||
               (s ~ /^[[:space:]]*\\end\{/) ||
               (s ~ /^[[:space:]]*\\begin\{/) ||
               (s ~ /^[[:space:]]*\\(section|subsection|subsubsection|paragraph|subparagraph|chapter|part)\*?[\{\[]/)
      }
      NR == 1 { prev = $0; next }
      {
        if (prev ~ /\\\\[[:space:]]*$/ && next_is_structural($0)) {
          sub(/\\\\[[:space:]]*$/, "", prev)
        }
        print prev
        prev = $0
      }
      END { print prev }
    ' "$texfile" "stripped trailing \\\\ before structural break"

    # 6e. Trailing \\ at end of \item lines (legacy formatting habit).
    sed_inplace 's/^\([[:space:]]*\\item.*\)\\\\[[:space:]]*$/\1/' "$texfile" "stripped trailing \\\\ on \\item lines"

    # 6e2. Trailing \\ immediately after a display- or inline-math close,
    # i.e. \]\\ or \)\\. The line break has no semantic value here and
    # the same "no line here to end" error trips on it.
    sed_inplace 's/\\\]\\\\[[:space:]]*$/\\]/' "$texfile" "stripped \\\\ after \\]"
    sed_inplace 's/\\)\\\\[[:space:]]*$/\\)/'   "$texfile" "stripped \\\\ after \\)"

    # 6f. \vfill\eject as a standalone line → \clearpage (the
    # \include-adjacent case is already handled in phase 3).
    sed_inplace 's/^[[:space:]]*\\vfill\\eject[[:space:]]*$/\\clearpage/' "$texfile" "\\vfill\\eject → \\clearpage"

    # 6h. Wrap inline math inside section-level commands with
    # \texorpdfstring{$X$}{}. Without this, unicode-math symbols like
    # \mitOmega leak into the .aux file (TOC / PDF bookmarks) and
    # trigger "Improper alphabetic constant" cascades on the next
    # pass. The {} second arg drops the math from TOC/bookmarks but
    # preserves it in the typeset heading. Uses -E because the
    # alternation needs extended-regex syntax.
    before_cksum="$(cksum < "$texfile")"
    sed -E -i '' '/^[[:space:]]*\\(section|subsection|subsubsection|chapter|paragraph|subparagraph|part)/ s/\$([^$]+)\$/\\texorpdfstring{$\1$}{}/g' "$texfile"
    after_cksum="$(cksum < "$texfile")"
    [ "$before_cksum" != "$after_cksum" ] && log_change "$(basename "$texfile"): wrapped math in section heading with \\texorpdfstring{...}{}"
  done

  # 6g. Geometry consolidation — master only. Replace per-length manual
  # \setlength{...} with a single geometry-package call.
  has_setlengths=0
  for cmd in textwidth textheight topmargin oddsidemargin evensidemargin; do
    if grep -q "^\\\\setlength{\\\\$cmd}" "$master"; then
      has_setlengths=1
      sed -i '' "/^\\\\setlength{\\\\$cmd}/d" "$master"
      log_change "$(basename "$master"): removed \\setlength{\\$cmd}"
    fi
  done
  if [ "$has_setlengths" = "1" ] && ! grep -q '\\usepackage\[paper=letterpaper' "$master"; then
    sed -i '' '/^\\documentclass.*{book}/a\
\\usepackage[paper=letterpaper,total={6in,8.5in}]{geometry}\
' "$master"
    log_change "$(basename "$master"): added \\usepackage{geometry}"
  fi

  # 6i. Tikz /tikz/decoration shim — master only. Current pgf (3.1.11a,
  # shipped in TeX Live 2026) does NOT declare /tikz/decoration; only
  # /pgf/decoration is defined. Sources that use the well-known
  # shorthand `decoration={markings, mark=...}` as a tikzpicture option
  # therefore trigger a recoverable pgfkeys "I do not know the key
  # /tikz/decoration" error which becomes a fatal Emergency stop under
  # interactive mode (Phase 12 runs latexmk without -interaction=nonstopmode).
  # The shim re-declares /tikz/decoration as a forwarder to /pgf/decoration,
  # restoring the historical syntax without modifying source bodies.
  # Idempotent: marker comment "% defensive tikz decoration shim".
  if grep -q '^\\usepackage{tikz}' "$master" && \
     ! grep -q '% defensive tikz decoration shim' "$master"; then
    sed -i '' '/^\\usepackage{tikz}/a\
\\tikzset{decoration/.code={\\pgfkeys{/pgf/decoration={#1}}}} % defensive tikz decoration shim\
' "$master"
    log_change "$(basename "$master"): injected \\tikzset{decoration/.code=...} shim"
  fi
fi
[ "$stop_after_phase" = "6" ] && exit 0

# ── Phase 7: Clean preamble (master only) ───────────────────────────
if phase_enabled 7; then
  log_phase 7 "Clean preamble"
  sed_inplace '/^\\font\\sans=cmss10/d'                       "$master" "removed \\font\\sans=cmss10"
  sed_inplace '/^\\input xypic/d'                             "$master" "removed \\input xypic"
  sed_inplace '/^\\usepackage\[all\]{xy}/d'                   "$master" "removed \\usepackage[all]{xy}"
  sed_inplace 's/,xypic//g'                                   "$master" "removed xypic from package list"
  sed_inplace '/^\\usepackage{nopageno}/d'                    "$master" "removed nopageno"
  sed_inplace '/^\\usepackage\(\[mathscr\]\)\{0,1\}{eucal}/d' "$master" "removed eucal"
  sed_inplace 's/\\usepackage{ulem}/\\usepackage[normalem]{ulem}/' "$master" "added [normalem] to ulem"
  sed_inplace '/\\thispagestyle{empty}/d'                     "$master" "removed \\thispagestyle{empty}"

  # Dedupe graphicx (keep first occurrence)
  awk_inplace '
    /^\\usepackage\{graphicx\}/ { if (!seen) { seen=1; print; next } else next }
    { print }
  ' "$master" "deduped \\usepackage{graphicx}"

  # Dedupe xcolor
  awk_inplace '
    /^\\usepackage(\[.*\])?\{xcolor\}/ { if (!seen) { seen=1; print; next } else next }
    { print }
  ' "$master" "deduped \\usepackage{xcolor}"
fi
[ "$stop_after_phase" = "7" ] && exit 0

# ── Phase 8: Inject \DocumentMetadata ───────────────────────────────
# UA-2 (default) embeds MathML as Structure Element + Artifact Form via
# tagging-setup. UA-1 omits that line, matching tagging/examples/minimal-ua1/
# (which has the same line commented out). \tagpdfsetup{math/alt/use} is
# injected separately by Phase 9 for both flavours.
if phase_enabled 8; then
  log_phase 8 "Inject \\DocumentMetadata (PDF/${pdfstandard})"
  if ! grep -q '^\\DocumentMetadata' "$master"; then
    if [ "$ua_flavour" = "1" ]; then
      sed -i '' '/^\\documentclass/i\
\\DocumentMetadata{\
  tagging       = on,\
  pdfstandard   = ua-1,\
  pdfversion    = 1.7,\
  lang          = en,\
}\
' "$master"
    else
      sed -i '' '/^\\documentclass/i\
\\DocumentMetadata{\
  tagging       = on,\
  tagging-setup = {math/setup={mathml-SE,mathml-AF}, extra-modules={verbatim-mo,verbatim-af}},\
  pdfstandard   = ua-2,\
  pdfversion    = 2.0,\
  lang          = en,\
}\
' "$master"
    fi
    log_change "$(basename "$master"): added \\DocumentMetadata (${pdfstandard})"
  else
    log_skip "\\DocumentMetadata already present"
  fi
fi
[ "$stop_after_phase" = "8" ] && exit 0

# ── Phase 9: Inject unicode-math + font setup ───────────────────────
if phase_enabled 9; then
  log_phase 9 "Inject unicode-math + font setup"
  if ! grep -q '^\\usepackage{unicode-math}' "$master"; then
    sed -i '' '/^\\usepackage{amssymb/a\
\\usepackage{unicode-math}\
\\setmainfont{TeX Gyre Termes}\
\\setmathfont{texgyretermes-math.otf}\
\\tagpdfsetup{math/alt/use}\
' "$master"
    log_change "$(basename "$master"): added unicode-math + texgyretermes-math + tagpdfsetup"
  else
    log_skip "unicode-math already present"
  fi
fi
[ "$stop_after_phase" = "9" ] && exit 0

# ── Phase 10: Math font commands ────────────────────────────────────
# \mathbb / \mathcal / \mathfrak / \mathscr → \symbb / \symcal / \symfrak /
# \symscr. Required by unicode-math: the legacy \math* commands clash.
if phase_enabled 10; then
  log_phase 10 "Math font commands"
  for texfile in "$output_dir"/*.tex; do
    [ -f "$texfile" ] || continue
    sed_inplace 's/\\mathbb{/\\symbb{/g
                 s/\\mathcal{/\\symcal{/g
                 s/\\mathfrak{/\\symfrak{/g
                 s/\\mathscr{/\\symscr{/g' "$texfile" "\\math{bb,cal,frak,scr} → \\sym{...}"
  done
fi
[ "$stop_after_phase" = "10" ] && exit 0

# ── Phase 11: Colorblind-friendly colors ────────────────────────────
if phase_enabled 11; then
  log_phase 11 "Colorblind-friendly colors"
  if ! grep -q 'colorblind' "$master"; then
    sed -i '' '/^\\usepackage\[dvipsnames\]{xcolor}/a\
\\usepackage[OkabeIto,keep-defaults]{colorblind}\
' "$master"
    log_change "$(basename "$master"): added \\usepackage{colorblind}"
  else
    log_skip "colorblind already present"
  fi
  sed_inplace 's/\\definecolor{T}{rgb}{0,\.5,0}/\\colorlet{T}{OI5}/' "$master" "T (green) → OI5 (Okabe-Ito)"
  sed_inplace 's/\\definecolor{F}{rgb}{1,0,0}/\\colorlet{F}{OI6}/'   "$master" "F (red)   → OI6 (Okabe-Ito)"
fi
[ "$stop_after_phase" = "11" ] && exit 0

# ── Dry-run exit point ──────────────────────────────────────────────
if [ "$dry_run" = "1" ]; then
  echo ""
  echo "── Dry-run: diff against originals ──"
  diff -ru "$input_dir" "$output_dir" || true
  echo ""
  echo "(dry-run complete — latexmk not invoked)"
  exit 0
fi

# ── Phase 12: Compile ───────────────────────────────────────────────
if phase_enabled 12; then
  log_phase 12 "Compile"
  cd "$output_dir"
  log_info "running latexmk with lualatex-dev"
  latexmk -lualatex -lualatex=lualatex-dev -synctex=1 "$basename_tex" || true
  pdf_out="${basename_tex%.tex}.pdf"
  if [ ! -f "$pdf_out" ]; then
    die "PDF was not produced. Check $output_dir/${basename_tex%.tex}.log"
  fi
  log_info "PDF written: $output_dir/$pdf_out"
fi
[ "$stop_after_phase" = "12" ] && exit 0

# ── Phase 13: PDF/UA validation ─────────────────────────────────────
# Lightweight conformance check. pdfinfo (from poppler-utils) reads the
# document metadata; verapdf (if installed) runs full UA-2 validation.
# Neither is a hard dependency.
if phase_enabled 13; then
  log_phase 13 "PDF/UA validation"
  cd "$output_dir"
  pdf_out="${basename_tex%.tex}.pdf"
  ua_meta="UNVERIFIED"
  ua_vera="UNVERIFIED"

  if command -v pdfinfo >/dev/null 2>&1; then
    if pdfinfo -meta "$pdf_out" 2>/dev/null | grep -qi 'pdfuaid:part'; then
      ua_meta="PASS (metadata advertises PDF/UA)"
    elif pdfinfo "$pdf_out" 2>/dev/null | grep -qi 'pdf.ua'; then
      ua_meta="PASS (PDF/UA marker present)"
    else
      ua_meta="FAIL (no PDF/UA marker found)"
    fi
  else
    log_info "pdfinfo not installed — skipping metadata check"
  fi

  if command -v verapdf >/dev/null 2>&1; then
    if verapdf --flavour "ua${ua_flavour}" "$pdf_out" >/dev/null 2>&1; then
      ua_vera="PASS (ua${ua_flavour})"
    else
      ua_vera="FAIL (ua${ua_flavour} — see verapdf output)"
    fi
  fi

  log_info "metadata check: $ua_meta"
  log_info "verapdf check : $ua_vera"
fi

echo ""
echo "✓ Done → $output_dir/${basename_tex%.tex}.pdf"
