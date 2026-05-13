---
title: LaTeXML
parent: Pipelines
nav_order: 3
---

# LaTeXML — LaTeX → HTML5 + MathML

[LaTeXML](https://math.nist.gov/~BMiller/LaTeXML/) is a LaTeX-aware
converter that produces HTML5 with embedded MathML (both
Presentation and Content) plus the original TeX as alternative content.
Output is post-processed by `fix-a11y.sh` to (1) rewrite theorem
`<h6>` titles as `<span>` so the heading hierarchy stays clean, and
(2) add `role="presentation"` to the `ltx_eqn_table` equation-layout
tables.

## Examples

| Folder | What it shows |
|---|---|
| [`minimal/`](https://github.com/ettorealdrovandi/ADA/tree/main/latexml/examples/minimal) | 30-line smoke test. |
| [`accessibility/`](https://github.com/ettorealdrovandi/ADA/tree/main/latexml/examples/accessibility) | Same body as `tagging/examples/full-document/` so PDF and HTML outputs can be compared on identical input. |
| [`research-article/`](https://github.com/ettorealdrovandi/ADA/tree/main/latexml/examples/research-article) | Stress test: a real published `amsart` paper (~1400 lines). Conversion completes with ~16 warnings. |

## Compile

```sh
cd latexml/examples/<example>/
../../build.sh <input.tex> [output.html]
```

`build.sh` wraps:

```sh
latexmlc --pmml --cmml --mathtex --unicodemath --index \
  --css="$SCRIPT_DIR/latex-style.css" <input.tex>
```

then runs `fix-a11y.sh` on the output.

## Custom styling

Only `latexml/latex-style.css` (the canonical user-authored stylesheet)
is tracked. The stock `LaTeXML.css` and per-class `ltx-*.css` files
that LaTeXML emits are regenerated at runtime and gitignored.

## Prerequisites

- [LaTeXML](https://math.nist.gov/~BMiller/LaTeXML/get.html) (CPAN or `brew install latexml`).
- A recent TeX Live for the underlying compilation.

## In-repo docs

See [`latexml/README.md`](https://github.com/ettorealdrovandi/ADA/blob/main/latexml/README.md)
for the canonical, working-level documentation.
