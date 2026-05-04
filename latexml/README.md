# LaTeX → HTML5 via LaTeXML

Experiments converting LaTeX sources to accessible HTML5 using
[LaTeXML](https://math.nist.gov/~BMiller/LaTeXML/) (`latexmlc`),
with a small post-processing pass that fixes a couple of accessibility
shortcomings in LaTeXML's default output.

## Examples

| Folder | What it shows |
|---|---|
| [`examples/minimal/`](examples/minimal/) | Smallest possible LaTeXML smoke test — `article` class, one display equation, prose filler. Verifies the toolchain. |
| [`examples/accessibility/`](examples/accessibility/) | Mirror of `tagging/examples/full-document/` for HTML output: theorems, Euler/Gaussian/residue/Stokes, a TikZ-style figure with `alt=` text. |
| [`examples/research-article/`](examples/research-article/) | A real published research paper (`amsart` class, ~1400 lines, theorems, commutative diagrams, bibliography) used as a stress test. Conversion succeeds with warnings — see that folder's README. |

Each example folder ships its source `.tex` and the rendered `.html`
output. The CSS files the HTML's `<link>` tags reference are
*regenerated at runtime* by `latexmlc` and are not tracked:

- `LaTeXML.css` and `ltx-<class>.css` are stock files shipped inside
  the LaTeXML installation; `latexmlc` copies them next to the HTML
  on every build.
- `latex-style.css` is our custom override; the canonical copy lives
  at `latexml/latex-style.css` and is the only tracked stylesheet.
  `build.sh` passes its absolute path to `latexmlc`, which then copies
  it next to the HTML — the per-example copy is a byproduct and is
  also gitignored.

To inspect a committed HTML output rendered correctly in a browser,
run `build.sh` first to regenerate the sibling CSS files.

## How to compile

From any example folder:

```sh
cd examples/<example-folder>/
../../build.sh <basename>.tex
```

`build.sh` wraps:

```sh
latexmlc --pmml --cmml --mathtex --unicodemath --index \
  --css=<latexml/latex-style.css> \
  <input>.tex --dest=<output>.html
```

and then runs `fix-a11y.sh` on the output to apply two accessibility
fixes:

1. Theorem titles emitted as `<h6>` are rewritten to `<span>` so the
   document's heading hierarchy stays clean.
2. LaTeXML's equation-layout `<table class="ltx_eqn_table">` elements
   get `role="presentation"` so screen readers don't announce them as
   data tables.

## Prerequisites

- **LaTeXML** — `brew install latexml` (or your distribution's
  equivalent). The tested version is whatever ships at
  `/opt/homebrew/Cellar/latexml/`.
- **TeX Live** — `latexmlc` shells out to LaTeX for graphics, math
  fallback rendering, etc.
- A modern browser with native MathML rendering (Firefox always; Chrome
  ≥ 109; Safari) for inspecting the HTML output. No MathJax fallback is
  injected.

## Custom styling

`latex-style.css` (at the root of this directory) holds responsive
overrides on top of LaTeXML's stock stylesheets. `build.sh` passes its
absolute path to `latexmlc`, which then copies it next to the HTML
output. To adjust styling for all examples, edit the single canonical
copy and re-run `build.sh`.
