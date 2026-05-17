# plan.md

This file provides the high-level **design intent** of the defensive
pipeline that turns legacy LaTeX into accessible tagged PDF. For the
authoritative per-phase reference (what each phase does, sub-step
catalog, CLI flag inventory) see [`README.md`](README.md). This file
is intentionally short and aspirational; it survives across phase
renumberings because it does not enumerate them.

## Overview

The pipeline expects messy, real-world, legacy LaTeX as input
(course notes, multi-file `amsbook` books, `$$…$$` plain-TeX math,
`\input xypic`, manual `\setlength`, etc.). Its output, in a separate
folder, is a transformed, cleaned-up source suitable for production of
an accessible tagged PDF — produced by `lualatex-dev` and then verified
for PDF/UA conformance.

## User interface

- Calling the pipeline:

    `/path/to/build.sh [options] <input.tex> [output-dir]`

  This follows the same convention as the sibling pipelines under
  `latexml/`, `tex4ht/`, `markdown/`.
- The interface currently implemented is fine; keep it. CLI flag
  catalog is in `README.md`.

## What the pipeline does

- Replace or eliminate problematic packages (problematic = not
  compatible with the LaTeX tagging infrastructure).
- Clean up legacy code that `pdflatex` tolerated but `lualatex-dev` +
  `tagpdf` reject.
- Inject the accessibility preamble and related code.
- Validate that the transformed sources are structurally well-formed
  (Phase 12) before invoking the compiler.
- Run the compilation step.
- Verify the produced PDF.

### Compilation

The lualatex compilation step is done via `lualatex-dev -synctex=1`.
**DO NOT** use the flag `-interaction=nonstopmode`: doing so may
produce a flawed PDF whose errors are hidden until much later (e.g. at
verapdf, or in a screen reader).

## Problematic packages

Packages that are incompatible or only partly compatible with the
tagging infrastructure:

- **Check the document** at
  <https://latex3.github.io/tagging-project/tagging-status/> for an
  up-to-date list of compatible packages.
- If a package is incompatible, replace or completely eliminate it.
  E.g. `amsbook` is replaced with the standard `book` class.
- Ideally replace or eliminate the partially compatible ones as well.

## Cleanup of messy or legacy code

Certain legacy constructions used for visual effect, but without sound
semantic functionality, are tolerated by `pdflatex` but break — or
become fragile — once compilation is handled by `lualatex-dev`. They
can also break the tagging structure. Examples:

- Using `$$ ... $$` for display math, as opposed to `\[ ... \]` or
  `\begin{equation*} ... \end{equation*}`.
- Line breaks `\\` after ends of paragraphs, after closing equations,
  or to close list environments. E.g. the combination `$$ ... $$\\` is
  lethal, and so is `\item ... \\`.
- Stray `\item` outside list environments — also lethal.

The full catalog of in-pipeline patches is in
[`README.md` § Phase 6](README.md#phase-6--legacy-latex-fixes-catalog).

## Gotchas

- **Don't be too aggressive in cleaning `$$ ... $$`.** NEVER do it
  inside environments unless they are prose-related. `$$` and `\\`
  can be literal markers in certain environments — `\\` inside math
  or tikz environments, `$$` inside `forest` (for binary-tree empty
  nodes). The Phase 6a skip-list (verbatim-, code-, and picture-family
  envs) preserves them.

- **Unbalanced `\begin … \end` pairs** in the transformed source
  trigger a fatal error at compile time and previously slipped past
  unnoticed under `-interaction=nonstopmode`. They are now caught by
  **Phase 12 (Validate balance)**, which:
    - auto-fixes the two safe cases (unclosed env at EOF;
      `\end{X}` alone on a line with no matching open `\begin{X}`);
    - hard-fails on the two unsafe cases (orphan `\end{X}` embedded in
      a content line; genuine mismatched nesting).
  When Phase 12 hard-fails, fix the source manually or pass
  `--no-autofix` first to inspect what would be patched. See
  [`README.md` § Phases](README.md#phases) for the diagnostic format.

- **`tagpdf` error "The number of automatic begin and end text-unit
  para hooks differ!"** — three structural triggers are autofixed;
  some residual cases remain because `amsthm` is only partly
  compatible with the tagging infrastructure (see *Tagpdf-incompatible
  packages* below).
  1. **`\newtheorem`-derived env nested inside another
     `\newtheorem`-derived env** (e.g. `\begin{remark}` inside
     `\begin{example}`). Phase 12c **UNWRAPs** the inner env (deletes
     its `\begin`/`\end` lines so the content survives as plain prose
     inside the outer env).
  2. **`proof` nested directly inside a `\newtheorem`-derived env**
     (e.g. `\begin{proof}` immediately inside `\begin{example}`).
     Phase 12c **SPLITs** the outer env: close before the proof,
     hoist proof to top scope, reopen after (or elide the reopen when
     only spacers remain). Limited to direct nesting — `proof` inside
     `itemize` inside `example`-style sandwiches are reported as
     **SKIP** (intermediate envs would corrupt the splice, and these
     compile cleanly in practice). When the proof body is wrapped in
     a TeX group (e.g. `{\textcolor{red}{\begin{proof}…\end{proof}}}`),
     Phase 12c **falls back to UNWRAP** — splice is brace-unsafe, but
     deleting the proof env tags keeps the colored body intact and
     resolves the trigger.
  3. **`pythonhighlight` package + its `\begin{python}…\end{python}`
     env.** Built on `listings`, which the [LaTeX3 tagging project
     status page](https://latex3.github.io/tagging-project/tagging-status/)
     lists as `currently-incompatible`. Phase 6j removes
     `\usepackage{pythonhighlight}` and rewrites `\begin{python}…\end{python}`
     → `\begin{verbatim}…\end{verbatim}` (built-in, tagpdf-handled).
     Syntax highlighting is lost — accepted cost for accessibility.

  **Residual whitespace-/adjacency-sensitive cases.** Beyond the
  three above, the para-hook error can fire in shapes the pipeline
  cannot reliably structurally fix (e.g. a `\newtheorem*`-derived env
  immediately following an `itemize`, where a single inserted newline
  can make the error vanish). These are characteristic of the
  `amsthm` partial-compatibility status. On any compile failure,
  Phase 13 prints a multi-line warning naming likely partly-
  compatible packages and recommending a re-run (analogous to
  latexmk's repeat-until-stable behaviour); if a partial PDF is left
  in the output directory, downstream tools like Canvas Ally will
  often still accept it for partial accessibility credit.

- **Tagpdf-incompatible packages.** Before adding any
  code-display or block-decoration package to a corpus, check
  <https://latex3.github.io/tagging-project/tagging-status/> for its
  compatibility status. Known **currently-incompatible**: `listings`,
  `fvextra`, `verbatimbox`, `spverbatim`. Known
  **partially-compatible** (works for our use cases): `verbatim`
  (built-in `\begin{verbatim}` patched by tagpdf), `fancyvrb`,
  `amsthm`, `tcolorbox`. When a new corpus brings in an incompatible
  package, mirror Phase 6j's pattern: corpus-conditional precheck,
  rewrite envs to a tagpdf-handled alternative, document the
  cosmetic loss.

- **Stale PDFs from a reused outdir.** If `[outdir]` already contains
  a main PDF from a previous (possibly failed) run, the Phase 13
  success check (`[ ! -f "$pdf_out" ]`) could falsely report success.
  **Phase 1 now removes the stale main PDF** before any transforms
  run, eliminating this trap. Other artifact PDFs (figure images
  copied from the source dir) are left alone.
