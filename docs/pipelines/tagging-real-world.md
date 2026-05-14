---
title: Tagging — real-world
parent: Pipelines
nav_order: 2
has_children: false
---

# Tagging — real-world LaTeX → PDF/UA-1 or PDF/UA-2

A defensive build pipeline for **legacy, messy LaTeX sources** that
weren't written with tagging in mind: `amsbook`-class books split into
many subfiles via `\input`, plain-TeX `$$...$$` display math, manual
`\setlength` margins, `\vfill\eject` between sections, `xypic`, and so
on. The script `build.sh` copies the input tree to an output directory,
applies a sequence of phases on the **copies**, and compiles the result
with `lualatex-dev`. Originals are never modified.

Both **PDF/UA-2** (default) and **PDF/UA-1** are supported — pick the
flavour with `--ua=1` / `--ua=2` (default 2). UA-1 emits a shorter
`\DocumentMetadata` block without the MathML-embedding `tagging-setup`
line, matching the canonical
[`tagging/examples/minimal-ua1/`](https://github.com/ettorealdrovandi/ADA/tree/main/tagging/examples/minimal-ua1)
preamble.

## When to pick this over [`tagging/`](tagging.html)

The curated `tagging/` examples are for documents that compile cleanly
with `lualatex-dev` and just need `\DocumentMetadata` added. This
pipeline is for everything else: real-world sources that need
preprocessing before they can be made accessible.

## Usage

```sh
./build.sh <input.tex> [output-dir]
```

The script ships **without committed example documents** — the
`examples/` directory is gitignored so private test corpora stay
private. Bring your own input.

Selective subfile compilation:

```sh
INCLUDE_ONLY=chapter1,chapter2 ./build.sh main.tex
```

### Phase-control flags

| Flag | Purpose |
|---|---|
| `--ua=1` \| `--ua=2` | PDF/UA flavour to target (default: 2) |
| `--only=N[,N…]` | Run only the listed phase numbers |
| `--skip=N[,N…]` | Skip the listed phases |
| `--stop-after=N` | Run through phase N and exit (no compile) |
| `--dry-run` | Run all transform phases, print a `diff` against originals, exit |

## What `build.sh` does

13 numbered phases. Each phase is idempotent (re-running on a
partially-built output directory is safe). Phase 6 — the **Legacy
LaTeX fixes** phase — is the heart of the pipeline; it auto-patches
patterns that `pdflatex` tolerated but `lualatex-dev` + tagging do
not (stray `\\` line breaks, `$$ … $$` display math, `\hfill\\`
spacing hacks, `\\\\` inside `align` environments, manual `\setlength`
margins replaced with `geometry`, etc.).

The full phase catalog and the legacy-fixes sub-step table live in the
in-repo README.

## Prerequisites

- A recent TeX Live with **`lualatex-dev`**.
- `latexmk`.
- The `tagpdf` package and the LaTeX team's `latex-lab` modules.
- Optional (used only by phase 13): `pdfinfo` and
  [`verapdf`](https://verapdf.org/) for PDF/UA conformance checks
  (`verapdf` is invoked with the flavour matching the build).

## In-repo docs

For the full phase catalog, sub-step table, and design notes, see
[`tagging-real-world/README.md`](https://github.com/ettorealdrovandi/ADA/blob/main/tagging-real-world/README.md).
