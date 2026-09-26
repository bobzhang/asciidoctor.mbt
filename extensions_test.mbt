// Extension API scenarios. Expected output was produced by Ruby Asciidoctor
// with equivalent Ruby extensions (see PLAN.md, extensions section).

///|
fn convert_with(src : String, exts : @core.Extensions) -> String raise {
  @asciidoctor.convert(
    src,
    options=@core.Options::new(safe=@core.SAFE_SAFE, extensions=exts),
  )
}

///|
test "block processor on paragraph" {
  let exts = @core.Extensions::new()
  exts.block(
    "yell",
    (parent, reader, attrs) => {
      Some(
        @core.create_paragraph(parent, reader.lines().map(@rb.upcase), attrs),
      )
    },
    contexts=[Paragraph],
    content_model=Simple,
  )
  inspect(
    convert_with("[yell]\nhello world", exts),
    content=(
      #|<div class="paragraph">
      #|<p>HELLO WORLD</p>
      #|</div>
    ),
  )
}

///|
test "block macro" {
  let exts = @core.Extensions::new()
  exts.block_macro("gist", (parent, target, _attrs) => {
    Some(
      @core.create_block(
        parent,
        Pass,
        Some(["<script src=\"https://gist.github.com/\{target}.js\"></script>"]),
        @core.Attributes::new(),
        content_model=Raw,
      ),
    )
  })
  inspect(
    convert_with("gist::12345[]", exts),
    content=(
      #|<script src="https://gist.github.com/12345.js"></script>
    ),
  )
}

///|
test "inline macro" {
  let exts = @core.Extensions::new()
  exts.inline_macro("man", (parent, target, attrs) => {
    Some(
      InlineNode(
        @core.create_anchor(
          parent,
          Some("\{target}(\{attrs.pos_str(1).unwrap_or("")})"),
          "link",
          target="\{target}.html",
        ),
      ),
    )
  })
  inspect(
    convert_with("See man:gittutorial[7] for details.", exts),
    content=(
      #|<div class="paragraph">
      #|<p>See <a href="gittutorial.html">gittutorial(7)</a> for details.</p>
      #|</div>
    ),
  )
}

///|
test "inline macro with short format and attributes content model" {
  let exts = @core.Extensions::new()
  exts.inline_macro(
    "kbd2",
    (parent, _target, attrs) => {
      Some(
        InlineNode(
          @core.create_inline(parent, Quoted, attrs.str("text"), type_="strong"),
        ),
      )
    },
    format="short",
  )
  // like Ruby: with the attributes content model the text is parsed as
  // positional attributes, so `text` is unset
  inspect(
    convert_with("Press kbd2:[Ctrl] now.", exts),
    content=(
      #|<div class="paragraph">
      #|<p>Press <strong></strong> now.</p>
      #|</div>
    ),
  )
}

///|
test "preprocessor" {
  let exts = @core.Extensions::new()
  exts.preprocessor((_doc, reader) => {
    Some(
      @core.Reader::new(
        reader.read_lines().filter(l => !l.has_prefix("// strip")),
      ),
    )
  })
  inspect(
    convert_with("keep\n// strip me\nkeep too", exts),
    content=(
      #|<div class="paragraph">
      #|<p>keep
      #|keep too</p>
      #|</div>
    ),
  )
}

///|
test "tree processor" {
  let exts = @core.Extensions::new()
  exts.tree_processor(doc => {
    for b in doc.blocks {
      b.lines = b.lines.map(@rb.upcase)
    }
    None
  })
  inspect(
    convert_with("first\n\nsecond", exts),
    content=(
      #|<div class="paragraph">
      #|<p>FIRST</p>
      #|</div>
      #|<div class="paragraph">
      #|<p>SECOND</p>
      #|</div>
    ),
  )
}

///|
test "postprocessor" {
  let exts = @core.Extensions::new()
  exts.postprocessor((_doc, output) => output + "\n<!-- footer -->")
  inspect(
    convert_with("text", exts),
    content=(
      #|<div class="paragraph">
      #|<p>text</p>
      #|</div>
      #|<!-- footer -->
    ),
  )
}

///|
test "include processor" {
  let exts = @core.Extensions::new()
  exts.include_processor(
    (_doc, reader, target, attrs) => {
      reader.push_include_lines(
        ["from *virtual*"],
        file=target,
        path=target,
        attributes=attrs,
      )
    },
    handles=(_doc, target) => target == "virtual.adoc",
  )
  inspect(
    convert_with("include::virtual.adoc[]\n\nafter", exts),
    content=(
      #|<div class="paragraph">
      #|<p>from <strong>virtual</strong></p>
      #|</div>
      #|<div class="paragraph">
      #|<p>after</p>
      #|</div>
    ),
  )
}
