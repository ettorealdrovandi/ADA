# Minimal Pandoc example

The smallest possible Markdown → HTML5 conversion via Pandoc. YAML
front-matter (title, author, language), two short paragraphs of prose
filler, and one display equation. Used to verify the Pandoc toolchain
end-to-end.

## Files

- [`test_pandoc.md`](test_pandoc.md) — source.
- [`test_pandoc.mathjax.html`](test_pandoc.mathjax.html) — MathJax-rendered output.
- [`test_pandoc.mathml.html`](test_pandoc.mathml.html) — MathML-rendered output.

## Compile

```sh
../../build.sh -m mathjax test_pandoc.md
../../build.sh -m mathml  test_pandoc.md
# or, since mathml is the default:
../../build.sh           test_pandoc.md
```
