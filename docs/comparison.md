---
title: Comparison
layout: default
nav_order: 3
---

# Comparison of the pipelines

| Property | Tagging | Tagging — real-world | LaTeXML | TeX4ht | Markdown (Pandoc) |
|---|---|---|---|---|---|
| **Output format** | Tagged PDF (UA-1, UA-2) | Tagged PDF (UA-2) | HTML5 + Presentation/Content MathML | HTML5 (MathJax or MathML) | HTML5 (MathJax or MathML) |
| **Input format** | LaTeX (tagging-aware) | LaTeX (legacy, messy) | LaTeX | LaTeX | Markdown |
| **Math rendering** | MathML embedded as Structure Element + Artifact Form | Same as Tagging | Both Pres. & Content MathML, with raw TeX as fallback | MathJax (CDN) **or** native MathML | MathJax (CDN) **or** native MathML |
| **Math modes committed per example** | 1 (PDF) | n/a — pipeline ships without examples | 1 (HTML) | 2 (mathjax + mathml) | 2 (mathjax + mathml) |
| **PDF/UA conformance** | Yes (UA-1 / UA-2) | Yes (UA-2) | n/a | n/a | n/a |
| **Accessibility post-processing** | None — handled in TeX | None at the HTML layer; ~13 defensive source-rewrite phases in `build.sh` | `fix-a11y.sh` (theorem `<h6>` + equation `<table>` fixes) | `fix-a11y.sh` (equation `<table>` fix; MathML mode only) | None (output already clean) |
| **Custom CSS tracked** | n/a (PDF output) | n/a (PDF output) | `latex-style.css` | `style.css` + `config.cfg` | `style.css` |
| **Scope notes** | Tagging-pipeline-aware LaTeX sources only | Real-world legacy LaTeX: `amsbook` + `\input`-based books, `$$…$$`, `xypic`, manual margin `\setlength`, etc. | Compatible with most LaTeX dialects (the `amsart` paper builds with ~16 warnings) | Standard LaTeX | **Single-file Markdown only** — multi-file workflows out of scope |

## When to pick which

- **Need a tagged accessible PDF, document compiles cleanly with `lualatex-dev`?** → Tagging pipeline.
- **Need a tagged accessible PDF from a legacy source you can't (or won't) rewrite?** → Tagging — real-world.
- **Need HTML output from existing LaTeX papers, with rich math semantics?** → LaTeXML.
- **Need HTML from LaTeX with simpler styling and a choice of math renderer?** → TeX4ht.
- **Authoring fresh content, want the lightest possible toolchain, single-file scope?** → Pandoc.
