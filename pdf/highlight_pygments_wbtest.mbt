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
