///|
/// Load `yaml` as the theme of the conversion (over the default theme when
/// it says so), prepared.
fn use_theme(yaml : String) -> Unit raise {
  let theme = @theme.load_text(yaml)
  prepare_theme(theme)
  current_theme.val = theme
  font_scope.val = None
}

///|
fn test_doc(source : String) -> @core.Node {
  register()
  @asciidoctor.load(
    source,
    options=@core.Options::new(backend="pdf", standalone=true),
  )
}

///|
test "page setup: size, layout and margins from the theme and attributes" {
  use_theme(
    (
      #|page:
      #|  size: Letter
      #|  layout: landscape
      #|  margin: [0.5in, 1in]
    ),
  )
  let setup = resolve_page_setup(test_doc("= Doc\n\ntext"))
  debug_inspect(
    (
      setup.width,
      setup.height,
      setup.margin_top,
      setup.margin_right,
      setup.margin_bottom,
      setup.margin_left,
    ),
    content="(792, 612, 36, 72, 36, 72)",
  )
  // the attributes win
  let setup = resolve_page_setup(
    test_doc(
      "= Doc\n:pdf-page-size: [8.5in, 11in]\n:pdf-page-layout: portrait\n:pdf-page-margin: 18\n\ntext",
    ),
  )
  debug_inspect(
    (setup.width, setup.height, setup.margin_top, setup.margin_left),
    content="(612, 792, 18, 18)",
  )
}

///|
test "running content columns" {
  use_theme(
    (
      #|footer:
      #|  columns: <40% =20% >40%
    ),
  )
  let columns = periphery_columns("footer", "recto", 500.0)
  debug_inspect(
    columns.map(c => (c.0, c.2, c.3)),
    content=(
      #|[("left", 0, 200), ("center", 200, 100), ("right", 300, 200)]
    ),
  )
  use_theme("")
  debug_inspect(
    periphery_columns("footer", "recto", 500.0).map(c => c.3),
    content="[500, 500, 500]",
  )
}

///|
test "theme fonts: categories, heading levels and relative sizes" {
  use_theme(
    (
      #|base:
      #|  font-family: Body
      #|  font-size: 10
      #|  font-color: 333333
      #|heading:
      #|  font-style: bold
      #|  h2-font-size: 20
      #|  font-color: [0, 0, 255]
      #|code:
      #|  font-size: 0.9em
      #|  font-style: italic
    ),
  )
  let (h2, _) = heading_font(2)
  debug_inspect(
    (h2.family, h2.size, h2.bold, h2.color == rgb_hex(0x0000FF)),
    content=(
      #|("Body", 20, true, true)
    ),
  )
  // a level without a size of its own takes the root size
  inspect(heading_font(3).0.size, content="10")
  let (code, _) = category_font("code")
  debug_inspect(
    (code.size, code.doc_italic, code.color == rgb_hex(0x333333)),
    content="(9, true, true)",
  )
}

///|
test "text of running content: attributes, unresolved lines dropped" {
  let doc = test_doc("= Doc\n:company: ACME\n\ntext")
  inspect(
    apply_subs_discretely(doc, "{company}\nsecond {missing} line\nthird"),
    content=(
      #|ACME
      #|third
    ),
  )
}
