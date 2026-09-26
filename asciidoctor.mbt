///|
pub using @core {
  type Node,
  type Options,
  type Attributes,
  type AttrVal,
  type Context,
  type Logger,
  type LogMessage,
  type Severity,
  type MemoryVfs,
  logger,
  set_logger,
  with_memory_logger,
}

///|
/// Parses attribute overrides given as a string (`"a=b c!"`, Ruby option form).
/// Spaces can be escaped with a backslash.
pub fn parse_attributes_option(attrs : String) -> Array[(String, AttrVal)] {
  let out = []
  // split on unescaped whitespace
  let entries = []
  let cur = StringBuilder()
  let mut i = 0
  let n = attrs.length()
  while i < n {
    let c = attrs[i]
    if c == '\\' && i + 1 < n && (attrs[i + 1] == ' ' || attrs[i + 1] == '\t') {
      cur.write_char(attrs[i + 1].to_int().unsafe_to_char())
      i += 2
      continue
    }
    if c == ' ' || c == '\t' || c == '\n' {
      if !cur.is_empty() {
        entries.push(cur.to_string())
        cur.reset()
      }
    } else {
      cur.write_char(c.to_int().unsafe_to_char())
    }
    i += 1
  }
  if !cur.is_empty() {
    entries.push(cur.to_string())
  }
  for entry in entries {
    let (k, _, v) = @rb.partition(entry, "=")
    out.push((k, @core.AttrVal::Str(v)))
  }
  out
}

///|
fn ensure_converters() -> Unit {
  @html5.register()
}

///|
/// Loads (parses) an AsciiDoc document from a string (Ruby `Asciidoctor.load`).
pub fn load(input : String, options? : Options = Options::new()) -> Node {
  ensure_converters()
  let doc = @core.new_document(
    Some(@core.prepare_source_string(input)),
    options,
  )
  if options.parse {
    doc.parse()
  } else {
    doc
  }
}

///|
/// Loads a document from lines.
pub fn load_lines(
  lines : Array[String],
  options? : Options = Options::new(),
) -> Node {
  ensure_converters()
  let doc = @core.new_document(Some(lines), options)
  if options.parse {
    doc.parse()
  } else {
    doc
  }
}

///|
/// Converts an AsciiDoc string (Ruby `Asciidoctor.convert` without file output).
///
/// ```mbt check
/// test {
///   let html = @asciidoctor.convert("Hello, *World*!")
///   inspect(
///     html,
///     content=(
///       #|<div class="paragraph">
///       #|<p>Hello, <strong>World</strong>!</p>
///       #|</div>
///     ),
///   )
/// }
/// ```
pub fn convert(input : String, options? : Options = Options::new()) -> String {
  load(input, options~).convert()
}
