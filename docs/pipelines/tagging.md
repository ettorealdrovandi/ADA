---
title: Tagging (PDF/UA)
parent: Pipelines
nav_order: 1
has_children: false
---

# Tagging — PDF/UA accessibility

LuaLaTeX with the `tagpdf` infrastructure to produce tagged PDFs that
conform to PDF/UA-1 and PDF/UA-2. Tagging is configured via
`\DocumentMetadata{...}` declared *before* `\documentclass`, with
math content embedded as MathML (Structure Element + Artifact Form)
for assistive-technology consumption.

## Examples

| Folder | What it shows |
|---|---|
| [`minimal-ua1/`](https://github.com/ettorealdrovandi/ADA/tree/main/tagging/examples/minimal-ua1) | Smallest possible PDF/UA-1 document. `pdfstandard=ua-1`, math alt-text via `\tagpdfsetup{math/alt/use}`. No MathML. |
| [`minimal-ua2/`](https://github.com/ettorealdrovandi/ADA/tree/main/tagging/examples/minimal-ua2) | Smallest possible PDF/UA-2 document. Adds `tagging-setup={math/setup={mathml-SE,mathml-AF}, extra-modules={verbatim-mo,verbatim-af}}`. |
| [`full-document/`](https://github.com/ettorealdrovandi/ADA/tree/main/tagging/examples/full-document) | Longer worked example: theorems, definitions, Euler / Gaussian / residue / Stokes, TikZ figures. Includes a sub-variant typeset in **OpenDyslexic**. |

## Compile

For self-contained examples, run from inside the example folder:

```sh
cd tagging/examples/<example>/
latexmk -lualatex -lualatex=lualatex-dev -synctex=1 <filename>.tex
```

(`latexmk` handles the multi-pass nature of math tagging automatically.)

## Prerequisites

- A recent TeX Live with **`lualatex-dev`** (development LuaLaTeX).
- `unicode-math`, `tagpdf`, and the OpenType math font `texgyretermes-math.otf`.
- For the dyslexic variant: **OpenDyslexic** installed in a system font location (`~/Library/Fonts/` on macOS, `~/.fonts/` on Linux, `%WINDIR%\Fonts` on Windows).

## Validation

Validate tagged PDFs with [veraPDF](https://verapdf.org/), the PDF
Accessibility Checker (PAC), or ngPDF.

## In-repo docs

For full details and per-example READMEs, see
[`tagging/README.md`](https://github.com/ettorealdrovandi/ADA/blob/main/tagging/README.md).
