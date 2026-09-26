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
/// Registers the built-in converters unless a converter is already registered
/// for their backend, so a converter the user registered for `html5`,
/// `docbook5` or `manpage` takes precedence (Ruby `Converter.register`).
fn ensure_converters() -> Unit {
  if @core.lookup_converter("html5") is None {
    @html5.register()
  }
  if @core.lookup_converter("manpage") is None {
    @manpage.register()
  }
  if @core.lookup_converter("docbook5") is None {
    @docbook5.register()
  }
}

///|
/// Loads (parses) an AsciiDoc document from a string (Ruby `Asciidoctor.load`).
///
/// Where Ruby raises (e.g. no converter is registered for the backend), the
/// document reports the error through `@core.Node::processing_error` and is
/// left unparsed; `convert` raises it.
pub fn load(input : String, options? : Options = Options::new()) -> Node {
  ensure_converters()
  if options.timings is Some(t) {
    t.start("read")
  }
  let lines = @core.prepare_source_string(input)
  load_prepared(lines, options)
}

///|
fn load_prepared(lines : Array[String], options : Options) -> Node {
  if options.timings is Some(t) {
    t.record("read")
    t.start("parse")
  }
  let doc = @core.new_document(Some(lines), options)
  let doc = if options.parse { doc.parse() } else { doc }
  if options.timings is Some(t) {
    t.record("parse")
  }
  doc
}

///|
/// Loads a document from lines.
pub fn load_lines(
  lines : Array[String],
  options? : Options = Options::new(),
) -> Node {
  ensure_converters()
  if options.timings is Some(t) {
    t.start("read")
  }
  load_prepared(lines, options)
}

///|
/// Converts an AsciiDoc string (Ruby `Asciidoctor.convert` without file output).
///
/// Raises the error that aborted processing, like Ruby: a `@core.ProcessingError`
/// (`MissingConverter` when no converter is registered for the backend,
/// `ConversionFailed` when the converter gives up) or an error raised by an
/// extension (e.g. `@core.ArgumentError`).
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
pub fn convert(
  input : String,
  options? : Options = Options::new(),
) -> String raise {
  let doc = load(input, options~)
  check_processing_error(doc)
  let output = doc.convert()
  check_processing_error(doc)
  output
}

///|
fn check_processing_error(doc : Node) -> Unit raise {
  match doc.processing_error() {
    Some(e) => raise e
    None => ()
  }
}
