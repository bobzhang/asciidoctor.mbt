# asciidoctor-pdf for MoonBit

A port of [Asciidoctor PDF](https://github.com/asciidoctor/asciidoctor-pdf) 2.3.27 to
[MoonBit](https://www.moonbitlang.com): the PDF backend of
[asciidoctor.mbt](https://github.com/bobzhang/asciidoctor.mbt). It converts AsciiDoc to PDF the way
Ruby `asciidoctor-pdf` does (same themes, same fonts, same page layout), on top of the
[`moonbitlang/pagelayout`](https://mooncakes.io/docs/moonbitlang/pagelayout) layout engine and
[`moonbitlang/pdflite`](https://mooncakes.io/docs/moonbitlang/pdflite).

* Runs on the `native` and `wasm` targets.
* Self-contained: asciidoctor-pdf's themes and the fonts they use (Noto Serif, M+ 1mn, Noto Sans,
  M+ 1p Fallback, Noto Emoji) and prawn-icon's icon fonts (Font Awesome 5, Foundation Icons,
  PaymentFont) are bundled; no Ruby, gem or font files are needed.

## Command line

Run the `asciidoctor-pdf` command with [`moonx`](https://www.moonbitlang.com) (no installation, the
`wasm` build):

```
moonx bobzhang/asciidoctor-pdf/cmd/asciidoctor-pdf doc.adoc
```

or build it natively from a checkout of the repository:

```
moon -C pdf build --target native --release
pdf/_build/native/release/build/bobzhang/asciidoctor-pdf/cmd/asciidoctor-pdf/asciidoctor-pdf.exe doc.adoc
```

It takes Ruby `asciidoctor-pdf`'s options (Asciidoctor's command line with the `pdf` backend):

```
asciidoctor-pdf doc.adoc                       # writes doc.pdf next to doc.adoc
asciidoctor-pdf -o out.pdf doc.adoc            # -o - writes the PDF to standard output
asciidoctor-pdf -D build -a toc doc.adoc       # writes build/doc.pdf
asciidoctor-pdf --theme default-sans doc.adoc  # or -a pdf-theme=my-theme.yml -a pdf-themesdir=themes
asciidoctor-pdf -d book -S safe doc.adoc
cat doc.adoc | asciidoctor-pdf - > doc.pdf     # standard input to standard output
asciidoctor-pdf --help                         # all options
```

Messages and exit codes follow Asciidoctor: log messages go to standard error
(`asciidoctor: WARNING: ...`), `--failure-level WARN` makes warnings fail the run, an invalid option
or a missing input fails with exit code 1. Content the port does not render yet is reported on
standard error as `asciidoctor-pdf: UNSUPPORTED <what> at <file>:<line>`.

## Library

Register the `pdf` backend, load the document with the `pdf` backend, then convert it to the
bytes of the PDF:

```mbt check
///|
test "convert a document to PDF" {
  @asciidoctor_pdf.register()
  let doc = @asciidoctor.load(
    (
      #|= Hello, PDF
      #|
      #|A paragraph with *strong* text.
    ),
    options=@core.Options::new(backend="pdf", standalone=true),
  )
  let pdf = @asciidoctor_pdf.convert(doc)
  assert_eq(pdf[0:5].to_owned(), b"%PDF-")
}
```

Files the document refers to (includes, images, themes) are read through the document's `Vfs`
(`@core.Options::new(vfs=...)`); `bobzhang/asciidoctor/io` provides one backed by the file system
(see `cmd/asciidoctor-pdf`).

`register` takes the fonts the themes find in asciidoctor-pdf's font directory (`GEM_FONTS_DIR`).
By default these are the default theme's (`@fonts.default_fonts()`, package
`bobzhang/asciidoctor-pdf/fonts`); the fonts of the other bundled themes and the icon fonts are in
packages of their own, so a program links only what it registers:

| Package | Fonts | Needed for |
| --- | --- | --- |
| `bobzhang/asciidoctor-pdf/fonts` | Noto Serif, M+ 1mn | the `default` theme (always) |
| `bobzhang/asciidoctor-pdf/fonts/sans` | Noto Sans | `default-sans` |
| `bobzhang/asciidoctor-pdf/fonts/fallback` | M+ 1p Fallback, Noto Emoji | `default-with-font-fallbacks` |
| `bobzhang/asciidoctor-pdf/fonts/icons` | Font Awesome 5, Foundation Icons, PaymentFont | `icons=font` |

```mbt check
///|
test "a theme with fonts of another package" {
  @asciidoctor_pdf.register(fonts=[@bundled.default_fonts(), @sans.fonts()])
  let doc = @asciidoctor.load(
    "Set in Noto Sans.",
    options=@core.Options::new(backend="pdf", standalone=true, attributes=[
      ("pdf-theme", Str("default-sans")),
    ]),
  )
  assert_eq(@asciidoctor_pdf.convert(doc)[0:5].to_owned(), b"%PDF-")
}
```

`register(fonts_dir=DIR)` reads them from a directory instead (a copy of the gem's `data/fonts`),
`register(icon_fonts_dir=DIR)` the icon fonts (prawn-icon's `data/fonts`), and
`register(catalog=...)` sets every document in a `FontCatalog` of your own. Fonts a theme names by
a path of its own (`pdf-fontsdir`, a font next to the theme file) are read through the document's
`Vfs`, as in Ruby.

## What is supported

The converter follows asciidoctor-pdf 2.3.27's converter and theme loader: every bundled theme and
custom YAML themes (`extends`, variables, math, colors, `pdf-themesdir`, `pdf-fontsdir`), title
page, table of contents, sections and parts, running headers and footers, paragraphs and inline
formatting, lists (including checklists and callouts), tables, admonitions, quotes, verses,
sidebars, examples, listings and literals, images (PNG, JPEG, SVG), font icons, footnotes, index,
links and cross references, outline (bookmarks), page backgrounds and watermarks, page breaks,
`media=print`/`prepress`, manpage and book doctypes, and the PDF info (title, author, dates,
`SOURCE_DATE_EPOCH`).

It is measured against Ruby asciidoctor-pdf 2.3.27 by `scripts/pdf_compare.mbtx` in the
repository, which converts with both and compares page count, text, the position of every word
(±1pt), rasterized pages and PDF structure:

* the gate (36 documents covering every feature above): 36 / 36 identical within the thresholds;
* the conversions of asciidoctor-pdf's own RSpec suite: 1977 / 2329 pass (the rest are listed with
  their reason in the repository's `tests/pdf_golden/known_failures.txt`);
* a corpus of 2,840 real-world documents: 2772 pass.

## Known differences from Ruby asciidoctor-pdf

* No source highlighting: `source-highlighter` (Rouge, Pygments, CodeRay) is ignored and listings
  are set in plain text.
* AsciiDoc table cells (`a|`), video poster images, GIF/BMP/TIFF and PDF images (`image::x.pdf[]`)
  are not rendered; image icons (`icons` other than `font`) show their alt text.
* A few theme keys are ignored: `abstract_padding`, caption backgrounds,
  `heading_min_height_after: auto`, `footnotes-title`.
* SVG text in a font the theme's catalog does not have is set in the base font.
* No Ruby extensions, converter subclasses or custom templates (`-r`, `-T`); `-r asciidoctor-pdf`
  is accepted (it is built in). No `asciidoctor-pdf-optimize`.
* The PDF's Producer names this port (`Asciidoctor PDF 0.1.0 (MoonBit), based on pagelayout`).

## License

MIT (see LICENSE). This is a port of Asciidoctor PDF, Copyright (C) 2014-present OpenDevise Inc.
and the Asciidoctor Project (MIT). The bundled fonts keep their own licenses (Apache 2.0, SIL OFL
1.1, M+ FONTS, MIT); see NOTICE and `fonts/LICENSES`.
