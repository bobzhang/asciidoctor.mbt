// Shared helpers for the API-level tests ported from the Ruby test suite.

///|
/// Renders captured log messages one per line as `SEVERITY: message`, where
/// SEVERITY is the Ruby severity symbol and message is Ruby's
/// `AutoFormattingMessage#inspect` (source location prefix when present).
/// Messages below `min_level` (see `Severity::to_int`) are dropped, which
/// mirrors a Ruby logger whose level suppresses `debug?`/`info?` messages.
fn log_lines(msgs : Array[@core.LogMessage], min_level? : Int = 0) -> String {
  msgs
  .filter(m => m.severity.to_int() >= min_level)
  .map(m => {
    let sev = match m.severity {
      Debug => "DEBUG"
      Info => "INFO"
      Warn => "WARN"
      Error => "ERROR"
      Fatal => "FATAL"
      Unknown => "UNKNOWN"
    }
    "\{sev}: \{m.to_string()}"
  })
  .join("\n")
}

///|
/// Renders attributes like Ruby 2.x `Hash#inspect`.
fn attrs_inspect(attrs : @core.Attributes) -> String {
  let parts = []
  for k, v in attrs.iter() {
    let key = match k {
      Name(n) => n.escape()
      Pos(i) => i.to_string()
    }
    let value = match v {
      Str(s) => s.escape()
      Int(i) => i.to_string()
      Nil => "nil"
      Bool(b) => b.to_string()
      Float(f) => f.to_string()
      List(l) => "[" + l.map(s => s.escape()).join(", ") + "]"
    }
    parts.push("\{key}=>\{value}")
  }
  "{" + parts.join(", ") + "}"
}

///|
/// Ruby `Document.new(src.lines, opts).parse.blocks.first` with
/// `standalone: false` (test_helper.rb `block_from_string`).
fn block_from_string(
  src : String,
  attributes? : Array[(String, @core.AttrVal)] = [],
  backend? : String,
  doctype? : String,
  safe? : Int,
  vfs? : &@core.Vfs,
  catalog_assets? : Bool = false,
) -> @core.Node {
  let doc = @asciidoctor.load(
    src,
    options=@core.Options::new(
      attributes~,
      standalone=false,
      backend?,
      doctype?,
      safe?,
      vfs?,
      catalog_assets~,
    ),
  )
  doc.blocks[0]
}

///|
/// test/fixtures/circle.svg from the Ruby test suite.
let circle_svg : String =
  #|<?xml version="1.0"?>
  #|<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">
  #|<!-- An SVG of a black circle -->
  #|<svg
  #|viewBox="0 0 120 120" version="1.1"
  #|xmlns="http://www.w3.org/2000/svg" style="width:500px;height:500px"
  #|width="500px" height="500px">
  #|  <circle cx="60" cy="60" r="50"/>
  #|</svg>
  #|

///|
/// A virtual file system holding the Ruby test fixtures used by these tests.
/// The Ruby tests use the test directory as docdir; here it is /test.
fn fixture_vfs() -> &@core.Vfs {
  let vfs = @core.MemoryVfs::new(cwd="/test")
  vfs.add_text("/test/fixtures/circle.svg", circle_svg)
  // test/fixtures/dot.gif
  vfs.add_bytes("/test/fixtures/dot.gif", [
    0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0x01, 0x00, 0x01, 0x00, 0x80, 0x00, 0x00,
    0x05, 0x04, 0x04, 0x00, 0x00, 0x00, 0x2c, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00,
    0x01, 0x00, 0x00, 0x02, 0x02, 0x44, 0x01, 0x00, 0x3b,
  ])
  vfs
}

///|
/// Renders an array of strings like Ruby 2.x `Array#inspect`.
fn rb_inspect_lines(lines : Array[String]) -> String {
  "[" + lines.map(l => l.escape()).join(", ") + "]"
}

///|
/// Renders a list of substitutions like Ruby's inspect of an array of symbols.
fn rb_inspect_subs(subs : Array[@core.Sub]?) -> String {
  match subs {
    None => "nil"
    Some(subs) => "[" + subs.map(s => ":" + s.name()).join(", ") + "]"
  }
}

///|
/// Renders footnotes as Ruby `[[index, id, text], ...]`.
fn rb_inspect_footnotes(footnotes : Array[@core.Footnote]) -> String {
  let items = footnotes.map(f => {
    let id = match f.id {
      Some(id) => id.escape()
      None => "nil"
    }
    "[\{f.index}, \{id}, \{f.text.escape()}]"
  })
  "[" + items.join(", ") + "]"
}
