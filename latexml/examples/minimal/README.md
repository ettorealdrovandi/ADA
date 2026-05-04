# Minimal LaTeXML example

The smallest possible LaTeX → HTML5 conversion via LaTeXML. Just an
`article` class, `hyperref`, a `\maketitle`, two paragraphs of prose
filler, and a single display equation. Used to verify the toolchain
end-to-end.

## Files

- [`test_latexml.tex`](test_latexml.tex) — source.
- [`test_latexml.html`](test_latexml.html) — rendered output.

## Compile

```sh
../../build.sh test_latexml.tex
```
