# Full-document worked example

A longer PDF/UA-2 document that exercises a representative cross-section
of mathematical typesetting:

- Theorems, definitions, and corollaries declared via `amsthm`.
- Inline and displayed mathematics: Euler's identity, the Gaussian
  integral, the residue theorem, Stokes' theorem.
- An `\includegraphics` figure with explicit `alt=` text.
- Hyperref configuration with `pdftitle`/`pdfauthor` metadata.

## Files

- [`test_accessibility.tex`](test_accessibility.tex) — main source.
- [`test_accessibility.pdf`](test_accessibility.pdf) — rendered output.
- [`alphatest.png`](alphatest.png) — sample figure used by the source.
- [`test_accessibility_dyslexic.tex`](test_accessibility_dyslexic.tex) —
  sub-variant: same body, typeset in **OpenDyslexic** as the main font.
- [`test_accessibility_dyslexic.pdf`](test_accessibility_dyslexic.pdf) —
  rendered dyslexic variant.

## Compile

```sh
latexmk -lualatex -lualatex=lualatex-dev -synctex=1 test_accessibility.tex
```

For the dyslexic variant:

```sh
latexmk -lualatex -lualatex=lualatex-dev -synctex=1 test_accessibility_dyslexic.tex
```

## OpenDyslexic prerequisite

The dyslexic variant requires [OpenDyslexic](https://opendyslexic.org/)
to be installed in a standard system font location:

- **macOS:** `~/Library/Fonts/` or `/Library/Fonts/`
- **Linux:** `~/.fonts/` or `/usr/share/fonts/`
- **Windows:** `%WINDIR%\Fonts`

Download the OTF bundle from
[opendyslexic.org](https://opendyslexic.org/), unpack it, and copy the
four files (`OpenDyslexic-Regular.otf`, `-Bold.otf`, `-Italic.otf`,
`-BoldItalic.otf`) into one of those directories. `fontspec` resolves
the family name and variants automatically — no absolute paths in the
LaTeX source.

## Note on duplication

`test_accessibility.tex` and `test_accessibility_dyslexic.tex` share
about 90% of their body; only the font setup differs. A future cleanup
could split the shared content into a `_body.tex` `\input` so the two
wrappers carry only their preambles. Left as-is for now to keep the
files self-contained as standalone teaching examples.
