---
title: Markdown (Pandoc)
parent: Pipelines
nav_order: 4
---

# Markdown — Pandoc → HTML5

The Markdown pipeline uses [Pandoc](https://pandoc.org/) to convert
single-file Markdown sources to standalone HTML5. Each example
commits **two** rendered HTMLs (MathJax and native MathML), with the
new default being MathML.

> ## ⚠ Scope: single-file Markdown only
>
> This pipeline handles single-file Markdown projects. Multi-file
> workflows — books split across chapter files, cross-document
> references, citation databases (`--bibliography`), custom Lua
> filters, includes — are intentionally **out of scope** here.
> A multi-file Markdown-to-accessible-HTML workflow would be a
> different project; this directory is not the place to evolve it.

## Examples

| Folder | What it shows |
|---|---|
| [`minimal/`](https://github.com/ettorealdrovandi/ADA/tree/main/markdown/examples/minimal) | Pandoc smoke test: YAML front-matter, two paragraphs, one display equation. |
| [`accessibility/`](https://github.com/ettorealdrovandi/ADA/tree/main/markdown/examples/accessibility) | Same content as the LaTeX-based accessibility examples, transcribed to Markdown. The four pipelines can be compared on equivalent content. |

## Compile

```sh
cd markdown/examples/<example>/
../../build.sh [-m mathjax|mathml] <input.md> [output.html]
```

The default math mode is **MathML**; output filename encodes the
mode.

## Custom styling

Only `markdown/style.css` (the canonical user-authored stylesheet)
is tracked. The per-example sibling copy that `build.sh` puts next to
each rendered HTML is gitignored.

## No `fix-a11y.sh`

Verified that Pandoc's HTML output doesn't have the two issues the
LaTeXML and TeX4ht pipelines patch around (no `<h6>` for theorems,
no `<table>` layout for equations), so no post-processor runs.

## Prerequisites

- [Pandoc](https://pandoc.org/installing.html) (`brew install pandoc` on macOS).

## In-repo docs

See [`markdown/README.md`](https://github.com/ettorealdrovandi/ADA/blob/main/markdown/README.md)
for full details.
