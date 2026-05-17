# Defensive build pipeline for real-world LaTeX

A `build.sh` wrapper that turns messy, real-world LaTeX sources (course
notes, legacy manuscripts, multi-file books split via `\input`) into
PDF/UA-2 tagged PDFs — **without modifying the originals**. The script
copies the input tree to an output directory, applies a sequence of
defensive transformations on the copies, and compiles with
`lualatex-dev`.

The companion `tagging/` directory holds curated examples that already
compile cleanly. This directory is for the other case: documents that
were written for `pdflatex` years ago, never imagined a tagging
infrastructure, and need preprocessing before they can be made
accessible.

## When to use this vs `tagging/`

| You are starting from… | Use… |
|---|---|
| A new document, written with accessibility in mind | [`tagging/`](../tagging/) — invoke `lualatex-dev` (or `latexmk`) directly. |
| A document that already compiles with `lualatex-dev` and just needs `\DocumentMetadata` added | [`tagging/`](../tagging/) — adopt the minimal pattern shown there. |
| A real-world legacy source: `amsbook`, `\input`-based subfiles, `xypic`, plain-TeX `$$...$$`, manual `\setlength` for margins, `\vfill\eject` between sections, etc. | **This pipeline** — `./build.sh path/to/main.tex`. |

## Examples

This directory deliberately ships **`build.sh` + documentation only**.
Real test corpora live locally under `examples/` and are gitignored —
the published artifact is the pipeline itself. Bring your own input:

```sh
./build.sh path/to/your/manuscript.tex
```

## How to compile

The default workflow:

```sh
./build.sh <input.tex> [output-dir]
# Default output-dir: <input_dir>/tagged_output
```

Selective subfile compilation via `\includeonly`:

```sh
INCLUDE_ONLY=chapter1,chapter2 ./build.sh main.tex
```

### CLI flags

| Flag | Purpose |
|---|---|
| `--ua=1` \| `--ua=2` | PDF/UA flavour to target. **Default: 2.** UA-1 emits a shorter `\DocumentMetadata` block without the MathML-embedding `tagging-setup` line — matching the canonical [`tagging/examples/minimal-ua1/`](../tagging/examples/minimal-ua1/) preamble. Both flavours still embed math alt-text via `\tagpdfsetup{math/alt/use}` (Phase 9). |
| `--only=N[,N…]` | Run only the listed phase numbers (see phase list below). |
| `--skip=N[,N…]` | Run everything except the listed phases. |
| `--stop-after=N` | Run through phase N and exit (no compile). Useful for debugging which phase introduced a problem. |
| `--no-autofix` | In Phase 12, skip the env-line-break normalization, the balance auto-fix, **and** the prose-on-prose nesting auto-unwrap. Phase 12 still detects each kind of defect but does not modify the transformed copy, and hard-fails on any defect. Useful for inspecting whether a source has structural source bugs. |
| `--validate` | Run Phase 14 (PDF/UA validation via `pdfinfo` + `verapdf`). **Off by default** — the validation tools are not needed for normal builds. Implicitly enabled by `--only=14`. |
| `--dry-run` | Run all transformation phases, then print a `diff -ru` against the originals and exit. `latexmk` is not invoked. |
| `-h`, `--help` | Show built-in help. |

## Phases

The pipeline is intentionally a flat list of 14 numbered phases. Each
phase logs what it touched; phases that mutate state are
**idempotent** — re-running on a partially-built output directory is
safe.

| # | Phase | What it does |
|---|---|---|
| 1 | Setup | Copies `*.tex`, `*.png`, `*.jpg`, `*.pdf`, `*.svg`, `*.PNG` from the input directory to the output directory and **removes any stale main PDF** (left over from a prior run or copied from the source dir) so Phase 13's success check can't be fooled. Originals are never touched after this. |
| 2 | Strip sub-file standalone preambles | Sub-files often wrap their standalone preamble + `\begin{document}` in `\begin{comment}…\end{comment}` (or, broken, `%\begin{comment}…\end{comment}`). The script deletes everything from BOF through `\end{comment}` and removes any stray `\begin{document}` / `\end{document}` lines that may still appear in subfiles. |
| 3 | `\input` → `\include` | Enables `\includeonly` for selective compilation; injects `\includeonly{…}` if `INCLUDE_ONLY` is set; strips redundant `\vfill\eject` immediately after each `\include`. |
| 4 | `amsbook` → `book` | `amsbook`'s `\@starttoc` / `\@tocline` / `\@tocwrite` internals clash with the tagging infrastructure's patches to `\chapter*`, `\contentsline`, etc. Adds `\usepackage{amsmath,mathtools,amsthm}` (which `book` doesn't autoload). |
| 5 | Strip structural hacks | Removes `\@tocline` redefinitions of `\l@section` etc.; removes the `enumerate` package and strips optional args from `\begin{enumerate}[…]` (the tagging block module rejects them as unknown keys). |
| 6 | **Legacy LaTeX fixes** | Catalog below. |
| 7 | Clean preamble | Removes `\font\sans=cmss10`, `\input xypic`, `\usepackage[all]{xy}`, comma-listed `,xypic`, `nopageno`, `eucal`, `\thispagestyle{empty}`; dedupes `graphicx` and `xcolor`; adds `[normalem]` to `ulem`. |
| 8 | Inject `\DocumentMetadata` | UA-2 by default (version 2.0, MathML embedded as Structure Element + Artifact Form, `lang=en`). Pass `--ua=1` to emit the UA-1 block instead (version 1.7, no MathML-embedding `tagging-setup` line). Skipped if `\DocumentMetadata` is already present. |
| 9 | Inject `unicode-math` + font setup | `\usepackage{unicode-math}`, TeX Gyre Termes / `texgyretermes-math.otf`, `\tagpdfsetup{math/alt/use}`. Skipped if already present. |
| 10 | Math font commands | `\mathbb` → `\symbb`, `\mathcal` → `\symcal`, `\mathfrak` → `\symfrak`, `\mathscr` → `\symscr`. Required because `unicode-math` clashes with the legacy `\math*` commands. |
| 11 | Colorblind-friendly colors | Adds `\usepackage[OkabeIto,keep-defaults]{colorblind}` after `xcolor`; remaps the conventional `T` (green) and `F` (red) colors to Okabe-Ito `OI5` / `OI6`. |
| 12 | **Normalize env line breaks + validate balance + detect prose-on-prose nesting** | Three sub-steps. **12a (normalize)**: rewrites each `.tex` so every `\begin{X}` and `\end{X}` sits on its own line; mid-line whitespace remnants that would become a `\par` are suppressed; verbatim-/picture-family env bodies (`verbatim`, `lstlisting`, `forest`, `tikzpicture`, …) are passed through unchanged. Idempotent. The canonical layout makes 12b's diagnostics easier to read and is a prerequisite for 12c's line-based splice. **12b (validate)**: stack-based per-file scan that auto-fixes the two safe cases (unclosed env at EOF → append `\end{X}`; orphan `\end{X}` alone on a line → delete the line) and hard-fails on the two unsafe ones (inline-content orphan; genuine mismatched nesting). **12c (prose nesting)**: detects a prose-family env nested inside another `\newtheorem`-derived env — a proven trigger of the tagpdf *"automatic begin and end text-unit para hooks differ"* error. The detection-only set comprises every env declared via `\newtheorem{X}` / `\newtheorem*{X}` in the corpus, plus `proof` (amsthm). The outer-ancestor lookup uses only `\newtheorem`-derived envs (since `proof` is leaf-ish and has no counter). The "any prose ancestor on stack" rule catches sandwiches like `example > tcolorbox > remark`. Two autofix strategies, picked by inner env type: **UNWRAP** (inner = `\newtheorem`-derived) deletes the inner's `\begin{...}` and matching `\end{...}` lines so the content survives as plain prose inside the outer; outer numbering preserved, inner semantic marker lost. **SPLIT** (inner = `proof`) closes the outer before the inner `\begin{proof}`, hoists the proof to top scope, and either reopens the outer after `\end{proof}` (reopen mode) or leaves the outer closed and elides the original `\end{OUTER}` (elide mode — chosen when the lines between `\end{proof}` and the original `\end{OUTER}` are only whitespace, %-comments, or spacers like `\vspace`/`\vskip`/`\medskip`/`\smallskip`/`\bigskip`/`\noindent`/`\par`). The split preserves the `Proof.…∎` formatting and the `Proof` structure element. Loops scan-and-fix (max 50 iterations) — UNWRAPs apply in batch per iteration (line-disjoint deletes are safe); at most one SPLIT applies per iteration (splice overlaps when multiple proofs share an outer are avoided by re-scanning after each splice). `--no-autofix` suppresses all three sub-steps and hard-fails on any defect, printing the chosen mode (UNWRAP / SPLIT-elide / SPLIT-reopen) for each violation. |
| 13 | Compile | `latexmk -lualatex -lualatex=lualatex-dev -synctex=1`. Interactive mode (no `-interaction=nonstopmode`) so real errors stop the build rather than scrolling past silently. **On any compile failure** (latexmk non-zero exit, or missing PDF), prints a visually distinct multi-line warning that points at the LaTeX3 [tagging-status page](https://latex3.github.io/tagging-project/tagging-status/), names a few representative partly-compatible packages (`amsthm`, `tcolorbox`, `fancyvrb`), and recommends re-running — some failures, notably the `tagpdf` para-hook miscount, are whitespace- and adjacency-sensitive and disappear on a subsequent pass. If a partial PDF is left in the output dir, the warning notes that downstream tools (e.g. Canvas Ally) will often still accept it for *partial* accessibility credit. When the log contains the para-hook signature, an extra line surfaces that breadcrumb. |
| 14 | PDF/UA validation (**opt-in** via `--validate`) | Light conformance check: reads PDF metadata via `pdfinfo` (if installed) and optionally runs `verapdf --flavour ua1` or `--flavour ua2` (matching the requested build). Neither tool is a hard dependency. Off by default to keep ordinary builds tool-free; `--only=14` implies `--validate`. |

### Phase 6 — Legacy LaTeX fixes (catalog)

The transforms below auto-patch patterns that `pdflatex` tolerated but
`lualatex-dev` + tagging do not. Every transform runs on the **copies**
in the output directory; originals are never touched.

| Sub-step | Pattern | Replacement | Notes |
|---|---|---|---|
| 6a | `$$ … $$` (plain-TeX display math, deprecated) | `\[ … \]` | Pair-toggle awk that tracks `$…$` inline-math state, so a typo `$X$$Y$` (close-then-open inline) is **left unchanged** rather than mis-converted. Skips inside verbatim-, code-, and picture-family envs (`verbatim`, `Verbatim`, `BVerbatim`, `LVerbatim`, `SaveVerbatim`, `lstlisting`, `minted`, `alltt`, `comment`, `forest`, `tikzpicture` — and their starred variants) and after `%` line comments. The `forest`/`tikzpicture` skips matter because in those envs `$$` can be a literal token rather than display math (e.g. forest's `[$$ ...]` empty-node placeholder, observed in a binary-trees source); rewriting it shreds the bracket structure. Warns on unbalanced `$$` and `$$$` sequences. |
| 6b | `\\\\` inside `align` / `align*` (double line break = empty math row, rejected by recent kernels) | `\\` | Range-restricted sed; runs only between `\begin{align}` / `\end{align}` markers. |
| 6c | Standalone `\hfill`, `\hfill\\`, `\hfill\\\\` on their own line | Line deleted | Fragile spacing hacks (typically after a `\subsection{}` heading) that tagging can't classify. |
| 6d | Trailing `\\` at end of a line whose **following** line is blank, or starts with `\item` / `\end{…}` / `\begin{…}` / `\section` / `\subsection` / `\subsubsection` / `\chapter` / `\paragraph` / `\subparagraph` / `\part` | `\\` removed | A no-op line break in that position; newer LaTeX raises a fatal *"there's no line here to end"* error. Two-line awk lookahead. |
| 6e | `\\` at end of an `\item` line | `\\` removed | Pure legacy formatting habit. |
| 6e2 | `\]\\` or `\)\\` at end of a line (line break immediately after a math-mode close) | `\]` / `\)` | Same *"no line here to end"* class of error. |
| 6f | `\vfill\eject` on its own line | `\clearpage` | The `\include`-adjacent case is already handled by Phase 3. |
| 6g | Master preamble: `\setlength{\textwidth\|\textheight\|topmargin\|oddsidemargin\|evensidemargin}{…}` | Deleted; replaced by a single `\usepackage[paper=letterpaper,total={6in,8.5in}]{geometry}` | Inserted only once (idempotent). |
| 6h | Inline math `$X$` **inside** a section-level command (`\section{…}`, `\subsection{…}`, …, `\part{…}`) | `\texorpdfstring{$X$}{}` | Without this wrapper, `unicode-math` symbols like `\mitOmega` leak into the `.aux` file (TOC / PDF bookmarks) and trigger an *"improper alphabetic constant"* cascade on the next pass. The empty second arg drops the math from TOC / bookmarks but preserves it in the typeset heading. |
| 6i | Master preamble: `\usepackage{tikz}` | `\tikzset{decoration/.code={\pgfkeys{/pgf/decoration={#1}}}}` injected immediately after (marker comment `% defensive tikz decoration shim`) | Current pgf (3.1.11a, TeX Live 2026) declares only `/pgf/decoration`, not `/tikz/decoration`. Legacy sources using the historical `decoration={markings, mark=…}` shorthand as a tikzpicture option trigger a recoverable pgfkeys "I do not know the key '/tikz/decoration'" error — under interactive mode (no `-interaction=nonstopmode`) this becomes a fatal *Emergency stop*. The shim re-declares `/tikz/decoration` as a forwarder to `/pgf/decoration`, restoring the syntax without editing source bodies. Idempotent via the marker. |
| 6j | `\usepackage{pythonhighlight}` + `\begin{python}…\end{python}` | Package line deleted; `\begin{python}` → `\begin{verbatim}`, `\end{python}` → `\end{verbatim}` (drops optional `[…]` / `{…}` args) | `pythonhighlight` is built on `listings`, which the [LaTeX3 tagging project](https://latex3.github.io/tagging-project/tagging-status/) lists as `currently-incompatible`. Compiling a source with `\begin{python}…\end{python}` produces a fatal tagpdf *"automatic begin and end text-unit para hooks differ"* Emergency stop. Replacement is plain `\begin{verbatim}` — built into LaTeX core and explicitly handled by tagpdf. Syntax highlighting is lost; accessibility wins. Only runs when `pythonhighlight` is actually used (corpus-conditional). |

### Patterns intentionally **not** auto-fixed

- `$X$$Y$` adjacency (a typo for, e.g., `$X\implies Y$`). Detectable
  but ambiguous in isolation; left alone and the case is preserved by
  the inline-math-aware pair toggle in 6a.
- Section-heading reshuffles between master and subfile. Both
  arrangements compile fine; touching them risks duplicating or
  losing headings.

## Originals are never modified

Every phase operates on copies inside `output-dir` (default
`<input_dir>/tagged_output/`). The input directory is read-only as far
as `build.sh` is concerned. To inspect what each phase did:

```sh
./build.sh --dry-run my.tex            # show full diff vs. originals, no compile
./build.sh --stop-after=6 my.tex out/  # apply phases 1–6, leave the partially-transformed copy
diff -ru my-input-dir/ out/            # then diff by hand
```

## Prerequisites

- A recent **TeX Live** with the development LuaLaTeX (`lualatex-dev`).
- `latexmk`.
- The `tagpdf` package and the LaTeX team's `latex-lab` modules
  (bundled with current TeX Live).
- `unicode-math` and `TeX Gyre Termes Math` (also bundled).
- Optional, only used in Phase 14 (which is opt-in via `--validate`):
  `pdfinfo` (from poppler-utils) and [`verapdf`](https://verapdf.org/)
  for full PDF/UA validation.

## What's *not* in scope

- Greenfield documents — use [`tagging/`](../tagging/) instead. The
  defensive pipeline exists because the original sources can't be
  rewritten freely; if you can rewrite, you don't need it.
- HTML output — see [`latexml/`](../latexml/), [`tex4ht/`](../tex4ht/),
  or [`markdown/`](../markdown/).
- Bibliography backends. The pipeline does not invoke `biber` /
  `bibtex` explicitly (though `latexmk` will run them if `*.bbl` is
  needed).
