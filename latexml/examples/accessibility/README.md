# Accessibility example

A more substantial document that exercises a representative slice of
mathematical typesetting (theorems, definitions, corollaries; Euler's
identity, the Gaussian integral, the residue theorem, Stokes' theorem)
plus an `\includegraphics` figure with explicit `alt=` text. Mirrors the
LaTeX source under `tagging/examples/full-document/` so the HTML output
can be compared directly against the tagged-PDF version.

## Files

- [`test_accessibility.tex`](test_accessibility.tex) — source.
- [`test_accessibility.html`](test_accessibility.html) — rendered output.
- [`alphatest.png`](alphatest.png) — sample figure used by the source.

## Compile

```sh
../../build.sh test_accessibility.tex
```

## What `fix-a11y.sh` cleans up here

Theorems in `amsthm` produce `<h6>` titles by default in LaTeXML's
output, which would put the document's heading hierarchy at level 6
within seconds. The post-processing pass rewrites those to `<span>`
elements that look the same but don't pollute the heading structure.
Equation-layout tables get `role="presentation"` so they aren't
announced as tabular data.
