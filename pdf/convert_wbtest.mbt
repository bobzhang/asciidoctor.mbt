///|
/// A catalog that stands pagelayout's bundled Liberation faces in for the
/// theme's fonts, so the test needs no font files.
fn test_catalog() -> FontCatalog raise {
  let files = []
  for entry in default_font_files() {
    let (family, bold, italic, _) = entry
    let bundled = if family == "M+ 1mn" {
      "Liberation Mono"
    } else {
      "Liberation Serif"
    }
    files.push(
      (
        family,
        bold,
        italic,
        @fontoutlines.outline_sfnt(bundled, bold~, italic~).unwrap(),
      ),
    )
  }
  FontCatalog::load(files)
}

///|
test "a document converts to a paginated pdf" {
  register()
  let catalog = test_catalog()
  let body = StringBuilder()
  body.write_string("= Title\n\n== Section\n\n")
  for i in 0..<120 {
    body.write_string(
      "Paragraph \{i} with *bold* and a https://example.org[link].\n\n",
    )
  }
  body.write_string("----\ncode\n----\n")
  let doc = @asciidoctor.load(
    body.to_string(),
    options=@core.Options::new(backend="pdf", standalone=true),
  )
  let pdf = convert_document(doc, catalog)
  let document = @pdflite.pdf_read_document_from_bytes(pdf)
  inspect(document.pages_of_pagetree().length() > 1, content="true")
}

///|
test "inline markup becomes styled fragments" {
  let fragments = parse_formatted(
    "a <strong>b</strong> <a href=\"https://x\">c</a>&#8217;s",
    Style::new(),
  )
  let described = fragments.map(fn(f) {
    let link = f.style.link.unwrap_or("-")
    "[\{f.text}] bold=\{f.style.bold} link=\{link}"
  })
  inspect(
    described.join("; "),
    content=(
      #|[a ] bold=false link=-; [b] bold=true link=-; [ ] bold=false link=-; [c] bold=false link=https://x; [’s] bold=false link=-
    ),
  )
}

///|
test "unsupported blocks and inline nodes are reported with their location" {
  register()
  let catalog = test_catalog()
  let doc = @asciidoctor.load(
    "= Title\n\nSee image:logo.png[Logo] here.\n\nvideo::intro.mp4[]\n\n++++\n<b>raw</b>\n++++\n",
    options=@core.Options::new(backend="pdf", standalone=true, sourcemap=true),
  )
  ignore(convert_document(doc, catalog))
  inspect(
    conversion_warnings().join("\n"),
    content=(
      #|UNSUPPORTED inline image at <stdin>:3
      #|UNSUPPORTED block video at <stdin>:5
      #|UNSUPPORTED block pass at <stdin>:7
    ),
  )
  // a new conversion starts a new report
  ignore(
    convert_document(
      @asciidoctor.load("plain", options=@core.Options::new(backend="pdf")),
      catalog,
    ),
  )
  inspect(conversion_warnings().length(), content="0")
}

///|
test "information dictionary dates follow Prawn's form" {
  inspect(
    pdf_date_of_attribute("2026-09-29 15:12:28 +0800").unwrap_or("-"),
    content="D:20260929151228+08'00'",
  )
  inspect(
    pdf_date_of_attribute("2019-01-02 03:04:05 UTC").unwrap_or("-"),
    content="D:20190102030405+00'00'",
  )
  inspect(
    pdf_date_of_attribute("2019-01-02 03:04:05 -0530").unwrap_or("-"),
    content="D:20190102030405-05'30'",
  )
  inspect(pdf_date_of_attribute("yesterday").unwrap_or("-"), content="-")
}

///|
test "document info, top anchor and outline levels" {
  register()
  let doc = @asciidoctor.load(
    "= Title\nJane Doe; John Roe\n:publisher: ACME\n:keywords: a, b\n:outlinelevels: 3:1\n:reproducible:\n\ntext\n",
    options=@core.Options::new(backend="pdf", standalone=true),
  )
  inspect(
    pdf_info(doc).map(entry => "\{entry.0}=\{entry.1}").join("; "),
    content="Title=Title; Author=Jane Doe, John Roe; Keywords=a, b; Creator=ACME; Producer=asciidoctor.mbt (spike)",
  )
  inspect(top_anchor(doc), content="__anchor-top")
  let (num, expand) = outline_levels(doc)
  inspect("\{num}:\{expand}", content="3:1")
  let plain = @asciidoctor.load(
    "= T\n:toclevels: 3\n\nx\n",
    options=@core.Options::new(backend="pdf"),
  )
  let (num, expand) = outline_levels(plain)
  inspect("\{num}:\{expand}", content="3:3")
}

///|
test "destination names and the untitled document title follow asciidoctor-pdf" {
  inspect(pdf_anchor_name("_intro"), content="_intro")
  inspect(pdf_anchor_name("test-é"), content="0x746573742dc3a9")
  register()
  let untitled = @asciidoctor.load(
    "== Section\n\ntext\n",
    options=@core.Options::new(backend="pdf", standalone=true),
  )
  inspect(resolve_doctitle(untitled).unwrap_or("-"), content="Untitled")
  inspect(pdf_info(untitled)[0].1, content="Untitled")
}
