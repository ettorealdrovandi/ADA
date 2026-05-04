# Minimal PDF/UA-2 example

The smallest tagged document targeting **PDF/UA-2** (PDF version 2.0).

The `\DocumentMetadata` block enables both tagging and MathML embedding:

```tex
\DocumentMetadata{
  tagging       = on,
  tagging-setup = {math/setup={mathml-SE,mathml-AF}, extra-modules={verbatim-mo,verbatim-af}},
  lang          = en,
  pdfversion    = 2.0,
  pdfstandard   = ua-2,
}
```

The `mathml-SE,mathml-AF` setup writes MathML twice into each math
expression: once as a Structure Element (carried in the tag tree, used
by assistive technology) and once as an Artifact Form (an off-page
copy that survives copy/paste and reuse). `\tagpdfsetup{math/alt/use}`
adds the visible alt-text fallback alongside.

## Files

- [`test_UA-2.tex`](test_UA-2.tex) — source.
- [`test_UA-2.pdf`](test_UA-2.pdf) — rendered output.
- [`test_UA-2.xml`](test_UA-2.xml) — StructTreeRoot dump for inspecting
  the tag tree without a PDF reader.

## Compile

```sh
latexmk -lualatex -lualatex=lualatex-dev -synctex=1 test_UA-2.tex
```
