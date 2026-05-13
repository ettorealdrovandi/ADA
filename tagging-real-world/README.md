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
| `--only=N[,N…]` | Run only the listed phase numbers (see phase list below). |
| `--skip=N[,N…]` | Run everything except the listed phases. |
| `--stop-after=N` | Run through phase N and exit (no compile). Useful for debugging which phase introduced a problem. |
| `--dry-run` | Run all transformation phases, then print a `diff -ru` against the originals and exit. `latexmk` is not invoked. |
| `-h`, `--help` | Show built-in help. |

## Phases

The pipeline is intentionally a flat list of 13 numbered phases. Each
phase logs what it touched; phases that mutate state are
**idempotent** — re-running on a partially-built output directory is
safe.

| # | Phase | What it does |
|---|---|---|
| 1 | Setup | Copies `*.tex`, `*.png`, `*.jpg`, `*.pdf`, `*.svg`, `*.PNG` from the input directory to the output directory. Originals are never touched after this. |
| 2 | Strip sub-file standalone preambles | Sub-files often wrap their standalone preamble + `\begin{document}` in `\begin{comment}…\end{comment}` (or, broken, `%\begin{comment}…\end{comment}`). The script deletes everything from BOF through `\end{comment}` and removes any trailing `\end{document}`. |
| 3 | `\input` → `\include` | Enables `\includeonly` for selective compilation; injects `\includeonly{…}` if `INCLUDE_ONLY` is set; strips redundant `\vfill\eject` immediately after each `\include`. |
| 4 | `amsbook` → `book` | `amsbook`'s `\@starttoc` / `\@tocline` / `\@tocwrite` internals clash with the tagging infrastructure's patches to `\chapter*`, `\contentsline`, etc. Adds `\usepackage{amsmath,mathtools,amsthm}` (which `book` doesn't autoload). |
| 5 | Strip structural hacks | Removes `\@tocline` redefinitions of `\l@section` etc.; removes the `enumerate` package and strips optional args from `\begin{enumerate}[…]` (the tagging block module rejects them as unknown keys). |
| 6 | **Legacy LaTeX fixes** | Catalog below. |
| 7 | Clean preamble | Removes `\font\sans=cmss10`, `\input xypic`, `\usepackage[all]{xy}`, comma-listed `,xypic`, `nopageno`, `eucal`, `\thispagestyle{empty}`; dedupes `graphicx` and `xcolor`; adds `[normalem]` to `ulem`. |
| 8 | Inject `\DocumentMetadata` | UA-2, version 2.0, MathML embedded as Structure Element + Artifact Form, `lang=en`. Skipped if already present. |
| 9 | Inject `unicode-math` + font setup | `\usepackage{unicode-math}`, TeX Gyre Termes / `texgyretermes-math.otf`, `\tagpdfsetup{math/alt/use}`. Skipped if already present. |
| 10 | Math font commands | `\mathbb` → `\symbb`, `\mathcal` → `\symcal`, `\mathfrak` → `\symfrak`, `\mathscr` → `\symscr`. Required because `unicode-math` clashes with the legacy `\math*` commands. |
| 11 | Colorblind-friendly colors | Adds `\usepackage[OkabeIto,keep-defaults]{colorblind}` after `xcolor`; remaps the conventional `T` (green) and `F` (red) colors to Okabe-Ito `OI5` / `OI6`. |
| 12 | Compile | `latexmk -lualatex -lualatex="lualatex-dev -interaction=nonstopmode" -synctex=1`. |
| 13 | PDF/UA validation | Light conformance check: reads PDF metadata via `pdfinfo` (if installed) and optionally runs `verapdf --flavour ua2` (if installed). Neither tool is a hard dependency. |

### Phase 6 — Legacy LaTeX fixes (catalog)

The transforms below auto-patch patterns that `pdflatex` tolerated but
`lualatex-dev` + tagging do not. Every transform runs on the **copies**
in the output directory; originals are never touched.

| Sub-step | Pattern | Replacement | Notes |
|---|---|---|---|
| 6a | `$$ … $$` (plain-TeX display math, deprecated) | `\[ … \]` | Pair-toggle awk that tracks `$…$` inline-math state, so a typo `$X$$Y$` (close-then-open inline) is **left unchanged** rather than mis-converted. Skips inside `verbatim`, `lstlisting`, `comment` envs and after `%` line comments. Warns on unbalanced `$$` and `$$$` sequences. |
| 6b | `\\\\` inside `align` / `align*` (double line break = empty math row, rejected by recent kernels) | `\\` | Range-restricted sed; runs only between `\begin{align}` / `\end{align}` markers. |
| 6c | Standalone `\hfill`, `\hfill\\`, `\hfill\\\\` on their own line | Line deleted | Fragile spacing hacks (typically after a `\subsection{}` heading) that tagging can't classify. |
| 6d | Trailing `\\` at end of a line whose **following** line is blank, or starts with `\item` / `\end{…}` / `\begin{…}` / `\section` / `\subsection` / `\subsubsection` / `\chapter` / `\paragraph` / `\subparagraph` / `\part` | `\\` removed | A no-op line break in that position; newer LaTeX raises a fatal *"there's no line here to end"* error. Two-line awk lookahead. |
| 6e | `\\` at end of an `\item` line | `\\` removed | Pure legacy formatting habit. |
| 6e2 | `\]\\` or `\)\\` at end of a line (line break immediately after a math-mode close) | `\]` / `\)` | Same *"no line here to end"* class of error. |
| 6f | `\vfill\eject` on its own line | `\clearpage` | The `\include`-adjacent case is already handled by Phase 3. |
| 6g | Master preamble: `\setlength{\textwidth\|\textheight\|topmargin\|oddsidemargin\|evensidemargin}{…}` | Deleted; replaced by a single `\usepackage[paper=letterpaper,total={6in,8.5in}]{geometry}` | Inserted only once (idempotent). |
| 6h | Inline math `$X$` **inside** a section-level command (`\section{…}`, `\subsection{…}`, …, `\part{…}`) | `\texorpdfstring{$X$}{}` | Without this wrapper, `unicode-math` symbols like `\mitOmega` leak into the `.aux` file (TOC / PDF bookmarks) and trigger an *"improper alphabetic constant"* cascade on the next pass. The empty second arg drops the math from TOC / bookmarks but preserves it in the typeset heading. |

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
- Optional, only used in phase 13: `pdfinfo` (from poppler-utils) and
  [`verapdf`](https://verapdf.org/) for full PDF/UA-2 validation.

## What's *not* in scope

- Greenfield documents — use [`tagging/`](../tagging/) instead. The
  defensive pipeline exists because the original sources can't be
  rewritten freely; if you can rewrite, you don't need it.
- HTML output — see [`latexml/`](../latexml/), [`tex4ht/`](../tex4ht/),
  or [`markdown/`](../markdown/).
- Bibliography backends. The pipeline does not invoke `biber` /
  `bibtex` explicitly (though `latexmk` will run them if `*.bbl` is
  needed).
