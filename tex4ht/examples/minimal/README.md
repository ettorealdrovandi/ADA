# Minimal TeX4ht example

The smallest possible LaTeX → HTML5 conversion via TeX4ht. Just an
`article` class, `hyperref`, a `\maketitle`, two paragraphs of Kant
lipsum filler, and a single display equation. Used to verify the
`make4ht` toolchain end-to-end.

## Files

- [`test_tex4ht.tex`](test_tex4ht.tex) — source.
- [`test_tex4ht.mathjax.html`](test_tex4ht.mathjax.html) — MathJax-rendered output.
- [`test_tex4ht.mathml.html`](test_tex4ht.mathml.html) — MathML-rendered output.

## Compile

```sh
../../build.sh -m mathjax test_tex4ht.tex
../../build.sh -m mathml  test_tex4ht.tex
# or, since mathml is the default:
../../build.sh           test_tex4ht.tex
```
