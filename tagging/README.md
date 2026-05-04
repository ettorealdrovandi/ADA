# Accessible PDF/UA tagging examples

A small set of LuaLaTeX examples demonstrating how to produce well-tagged,
accessible PDFs using the LaTeX team's `tagpdf` infrastructure and the
`\DocumentMetadata` interface.

The collection follows the structure of the [LaTeX3 tagging-project
documentation](https://latex3.github.io/tagging-project/documentation/wtpdf/):
two short minimal examples — one per PDF/UA standard — plus one longer
worked example that exercises theorems, mathematics, and figures.

## Examples

| Folder | What it shows |
|---|---|
| [`examples/minimal-ua1/`](examples/minimal-ua1/) | Smallest possible PDF/UA-1 document. Math alt-text, no MathML embedding. |
| [`examples/minimal-ua2/`](examples/minimal-ua2/) | Smallest possible PDF/UA-2 document. Math alt-text plus embedded MathML (Structure Element + Artifact Form). |
| [`examples/full-document/`](examples/full-document/) | Longer worked example: theorems, Euler/Gaussian/residue/Stokes, TikZ, figures with `alt=` text. Includes a sub-variant typeset in OpenDyslexic. |

Each example folder ships its source `.tex`, the rendered `.pdf`, and (for
the minimal examples) an `.xml` dump of the PDF's StructTreeRoot for
inspection without a PDF reader.

## How to compile

All examples must be compiled with **LuaLaTeX** — specifically the
development branch (`lualatex-dev`) for the most up-to-date tagging
support. Math tagging often requires two or more passes; `latexmk`
handles this automatically:

```sh
cd examples/<example-folder>/
latexmk -lualatex -lualatex=lualatex-dev -synctex=1 <basename>.tex
```

A single-pass invocation also works for minimal documents:

```sh
lualatex-dev -synctex=1 <basename>.tex
```

## Prerequisites

- A recent **TeX Live** with the development LuaLaTeX (`lualatex-dev`).
- The `tagpdf` package and the LaTeX team's `latex-lab` modules
  (bundled with current TeX Live).
- `unicode-math` and the OpenType math fonts referenced in each example
  (TeX Gyre Termes Math is included in TeX Live; EB Garamond and
  Garamond-Math are not, but no example here uses them — they would
  appear if more variants are added later).
- For the OpenDyslexic sub-variant of the larger example, install
  [OpenDyslexic](https://opendyslexic.org/) into your system or user
  font path. The `.tex` source currently hard-codes a macOS user
  font path; see that example's README.

## A note on `test_cases/`

A sibling directory `../test_cases/` holds real-world LaTeX sources
(course notes, etc.) that *do* require preprocessing before they can be
compiled with the tagging infrastructure. The defensive pipeline that
performs that preprocessing lives at `../test_cases/build.sh` and is
documented in the project's top-level `CLAUDE.md`. It is not relevant
to the curated examples in this directory, which compile cleanly with
`lualatex-dev` or `latexmk`.

## Validating a tagged PDF

External tools to verify PDF/UA conformance and inspect the tag tree:

- **VeraPDF** — open-source PDF/UA validator. Web UI at
  [demo.verapdf.org](https://demo.verapdf.org/) or run locally.
- **PAC (PDF Accessibility Checker)** — Windows-only checker maintained
  by access-for-all.ch.
- **ngPDF** — converts a tagged PDF to HTML for inspection.
- **`showtags`** (TeX Live) — prints the structural tree of a tagged
  PDF directly in the terminal.
