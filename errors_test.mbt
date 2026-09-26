// Errors Ruby Asciidoctor raises from the API (document_test.rb,
// extensions_test.rb, manpage_test.rb) and the converter registry.

///|
fn error_message(f : () -> String raise) -> String {
  try f() catch {
    e => e.to_string()
  } noraise {
    output => "no error; output: \{output}"
  }
}

///|
test "should raise an exception when a converter cannot be resolved before conversion" {
  let input =
    #|= Document Title
    #|
    #|text
  inspect(
    error_message(() => {
      @asciidoctor.convert(
        input,
        options=@core.Options::new(backend="unknownBackend"),
      )
    }),
    content="asciidoctor: FAILED: missing converter for backend 'unknownBackend'. Processing aborted.",
  )
}

///|
test "missing converter: the loaded document reports the error and is not parsed" {
  let (doc, messages) = @core.with_memory_logger(() => {
    @asciidoctor.load(
      "= Title\n\n<<missing>>\n\nfoo::bar[]",
      options=@core.Options::new(backend="nope"),
    )
  })
  debug_inspect(
    doc.processing_error().map(e => e is @core.MissingConverter("nope")),
    content="Some(true)",
  )
  inspect(doc.blocks.length(), content="0")
  inspect(messages.length(), content="0")
  inspect(doc.convert(), content="")
}

///|
test "missing converter set by a document header attribute" {
  // the backend attribute is locked in secure mode (the API default)
  inspect(
    @asciidoctor.convert("= Title\n:backend: nope\n\ntext"),
    content=(
      #|<div class="paragraph">
      #|<p>text</p>
      #|</div>
    ),
  )
  inspect(
    error_message(() => {
      @asciidoctor.convert(
        "= Title\n:backend: nope\n\ntext",
        options=@core.Options::new(safe=@core.SAFE_UNSAFE),
      )
    }),
    content="asciidoctor: FAILED: missing converter for backend 'nope'. Processing aborted.",
  )
}

///|
test "a converter registered by the user replaces the built-in one" {
  let builtin = @core.lookup_converter("docbook5").unwrap()
  let custom : @core.ConverterFactory = (backend, htmlsyntax, doc) => {
    let delegate = builtin(backend, htmlsyntax, doc)
    @core.CompositeConverter::new(delegate, handlers={
      "paragraph": node => "<para>custom: \{node.content()}</para>",
    })
  }
  @core.register_converter(["docbook5"], custom)
  let output = {
    defer @core.register_converter(["docbook5"], builtin)
    @asciidoctor.convert("text", options=@core.Options::new(backend="docbook5"))
  }
  inspect(output, content="<para>custom: text</para>")
  inspect(
    @asciidoctor.convert("text", options=@core.Options::new(backend="docbook5")),
    content="<simpara>text</simpara>",
  )
}

///|
test "manpage backend requires the manpage doctype" {
  // Ruby: RuntimeError 'asciidoctor: ERROR: doctype must be set to manpage when using manpage backend'
  let (result, messages) = @core.with_memory_logger(() => {
    error_message(() => {
      @asciidoctor.convert(
        "= Title\n:backend: manpage\n\ntext",
        options=@core.Options::new(safe=@core.SAFE_UNSAFE, standalone=true),
      )
    })
  })
  inspect(
    result,
    content="asciidoctor: ERROR: doctype must be set to manpage when using manpage backend",
  )
  inspect(messages.length(), content="0")
}

///|
fn cat_in_sink_extensions() -> @core.Extensions raise {
  let exts = @core.Extensions::new()
  exts.block_macro("cat_in_sink", (parent, target, attrs) => {
    let image_attrs = @core.Attributes::new()
    if target != "" {
      image_attrs.set_str("target", "cat-in-sink-day-\{target}.png")
    }
    match attrs.str("title") {
      Some(t) => image_attrs.set_str("title", t)
      None => ()
    }
    Some(@core.create_image_block(parent, image_attrs))
  })
  exts
}

///|
test "should raise an exception if mandatory target attribute is not provided for image block" {
  let exts = cat_in_sink_extensions()
  inspect(
    error_message(() => {
      @asciidoctor.convert(
        "cat_in_sink::[]",
        options=@core.Options::new(extensions=exts),
      )
    }),
    content="Unable to create an image block, target attribute is required",
  )
  inspect(
    @asciidoctor.convert(
      "cat_in_sink::25[]",
      options=@core.Options::new(extensions=exts),
    ),
    content=(
      #|<div class="imageblock">
      #|<div class="content">
      #|<img src="cat-in-sink-day-25.png" alt="cat in sink day 25">
      #|</div>
      #|</div>
    ),
  )
}

///|
test "invalid macro names are rejected" {
  let exts = @core.Extensions::new()
  try exts.block_macro("bad name", (_, _, _) => None) catch {
    e => inspect(e, content="invalid name for block macro: bad name")
  } noraise {
    _ => fail("expected an ArgumentError")
  }
  try exts.inline_macro("bad:name", (_, _, _) => None) catch {
    e => inspect(e, content="invalid name for inline macro: bad:name")
  } noraise {
    _ => fail("expected an ArgumentError")
  }
}

///|
test "normalize_asset_path raises when not autocorrecting a path outside the jail" {
  let doc = @asciidoctor.load(
    "",
    options=@core.Options::new(
      vfs=@core.MemoryVfs::new(cwd="/project", home="/home/user"),
      parse=false,
    ),
  )
  try doc.normalize_asset_path("/etc/passwd", autocorrect=false) catch {
    @core.SecurityError(msg) =>
      inspect(
        msg,
        content=(
          #|path /etc/passwd is outside of jail: /project (disallowed in safe mode)
        ),
      )
  } noraise {
    _ => fail("expected a SecurityError")
  }
}
