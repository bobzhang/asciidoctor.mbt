# TODO

Open work after the 2026-10-05 releases: prawn 0.2.0 and asciidoctor-pdf 0.2.1, on core 0.3.4,
pdflite 0.3.7 and pagelayout 0.7.1.

## Where things stand

- **Releases.** `bobzhang/asciidoctor` 0.3.4, `bobzhang/prawn` 0.2.0 and
  `bobzhang/asciidoctor-pdf` 0.2.1 are published and tagged. Both commands work through moonx:
  `cmd/asciidoctor-pdf` (Rouge only) and `cmd/asciidoctor-pdf-pygments`.
- **Spec suite.** asciidoctor-pdf's suite replays 2097 of 2415 conversions identically. The 318
  known failures are listed in `tests/pdf_golden/known_failures.txt`. The gate passes 38/38.
- **Speed and size against Ruby 4.0.**
  - The native command is 4–8× faster than Ruby; wasm is about 1.5× faster.
  - PDFs are 40–60% smaller than Ruby's by default. Ruby with `-a compress` is about the same
    size.

## PDF backend: fidelity

- **Known failures.** Work down the 318 known spec failures. By category: styling/assets 230,
  geometry 172, missing/extra text 80, navigation/metadata 80, unsupported 23, reading order 22,
  page breaks 14. Regenerate the list with `pdf_compare -- --spec-goldens --write-known ...`.
- **Corpus.** Rerun the 2,840-document corpus comparison; it was last measured at 0.1.0
  (97.6%).
- **Unsupported features:**
  - watermarks
  - `pdf-page-margin-rotated`
  - links and other annotations on imported PDF pages (prawn-templates keeps them)
  - a PDF page background should resize the page to the PDF's size, not scale to the page
  - Ruby's quirk of 36pt margins after a failed PDF front cover (cover_page_spec-1.33/1.36,
    page_spec-1.7.58)
- **CodeRay highlighting.** Not supported; 4 source_spec records.
- **Harvest gaps.** The text-hyphen (hyphens_spec) and open-uri-cached (image cache) examples are
  never harvested. The cause is the same `gem_available?`/Bundler activation issue fixed for
  rouge/pygments in `scripts/pdf_harvest/harvest.rb`. Activate them and support hyphenation.

## PDF backend: highlighting

- **`bobzhang/rouge`.** Extract `pdf/rouge` (engine, lexers, themes) into a reusable module, so
  the HTML backend could use it too. Its dependencies on core case conversion and the `regex`
  package need arranging first, without a cycle back through `bobzhang/asciidoctor`.
- **Lexer state stack.** A lexer that empties its state stack mid-lex aborts the process; Ruby
  raises, failing only that conversion. Make it an error.
- **Guessed languages.** A fenced block whose guessed language has no ported lexer falls back to
  plain text. Port more lexers, or document the gap.
- **Activation regression.** The harvest has no committed test that the pinned highlighter
  version wins when a newer Rouge (4.x) is installed alongside it.

## prawn module

Moved to [prawn.mbt](https://github.com/bobzhang/prawn.mbt), with its open items (API cleanup,
licence, versions, SVG coverage) in that repository's `PLAN.md`.

## Size

- **pagelayout's bundled fonts** (11.9 MB) are linked but unused by the PDF backend. An opt-in
  bundled-font fallback in pagelayout (office.mbt PR) would shrink the CLI to roughly 6 MB wasm.
- **Current sizes:** 18.8 MB (Rouge only) / 28.7 MB (with Pygments) wasm; Pygments alone adds
  about 10 MB.

## Upstream libraries (moonbitlang/office.mbt; merges need the owner's approval)

- **pdflite.** The name and number trees in `pdf_tree_read.mbt` are still read recursively;
  bound them like the page-tree walk from #589.

## Housekeeping

- **Old worktrees.** Remove the finished subagent worktrees under `.claude/worktrees/` once
  nothing in them is needed: `git worktree list`, then `git worktree remove`.
- **Merged branches.** The stacked highlighting branches (`hl-*`) and older merged branches are
  still on GitHub; delete them when no longer useful.
