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
    describe_fragments(fragments),
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
/// Load `text` for the `pdf` backend in the safe mode (in the API's
/// default, secure, `source-highlighter` is locked off).
fn load_safe(text : String) -> @core.Node {
  register()
  @asciidoctor.load(
    text,
    options=@core.Options::new(backend="pdf", standalone=true, safe=1),
  )
}

///|
/// The text of the fragments of the first block of `source` as
/// `convert_code` makes them, and whether a highlighter made them.
fn code_text(source : String) -> (String, Bool) raise {
  let doc = load_safe(source)
  use_theme("extends: default\n")
  let converter = Converter::new(doc, new_flow(test_catalog()))
  let chunks = converter.code_chunks(doc.blocks[0], text_style())
  (chunks.fragments.map(f => f.text).join(""), chunks.highlighted)
}

///|
test "sanitizing keeps a < that opens no tag" {
  inspect(strip_markup("before < after"), content="before < after")
  // as Ruby's /<[^>]+>\0?/ does, a `<` before a tag runs to its `>`
  inspect(strip_markup("a < b <i>c</i>"), content="a c")
  inspect(strip_markup("<b>x</b> &lt;&#65;&#x42;&foo;"), content="x <AB?")
  let source =
    #|[source,text,subs=normal]
    #|----
    #|before pass:[<] after
    #|----
  debug_inspect(code_text(source), content="(\"before < after\", false)")
  debug_inspect(
    code_text(":source-highlighter: rouge\n\n" + source),
    content="(\"before < after\", true)",
  )
}

///|
test "a numbered line that cannot fit fails the conversion" {
  // Ruby raises Prawn::Errors::CannotFit; SourceWrap used to loop forever
  let doc = load_safe(
    (
      #|:source-highlighter: rouge
      #|:pdf-page-size: [120, 200]
      #|
      #|[source,ruby,linenums]
      #|----
      #|x
      #|----
    ),
  )
  try convert_document(doc, test_catalog()) catch {
    e => inspect(e, content="Failure(Prawn::Errors::CannotFit)")
  } noraise {
    _ => fail("expected the conversion to fail")
  }
}

///|
test "a block of callouts alone shows no callout" {
  // restore_conums makes a line only for a fragment on it: Rouge leaves
  // no fragment, so there is no line to put the callout back on
  let source =
    #|:source-highlighter: rouge
    #|
    #|[source,ruby]
    #|----
    #|<1>
    #|----
  debug_inspect(code_text(source), content="(\"\", true)")
  inspect(
    describe_fragments(
      restore_conums([], extract_conums("<1>").1, text_style(), linenums=1),
    ),
    content="",
  )
}

///|
/// The colours of the filled rectangles of the first block of `source`
/// (safe mode, page size and theme as the document says), set alone on a
/// page, in order.
fn block_fills(source : String) -> Array[String] raise {
  let doc = load_safe(source)
  activate_session(doc)
  use_theme("extends: default\n")
  session().page_setup = resolve_page_setup(doc)
  let flow = new_flow(test_catalog())
  flow.start_new_page()
  Converter::new(doc, flow).convert_block(doc.blocks[0])
  flow.model.pages
  .iter()
  .flat_map(page => page.items.iter())
  .filter_map(item => {
    match item {
      Rect({ fill: Some(c), .. }) => Some(hex6(c))
      _ => None
    }
  })
  .collect()
}

///|
test "the blank of a wrapped numbered line has no background" {
  // tulip gives the line numbers a background; the blank SourceWrap puts
  // where a line wraps has none (one 766daf: the number of line 1)
  let fills = block_fills(
    (
      #|:source-highlighter: rouge
      #|:rouge-style: tulip
      #|:pdf-page-size: [220, 400]
      #|
      #|[source,ruby,linenums]
      #|----
      #|
    ) +
    "x".repeat(60) +
    "\n----\n",
  )
  inspect(fills.filter(c => c == "766daf").length(), content="1")
}

///|
test "source-highlighter is locked off from the server safe mode up" {
  let source =
    #|:source-highlighter: rouge
    #|
    #|[source,ruby]
    #|----
    #|puts 1
    #|----
  let highlighted = (safe : Int?, attributes : Array[(String, @core.AttrVal)]) => {
    register()
    let doc = @asciidoctor.load(
      source,
      options=@core.Options::new(
        backend="pdf",
        standalone=true,
        safe?,
        attributes~,
      ),
    )
    doc.syntax_highlighter() is Some(_)
  }
  // the API's default is secure
  inspect(highlighted(None, []), content="false")
  inspect(highlighted(Some(10), []), content="false")
  inspect(highlighted(Some(1), []), content="true")
  // the API can still set it
  inspect(
    highlighted(None, [("source-highlighter", @core.AttrVal::Str("rouge"))]),
    content="true",
  )
}

///|
test "each document highlights with its own Rouge style" {
  let source = (style : String) => {
    ":source-highlighter: rouge\n:rouge-style: \{style}\n\n[source,ruby]\n----\nputs 1\n----\n"
  }
  let tulip = load_safe(source("tulip"))
  let github = load_safe(source("github"))
  let background = (doc : @core.Node) => {
    activate_session(doc)
    use_theme("extends: default\n")
    let converter = Converter::new(doc, new_flow(test_catalog()))
    converter.code_chunks(doc.blocks[0], text_style()).background
    .map(hex6)
    .unwrap_or("none")
  }
  let first = background(tulip)
  let second = background(github)
  inspect(first != second, content="true")
  // converting the other document in between changes neither
  inspect(background(tulip) == first, content="true")
  inspect(background(github) == second, content="true")
}
