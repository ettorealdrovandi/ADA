# ADA — Accessible Documents from LaTeX

Experiments in producing accessible PDF and HTML output from LaTeX sources.

## What's here

ADA is a research and experimentation playground that compares several
toolchains for emitting accessible documents from LaTeX: PDF/UA tagging via
LuaLaTeX + `tagpdf`, plus HTML conversion via LaTeXML, TeX4ht (`make4ht`),
and Pandoc. The `tagging/` directory holds a curated set of examples ready
to be read and reused; the other directories are still works in progress
and may have rough edges.

## Subdirectories

| Path | What it does | Status |
|---|---|---|
| [`tagging/`](tagging/) | PDF/UA accessibility examples using LuaLaTeX + `tagpdf`. Minimal UA-1 / UA-2 documents and one longer worked example. | **Curated** |
| [`latexml/`](latexml/) | LaTeX-to-HTML conversion via LaTeXML, with light a11y post-processing. | **Curated** |
| [`tex4ht/`](tex4ht/) | LaTeX-to-HTML conversion via TeX4ht (`make4ht`). Each example commits both a MathJax- and MathML-rendered HTML for direct comparison. | **Curated** |
| [`markdown/`](markdown/) | Markdown-to-HTML conversion via Pandoc. Each example commits both a MathJax- and MathML-rendered HTML. **Single-file Markdown only — multi-file workflows out of scope.** | **Curated** |
| [`test_cases/`](test_cases/) | Real-world LaTeX sources (course notes, etc.) plus `test_cases/build.sh`, the defensive multi-phase pipeline that produces tagged accessible PDFs from them. | Under restructuring |

## Quick start

Render the smallest tagged example to confirm your toolchain is set up:

```sh
cd tagging/examples/minimal-ua1
latexmk -lualatex -lualatex=lualatex-dev -synctex=1 test_UA-1.tex
```

For everything else under `tagging/` (prerequisites, the longer worked
example, validation tools), see [`tagging/README.md`](tagging/README.md).

## Status

This repository is an active experiment, not a finished product. Layouts,
filenames, and build scripts may change as the underlying tagging
infrastructure evolves and as more of the directory is restructured for
publication. Use it as a reference and a starting point, not a stable API.

## License

Released under the [MIT License](LICENSE).
