///|
/// Load `text` for the `pdf` backend, reproducibly (no dates).
fn load_pdf(text : String) -> @core.Node {
  @asciidoctor.load(
    text,
    options=@core.Options::new(backend="pdf", standalone=true, attributes=[
      ("reproducible", Str("")),
    ]),
  )
}

///|
/// A document in the base theme (12pt text), with what keeps state across
/// its load and conversion: index terms, footnotes, bibliography
/// references.
let doc_a : String =
  #|= Document A
  #|:doctype: book
  #|:pdf-theme: base
  #|
  #|== Chapter
  #|
  #|A paragraph about ((apples)) and ((pears)).footnote:[A note in A.]
  #|See <<ref-a>>.
  #|
  #|[bibliography]
  #|== References
  #|
  #|* [[[ref-a]]] A reference.
  #|
  #|[index]
  #|== Index
  #|

///|
/// A document in the default theme (10.5pt text), with state of its own.
let doc_b : String =
  #|= Document B
  #|:doctype: book
  #|
  #|== First
  #|
  #|Text with ((bananas)).footnote:[The first note of B.]
  #|footnote:[The second note of B.]
  #|
  #|== Second
  #|
  #|More ((cherries)).footnote:[The third note of B.]
  #|
  #|[index]
  #|== Index
  #|

///|
test "documents loaded one after the other keep their own state" {
  register()
  // each alone
  let alone_a = convert_document(load_pdf(doc_a), test_catalog())
  let warnings_a = conversion_warnings()
  let alone_b = convert_document(load_pdf(doc_b), test_catalog())
  // loaded A then B, converted B then A
  let a = load_pdf(doc_a)
  let b = load_pdf(doc_b)
  let interleaved_b = convert_document(b, test_catalog())
  let interleaved_a = convert_document(a, test_catalog())
  inspect(interleaved_a == alone_a, content="true")
  inspect(interleaved_b == alone_b, content="true")
  inspect(conversion_warnings() == warnings_a, content="true")
  // and the base theme's 12pt text is not the default theme's 10.5pt
  inspect(alone_a == alone_b, content="false")
}

///|
test "a theme warning given while loading is reported by the conversion" {
  register()
  // the section title is converted while the document is loaded, its
  // quotes from the theme
  let doc = load_pdf(
    "= Title\n:pdf-theme: no-such\n\n== A \"`quoted`\" title\n\ntext\n",
  )
  // another document loaded in between
  ignore(load_pdf("other"))
  ignore(convert_document(doc, test_catalog()))
  inspect(
    conversion_warnings().join("\n"),
    content=(
      #|WARNING could not locate or load the built-in pdf theme `no-such' because of No such file or directory @ rb_sysopen - /asciidoctor-pdf/data/themes/no-such-theme.yml; reverting to default theme at <document>
    ),
  )
}

///|
test "an unknown base font is reported, and Helvetica stands in" {
  register(pdf_theme=files => {
    let theme = @theme.load_theme(files)
    theme["base_font_family"] = Str("No Such Font")
    theme
  })
  let pdf = convert_document(load_pdf("text\n\n*bold*\n"), test_catalog())
  register()
  inspect(pdf.length() > 0, content="true")
  inspect(
    conversion_warnings().join("\n"),
    content=(
      #|WARNING No Such Font (normal) is not a known font; using Helvetica instead at <document>
      #|WARNING No Such Font (bold) is not a known font; using Helvetica instead at <document>
    ),
  )
}

///|
test "a document keeps the fonts registered when it was loaded" {
  register()
  let before = load_pdf("text\n")
  // registered after `before` was loaded: no bundled fonts at all
  register(fonts=[])
  let after = load_pdf("text\n")
  register()
  activate_session(before)
  ignore(document_catalog(before))
  activate_session(after)
  try document_catalog(after) catch {
    e =>
      inspect(
        e
        .to_string()
        .contains(
          "font /asciidoctor-pdf/data/fonts/notoserif-regular-subset.ttf not found in GEM_FONTS_DIR",
        ),
        content="true",
      )
  } noraise {
    _ => fail("expected the fonts not to be found")
  }
}

///|
test "icon fonts are loaded for icons=font set in the body" {
  register(icon_fonts=@icons.fonts())
  // the entry takes effect only as the conversion reaches the paragraph
  // (safe mode, so that the document may set `icons`)
  let doc = @asciidoctor.load(
    "= Title\n\n:icons: font\n\nicon:heart[] text\n",
    options=@core.Options::new(backend="pdf", standalone=true, safe=1, attributes=[
      ("reproducible", Str("")),
    ]),
  )
  register()
  inspect(doc.attr("icons") is None, content="true")
  activate_session(doc)
  inspect(document_catalog(doc).has_icons(), content="true")
}

///|
test "a document keeps the icon fonts registered when it was loaded" {
  // `icons` is locked in the API's secure safe mode: set it from outside
  let load_icons = () => {
    @asciidoctor.load(
      "icon:heart[]\n",
      options=@core.Options::new(backend="pdf", standalone=true, attributes=[
        ("reproducible", Str("")),
        ("icons", Str("font")),
      ]),
    )
  }
  register(icon_fonts=@icons.fonts())
  let with_icons = load_icons()
  register()
  let without_icons = load_icons()
  activate_session(with_icons)
  inspect(document_catalog(with_icons).has_icons(), content="true")
  activate_session(without_icons)
  inspect(document_catalog(without_icons).has_icons(), content="false")
  // the icon fonts are loaded only for the documents that use them
  register(icon_fonts=@icons.fonts())
  let plain = load_pdf("no icons here\n")
  register()
  activate_session(plain)
  inspect(document_catalog(plain).has_icons(), content="false")
}

///|
test "a document's flow hooks work in its own session" {
  register()
  let a = load_pdf(doc_a)
  let b = load_pdf(doc_b)
  // A's hooks, made while A is active
  activate_session(a)
  let session_a = session()
  let hooks_a = document_hooks()
  // then B becomes the active document
  activate_session(b)
  let session_b = session()
  (hooks_a.unknown_font)("No Such Font (normal)")
  (hooks_a.unknown_font)("No Such Font (normal)")
  (hooks_a.anchor_inked)("__indexterm-1", 3)
  // A's state took the calls, reported once; B is still active and untouched
  inspect(physical_equal(session(), session_b), content="true")
  inspect(
    session_a.unknown_fonts.contains("No Such Font (normal)"),
    content="true",
  )
  inspect(
    session_b.unknown_fonts.contains("No Such Font (normal)"),
    content="false",
  )
  debug_inspect(
    session_a.pending_diagnostics
    .filter(d => d.contains("No Such Font"))
    .length(),
    content="1",
  )
  debug_inspect(
    session_b.pending_diagnostics.filter(d => d.contains("No Such Font")),
    content="[]",
  )
}

///|
test "a document's image hooks size images against its own page" {
  register()
  let a = load_pdf(doc_a)
  let b = load_pdf(doc_b)
  activate_session(a)
  let session_a = session()
  // a 600pt content area in A, 200pt in B
  session_a.page_setup = {
    width: 400.0,
    height: 700.0,
    margin_top: 50.0,
    margin_right: 50.0,
    margin_bottom: 50.0,
    margin_left: 50.0,
  }
  session_a.inline_images.push({
    data: b"",
    mime: "image/png",
    px_w: 100,
    px_h: 400,
    width: "100",
    fit: None,
    svg: None,
    dropped: None,
    warned: false,
  })
  let hooks_a = document_hooks()
  activate_session(b)
  session().page_setup = { ..session_a.page_setup, height: 300.0, }
  // 100pt wide, 400pt tall: fits A's 600pt, would shrink to 200pt in B
  debug_inspect(
    (hooks_a.image_size)(0, 500.0, 12.0),
    content="(100, 400, true)",
  )
}
