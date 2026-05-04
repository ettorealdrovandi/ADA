# Accessibility example

A more substantial document that exercises a representative slice of
mathematical typesetting (theorems, definitions, corollaries; Euler's
identity, the Gaussian integral, the residue theorem, Stokes' theorem)
plus an `\includegraphics` figure with explicit `alt=` text. The same
LaTeX source also appears in `latexml/examples/accessibility/` and as
the body of `tagging/examples/full-document/test_accessibility.tex`,
so the three pipelines can be compared on identical input.

## Files

- [`test_accessibility.tex`](test_accessibility.tex) — source.
- [`test_accessibility.mathjax.html`](test_accessibility.mathjax.html) — MathJax-rendered output.
- [`test_accessibility.mathml.html`](test_accessibility.mathml.html) — MathML-rendered output.
- [`alphatest.png`](alphatest.png) — sample figure used by the source.

## Compile

```sh
../../build.sh -m mathjax test_accessibility.tex
../../build.sh -m mathml  test_accessibility.tex
```

## What `fix-a11y.sh` cleans up here

The MathML variant produces about ten `<table class='equation'>`
elements — one per displayed equation. tex4ht uses these tables purely
for equation layout, but screen readers would announce them as data
tables. `fix-a11y.sh` adds `role="presentation"` to each so the
equations are read as math content, not tabular data. The MathJax
variant doesn't emit equation tables (MathJax handles equation
rendering in its own DOM), so the post-processing has nothing to do
there.
