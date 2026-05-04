# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a LaTeX research/experimentation repository focused on **accessible PDF and HTML output from LaTeX documents**, specifically:

- **`tagging/`** — PDF/UA accessibility experiments using LuaLaTeX with the `tagpdf` tagging infrastructure. Curated examples live under `tagging/examples/{minimal-ua1,minimal-ua2,full-document}/`; see `tagging/README.md` for the publishable overview.
- **`latexml/`** — LaTeX-to-HTML conversion experiments using LaTeXML. Examples live under `latexml/examples/{minimal,accessibility,research-article}/`; see `latexml/README.md` for the overview.
- **`tex4ht/`** — LaTeX-to-HTML conversion experiments using TeX4ht (`make4ht`). Examples live under `tex4ht/examples/{minimal,accessibility}/`; see `tex4ht/README.md` for the overview. Each example commits both a MathJax- and a MathML-rendered output.
- **`markdown/`** — Markdown-to-HTML conversion experiments using Pandoc. Examples live under `markdown/examples/{minimal,accessibility}/`; see `markdown/README.md` for the overview. **Scope:** intentionally limited to single-file Markdown projects — multi-file workflows (book chapters, citations, custom Lua filters) are out of scope and would be a different project.
- **`test_cases/`** — Real-world, messier LaTeX sources (course notes, etc.) plus `test_cases/build.sh`, the defensive pipeline that compiles them into accessible tagged PDFs. The originals are never edited; iterate on `test_cases/build.sh` instead.

## Compilation

### Tagged PDFs (tagging/ and test_cases/)

All tagged documents must be compiled with **LuaLaTeX** (not pdflatex or xelatex). Use the development version for best tagging support. We always enable **synctex** for good interplay with previewers.

For self-contained examples in `tagging/examples/*/`, run directly from inside the example folder:

```sh
cd tagging/examples/<example>/
lualatex-dev -synctex=1 <filename>.tex
# or, for reliable multi-pass (math tagging often needs ≥2 passes):
latexmk -lualatex -lualatex=lualatex-dev -synctex=1 <filename>.tex
```

For real-world sources in `test_cases/`, use the defensive pipeline:

```sh
./test_cases/build.sh <input.tex> [output-dir]                 # default output-dir: <input_dir>/tagged_output
INCLUDE_ONLY=graph_intro,gr_connect ./test_cases/build.sh ...  # selective subfile compile via \includeonly
```

`test_cases/build.sh` copies sources to a fresh output dir (originals untouched), applies ~10 transformation phases (see *Defensive build pipeline* below), then runs `latexmk -lualatex=lualatex-dev`.

### LaTeXML HTML output (latexml/)

```sh
cd latexml/examples/<example>/
../../build.sh <input.tex> [output.html]
```

`build.sh` lives at `latexml/build.sh` and wraps `latexmlc --pmml --cmml --mathtex --unicodemath --index --css=$SCRIPT_DIR/latex-style.css` (the `latex-style.css` reference resolves to the canonical copy at the `latexml/` root regardless of cwd). It then runs `fix-a11y.sh` to (1) rewrite theorem `<h6>` titles to `<span>` so the heading hierarchy stays clean, and (2) add `role="presentation"` to `ltx_eqn_table` equation-layout tables. `latexmlc` also copies its stock CSS (`LaTeXML.css`, `ltx-<class>.css`) and a sibling copy of `latex-style.css` next to each HTML output. These are all regenerated at runtime and gitignored — only the canonical `latexml/latex-style.css` is tracked. To view a committed `.html` rendered correctly in a browser, run `build.sh` first to regenerate the sibling stylesheets.

### TeX4ht HTML output (tex4ht/)

```sh
cd tex4ht/examples/<example>/
../../build.sh [-m mathjax|mathml] <input.tex> [output.html]
```

`build.sh` wraps `make4ht -c $SCRIPT_DIR/config.cfg -f html5`. The default math mode is **MathML** (native browser rendering, no JavaScript); pass `-m mathjax` for the MathJax variant. The default output filename encodes the math mode (`<basename>.mathml.html` / `<basename>.mathjax.html`), so building both variants is just two invocations. After `make4ht`, `build.sh` runs `fix-a11y.sh`, which adds `role="presentation"` to `<table class='equation'>` elements (the layout containers tex4ht emits for each displayed equation in MathML mode). Note: `build.sh` copies the canonical `style.css` into the example folder *before* invoking `make4ht`, since `config.cfg`'s `\Configure{AddCss}{style.css}` directive resolves the file by relative name during compilation.

### Pandoc HTML output (markdown/)

```sh
cd markdown/examples/<example>/
../../build.sh [-m mathjax|mathml] <input.md> [output.html]
```

`build.sh` wraps `pandoc --standalone --css=style.css <math_flag> <input>.md -o <output>.html` and copies the canonical `style.css` next to the output. The default math mode is **MathML** (native browser rendering, no JavaScript); pass `-m mathjax` for the MathJax variant. The default output filename encodes the math mode (`<basename>.{mathml,mathjax}.html`). No `fix-a11y.sh` is needed — verified that Pandoc HTML doesn't have the `<h6>`-as-theorem or `<table>`-as-equation issues.

## Architecture

### PDF Accessibility (tagging/)

Documents targeting PDF/UA use `\DocumentMetadata` (must appear before `\documentclass`) to configure:

- `tagging = on` — enables the tagging infrastructure
- `tagging-setup = {math/setup={mathml-SE,mathml-AF}, extra-modules={verbatim-mo,verbatim-af}}` — embeds MathML (Structure Element + Artifact Form) in the PDF
- `pdfstandard = ua-1` + `pdfversion = 1.7` for PDF/UA-1, or `pdfstandard = ua-2` + `pdfversion = 2.0` for PDF/UA-2
- `\tagpdfsetup{math/alt/use}` — adds alt-text for math

Math font setup uses `unicode-math` with OpenType fonts. The kept examples and the `build.sh` pipeline standardize on `texgyretermes-math.otf`; the dyslexic variant under `examples/full-document/` swaps in **OpenDyslexic** for the main text font, resolved via fontspec's `*-Regular`/`*-Bold` family-substitution syntax (no absolute paths — the font must be installed to a standard system font location, documented in that example's README). Use `\symcal`, `\symbb`, `\symfrak` (not `\mathcal`, `\mathbb`, `\mathfrak`) when `unicode-math` is loaded.

**UA-1 vs UA-2**: `examples/minimal-ua1/test_UA-1.tex` uses UA-1 with `math/alt/use` only (no MathML embedding); the UA-2 examples (`examples/minimal-ua2/test_UA-2.tex`, `examples/full-document/test_accessibility{,_dyslexic}.tex`) embed MathML via `mathml-SE,mathml-AF`.

### Defensive build pipeline (`test_cases/build.sh`)

`test_cases/` holds real LaTeX (e.g. course-notes books split into subfiles) that breaks the tagging infrastructure if compiled as-is. `test_cases/build.sh` is the workaround. It copies the input tree to an output directory and applies these phases in order — never modifying the originals:

1. **Setup** — copy `*.tex`, `*.png`, `*.jpg`, `*.pdf`, `*.svg`, `*.PNG` into `tagged_output/`.
2. **Strip sub-file standalone preambles** — subfiles wrap their preamble + `\begin{document}` in `\begin{comment}…\end{comment}` (some are broken with `%\begin{comment}`); the script deletes everything from BOF through `\end{comment}` and removes trailing `\end{document}`.
3. **`\input` → `\include`** — enables `\includeonly` for selective compilation; injects `\includeonly{…}` if `INCLUDE_ONLY` is set; strips redundant `\vfill\eject` after `\include`.
4. **`amsbook` → `book`** — `amsbook`'s `\@starttoc`/`\@tocline`/`\@tocwrite` internals conflict with the tagging patches to `\chapter*`, `\contentsline`, etc. Adds `\usepackage{amsmath,mathtools,amsthm}` since `book` doesn't load them implicitly.
5. **Strip structural hacks** — remove `\@tocline` redefinitions of `\l@section` etc.; remove the `enumerate` package and strip optional args from `\begin{enumerate}[…]` (the block module rejects them as unknown keys).
6. **Clean preamble** — remove `\font\sans=cmss10`, `\input xypic`, `\usepackage[all]{xy}`, comma-listed `,xypic`, `nopageno`, `eucal`, `\thispagestyle{empty}`; dedupe `graphicx` and `xcolor`; add `[normalem]` to `ulem`.
7. **Inject `\DocumentMetadata`** — `tagging=on`, `tagging-setup={math/setup={mathml-SE,mathml-AF}, extra-modules={verbatim-mo,verbatim-af}}`, `pdfstandard=ua-2`, `pdfversion=2.0`, `lang=en` (skipped if already present).
8. **Inject unicode-math + font setup** — after the `amssymb` line: `\usepackage{unicode-math}`, `\setmainfont{TeX Gyre Termes}`, `\setmathfont{texgyretermes-math.otf}`, `\tagpdfsetup{math/alt/use}`.
9. **Math font commands** — `\mathbb` → `\symbb`, `\mathcal` → `\symcal`, `\mathfrak` → `\symfrak`, `\mathscr` → `\symscr` across all `.tex` files.
10. **Colorblind-friendly colors** — add `\usepackage[OkabeIto,keep-defaults]{colorblind}` after `xcolor`; remap `\definecolor{T}{rgb}{0,.5,0}` → `\colorlet{T}{OI5}` and the corresponding `F` → `OI6`.
11. **Compile** — `latexmk -lualatex -lualatex="lualatex-dev -interaction=nonstopmode" -synctex=1`.

When a `test_cases/` source fails to build accessibly, fix it by adding/adjusting a phase in `test_cases/build.sh` rather than editing the original `.tex`.

### LaTeXML (latexml/)

The three examples cover progressively harder targets: `examples/minimal/test_latexml.tex` is a 30-line smoke test, `examples/accessibility/test_accessibility.tex` is the same body as `tagging/examples/full-document/` (so PDF and HTML outputs can be compared), and `examples/research-article/Heisenberg.tex` is a real published `amsart` paper used as a stress test (~1400 lines; conversion completes with ~16 warnings — see that folder's README). None of these documents use `\DocumentMetadata` since LaTeXML targets HTML, not tagged PDF. LaTeXML generates Presentation MathML (`--pmml`), Content MathML (`--cmml`), and embeds the raw TeX (`--mathtex`). Post-processing lives in `fix-a11y.sh`.

### TeX4ht (tex4ht/)

Two examples mirror the latexml/ pipeline: `examples/minimal/test_tex4ht.tex` (a smoke test paralleling `latexml/examples/minimal/test_latexml.tex`) and `examples/accessibility/test_accessibility.tex` (the same body as the latexml accessibility example, so the two HTML pipelines can be compared on identical input). Each example commits both a MathJax-rendered and a MathML-rendered HTML, named `<basename>.{mathjax,mathml}.html`, so the two math-rendering modes can be compared side-by-side. The hand-written `config.cfg` and `style.css` at the `tex4ht/` root are the only tracked CSS/config files; per-example copies of `style.css` and the per-document CSS tex4ht emits are regenerated at runtime and gitignored. `fix-a11y.sh` adds `role="presentation"` to the `<table class='equation'>` layout containers tex4ht emits in MathML mode.

### Pandoc / Markdown (markdown/)

Two examples mirror the LaTeX-based pipelines: `examples/minimal/test_pandoc.md` (smoke test) and `examples/accessibility/test_accessibility.md` (the same content as the LaTeX accessibility examples, transcribed to Markdown). Each commits both a MathJax- and a MathML-rendered HTML, same naming convention. The hand-written `style.css` at the markdown/ root is the only tracked stylesheet; per-example copies are byproducts and are gitignored. **Scope is single-file Markdown only** — multi-file Markdown workflows (chapter splits, cross-references, citation databases, custom Lua filters) are out of scope and would be a different project; the README states this caveat upfront. **No `fix-a11y.sh`** — Pandoc's HTML doesn't exhibit the `<h6>`-theorem or `<table>`-equation issues that the LaTeX-based pipelines patch.

### Auto files

`tagging/`, `latexml/`, `tex4ht/`, and `markdown/` deliberately have no `auto/` directory after their respective reorgs — example sources moved into per-folder subdirectories, so Emacs will re-scaffold AUCTeX `.el` hooks per-folder on demand if you visit the sources.
