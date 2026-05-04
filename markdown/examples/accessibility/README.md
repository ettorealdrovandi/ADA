# Accessibility example

The same `test_accessibility` content used elsewhere in this repo
(`latexml/examples/accessibility/`, `tex4ht/examples/accessibility/`,
`tagging/examples/full-document/`), transcribed to Markdown. Section-
level discussion of mathematical typesetting, narrated treatments of
Euler's identity, the Gaussian integral, the residue theorem, and
Stokes' theorem, plus a figure with explicit alt text. The four
pipelines can be compared on equivalent content.

## Files

- [`test_accessibility.md`](test_accessibility.md) — source.
- [`test_accessibility.mathjax.html`](test_accessibility.mathjax.html) — MathJax-rendered output.
- [`test_accessibility.mathml.html`](test_accessibility.mathml.html) — MathML-rendered output.
- [`alphatest.png`](alphatest.png) — sample figure.

## Compile

```sh
../../build.sh -m mathjax test_accessibility.md
../../build.sh -m mathml  test_accessibility.md
```
