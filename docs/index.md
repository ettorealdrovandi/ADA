---
title: Home
layout: default
nav_order: 1
---

# ADA — Accessible Documents from LaTeX

Experiments in producing accessible PDF and HTML output from LaTeX sources.

ADA is a research and experimentation playground that compares several
toolchains for emitting accessible documents from LaTeX: PDF/UA tagging
via LuaLaTeX + `tagpdf`, plus HTML conversion via LaTeXML, TeX4ht
(`make4ht`), and Pandoc.

## Pipelines

| Pipeline | What it does |
|---|---|
| [Tagging (PDF/UA)](pipelines/tagging.html) | LuaLaTeX + `tagpdf` → tagged PDF/UA-1, PDF/UA-2 |
| [Tagging — real-world](pipelines/tagging-real-world.html) | Defensive build script for legacy LaTeX → PDF/UA-2 without modifying the originals |
| [LaTeXML](pipelines/latexml.html) | LaTeX → HTML5 + MathML via LaTeXML |
| [TeX4ht](pipelines/tex4ht.html) | LaTeX → HTML5 via `make4ht` |
| [Markdown](pipelines/markdown.html) | Single-file Markdown → HTML5 via Pandoc |

See the [comparison page](comparison.html) for a side-by-side overview.

## Source

Code lives at [github.com/ettorealdrovandi/ADA](https://github.com/ettorealdrovandi/ADA).
Released under the [MIT License](https://github.com/ettorealdrovandi/ADA/blob/main/LICENSE).
