---
title: TeX4ht
parent: Pipelines
nav_order: 4
---

# TeX4ht — LaTeX → HTML5 via `make4ht`

The TeX4ht pipeline uses [`make4ht`](https://www.kodymirus.cz/make4ht/)
to produce HTML5 output. Each example commits **two** rendered HTMLs:
one with MathJax (CDN-loaded, JS-rendered) and one with native
**MathML** (the new default). `fix-a11y.sh` adds
`role="presentation"` to the `<table class='equation'>` containers
that tex4ht emits for displayed equations in MathML mode.

## Examples

| Folder | What it shows |
|---|---|
| [`minimal/`](https://github.com/ettorealdrovandi/ADA/tree/main/tex4ht/examples/minimal) | Smoke test paralleling the LaTeXML minimal example. |
| [`accessibility/`](https://github.com/ettorealdrovandi/ADA/tree/main/tex4ht/examples/accessibility) | Same body as the LaTeXML and tagging accessibility examples, so the two HTML pipelines can be compared on identical input. |

## Compile

```sh
cd tex4ht/examples/<example>/
../../build.sh [-m mathjax|mathml] <input.tex> [output.html]
```

The default math mode is **MathML**. Output filename encodes the math
mode (`<basename>.{mathjax,mathml}.html`), so building both variants
is just two invocations.

## Two math-rendering modes

- **MathJax** — CDN-loaded, JavaScript-rendered. Broader
  cross-browser compatibility historically; depends on JS being
  enabled.
- **MathML** — native browser rendering, no JS, smaller HTML.
  Modern browsers ship full support.

The committed `examples/accessibility/` folder ships both renderings
of the same source so they can be opened side-by-side.

## Custom styling

`tex4ht/style.css` (responsive theme) and `tex4ht/config.cfg`
(theorem/definition/corollary class-name configuration) at the
pipeline root are the only tracked CSS/config files. Per-example
copies and the per-document CSS that tex4ht emits are regenerated at
runtime and gitignored.

## Prerequisites

- `make4ht` (from a recent TeX Live, or `brew install make4ht`).

## In-repo docs

See [`tex4ht/README.md`](https://github.com/ettorealdrovandi/ADA/blob/main/tex4ht/README.md)
for full details.
