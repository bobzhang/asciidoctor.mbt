# asciidoctor.mbt

A faithful port of [Asciidoctor](https://github.com/asciidoctor/asciidoctor) (the Ruby AsciiDoc
processor) to [MoonBit](https://www.moonbitlang.com). It parses AsciiDoc and converts it to HTML 5,
DocBook 5 and manpage (troff), aiming for byte-for-byte identical output with Ruby Asciidoctor
(tracking upstream `2.1.0.alpha.0`).

* The core (parser, substitutions, converters) is pure and synchronous and runs on every MoonBit
  backend (native, wasm-gc, js). File access goes through a small `Vfs` interface.
* The `io` package provides file-system integration on top of
  [`moonbitlang/async`](https://mooncakes.io/docs/moonbitlang/async), and `cmd/asciidoctor` is a CLI.

## Converting a string

```mbt check
///|
test "convert a string" {
  let html = @asciidoctor.convert("A paragraph with *strong* and _emphasis_.")
  inspect(
    html,
    content=(
      #|<div class="paragraph">
      #|<p>A paragraph with <strong>strong</strong> and <em>emphasis</em>.</p>
      #|</div>
    ),
  )
}
```

Options mirror Ruby's options hash:

```mbt check
///|
test "options" {
  let options = @core.Options::new(backend="docbook5", attributes=[
    ("product", Str("MoonBit")),
  ])
  inspect(
    @asciidoctor.convert("Hello from {product}.", options~),
    content=(
      #|<simpara>Hello from MoonBit.</simpara>
    ),
  )
}
```

## Working with the document model

`load` parses without converting and returns the document node. Every node is a `@core.Node`; its
`context` says what kind of node it is.

```mbt check
///|
test "load and inspect" {
  let doc = @asciidoctor.load(
    (
      #|= Document Title
      #|
      #|== First Section
      #|
      #|content
    ),
  )
  inspect(doc.doctitle().unwrap(), content="Document Title")
  let section = doc.blocks[0]
  inspect(section.context.name(), content="section")
  inspect(section.title().unwrap(), content="First Section")
  inspect(section.id.unwrap(), content="_first_section")
}
```

## Extensions

Extensions are typed callbacks registered on a `@core.Extensions` registry (block, block macro,
inline macro, preprocessor, tree processor, postprocessor, include and docinfo processors):

```mbt check
///|
test "inline macro extension" {
  let exts = @core.Extensions::new()
  exts.inline_macro("man", (parent, target, attrs) => {
    let label = "\{target}(\{attrs.pos_str(1).unwrap_or("")})"
    Some(
      InlineNode(
        @core.create_anchor(
          parent,
          Some(label),
          "link",
          target="\{target}.html",
        ),
      ),
    )
  })
  let html = @asciidoctor.convert(
    "See man:git[1].",
    options=@core.Options::new(extensions=exts),
  )
  inspect(
    html,
    content=(
      #|<div class="paragraph">
      #|<p>See <a href="git.html">git(1)</a>.</p>
      #|</div>
    ),
  )
}
```

## Files and the command line

`@io.convert_file(path)` reads the input, resolves includes, docinfo files and assets from the file
system (asynchronously, then reruns the pure pipeline until every requested file is available) and
writes the output next to the input, like `Asciidoctor.convert_file`. `@io.convert_source` is the
general driver behind it (Ruby `Asciidoctor.convert`): a file or a string (e.g. standard input),
written next to the input, to an explicit file or directory (jailed in safe mode), to standard output
or not at all; it copies stylesheets (`linkcss` + `copycss`), writes the `.so` pages of a man page's
alternate names, and returns the document and its output. The CLI is a thin invoker on top of it.

Run the CLI straight from [mooncakes.io](https://mooncakes.io/docs/bobzhang/asciidoctor) with
`moonx`, or build it from a checkout (`io` and the CLI run on the `native` and `wasm` targets):

```
moonx bobzhang/asciidoctor/cmd/asciidoctor@latest -b html5 -a toc doc.adoc
moon run --target native cmd/asciidoctor -- -b html5 -a toc doc.adoc
```

The CLI accepts Ruby's options with OptionParser's syntax (`--backend=html5`, abbreviations such
as `--back`, clustered short options such as `-sn`, `--`) and reports errors and exit codes like
Ruby, including `-t` timings, `-R`/`-D` output directories and standard input (`-`). Custom
templates (`-T`) and Ruby libraries (`-r`) are not supported.

## Syntax highlighting

`source-highlighter` selects an adapter (`@core.SyntaxHighlighter`, Ruby's `SyntaxHighlighter`):

| name | kind | provided by |
|---|---|---|
| `highlight.js` (`highlightjs`), `prettify`, `html-pipeline` | client-side | `core` |
| `pygments` | server-side, with the [MoonBit port of Pygments](https://mooncakes.io/docs/bobzhang/pygments) | `highlighter/pygments` (optional) |
| `rouge`, `coderay` | not ported: they behave as in Ruby when their gems are missing | `core` |

The Pygments adapter is a port of Ruby's `pygments.rb` adapter (`pygments-style`, `pygments-css`
class or style, `pygments-linenums-mode` table or inline, highlighted lines, callouts, the
`pygments-<style>.css` stylesheet embedded in the document or, with `linkcss` and `copycss`, written
next to it). The lexers are large, so the package is not linked by the `@asciidoctor` facade; call
`register()` to use it. The CLI registers it at startup.

```mbt nocheck
///|
fn main {
  @pygments.register() // bobzhang/asciidoctor/highlighter/pygments
  let options = @core.Options::new(attributes=[
    ("source-highlighter", Str("pygments")),
  ])
  println(
    @asciidoctor.convert("[source,ruby]\n----\nputs 'hi'\n----", options~),
  )
}
```

## PDF

The PDF backend is a separate module in `pdf/`,
[`bobzhang/asciidoctor-pdf`](pdf/README.mbt.md): a port of Asciidoctor PDF 2.3.27 with its themes
and fonts bundled.

```
moonx bobzhang/asciidoctor-pdf/cmd/asciidoctor-pdf doc.adoc
```

It is licensed under the MIT license with Asciidoctor PDF's copyright notice, and bundles fonts
under their own licenses: see `pdf/LICENSE` and `pdf/NOTICE`.

## Status

Parity is measured against goldens harvested from the upstream Ruby test suite (2,961 documents with
their options, the files they read, an AST snapshot, every conversion output and the log messages):

| | passing |
|---|---|
| AST snapshots | 2593 / 2704 |
| converted outputs (HTML5, DocBook5, manpage) | 1763 / 1885 |
| log messages (severity, text, source location) | 2626 / 2702 |
| unexpected failures | 0 |

The remaining failures are catalogued in `tests/golden/known_failures.txt`: tests of Ruby's extension
DSL (equivalent scenarios are tested in `extensions_test.mbt`), the Rouge and CodeRay syntax
highlighters, remote URIs, and tests that mutate the model through the Ruby API before converting
(those are hand-ported in `api_test.mbt`). The Pygments goldens are harvested with pygments.rb
running Python Pygments 2.21, the release `bobzhang/pygments` ports. About 900 hand-ported API tests
cover the reader, parser, substitutions, path resolver, attribute lists, logging and the document
API.

In addition, 2,840 real-world documents convert byte-identically to Ruby — output, warnings and
exit status — with all three backends (`scripts/corpus.mbtx`), and with Pygments highlighting for
HTML5, embedded and standalone (`--pygments`): the documentation of Asciidoctor, asciidoctor-pdf,
-diagram, -epub3 and AsciidoctorJ, the Pro Git book, Git's manual pages and release notes, the
Quarkus, Spring Boot, Hibernate ORM and Debezium docs, and the AsciiDoc language specification
(`scripts/fetch_corpora.mbtx` clones them at pinned commits). The only differences are three tables
where Ruby itself crashes (manpage).

## Layout

| path | contents |
|---|---|
| `regex/` | backtracking regex engine with Ruby (Onigmo) semantics over UTF-16 |
| `internal/rb/` | Ruby-compatible string and number helpers (strip, split, succ, `Float#to_s`, Unicode case mapping) |
| `core/` | document model, reader/preprocessor, parser, substitutions, extensions API, converter interface |
| `converter/html5`, `converter/docbook5`, `converter/manpage` | converters |
| `highlighter/pygments` | server-side syntax highlighting with Pygments (optional, links `bobzhang/pygments`) |
| `io/` | async file-system integration (`load_file`, `convert_file`, `convert_source`) |
| `cmd/asciidoctor` | CLI |
| `cmd/golden`, `scripts/` | golden harvesting/replay, regex oracle, corpus comparison |
| `pdf/` | the PDF backend, a module of its own (`bobzhang/asciidoctor-pdf`) |
| `tests/pdf_golden/` | conversions harvested from asciidoctor-pdf's RSpec suite (`scripts/pdf_harvest.mbtx`) |

## Development

Scripts are MoonBit scripts (`.mbtx`), run with `moon run --target native`. The Ruby files under
`scripts/` only drive Ruby Asciidoctor itself (the oracle).

```
moon run --target native scripts/check.mbtx               # check/test on all targets + golden parity
moon run --target native scripts/check.mbtx -- --corpus   # also compare the corpora with Ruby
moon run --target native scripts/corpus.mbtx -- -v        # corpus comparison only
moon run --target native scripts/corpus.mbtx -- -b html5 --pygments --standalone  # with Pygments
moon run --target native scripts/cli_parity.mbtx -- -v    # CLI vs Ruby: exit code, stdout, stderr, files
moon run --target native scripts/harvest.mbtx             # regenerate goldens (needs Ruby + nokogiri, python3)
moon run --target native cmd/golden -- -v -n 20           # golden replay with failure details
moon run --target native cmd/golden -- --prune-known      # drop fixed entries from known_failures.txt
```

The PDF backend (`pdf/`) is checked with `moon -C pdf check --target all` and
`moon -C pdf test --target native`, and compared with Ruby asciidoctor-pdf by
`scripts/pdf_compare.mbtx`. The comparison needs Ruby (the `ruby` path at the top of the script)
with the asciidoctor-pdf 2.3.27 gems installed in `.repos/gems-pdf`
(`gem install --install-dir .repos/gems-pdf asciidoctor-pdf -v 2.3.27`), the
asciidoctor-pdf sources in `.repos/asciidoctor-pdf` and poppler (`pdftotext`, `pdftoppm`,
`pdfinfo`):

```
moon run --target native scripts/pdf_compare.mbtx -- --gate          # 36 documents, must all pass
moon run --target native scripts/pdf_compare.mbtx -- --self-test     # the metrics flag corrupted PDFs
moon run --target native scripts/pdf_compare.mbtx -- --spec-goldens  # asciidoctor-pdf's spec suite
moon run --target native scripts/pdf_harvest.mbtx                    # re-harvest the spec suite
moon run --target native scripts/pdf_bundle_fonts.mbtx               # regenerate pdf/fonts from the gems
```

The upstream sources are expected in `.repos/asciidoctor` (`git clone --depth 1
https://github.com/asciidoctor/asciidoctor .repos/asciidoctor`); extra corpora are cloned next to it.
