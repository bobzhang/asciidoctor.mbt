# asciidoctor-pdf for MoonBit

A port of [Asciidoctor PDF](https://github.com/asciidoctor/asciidoctor-pdf) 2.3.27 to
[MoonBit](https://www.moonbitlang.com): the PDF backend of
[asciidoctor.mbt](https://github.com/bobzhang/asciidoctor.mbt). It converts AsciiDoc to PDF the way
Ruby `asciidoctor-pdf` does (same themes, same fonts, same page layout), on top of the
[`moonbitlang/pagelayout`](https://mooncakes.io/docs/moonbitlang/pagelayout) layout engine and
[`moonbitlang/pdflite`](https://mooncakes.io/docs/moonbitlang/pdflite).

* Runs on the `native` and `wasm` targets.
* Self-contained: asciidoctor-pdf's themes and the fonts they use (Noto Serif, M+ 1mn, Noto Sans,
  M+ 1p Fallback, Noto Emoji) and the icon fonts prawn-icon draws with (Font Awesome 5, Foundation Icons,
  PaymentFont) are bundled; no Ruby, gem or font files are needed.

## Command line

Run the `asciidoctor-pdf` command with [`moonx`](https://www.moonbitlang.com) (no installation, the
`wasm` build):

```
moonx bobzhang/asciidoctor-pdf/cmd/asciidoctor-pdf doc.adoc
```

It highlights source blocks with Rouge. `source-highlighter: pygments` needs the same command with
Pygments linked in, which is larger:

```
moonx bobzhang/asciidoctor-pdf/cmd/asciidoctor-pdf-pygments doc.adoc
```

| Command | wasm | native (macOS arm64) |
| --- | --- | --- |
| `cmd/asciidoctor-pdf` (Rouge) | 18.8 MB | 25.4 MB |
| `cmd/asciidoctor-pdf-pygments` (Rouge and Pygments) | 28.7 MB | 43.7 MB |

or build them natively from a checkout of the repository:

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
(see the package `bobzhang/asciidoctor-pdf/cli`, the command line).

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

## Source highlighting

`source-highlighter: rouge` works out of the box: the package `bobzhang/asciidoctor-pdf/rouge` is a
port of Rouge 3.30 (the version asciidoctor-pdf's own tests run with), its lexer core, its themes
(`rouge-style`) and, token for token, these lexers: apache, batchfile, c, coffeescript, conf,
console, cpp, csharp, css, d, dart, diff, docker, elixir, erb, go, gradle, groovy, haskell, html, ini,
irb, java, javascript, json, json-doc, jsx, kotlin, lua, make, markdown, matlab, nginx, perl, php,
plaintext, powershell, properties, protobuf, python, r, ruby, rust, sass, scala, scss, shell, sql,
swift, toml, tsx, typescript, vue, xml and yaml (with their aliases). A language Rouge does not know,
or one not ported yet, is set as plain text. Line numbers (`linenums`, `start`), highlighted lines
(`highlight`) and callouts are laid out as asciidoctor-pdf does. As in Ruby, the `secure` safe mode (the
API's default) turns `source-highlighter` off.

`source-highlighter: pygments` needs Pygments, which is in a package of its own
(`bobzhang/asciidoctor-pdf/pygments`, on [`bobzhang/pygments`](https://mooncakes.io/docs/bobzhang/pygments),
a port of Pygments 2.21) so that a program links it only when it asks for it; the command
`cmd/asciidoctor-pdf-pygments` does:

```mbt nocheck
@pygments.register() // package bobzhang/asciidoctor-pdf/pygments
```

`source-highlighter: coderay` is not supported (listings are set in plain text).

## What is supported

The converter follows asciidoctor-pdf 2.3.27's converter and theme loader: every bundled theme and
custom YAML themes (`extends`, variables, math, colors, `pdf-themesdir`, `pdf-fontsdir`), title
page, table of contents, sections and parts, running headers and footers, paragraphs and inline
formatting, lists (including checklists and callouts), tables, admonitions, quotes, verses,
sidebars, examples, listings and literals, images (PNG, JPEG, SVG, and PDF: `image::x.pdf[page=2]`
imports the page on a page of its own, as do PDF covers and page backgrounds), font icons,
footnotes, index, links and cross references, outline (bookmarks), page backgrounds and
watermarks, page breaks, `media=print`/`prepress`, manpage and book doctypes, and the PDF info
(title, author, dates, `SOURCE_DATE_EPOCH`).

It is measured against Ruby asciidoctor-pdf 2.3.27 by `scripts/pdf_compare.mbtx` in the
repository, which converts with both and compares page count, text, the position of every word
(±1pt), rasterized pages and PDF structure:

* the gate (38 documents covering every feature above): 38 / 38 identical within the thresholds;
* the conversions of asciidoctor-pdf's own RSpec suite: 2097 / 2415 pass (the rest are listed with
  their reason in the repository's `tests/pdf_golden/known_failures.txt`);
* a corpus of 2,840 real-world documents: 2772 pass.

## Known differences from Ruby asciidoctor-pdf

* No CodeRay highlighting, and only the Rouge lexers listed above (see Source highlighting).
* AsciiDoc table cells (`a|`), video poster images and GIF/BMP/TIFF images are not rendered;
  image icons (`icons` other than `font`) show their alt text.
* A PDF page imported as an image keeps its drawing but not its links or other annotations.
  Ruby gives the pages after a PDF front cover that cannot be imported, or after a PDF background
  on the first page, Prawn's default 36pt margins; this port keeps the theme's.
* A few theme keys are ignored: `abstract_padding`, caption backgrounds,
  `heading_min_height_after: auto`, `footnotes-title`.
* SVG text in a font the theme's catalog does not have is set in the base font.
* No Ruby extensions, converter subclasses or custom templates (`-r`, `-T`); `-r asciidoctor-pdf`
  is accepted (it is built in). No `asciidoctor-pdf-optimize`.
* The PDF's Producer names this port (`Asciidoctor PDF 0.1.0 (MoonBit), based on pagelayout`).

## Changes

### 0.2.1

* **Images** that 0.2.0 drew wrongly, or left out with an `UNSUPPORTED image` warning, are
  embedded (pdflite 0.3.7):
  * greyscale and CMYK JPEGs in their own colour space (they were written as RGB), progressive
    JPEGs and JPEGs without a JFIF header (left out);
  * 16-bit PNGs with an alpha channel and palette PNGs with transparency (left out), and the
    transparent colour of a greyscale or truecolour PNG (drawn opaque).
* **Characters beyond the Basic Multilingual Plane** (emoji, CJK extensions) are set with the
  glyphs of a font that has them, such as the fallback font's emoji (they were empty boxes).
* **Layout**: `bobzhang/prawn` 0.2.0. With the standard (AFM) fonts, as in the base theme, pairs
  with an accented letter (`Té`, `Vé`, `Yó`) kern as in Ruby; they were not kerned, which moved the
  rest of the line.
* **Fidelity**: asciidoctor-pdf's spec suite replays as before, 2097 of 2415 records
  identically. The two emoji examples now render as Ruby's do; they still count as different,
  because Ruby's PDF gives the emoji other characters when its text is extracted.

### 0.2.0

* **Source highlighting**:
  * Rouge, through a port of Rouge 3.30 (its lexer engine, themes and 56 lexers, checked token by
    token against Ruby Rouge), as asciidoctor-pdf's `convert_code` uses it: `linenums`,
    `highlight` line ranges, callouts, PHP `start_inline`, the highlighter's background and
    colours, and line numbering that wraps as asciidoctor-pdf's `SourceWrap` does.
  * Pygments too, through bobzhang/pygments, when registered (`bobzhang/asciidoctor-pdf/pygments`).
* **Commands**: `cmd/asciidoctor-pdf` highlights with Rouge only. The larger
  `cmd/asciidoctor-pdf-pygments` registers Pygments as well.
* **PDF files** as block images (`page=`, `pages=`), front and back covers and page backgrounds,
  imported as vector graphics (pdflite 0.3.2 / pagelayout 0.7.1). An unreadable PDF fails the
  conversion with `TemplateError` (a background warns instead).
* **Layout**: the layout moved to its own module, `bobzhang/prawn`. This breaks code that imports
  `bobzhang/asciidoctor-pdf/svg`, which is now `bobzhang/prawn/svg`. `FontCatalog`, `IconSet`,
  `default_font_files` and `default_icon_font_files` are re-exported, so `register(catalog=...)`
  and `convert_document` are used as before.
* **Fidelity**: asciidoctor-pdf's spec suite replays 2097 of 2415 records identically (0.1.0:
  1978 of 2329, before the harvest also recorded the highlighting examples).

### 0.1.0

* First release.

## License

MIT (see LICENSE). This is a port of Asciidoctor PDF, Copyright (C) 2014-present OpenDevise Inc.
and the Asciidoctor Project (MIT). The bundled fonts keep their own licenses (Apache 2.0, SIL OFL
1.1, M+ FONTS, MIT), and the icon names come from the icon fonts' own projects; see NOTICE and
`fonts/LICENSES`.
