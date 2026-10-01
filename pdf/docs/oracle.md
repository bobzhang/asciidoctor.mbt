# The Ruby oracle

The PDF backend is checked against Ruby asciidoctor-pdf 2.3.27, pinned with
all its dependencies. The scripts that run it:

| script | what it runs |
| --- | --- |
| `scripts/pdf_compare.mbtx` | the gate: built-in cases, `--list` corpora, `--spec-goldens` replay, `--self-test` |
| `scripts/pdf_harvest.mbtx` | asciidoctor-pdf's RSpec suite, recording the spec goldens in `tests/pdf_golden` |
| `scripts/pdf_theme_harvest.mbtx` | the theme loader cases of `pdf/theme/harvest_test.mbt` |
| `scripts/pdf_bundle_themes.mbtx` | reads the bundled themes into `pdf/theme/bundled.mbt` |

## Setup

You need Ruby 3.x with a C compiler (bigdecimal builds a native extension)
and network access for the first run. Everything else is installed into
`.repos/` (gitignored):

```sh
moon run --target native scripts/pdf_harvest.mbtx
```

The first run installs:

- `.repos/gems-pdf`: asciidoctor-pdf 2.3.27 and its runtime dependencies
  (prawn 2.4.0, prawn-svg 0.34.2, ttfunk 1.7.0 and the rest, listed in
  `runtime_pinned`), each at its pinned version
- `.repos/asciidoctor-pdf-2.3.27`: a shallow clone of the release tag, for
  its spec suite
- `.repos/gems-pdf-spec`: the spec dependencies (rspec 3.12 and the rest,
  listed in `pinned_gems`)

Then it runs the spec suite and writes the reference PDFs to
`_build/pdf-spec-cache/pdfs`, which `pdf_compare.mbtx --spec-goldens`
replays against.

## Choosing the Ruby and the gem homes

| setting | flag | environment | default |
| --- | --- | --- | --- |
| Ruby | `--ruby RUBY` | `ASCIIDOCTOR_PDF_RUBY` | Homebrew's Ruby (`/opt/homebrew/opt/ruby/bin/ruby`, `/usr/local/opt/ruby/bin/ruby`) when installed, else `ruby` on `PATH` |
| oracle gems | `--gems DIR` | `ASCIIDOCTOR_PDF_GEMS` | `.repos/gems-pdf` |
| spec gems | `--spec-gems DIR` (harvest only) | `ASCIIDOCTOR_PDF_SPEC_GEMS` | `.repos/gems-pdf-spec` |

A flag wins over the environment. The harvest installs gems with the `gem`
command next to the Ruby it runs (else `gem` on `PATH`). The theme scripts
take the environment variables only. The system Ruby of macOS is too old,
hence the Homebrew default there.

For example, with a Ruby managed by rbenv and the gems outside the
checkout:

```sh
export ASCIIDOCTOR_PDF_RUBY=$(rbenv which ruby)
export ASCIIDOCTOR_PDF_GEMS=$HOME/.cache/asciidoctor-pdf-oracle
moon run --target native scripts/pdf_harvest.mbtx   # installs, then harvests
moon run --target native scripts/pdf_compare.mbtx -- --gate
```

## What the harvest guards

The harvest writes into `_build/pdf-spec-cache/staging` and replaces the
committed records (`tests/pdf_golden/*.jsonl`, `summary.txt`) and the
reference PDFs only after the RSpec run succeeded (apart from the known
environmental `cli_spec` failures) and no spec file yielded fewer records
than `tests/pdf_golden/record_counts.txt` says. Pass `--update-counts`
after an intended change in the counts.

A full `pdf_compare.mbtx --spec-goldens` replay checks the same counts: it
fails when it replays fewer records of a spec file than the harvest wrote.
