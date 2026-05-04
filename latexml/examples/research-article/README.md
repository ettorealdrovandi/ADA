# Research-article example

A real published research paper used as a LaTeXML stress test. The
source is roughly 1400 lines of `amsart` LaTeX with theorems,
commutative diagrams (`tikz-cd`), an extensive math-operator preamble,
a bibliography, and the usual idiosyncrasies of an authored article
that was never written with HTML conversion in mind.

## Files

- [`Heisenberg.tex`](Heisenberg.tex) — source.
- [`Heisenberg.html`](Heisenberg.html) — rendered output.

## Compile

```sh
../../build.sh Heisenberg.tex
```

## Known issues

LaTeXML's conversion of this paper completes (status code 1) but emits
roughly a dozen warnings — most of them around math-mode parsing for
constructs like `\sb` floating subscripts, custom-defined operators,
and macro nesting that LaTeXML's parser handles imperfectly. The
resulting HTML is readable but not pixel-perfect against the original
typeset PDF. Diagnostics live in `Heisenberg.latexml.log` (not tracked
in git; regenerated on each build).

This example is here precisely to surface those rough edges. If you
fix one, the warning count in the log should drop.
