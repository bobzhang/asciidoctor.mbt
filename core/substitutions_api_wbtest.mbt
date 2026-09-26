// Passthrough tests ported from test/substitutions_test.rb ('Passthroughs'
// context). extract_passthroughs / restore_passthroughs and the collected
// passthroughs are private in the port, hence a white-box test. No converter
// is registered in this package, so restore assertions that need one (quotes)
// are checked through the public `apply_subs(text, [Macros])` in
// substitutions_api_test.mbt instead. Expected values come from the Ruby
// assertions (and, for details the assertions leave implicit, from running
// the Ruby tests with the calls recorded).

///|
fn wb_block_from_string(src : String) -> Node {
  let doc = new_document(
    Some(prepare_source_string(src)),
    Options::new(standalone=false),
  )
  doc.parse().blocks[0]
}

///|
/// Renders collected passthroughs like `[{text: ..., subs: [...]}]`.
fn wb_passthroughs(node : Node) -> String {
  let items = node.passthroughs.map(p => {
    let subs = match p.subs {
      Some(subs) => "[" + subs.map(s => ":" + s.name()).join(", ") + "]"
      None => "nil"
    }
    "{text: \{p.text.escape()}, subs: \{subs}}"
  })
  "[" + items.join(", ") + "]"
}

///|
let wb_placeholder_0 : String = "\u{96}0\u{97}"

///|
test "Passthroughs: collect inline triple plus passthroughs" {
  let para = wb_block_from_string("+++<code>inline code</code>+++")
  assert_eq(para.extract_passthroughs(para.source()), wb_placeholder_0)
  inspect(
    wb_passthroughs(para),
    content=(
      #|[{text: "<code>inline code</code>", subs: []}]
    ),
  )
}

///|
test "Passthroughs: collect multi-line inline triple plus passthroughs" {
  let para = wb_block_from_string("+++<code>inline\ncode</code>+++")
  assert_eq(para.extract_passthroughs(para.source()), wb_placeholder_0)
  inspect(
    wb_passthroughs(para),
    content=(
      #|[{text: "<code>inline\ncode</code>", subs: []}]
    ),
  )
}

///|
test "Passthroughs: collect inline double dollar passthroughs" {
  let para = wb_block_from_string("$$<code>{code}</code>$$")
  assert_eq(para.extract_passthroughs(para.source()), wb_placeholder_0)
  inspect(
    wb_passthroughs(para),
    content=(
      #|[{text: "<code>{code}</code>", subs: [:specialcharacters]}]
    ),
  )
}

///|
test "Passthroughs: collect inline double plus passthroughs" {
  let para = wb_block_from_string("++<code>{code}</code>++")
  assert_eq(para.extract_passthroughs(para.source()), wb_placeholder_0)
  inspect(
    wb_passthroughs(para),
    content=(
      #|[{text: "<code>{code}</code>", subs: [:specialcharacters]}]
    ),
  )
}

///|
test "Passthroughs: collect multi-line inline double dollar passthroughs" {
  let para = wb_block_from_string("$$<code>\n{code}\n</code>$$")
  assert_eq(para.extract_passthroughs(para.source()), wb_placeholder_0)
  inspect(
    wb_passthroughs(para),
    content=(
      #|[{text: "<code>\n{code}\n</code>", subs: [:specialcharacters]}]
    ),
  )
}

///|
test "Passthroughs: collect multi-line inline double plus passthroughs" {
  let para = wb_block_from_string("++<code>\n{code}\n</code>++")
  assert_eq(para.extract_passthroughs(para.source()), wb_placeholder_0)
  inspect(
    wb_passthroughs(para),
    content=(
      #|[{text: "<code>\n{code}\n</code>", subs: [:specialcharacters]}]
    ),
  )
}

///|
test "Passthroughs: collect passthroughs from inline pass macro" {
  let para = wb_block_from_string(
    "pass:specialcharacters,quotes[<code>['code'\\]</code>]",
  )
  assert_eq(para.extract_passthroughs(para.source()), wb_placeholder_0)
  inspect(
    wb_passthroughs(para),
    content=(
      #|[{text: "<code>['code']</code>", subs: [:specialcharacters, :quotes]}]
    ),
  )
}

///|
test "Passthroughs: collect multi-line passthroughs from inline pass macro" {
  let para = wb_block_from_string(
    "pass:specialcharacters,quotes[<code>['more\ncode'\\]</code>]",
  )
  assert_eq(para.extract_passthroughs(para.source()), wb_placeholder_0)
  inspect(
    wb_passthroughs(para),
    content=(
      #|[{text: "<code>['more\ncode']</code>", subs: [:specialcharacters, :quotes]}]
    ),
  )
}

///|
test "Passthroughs: resolves sub shorthands on inline pass macro" {
  let para = wb_block_from_string("pass:q,a[*<{backend}>*]")
  assert_eq(para.extract_passthroughs(para.source()), wb_placeholder_0)
  inspect(
    wb_passthroughs(para),
    content=(
      #|[{text: "*<{backend}>*", subs: [:quotes, :attributes]}]
    ),
  )
}

///|
test "Passthroughs: inline pass macro supports incremental subs" {
  let para = wb_block_from_string("pass:n,-a[<{backend}>]")
  let result = para.extract_passthroughs(para.source())
  inspect(para.passthroughs.length(), content="1")
  // n,-a => normal subs without attributes
  inspect(
    wb_passthroughs(para),
    content=(
      #|[{text: "<{backend}>", subs: [:specialcharacters, :quotes, :replacements, :macros, :post_replacements]}]
    ),
  )
  inspect(para.restore_passthroughs(result), content="&lt;{backend}&gt;")
}

///|
test "Passthroughs: should not recognize pass macro with invalid substitution list" {
  for subs in [",", "42", "a,"] {
    let para = wb_block_from_string("pass:\{subs}[foobar]")
    assert_eq(para.extract_passthroughs(para.source()), "pass:\{subs}[foobar]")
  }
}

///|
test "Passthroughs: should allow content of inline pass macro to be empty" {
  let para = wb_block_from_string("pass:[]")
  let result = para.extract_passthroughs(para.source())
  inspect(para.passthroughs.length(), content="1")
  inspect(para.restore_passthroughs(result), content="")
}

///|
test "Passthroughs: restore inline passthroughs without subs" {
  let para = wb_block_from_string("some \u{96}0\u{97} to study")
  para.extract_passthroughs("") |> ignore
  para.passthroughs.push({
    text: "<code>inline code</code>",
    subs: Some([]),
    type_: None,
    attributes: None,
  })
  inspect(
    para.restore_passthroughs(para.source()),
    content="some <code>inline code</code> to study",
  )
}

///|
test "Passthroughs: restore inline passthroughs with subs" {
  let para = wb_block_from_string(
    "some \u{96}0\u{97} to study in the \u{96}1\u{97} programming language",
  )
  para.extract_passthroughs("") |> ignore
  para.passthroughs.push({
    text: "<code>{code}</code>",
    subs: Some([SpecialCharacters]),
    type_: None,
    attributes: None,
  })
  para.passthroughs.push({
    text: "{language}",
    subs: Some([SpecialCharacters]),
    type_: None,
    attributes: None,
  })
  inspect(
    para.restore_passthroughs(para.source()),
    content="some &lt;code&gt;{code}&lt;/code&gt; to study in the {language} programming language",
  )
}

///|
test "Passthroughs: complex inline passthrough macro" {
  let text_to_escape = "[(] <'basic form'> <'logical operator'> <'basic form'> [)]"
  let para = wb_block_from_string("$$\{text_to_escape}$$")
  para.extract_passthroughs(para.source()) |> ignore
  inspect(para.passthroughs.length(), content="1")
  assert_eq(para.passthroughs[0].text, text_to_escape)
  let text_to_escape_escaped = "[(\\] <'basic form'> <'logical operator'> <'basic form'> [)\\]"
  let para = wb_block_from_string(
    "pass:specialcharacters[\{text_to_escape_escaped}]",
  )
  para.extract_passthroughs(para.source()) |> ignore
  inspect(para.passthroughs.length(), content="1")
  assert_eq(para.passthroughs[0].text, text_to_escape)
}
