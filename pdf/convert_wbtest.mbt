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
