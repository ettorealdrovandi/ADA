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
#
# See ./README.md (per-phase catalogue) and ./plan.md (design intent)
# for full documentation.

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
autofix=1
validate=0
compile_clean=1

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

# ── Env-line-break normalizer ───────────────────────────────────────
# Splits any line containing `\begin{X}` / `\end{X}` so each env token
# sits on its own line. Motivation: tagpdf's automatic text-unit
# paragraph hooks can miscount when multiple env begins/ends share a
# source line. Contents of verbatim-/picture-family envs are passed
# through unchanged (same skip-list as Phase 6a / validate_env_balance).
# Idempotent: re-running on an already-normalized file is a no-op.
normalize_env_lines() {
  local outdir="$1" do_rewrite="$2" files_changed=0
  local f base before after
  for f in "$outdir"/*.tex; do
    [ -f "$f" ] || continue
    base="$(basename "$f")"
    before="$(cksum < "$f")"
    awk '
      function name_of(s,    p) { p = index(s, "{"); return substr(s, p+1, length(s)-p-1) }
      function is_verb_env(env,    base) {
        base = env; sub(/\*$/, "", base)
        return base ~ /^(verbatim|Verbatim|BVerbatim|LVerbatim|SaveVerbatim|lstlisting|minted|alltt|comment|forest|tikzpicture)$/
      }
      function ws_only(s,    t) {
        t = s; sub(/^[[:space:]]+/, "", t); sub(/[[:space:]]+$/, "", t)
        return t == ""
      }
      BEGIN { in_verb = 0 }
      /^[[:space:]]*%/ { print; next }
      {
        line = $0
        emitted = 0
        while (length(line) > 0) {
          if (in_verb > 0) {
            pat = "\\\\end[[:space:]]*\\{" verb_env "\\*?\\}"
            if (match(line, pat)) {
              pre = substr(line, 1, RSTART - 1)
              tok = substr(line, RSTART, RLENGTH)
              # Drop whitespace-only "pre" remnants; emitting them
              # would create blank lines (= \par) inside an env body.
              if (pre != "" && !ws_only(pre)) { print pre; emitted = 1 }
              print tok; emitted = 1
              in_verb = 0
              line = substr(line, RSTART + RLENGTH)
            } else {
              # Inside verb env: pass through; suppress whitespace-only
              # mid-line artifacts that would introduce a \par.
              if (!ws_only(line)) { print line; emitted = 1 }
              line = ""
            }
            continue
          }
          bs = match(line, /\\begin[[:space:]]*\{[^}]+\}(\[[^]]*\])?/); bl = RLENGTH
          if (bs > 0) bm = substr(line, bs, bl)
          es = match(line, /\\end[[:space:]]*\{[^}]+\}/); el = RLENGTH
          if (es > 0) em = substr(line, es, el)
          if (bs == 0 && es == 0) {
            # No more tokens. If this is the entire input line (nothing
            # emitted yet) we preserve whitespace-only lines so a
            # paragraph-break-by-whitespace stays a \par. Otherwise the
            # remainder is a mid-line artifact and we drop it if blank.
            if (!emitted || !ws_only(line)) { print line; emitted = 1 }
            line = ""; continue
          }
          if (bs > 0 && (es == 0 || bs < es)) {
            pre = substr(line, 1, bs - 1)
            sub(/[[:space:]]+$/, "", pre)
            if (pre != "") { print pre; emitted = 1 }
            print bm; emitted = 1
            env = name_of(bm)
            if (is_verb_env(env)) { in_verb = 1; verb_env = env }
            line = substr(line, bs + bl)
          } else {
            pre = substr(line, 1, es - 1)
            sub(/[[:space:]]+$/, "", pre)
            if (pre != "") { print pre; emitted = 1 }
            print em; emitted = 1
            line = substr(line, es + el)
          }
        }
        # Preserve blank input lines as blank output lines.
        if (!emitted && $0 == "") print ""
      }
    ' "$f" > "$f.tmp"
    after="$(cksum < "$f.tmp")"
    if [ "$before" != "$after" ]; then
      if [ "$do_rewrite" = "1" ]; then
        mv "$f.tmp" "$f"
        files_changed=$((files_changed + 1))
        log_change "$base: normalized env line breaks"
      else
        rm -f "$f.tmp"
        log_warn "$base: would normalize env line breaks (skipped — --no-autofix)"
      fi
    else
      rm -f "$f.tmp"
    fi
  done
  if [ "$files_changed" -gt 0 ]; then
    log_info "normalized env line breaks in $files_changed file(s)"
  fi
}

# ── Env-balance validator ───────────────────────────────────────────
# Stack-based per-file scan that reports unbalanced \begin/\end pairs and
# (when do_fix=1) auto-fixes the two safe cases:
#   - unclosed env at EOF → append \end{X}
#   - orphan \end{X} alone on a line (only whitespace around it) → delete line
# Hard-fails on the two unsafe cases:
#   - orphan \end{X} embedded in a content line
#   - mismatched nesting (\end{got} when stack top was \begin{expected})
# Skips inside verbatim-/picture-family envs (same skip-list as Phase 6a).
validate_env_balance() {
  local outdir="$1" do_fix="$2" any_fail=0 fix_count=0 file_count=0

  local f base report
  for f in "$outdir"/*.tex; do
    [ -f "$f" ] || continue
    base="$(basename "$f")"

    report=$(awk '
      function name_of(match_str,    p) {
        # Extract env name from "\\begin <ws>* { name }" or
        # "\\end <ws>* { name }". LaTeX accepts whitespace between the
        # command and its argument; env names never contain { or }.
        p = index(match_str, "{")
        return substr(match_str, p+1, length(match_str) - p - 1)
      }
      function is_verb_env(env,    base) {
        # Verbatim-/picture-family envs whose CONTENTS must not be
        # parsed for nested \begin/\end. The same skip-list as Phase 6a.
        base = env
        sub(/\*$/, "", base)
        return base ~ /^(verbatim|Verbatim|BVerbatim|LVerbatim|SaveVerbatim|lstlisting|minted|alltt|comment|forest|tikzpicture)$/
      }
      BEGIN { top = 0; in_verb = 0 }
      {
        # If we are inside a verbatim-family env, only look for the
        # matching \end on this line; everything else is opaque content.
        if (in_verb > 0) {
          verb_env = stack_env[top]
          # Build a regex for "\end{verb_env}" with optional trailing *.
          pat = "\\\\end[[:space:]]*\\{" verb_env "\\*?\\}"
          if (match($0, pat)) {
            in_verb = 0
            top--
          }
          next
        }
        # Whole-line %-comment.
        if ($0 ~ /^[[:space:]]*%/) next
        # Strip inline %-comments (preserve literal \%).
        raw = $0
        gsub(/\\%/, "\001PCT\001", raw)
        sub(/%.*$/, "", raw)
        gsub(/\001PCT\001/, "\\%", raw)
        original = raw
        line = raw
        while (1) {
          bs = match(line, /\\begin[[:space:]]*\{[^}]+\}/); bl = RLENGTH
          if (bs > 0) bmatch = substr(line, bs, bl)
          es = match(line, /\\end[[:space:]]*\{[^}]+\}/);   el = RLENGTH
          if (es > 0) ematch = substr(line, es, el)
          if (bs == 0 && es == 0) break
          if (bs > 0 && (es == 0 || bs < es)) {
            env = name_of(bmatch)
            top++
            stack_env[top] = env
            stack_line[top] = NR
            if (is_verb_env(env)) {
              # Enter verbatim mode: ignore rest of line and following
              # lines until matching \end.
              in_verb = 1
              break
            }
            line = substr(line, bs+bl)
          } else {
            env = name_of(ematch)
            in_stack_at = 0
            for (k = top; k >= 1; k--) {
              if (stack_env[k] == env) { in_stack_at = k; break }
            }
            if (in_stack_at == 0) {
              trimmed = original
              gsub(/^[[:space:]]+|[[:space:]]+$/, "", trimmed)
              if (trimmed == "\\end{" env "}" || trimmed == "\\end {" env "}") {
                printf "FIX_DELETE_LINE:%d:%s\n", NR, env
              } else {
                printf "FAIL_INLINE_ORPHAN:%d:%s\n", NR, env
              }
            } else if (in_stack_at == top) {
              top--
            } else {
              for (k = top; k > in_stack_at; k--) {
                printf "FAIL_MISMATCH:%d:%s:%s:%d\n", NR, env, stack_env[k], stack_line[k]
              }
              top = in_stack_at - 1
            }
            line = substr(line, es+el)
          }
        }
      }
      END {
        for (i = top; i >= 1; i--) {
          printf "FIX_APPEND_END:%s:%d\n", stack_env[i], stack_line[i]
        }
      }
    ' "$f")

    [ -z "$report" ] && continue
    file_count=$((file_count + 1))

    log_warn "$base: imbalance detected"
    local kind a b c d
    while IFS=: read -r kind a b c d; do
      case "$kind" in
        FIX_APPEND_END)
          echo "      unclosed \\begin{$a} opened at line $b — will append \\end{$a}" >&2
          ;;
        FIX_DELETE_LINE)
          echo "      orphan \\end{$b} alone at line $a — will delete that line" >&2
          ;;
        FAIL_INLINE_ORPHAN)
          echo "      orphan \\end{$b} on content line $a — refusing to autofix (edit the source)" >&2
          ;;
        FAIL_MISMATCH)
          echo "      \\end{$b} at line $a does not close \\begin{$c} (opened at line $d) — would need an extra \\end{$c} first; refusing to autofix" >&2
          ;;
      esac
    done <<< "$report"

    if printf '%s\n' "$report" | grep -q '^FAIL_'; then
      any_fail=1
      continue
    fi

    if [ "$do_fix" != "1" ]; then
      # In --no-autofix mode, any imbalance — even one that would be
      # safe to auto-fix — must hard-fail. The point of the flag is to
      # surface problems for inspection without mutating the transformed
      # source.
      any_fail=1
      continue
    fi

    # Apply autofixes.
    local delete_lines appends
    delete_lines=$(printf '%s\n' "$report" | awk -F: '$1=="FIX_DELETE_LINE"{print $2}' | sort -rn)
    if [ -n "$delete_lines" ]; then
      local expr="" n
      for n in $delete_lines; do
        expr="$expr${n}d;"
      done
      local before_cksum after_cksum
      before_cksum="$(cksum < "$f")"
      sed -i '' "$expr" "$f"
      after_cksum="$(cksum < "$f")"
      if [ "$before_cksum" != "$after_cksum" ]; then
        log_change "$base: deleted $(printf '%s\n' "$delete_lines" | wc -l | tr -d ' ') orphan \\end{...} line(s)"
        fix_count=$((fix_count + 1))
      fi
    fi

    appends=$(printf '%s\n' "$report" | awk -F: '$1=="FIX_APPEND_END"{print $2}')
    if [ -n "$appends" ]; then
      local last_char
      last_char="$(tail -c 1 "$f" 2>/dev/null || true)"
      if [ -n "$last_char" ] && [ "$last_char" != $'\n' ]; then
        printf '\n' >> "$f"
      fi
      printf '%% auto-closed by build.sh Phase 12 (unclosed envs)\n' >> "$f"
      local env
      while IFS= read -r env; do
        [ -z "$env" ] && continue
        printf '\\end{%s}\n' "$env" >> "$f"
      done <<< "$appends"
      log_change "$base: appended $(printf '%s\n' "$appends" | wc -l | tr -d ' ') \\end{...} for unclosed env(s)"
      fix_count=$((fix_count + 1))
    fi
  done

  if [ "$file_count" -eq 0 ]; then
    log_info "all .tex files have balanced \\begin/\\end pairs"
  else
    log_info "scanned $file_count file(s) with imbalance; applied $fix_count autofix action(s)"
  fi

  [ "$any_fail" = "1" ] && return 1
  return 0
}

# ── Prose-on-prose env-nesting detector ─────────────────────────────
# Emit the per-corpus prose-family env list (pipe-delimited) by parsing
# every \newtheorem{X} / \newtheorem*{X} in the output dir. 'proof'
# (amsthm) is excluded because it has no counter and doesn't trigger
# the tagpdf para-hook bug — proof-in-example compiles cleanly.
_detect_prose_family() {
  local outdir="$1"
  grep -h -oE '\\newtheorem\*?\{[a-zA-Z]+\}' "$outdir"/*.tex 2>/dev/null \
    | sed -E 's/\\newtheorem\*?\{([a-zA-Z]+)\}/\1/' \
    | grep -v '^proof$' \
    | sort -u \
    | tr '\n' '|' \
    | sed 's/|$//'
}

# Scan one file for prose-on-prose nestings. Emits one record per violation:
#   UNWRAP:<inner_begin>:<inner_end>:<inner_env>:<outer_env>:<outer_begin>
#     for a \newtheorem-derived env nested inside another \newtheorem-derived env
#   SPLIT:<inner_begin>:<inner_end>:<inner_env>:<outer_env>:<outer_begin>:<outer_end>
#     for a `proof` env nested inside a \newtheorem-derived env
# `prose` = pipe-delimited \newtheorem-derived envs (UNWRAP set, excludes proof).
# `detect` = `prose` plus `proof` (SPLIT detection set).
# Skips inside verbatim-/picture-/code-family envs (same skip-list as Phase 6a / 12b,
# extended with bare `verbatim` and `python` for post-Phase-6j safety).
_scan_prose_nesting() {
  local file="$1" prose="$2" detect="$3"
  awk -v prose="$prose" -v detect="$detect" '
    function name_of(s,    p) { p = index(s, "{"); return substr(s, p+1, length(s)-p-1) }
    function is_verb_env(env,    b) {
      b = env; sub(/\*$/, "", b)
      return b ~ /^(verbatim|Verbatim|BVerbatim|LVerbatim|SaveVerbatim|lstlisting|minted|alltt|comment|forest|tikzpicture|python)$/
    }
    function strip_star(s,    t) { t = s; sub(/\*$/, "", t); return t }
    function any_prose_ancestor(    k) {
      # Search ancestors only (exclude the just-pushed top frame).
      # Returns the depth of the nearest \newtheorem-derived ancestor — proof
      # is NOT a valid outer (it has no counter and is a leaf-ish structure).
      for (k = top - 1; k >= 1; k--) {
        if (is_prose_unwrap[strip_star(stack_env[k])]) return k
      }
      return 0
    }
    function finalize_split_records_for(pop_id,    i) {
      # Outer just popped — fill in outer_end_NR for any SPLIT records
      # waiting on this outer instance.
      for (i = 1; i <= n_split; i++) {
        if (split_outer_pid[i] == pop_id && split_outer_end[i] == 0) {
          split_outer_end[i] = NR
        }
      }
    }
    BEGIN {
      split(prose,  arr_u, "|"); for (i in arr_u) is_prose_unwrap[arr_u[i]] = 1
      split(detect, arr_d, "|"); for (i in arr_d) is_prose_detect[arr_d[i]] = 1
      top = 0; in_verb = 0; push_seq = 0; n_split = 0
    }
    {
      if (in_verb > 0) {
        verb_env = stack_env[top]
        pat = "\\\\end[[:space:]]*\\{" verb_env "\\*?\\}"
        if (match($0, pat)) {
          finalize_split_records_for(stack_pid[top])
          in_verb = 0; top--
        }
        next
      }
      if ($0 ~ /^[[:space:]]*%/) next
      raw = $0
      gsub(/\\%/, "\001PCT\001", raw); sub(/%.*$/, "", raw); gsub(/\001PCT\001/, "\\%", raw)
      line = raw
      while (1) {
        bs = match(line, /\\begin[[:space:]]*\{[^}]+\}/); bl = RLENGTH
        if (bs > 0) bm = substr(line, bs, bl)
        es = match(line, /\\end[[:space:]]*\{[^}]+\}/); el = RLENGTH
        if (es > 0) em = substr(line, es, el)
        if (bs == 0 && es == 0) break
        if (bs > 0 && (es == 0 || bs < es)) {
          env = name_of(bm); base = strip_star(env)
          push_seq++
          top++
          stack_env[top]  = env
          stack_line[top] = NR
          stack_pid[top]  = push_seq
          stack_violation[top] = ""
          if (is_verb_env(env)) { in_verb = 1; break }
          if (is_prose_detect[base]) {
            anc = any_prose_ancestor()
            if (anc > 0) {
              if (base == "proof") {
                # SPLIT only when the immediate parent of the proof IS the
                # prose ancestor (no intermediate envs between). When other
                # envs sit between (e.g. example > itemize > proof), the
                # splice would corrupt the structure: emit a SKIP record for
                # diagnostic only; do not count as a fixable violation.
                if (anc == top - 1) {
                  stack_violation[top] = "split"
                  stack_outer[top]     = strip_star(stack_env[anc])
                  stack_outerline[top] = stack_line[anc]
                  stack_outer_pid[top] = stack_pid[anc]
                } else {
                  stack_violation[top] = "skip"
                  stack_outer[top]     = strip_star(stack_env[anc])
                  stack_outerline[top] = stack_line[anc]
                  # Capture the intermediate chain for the diagnostic.
                  chain = ""
                  for (j = anc + 1; j < top; j++) {
                    chain = chain (chain == "" ? "" : ">") strip_star(stack_env[j])
                  }
                  stack_skip_chain[top] = chain
                }
              } else {
                stack_violation[top] = "unwrap"
                stack_outer[top]     = strip_star(stack_env[anc])
                stack_outerline[top] = stack_line[anc]
                stack_outer_pid[top] = stack_pid[anc]
              }
            }
          }
          line = substr(line, bs + bl)
        } else {
          env = name_of(em)
          match_at = 0
          for (k = top; k >= 1; k--) {
            if (stack_env[k] == env || strip_star(stack_env[k]) == strip_star(env)) { match_at = k; break }
          }
          if (match_at > 0) {
            # Emit / record violations for everything we are popping.
            for (k = top; k >= match_at; k--) {
              if (stack_violation[k] == "unwrap") {
                printf "UNWRAP:%d:%d:%s:%s:%d\n", stack_line[k], NR, strip_star(stack_env[k]), stack_outer[k], stack_outerline[k]
              } else if (stack_violation[k] == "split") {
                n_split++
                split_inner_begin[n_split] = stack_line[k]
                split_inner_end[n_split]   = NR
                split_inner_env[n_split]   = strip_star(stack_env[k])
                split_outer_env[n_split]   = stack_outer[k]
                split_outer_begin[n_split] = stack_outerline[k]
                split_outer_pid[n_split]   = stack_outer_pid[k]
                split_outer_end[n_split]   = 0
              } else if (stack_violation[k] == "skip") {
                printf "SKIP:%d:%d:%s:%s:%d:%s\n", stack_line[k], NR, strip_star(stack_env[k]), stack_outer[k], stack_outerline[k], stack_skip_chain[k]
              }
              # Outer-frame pop: finalize any pending SPLIT records waiting on it.
              finalize_split_records_for(stack_pid[k])
            }
            top = match_at - 1
          }
          # orphan \end: ignored — Phase 12b owns that diagnostic
          line = substr(line, es + el)
        }
      }
    }
    END {
      for (i = 1; i <= n_split; i++) {
        # Skip records whose outer never closed (Phase 12b would catch it,
        # or it is genuinely malformed and not safe to splice).
        if (split_outer_end[i] == 0) continue
        printf "SPLIT:%d:%d:%s:%s:%d:%d\n",
               split_inner_begin[i], split_inner_end[i],
               split_inner_env[i], split_outer_env[i],
               split_outer_begin[i], split_outer_end[i]
      }
    }
  ' "$file"
}

# Returns "elide" if the lines strictly between inner_end and outer_end of
# `file` contain only whitespace, %-comments, and inline spacers (\vspace,
# \vskip, \medskip, \smallskip, \bigskip, \noindent, \par), so the trailing
# fragment after a SPLIT can be elided rather than reopened. Returns "reopen"
# otherwise.
_smart_elide_check() {
  local file="$1" inner_end="$2" outer_end="$3"
  local start=$((inner_end + 1)) stop=$((outer_end - 1))
  if [ "$start" -gt "$stop" ]; then echo "elide"; return; fi
  awk -v s="$start" -v e="$stop" '
    NR < s { next }
    NR > e { exit }
    {
      line = $0
      sub(/^[[:space:]]+/, "", line); sub(/[[:space:]]+$/, "", line)
      if (line == "") next
      if (line ~ /^%/) next
      if (line ~ /^\\(vspace|vskip|medskip|smallskip|bigskip|noindent|par)([^a-zA-Z]|$)/) next
      print "non-spacer"; exit
    }
  ' "$file" | grep -q 'non-spacer' && echo "reopen" || echo "elide"
}

# Returns the net brace depth across lines [start..stop] inclusive of `file`,
# stripped of escaped braces (\{, \}) and \\ line breaks. Used to detect
# proof-in-prose cases where the proof body is wrapped in a TeX group like
# {\textcolor{red}{...}}, in which case splicing \end{OUTER} before the
# proof would corrupt the brace nesting.
_brace_balance() {
  local file="$1" start="$2" stop="$3"
  if [ "$start" -gt "$stop" ]; then echo 0; return; fi
  awk -v s="$start" -v e="$stop" '
    NR < s { next }
    NR > e { exit }
    {
      line = $0
      # Strip %-line-comments first (but preserve \%).
      gsub(/\\%/, "\001PCT\001", line); sub(/%.*$/, "", line); gsub(/\001PCT\001/, "\\%", line)
      # Strip \\ (line-break) and \{ / \} (escaped braces).
      gsub(/\\\\/, "", line)
      gsub(/\\[{}]/, "", line)
      n = gsub(/\{/, "", line)
      m = gsub(/\}/, "", line)
      depth += n - m
    }
    END { print depth+0 }
  ' "$file"
}

# Splice a SPLIT record into the file. Mode is "elide" or "reopen".
#   elide:  delete original \end{OUTER} at outer_end_line; insert \end{OUTER}
#           immediately before inner_begin_line. Net line count: 0.
#   reopen: insert \begin{OUTER} immediately after inner_end_line; insert
#           \end{OUTER} immediately before inner_begin_line. Net line count: +2.
_apply_split() {
  local file="$1" inner_begin="$2" inner_end="$3" outer_env="$4" outer_end="$5" mode="$6"
  awk -v ib="$inner_begin" -v ie="$inner_end" -v oe="$outer_end" \
      -v outer="$outer_env" -v mode="$mode" '
    {
      if (mode == "elide" && NR == oe) { next }     # drop original \end{OUTER}
      if (NR == ib)                    { print "\\end{"  outer "}" }
      print
      if (mode == "reopen" && NR == ie){ print "\\begin{" outer "}" }
    }
  ' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
}

# Detects prose-on-prose env nestings — a proven trigger of the tagpdf
# "automatic begin and end text-unit para hooks differ" Emergency stop.
#
# Two fix strategies:
#   UNWRAP — \newtheorem-derived env nested inside another \newtheorem-derived env
#            (e.g. \begin{remark} inside \begin{example}). The inner env's
#            \begin{...} and matching \end{...} lines are deleted so the
#            inner content survives as plain prose inside the outer env.
#            Preserves outer numbering; inner semantic marker is lost.
#   SPLIT  — `proof` (amsthm) nested inside a \newtheorem-derived env. The
#            outer env is closed before the proof, the proof is hoisted to
#            top scope, and the outer is reopened after the proof (or, when
#            no meaningful content remains between \end{proof} and the
#            outer's \end{...}, the outer simply stays closed — "smart elision").
#            Preserves the `Proof.…∎` structure element.
#
# Uses the "any \newtheorem-derived ancestor on stack" rule so an
# example > tcolorbox > remark sandwich is caught too.
# Skips inside verbatim-/picture-family envs (Phase 6a / 12b skip-list,
# extended with bare `verbatim` and `python`).
#
# do_fix=1 (default): autofix loop. Each iteration: scan, apply ALL UNWRAPs
# in batch (safe — line-disjoint deletes), then apply ONE SPLIT per
# iteration (split splices can overlap when multiple SPLITs share an outer;
# applying one and re-scanning is the simplest correctness guarantee).
# Max 50 iterations — fails loudly if it can't converge.
# do_fix=0: hard-fail with a per-site diagnostic.
validate_prose_nesting() {
  local outdir="$1" do_fix="$2"
  local prose_family
  prose_family="$(_detect_prose_family "$outdir")"
  if [ -z "$prose_family" ]; then
    log_skip "no \\newtheorem-declared envs found — nothing to validate"
    return 0
  fi
  local detect_set="${prose_family}|proof"

  local iter=0 max_iter=50 any_fail=0
  local total_unwrapped=0 total_split=0
  local first_iter=1

  while [ "$iter" -lt "$max_iter" ]; do
    iter=$((iter + 1))
    local iter_violations=0 iter_unwrapped=0 iter_split_applied=0
    local f base report

    for f in "$outdir"/*.tex; do
      [ -f "$f" ] || continue
      base="$(basename "$f")"

      report="$(_scan_prose_nesting "$f" "$prose_family" "$detect_set")"
      [ -z "$report" ] && continue

      local nunwrap nsplit nskip
      nunwrap=$(printf '%s\n' "$report" | grep -c '^UNWRAP:' || true)
      nsplit=$(printf '%s\n' "$report" | grep -c '^SPLIT:' || true)
      nskip=$(printf '%s\n' "$report" | grep -c '^SKIP:' || true)
      # Count brace-unsafe SPLITs: they fall back to UNWRAP (delete the inner
      # \begin{proof} and \end{proof} lines) since splicing would corrupt
      # brace nesting. Line-disjoint deletes are always brace-safe. The cost:
      # the proof body becomes plain prose, losing the "Proof.…∎" structure
      # element — but compilation proceeds and the para-hook count balances.
      local nsplit_unsafe=0
      if [ "$nsplit" -gt 0 ]; then
        local _rec _kind2 _ib2 _ie2 _i2 _o2 _ob2 _oe2 _bL _bR
        while IFS= read -r _rec; do
          [ -z "$_rec" ] && continue
          IFS=: read -r _kind2 _ib2 _ie2 _i2 _o2 _ob2 _oe2 <<<"$_rec"
          _bL="$(_brace_balance "$f" "$((_ob2 + 1))" "$((_ib2 - 1))")"
          _bR="$(_brace_balance "$f" "$((_ie2 + 1))" "$((_oe2 - 1))")"
          [ "$_bL" != "0" ] || [ "$_bR" != "0" ] && nsplit_unsafe=$((nsplit_unsafe + 1))
        done <<< "$(printf '%s\n' "$report" | grep '^SPLIT:')"
      fi
      local nsplit_fixable=$((nsplit - nsplit_unsafe))
      iter_violations=$((iter_violations + nunwrap + nsplit))

      # First-iter diagnostic per file.
      if [ "$first_iter" = "1" ]; then
        local total_actionable=$((nunwrap + nsplit))
        if [ "$total_actionable" -gt 0 ]; then
          log_warn "$base: $total_actionable prose-on-prose nesting(s) detected ($nunwrap unwrap, $nsplit_fixable split, $nsplit_unsafe split→unwrap fallback)"
        fi
        if [ "$nskip" -gt 0 ]; then
          log_warn "$base: $nskip proof-in-prose nesting(s) with intermediate envs — not autofixable, left as-is"
        fi
        printf '%s\n' "$report" | while IFS= read -r rec; do
          case "$rec" in
            UNWRAP:*)
              local _b _e _inner _outer _ol
              IFS=: read -r _kind _b _e _inner _outer _ol <<<"$rec"
              echo "      $base:$_b  \\begin{$_inner} inside \\begin{$_outer} (outer opened at $_ol; \\end{$_inner} at line $_e) — would UNWRAP" >&2
              ;;
            SPLIT:*)
              local _ib _ie _inner _outer _ob _oe _mode _bL2 _bR2
              IFS=: read -r _kind _ib _ie _inner _outer _ob _oe <<<"$rec"
              _bL2="$(_brace_balance "$f" "$((_ob + 1))" "$((_ib - 1))")"
              _bR2="$(_brace_balance "$f" "$((_ie + 1))" "$((_oe - 1))")"
              if [ "$_bL2" != "0" ] || [ "$_bR2" != "0" ]; then
                echo "      $base:$_ib  \\begin{$_inner} inside \\begin{$_outer} — would UNWRAP (brace depth left=$_bL2 right=$_bR2; proof wrapped in a TeX group, SPLIT unsafe)" >&2
              else
                _mode="$(_smart_elide_check "$f" "$_ie" "$_oe")"
                echo "      $base:$_ib  \\begin{$_inner} inside \\begin{$_outer} (outer opens @ $_ob, closes @ $_oe; \\end{$_inner} @ $_ie) — would SPLIT ($_mode)" >&2
              fi
              ;;
            SKIP:*)
              local _b _e _inner _outer _ol _chain
              IFS=: read -r _kind _b _e _inner _outer _ol _chain <<<"$rec"
              echo "      $base:$_b  \\begin{$_inner} inside \\begin{$_outer} via [$_chain] — SKIP (intermediate envs would corrupt splice; usually compiles cleanly)" >&2
              ;;
          esac
        done
      fi

      if [ "$do_fix" != "1" ]; then
        any_fail=1
        continue
      fi

      # Collect deletion lines: all UNWRAPs + all brace-unsafe SPLITs
      # (fallback UNWRAP for SPLITs that cannot be safely spliced).
      # Line-disjoint deletes can all be batched in one sed call.
      local del_lines=""
      if [ "$nunwrap" -gt 0 ]; then
        del_lines+="$(printf '%s\n' "$report" | awk -F: '$1=="UNWRAP"{print $2; print $3}')"$'\n'
      fi
      if [ "$nsplit_unsafe" -gt 0 ]; then
        local _rec3 _kind3 _ib3 _ie3 _i3 _o3 _ob3 _oe3 _bL3 _bR3
        while IFS= read -r _rec3; do
          [ -z "$_rec3" ] && continue
          IFS=: read -r _kind3 _ib3 _ie3 _i3 _o3 _ob3 _oe3 <<<"$_rec3"
          _bL3="$(_brace_balance "$f" "$((_ob3 + 1))" "$((_ib3 - 1))")"
          _bR3="$(_brace_balance "$f" "$((_ie3 + 1))" "$((_oe3 - 1))")"
          if [ "$_bL3" != "0" ] || [ "$_bR3" != "0" ]; then
            del_lines+="${_ib3}"$'\n'"${_ie3}"$'\n'
          fi
        done <<< "$(printf '%s\n' "$report" | grep '^SPLIT:')"
      fi
      if [ -n "$(echo "$del_lines" | tr -d '[:space:]')" ]; then
        local expr="" n unique_lines
        unique_lines=$(printf '%s\n' "$del_lines" | grep -v '^$' | sort -rn | uniq)
        for n in $unique_lines; do expr="$expr${n}d;"; done
        local before_cksum after_cksum
        before_cksum="$(cksum < "$f")"
        sed -i '' "$expr" "$f"
        after_cksum="$(cksum < "$f")"
        if [ "$before_cksum" != "$after_cksum" ]; then
          local total_deleted=$((nunwrap + nsplit_unsafe))
          iter_unwrapped=$((iter_unwrapped + total_deleted))
          if [ "$nsplit_unsafe" -gt 0 ]; then
            log_change "$base: unwrapped $nunwrap nested prose env(s) + $nsplit_unsafe brace-unsafe proof env(s)"
          else
            log_change "$base: unwrapped $nunwrap nested prose env(s)"
          fi
        fi
        # When deletes change the file, re-scan in the next iteration before
        # touching SPLITs — line numbers have shifted.
        continue
      fi

      # No UNWRAPs (or unsafe-SPLIT fallbacks) in this file; apply at most
      # one (brace-safe) SPLIT per iteration (globally).
      if [ "$iter_split_applied" = "0" ] && [ "$nsplit_fixable" -gt 0 ]; then
        local rec _ib _ie _inner _outer _ob _oe _mode _balL _balR
        while IFS= read -r rec; do
          [ -z "$rec" ] && continue
          IFS=: read -r _kind _ib _ie _inner _outer _ob _oe <<<"$rec"
          _balL="$(_brace_balance "$f" "$((_ob + 1))" "$((_ib - 1))")"
          _balR="$(_brace_balance "$f" "$((_ie + 1))" "$((_oe - 1))")"
          [ "$_balL" != "0" ] || [ "$_balR" != "0" ] && continue
          _mode="$(_smart_elide_check "$f" "$_ie" "$_oe")"
          _apply_split "$f" "$_ib" "$_ie" "$_outer" "$_oe" "$_mode"
          log_change "$base: split \\begin{$_outer} around \\begin{$_inner} ($_mode mode)"
          iter_split_applied=1
          total_split=$((total_split + 1))
          break
        done <<< "$(printf '%s\n' "$report" | grep '^SPLIT:' | sort -t: -k2,2n)"
      fi
    done  # for f

    first_iter=0
    total_unwrapped=$((total_unwrapped + iter_unwrapped))

    if [ "$iter_violations" -eq 0 ]; then
      [ "$iter" = "1" ] && log_info "no prose-on-prose env nestings detected"
      break
    fi

    if [ "$do_fix" != "1" ]; then
      break
    fi

    if [ "$iter_unwrapped" -eq 0 ] && [ "$iter_split_applied" = "0" ]; then
      log_warn "violations reported but no fix could be applied — aborting loop"
      any_fail=1
      break
    fi
  done  # while iter

  if [ "$iter" -ge "$max_iter" ] && [ "$iter_violations" -gt 0 ]; then
    log_warn "reached max iterations ($max_iter) — nestings may persist"
    any_fail=1
  fi

  if [ "$total_unwrapped" -gt 0 ] || [ "$total_split" -gt 0 ]; then
    log_info "resolved $total_unwrapped unwrap + $total_split split nesting(s) over $iter iteration(s)"
  fi

  [ "$any_fail" = "1" ] && return 1
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
  --no-autofix         In Phase 12, report \begin/\end imbalances and
                       prose-on-prose env nestings but do not auto-close,
                       auto-delete, or auto-unwrap. Hard-fails on any
                       defect instead.
  --validate           Run Phase 14 (PDF/UA validation via pdfinfo and
                       verapdf). Off by default. Implicitly enabled by
                       --only=14.
  --dry-run            Run all transform phases, print a diff against
                       originals, then exit without compiling
  -h, --help           Show this help

Environment:
  INCLUDE_ONLY=a,b     Inject \includeonly{a,b} for selective compilation

Phases:
  1.  Setup (copy source tree; clean stale main PDF)
  2.  Strip sub-file standalone preambles
  3.  \input → \include
  4.  amsbook → book
  5.  Strip structural hacks
  6.  Legacy LaTeX fixes ($$, stray \\, align \\\\, \vfill\eject, geometry,
      tikz decoration shim, pythonhighlight → verbatim)
  7.  Clean preamble
  8.  Inject \DocumentMetadata
  9.  Inject unicode-math + font setup
  10. Math font commands (\mathbb → \symbb, etc.)
  11. Colorblind-friendly color scheme
  12. Normalize each \begin/\end onto its own line, validate balance, then
      detect prose-on-prose env nesting (auto-unwrap inner env on the copy;
      all three sub-steps suppressed and any defect hard-fails under
      --no-autofix)
  13. Compile (latexmk + lualatex-dev)
  14. PDF/UA validation (opt-in via --validate)
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
    --no-autofix)    autofix=0; shift ;;
    --validate)      validate=1; shift ;;
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

# --only=14 implies --validate (user explicitly asked for Phase 14).
if [ -n "$only_phases" ]; then
  case ",$only_phases," in
    *",14,"*) validate=1 ;;
  esac
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
  # Remove a stale main PDF (either copied from source or left over from a
  # prior run) so Phase 13's `[ ! -f "$pdf_out" ]` check can't be fooled.
  stale_pdf="$output_dir/${basename_tex%.tex}.pdf"
  if [ -f "$stale_pdf" ]; then
    rm -f "$stale_pdf"
    log_change "removed stale $(basename "$stale_pdf")"
  fi
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
    sed_inplace '/^[[:space:]]*\\begin{document}/d' "$texfile" "removed stray \\begin{document}"
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
  # interactive mode (Phase 13 runs latexmk without -interaction=nonstopmode).
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

  # 6j. Replace `pythonhighlight` with built-in `verbatim`. The pythonhighlight
  # package is built on `listings`, which the LaTeX3 tagging-project lists as
  # `currently-incompatible` (https://latex3.github.io/tagging-project/tagging-status/);
  # the resulting `\begin{python}...\end{python}` env triggers a tagpdf
  # "automatic begin and end text-unit para hooks differ" Emergency stop.
  # The built-in `\begin{verbatim}` is patched by tagpdf and works. Syntax
  # highlighting is lost — accepted cost for accessibility compliance.
  # Idempotent: triggered only when pythonhighlight is still present.
  if grep -lq 'pythonhighlight' "$output_dir"/*.tex 2>/dev/null; then
    sed_inplace '/^\\usepackage{pythonhighlight}/d' "$master" "removed \\usepackage{pythonhighlight}"
    for texfile in "$output_dir"/*.tex; do
      [ -f "$texfile" ] || continue
      sed_inplace 's/\\begin{python}\(\[[^]]*\]\)\{0,1\}\({[^}]*}\)\{0,1\}/\\begin{verbatim}/g' "$texfile" "\\begin{python} → \\begin{verbatim}"
      sed_inplace 's/\\end{python}/\\end{verbatim}/g' "$texfile" "\\end{python} → \\end{verbatim}"
    done
    log_warn "replaced pythonhighlight \\begin{python}...\\end{python} with \\begin{verbatim}...\\end{verbatim} (syntax highlighting dropped — tagpdf compat)"
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

# ── Phase 12: Validate \begin/\end balance ──────────────────────────
# Per-file scan that catches unbalanced env pairs the previous phases may
# have introduced (and ones the originals already had — e.g. an author
# left a proof unfinished). Auto-fixes the two safe cases and hard-fails
# on the unsafe ones. See validate_env_balance() above.
if phase_enabled 12; then
  log_phase 12 "Validate \\begin/\\end balance"
  # 12a: normalize line breaks so each \begin{X}/\end{X} sits on its
  # own line. Done first so 12b's diagnostics and 12c's line-based
  # deletion both operate on a canonical layout.
  normalize_env_lines "$output_dir" "$autofix"
  # 12b: stack-based balance check (auto-fix on safe cases).
  if ! validate_env_balance "$output_dir" "$autofix"; then
    if [ "$autofix" = "1" ]; then
      die "unsafe imbalance detected — fix the source (mismatched nesting or inline orphan \\end can't be auto-closed)"
    else
      die "imbalance detected and --no-autofix is set"
    fi
  fi
  # 12c: prose-on-prose env-nesting detector (autofix = unwrap inner env).
  # Addresses the tagpdf para-hook miscount triggered by, e.g.,
  # \begin{remark} inside \begin{example}.
  if ! validate_prose_nesting "$output_dir" "$autofix"; then
    if [ "$autofix" = "1" ]; then
      die "prose-on-prose env nesting persists after autofix — inspect log"
    else
      die "prose-on-prose env nesting detected and --no-autofix is set"
    fi
  fi
fi
[ "$stop_after_phase" = "12" ] && exit 0

# ── Phase 13: Compile ───────────────────────────────────────────────
# Emit a multi-line, visually distinct warning on any compile failure
# (latexmk non-zero exit OR missing PDF). The pipeline can't predict
# every partial-tagging-compat interaction, so the message points at
# the LaTeX3 tagging-status page and names representative partly-
# compatible packages rather than diagnosing a specific error class.
print_compile_warning() {
  local log_path="$1"
  local pdf_present="$2"   # 0|1
  local para_hook_hit="$3" # 0|1
  echo "" >&2
  echo "!! ─────────────────────────────────────────────────────────────────" >&2
  echo "!!  COMPILE WARNING — tagged PDF generation did not finish cleanly" >&2
  echo "!! ─────────────────────────────────────────────────────────────────" >&2
  echo "!!  See log: $log_path" >&2
  echo "!!" >&2
  echo "!!  Likely root cause: many widely-used LaTeX packages are only" >&2
  echo "!!  partly compatible with the LaTeX tagging infrastructure." >&2
  echo "!!  Frequent offenders include amsthm, tcolorbox, and fancyvrb" >&2
  echo "!!  — among others; we can't predict every interaction." >&2
  echo "!!  Up-to-date status:" >&2
  echo "!!    https://latex3.github.io/tagging-project/tagging-status/" >&2
  if [ "$para_hook_hit" = "1" ]; then
    echo "!!" >&2
    echo "!!  This log shows the tagpdf 'automatic begin and end text-unit" >&2
    echo "!!  para hooks differ' Emergency stop — a known amsthm-adjacent" >&2
    echo "!!  trigger that is whitespace- and adjacency-sensitive." >&2
  fi
  echo "!!" >&2
  echo "!!  What to try:" >&2
  echo "!!    1. Re-run build.sh. Some failures (notably the para-hook" >&2
  echo "!!       miscount above) disappear on a subsequent pass — much" >&2
  echo "!!       like latexmk re-runs until references converge." >&2
  if [ "$pdf_present" = "1" ]; then
    echo "!!    2. A PDF was nevertheless left in the output directory." >&2
    echo "!!       Downstream accessibility tools (e.g. Canvas Ally) will" >&2
    echo "!!       often still accept a partly-tagged PDF for partial" >&2
    echo "!!       credit — worth uploading even with this warning." >&2
  else
    echo "!!    2. No PDF was produced this run. If a subsequent retry" >&2
    echo "!!       leaves even a partial PDF behind, downstream tools" >&2
    echo "!!       (e.g. Canvas Ally) will often accept it for partial" >&2
    echo "!!       accessibility credit." >&2
  fi
  echo "!! ─────────────────────────────────────────────────────────────────" >&2
  echo "" >&2
}

if phase_enabled 13; then
  log_phase 13 "Compile"
  cd "$output_dir"
  log_info "running latexmk with lualatex-dev"
  set +e
  latexmk -lualatex -lualatex=lualatex-dev -synctex=1 "$basename_tex"
  latexmk_rc=$?
  set -e
  pdf_out="${basename_tex%.tex}.pdf"
  log_file="$output_dir/${basename_tex%.tex}.log"
  para_hook_hit=0
  if [ -f "$log_file" ] && \
     grep -q 'The number of automatic begin and end text-unit para hooks differ' "$log_file"; then
    para_hook_hit=1
  fi

  if [ "$latexmk_rc" -ne 0 ] || [ ! -f "$pdf_out" ]; then
    compile_clean=0
    if [ -f "$pdf_out" ]; then
      print_compile_warning "$log_file" 1 "$para_hook_hit"
      log_info "partial PDF retained: $output_dir/$pdf_out"
    else
      print_compile_warning "$log_file" 0 "$para_hook_hit"
      die "no PDF produced this run — retry recommended (see warning above)"
    fi
  else
    log_info "PDF written: $output_dir/$pdf_out"
  fi
fi
[ "$stop_after_phase" = "13" ] && exit 0

# ── Phase 14: PDF/UA validation ─────────────────────────────────────
# Lightweight conformance check. pdfinfo (from poppler-utils) reads the
# document metadata; verapdf (if installed) runs full UA-2 validation.
# Neither is a hard dependency. Opt-in via --validate (or --only=14).
if phase_enabled 14 && [ "$validate" = "1" ]; then
  log_phase 14 "PDF/UA validation"
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
if [ "$compile_clean" = "1" ]; then
  echo "✓ Done → $output_dir/${basename_tex%.tex}.pdf"
else
  echo "⚠ Done with warnings → $output_dir/${basename_tex%.tex}.pdf (partial)"
fi
