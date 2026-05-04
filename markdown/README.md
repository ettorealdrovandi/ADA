# Markdown → HTML5 via Pandoc

Experiments converting single-file Markdown sources to accessible
HTML5 using [Pandoc](https://pandoc.org/), with a small custom
stylesheet for theme/typography.

This directory mirrors the structure of the sibling LaTeX→HTML
pipelines (`latexml/` and `tex4ht/`): one canonical hand-written
`style.css` at the root, a `build.sh` wrapper that exposes a math-mode
flag, and example sources/outputs under `examples/`. The output is
clean enough that this pipeline needs **no `fix-a11y.sh`
post-processor** — Pandoc's HTML doesn't exhibit the `<h6>`-as-theorem
or `<table>`-as-equation issues that the LaTeX-based pipelines need to
patch.

## ⚠ Scope: single-file Markdown only

This pipeline is intentionally limited to **single-file Markdown
projects**. Multi-file workflows are out of scope here, including:

- Books or papers split across chapter files.
- Cross-document references between sibling `.md` files.
- Bibliography / citation processing (`--bibliography`, `--csl`).
- Custom Lua filters that reorganize or extend the AST.
- `\input`-style includes between Markdown files.

A multi-file Markdown-to-accessible-HTML workflow is a different
project; this directory is not the place to evolve one. If you need
that, open a new repo and explore tools like Quarto, mdBook, or a
Pandoc-based custom build with a defaults file.

## Examples

| Folder | What it shows |
|---|---|
| [`examples/minimal/`](examples/minimal/) | Smallest possible smoke test — YAML front-matter, two paragraphs, one display equation. Verifies the Pandoc toolchain. |
| [`examples/accessibility/`](examples/accessibility/) | The same `test_accessibility` content used in `latexml/`, `tex4ht/`, and `tagging/`, transcribed to Markdown: section-level math discussion, the residue and Stokes theorems narrated in prose, a figure with explicit alt text. Each example commits **both** a MathJax-rendered and a MathML-rendered HTML so the two math-mode renderings can be compared directly. |

## How to compile

From any example folder:

```sh
cd examples/<example-folder>/
../../build.sh [-m mathjax|mathml] <basename>.md
```

`build.sh` wraps `pandoc <input>.md -o <output>.html --standalone <math_flag> --css=style.css` and copies the canonical `style.css` next to the output so the `<link>` resolves locally in a browser.

The default math mode is **MathML** (native browser rendering, no
JavaScript). The output filename encodes the math mode automatically:

```sh
../../build.sh                 test_accessibility.md   # → test_accessibility.mathml.html
../../build.sh -m mathjax      test_accessibility.md   # → test_accessibility.mathjax.html
```

so building both variants is just two invocations.

## Two math-rendering modes

| Mode | How it works | Output characteristics |
|---|---|---|
| **MathML** (default) | Pandoc emits MathML elements directly into the HTML body | No JavaScript needed; renders in modern browsers with native MathML support (Firefox always; Chrome ≥ 109; Safari). Smaller HTML, no external requests. |
| **MathJax** | Pandoc keeps the math as TeX-syntax in the HTML and adds a `<script>` referencing the MathJax CDN | Wider browser compatibility (legacy browsers); pretty rendering; requires JavaScript to load MathJax at view time. |

The committed `examples/accessibility/` folder ships both variants so
they can be compared side-by-side.

## Custom styling

`style.css` at the root of this directory is the canonical hand-written
stylesheet and is the only tracked CSS file. `build.sh` copies it next
to each rendered HTML so the `<link href="style.css">` Pandoc emits
resolves locally. The per-example copies are byproducts and are
gitignored. To adjust styling, edit the canonical `style.css` and
re-run `build.sh`.

## Prerequisites

- **Pandoc** — `brew install pandoc` on macOS, or your distribution's
  equivalent.
- A modern browser with native MathML rendering (Firefox always;
  Chrome ≥ 109; Safari) for inspecting the MathML variant. The
  MathJax variant works in any browser with JavaScript enabled.
