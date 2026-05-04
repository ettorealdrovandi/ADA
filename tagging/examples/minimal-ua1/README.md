# Minimal PDF/UA-1 example

The smallest tagged document targeting **PDF/UA-1** (PDF version 1.7).

The `\DocumentMetadata` block enables tagging and selects the UA-1
standard:

```tex
\DocumentMetadata{
  tagging      = on,
  lang         = en,
  pdfversion   = 1.7,
  pdfstandard  = ua-1,
}
```

`\tagpdfsetup{math/alt/use}` adds alt-text to every math expression,
which is the route we take for UA-1 here. UA-1 does not require
embedded MathML, so the `tagging-setup = {math/setup={mathml-SE,mathml-AF}, ...}`
line is left commented out — toggle it on if you want UA-1 with MathML
as well.

## Files

- [`test_UA-1.tex`](test_UA-1.tex) — source.
- [`test_UA-1.pdf`](test_UA-1.pdf) — rendered output.
- [`test_UA-1.xml`](test_UA-1.xml) — StructTreeRoot dump for inspecting
  the tag tree without a PDF reader.

## Compile

```sh
latexmk -lualatex -lualatex=lualatex-dev -synctex=1 test_UA-1.tex
```
