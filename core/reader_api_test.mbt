// Direct-API tests ported from asciidoctor/test/reader_test.rb.
// Fixtures from test/fixtures are served by a MemoryVfs rooted at
// /asciidoctor (the Ruby test's working directory); the test directory
// (Ruby `DIRNAME`) is /asciidoctor/test.

///|
let testdir : String = "/asciidoctor/test"

///|
let fixturesdir : String = "/asciidoctor/test/fixtures"

///|
let sample_data : Array[String] = ["first line", "second line", "third line"]

///|
fn fixtures_vfs() -> @core.MemoryVfs {
  let vfs = @core.MemoryVfs::new(cwd="/asciidoctor")
  let add = fn(name : String, text : String) {
    vfs.add_text("\{fixturesdir}/\{name}", text)
  }
  add(
    "include-file.adoc",
    (
      #|first line of included content
      #|second line of included content
      #|third line of included content
      #|fourth line of included content
      #|fifth line of included content
      #|sixth line of included content
      #|seventh line of included content
      #|eighth line of included content
      #|
      #|// tag::snippet[]
      #|// tag::snippetA[]
      #|snippetA content
      #|// end::snippetA[]
      #|
      #|non-tagged content
      #|
      #|// tag::snippetB[]
      #|snippetB content
      #|// end::snippetB[]
      #|// end::snippet[]
      #|
      #|more non-tagged content
      #|
      #|last line of included content
      #|
    ),
  )
  add(
    "parent-include.adoc",
    (
      #|first line of parent
      #|
      #|include::child-include.adoc[]
      #|
      #|last line of parent
      #|
    ),
  )
  add(
    "parent-include-restricted.adoc",
    (
      #|first line of parent
      #|
      #|include::child-include.adoc[depth=0]
      #|
      #|last line of parent
      #|
    ),
  )
  add(
    "child-include.adoc",
    (
      #|first line of child
      #|
      #|include::grandchild-include.adoc[]
      #|
      #|last line of child
      #|
    ),
  )
  add(
    "grandchild-include.adoc",
    (
      #|first line of grandchild
      #|
      #|last line of grandchild
      #|
    ),
  )
  add(
    "main.adoc",
    (
      #|= Main Document
      #|
      #|preamble
      #|
      #|include::chapter-a.adoc[leveloffset=+1]
      #|
    ),
  )
  add(
    "chapter-a.adoc",
    (
      #|= Chapter A
      #|
      #|content
      #|
    ),
  )
  add(
    "with-front-matter.adoc",
    (
      #|---
      #|name: value
      #|---
      #|content
      #|
    ),
  )
  add(
    "unclosed-tag.adoc",
    (
      #|x
      #|// tag::a[]
      #|a
      #|
    ),
  )
  add(
    "mismatched-end-tag.adoc",
    (
      #|//tag::a[]
      #|a
      #|//tag::b[]
      #|b
      #|//end::a[]
      #|//end::b[]
      #|c
      #|
    ),
  )
  add(
    "unexpected-end-tag.adoc",
    (
      #|// tag::a[]
      #|a
      #|// end::a[]
      #|// end::a[]
      #|
    ),
  )
  add(
    "tagged-class.rb",
    (
      #|class Dog
      #|  #tag::init[]
      #|  def initialize breed
      #|    @breed = breed
      #|  end
      #|  #end::init[]
      #|  #tag::bark[]
      #|
      #|  def bark
      #|    #tag::bark-beagle[]
      #|    if @breed == 'beagle'
      #|      'woof woof woof woof woof'
      #|    #end::bark-beagle[]
      #|    #tag::bark-other[]
      #|    else
      #|      'woof woof'
      #|    #end::bark-other[]
      #|    #tag::bark-all[]
      #|    end
      #|    #end::bark-all[]
      #|  end
      #|  #end::bark[]
      #|end
      #|
    ),
  )
  add(
    "tagged-class-enclosed.rb",
    (
      #|#tag::all[]
      #|class Dog
      #|  #tag::init[]
      #|  def initialize breed
      #|    @breed = breed
      #|  end
      #|  #end::init[]
      #|  #tag::bark[]
      #|
      #|  def bark
      #|    #tag::bark-beagle[]
      #|    if @breed == 'beagle'
      #|      'woof woof woof woof woof'
      #|    #end::bark-beagle[]
      #|    #tag::bark-other[]
      #|    else
      #|      'woof woof'
      #|    #end::bark-other[]
      #|    #tag::bark-all[]
      #|    end
      #|    #end::bark-all[]
      #|  end
      #|  #end::bark[]
      #|end
      #|#end::all[]
      #|
    ),
  )
  add(
    "include-alt-extension.asciidoc",
    (
      #|first line
      #|
      #|ifdef::asciidoctor-version[Asciidoctor!]
      #|
      #|last line
      #|
    ),
  )
  add("data.tsv", "First\tSecond\tThird\na\tb\tc\n1\t2\t\nx\ty\tz\n")
  add(
    "include-file.xml",
    (
      #|<root>
      #|  <!-- tag::snippet[] -->
      #|  <snippet>content</snippet>
      #|  <!-- end::snippet[] -->
      #|</root>
      #|
    ),
  )
  add(
    "include-file.ml",
    (
      #|(* tag::snippet[] *)
      #|let s = SS.empty;;
      #|(* end::snippet[] *)
      #|
    ),
  )
  add(
    "include-file.jsx",
    (
      #|const element = (
      #|  <div>
      #|    <h1>Hello, Programmer!</h1>
      #|    <!-- tag::snippet[] -->
      #|    <p>Welcome to the club.</p>
      #|    <!-- end::snippet[] -->
      #|  </div>
      #|)
      #|
    ),
  )
  add(
    "basic-docinfo.xml",
    (
      #|<copyright><!-- don't remove the indent! -->
      #|    <year>2013</year>
      #|    <holder>Acme™, Inc.</holder>
      #|</copyright>
      #|
    ),
  )
  add(
    "encoding.adoc",
    (
      #|Gregory Romé has written an AsciiDoc plugin for the Redmine project management application.
      #|
      #|tag::romé[]
      #|Gregory Romé has written an AsciiDoc plugin for the Redmine project management application.
      #|end::romé[]
      #|
    ),
  )
  add(
    "circle.svg",
    (
      #|<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100">
      #|<circle cx="50" cy="50" r="40"/>
      #|</svg>
      #|
    ),
  )
  // "= 人" preceded by a UTF-8 BOM
  vfs.add_bytes(
    "\{fixturesdir}/file-with-utf8-bom.adoc",
    b"\xef\xbb\xbf= \xe4\xba\xba\n",
  )
  // "Où est l'hôpital ?" encoded as ISO-8859-1
  vfs.add_bytes("\{fixturesdir}/iso-8859-1.txt", b"O\xf9 est l'h\xf4pital ?\n")
  vfs
}

///|
/// Ruby `Asciidoctor::Document.new input, opts` (not parsed).
fn new_doc(
  input : String,
  attributes? : Array[(String, @core.AttrVal)] = [],
  safe? : Int,
  base_dir? : String,
  sourcemap? : Bool = false,
  standalone? : Bool,
  extensions? : @core.Extensions,
  vfs? : @core.MemoryVfs = fixtures_vfs(),
) -> @core.Node {
  @core.new_document(
    Some(@core.prepare_source_string(input)),
    @core.Options::new(
      attributes~,
      safe?,
      base_dir?,
      sourcemap~,
      standalone?,
      extensions?,
      vfs~,
    ),
  )
}

///|
/// Ruby test helper `document_from_string` (standalone and parsed by default).
fn document_from_string(
  input : String,
  attributes? : Array[(String, @core.AttrVal)] = [],
  safe? : Int,
  base_dir? : String,
  standalone? : Bool = true,
  parse? : Bool = true,
  vfs? : @core.MemoryVfs = fixtures_vfs(),
) -> @core.Node {
  let doc = new_doc(input, attributes~, safe?, base_dir?, standalone~, vfs~)
  if parse {
    doc.parse()
  } else {
    doc
  }
}

///|
/// Ruby test helper `empty_safe_document`.
fn empty_safe_document(
  attributes? : Array[(String, @core.AttrVal)] = [],
  extensions? : @core.Extensions,
) -> @core.Node {
  @core.new_document(
    Some([]),
    @core.Options::new(
      attributes~,
      safe=@core.SAFE_SAFE,
      base_dir=testdir,
      extensions?,
      vfs=fixtures_vfs(),
    ),
  )
}

///|
fn doc_reader(doc : @core.Node) -> @core.Reader {
  doc.reader().unwrap()
}

///|
/// Ruby `lines << reader.read_line while reader.has_more_lines?` joined by LF.
fn read_all(reader : @core.Reader) -> String {
  let lines = []
  while reader.has_more_lines() {
    lines.push(reader.read_line().unwrap_or("<nil>"))
  }
  lines.join("\n")
}

///|
/// Renders captured log messages as `SEVERITY: [path: line N: ]text`.
fn fmt_logs(messages : Array[@core.LogMessage]) -> String {
  messages
  .map(m => {
    let severity = match m.severity {
      Debug => "DEBUG"
      Info => "INFO"
      Warn => "WARN"
      Error => "ERROR"
      Fatal => "FATAL"
      Unknown => "UNKNOWN"
    }
    "\{severity}: \{m.to_string()}"
  })
  .join("\n")
}

///|
fn lines_of(text : String) -> Array[String] {
  text.split("\n").map(s => s.to_owned()).collect()
}

// ---------------------------------------------------------------------------
// Reader: Prepare lines

///|
test "should prepare lines from Array data" {
  let reader = @core.Reader::new(sample_data)
  assert_eq(reader.lines(), sample_data)
}

///|
test "should prepare lines from String data" {
  let reader = @core.Reader::from_string(sample_data.join("\n"))
  assert_eq(reader.lines(), sample_data)
}

///|
test "should prepare lines from String data with trailing newline" {
  let reader = @core.Reader::from_string(sample_data.join("\n") + "\n")
  assert_eq(reader.lines(), sample_data)
}

///|
test "should remove UTF-8 BOM from first line of String data" {
  let data = "\u{FEFF}" + sample_data.join("\n")
  let reader = @core.Reader::new(
    @core.prepare_source_string(data),
    normalize=true,
  )
  inspect(reader.lines()[0], content="first line")
  assert_eq(reader.lines(), sample_data)
  // the same data read from bytes
  let bytes = @utf8.encode(data)
  inspect(bytes[0:3], content="b\"\\xef\\xbb\\xbf\"")
  let reader = @core.Reader::new(
    @core.prepare_source_string(@core.decode_text(bytes)),
    normalize=true,
  )
  assert_eq(reader.lines(), sample_data)
}

///|
test "should remove UTF-8 BOM from first line of Array data" {
  let data = sample_data.copy()
  data[0] = "\u{FEFF}" + data[0]
  let reader = @core.Reader::new(data, normalize=true)
  inspect(reader.lines()[0], content="first line")
  assert_eq(reader.lines(), sample_data)
}

///|
fn utf16_bytes(s : String, big_endian~ : Bool) -> Bytes {
  let buf = Buffer()
  for i in 0..<s.length() {
    let u = s[i].to_int()
    if big_endian {
      buf.write_byte((u >> 8).to_byte())
      buf.write_byte((u & 0xFF).to_byte())
    } else {
      buf.write_byte((u & 0xFF).to_byte())
      buf.write_byte((u >> 8).to_byte())
    }
  }
  buf.to_bytes()
}

///|
test "should encode UTF-16LE string to UTF-8 when BOM is found" {
  let data = utf16_bytes("\u{FEFF}" + sample_data.join("\n"), big_endian=false)
  inspect(data[0:2], content="b\"\\xff\\xfe\"")
  let reader = @core.Reader::new(
    @core.prepare_source_string(@core.decode_text(data)),
    normalize=true,
  )
  inspect(reader.lines()[0], content="first line")
  assert_eq(reader.lines(), sample_data)
}

///|
test "should encode UTF-16BE string to UTF-8 when BOM is found" {
  let data = utf16_bytes("\u{FEFF}" + sample_data.join("\n"), big_endian=true)
  inspect(data[0:2], content="b\"\\xfe\\xff\"")
  let reader = @core.Reader::new(
    @core.prepare_source_string(@core.decode_text(data)),
    normalize=true,
  )
  inspect(reader.lines()[0], content="first line")
  assert_eq(reader.lines(), sample_data)
}

// ---------------------------------------------------------------------------
// Reader: With empty data

///|
test "has_more_lines? should return false with empty data" {
  assert_false(@core.Reader::new([]).has_more_lines())
}

///|
test "empty? should return true with empty data" {
  assert_true(@core.Reader::new([]).is_empty())
}

///|
test "next_line_empty? should return true with empty data" {
  assert_true(@core.Reader::new([]).next_line_empty())
}

///|
test "peek_line should return nil with empty data" {
  debug_inspect(@core.Reader::new([]).peek_line(), content="None")
}

///|
test "peek_lines should return empty Array with empty data" {
  debug_inspect(@core.Reader::new([]).peek_lines(num=1), content="[]")
}

///|
test "read_line should return nil with empty data" {
  debug_inspect(@core.Reader::new([]).read_line(), content="None")
}

///|
test "read_lines should return empty Array with empty data" {
  debug_inspect(@core.Reader::new([]).read_lines(), content="[]")
}

// ---------------------------------------------------------------------------
// Reader: With data

///|
test "has_more_lines? should return true if there are lines remaining" {
  assert_true(@core.Reader::new(sample_data).has_more_lines())
}

///|
test "empty? should return false if there are lines remaining" {
  assert_false(@core.Reader::new(sample_data).is_empty())
}

///|
test "next_line_empty? should return false if next line is not blank" {
  assert_false(@core.Reader::new(sample_data).next_line_empty())
}

///|
test "next_line_empty? should return true if next line is blank" {
  assert_true(@core.Reader::new(["", "second line"]).next_line_empty())
}

///|
test "peek_line should return next line if there are lines remaining" {
  let reader = @core.Reader::new(sample_data)
  debug_inspect(reader.peek_line(), content="Some(\"first line\")")
}

///|
test "peek_line should not consume line or increment line number" {
  let reader = @core.Reader::new(sample_data)
  debug_inspect(reader.peek_line(), content="Some(\"first line\")")
  debug_inspect(reader.peek_line(), content="Some(\"first line\")")
  inspect(reader.lineno(), content="1")
}

///|
test "peek_line should return next lines if there are lines remaining" {
  let reader = @core.Reader::new(sample_data)
  debug_inspect(
    reader.peek_lines(num=2),
    content="[\"first line\", \"second line\"]",
  )
}

///|
test "peek_lines should not consume lines or increment line number" {
  let reader = @core.Reader::new(sample_data)
  debug_inspect(
    reader.peek_lines(num=2),
    content="[\"first line\", \"second line\"]",
  )
  debug_inspect(
    reader.peek_lines(num=2),
    content="[\"first line\", \"second line\"]",
  )
  inspect(reader.lineno(), content="1")
}

///|
test "peek_lines should not increment line number if reader overruns buffer" {
  let reader = @core.Reader::new(sample_data)
  assert_eq(reader.peek_lines(num=sample_data.length() * 2), sample_data)
  inspect(reader.lineno(), content="1")
}

///|
test "peek_lines should peek all lines if no arguments are given" {
  let reader = @core.Reader::new(sample_data)
  assert_eq(reader.peek_lines(), sample_data)
  inspect(reader.lineno(), content="1")
}

///|
test "peek_lines should not invert order of lines" {
  let reader = @core.Reader::new(sample_data)
  assert_eq(reader.lines(), sample_data)
  reader.peek_lines(num=3) |> ignore
  assert_eq(reader.lines(), sample_data)
}

///|
test "read_line should return next line if there are lines remaining" {
  let reader = @core.Reader::new(sample_data)
  debug_inspect(reader.read_line(), content="Some(\"first line\")")
}

///|
test "read_line should consume next line and increment line number" {
  let reader = @core.Reader::new(sample_data)
  debug_inspect(reader.read_line(), content="Some(\"first line\")")
  debug_inspect(reader.read_line(), content="Some(\"second line\")")
  inspect(reader.lineno(), content="3")
}

///|
test "advance should consume next line and return a Boolean indicating if a line was consumed" {
  let reader = @core.Reader::new(sample_data)
  assert_true(reader.advance())
  assert_true(reader.advance())
  assert_true(reader.advance())
  assert_false(reader.advance())
}

///|
test "read_lines should return all lines" {
  let reader = @core.Reader::new(sample_data)
  assert_eq(reader.read_lines(), sample_data)
}

///|
test "read should return all lines joined as String" {
  let reader = @core.Reader::new(sample_data)
  inspect(
    reader.read(),
    content=(
      #|first line
      #|second line
      #|third line
    ),
  )
}

///|
test "has_more_lines? should return false after read_lines is invoked" {
  let reader = @core.Reader::new(sample_data)
  reader.read_lines() |> ignore
  assert_false(reader.has_more_lines())
}

///|
test "unshift puts line onto Reader as next line to read" {
  let reader = @core.Reader::new(sample_data, normalize=true)
  reader.unshift_line("line zero")
  debug_inspect(reader.peek_line(), content="Some(\"line zero\")")
  debug_inspect(reader.read_line(), content="Some(\"line zero\")")
  inspect(reader.lineno(), content="1")
}

///|
test "terminate should consume all lines and update line number" {
  let reader = @core.Reader::new(sample_data)
  reader.terminate()
  assert_true(reader.is_empty())
  inspect(reader.lineno(), content="4")
}

///|
test "skip_blank_lines should skip blank lines" {
  let reader = @core.Reader::new(["", ""] + sample_data)
  debug_inspect(reader.skip_blank_lines(), content="Some(2)")
  debug_inspect(reader.peek_line(), content="Some(\"first line\")")
}

///|
test "lines should return remaining lines" {
  let reader = @core.Reader::new(sample_data)
  reader.read_line() |> ignore
  debug_inspect(reader.lines(), content="[\"second line\", \"third line\"]")
}

///|
test "source_lines should return copy of original data Array" {
  let reader = @core.Reader::new(sample_data)
  reader.read_lines() |> ignore
  assert_eq(reader.source_lines, sample_data)
}

///|
test "source should return original data Array joined as String" {
  let reader = @core.Reader::new(sample_data)
  reader.read_lines() |> ignore
  inspect(
    reader.source(),
    content=(
      #|first line
      #|second line
      #|third line
    ),
  )
}

// ---------------------------------------------------------------------------
// Reader: Line context

///|
test "cursor.to_s should return file name and line number of current line" {
  let reader = @core.Reader::new(
    sample_data,
    cursor=@core.Cursor::new(file="sample.adoc"),
  )
  reader.read_line() |> ignore
  inspect(reader.cursor().line_info(), content="sample.adoc: line 2")
}

///|
test "line_info should return file name and line number of current line" {
  let reader = @core.Reader::new(
    sample_data,
    cursor=@core.Cursor::new(file="sample.adoc"),
  )
  reader.read_line() |> ignore
  inspect(reader.line_info(), content="sample.adoc: line 2")
}

///|
test "cursor_at_prev_line should return file name and line number of previous line read" {
  let reader = @core.Reader::new(
    sample_data,
    cursor=@core.Cursor::new(file="sample.adoc"),
  )
  reader.read_line() |> ignore
  inspect(
    reader.cursor_at_prev_line().line_info(),
    content="sample.adoc: line 1",
  )
}

// ---------------------------------------------------------------------------
// Reader: Read lines until

///|
let two_paragraphs : String =
  #|This is one paragraph.
  #|
  #|This is another paragraph.
  #|

///|
let block_and_paragraph : Array[String] = [
  "--", "This is one paragraph inside the block.", "", "This is another paragraph inside the block.",
  "--", "", "This is a paragraph outside the block.",
]

///|
test "Read lines until until end" {
  // Ruby: heredoc.lines (each line keeps its LF)
  let lines = ["This is one paragraph.\n", "\n", "This is another paragraph.\n"]
  let reader = @core.Reader::new(lines, normalize=true)
  let result = reader.read_lines_until()
  inspect(result.length(), content="3")
  debug_inspect(
    result,
    content="[\"This is one paragraph.\", \"\", \"This is another paragraph.\"]",
  )
  assert_false(reader.has_more_lines())
  assert_true(reader.is_empty())
}

///|
test "Read lines until until blank line" {
  let reader = @core.Reader::new(lines_of(two_paragraphs), normalize=true)
  let result = reader.read_lines_until(break_on_blank_lines=true)
  debug_inspect(result, content="[\"This is one paragraph.\"]")
  debug_inspect(
    reader.peek_line(),
    content="Some(\"This is another paragraph.\")",
  )
}

///|
test "Read lines until until blank line preserving last line" {
  let lines = ["This is one paragraph.", "", "This is another paragraph."]
  let reader = @core.Reader::new(lines)
  let result = reader.read_lines_until(
    break_on_blank_lines=true,
    preserve_last_line=true,
  )
  debug_inspect(result, content="[\"This is one paragraph.\"]")
  assert_true(reader.next_line_empty())
}

///|
test "Read lines until until condition is true" {
  let reader = @core.Reader::new(block_and_paragraph)
  reader.read_line() |> ignore
  let result = reader.read_lines_until(break_if=line => line == "--")
  inspect(result.length(), content="3")
  assert_eq(result, block_and_paragraph[1:4].to_owned())
  assert_true(reader.next_line_empty())
}

///|
test "Read lines until until condition is true, taking last line" {
  let reader = @core.Reader::new(block_and_paragraph)
  reader.read_line() |> ignore
  let result = reader.read_lines_until(read_last_line=true, break_if=line => {
    line == "--"
  })
  inspect(result.length(), content="4")
  assert_eq(result, block_and_paragraph[1:5].to_owned())
  assert_true(reader.next_line_empty())
}

///|
test "Read lines until until condition is true, taking and preserving last line" {
  let reader = @core.Reader::new(block_and_paragraph)
  reader.read_line() |> ignore
  let result = reader.read_lines_until(
    read_last_line=true,
    preserve_last_line=true,
    break_if=line => line == "--",
  )
  inspect(result.length(), content="4")
  assert_eq(result, block_and_paragraph[1:5].to_owned())
  debug_inspect(reader.peek_line(), content="Some(\"--\")")
}

///|
test "read lines until terminator" {
  let lines = [
    "****\n", "captured\n", "\n", "also captured\n", "****\n", "\n", "not captured\n",
  ]
  let doc = empty_safe_document()
  let reader = @core.Reader::new_preprocessor(doc, lines, normalize=true)
  let terminator = reader.read_line().unwrap()
  let result = reader.read_lines_until(terminator~, skip_processing=true)
  debug_inspect(result, content="[\"captured\", \"\", \"also captured\"]")
  assert_false(reader.unterminated)
}

///|
test "should flag reader as unterminated if reader reaches end of source without finding terminator" {
  let lines = [
    "****\n", "captured\n", "\n", "also captured\n", "\n", "captured yet again\n",
  ]
  let ((result, reader), messages) = @core.with_memory_logger(() => {
    let doc = empty_safe_document()
    let reader = @core.Reader::new_preprocessor(doc, lines, normalize=true)
    let terminator = reader.peek_line().unwrap()
    let result = reader.read_lines_until(
      terminator~,
      skip_first_line=true,
      skip_processing=true,
    )
    (result, reader)
  })
  debug_inspect(
    result,
    content="[\"captured\", \"\", \"also captured\", \"\", \"captured yet again\"]",
  )
  assert_true(reader.unterminated)
  inspect(
    fmt_logs(messages),
    content="WARN: <stdin>: line 1: unterminated **** block",
  )
}

// ---------------------------------------------------------------------------
// PreprocessorReader: Type hierarchy / Prepare lines

///|
test "PreprocessorReader should invoke or emulate Reader initializer" {
  let doc = @core.new_document(Some(sample_data), @core.Options::new())
  let reader = doc_reader(doc)
  assert_eq(reader.lines(), sample_data)
  inspect(reader.lineno(), content="1")
}

///|
test "should prepare and normalize lines from Array data" {
  let data = [""] + sample_data + [""]
  let reader = doc_reader(@core.new_document(Some(data), @core.Options::new()))
  assert_eq(reader.lines(), [""] + sample_data)
}

///|
test "should prepare and normalize lines from String data" {
  let data = ([" "] + sample_data + [" "]).join("\n")
  let reader = doc_reader(new_doc(data))
  assert_eq(reader.lines(), [""] + sample_data)
}

///|
test "should drop all lines if all lines are empty" {
  let data = ["", " ", "", " "]
  let reader = doc_reader(@core.new_document(Some(data), @core.Options::new()))
  debug_inspect(reader.lines(), content="[]")
}

///|
test "should clean CRLF from end of lines" {
  let input = "source\r\nwith\r\nCRLF\r\nline endings\r\n"
  let variants : Array[Array[String]] = [
    @core.prepare_source_string(input),
    ["source\r\n", "with\r\n", "CRLF\r\n", "line endings\r\n"],
    ["source\r", "with\r", "CRLF\r", "line endings\r"],
  ]
  for lines in variants {
    let reader = doc_reader(
      @core.new_document(Some(lines), @core.Options::new()),
    )
    debug_inspect(
      reader.lines(),
      content="[\"source\", \"with\", \"CRLF\", \"line endings\"]",
    )
  }
}

///|
let front_matter_input : String =
  #|---
  #|layout: post
  #|title: Document Title
  #|author: username
  #|tags: [ first, second ]
  #|---
  #|= Document Title
  #|Author Name
  #|
  #|preamble
  #|

///|
test "should not skip front matter by default" {
  let doc = new_doc(front_matter_input)
  let reader = doc_reader(doc)
  assert_false(doc.attributes.contains("front-matter"))
  debug_inspect(reader.peek_line(), content="Some(\"---\")")
  inspect(reader.lineno(), content="1")
}

///|
test "should not skip front matter if ending delimiter is not found" {
  let input =
    #|---
    #|title: Document Title
    #|tags: [ first, second ]
    #|= Document Title
    #|Author Name
    #|
    #|preamble
    #|
  let doc = new_doc(input, attributes=[("skip-front-matter", Str(""))])
  let reader = doc_reader(doc)
  debug_inspect(reader.peek_line(), content="Some(\"---\")")
  assert_false(doc.attributes.contains("front-matter"))
  inspect(reader.lineno(), content="1")
}

///|
test "should skip front matter if specified by skip-front-matter attribute" {
  let doc = new_doc(front_matter_input, attributes=[
    ("skip-front-matter", Str("")),
  ])
  let reader = doc_reader(doc)
  debug_inspect(reader.peek_line(), content="Some(\"= Document Title\")")
  inspect(
    doc.attributes.str("front-matter").unwrap(),
    content=(
      #|layout: post
      #|title: Document Title
      #|author: username
      #|tags: [ first, second ]
    ),
  )
  inspect(reader.lineno(), content="7")
}

///|
test "should skip TOML front matter if specified by skip-front-matter attribute" {
  let input =
    #|+++
    #|layout = 'post'
    #|title = 'Document Title'
    #|author = 'username'
    #|tags = ['first', 'second']
    #|+++
    #|= Document Title
    #|Author Name
    #|
    #|preamble
    #|
  let doc = new_doc(input, attributes=[("skip-front-matter", Str(""))])
  let reader = doc_reader(doc)
  debug_inspect(reader.peek_line(), content="Some(\"= Document Title\")")
  inspect(
    doc.attributes.str("front-matter").unwrap(),
    content=(
      #|layout = 'post'
      #|title = 'Document Title'
      #|author = 'username'
      #|tags = ['first', 'second']
    ),
  )
  inspect(reader.lineno(), content="7")
}

///|
test "should not skip front matter in include file if skip-front-matter attribute is set" {
  let input =
    #|....
    #|include::fixtures/with-front-matter.adoc[]
    #|....
    #|
  let doc = document_from_string(
    input,
    safe=@core.SAFE_SAFE,
    parse=false,
    base_dir=testdir,
  )
  debug_inspect(
    doc_reader(doc).read_lines(),
    content="[\"....\", \"---\", \"name: value\", \"---\", \"content\", \"....\"]",
  )
  assert_false(doc.has_attr("front-matter"))
}

///|
test "should skip front matter in include file if skip-front-matter option is set on include directiv" {
  let input =
    #|....
    #|include::fixtures/with-front-matter.adoc[opts=skip-front-matter]
    #|....
    #|
  let doc = document_from_string(
    input,
    safe=@core.SAFE_SAFE,
    parse=false,
    base_dir=testdir,
  )
  debug_inspect(
    doc_reader(doc).read_lines(),
    content="[\"....\", \"content\", \"....\"]",
  )
  assert_false(doc.has_attr("front-matter"))
}

// ---------------------------------------------------------------------------
// PreprocessorReader: Include Stack

///|
test "PreprocessorReader#push_include method should put lines on top of stack" {
  let doc = @core.new_document(Some(["a", "b", "c"]), @core.Options::new())
  let reader = doc_reader(doc)
  reader.push_include_lines(["one", "two", "three"], file="", path="<stdin>")
  inspect(reader.include_depth(), content="1")
  debug_inspect(reader.read_line(), content="Some(\"one\")")
}

///|
test "PreprocessorReader#push_include method should gracefully handle file and path" {
  let doc = @core.new_document(Some(["a", "b", "c"]), @core.Options::new())
  let reader = doc_reader(doc)
  reader.push_include_lines(["one", "two", "three"])
  inspect(reader.include_depth(), content="1")
  debug_inspect(reader.read_line(), content="Some(\"one\")")
  debug_inspect(reader.file(), content="None")
  inspect(reader.path(), content="<stdin>")
}

///|
test "PreprocessorReader#push_include method should set path from file automatically if not specified" {
  let doc = @core.new_document(Some(["a", "b", "c"]), @core.Options::new())
  let reader = doc_reader(doc)
  reader.push_include_lines(["one", "two", "three"], file="/tmp/lines.adoc")
  debug_inspect(reader.file(), content="Some(\"/tmp/lines.adoc\")")
  inspect(reader.path(), content="lines.adoc")
  debug_inspect(doc.catalog().includes.get("lines"), content="Some(true)")
}

///|
test "PreprocessorReader#push_include method should accept file as a URI and compute dir and path" {
  let reader = doc_reader(@core.new_document(Some([]), @core.Options::new()))
  reader.push_include_lines(
    ["one", "two", "three"],
    file="http://example.com/docs/file.adoc",
  )
  debug_inspect(
    reader.file(),
    content="Some(\"http://example.com/docs/file.adoc\")",
  )
  inspect(reader.dir(), content="http://example.com/docs")
  inspect(reader.path(), content="file.adoc")
}

///|
test "PreprocessorReader#push_include method should accept file as a top-level URI and compute dir and path" {
  let reader = doc_reader(@core.new_document(Some([]), @core.Options::new()))
  reader.push_include_lines(
    ["one", "two", "three"],
    file="http://example.com/index.adoc",
  )
  debug_inspect(
    reader.file(),
    content="Some(\"http://example.com/index.adoc\")",
  )
  inspect(reader.dir(), content="http://example.com")
  inspect(reader.path(), content="index.adoc")
}

///|
test "PreprocessorReader#push_include method should not fail if data is nil" {
  // there is no nil Array in MoonBit; empty data takes the same path
  let doc = @core.new_document(Some(["a", "b", "c"]), @core.Options::new())
  let reader = doc_reader(doc)
  reader.push_include_lines([], file="", path="<stdin>")
  inspect(reader.include_depth(), content="0")
  debug_inspect(reader.read_line(), content="Some(\"a\")")
}

///|
test "PreprocessorReader#push_include method should ignore dot in directory name when computing include path" {
  let doc = @core.new_document(Some(["a", "b", "c"]), @core.Options::new())
  let reader = doc_reader(doc)
  reader.push_include_lines(["one", "two", "three"], path="include.d/data")
  debug_inspect(reader.file(), content="None")
  inspect(reader.path(), content="include.d/data")
  debug_inspect(
    doc.catalog().includes.get("include.d/data"),
    content="Some(true)",
  )
}

// ---------------------------------------------------------------------------
// PreprocessorReader: Include Directive

///|
test "should replace include directive with link macro in default safe mode" {
  let reader = doc_reader(new_doc("include::include-file.adoc[]"))
  debug_inspect(
    reader.read_line(),
    content="Some(\"link:include-file.adoc[role=include]\")",
  )
}

///|
test "should not add role to link macro used to replace include directive in compat mode" {
  let reader = doc_reader(
    new_doc("include::include-file.adoc[]", attributes=[
      ("compat-mode", Str("")),
    ]),
  )
  debug_inspect(
    reader.read_line(),
    content="Some(\"link:include-file.adoc[]\")",
  )
}

///|
test "should escape spaces in target when generating link from include directive" {
  let reader = doc_reader(new_doc("include::foo bar baz.adoc[]"))
  debug_inspect(
    reader.read_line(),
    content="Some(\"link:pass:c[foo bar baz.adoc][role=include]\")",
  )
}

///|
test "should preserve attrlist when replacing include directive with link macro" {
  let reader = doc_reader(new_doc("include::include-file.adoc[leveloffset=+1]"))
  debug_inspect(
    reader.read_line(),
    content="Some(\"link:include-file.adoc[role=include,leveloffset=+1]\")",
  )
}

///|
test "should replace include directive with link macro if safe mode allows it, but allow-uri-read is not set" {
  let (line, messages) = @core.with_memory_logger(() => {
    doc_reader(
      new_doc(
        "include::https://example.org/dist/info.adoc[]",
        safe=@core.SAFE_SAFE,
      ),
    ).read_line()
  })
  debug_inspect(
    line,
    content="Some(\"link:https://example.org/dist/info.adoc[role=include]\")",
  )
  inspect(
    fmt_logs(messages),
    content="WARN: <stdin>: line 1: cannot include contents of URI: https://example.org/dist/info.adoc (allow-uri-read attribute not enabled)",
  )
}

///|
test "should not add role to link macro that replaces include directive with remote target in compat mode" {
  let (line, messages) = @core.with_memory_logger(() => {
    doc_reader(
      new_doc(
        "include::https://example.org/dist/info.adoc[]",
        safe=@core.SAFE_SAFE,
        attributes=[("compat-mode", Str(""))],
      ),
    ).read_line()
  })
  debug_inspect(
    line,
    content="Some(\"link:https://example.org/dist/info.adoc[]\")",
  )
  inspect(
    fmt_logs(messages),
    content="WARN: <stdin>: line 1: cannot include contents of URI: https://example.org/dist/info.adoc (allow-uri-read attribute not enabled)",
  )
}

///|
test "should escape spaces in target when generating link from remote include directive" {
  let (line, messages) = @core.with_memory_logger(() => {
    doc_reader(
      new_doc(
        "include::https://example.org/no such file.adoc[]",
        safe=@core.SAFE_SAFE,
      ),
    ).read_line()
  })
  debug_inspect(
    line,
    content="Some(\"link:pass:c[https://example.org/no such file.adoc][role=include]\")",
  )
  inspect(
    fmt_logs(messages),
    content="WARN: <stdin>: line 1: cannot include contents of URI: https://example.org/no such file.adoc (allow-uri-read attribute not enabled)",
  )
}

///|
test "should preserve attrlist when replacing remove include directive with link macro" {
  let (line, messages) = @core.with_memory_logger(() => {
    doc_reader(
      new_doc(
        "include::https://example.org/dist/info.adoc[leveloffset=+1]",
        safe=@core.SAFE_SAFE,
      ),
    ).read_line()
  })
  debug_inspect(
    line,
    content="Some(\"link:https://example.org/dist/info.adoc[role=include,leveloffset=+1]\")",
  )
  inspect(
    fmt_logs(messages),
    content="WARN: <stdin>: line 1: cannot include contents of URI: https://example.org/dist/info.adoc (allow-uri-read attribute not enabled)",
  )
}

///|
test "include directive with remote target is converted to a link when allow-uri-read is not set" {
  let (line, messages) = @core.with_memory_logger(() => {
    doc_reader(
      new_doc("include::http://example.org/team.adoc[]", safe=@core.SAFE_SAFE),
    ).read_line()
  })
  debug_inspect(
    line,
    content="Some(\"link:http://example.org/team.adoc[role=include]\")",
  )
  inspect(
    fmt_logs(messages),
    content="WARN: <stdin>: line 1: cannot include contents of URI: http://example.org/team.adoc (allow-uri-read attribute not enabled)",
  )
}

///|
test "include directive with remote target is converted to a link when safe mode is secure" {
  let (line, messages) = @core.with_memory_logger(() => {
    doc_reader(
      new_doc("include::http://example.org/team.adoc[]", safe=@core.SAFE_SECURE),
    ).read_line()
  })
  debug_inspect(
    line,
    content="Some(\"link:http://example.org/team.adoc[role=include]\")",
  )
  inspect(messages.length(), content="0")
}

///|
test "include directive is enabled when safe mode is less than SECURE" {
  let doc = document_from_string(
    "include::fixtures/include-file.adoc[]",
    safe=@core.SAFE_SAFE,
    standalone=false,
    base_dir=testdir,
  )
  debug_inspect(
    doc.blocks[0].lines,
    content=(
      #|[
      #|  "first line of included content",
      #|  "second line of included content",
      #|  "third line of included content",
      #|  "fourth line of included content",
      #|  "fifth line of included content",
      #|  "sixth line of included content",
      #|  "seventh line of included content",
      #|  "eighth line of included content",
      #|]
    ),
  )
  debug_inspect(
    doc.catalog().includes.get("fixtures/include-file"),
    content="Some(true)",
  )
}

///|
test "should strip BOM from include file" {
  let input = ":showtitle:\ninclude::fixtures/file-with-utf8-bom.adoc[]"
  let doc = document_from_string(
    input,
    safe=@core.SAFE_SAFE,
    base_dir=testdir,
    parse=false,
  )
  debug_inspect(
    doc_reader(doc).read_lines(),
    content="[\":showtitle:\", \"= 人\"]",
  )
  let doc = document_from_string(
    input,
    safe=@core.SAFE_SAFE,
    base_dir=testdir,
    standalone=false,
  )
  debug_inspect(doc.doctitle(), content="Some(\"人\")")
  inspect(doc.blocks.length(), content="0")
}

///|
test "should not track include in catalog for non-AsciiDoc include files" {
  let input =
    #|----
    #|include::fixtures/circle.svg[]
    #|----
    #|
  let doc = document_from_string(
    input,
    safe=@core.SAFE_SAFE,
    standalone=false,
    base_dir=testdir,
  )
  inspect(doc.catalog().includes.length(), content="0")
}

///|
fn vfs_with_include_file_with_space() -> @core.MemoryVfs {
  let vfs = fixtures_vfs()
  vfs.add_bytes(
    "\{fixturesdir}/include file.adoc",
    vfs.files["\{fixturesdir}/include-file.adoc"],
  )
  vfs
}

///|
test "include directive should resolve file with spaces in name" {
  let doc = document_from_string(
    "include::fixtures/include file.adoc[]",
    safe=@core.SAFE_SAFE,
    standalone=false,
    base_dir=testdir,
    vfs=vfs_with_include_file_with_space(),
  )
  debug_inspect(
    doc.blocks[0].lines[0],
    content="\"first line of included content\"",
  )
}

///|
test "include directive should resolve file with {sp} in name" {
  let doc = document_from_string(
    "include::fixtures/include{sp}file.adoc[]",
    safe=@core.SAFE_SAFE,
    standalone=false,
    base_dir=testdir,
    vfs=vfs_with_include_file_with_space(),
  )
  debug_inspect(
    doc.blocks[0].lines[0],
    content="\"first line of included content\"",
  )
}

///|
test "include directive should not match if target is empty or starts or ends with space" {
  for
    input in [
      "include::[]", "include:: []", "include:: not-include[]", "include::not-include []",
    ] {
    let reader = doc_reader(new_doc(input))
    assert_eq(reader.read_line(), Some(input))
  }
}

///|
test "include directive should not attempt to resolve target as remote if allow-uri-read is set and URL is not on first line" {
  let input =
    #|:target: not-a-file.adoc + \
    #|http://example.org/team.adoc
    #|
    #|include::{target}[]
    #|
  let (doc, messages) = @core.with_memory_logger(() => {
    document_from_string(input, safe=@core.SAFE_SAFE, base_dir=fixturesdir)
  })
  debug_inspect(
    doc.blocks[0].lines,
    content=(
      #|["Unresolved directive in <stdin> - include::not-a-file.adoc +\nhttp://example.org/team.adoc[]"]
    ),
  )
  inspect(
    fmt_logs(messages),
    content=(
      #|ERROR: <stdin>: line 4: include file not found: /asciidoctor/test/fixtures/not-a-file.adoc +
      #|http://example.org/team.adoc
    ),
  )
}

///|
test "include directive should resolve file relative to current include" {
  let pseudo_docfile = "\{testdir}/main.adoc"
  let doc = empty_safe_document()
  let reader = @core.Reader::new_preprocessor(
    doc,
    ["include::fixtures/parent-include.adoc[]"],
    cursor=@core.Cursor::new(file=pseudo_docfile),
    normalize=true,
  )
  debug_inspect(reader.file(), content="Some(\"/asciidoctor/test/main.adoc\")")
  inspect(reader.dir(), content="/asciidoctor/test")
  inspect(reader.path(), content="main.adoc")
  debug_inspect(reader.read_line(), content="Some(\"first line of parent\")")
  inspect(
    reader.cursor_at_prev_line().line_info(),
    content="fixtures/parent-include.adoc: line 1",
  )
  debug_inspect(
    reader.file(),
    content="Some(\"/asciidoctor/test/fixtures/parent-include.adoc\")",
  )
  inspect(reader.dir(), content="/asciidoctor/test/fixtures")
  inspect(reader.path(), content="fixtures/parent-include.adoc")
  reader.skip_blank_lines() |> ignore
  debug_inspect(reader.read_line(), content="Some(\"first line of child\")")
  inspect(
    reader.cursor_at_prev_line().line_info(),
    content="fixtures/child-include.adoc: line 1",
  )
  debug_inspect(
    reader.file(),
    content="Some(\"/asciidoctor/test/fixtures/child-include.adoc\")",
  )
  inspect(reader.dir(), content="/asciidoctor/test/fixtures")
  inspect(reader.path(), content="fixtures/child-include.adoc")
  reader.skip_blank_lines() |> ignore
  debug_inspect(
    reader.read_line(),
    content="Some(\"first line of grandchild\")",
  )
  inspect(
    reader.cursor_at_prev_line().line_info(),
    content="fixtures/grandchild-include.adoc: line 1",
  )
  debug_inspect(
    reader.file(),
    content="Some(\"/asciidoctor/test/fixtures/grandchild-include.adoc\")",
  )
  inspect(reader.dir(), content="/asciidoctor/test/fixtures")
  inspect(reader.path(), content="fixtures/grandchild-include.adoc")
  reader.skip_blank_lines() |> ignore
  debug_inspect(reader.read_line(), content="Some(\"last line of grandchild\")")
  reader.skip_blank_lines() |> ignore
  debug_inspect(reader.read_line(), content="Some(\"last line of child\")")
  reader.skip_blank_lines() |> ignore
  debug_inspect(reader.read_line(), content="Some(\"last line of parent\")")
  inspect(
    reader.cursor_at_prev_line().line_info(),
    content="fixtures/parent-include.adoc: line 5",
  )
  debug_inspect(
    reader.file(),
    content="Some(\"/asciidoctor/test/fixtures/parent-include.adoc\")",
  )
  inspect(reader.dir(), content="/asciidoctor/test/fixtures")
  inspect(reader.path(), content="fixtures/parent-include.adoc")
}

///|
test "include directive should process lines when file extension of target is .asciidoc" {
  let doc = document_from_string(
    "include::fixtures/include-alt-extension.asciidoc[]",
    safe=@core.SAFE_SAFE,
    base_dir=testdir,
  )
  inspect(doc.blocks.length(), content="3")
  debug_inspect(doc.blocks[0].lines, content="[\"first line\"]")
  debug_inspect(doc.blocks[1].lines, content="[\"Asciidoctor!\"]")
  debug_inspect(doc.blocks[2].lines, content="[\"last line\"]")
}

///|
test "should only strip trailing newlines, not trailing whitespace, if include file is not AsciiDoc" {
  let input =
    #|....
    #|include::fixtures/data.tsv[]
    #|....
    #|
  let doc = document_from_string(input, safe=@core.SAFE_SAFE, base_dir=testdir)
  inspect(doc.blocks.length(), content="1")
  debug_inspect(doc.blocks[0].lines[2], content="\"1\\t2\\t\"")
}

///|
test "should ignore encoding attribute if value is not a valid encoding" {
  let input =
    #|....
    #|include::fixtures/encoding.adoc[tag=romé,encoding=iso-1000-1]
    #|....
    #|
  let doc = document_from_string(input, safe=@core.SAFE_SAFE, base_dir=testdir)
  inspect(doc.blocks.length(), content="1")
  debug_inspect(
    doc.blocks[0].lines,
    content="[\"Gregory Romé has written an AsciiDoc plugin for the Redmine project management application.\"]",
  )
}

///|
test "should use encoding specified by encoding attribute when reading include file" {
  let input =
    #|....
    #|include::fixtures/iso-8859-1.txt[encoding=iso-8859-1]
    #|....
    #|
  let doc = document_from_string(input, safe=@core.SAFE_SAFE, base_dir=testdir)
  inspect(doc.blocks.length(), content="1")
  debug_inspect(doc.blocks[0].lines, content="[\"Où est l'hôpital ?\"]")
}

///|
test "unresolved target referenced by include directive is skipped when optional option is set" {
  let input =
    #|include::fixtures/{no-such-file}[opts=optional]
    #|
    #|trailing content
    #|
  let (doc, messages) = @core.with_memory_logger(() => {
    document_from_string(input, safe=@core.SAFE_SAFE, base_dir=testdir)
  })
  inspect(doc.blocks.length(), content="1")
  debug_inspect(doc.blocks[0].lines, content="[\"trailing content\"]")
  inspect(
    fmt_logs(messages),
    content="INFO: <stdin>: line 1: optional include dropped because include file not found: /asciidoctor/test/fixtures/{no-such-file}",
  )
}

///|
test "should skip include directive that references missing file if optional option is set" {
  let input =
    #|include::fixtures/no-such-file.adoc[opts=optional]
    #|
    #|trailing content
    #|
  let (doc, messages) = @core.with_memory_logger(() => {
    document_from_string(input, safe=@core.SAFE_SAFE, base_dir=testdir)
  })
  inspect(doc.blocks.length(), content="1")
  debug_inspect(doc.blocks[0].lines, content="[\"trailing content\"]")
  inspect(
    fmt_logs(messages),
    content="INFO: <stdin>: line 1: optional include dropped because include file not found: /asciidoctor/test/fixtures/no-such-file.adoc",
  )
}

///|
test "should replace include directive that references missing file with message" {
  let input =
    #|include::fixtures/no-such-file.adoc[]
    #|
    #|trailing content
    #|
  let (doc, messages) = @core.with_memory_logger(() => {
    document_from_string(input, safe=@core.SAFE_SAFE, base_dir=testdir)
  })
  inspect(doc.blocks.length(), content="2")
  debug_inspect(
    doc.blocks[0].lines,
    content="[\"Unresolved directive in <stdin> - include::fixtures/no-such-file.adoc[]\"]",
  )
  debug_inspect(doc.blocks[1].lines, content="[\"trailing content\"]")
  inspect(
    fmt_logs(messages),
    content="ERROR: <stdin>: line 1: include file not found: /asciidoctor/test/fixtures/no-such-file.adoc",
  )
}

///|
/// A file system in which one file exists but cannot be read.
struct UnreadableVfs {
  inner : @core.MemoryVfs
  unreadable : String
}

///|
impl @core.Vfs for UnreadableVfs with fn read(self, path) {
  if path == self.unreadable {
    None
  } else {
    @core.Vfs::read(self.inner, path)
  }
}

///|
impl @core.Vfs for UnreadableVfs with fn is_file(self, path) {
  @core.Vfs::is_file(self.inner, path)
}

///|
impl @core.Vfs for UnreadableVfs with fn is_dir(self, path) {
  @core.Vfs::is_dir(self.inner, path)
}

///|
impl @core.Vfs for UnreadableVfs with fn cwd(self) {
  @core.Vfs::cwd(self.inner)
}

///|
impl @core.Vfs for UnreadableVfs with fn home(self) {
  @core.Vfs::home(self.inner)
}

///|
test "should replace include directive that references unreadable file with message" {
  let input =
    #|include::fixtures/chapter-a.adoc[]
    #|
    #|trailing content
    #|
  let vfs : UnreadableVfs = {
    inner: fixtures_vfs(),
    unreadable: "\{fixturesdir}/chapter-a.adoc",
  }
  let (doc, messages) = @core.with_memory_logger(() => {
    @core.new_document(
      Some(@core.prepare_source_string(input)),
      @core.Options::new(safe=@core.SAFE_SAFE, base_dir=testdir, vfs~),
    ).parse()
  })
  inspect(doc.blocks.length(), content="2")
  debug_inspect(
    doc.blocks[0].lines,
    content="[\"Unresolved directive in <stdin> - include::fixtures/chapter-a.adoc[]\"]",
  )
  debug_inspect(doc.blocks[1].lines, content="[\"trailing content\"]")
  inspect(
    fmt_logs(messages),
    content="ERROR: <stdin>: line 1: include file not readable: /asciidoctor/test/fixtures/chapter-a.adoc",
  )
}

///|
test "can resolve include directive with absolute path" {
  let input = "include::\{fixturesdir}/chapter-a.adoc[]"
  let result = document_from_string(input, safe=@core.SAFE_SAFE)
  debug_inspect(result.doctitle(), content="Some(\"Chapter A\")")
  let result = document_from_string(
    input,
    safe=@core.SAFE_UNSAFE,
    base_dir="/tmp",
  )
  debug_inspect(result.doctitle(), content="Some(\"Chapter A\")")
}

///|
/// Emulates the test web server of the Ruby suite: files served at
/// http://localhost:9876 (the VFS is asked for the URI).
fn remote_vfs() -> @core.MemoryVfs {
  let vfs = fixtures_vfs()
  let base = "http://localhost:9876"
  vfs.add_text("\{base}/name/asciidoctor", "{\"name\": \"asciidoctor\"}\n")
  vfs.add_text(
    "\{base}/fixtures/outer-include.adoc",
    "first line of outer\n\ninclude::subdir/middle-include.adoc[]\n\nlast line of outer\n",
  )
  vfs.add_text(
    "\{base}/fixtures/subdir/middle-include.adoc",
    "first line of middle\n\ninclude::inner-include.adoc[]\n\nlast line of middle\n",
  )
  vfs.add_text(
    "\{base}/fixtures/subdir/inner-include.adoc",
    "first line of inner\n\nlast line of inner\n",
  )
  vfs.add_text(
    "\{base}/fixtures/file-with-missing-include.adoc",
    "include::no-such-file.adoc[]\n",
  )
  vfs.add_bytes(
    "\{base}/fixtures/tagged-class.rb",
    vfs.files["\{fixturesdir}/tagged-class.rb"],
  )
  vfs
}

///|
fn load_remote(input : String) -> (@core.Node, String) {
  let (doc, messages) = @core.with_memory_logger(() => {
    document_from_string(
      input,
      safe=@core.SAFE_SAFE,
      attributes=[("allow-uri-read", Str(""))],
      standalone=false,
      vfs=remote_vfs(),
    )
  })
  (doc, fmt_logs(messages))
}

///|
test "include directive can retrieve data from uri" {
  let (doc, logs) = load_remote(
    (
      #|....
      #|include::http://localhost:9876/name/asciidoctor[]
      #|....
    ),
  )
  debug_inspect(
    doc.blocks[0].lines,
    content="[\"{\\\"name\\\": \\\"asciidoctor\\\"}\"]",
  )
  inspect(logs, content="")
}

///|
test "nested remote include directive is resolved relative to uri of current file" {
  let (doc, logs) = load_remote(
    (
      #|....
      #|include::http://localhost:9876/fixtures/outer-include.adoc[]
      #|....
    ),
  )
  inspect(
    doc.blocks[0].source(),
    content=(
      #|first line of outer
      #|
      #|first line of middle
      #|
      #|first line of inner
      #|
      #|last line of inner
      #|
      #|last line of middle
      #|
      #|last line of outer
    ),
  )
  inspect(logs, content="")
}

///|
test "nested remote include directive that cannot be resolved does not crash processor" {
  let (doc, logs) = load_remote(
    (
      #|....
      #|include::http://localhost:9876/fixtures/file-with-missing-include.adoc[]
      #|....
    ),
  )
  inspect(
    doc.blocks[0].source(),
    content="Unresolved directive in http://localhost:9876/fixtures/file-with-missing-include.adoc - include::no-such-file.adoc[]",
  )
  inspect(
    logs,
    content="ERROR: http://localhost:9876/fixtures/file-with-missing-include.adoc: line 1: include uri not readable: http://localhost:9876/fixtures/no-such-file.adoc",
  )
}

///|
test "should support tag filtering for remote includes" {
  let (doc, _) = load_remote(
    (
      #|[source,ruby]
      #|----
      #|include::http://localhost:9876/fixtures/tagged-class.rb[tag=init,indent=0]
      #|----
    ),
  )
  inspect(
    doc.blocks[0].source(),
    content=(
      #|def initialize breed
      #|  @breed = breed
      #|end
    ),
  )
}

///|
test "should not crash if include directive references inaccessible uri" {
  let (doc, logs) = load_remote(
    (
      #|....
      #|include::http://localhost:9876/no_such_file[]
      #|....
    ),
  )
  inspect(
    doc.blocks[0].source(),
    content="Unresolved directive in <stdin> - include::http://localhost:9876/no_such_file[]",
  )
  inspect(
    logs,
    content="ERROR: <stdin>: line 2: include uri not readable: http://localhost:9876/no_such_file",
  )
}

///|
fn read_include(input : String) -> (Array[String], String) {
  let (lines, messages) = @core.with_memory_logger(() => {
    let doc = document_from_string(
      input,
      safe=@core.SAFE_SAFE,
      parse=false,
      base_dir=testdir,
    )
    doc_reader(doc).read_lines()
  })
  (lines, fmt_logs(messages))
}

///|
test "include directive supports selecting lines by line number" {
  let (lines, _) = read_include(
    "include::fixtures/include-file.adoc[lines=1;3..4;6..-1]",
  )
  debug_inspect(
    lines[:7].to_owned(),
    content=(
      #|[
      #|  "first line of included content",
      #|  "third line of included content",
      #|  "fourth line of included content",
      #|  "sixth line of included content",
      #|  "seventh line of included content",
      #|  "eighth line of included content",
      #|  "",
      #|]
    ),
  )
  inspect(lines.length(), content="22")
  debug_inspect(lines.last(), content="Some(\"last line of included content\")")
}

///|
test "include directive supports line ranges separated by commas in quoted attribute value" {
  let (expected, _) = read_include(
    "include::fixtures/include-file.adoc[lines=1;3..4;6..-1]",
  )
  let (lines, _) = read_include(
    "include::fixtures/include-file.adoc[lines=\"1,3..4,6..-1\"]",
  )
  assert_eq(lines, expected)
}

///|
test "include directive ignores spaces between line ranges in quoted attribute value" {
  let (expected, _) = read_include(
    "include::fixtures/include-file.adoc[lines=1;3..4;6..-1]",
  )
  let (lines, _) = read_include(
    "include::fixtures/include-file.adoc[lines=\"1, 3..4 , 6 .. -1\"]",
  )
  assert_eq(lines, expected)
}

///|
test "include directive supports implicit endless range" {
  let (lines, _) = read_include(
    "include::fixtures/include-file.adoc[lines=6..]",
  )
  debug_inspect(
    lines[:3].to_owned(),
    content=(
      #|[
      #|  "sixth line of included content",
      #|  "seventh line of included content",
      #|  "eighth line of included content",
      #|]
    ),
  )
  inspect(lines.length(), content="19")
}

///|
test "include directive ignores lines attribute if empty" {
  let (lines, _) = read_include("include::fixtures/include-file.adoc[lines=]")
  inspect(lines.length(), content="24")
  debug_inspect(lines[0], content="\"first line of included content\"")
  debug_inspect(lines[23], content="\"last line of included content\"")
}

///|
test "include directive ignores lines attribute with invalid range" {
  let (lines, _) = read_include(
    "include::fixtures/include-file.adoc[lines=10..5]",
  )
  inspect(lines.length(), content="24")
  debug_inspect(lines[0], content="\"first line of included content\"")
  debug_inspect(lines[23], content="\"last line of included content\"")
}

///|
test "include directive supports selecting lines by tag" {
  let (lines, _) = read_include(
    "include::fixtures/include-file.adoc[tag=snippetA]",
  )
  debug_inspect(lines, content="[\"snippetA content\"]")
}

///|
test "include directive supports selecting lines by tags" {
  let (lines, _) = read_include(
    "include::fixtures/include-file.adoc[tags=snippetA;snippetB]",
  )
  debug_inspect(lines, content="[\"snippetA content\", \"snippetB content\"]")
}

///|
test "include directive supports selecting lines by tag in language that uses circumfix comments" {
  for
    pair in [
      ("include-file.xml", "<snippet>content</snippet>"),
      ("include-file.ml", "let s = SS.empty;;"),
      ("include-file.jsx", "<p>Welcome to the club.</p>"),
    ] {
    let (filename, expect) = pair
    let input =
      $|[source,xml]
      $|----
      $|include::fixtures/\{filename}[tag=snippet,indent=0]
      $|----
      $|
    let doc = document_from_string(
      input,
      safe=@core.SAFE_SAFE,
      base_dir=testdir,
    )
    assert_eq(doc.blocks[0].source(), expect)
  }
}

///|
test "include directive supports selecting lines by tag in file that has CRLF line endings" {
  let vfs = @core.MemoryVfs::new(cwd="/tmp")
  vfs.add_text(
    "/tmp/include-crlf.adoc", "do not include\r\ntag::include-me[]\r\nincluded line\r\nend::include-me[]\r\ndo not include\r\n",
  )
  let doc = @core.new_document(
    Some(["include::include-crlf.adoc[tag=include-me]"]),
    @core.Options::new(safe=@core.SAFE_SAFE, base_dir="/tmp", parse=false, vfs~),
  )
  debug_inspect(doc_reader(doc).read_lines(), content="[\"included line\"]")
}

///|
test "include directive finds closing tag on last line of file without a trailing newline" {
  let vfs = @core.MemoryVfs::new(cwd="/tmp")
  vfs.add_text(
    "/tmp/include-nonl.adoc", "line not included\ntag::include-me[]\nline included\nend::include-me[]",
  )
  let (lines, messages) = @core.with_memory_logger(() => {
    let doc = @core.new_document(
      Some(["include::include-nonl.adoc[tag=include-me]"]),
      @core.Options::new(safe=@core.SAFE_SAFE, base_dir="/tmp", vfs~),
    )
    doc_reader(doc).read_lines()
  })
  debug_inspect(lines, content="[\"line included\"]")
  inspect(messages.length(), content="0")
}

///|
test "include directive does not select lines containing tag directives within selected tag region" {
  let (lines, _) = read_include(
    "include::fixtures/include-file.adoc[tags=snippet]",
  )
  debug_inspect(
    lines,
    content="[\"snippetA content\", \"\", \"non-tagged content\", \"\", \"snippetB content\"]",
  )
}

///|
let dog_without_bark : String =
  #|class Dog
  #|  def initialize breed
  #|    @breed = breed
  #|  end
  #|end

///|
let dog_all : String =
  #|class Dog
  #|  def initialize breed
  #|    @breed = breed
  #|  end
  #|
  #|  def bark
  #|    if @breed == 'beagle'
  #|      'woof woof woof woof woof'
  #|    else
  #|      'woof woof'
  #|    end
  #|  end
  #|end

///|
let dog_without_init : String =
  #|class Dog
  #|
  #|  def bark
  #|    if @breed == 'beagle'
  #|      'woof woof woof woof woof'
  #|    else
  #|      'woof woof'
  #|    end
  #|  end
  #|end

///|
fn read_tagged(file : String, tags : String) -> String {
  let (lines, _) = read_include("include::fixtures/\{file}[\{tags}]")
  lines.join("\n")
}

///|
test "include directive skips lines inside tag which is negated" {
  assert_eq(
    read_tagged("tagged-class-enclosed.rb", "tags=all;!bark"),
    dog_without_bark,
  )
}

///|
test "include directive selects all lines without a tag directive when value is double asterisk" {
  assert_eq(read_tagged("tagged-class.rb", "tags=**"), dog_all)
}

///|
test "include directive selects all lines except lines inside tag which is negated when value starts with double asterisk" {
  assert_eq(read_tagged("tagged-class.rb", "tags=**;!bark"), dog_without_bark)
}

///|
test "include directive selects all lines, including lines inside nested tags, except lines inside tag which is negated when value starts with double asterisk" {
  assert_eq(read_tagged("tagged-class.rb", "tags=**;!init"), dog_without_init)
}

///|
test "include directive selects all lines outside of tags when value is double asterisk followed by negated wildcard" {
  inspect(
    read_tagged("tagged-class.rb", "tags=**;!*"),
    content=(
      #|class Dog
      #|end
    ),
  )
}

///|
test "include directive skips all tagged regions when value of tags attribute is negated wildcard" {
  inspect(
    read_tagged("tagged-class.rb", "tags=!*"),
    content=(
      #|class Dog
      #|end
    ),
  )
}

///|
test "include directive selects all lines except for lines containing tag directive if value is double asterisk followed by nested tag names" {
  assert_eq(
    read_tagged("tagged-class.rb", "tags=**;bark-beagle;bark-all"),
    dog_all,
  )
}

///|
test "include directive selects all lines except for lines containing tag directive when value is double asterisk followed by outer tag name" {
  assert_eq(read_tagged("tagged-class.rb", "tags=**;bark"), dog_all)
}

///|
test "include directive selects all lines inside unspecified tags when value is negated double asterisk followed by negated tags" {
  inspect(
    read_tagged("tagged-class.rb", "tags=!**;!init"),
    content=(
      #|
      #|  def bark
      #|    if @breed == 'beagle'
      #|      'woof woof woof woof woof'
      #|    else
      #|      'woof woof'
      #|    end
      #|  end
    ),
  )
}

///|
test "include directive selects all lines except tag which is negated when value only contains negated tag" {
  assert_eq(read_tagged("tagged-class.rb", "tag=!bark"), dog_without_bark)
}

///|
test "include directive selects all lines except tags which are negated when value only contains negated tags" {
  inspect(
    read_tagged("tagged-class.rb", "tags=!bark;!init"),
    content=(
      #|class Dog
      #|end
    ),
  )
}

///|
test "should recognize tag wildcard if not at start of tags list" {
  inspect(
    read_tagged("tagged-class.rb", "tags=init;**;*;!bark-other"),
    content=(
      #|class Dog
      #|  def initialize breed
      #|    @breed = breed
      #|  end
      #|
      #|  def bark
      #|    if @breed == 'beagle'
      #|      'woof woof woof woof woof'
      #|    end
      #|  end
      #|end
    ),
  )
}

///|
test "include directive selects lines between tags when value of tags attribute is wildcard" {
  inspect(
    read_tagged("tagged-class.rb", "tags=*"),
    content=(
      #|  def initialize breed
      #|    @breed = breed
      #|  end
      #|
      #|  def bark
      #|    if @breed == 'beagle'
      #|      'woof woof woof woof woof'
      #|    else
      #|      'woof woof'
      #|    end
      #|  end
    ),
  )
}

///|
test "include directive selects lines inside tags when value of tags attribute is wildcard and tag surrounds content" {
  assert_eq(read_tagged("tagged-class-enclosed.rb", "tags=*"), dog_all)
}

///|
test "include directive selects lines inside all tags except tag which is negated when value of tags attribute is wildcard followed by negated tag" {
  assert_eq(
    read_tagged("tagged-class-enclosed.rb", "tags=*;!init"),
    dog_without_init,
  )
}

///|
test "include directive skips all tagged regions except ones re-enabled when value of tags attribute is negated wildcard followed by tag name" {
  inspect(
    read_tagged("tagged-class.rb", "tags=!*;bark"),
    content=(
      #|class Dog
      #|
      #|  def bark
      #|  end
      #|end
    ),
  )
}

///|
test "include directive includes lines inside tag except for lines inside nested tags when tag is followed by negated wildcard" {
  inspect(
    read_tagged("tagged-class.rb", "tags=!**;!*;bark"),
    content=(
      #|
      #|  def bark
      #|  end
    ),
  )
}

///|
test "include directive does not select lines inside tag that has been included then excluded" {
  inspect(
    read_tagged("tagged-class.rb", "tags=!*;init;!init"),
    content=(
      #|class Dog
      #|end
    ),
  )
}

///|
test "include directive selects lines inside specified tag and ignores lines inside a negated tag" {
  inspect(
    read_tagged("tagged-class.rb", "tags=bark;!bark-other"),
    content=(
      #|
      #|  def bark
      #|    if @breed == 'beagle'
      #|      'woof woof woof woof woof'
      #|    end
      #|  end
    ),
  )
}

///|
test "should warn if specified tag is not found in include file" {
  let (lines, logs) = read_include(
    "include::fixtures/include-file.adoc[tag=no-such-tag]",
  )
  debug_inspect(lines, content="[]")
  inspect(
    logs,
    content="WARN: <stdin>: line 1: tag 'no-such-tag' not found in include file: /asciidoctor/test/fixtures/include-file.adoc",
  )
}

///|
test "should not warn if specified negated tag is not found in include file" {
  let (lines, logs) = read_include(
    "include::fixtures/tagged-class-enclosed.rb[tag=!no-such-tag]",
  )
  assert_eq(lines.join("\n"), dog_all)
  inspect(logs, content="")
}

///|
test "should warn if specified tags are not found in include file" {
  let (lines, logs) = read_include(
    (
      #|++++
      #|include::fixtures/include-file.adoc[tags=no-such-tag-b;no-such-tag-a]
      #|++++
    ),
  )
  debug_inspect(lines, content="[\"++++\", \"++++\"]")
  inspect(
    logs,
    content="WARN: <stdin>: line 2: tags 'no-such-tag-b, no-such-tag-a' not found in include file: /asciidoctor/test/fixtures/include-file.adoc",
  )
}

///|
test "should not warn if specified negated tags are not found in include file" {
  let (lines, logs) = read_include(
    "include::fixtures/tagged-class-enclosed.rb[tags=all;!no-such-tag;!unknown-tag]",
  )
  assert_eq(lines.join("\n"), dog_all)
  inspect(logs, content="")
}

///|
test "should warn if specified tag in include file is not closed" {
  let (messages_lines, messages) = @core.with_memory_logger(() => {
    let doc = document_from_string(
      (
        #|++++
        #|include::fixtures/unclosed-tag.adoc[tag=a]
        #|++++
      ),
      safe=@core.SAFE_SAFE,
      parse=false,
      base_dir=testdir,
    )
    doc_reader(doc).read_lines()
  })
  debug_inspect(messages_lines, content="[\"++++\", \"a\", \"++++\"]")
  inspect(
    fmt_logs(messages),
    content="WARN: <stdin>: line 2: detected unclosed tag 'a' starting at line 2 of include file: /asciidoctor/test/fixtures/unclosed-tag.adoc",
  )
  inspect(
    messages[0].include_location.unwrap().line_info(),
    content="fixtures/unclosed-tag.adoc: line 2",
  )
}

///|
test "should warn if end tag in included file is mismatched" {
  let (lines, messages) = @core.with_memory_logger(() => {
    let doc = document_from_string(
      (
        #|++++
        #|include::fixtures/mismatched-end-tag.adoc[tags=a;b]
        #|++++
      ),
      safe=@core.SAFE_SAFE,
      parse=false,
      base_dir=testdir,
    )
    doc_reader(doc).read_lines()
  })
  debug_inspect(lines, content="[\"++++\", \"a\", \"b\", \"++++\"]")
  inspect(
    fmt_logs(messages),
    content="WARN: <stdin>: line 2: mismatched end tag (expected 'b' but found 'a') at line 5 of include file: /asciidoctor/test/fixtures/mismatched-end-tag.adoc",
  )
  assert_true(messages[0].include_location is Some(_))
}

///|
test "should warn if unexpected end tag is found in included file" {
  let (lines, messages) = @core.with_memory_logger(() => {
    let doc = document_from_string(
      (
        #|++++
        #|include::fixtures/unexpected-end-tag.adoc[tags=a]
        #|++++
      ),
      safe=@core.SAFE_SAFE,
      parse=false,
      base_dir=testdir,
    )
    doc_reader(doc).read_lines()
  })
  debug_inspect(lines, content="[\"++++\", \"a\", \"++++\"]")
  inspect(
    fmt_logs(messages),
    content="WARN: <stdin>: line 2: unexpected end tag 'a' at line 4 of include file: /asciidoctor/test/fixtures/unexpected-end-tag.adoc",
  )
  assert_true(messages[0].include_location is Some(_))
}

///|
test "include directive ignores tags attribute when empty" {
  for attr_name in ["tag", "tags"] {
    let (lines, _) = read_include(
      "include::fixtures/include-file.xml[\{attr_name}=]",
    )
    debug_inspect(
      lines,
      content=(
        #|[
        #|  "<root>",
        #|  "  <!-- tag::snippet[] -->",
        #|  "  <snippet>content</snippet>",
        #|  "  <!-- end::snippet[] -->",
        #|  "</root>",
        #|]
      ),
    )
  }
}

///|
test "lines attribute takes precedence over tags attribute in include directive" {
  let (lines, _) = read_include(
    "include::fixtures/include-file.adoc[lines=1, tags=snippetA;snippetB]",
  )
  debug_inspect(lines, content="[\"first line of included content\"]")
}

///|
test "indent of included file can be reset to size of indent attribute" {
  let (lines, _) = read_include(
    "include::fixtures/basic-docinfo.xml[lines=2..3, indent=0]",
  )
  debug_inspect(
    lines,
    content="[\"<year>2013</year>\", \"<holder>Acme™, Inc.</holder>\"]",
  )
}

///|
test "should substitute attribute references in attrlist" {
  let input =
    #|:name-of-tag: snippetA
    #|include::fixtures/include-file.adoc[tag={name-of-tag}]
    #|
  let doc = document_from_string(input, safe=@core.SAFE_SAFE, base_dir=testdir)
  inspect(doc.blocks.length(), content="1")
  debug_inspect(doc.blocks[0].lines, content="[\"snippetA content\"]")
}

///|
test "should fall back to built-in include directive behavior when not handled by include processor" {
  let exts = @core.Extensions::new()
  exts.include_processor(
    (_doc, _reader, _target, _attrs) => {
      abort("TestIncludeHandler should not have been invoked")
    },
    handles=(_doc, _target) => false,
  )
  let document = empty_safe_document(extensions=exts)
  let reader = @core.Reader::new_preprocessor(
    document,
    ["include::fixtures/include-file.adoc[]"],
    normalize=true,
  )
  let source = reader.read_lines().join("\n")
  assert_true(source.contains("included content"))
}

///|
test "leveloffset attribute entries should be added to content if leveloffset attribute is specified" {
  let document = document_from_string(
    "include::fixtures/main.adoc[]",
    safe=@core.SAFE_SAFE,
    base_dir=testdir,
    parse=false,
  )
  debug_inspect(
    doc_reader(document).read_lines(),
    content=(
      #|[
      #|  "= Main Document",
      #|  "",
      #|  "preamble",
      #|  "",
      #|  ":leveloffset: +1",
      #|  "",
      #|  "= Chapter A",
      #|  "",
      #|  "content",
      #|  "",
      #|  ":leveloffset!:",
      #|]
    ),
  )
}

///|
test "attributes are substituted in target of include directive" {
  let input =
    #|:fixturesdir: fixtures
    #|:ext: adoc
    #|
    #|include::{fixturesdir}/include-file.{ext}[]
    #|
  let doc = document_from_string(input, safe=@core.SAFE_SAFE, base_dir=testdir)
  debug_inspect(
    doc.blocks[0].lines[0],
    content="\"first line of included content\"",
  )
}

///|
test "line is skipped by default if target of include directive resolves to empty" {
  let (line, messages) = @core.with_memory_logger(() => {
    let doc = empty_safe_document()
    let reader = @core.Reader::new_preprocessor(
      doc,
      ["include::{blank}[]"],
      normalize=true,
    )
    reader.read_line()
  })
  debug_inspect(
    line,
    content="Some(\"Unresolved directive in <stdin> - include::{blank}[]\")",
  )
  inspect(
    fmt_logs(messages),
    content="WARN: <stdin>: line 1: include dropped because resolved target is blank: include::{blank}[]",
  )
}

///|
test "include is dropped if target contains missing attribute and attribute-missing is drop-line" {
  let (line, messages) = @core.with_memory_logger(() => {
    let doc = empty_safe_document(attributes=[
      ("attribute-missing", Str("drop-line")),
    ])
    let reader = @core.Reader::new_preprocessor(
      doc,
      ["include::{foodir}/include-file.adoc[]"],
      normalize=true,
    )
    reader.read_line()
  })
  debug_inspect(line, content="None")
  inspect(
    fmt_logs(messages),
    content=(
      #|INFO: dropping line containing reference to missing attribute: foodir
      #|INFO: <stdin>: line 1: include dropped due to missing attribute: include::{foodir}/include-file.adoc[]
    ),
  )
}

///|
test "line following dropped include is not dropped" {
  let (lines, messages) = @core.with_memory_logger(() => {
    let doc = empty_safe_document(attributes=[
      ("attribute-missing", Str("warn")),
    ])
    let reader = @core.Reader::new_preprocessor(
      doc,
      ["include::{foodir}/include-file.adoc[]", "yo"],
      normalize=true,
    )
    [reader.read_line(), reader.read_line()]
  })
  debug_inspect(
    lines,
    content=(
      #|[
      #|  Some("Unresolved directive in <stdin> - include::{foodir}/include-file.adoc[]"),
      #|  Some("yo"),
      #|]
    ),
  )
  inspect(
    fmt_logs(messages),
    content=(
      #|INFO: dropping line containing reference to missing attribute: foodir
      #|WARN: <stdin>: line 1: include dropped due to missing attribute: include::{foodir}/include-file.adoc[]
    ),
  )
}

///|
test "escaped include directive is left unprocessed" {
  let doc = empty_safe_document()
  let reader = @core.Reader::new_preprocessor(
    doc,
    ["\\include::fixtures/include-file.adoc[]", "\\escape preserved here"],
    normalize=true,
  )
  // we should be able to peek it multiple times and still have the backslash preserved
  debug_inspect(
    reader.peek_line(),
    content="Some(\"include::fixtures/include-file.adoc[]\")",
  )
  debug_inspect(
    reader.peek_line(),
    content="Some(\"include::fixtures/include-file.adoc[]\")",
  )
  debug_inspect(
    reader.read_line(),
    content="Some(\"include::fixtures/include-file.adoc[]\")",
  )
  debug_inspect(
    reader.read_line(),
    content="Some(\"\\\\escape preserved here\")",
  )
}

///|
test "include directive not at start of line is ignored" {
  let para = block_from_string(" include::include-file.adoc[]")
  inspect(para.lines.length(), content="1")
  // NOTE the space gets stripped because the line is treated as an inline literal
  debug_inspect(para.context, content="Literal")
  inspect(para.source(), content="include::include-file.adoc[]")
}

///|
test "include directive is disabled when max-include-depth attribute is 0" {
  let para = block_from_string(
    "include::include-file.adoc[]",
    safe=@core.SAFE_SAFE,
    attributes=[("max-include-depth", Int(0))],
  )
  inspect(para.lines.length(), content="1")
  inspect(para.source(), content="include::include-file.adoc[]")
}

///|
test "max-include-depth cannot be set by document" {
  let input =
    #|:max-include-depth: 1
    #|
    #|include::include-file.adoc[]
    #|
  let para = block_from_string(input, safe=@core.SAFE_SAFE, attributes=[
    ("max-include-depth", Int(0)),
  ])
  inspect(para.lines.length(), content="1")
  inspect(para.source(), content="include::include-file.adoc[]")
}

///|
test "include directive should be disabled if max include depth has been exceeded" {
  let (lines, messages) = @core.with_memory_logger(() => {
    let doc = empty_safe_document()
    let reader = @core.Reader::new_preprocessor(
      doc,
      ["include::fixtures/parent-include.adoc[depth=1]"],
      cursor=@core.Cursor::new(file="\{testdir}/main.adoc"),
      normalize=true,
    )
    reader.read_lines()
  })
  assert_true(lines.contains("include::grandchild-include.adoc[]"))
  inspect(
    fmt_logs(messages),
    content="ERROR: fixtures/child-include.adoc: line 3: maximum include depth of 1 exceeded",
  )
}

///|
test "include directive should be disabled if max include depth set in nested context has been exceeded" {
  let (lines, messages) = @core.with_memory_logger(() => {
    let doc = empty_safe_document()
    let reader = @core.Reader::new_preprocessor(
      doc,
      ["include::fixtures/parent-include-restricted.adoc[depth=3]"],
      cursor=@core.Cursor::new(file="\{testdir}/main.adoc"),
      normalize=true,
    )
    reader.read_lines()
  })
  assert_true(lines.contains("first line of child"))
  assert_true(lines.contains("include::grandchild-include.adoc[]"))
  inspect(
    fmt_logs(messages),
    content="ERROR: fixtures/child-include.adoc: line 3: maximum include depth of 0 exceeded",
  )
}

///|
test "read_lines_until should not process lines if process option is false" {
  let lines = ["////\n", "include::fixtures/no-such-file.adoc[]\n", "////\n"]
  let doc = empty_safe_document()
  let reader = @core.Reader::new_preprocessor(doc, lines, normalize=true)
  reader.read_line() |> ignore
  let result = reader.read_lines_until(terminator="////", skip_processing=true)
  debug_inspect(result, content="[\"include::fixtures/no-such-file.adoc[]\"]")
}

///|
test "skip_comment_lines should not process lines read" {
  let lines = ["////\n", "include::fixtures/no-such-file.adoc[]\n", "////\n"]
  let (reader, messages) = @core.with_memory_logger(() => {
    let doc = empty_safe_document()
    let reader = @core.Reader::new_preprocessor(doc, lines, normalize=true)
    reader.skip_comment_lines()
    reader
  })
  assert_true(reader.is_empty())
  inspect(messages.length(), content="0")
}

// ---------------------------------------------------------------------------
// PreprocessorReader: Conditional Inclusions

///|
test "peek_line advances cursor to next conditional line of content" {
  let input =
    #|ifdef::asciidoctor[]
    #|Asciidoctor!
    #|endif::asciidoctor[]
    #|
  let reader = doc_reader(new_doc(input))
  inspect(reader.lineno(), content="1")
  debug_inspect(reader.peek_line(), content="Some(\"Asciidoctor!\")")
  inspect(reader.lineno(), content="2")
}

///|
let asciidoctor_is_in : String =
  #|The Asciidoctor
  #|ifdef::asciidoctor[is in.]
  #|

///|
test "peek_lines should preprocess lines if direct is false" {
  let reader = doc_reader(new_doc(asciidoctor_is_in))
  debug_inspect(
    reader.peek_lines(num=2, direct=false),
    content="[\"The Asciidoctor\", \"is in.\"]",
  )
}

///|
test "peek_lines should not preprocess lines if direct is true" {
  let reader = doc_reader(new_doc(asciidoctor_is_in))
  debug_inspect(
    reader.peek_lines(num=2, direct=true),
    content="[\"The Asciidoctor\", \"ifdef::asciidoctor[is in.]\"]",
  )
}

///|
test "peek_lines should not prevent subsequent preprocessing of peeked lines" {
  let reader = doc_reader(new_doc(asciidoctor_is_in))
  reader.peek_lines(num=2, direct=true) |> ignore
  debug_inspect(
    reader.peek_lines(num=2, direct=false),
    content="[\"The Asciidoctor\", \"is in.\"]",
  )
}

///|
test "peek_line does not advance cursor when on a regular content line" {
  let input =
    #|content
    #|ifdef::asciidoctor[]
    #|Asciidoctor!
    #|endif::asciidoctor[]
    #|
  let reader = doc_reader(new_doc(input))
  inspect(reader.lineno(), content="1")
  debug_inspect(reader.peek_line(), content="Some(\"content\")")
  inspect(reader.lineno(), content="1")
}

///|
test "peek_line returns nil if cursor advances past end of source" {
  let input =
    #|ifdef::foobar[]
    #|swallowed content
    #|endif::foobar[]
    #|
  let reader = doc_reader(new_doc(input))
  inspect(reader.lineno(), content="1")
  debug_inspect(reader.peek_line(), content="None")
  inspect(reader.lineno(), content="4")
}

///|
test "peek_line returns nil if contents of skipped conditional is empty line" {
  let input =
    #|ifdef::foobar[]
    #|
    #|endif::foobar[]
    #|
  let reader = doc_reader(new_doc(input))
  inspect(reader.lineno(), content="1")
  debug_inspect(reader.peek_line(), content="None")
}

///|
test "ifdef with defined attribute includes content" {
  let input =
    #|ifdef::holygrail[]
    #|There is a holy grail!
    #|endif::holygrail[]
    #|
  let reader = doc_reader(new_doc(input, attributes=[("holygrail", Str(""))]))
  inspect(read_all(reader), content="There is a holy grail!")
}

///|
test "ifdef with defined attribute includes text in brackets" {
  let input =
    #|On our quest we go...
    #|ifdef::holygrail[There is a holy grail!]
    #|There was much rejoicing.
    #|
  let reader = doc_reader(new_doc(input, attributes=[("holygrail", Str(""))]))
  inspect(
    read_all(reader),
    content=(
      #|On our quest we go...
      #|There is a holy grail!
      #|There was much rejoicing.
    ),
  )
}

///|
test "ifdef with defined attribute processes include directive in brackets" {
  let input = "ifdef::asciidoctor-version[include::fixtures/include-file.adoc[tag=snippetA]]"
  let reader = doc_reader(
    new_doc(input, safe=@core.SAFE_SAFE, base_dir=testdir),
  )
  let lines = []
  while reader.has_more_lines() {
    lines.push(reader.read_line().unwrap_or("<nil>"))
  }
  debug_inspect(lines[0], content="\"snippetA content\"")
}

///|
test "ifdef attribute name is not case sensitive" {
  let input =
    #|ifdef::showScript[]
    #|The script is shown!
    #|endif::showScript[]
    #|
  let doc = new_doc(input, attributes=[("showscript", Str(""))])
  inspect(doc_reader(doc).read(), content="The script is shown!")
}

///|
test "ifndef with defined attribute does not include text in brackets" {
  let input =
    #|On our quest we go...
    #|ifndef::hardships[There is a holy grail!]
    #|There was no rejoicing.
    #|
  let reader = doc_reader(new_doc(input, attributes=[("hardships", Str(""))]))
  inspect(
    read_all(reader),
    content=(
      #|On our quest we go...
      #|There was no rejoicing.
    ),
  )
}

///|
test "include with non-matching nested exclude" {
  let input =
    #|ifdef::grail[]
    #|holy
    #|ifdef::swallow[]
    #|swallow
    #|endif::swallow[]
    #|grail
    #|endif::grail[]
    #|
  let reader = doc_reader(new_doc(input, attributes=[("grail", Str(""))]))
  inspect(
    read_all(reader),
    content=(
      #|holy
      #|grail
    ),
  )
}

///|
test "nested excludes with same condition" {
  let input =
    #|ifndef::grail[]
    #|ifndef::grail[]
    #|not here
    #|endif::grail[]
    #|endif::grail[]
    #|
  let reader = doc_reader(new_doc(input, attributes=[("grail", Str(""))]))
  inspect(read_all(reader), content="")
}

///|
test "include with nested exclude of inverted condition" {
  let input =
    #|ifdef::grail[]
    #|holy
    #|ifndef::grail[]
    #|not here
    #|endif::grail[]
    #|grail
    #|endif::grail[]
    #|
  let reader = doc_reader(new_doc(input, attributes=[("grail", Str(""))]))
  inspect(
    read_all(reader),
    content=(
      #|holy
      #|grail
    ),
  )
}

///|
test "exclude with matching nested exclude" {
  let input =
    #|poof
    #|ifdef::swallow[]
    #|no
    #|ifdef::swallow[]
    #|swallow
    #|endif::swallow[]
    #|here
    #|endif::swallow[]
    #|gone
    #|
  let reader = doc_reader(new_doc(input, attributes=[("grail", Str(""))]))
  inspect(
    read_all(reader),
    content=(
      #|poof
      #|gone
    ),
  )
}

///|
test "exclude with nested include using shorthand end" {
  let input =
    #|poof
    #|ifndef::grail[]
    #|no grail
    #|ifndef::swallow[]
    #|or swallow
    #|endif::[]
    #|in here
    #|endif::[]
    #|gone
    #|
  let reader = doc_reader(new_doc(input, attributes=[("grail", Str(""))]))
  inspect(
    read_all(reader),
    content=(
      #|poof
      #|gone
    ),
  )
}

///|
let holygrail_or_swallow : String =
  #|ifdef::holygrail,swallow[]
  #|Our quest is complete!
  #|endif::holygrail,swallow[]
  #|

///|
let holygrail_and_swallow : String =
  #|ifdef::holygrail+swallow[]
  #|Our quest is complete!
  #|endif::holygrail+swallow[]
  #|

///|
test "ifdef with one alternative attribute set includes content" {
  let reader = doc_reader(
    new_doc(holygrail_or_swallow, attributes=[("swallow", Str(""))]),
  )
  inspect(read_all(reader), content="Our quest is complete!")
}

///|
test "ifdef with no alternative attributes set does not include content" {
  let reader = doc_reader(new_doc(holygrail_or_swallow))
  inspect(read_all(reader), content="")
}

///|
test "ifdef with all required attributes set includes content" {
  let reader = doc_reader(
    new_doc(holygrail_and_swallow, attributes=[
      ("holygrail", Str("")),
      ("swallow", Str("")),
    ]),
  )
  inspect(read_all(reader), content="Our quest is complete!")
}

///|
test "ifdef with missing required attributes does not include content" {
  let reader = doc_reader(
    new_doc(holygrail_and_swallow, attributes=[("holygrail", Str(""))]),
  )
  inspect(read_all(reader), content="")
}

///|
test "ifdef should permit leading, trailing, and repeat operators" {
  let results = [
    "asciidoctor,", ",asciidoctor", "asciidoctor+", "+asciidoctor", "asciidoctor,,asciidoctor-version",
    "asciidoctor++asciidoctor-version",
  ].map(condition => {
    let input = "ifdef::\{condition}[]\ncontent\nendif::[]\n"
    (condition, doc_reader(document_from_string(input, parse=false)).read())
  })
  debug_inspect(
    results,
    content=(
      #|[
      #|  ("asciidoctor,", "content"),
      #|  (",asciidoctor", "content"),
      #|  ("asciidoctor+", ""),
      #|  ("+asciidoctor", ""),
      #|  ("asciidoctor,,asciidoctor-version", "content"),
      #|  ("asciidoctor++asciidoctor-version", ""),
      #|]
    ),
  )
}

///|
test "ifndef with undefined attribute includes block" {
  let input =
    #|ifndef::holygrail[]
    #|Our quest continues to find the holy grail!
    #|endif::holygrail[]
    #|
  inspect(
    read_all(doc_reader(new_doc(input))),
    content="Our quest continues to find the holy grail!",
  )
}

///|
let not_holygrail_or_swallow : String =
  #|ifndef::holygrail,swallow[]
  #|Our quest is complete!
  #|endif::holygrail,swallow[]
  #|

///|
let not_holygrail_and_swallow : String =
  #|ifndef::holygrail+swallow[]
  #|Our quest is complete!
  #|endif::holygrail+swallow[]
  #|

///|
test "ifndef with one alternative attribute set does not include content" {
  let doc = new_doc(not_holygrail_or_swallow, attributes=[("swallow", Str(""))])
  inspect(doc_reader(doc).read(), content="")
}

///|
test "ifndef with both alternative attributes set does not include content" {
  let doc = new_doc(not_holygrail_or_swallow, attributes=[
    ("swallow", Str("")),
    ("holygrail", Str("")),
  ])
  inspect(doc_reader(doc).read(), content="")
}

///|
test "ifndef with no alternative attributes set includes content" {
  let doc = new_doc(not_holygrail_or_swallow)
  inspect(doc_reader(doc).read(), content="Our quest is complete!")
}

///|
test "ifndef with no required attributes set includes content" {
  let doc = new_doc(not_holygrail_and_swallow)
  inspect(doc_reader(doc).read(), content="Our quest is complete!")
}

///|
test "ifndef with all required attributes set does not include content" {
  let doc = new_doc(not_holygrail_and_swallow, attributes=[
    ("swallow", Str("")),
    ("holygrail", Str("")),
  ])
  inspect(doc_reader(doc).read(), content="")
}

///|
test "ifndef with at least one required attributes set does not include content" {
  let doc = new_doc(not_holygrail_and_swallow, attributes=[("swallow", Str(""))])
  inspect(doc_reader(doc).read(), content="Our quest is complete!")
}

///|
test "ifdef around empty line does not introduce extra line" {
  let input =
    #|before
    #|ifdef::no-such-attribute[]
    #|
    #|endif::[]
    #|after
    #|
  inspect(
    doc_reader(new_doc(input)).read(),
    content=(
      #|before
      #|after
    ),
  )
}

///|
test "should log warning if endif is unmatched" {
  let input =
    #|Our quest is complete!
    #|endif::on-quest[]
    #|
  let (result, messages) = @core.with_memory_logger(() => {
    doc_reader(new_doc(input, attributes=[("on-quest", Str(""))])).read()
  })
  inspect(result, content="Our quest is complete!")
  inspect(
    fmt_logs(messages),
    content="ERROR: <stdin>: line 2: unmatched preprocessor directive: endif::on-quest[]",
  )
}

///|
test "should log warning if endif is mismatched" {
  let input =
    #|ifdef::on-quest[]
    #|Our quest is complete!
    #|endif::on-journey[]
    #|
  let (result, messages) = @core.with_memory_logger(() => {
    doc_reader(
      new_doc(input, attributes=[("on-quest", Str(""))], sourcemap=true),
    ).read()
  })
  inspect(result, content="Our quest is complete!")
  inspect(
    fmt_logs(messages),
    content=(
      #|ERROR: <stdin>: line 3: mismatched preprocessor directive: endif::on-journey[], expected endif::on-quest[]
      #|ERROR: <stdin>: line 1: detected unterminated preprocessor conditional directive: ifdef::on-quest[]
    ),
  )
}

///|
test "should log warning if endif contains text" {
  let input =
    #|ifdef::on-quest[]
    #|Our quest is complete!
    #|endif::on-quest[complete!]
    #|fin
    #|
  let (result, messages) = @core.with_memory_logger(() => {
    doc_reader(
      new_doc(input, attributes=[("on-quest", Str(""))], sourcemap=true),
    ).read()
  })
  inspect(
    result,
    content=(
      #|Our quest is complete!
      #|fin
    ),
  )
  inspect(
    fmt_logs(messages),
    content=(
      #|ERROR: <stdin>: line 3: malformed preprocessor directive - text not permitted: endif::on-quest[complete!]
      #|ERROR: <stdin>: line 1: detected unterminated preprocessor conditional directive: ifdef::on-quest[]
    ),
  )
}

///|
test "escaped ifdef is unescaped and ignored" {
  let input =
    #|\ifdef::holygrail[]
    #|content
    #|\endif::holygrail[]
    #|
  inspect(
    read_all(doc_reader(new_doc(input))),
    content=(
      #|ifdef::holygrail[]
      #|content
      #|endif::holygrail[]
    ),
  )
}

///|
test "ifeval comparing missing attribute to nil includes content" {
  let input =
    #|ifeval::['{foo}' == '']
    #|No foo for you!
    #|endif::[]
    #|
  inspect(read_all(doc_reader(new_doc(input))), content="No foo for you!")
}

///|
test "ifeval comparing missing attribute to 0 drops content" {
  let input =
    #|ifeval::[{leveloffset} == 0]
    #|I didn't make the cut!
    #|endif::[]
    #|
  inspect(read_all(doc_reader(new_doc(input))), content="")
}

///|
test "ifeval running unsupported operation on missing attribute drops content" {
  let input =
    #|ifeval::[{leveloffset} >= 3]
    #|I didn't make the cut!
    #|endif::[]
    #|
  inspect(read_all(doc_reader(new_doc(input))), content="")
}

///|
test "ifeval running invalid operation drops content" {
  let input =
    #|ifeval::[{asciidoctor-version} > true]
    #|I didn't make the cut!
    #|endif::[]
    #|
  inspect(read_all(doc_reader(new_doc(input))), content="")
}

///|
test "ifeval comparing double-quoted attribute to matching string includes content" {
  let input =
    #|ifeval::["{gem}" == "asciidoctor"]
    #|Asciidoctor it is!
    #|endif::[]
    #|
  let reader = doc_reader(
    new_doc(input, attributes=[("gem", Str("asciidoctor"))]),
  )
  inspect(read_all(reader), content="Asciidoctor it is!")
}

///|
test "ifeval comparing single-quoted attribute to matching string includes content" {
  let input =
    #|ifeval::['{gem}' == 'asciidoctor']
    #|Asciidoctor it is!
    #|endif::[]
    #|
  let reader = doc_reader(
    new_doc(input, attributes=[("gem", Str("asciidoctor"))]),
  )
  inspect(read_all(reader), content="Asciidoctor it is!")
}

///|
test "ifeval comparing quoted attribute to non-matching string drops content" {
  let input =
    #|ifeval::['{gem}' == 'asciidoctor']
    #|Asciidoctor it is!
    #|endif::[]
    #|
  let reader = doc_reader(new_doc(input, attributes=[("gem", Str("tilt"))]))
  inspect(read_all(reader), content="")
}

///|
test "ifeval comparing attribute to lower version number includes content" {
  let input =
    #|ifeval::['{asciidoctor-version}' >= '0.1.0']
    #|That version will do!
    #|endif::[]
    #|
  inspect(read_all(doc_reader(new_doc(input))), content="That version will do!")
}

///|
test "ifeval comparing attribute to self includes content" {
  let input =
    #|ifeval::['{asciidoctor-version}' == '{asciidoctor-version}']
    #|Of course it's the same!
    #|endif::[]
    #|
  inspect(
    read_all(doc_reader(new_doc(input))),
    content="Of course it's the same!",
  )
}

///|
test "ifeval arguments can be transposed" {
  let input =
    #|ifeval::['0.1.0' <= '{asciidoctor-version}']
    #|That version will do!
    #|endif::[]
    #|
  inspect(read_all(doc_reader(new_doc(input))), content="That version will do!")
}

///|
test "ifeval matching numeric equality includes content" {
  let input =
    #|ifeval::[{rings} == 1]
    #|One ring to rule them all!
    #|endif::[]
    #|
  let reader = doc_reader(new_doc(input, attributes=[("rings", Str("1"))]))
  inspect(read_all(reader), content="One ring to rule them all!")
}

///|
test "ifeval matching numeric inequality includes content" {
  let input =
    #|ifeval::[{rings} != 0]
    #|One ring to rule them all!
    #|endif::[]
    #|
  let reader = doc_reader(new_doc(input, attributes=[("rings", Str("1"))]))
  inspect(read_all(reader), content="One ring to rule them all!")
}

///|
fn read_all_logged(input : String) -> (String, String) {
  let (result, messages) = @core.with_memory_logger(() => {
    read_all(doc_reader(new_doc(input)))
  })
  (result, fmt_logs(messages))
}

///|
test "should log error if ifeval has target" {
  let (result, logs) = read_all_logged("ifeval::target[1 == 1]\ncontent\n")
  inspect(result, content="content")
  inspect(
    logs,
    content="ERROR: <stdin>: line 1: malformed preprocessor directive - target not permitted: ifeval::target[1 == 1]",
  )
}

///|
test "should log error if ifeval has invalid expression" {
  let (result, logs) = read_all_logged("ifeval::[1 | 2]\ncontent\n")
  inspect(result, content="content")
  inspect(
    logs,
    content="ERROR: <stdin>: line 1: malformed preprocessor directive - invalid expression: ifeval::[1 | 2]",
  )
}

///|
test "should log error if ifeval is missing expression" {
  let (result, logs) = read_all_logged("ifeval::[]\ncontent\n")
  inspect(result, content="content")
  inspect(
    logs,
    content="ERROR: <stdin>: line 1: malformed preprocessor directive - missing expression: ifeval::[]",
  )
}

///|
test "ifdef with no target is ignored" {
  let (result, logs) = read_all_logged("ifdef::[]\ncontent\n")
  inspect(result, content="content")
  inspect(
    logs,
    content="ERROR: <stdin>: line 1: malformed preprocessor directive - missing target: ifdef::[]",
  )
}

///|
test "should not warn about invalid ifdef preprocessor directive if already skipping" {
  let input =
    #|ifdef::attribute-not-set[]
    #|foo
    #|ifdef::[]
    #|bar
    #|endif::[]
    #|baz
    #|
  let (result, messages) = @core.with_memory_logger(() => {
    doc_reader(new_doc(input)).read()
  })
  inspect(result, content="baz")
  inspect(messages.length(), content="0")
}

///|
test "should not warn about invalid ifeval preprocessor directive if already skipping" {
  let input =
    #|ifdef::attribute-not-set[]
    #|foo
    #|ifeval::[]
    #|bar
    #|endif::[]
    #|baz
    #|
  let (result, messages) = @core.with_memory_logger(() => {
    doc_reader(new_doc(input)).read()
  })
  inspect(result, content="baz")
  inspect(messages.length(), content="0")
}

///|
let unterminated_input : String =
  #|before
  #|ifdef::not-set[]
  #|skip
  #|these
  #|lines
  #|fin
  #|

///|
test "should log error with end position if preprocessor conditional directive is unterminated" {
  let (result, logs) = read_all_logged(unterminated_input)
  inspect(result, content="before")
  inspect(
    logs,
    content="ERROR: <stdin>: line 6: detected unterminated preprocessor conditional directive: ifdef::not-set[]",
  )
}

///|
test "should log error with start location if preprocessor conditional directive is unterminated and sourcemap is set" {
  let (result, messages) = @core.with_memory_logger(() => {
    read_all(doc_reader(new_doc(unterminated_input, sourcemap=true)))
  })
  inspect(result, content="before")
  inspect(
    fmt_logs(messages),
    content="ERROR: <stdin>: line 2: detected unterminated preprocessor conditional directive: ifdef::not-set[]",
  )
}

///|
test "should log error if multiple preprocessor conditional directives are unterminated" {
  let input =
    #|before
    #|ifdef::not-set[]
    #|skip
    #|these
    #|lines
    #|ifeval::[1 == 2]
    #|{asciidoctor-version}
    #|fin
    #|
  let (result, messages) = @core.with_memory_logger(() => {
    read_all(doc_reader(new_doc(input, sourcemap=true)))
  })
  inspect(result, content="before")
  inspect(
    fmt_logs(messages),
    content=(
      #|ERROR: <stdin>: line 2: detected unterminated preprocessor conditional directive: ifdef::not-set[]
      #|ERROR: <stdin>: line 6: detected unterminated preprocessor conditional directive: ifeval::[1 == 2]
    ),
  )
}

///|
test "should not fail to process preprocessor directive that evaluates to false and has a large number of lines" {
  let data = Array::make(5000, "data").join("\n")
  let input = "before\n\nifdef::attribute-not-set[]\n\{data}\nendif::attribute-not-set[]\n\nafter\n"
  let doc = @core.new_document(
    Some(@core.prepare_source_string(input)),
    @core.Options::new(),
  ).parse()
  inspect(doc.blocks.length(), content="2")
  inspect(doc.blocks[0].source(), content="before")
  inspect(doc.blocks[1].source(), content="after")
}
