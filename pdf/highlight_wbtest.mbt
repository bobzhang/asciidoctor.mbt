///|
/// A colour as six hex digits.
fn hex6(c : Color) -> String {
  let digits = fn(v : Int) {
    let s = v.to_string(radix=16)
    if s.length() < 2 {
      "0" + s
    } else {
      s
    }
  }
  digits(c.r) + digits(c.g) + digits(c.b)
}

///|
/// Fragments as `[text] color bold/italic`, plus `#` for a line number and
/// `@bg` for a line mark or a background.
fn describe_fragments(fragments : Array[Fragment]) -> String {
  fragments
  .map(f => {
    let s = f.style
    let text = f.text
      .replace_all(old="\u{a0}", new="~")
      .replace_all(old="\u{200b}", new="^")
      .replace_all(old="\n", new="\\n")
    let mut d = "[\{text}] \{hex6(s.color)}"
    if s.bold {
      d = d + " b"
    }
    if s.italic {
      d = d + " i"
    }
    if s.linenum {
      d = d + " #"
    }
    match s.background {
      Some(bg) => d = d + " @\{hex6(bg)}"
      None => ()
    }
    if s.line_mark {
      d = d + " mark"
    }
    d
  })
  .join("\n")
}

///|
test "extract_conums takes callouts out and remembers where they were" {
  let (text, conums) = extract_conums(
    "puts 1 <1>\nputs 2 # <2> <3>\nkeep \\<4>\nauto <.>",
  )
  inspect(text.escape(), content="\"puts 1\\nputs 2\\nkeep <4>\\nauto\"")
  let conums = conums.unwrap()
  let lines = conums.lines.keys().collect()
  lines.sort()
  debug_inspect(
    lines.map(l => (l, conums.lines[l])),
    content=(
      #|[
      #|  (0, (Some(" "), [1])),
      #|  (1, (Some(" "), [2, 3])),
      #|  (3, (Some(" "), [1])),
      #|]
    ),
  )
}

///|
test "the Rouge formatter colours tokens with asciidoctor-pdf's default theme" {
  use_theme("extends: default\n")
  let formatter = RougeFormatter::new(None)
  let tokens = @rouge.find("ruby").unwrap()(Map([])).tokens(
    "def hi\n  puts 'x' # c\nend",
  )
  inspect(
    describe_fragments(
      formatter.format(text_style(color=rgb_hex(0x333333)), tokens),
    ),
    content=(
      #|[def] 008800 b
      #|[ ] 333333
      #|[hi] 0066bb b
      #|[\n~ ] 333333
      #|[puts] 003388
      #|[ ] 333333
      #|['x'] dd2200
      #|[ ] 333333
      #|[# c] 888888
      #|[\n] 333333
      #|[end] 008800 b
    ),
  )
}

///|
test "line numbers are padded with no-break spaces and highlighted lines marked" {
  use_theme("extends: default\n")
  let formatter = RougeFormatter::new(None)
  let source = "a\nb\nc\nd\ne\nf\ng\nh\ni\nj"
  let tokens = @rouge.plain_text(Map([])).tokens(source)
  let fragments = formatter.format(
    text_style(color=rgb_hex(0x333333)),
    tokens,
    line_numbers=true,
    start_line=1,
    highlight_lines={ 2: true },
  )
  inspect(
    describe_fragments(fragments[:8].to_owned()),
    content=(
      #|[~1 ] 888888 #
      #|[a\n] 333333
      #|[~2 ] 888888 #
      #|[^] 333333 @ffffcc mark
      #|[b\n] 333333
      #|[~3 ] 888888 #
      #|[c\n] 333333
      #|[~4 ] 888888 #
    ),
  )
}

///|
test "restore_conums numbers the lines and puts the callouts back" {
  use_theme("conum:\n  font_color: B12146\n")
  let base = text_style(color=rgb_hex(0x333333))
  let (text, conums) = extract_conums("x <1>\ny")
  let fragments = restore_conums(
    [{ text, style: base, anchor: None, }],
    conums,
    base,
    linenums=9,
    highlight={ 10: rgb_hex(0xFFFFCC) },
  )
  inspect(
    describe_fragments(guard_indentation_in_fragments(fragments)),
    content=(
      #|[9 ] 999999 #
      #|[x] 333333
      #|[ ] 333333
      #|[①] b12146
      #|[\n] 333333
      #|[10 ] 999999 #
      #|[^] 333333 @ffffcc mark
      #|[y] 333333
    ),
  )
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
test "a numbered line that wraps continues behind a blank as wide as its number" {
  let catalog = test_catalog()
  let style = text_style(family="M+ 1mn", size=10.0)
  let fragments : Array[Fragment] = [
    { text: "1 ", style: { ..style, linenum: true, }, anchor: None, },
    { text: "x".repeat(30) + " " + "y".repeat(30), style, anchor: None, },
  ]
  let text = TextContext::{
    catalog,
    hooks: Hooks::new(base_family="Noto Serif"),
  }
  let wrapped = source_wrap(fragments, text, 150.0)
  inspect(
    wrapped
    .map(f => f.text.replace_all(old="\u{a0}", new="~").escape())
    .join(" | "),
    content=(
      #|"1 " | "xxxxxxxxxxxxxxxxxxxxxxx" | "\n" | "~ " | "xxxxxxx " | "\n" | "~ " | "yyyyyyyyyyyyyyyyyyyyyyy" | "\n" | "~ " | "yyyyyyy"
    ),
  )
}
