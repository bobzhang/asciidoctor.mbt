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
writes the output next to the input, like `Asciidoctor.convert_file`.

```
moon build --target native cmd/asciidoctor
./_build/native/debug/build/cmd/asciidoctor/asciidoctor.exe -b html5 -a toc doc.adoc
```

The CLI supports the common Ruby options (`-b`, `-d`, `-a`, `-s`/`-e`, `-o`, `-D`, `-B`, `-S`, `-n`,
`--log-level`, `--failure-level`, `-q`, `-v`).

## Status

Parity is measured against goldens harvested from the upstream Ruby test suite (2,901 documents with
their options, the files they read, an AST snapshot and every conversion output):

| | passing |
|---|---|
| AST snapshots | 2506 / 2612 |
| converted outputs (HTML5, DocBook5, manpage) | 1705 / 1819 |
| unexpected failures | 0 |

The remaining failures are catalogued in `tests/golden/known_failures.txt`: tests of Ruby's extension
DSL (equivalent scenarios are tested in `extensions_test.mbt`), server-side syntax highlighters
(Rouge, CodeRay, Pygments — the client-side highlight.js, prettify and html-pipeline adapters are
supported; the server-side ones behave as Ruby does when their gems are missing), remote URIs, and
tests that mutate the model through the Ruby API before converting (those are hand-ported in
`api_test.mbt`). About 860 hand-ported API tests cover the reader, parser, substitutions, path
resolver, attribute lists, logging and the document API.

In addition, 506 real-world documents (the Asciidoctor, asciidoctor-pdf, -diagram, -epub3 and
AsciidoctorJ documentation and fixtures) convert byte-identically to Ruby — output and warnings —
with all three backends (`scripts/corpus.mbtx`). The only differences are two documents where Ruby
itself crashes or has no handler.

## Layout

| path | contents |
|---|---|
| `regex/` | backtracking regex engine with Ruby (Onigmo) semantics over UTF-16 |
| `internal/rb/` | Ruby-compatible string and number helpers (strip, split, succ, `Float#to_s`, Unicode case mapping) |
| `core/` | document model, reader/preprocessor, parser, substitutions, extensions API, converter interface |
| `converter/html5`, `converter/docbook5`, `converter/manpage` | converters |
| `io/` | async file-system integration (`load_file`, `convert_file`) |
| `cmd/asciidoctor` | CLI |
| `cmd/golden`, `scripts/` | golden harvesting/replay, regex oracle, corpus comparison |

## Development

Scripts are MoonBit scripts (`.mbtx`), run with `moon run --target native`. The Ruby files under
`scripts/` only drive Ruby Asciidoctor itself (the oracle).

```
moon run --target native scripts/check.mbtx               # check/test on all targets + golden parity
moon run --target native scripts/check.mbtx -- --corpus   # also compare the corpora with Ruby
moon run --target native scripts/corpus.mbtx -- -v        # corpus comparison only
moon run --target native scripts/harvest.mbtx             # regenerate goldens (needs Ruby + nokogiri)
moon run --target native cmd/golden -- -v -n 20           # golden replay with failure details
moon run --target native cmd/golden -- --prune-known      # drop fixed entries from known_failures.txt
```

The upstream sources are expected in `.repos/asciidoctor` (`git clone --depth 1
https://github.com/asciidoctor/asciidoctor .repos/asciidoctor`); extra corpora are cloned next to it.
