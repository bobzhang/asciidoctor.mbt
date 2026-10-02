///|
/// A Pygments backend whose styles all have the background `bg`.
fn fake_pygments(bg : String) -> PygmentsBackend {
  {
    find_lexer: _ => None,
    find_lexer_by_mimetype: _ => None,
    highlight: (_, _, _) => None,
    css: (_, _) => ".highlight { background: #\{bg}; }",
    styles: () => ["pastie"],
  }
}

///|
test "span styles of a syntax highlighter's HTML" {
  let fragments = parse_formatted(
    "<span style=\"color: #008800; font-weight: bold\">def</span> <span style=\"font-style: italic; background-color: #fff0f0\">s</span><span style=\"color: #abc\">c</span>",
    text_style(color=rgb_hex(0x333333)),
  )
  inspect(
    describe_fragments(fragments),
    content=(
      #|[def] 008800 b
      #|[ ] 333333
      #|[s] 333333 i @fff0f0
      #|[c] aabbcc
    ),
  )
}

///|
test "replacing the Pygments backend forgets the block colours it gave" {
  let first = fake_pygments("111111")
  register_pygments(first)
  let style = pygments_block_style(first, "pastie")
  inspect(style.background.map(hex6).unwrap_or("none"), content="111111")
  let second = fake_pygments("222222")
  register_pygments(second)
  let style = pygments_block_style(second, "pastie")
  inspect(style.background.map(hex6).unwrap_or("none"), content="222222")
  pygments_backend.val = None
  pygments_block_styles.clear()
}

///|
test "a Pygments style with no .hll background marks no line" {
  let backend = (css : String) => {
    (
      {
        find_lexer: _ => Some(("Ruby", "rb")),
        find_lexer_by_mimetype: _ => None,
        highlight: (source, _, _) => Some(source),
        css: (_, _) => css,
        styles: () => ["pastie"],
      } : PygmentsBackend)
  }
  let doc = load_safe(
    (
      #|[source,ruby,highlight=1]
      #|----
      #|puts 1
      #|----
    ),
  )
  let marks = (css : String) => {
    let b = backend(css)
    register_pygments(b)
    let (fragments, _, _, _) = pygments_chunks(
      b,
      doc.blocks[0],
      "puts 1",
      false,
      None,
      text_style(),
    )
    fragments
    .filter(f => f.style.line_mark)
    .map(f => f.style.background.map(hex6).unwrap_or("none"))
    .join(" ")
  }
  inspect(marks(".highlight { background: #f8f8f8; }"), content="")
  inspect(
    marks(
      ".highlight { background: #f8f8f8; }\n.highlight .hll { background-color: #ffffcc }",
    ),
    content="ffffcc",
  )
  pygments_backend.val = None
  pygments_block_styles.clear()
}

///|
test "a block of callouts alone keeps its callout with Pygments" {
  // unlike Rouge's, the Pygments branch formats the (empty) HTML into one
  // empty fragment, so restore_conums has a line to put the callout on
  let backend : PygmentsBackend = {
    find_lexer: _ => Some(("Ruby", "rb")),
    find_lexer_by_mimetype: _ => None,
    highlight: (source, _, _) => Some(source),
    css: (_, _) => ".highlight { background: #f8f8f8; }",
    styles: () => ["pastie"],
  }
  register_pygments(backend)
  let doc = load_safe("[source,ruby]\n----\n<1>\n----\n")
  let (fragments, _, _, _) = pygments_chunks(
    backend,
    doc.blocks[0],
    "<1>",
    true,
    None,
    text_style(),
  )
  inspect(fragments.map(f => f.text).join("|"), content="|①")
  pygments_backend.val = None
  pygments_block_styles.clear()
}
