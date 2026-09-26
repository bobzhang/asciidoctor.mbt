// Direct-API tests ported from asciidoctor/test/api_test.rb. Each test is
// named after the Ruby test it ports; expected values come from the Ruby
// assertions (or from running Ruby Asciidoctor on the same input).

// ---------------------------------------------------------------------------
// Helpers shared by api_test.mbt and document_test.mbt (mirroring
// test/test_helper.rb).

///|
/// Ruby `document_from_string`: standalone and parsed by default; `linkcss`
/// is set for standalone documents so the stylesheet is not embedded.
fn document_from_string(
  src : String,
  options? : @core.Options = @core.Options::new(),
) -> @core.Node {
  if options.standalone is None {
    options.standalone = Some(true)
  }
  if options.standalone is Some(true) {
    options.attributes.push(("linkcss", Str("")))
  }
  @asciidoctor.load(src, options~)
}

///|
/// Ruby `convert_string_to_embedded`.
fn convert_string_to_embedded(
  src : String,
  options? : @core.Options = @core.Options::new(),
) -> String {
  options.standalone = Some(false)
  document_from_string(src, options~).convert()
}

///|
/// Ruby `empty_document`: `Document.new [], options` (not parsed).
fn empty_document(
  options? : @core.Options = @core.Options::new(),
) -> @core.Node {
  options.parse = false
  @asciidoctor.load_lines([], options~)
}

///|
/// Ruby `Document.new data, options` (not parsed). Loads an empty document
/// first so the built-in converters are registered.
fn new_document(data : Array[String]?, options : @core.Options) -> @core.Node {
  @asciidoctor.load_lines([], options=@core.Options::new(parse=false)) |> ignore
  @core.new_document(data, options)
}

///|
let fixture_dir : String = "/project/test/fixtures"

///|
fn fixture_path(name : String) -> String {
  "\{fixture_dir}/\{name}"
}

///|
/// A virtual file system holding the fixture files the ported tests read.
fn fixtures_vfs() -> @core.MemoryVfs {
  let vfs = @core.MemoryVfs::new(cwd="/project", home="/home/user")
  vfs.add_text(fixture_path("sample.adoc"), sample_adoc)
  vfs.add_text(fixture_path("sample-alt-extension.asciidoc"), sample_adoc)
  vfs.add_text(fixture_path("lists.adoc"), lists_adoc)
  vfs.add_text(
    fixture_path("main.adoc"),
    (
      #|= Main Document
      #|
      #|preamble
      #|
      #|include::chapter-a.adoc[leveloffset=+1]
      #|
    ),
  )
  vfs.add_text(
    fixture_path("chapter-a.adoc"),
    (
      #|= Chapter A
      #|
      #|content
      #|
    ),
  )
  vfs
}

///|
/// Ruby `Asciidoctor.load_file` over the fixture VFS: sets docfile, docdir,
/// docfilesuffix and docname like `@io.load_file` does.
fn load_file(
  path : String,
  options? : @core.Options = @core.Options::new(),
) -> @core.Node {
  let vfs = fixtures_vfs()
  let text = @core.decode_text(vfs.files[path])
  options.vfs = Some(vfs)
  options.attributes = [
    ("docfile", Str(path)),
    ("docdir", Str(@core.dirname(path))),
    ("docfilesuffix", Str(@core.extname(path, fallback=""))),
    ("docname", Str(@core.basename(path, drop_ext=true))),
    ..options.attributes,
  ]
  @asciidoctor.load(text, options~)
}

///|
fn linenos(nodes : Array[@core.Node]) -> Array[Int] {
  nodes.map(n => n.lineno().unwrap_or(-1))
}

///|
let sample_adoc : String =
  #|Document Title
  #|==============
  #|Doc Writer <thedoc@asciidoctor.org>
  #|:idprefix: id_
  #|
  #|Preamble paragraph.
  #|
  #|NOTE: This is test, only a test.
  #|
  #|== Section A
  #|
  #|*Section A* paragraph.
  #|
  #|=== Section A Subsection
  #|
  #|*Section A* 'subsection' paragraph.
  #|
  #|== Section B
  #|
  #|*Section B* paragraph.
  #|
  #||===
  #||a |b |c
  #||1 |2 |3
  #||===
  #|
  #|.Section B list
  #|* Item 1
  #|* Item 2
  #|* Item 3
  #|

///|
let lists_adoc : String =
  #|= Document Title
  #|Doc Writer <thedoc@asciidoctor.org>
  #|
  #|Preamble paragraph.
  #|
  #|NOTE: This is test, only a test.
  #|
  #|== Lists
  #|
  #|.Unordered, basic
  #|* Edgar Allan Poe
  #|* Sheri S. Tepper
  #|* Bill Bryson
  #|
  #|.Unordered, max nesting
  #|* level 1
  #|** level 2
  #|*** level 3
  #|**** level 4
  #|***** level 5
  #|* level 1
  #|
  #|.Checklist
  #|- [*] checked
  #|- [x] also checked
  #|- [ ] not checked
  #|-     normal list item
  #|
  #|.Ordered, basic
  #|. Step 1
  #|. Step 2
  #|. Step 3
  #|
  #|.Ordered, nested
  #|. Step 1
  #|. Step 2
  #|.. Step 2a
  #|.. Step 2b
  #|. Step 3
  #|
  #|.Ordered, max nesting
  #|. level 1
  #|.. level 2
  #|... level 3
  #|.... level 4
  #|..... level 5
  #|. level 1
  #|
  #|.Labeled, single-line
  #|first term:: definition of first term
  #|section term:: definition of second term
  #|
  #|.Labeled, multi-line
  #|first term::
  #|definition of first term
  #|second term::
  #|definition of second term
  #|
  #|.Q&A
  #|[qanda]
  #|What is Asciidoctor?::
  #|  An implementation of the AsciiDoc processor in Ruby.
  #|What is the answer to the Ultimate Question?:: 42
  #|
  #|.Mixed
  #|Operating Systems::
  #|  Linux:::
  #|    . Fedora
  #|      * Desktop
  #|    . Ubuntu
  #|      * Desktop
  #|      * Server
  #|  BSD:::
  #|    . FreeBSD
  #|    . NetBSD
  #|
  #|Cloud Providers::
  #|  PaaS:::
  #|    . OpenShift
  #|    . CloudBees
  #|  IaaS:::
  #|    . Amazon EC2
  #|    . Rackspace
  #|
  #|.Unordered, complex
  #|* level 1
  #|** level 2
  #|*** level 3
  #|This is a new line inside an unordered list using {plus} symbol.
  #|We can even force content to start on a separate line... +
  #|Amazing, isn't it?
  #|**** level 4
  #|+
  #|The {plus} symbol is on a new line.
  #|
  #|***** level 5
  #|

// ---------------------------------------------------------------------------
// API > Load

///|
test "should load input file" {
  let path = fixture_path("sample.adoc")
  let doc = load_file(path, options=@core.Options::new(safe=@core.SAFE_SAFE))
  debug_inspect(doc.doctitle(), content="Some(\"Document Title\")")
  inspect(doc.attr("docfile").unwrap(), content=path)
  inspect(doc.attr("docdir").unwrap(), content=fixture_dir)
  debug_inspect(doc.attr("docfilesuffix"), content="Some(\".adoc\")")
}

///|
test "should load input file with alternate file extension" {
  let path = fixture_path("sample-alt-extension.asciidoc")
  let doc = load_file(path, options=@core.Options::new(safe=@core.SAFE_SAFE))
  debug_inspect(doc.doctitle(), content="Some(\"Document Title\")")
  inspect(doc.attr("docfile").unwrap(), content=path)
  inspect(doc.attr("docdir").unwrap(), content=fixture_dir)
  debug_inspect(doc.attr("docfilesuffix"), content="Some(\".asciidoc\")")
}

///|
test "should load input string" {
  let input =
    #|Document Title
    #|==============
    #|
    #|preamble
    #|
  let doc = @asciidoctor.load(
    input,
    options=@core.Options::new(safe=@core.SAFE_SAFE),
  )
  debug_inspect(doc.doctitle(), content="Some(\"Document Title\")")
  assert_false(doc.has_attr("docfile"))
  assert_eq(doc.attr("docdir"), Some(doc.base_dir()))
}

///|
test "should load input string array" {
  let lines = ["Document Title\n", "==============\n", "\n", "preamble\n"]
  let doc = @asciidoctor.load_lines(
    lines,
    options=@core.Options::new(safe=@core.SAFE_SAFE),
  )
  debug_inspect(doc.doctitle(), content="Some(\"Document Title\")")
  assert_false(doc.has_attr("docfile"))
  assert_eq(doc.attr("docdir"), Some(doc.base_dir()))
}

///|
test "should load nil input" {
  let doc = new_document(None, @core.Options::new(safe=@core.SAFE_SAFE)).parse()
  assert_true(doc.blocks.is_empty())
}

///|
test "should set outfilesuffix attribute to file extension of value of :to_file option if value is a string" {
  let doc = load_file(
    fixture_path("sample.adoc"),
    options=@core.Options::new(safe=@core.SAFE_SAFE, to_file="out.htm"),
  )
  debug_inspect(doc.doctitle(), content="Some(\"Document Title\")")
  debug_inspect(doc.attr("outfilesuffix"), content="Some(\".htm\")")
}

///|
test "should accept attributes as array" {
  // NOTE there's a tab character before idseparator
  let attributes = @asciidoctor.parse_attributes_option(
    "toc sectnums   source-highlighter=coderay idprefix\tidseparator=-",
  )
  let doc = @asciidoctor.load("text", options=@core.Options::new(attributes~))
  assert_true(doc.has_attr("toc"))
  debug_inspect(doc.attr("toc"), content="Some(\"\")")
  assert_true(doc.has_attr("sectnums"))
  debug_inspect(doc.attr("sectnums"), content="Some(\"\")")
  assert_true(doc.has_attr("source-highlighter"))
  debug_inspect(doc.attr("source-highlighter"), content="Some(\"coderay\")")
  assert_true(doc.has_attr("idprefix"))
  debug_inspect(doc.attr("idprefix"), content="Some(\"\")")
  assert_true(doc.has_attr("idseparator"))
  debug_inspect(doc.attr("idseparator"), content="Some(\"-\")")
}

///|
test "should accept attributes as string" {
  let attributes = @asciidoctor.parse_attributes_option(
    "toc sectnums\nsource-highlighter=coderay\nidprefix\nidseparator=-",
  )
  let doc = @asciidoctor.load("text", options=@core.Options::new(attributes~))
  debug_inspect(doc.attr("toc"), content="Some(\"\")")
  debug_inspect(doc.attr("sectnums"), content="Some(\"\")")
  debug_inspect(doc.attr("source-highlighter"), content="Some(\"coderay\")")
  debug_inspect(doc.attr("idprefix"), content="Some(\"\")")
  debug_inspect(doc.attr("idseparator"), content="Some(\"-\")")
}

///|
test "should accept values containing spaces in attributes string" {
  let attributes = @asciidoctor.parse_attributes_option(
    "idprefix idseparator=-   note-caption=Note\\ to\\\tself toc",
  )
  let doc = @asciidoctor.load("text", options=@core.Options::new(attributes~))
  debug_inspect(doc.attr("idprefix"), content="Some(\"\")")
  debug_inspect(doc.attr("idseparator"), content="Some(\"-\")")
  debug_inspect(doc.attr("note-caption"), content="Some(\"Note to\\tself\")")
  debug_inspect(doc.attr("toc"), content="Some(\"\")")
}

///|
test "should accept attributes as empty string" {
  let attributes = @asciidoctor.parse_attributes_option("")
  assert_true(attributes.is_empty())
  let doc = @asciidoctor.load("text", options=@core.Options::new(attributes~))
  assert_false(doc.attributes.is_empty())
}

///|
test "should not expand value of docdir attribute if specified via API" {
  let docdir = "virtual/directory"
  let doc = document_from_string(
    "",
    options=@core.Options::new(safe=@core.SAFE_SAFE, attributes=[
      ("docdir", Str(docdir)),
    ]),
  )
  debug_inspect(doc.attr("docdir"), content="Some(\"virtual/directory\")")
  inspect(doc.base_dir(), content="virtual/directory")
}

///|
test "converts block to output format when convert is called" {
  let doc = @asciidoctor.load("paragraph text")
  inspect(doc.blocks.length(), content="1")
  debug_inspect(doc.blocks[0].context, content="Paragraph")
  inspect(
    doc.blocks[0].convert(),
    content=(
      #|<div class="paragraph">
      #|<p>paragraph text</p>
      #|</div>
    ),
  )
}

///|
test "content method on Inline node is aliased to text method" {
  let doc = @asciidoctor.load("paragraph")
  let inline = doc.blocks[0].new_inline(Quoted, text="yo", type_="strong")
  debug_inspect(inline.text(), content="Some(\"yo\")")
  inspect(inline.content(), content="yo")
}

///|
test "should output timestamps by default" {
  let doc = document_from_string(
    "text",
    options=@core.Options::new(backend="html5"),
  )
  let result = doc.convert()
  assert_true(doc.has_attr("docdate"))
  assert_false(doc.has_attr("reproducible"))
  assert_true(result.contains("<div id=\"footer-text\">\nLast updated "))
}

///|
test "should not output timestamps if reproducible attribute is set in HTML 5" {
  let doc = document_from_string(
    "text",
    options=@core.Options::new(backend="html5", attributes=[
      ("reproducible", Str("")),
    ]),
  )
  let result = doc.convert()
  assert_true(doc.has_attr("docdate"))
  assert_true(doc.has_attr("reproducible"))
  assert_true(result.contains("<div id=\"footer-text\">"))
  assert_false(result.contains("Last updated"))
}

///|
test "should not output meta generator tag in HTML 5 if reproducible attribute is set" {
  let doc = document_from_string(
    "text",
    options=@core.Options::new(backend="html5", attributes=[
      ("reproducible", Str("")),
    ]),
  )
  let result = doc.convert()
  assert_true(doc.has_attr("reproducible"))
  assert_false(result.contains("name=\"generator\""))
}

///|
test "should not output timestamps if reproducible attribute is set in DocBook" {
  let doc = document_from_string(
    "text",
    options=@core.Options::new(backend="docbook", attributes=[
      ("reproducible", Str("")),
    ]),
  )
  let result = doc.convert()
  assert_true(doc.has_attr("docdate"))
  assert_true(doc.has_attr("reproducible"))
  assert_true(result.contains("<info>"))
  assert_false(result.contains("<date>"))
}

///|
test "should not modify options argument" {
  let options = @core.Options::new(safe=@core.SAFE_SAFE)
  let doc = load_file(fixture_path("sample.adoc"), options~)
  assert_false(physical_equal(options, doc.options()))
}

///|
test "should not modify attributes Hash argument" {
  let attributes : Array[(String, @core.AttrVal)] = []
  let options = @core.Options::new(safe=@core.SAFE_SAFE, attributes~)
  let doc = @asciidoctor.load(sample_adoc, options~)
  assert_true(attributes.is_empty())
  assert_false(physical_equal(attributes, doc.options().attributes))
}

///|
test "should be able to restore header attributes after call to convert" {
  let input =
    #|= Document Title
    #|:foo: bar
    #|
    #|content
    #|
    #|:foo: baz
    #|
    #|content
    #|
  let doc = @asciidoctor.load(input)
  debug_inspect(doc.attr("foo"), content="Some(\"bar\")")
  doc.convert() |> ignore
  debug_inspect(doc.attr("foo"), content="Some(\"baz\")")
  doc.restore_attributes()
  debug_inspect(doc.attr("foo"), content="Some(\"bar\")")
}

///|
test "should track file and line information with blocks if sourcemap option is set" {
  let doc = load_file(
    fixture_path("sample.adoc"),
    options=@core.Options::new(sourcemap=true),
  )
  assert_true(doc.source_location is Some(_))
  debug_inspect(doc.file(), content="Some(\"sample.adoc\")")
  debug_inspect(doc.lineno(), content="Some(1)")
  let preamble = doc.blocks[0]
  debug_inspect(preamble.file(), content="Some(\"sample.adoc\")")
  debug_inspect(preamble.lineno(), content="Some(6)")
  let section_1 = doc.sections()[0]
  debug_inspect(section_1.title(), content="Some(\"Section A\")")
  debug_inspect(section_1.file(), content="Some(\"sample.adoc\")")
  debug_inspect(section_1.lineno(), content="Some(10)")
  let section_2 = doc.sections()[1]
  debug_inspect(section_2.title(), content="Some(\"Section B\")")
  debug_inspect(section_2.file(), content="Some(\"sample.adoc\")")
  debug_inspect(section_2.lineno(), content="Some(18)")
  let table_block = section_2.blocks[1]
  debug_inspect(table_block.context, content="Table")
  debug_inspect(table_block.file(), content="Some(\"sample.adoc\")")
  debug_inspect(table_block.lineno(), content="Some(22)")
  let body = table_block.rows().body
  let first_cell = body[0][0]
  debug_inspect(first_cell.file(), content="Some(\"sample.adoc\")")
  debug_inspect(first_cell.lineno(), content="Some(23)")
  let second_cell = body[0][1]
  debug_inspect(second_cell.file(), content="Some(\"sample.adoc\")")
  debug_inspect(second_cell.lineno(), content="Some(23)")
  let last_row = body[body.length() - 1]
  let last_cell = last_row[last_row.length() - 1]
  debug_inspect(last_cell.file(), content="Some(\"sample.adoc\")")
  debug_inspect(last_cell.lineno(), content="Some(24)")
  let last_block = section_2.blocks[section_2.blocks.length() - 1]
  debug_inspect(last_block.context, content="Ulist")
  debug_inspect(last_block.file(), content="Some(\"sample.adoc\")")
  debug_inspect(last_block.lineno(), content="Some(28)")
  let list_items = last_block.blocks
  debug_inspect(
    list_items.map(li => (li.file(), li.lineno())),
    content=(
      #|[
      #|  (Some("sample.adoc"), Some(28)),
      #|  (Some("sample.adoc"), Some(29)),
      #|  (Some("sample.adoc"), Some(30)),
      #|]
    ),
  )
  let doc = load_file(
    fixture_path("main.adoc"),
    options=@core.Options::new(sourcemap=true, safe=@core.SAFE_SAFE),
  )
  let section_1 = doc.sections()[0]
  debug_inspect(section_1.title(), content="Some(\"Chapter A\")")
  assert_eq(section_1.file(), Some(fixture_path("chapter-a.adoc")))
  debug_inspect(section_1.lineno(), content="Some(1)")
}

///|
test "should track file and line information on list items if sourcemap option is set" {
  let doc = load_file(
    fixture_path("lists.adoc"),
    options=@core.Options::new(sourcemap=true),
  )
  let first_section = doc.blocks[1]
  let check = fn(idx : Int) -> (Int?, Array[Int]) {
    let list = first_section.blocks[idx]
    (list.lineno(), linenos(list.find_by(context=ListItem)))
  }
  debug_inspect(check(0), content="(Some(11), [11, 12, 13])")
  debug_inspect(check(1), content="(Some(16), [16, 17, 18, 19, 20, 21])")
  debug_inspect(check(2), content="(Some(24), [24, 25, 26, 27])")
  debug_inspect(check(3), content="(Some(30), [30, 31, 32])")
  debug_inspect(check(4), content="(Some(35), [35, 36, 37, 38, 39])")
  debug_inspect(check(5), content="(Some(42), [42, 43, 44, 45, 46, 47])")
  debug_inspect(check(6), content="(Some(50), [50, 50, 51, 51])")
  debug_inspect(check(7), content="(Some(54), [54, 55, 56, 57])")
  debug_inspect(check(8), content="(Some(61), [61, 62, 63, 63])")
  let mixed = first_section.blocks[9]
  debug_inspect(mixed.lineno(), content="Some(66)")
  let mixed_items = mixed.find_by(context=ListItem, filter=block => {
    if block.has_text() {
      Accept
    } else {
      Skip
    }
  })
  debug_inspect(
    linenos(mixed_items),
    content="[66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 77, 78, 79, 80, 81, 82, 83]",
  )
  debug_inspect(check(10), content="(Some(86), [86, 87, 88, 92, 96])")
}

///|
test "should assign incorrect lineno for paragraph inside a conditional preprocessor directive" {
  let input =
    #|:conditional-attribute:
    #|
    #|before
    #|
    #|ifdef::conditional-attribute[]
    #|subject
    #|endif::[]
    #|
    #|after
    #|
  let doc = document_from_string(
    input,
    options=@core.Options::new(sourcemap=true),
  )
  // FIXME (upstream) the second line number should be 6 instead of 7
  debug_inspect(linenos(doc.find_by(context=Paragraph)), content="[3, 7, 9]")
}

///|
test "should assign correct lineno for paragraph inside a conditional preprocessor directive when underline style off" {
  let input =
    #|:conditional-attribute:
    #|
    #|before
    #|
    #|ifdef::conditional-attribute[]
    #|subject
    #|endif::[]
    #|
    #|after
    #|
  @core.compliance.underline_style_section_titles = false
  let doc = document_from_string(
    input,
    options=@core.Options::new(sourcemap=true),
  )
  @core.compliance.underline_style_section_titles = true
  debug_inspect(linenos(doc.find_by(context=Paragraph)), content="[3, 6, 9]")
}

///|
test "should assign correct lineno for multi-line paragraph inside a conditional preprocessor directive" {
  let input =
    #|:conditional-attribute:
    #|
    #|before
    #|
    #|ifdef::conditional-attribute[]
    #|subject
    #|subject
    #|endif::[]
    #|
    #|after
    #|
  let doc = document_from_string(
    input,
    options=@core.Options::new(sourcemap=true),
  )
  debug_inspect(linenos(doc.find_by(context=Paragraph)), content="[3, 6, 10]")
}

///|
test "should assign correct source location to blocks that follow a detached list continuation" {
  let input =
    #|* parent
    #| ** child
    #|
    #|+
    #|paragraph attached to parent
    #|
    #|****
    #|sidebar outside list
    #|****
    #|
  let doc = document_from_string(
    input,
    options=@core.Options::new(sourcemap=true),
  )
  debug_inspect(linenos(doc.find_by(context=Paragraph)), content="[5, 8]")
}

///|
test "should assign correct source location if section occurs on last line of input" {
  let input =
    #|= Document Title
    #|
    #|== Section A
    #|
    #|content
    #|
    #|== Section B
    #|
  let doc = document_from_string(
    input,
    options=@core.Options::new(sourcemap=true),
  )
  debug_inspect(linenos(doc.find_by(context=Section)), content="[1, 3, 7]")
}

///|
test "should allow sourcemap option on document to be modified before document is parsed" {
  let doc = load_file(
    fixture_path("sample.adoc"),
    options=@core.Options::new(parse=false),
  )
  doc.set_sourcemap(true)
  assert_false(doc.is_parsed())
  let doc = doc.parse()
  assert_true(doc.is_parsed())
  let section_1 = doc.sections()[0]
  debug_inspect(section_1.title(), content="Some(\"Section A\")")
  debug_inspect(section_1.file(), content="Some(\"sample.adoc\")")
  debug_inspect(section_1.lineno(), content="Some(10)")
}

///|
test "find_by should return Array of blocks anywhere in document tree that match criteria" {
  let input =
    #|= Document Title
    #|
    #|preamble
    #|
    #|== Section A
    #|
    #|paragraph
    #|
    #|--
    #|Exhibit A::
    #|+
    #|[#tiger.animal]
    #|image::tiger.png[Tiger]
    #|--
    #|
    #|image::shoe.png[Shoe]
    #|
    #|== Section B
    #|
    #|paragraph
    #|
  let doc = @asciidoctor.load(input)
  let result = doc.find_by(context=Image)
  inspect(result.length(), content="2")
  debug_inspect(result[0].context, content="Image")
  debug_inspect(result[0].attr("target"), content="Some(\"tiger.png\")")
  debug_inspect(result[1].context, content="Image")
  debug_inspect(result[1].attr("target"), content="Some(\"shoe.png\")")
}

///|
test "find_by should return an empty Array if no matches are found" {
  let doc = @asciidoctor.load("paragraph")
  inspect(doc.find_by(context=Section).length(), content="0")
}

///|
test "should only return matched node when return value of block argument is :prune" {
  let input =
    #|* foo
    #| ** yin
    #|  *** zen
    #| ** yang
    #|* bar
    #|* baz
    #|
  let doc = @asciidoctor.load(input)
  let result = doc.find_by(context=ListItem, filter=li => {
    if li.text() == Some("yin") {
      Prune
    } else {
      Skip
    }
  })
  inspect(result.length(), content="1")
  debug_inspect(result[0].text(), content="Some(\"yin\")")
}

///|
test "find_by should discover blocks inside AsciiDoc table cells if traverse_documents selector option is true" {
  let input =
    #|paragraph in parent document (before)
    #|
    #|[%footer,cols=2*]
    #||===
    #|a|
    #|paragraph in nested document (body)
    #||normal table cell
    #|
    #|a|
    #|paragraph in nested document (foot)
    #||normal table cell
    #||===
    #|
    #|paragraph in parent document (after)
    #|
  let doc = @asciidoctor.load(input)
  inspect(doc.find_by(context=Paragraph).length(), content="2")
  inspect(
    doc.find_by(context=Paragraph, traverse_documents=true).length(),
    content="4",
  )
}

///|
test "find_by should return inner document of AsciiDoc table cell if traverse_documents selector option is true" {
  let input =
    #||===
    #|a|paragraph in nested document
    #||===
    #|
  let doc = @asciidoctor.load(input)
  let inner_doc = doc.blocks[0].rows().body[0][0].inner_document().unwrap()
  let result = doc.find_by(traverse_documents=true)
  assert_true(result.iter().any(n => physical_equal(n, inner_doc)))
  let result = doc.find_by(
    context=Custom("inner_document"),
    traverse_documents=true,
  )
  inspect(result.length(), content="1")
  assert_true(physical_equal(result[0], inner_doc))
}

///|
test "find_by should match table cells" {
  let input =
    #||===
    #||a |b |c
    #|
    #||1
    #|one
    #|a|NOTE: 2, as it goes.
    #|l|
    #|3
    #| you
    #|  me
    #||===
    #|
  let doc = document_from_string(input)
  let table = doc.blocks[0]
  let first_head_cell = table.rows().head[0][0]
  let first_body_cell = table.rows().body[0][0]
  let result = doc.find_by()
  assert_true(result.iter().any(n => physical_equal(n, first_head_cell)))
  assert_true(result.iter().any(n => physical_equal(n, first_body_cell)))
  inspect(first_head_cell.source(), content="a")
  debug_inspect(first_head_cell.cell_lines(), content="[\"a\"]")
  inspect(
    first_body_cell.source(),
    content=(
      #|1
      #|one
    ),
  )
  debug_inspect(first_body_cell.cell_lines(), content="[\"1\", \"one\"]")
  let result = doc.find_by(context=TableCell, style="asciidoc")
  inspect(result.length(), content="1")
  debug_inspect(result[0].context, content="TableCell")
  debug_inspect(result[0].style, content="Some(\"asciidoc\")")
  inspect(result[0].source(), content="NOTE: 2, as it goes.")
}

///|
test "find_by should return Array of blocks that match style criteria" {
  let input =
    #|[square]
    #|* one
    #|* two
    #|* three
    #|
    #|---
    #|
    #|* apples
    #|* bananas
    #|* pears
    #|
  let doc = @asciidoctor.load(input)
  let result = doc.find_by(context=Ulist, style="square")
  inspect(result.length(), content="1")
  debug_inspect(result[0].context, content="Ulist")
}

///|
test "find_by should return Array of blocks that match role criteria" {
  let input =
    #|[#tiger.animal]
    #|image::tiger.png[Tiger]
    #|
    #|image::shoe.png[Shoe]
    #|
  let doc = @asciidoctor.load(input)
  let result = doc.find_by(context=Image, role="animal")
  inspect(result.length(), content="1")
  debug_inspect(result[0].context, content="Image")
  debug_inspect(result[0].attr("target"), content="Some(\"tiger.png\")")
}

///|
test "find_by should return the document title section if context selector is :section" {
  let input =
    #|= Document Title
    #|
    #|preamble
    #|
    #|== Section One
    #|
    #|content
    #|
  let doc = @asciidoctor.load(input)
  let result = doc.find_by(context=Section)
  inspect(result.length(), content="2")
  debug_inspect(result[0].context, content="Section")
  debug_inspect(result[0].title(), content="Some(\"Document Title\")")
}

///|
test "find_by should only return results for which the block argument yields true" {
  let input =
    #|== Section
    #|
    #|content
    #|
    #|=== Subsection
    #|
    #|content
    #|
  let doc = @asciidoctor.load(input)
  let result = doc.find_by(context=Section, filter=sect => {
    if sect.level == 1 {
      Accept
    } else {
      Skip
    }
  })
  inspect(result.length(), content="1")
  debug_inspect(result[0].context, content="Section")
  debug_inspect(result[0].title(), content="Some(\"Section\")")
}

///|
test "find_by should reject node and its children if block returns :reject" {
  let input =
    #|paragraph 1
    #|
    #|====
    #|paragraph 2
    #|
    #|term::
    #|+
    #|paragraph 3
    #|====
    #|
    #|paragraph 4
    #|
  let doc = @asciidoctor.load(input)
  let result = doc.find_by(filter=candidate => {
    match candidate.context {
      Example => Reject
      Paragraph => Accept
      _ => Skip
    }
  })
  inspect(result.length(), content="2")
  debug_inspect(result.map(n => n.context), content="[Paragraph, Paragraph]")
  debug_inspect(
    result.map(n => n.source()),
    content="[\"paragraph 1\", \"paragraph 4\"]",
  )
}

///|
test "find_by should reject node matched by ID selector if block returns :reject" {
  let input =
    #|[.rolename]
    #|paragraph 1
    #|
    #|[.rolename#idname]
    #|paragraph 2
    #|
  let doc = @asciidoctor.load(input)
  let result = doc.find_by(id="idname", role="rolename")
  inspect(result.length(), content="1")
  assert_true(physical_equal(result[0], doc.blocks[1]))
  let result = doc.find_by(id="idname", role="rolename", filter=_ => Reject)
  inspect(result.length(), content="0")
}

///|
test "find_by should accept node matched by ID selector if block returns :prune" {
  let input =
    #|[.rolename]
    #|paragraph 1
    #|
    #|[.rolename#idname]
    #|====
    #|paragraph 2
    #|====
    #|
  let doc = @asciidoctor.load(input)
  let result = doc.find_by(id="idname", role="rolename")
  inspect(result.length(), content="1")
  assert_true(physical_equal(result[0], doc.blocks[1]))
  let result = doc.find_by(id="idname", role="rolename", filter=_ => Prune)
  inspect(result.length(), content="1")
  assert_true(physical_equal(result[0], doc.blocks[1]))
}

///|
test "find_by should accept node but reject its children if block returns :prune" {
  let input =
    #|====
    #|paragraph 2
    #|
    #|term::
    #|+
    #|paragraph 3
    #|====
    #|
  let doc = @asciidoctor.load(input)
  let result = doc.find_by(filter=candidate => {
    if candidate.context == Example {
      Prune
    } else {
      Skip
    }
  })
  inspect(result.length(), content="1")
  debug_inspect(result[0].context, content="Example")
}

///|
let stop_input : String =
  #|paragraph 1
  #|
  #|====
  #|paragraph 2
  #|
  #|****
  #|paragraph 3
  #|****
  #|====
  #|
  #|paragraph 4
  #|
  #|* item
  #|+
  #|paragraph 5
  #|

///|
test "find_by should stop looking for blocks when StopIteration is raised" {
  // Ruby raises StopIteration from the filter; the MoonBit filter returns Stop
  let doc = @asciidoctor.load(stop_input)
  let mut stop_at_next = false
  let result = doc.find_by(filter=candidate => {
    if stop_at_next {
      return Stop
    }
    if candidate.context == Paragraph {
      if candidate.parent().unwrap().context == Sidebar {
        stop_at_next = true
      }
      Accept
    } else {
      Skip
    }
  })
  inspect(result.length(), content="3")
  debug_inspect(
    result.map(n => n.content()),
    content="[\"paragraph 1\", \"paragraph 2\", \"paragraph 3\"]",
  )
}

///|
test "find_by should stop looking for blocks when filter block returns :stop directive" {
  let doc = @asciidoctor.load(stop_input)
  let mut stop_at_next = false
  let result = doc.find_by(filter=candidate => {
    if stop_at_next {
      return Stop
    }
    if candidate.context == Paragraph {
      if candidate.parent().unwrap().context == Sidebar {
        stop_at_next = true
      }
      Accept
    } else {
      Skip
    }
  })
  inspect(result.length(), content="3")
  debug_inspect(
    result.map(n => n.content()),
    content="[\"paragraph 1\", \"paragraph 2\", \"paragraph 3\"]",
  )
}

///|
test "find_by should only return one result when matching by id" {
  let input =
    #|== Section
    #|
    #|content
    #|
    #|[#subsection]
    #|=== Subsection
    #|
    #|content
    #|
  let doc = @asciidoctor.load(input)
  let result = doc.find_by(context=Section, id="subsection")
  inspect(result.length(), content="1")
  debug_inspect(result[0].context, content="Section")
  debug_inspect(result[0].title(), content="Some(\"Subsection\")")
}

///|
test "find_by should stop seeking once match is found" {
  let input =
    #|== Section
    #|
    #|content
    #|
    #|[#subsection]
    #|=== Subsection
    #|
    #|[#last]
    #|content
    #|
  let doc = @asciidoctor.load(input)
  let mut visited_last = false
  let result = doc.find_by(id="subsection", filter=candidate => {
    if candidate.id == Some("last") {
      visited_last = true
    }
    Accept
  })
  inspect(result.length(), content="1")
  assert_false(visited_last)
}

///|
test "find_by should return an empty Array if the id criteria matches but the block argument yields false" {
  let input =
    #|== Section
    #|
    #|content
    #|
    #|[#subsection]
    #|=== Subsection
    #|
    #|content
    #|
  let doc = @asciidoctor.load(input)
  let result = doc.find_by(context=Section, id="subsection", filter=_ => Skip)
  inspect(result.length(), content="0")
}

///|
test "find_by should not crash if dlist entry does not have description" {
  let doc = @asciidoctor.load("term without description::")
  let result = doc.find_by()
  debug_inspect(
    result.map(n => n.context),
    content="[Document, Dlist, ListItem]",
  )
}

///|
test "dlist item should always have two entries for terms and desc" {
  let results = []
  for
    input in [
      "term w/o desc::", "term::\nalias::", "primary:: 1\nsecondary:: 2",
    ] {
    let dlist = @asciidoctor.load(input).blocks[0]
    for item in dlist.dlist_items {
      results.push(
        (item.terms.map(t => t.context), item.desc.map(d => d.context)),
      )
    }
  }
  debug_inspect(
    results,
    content=(
      #|[
      #|  ([ListItem], None),
      #|  ([ListItem, ListItem], None),
      #|  ([ListItem], Some(ListItem)),
      #|  ([ListItem], Some(ListItem)),
      #|]
    ),
  )
}

///|
/// A syntax highlighter factory that maps names through a table and
/// otherwise defers to the built-in registry (Ruby `CustomFactory` /
/// `DefaultFactory`).
fn custom_highlighter_factory(
  mapping : Map[String, String?],
) -> (String, String, @core.Node) -> &@core.SyntaxHighlighter? {
  (name, backend, doc) => {
    match mapping.get(name) {
      Some(Some(target)) =>
        @core.create_syntax_highlighter(target, backend, doc)
      Some(None) => None
      None => @core.create_syntax_highlighter(name, backend, doc)
    }
  }
}

///|
test "can disable syntax highlighter by setting value to nil in :syntax_highlighters option" {
  let options = @core.Options::new(safe=@core.SAFE_SAFE, attributes=[
    ("source-highlighter", Str("highlight.js")),
  ])
  options.syntax_highlighter_factory = Some(
    custom_highlighter_factory({ "highlight.js": None }),
  )
  let doc = @asciidoctor.load("", options~)
  assert_true(doc.syntax_highlighter() is None)
}

///|
let source_ruby_input : String =
  #|[source,ruby]
  #|----
  #|puts 'Hello, World!'
  #|----
  #|

///|
test "can substitute a custom syntax highlighter factory instance using the :syntax_highlighter_factory option" {
  let options = @core.Options::new(safe=@core.SAFE_SAFE, attributes=[
    ("source-highlighter", Str("github")),
  ])
  options.syntax_highlighter_factory = Some(
    custom_highlighter_factory({ "github": Some("html-pipeline") }),
  )
  let doc = @asciidoctor.load(source_ruby_input, options~)
  inspect(doc.syntax_highlighter().unwrap().name(), content="html-pipeline")
  assert_true(doc.convert().contains("<pre lang=\"ruby\"><code>"))
}

///|
test "can substitute an extended syntax highlighter factory implementation using the :syntax_highlighters option" {
  let options = @core.Options::new(safe=@core.SAFE_SAFE, attributes=[
    ("source-highlighter", Str("coderay")),
  ])
  options.syntax_highlighter_factory = Some((_, backend, doc) => {
    @core.create_syntax_highlighter("highlight.js", backend, doc)
  })
  let doc = @asciidoctor.load(source_ruby_input, options~)
  assert_true(doc.syntax_highlighter() is Some(_))
  let output = doc.convert()
  assert_false(output.contains("CodeRay"))
  assert_true(output.contains("hljs"))
}

// ---------------------------------------------------------------------------
// API > Convert

///|
test "should set outfilesuffix to match file extension of target file" {
  let doc = @asciidoctor.load(
    "{outfilesuffix}",
    options=@core.Options::new(to_file="result.htm"),
  )
  assert_true(doc.convert().contains("<p>.htm</p>"))
}

///|
/// A server-side syntax highlighter that replaces the source with a fixed
/// string (Ruby `Class.new Asciidoctor::SyntaxHighlighter::Base`).
priv struct FixedHighlighter {
  name : String
}

///|
impl @core.SyntaxHighlighter for FixedHighlighter with fn name(self) {
  self.name
}

///|
impl @core.SyntaxHighlighter for FixedHighlighter with fn handles_highlighting(
  _self,
) {
  true
}

///|
/// `format` is the default one (Ruby `SyntaxHighlighter::Base#format`).
impl @core.SyntaxHighlighter for FixedHighlighter with fn highlight(
  _self,
  _node,
  _source,
  _lang,
  _opts,
) {
  ("highlighted", None)
}

///|
test "can override syntax highlighter using syntax_highlighters option" {
  let options = @core.Options::new(safe=@core.SAFE_SAFE, attributes=[
    ("source-highlighter", Str("coderay")),
  ])
  options.syntax_highlighter_factory = Some((name, backend, doc) => {
    if name == "coderay" {
      Some(({ name, } : FixedHighlighter))
    } else {
      @core.create_syntax_highlighter(name, backend, doc)
    }
  })
  let output = @asciidoctor.convert(source_ruby_input, options~)
  inspect(
    output,
    content=(
      #|<div class="listingblock">
      #|<div class="content">
      #|<pre class="coderay highlight"><code data-lang="ruby">highlighted</code></pre>
      #|</div>
      #|</div>
    ),
  )
}

// ---------------------------------------------------------------------------
// API > AST

///|
let getting_real_title : String = "= Getting Real: The Smarter, Faster, Easier Way to Build a Successful Web Application"

///|
let getting_real_body : String = "\nGetting Real details the business, design, programming, and marketing principles of 37signals.\n"

///|
test "with no author" {
  let doc = document_from_string("\{getting_real_title}\n\{getting_real_body}")
  inspect(doc.authors().length(), content="0")
}

///|
test "with one author" {
  let doc = document_from_string(
    "\{getting_real_title}\nDavid Heinemeier Hansson <david@37signals.com>\n\{getting_real_body}",
  )
  debug_inspect(
    doc.authors(),
    content=(
      #|[
      #|  {
      #|    name: Some("David Heinemeier Hansson"),
      #|    firstname: Some("David"),
      #|    middlename: Some("Heinemeier"),
      #|    lastname: Some("Hansson"),
      #|    initials: Some("DHH"),
      #|    email: Some("david@37signals.com"),
      #|  },
      #|]
    ),
  )
}

///|
let two_authors_expected : String =
  #|[
  #|  {
  #|    name: Some("David Heinemeier Hansson"),
  #|    firstname: Some("David"),
  #|    middlename: Some("Heinemeier"),
  #|    lastname: Some("Hansson"),
  #|    initials: Some("DHH"),
  #|    email: Some("david@37signals.com"),
  #|  },
  #|  {
  #|    name: Some("Jason Fried"),
  #|    firstname: Some("Jason"),
  #|    middlename: None,
  #|    lastname: Some("Fried"),
  #|    initials: Some("JF"),
  #|    email: Some("jason@37signals.com"),
  #|  },
  #|]

///|
test "with two authors" {
  let doc = document_from_string(
    "\{getting_real_title}\nDavid Heinemeier Hansson <david@37signals.com>; Jason Fried <jason@37signals.com>\n\{getting_real_body}",
  )
  debug_inspect(doc.authors(), content=two_authors_expected)
}

///|
test "with authors as attributes" {
  let doc = document_from_string(
    (
      $|\{getting_real_title}
      $|:author_1: David Heinemeier Hansson
      $|:email_1: david@37signals.com
      $|:author_2: Jason Fried
      $|:email_2: jason@37signals.com
      $|\{getting_real_body}
    ),
  )
  debug_inspect(doc.authors(), content=two_authors_expected)
}

///|
test "should set option on node when set_option is called" {
  let block = document_from_string(". three\n. two\n. one\n").blocks[0]
  block.set_option("reversed") |> ignore
  assert_true(block.has_option("reversed"))
  debug_inspect(
    block.attributes.get("reversed-option"),
    content="Some(Str(\"\"))",
  )
}

///|
test "enabled_options should return all options which are set" {
  let input =
    #|[%interactive]
    #|* [x] code
    #|* [ ] test
    #|* [ ] profit
    #|
  let block = document_from_string(input).blocks[0]
  let options = block.enabled_options()
  options.sort()
  debug_inspect(options, content="[\"checklist\", \"interactive\"]")
}

///|
test "should append option to existing options" {
  let block = document_from_string("[%fancy]\n. three\n. two\n. one\n").blocks[0]
  block.set_option("reversed") |> ignore
  assert_true(block.has_option("fancy"))
  assert_true(block.has_option("reversed"))
}

///|
test "should not append option if option is already set" {
  let block = document_from_string("[%reversed]\n. three\n. two\n. one\n").blocks[0]
  assert_false(block.set_option("reversed"))
  debug_inspect(
    block.attributes.get("reversed-option"),
    content="Some(Str(\"\"))",
  )
}

///|
test "should return set of option names" {
  let block = document_from_string(
      "[%compact%reversed]\n. three\n. two\n. one\n",
    ).blocks[0]
  let options = block.enabled_options()
  options.sort()
  debug_inspect(options, content="[\"compact\", \"reversed\"]")
}

///|
test "should set linenums option if linenums enabled on source block" {
  let input =
    #|[,ruby,linenums]
    #|----
    #|puts "Hello, World!"
    #|----
    #|
  let block = document_from_string(input).blocks[0]
  assert_true(block.has_attr("linenums"))
  assert_true(block.has_option("linenums"))
}

///|
test "should set linenums option if linenums enabled on fenced code block" {
  let input =
    #|```ruby,linenums
    #|puts "Hello, World!"
    #|```
    #|
  let block = document_from_string(input).blocks[0]
  assert_true(block.has_attr("linenums"))
  assert_true(block.has_option("linenums"))
}

///|
test "should not set linenums attribute if linenums option is enabled on source block" {
  let input =
    #|[%linenums,ruby]
    #|----
    #|puts "Hello, World!"
    #|----
    #|
  let block = document_from_string(input).blocks[0]
  assert_false(block.has_attr("linenums"))
  assert_true(block.has_option("linenums"))
}

///|
test "should not set linenums attribute if linenums option is enabled on fenced code block" {
  let input =
    #|:source-linenums-option:
    #|
    #|```ruby
    #|puts "Hello, World!"
    #|```
    #|
  let block = document_from_string(input).blocks[0]
  assert_false(block.has_attr("linenums"))
  assert_true(block.has_option("linenums"))
}

///|
test "table column should not be a block or inline" {
  let col = document_from_string("|===\n|a\n|===\n").blocks[0].columns()[0]
  assert_false(col.is_block())
  assert_false(col.is_inline())
}

///|
test "table cell should be a block" {
  let cell = document_from_string("|===\n|a\n|===\n").blocks[0].rows().body[0][0]
  assert_true(cell.is_block())
  assert_false(cell.is_inline())
}

///|
test "next_adjacent_block should return next block" {
  let doc = document_from_string("first\n\nsecond\n")
  assert_true(
    physical_equal(doc.blocks[0].next_adjacent_block().unwrap(), doc.blocks[1]),
  )
}

///|
test "next_adjacent_block should return next sibling of parent if called on last sibling" {
  let doc = document_from_string("--\nfirst\n--\n\nsecond\n")
  assert_true(
    physical_equal(
      doc.blocks[0].blocks[0].next_adjacent_block().unwrap(),
      doc.blocks[1],
    ),
  )
}

///|
test "next_adjacent_block should return next sibling of list if called on last item" {
  let doc = document_from_string("* first\n\nsecond\n")
  assert_true(
    physical_equal(
      doc.blocks[0].blocks[0].next_adjacent_block().unwrap(),
      doc.blocks[1],
    ),
  )
}

///|
test "next_adjacent_block should return next item in dlist if called on last block of list item" {
  let input =
    #|first::
    #|desc
    #|+
    #|more desc
    #|
    #|second::
    #|desc
    #|
  let doc = document_from_string(input)
  let items = doc.blocks[0].dlist_items
  // Ruby returns the [terms, desc] pair of the next item; the port returns
  // its first term
  assert_true(
    physical_equal(
      items[0].desc.unwrap().blocks[0].next_adjacent_block().unwrap(),
      items[1].terms[0],
    ),
  )
}

///|
test "should return true when sections? is called on a document or section that has sections" {
  let input =
    #|= Document Title
    #|
    #|== First Section
    #|
    #|=== First subsection
    #|
    #|content
    #|
  let doc = document_from_string(input)
  assert_true(doc.has_sections())
  assert_true(doc.blocks[0].has_sections())
}

///|
test "should return false when sections? is called on a document with no sections" {
  let doc = document_from_string("= Document Title\n\ncontent\n")
  assert_false(doc.has_sections())
}

///|
test "should return false when sections? is called on a section with no sections" {
  let doc = document_from_string("= Document Title\n\n== First Section\n")
  assert_false(doc.blocks[0].has_sections())
}

///|
test "should return false when sections? is called on anything that is not a section" {
  let input =
    #|.Title
    #|====
    #|I'm not section!
    #|====
    #|
    #|[NOTE]
    #|I'm not a section either!
    #|
  let doc = document_from_string(input)
  assert_false(doc.blocks[0].has_sections())
  assert_false(doc.blocks[1].has_sections())
}

// ---------------------------------------------------------------------------
// API > SafeMode

///|
test "should return nil if safe mode value not recognized" {
  debug_inspect(@core.safe_mode_name_for_value(99), content="None")
}

///|
test "should return nil if safe mode name not recognized" {
  debug_inspect(@core.safe_mode_value_for_name("unknown"), content="None")
}

// ---------------------------------------------------------------------------
// Scenarios from other Ruby test files that mutate the model through the API
// between load and convert. The golden harness cannot replay these (they are
// listed as `api-mutation` in tests/golden/known_failures.txt).

///|
test "xref using angled bracket syntax with explicit hash" {
  let doc = document_from_string(
    "<<#tigers>>",
    options=@core.Options::new(standalone=false),
  )
  doc.register_ref(
    "tigers",
    doc.new_inline(Anchor, text="Tigers", type_="ref", target="tigers"),
  )
  |> ignore
  inspect(
    doc.convert(),
    content=(
      #|<div class="paragraph">
      #|<p><a href="#tigers">Tigers</a></p>
      #|</div>
    ),
  )
}

///|
test "xref using macro syntax with explicit hash" {
  let doc = document_from_string(
    "xref:#tigers[]",
    options=@core.Options::new(standalone=false),
  )
  doc.register_ref(
    "tigers",
    doc.new_inline(Anchor, text="Tigers", type_="ref", target="tigers"),
  )
  |> ignore
  inspect(
    doc.convert(),
    content=(
      #|<div class="paragraph">
      #|<p><a href="#tigers">Tigers</a></p>
      #|</div>
    ),
  )
}

///|
test "xref using angled bracket syntax with path which has been included in this document" {
  let (output, messages) = @core.with_memory_logger(() => {
    let doc = document_from_string(
      "<<tigers#about,About Tigers>>",
      options=@core.Options::new(standalone=false),
    )
    doc.catalog().includes["tigers"] = true
    doc.convert()
  })
  inspect(
    output,
    content=(
      #|<div class="paragraph">
      #|<p><a href="#about">About Tigers</a></p>
      #|</div>
    ),
  )
  debug_inspect(
    messages.map(m => (m.severity, m.text)),
    content=(
      #|[(Info, "possible invalid reference: about")]
    ),
  )
}

///|
test "xref using angled bracket syntax with nested path which has been included in this document" {
  let (output, messages) = @core.with_memory_logger(() => {
    let doc = document_from_string(
      "<<part1/tigers#about,About Tigers>>",
      options=@core.Options::new(standalone=false),
    )
    doc.catalog().includes["part1/tigers"] = true
    doc.convert()
  })
  inspect(
    output,
    content=(
      #|<div class="paragraph">
      #|<p><a href="#about">About Tigers</a></p>
      #|</div>
    ),
  )
  debug_inspect(
    messages.map(m => (m.severity, m.text)),
    content=(
      #|[(Info, "possible invalid reference: about")]
    ),
  )
}

///|
test "id and role assigned to ulist item in model are transmitted to output" {
  let doc = document_from_string(
    "* one\n* two\n* three\n",
    options=@core.Options::new(standalone=false),
  )
  let item_0 = doc.blocks[0].items()[0]
  item_0.set_id(Some("one"))
  item_0.add_role("item") |> ignore
  assert_true(
    doc.convert().contains("<li id=\"one\" class=\"item\">\n<p>one</p>"),
  )
}

///|
test "id and role assigned to olist item in model are transmitted to output" {
  let doc = document_from_string(
    ". one\n. two\n. three\n",
    options=@core.Options::new(standalone=false),
  )
  let item_0 = doc.blocks[0].items()[0]
  item_0.set_id(Some("one"))
  item_0.add_role("item") |> ignore
  assert_true(
    doc.convert().contains("<li id=\"one\" class=\"item\">\n<p>one</p>"),
  )
}

///|
test "should not crash if explicit width on SVG image block is an integer" {
  let vfs = @core.MemoryVfs::new(cwd="/project/test")
  vfs.add_text(
    "/project/test/fixtures/circle.svg",
    (
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
    ),
  )
  let doc = document_from_string(
    ":imagesdir: fixtures\n\nimage::circle.svg[Circle,opts=inline]\n",
    options=@core.Options::new(safe=@core.SAFE_SERVER, standalone=false, vfs~, attributes=[
      ("docdir", Str("/project/test")),
    ]),
  )
  doc.blocks[0].set_attr("width", value=Int(50)) |> ignore
  inspect(
    doc.convert(),
    content=(
      #|<div class="imageblock">
      #|<div class="content">
      #|<svg
      #|viewBox="0 0 120 120" version="1.1"
      #|xmlns="http://www.w3.org/2000/svg" width="50">
      #|  <circle cx="60" cy="60" r="50"/>
      #|</svg>
      #|</div>
      #|</div>
    ),
  )
}

///|
test "should allow sections to be renumbered using numeral or deprecated number property" {
  let input =
    #|== Somewhere in the Middle
    #|
    #|== A Bit Later
    #|
    #|== Nearing the End
    #|
    #|== The End
    #|
  let doc = document_from_string(
    input,
    options=@core.Options::new(attributes=[("sectnums", Str(""))]),
  )
  for sect in doc.sections() {
    let numeral = sect.numeral.unwrap()
    if @rb.to_i(numeral) % 2 == 0 {
      sect.numeral = Some(@rb.succ(numeral))
    } else {
      // Ruby `sect.number += 1`
      sect.numeral = Some((sect.number().to_i() + 1).to_string())
    }
  }
  let output = doc.convert_with(standalone=false)
  let headings = output
    .split("\n")
    .filter(l => l.has_prefix("<h2"))
    .map(l => l.to_owned())
    .collect()
  debug_inspect(
    headings,
    content=(
      #|[
      #|  "<h2 id=\"_somewhere_in_the_middle\">2. Somewhere in the Middle</h2>",
      #|  "<h2 id=\"_a_bit_later\">3. A Bit Later</h2>",
      #|  "<h2 id=\"_nearing_the_end\">4. Nearing the End</h2>",
      #|  "<h2 id=\"_the_end\">5. The End</h2>",
      #|]
    ),
  )
}

///|
test "set_attr should set header attribute in loaded document" {
  let input =
    #|:uri: http://example.org
    #|
    #|{uri}
    #|
  let doc = @asciidoctor.load(
    input,
    options=@core.Options::new(attributes=[("uri", Str("https://github.com"))]),
  )
  doc.set_attr("uri", value=Str("https://google.com")) |> ignore
  inspect(
    doc.convert(),
    content=(
      #|<div class="paragraph">
      #|<p><a href="https://google.com" class="bare">https://google.com</a></p>
      #|</div>
    ),
  )
}

// ---------------------------------------------------------------------------
// Attribute API (attr/attr?/set_attr/set_attribute), from
// test/attributes_test.rb > Intrinsic/API attributes.

///|
test "backend attributes defined in document options overrides backend attribute in document" {
  let doc = document_from_string(
    ":backend: docbook5",
    options=@core.Options::new(safe=@core.SAFE_SAFE, attributes=[
      ("backend", Str("html5")),
    ]),
  )
  debug_inspect(doc.attributes.get("backend"), content="Some(Str(\"html5\"))")
  assert_true(doc.attributes.contains("backend-html5"))
  debug_inspect(
    doc.attributes.get("basebackend"),
    content="Some(Str(\"html\"))",
  )
  assert_true(doc.attributes.contains("basebackend-html"))
}

///|
test "can only access a positional attribute from the attributes hash" {
  let doc = empty_document()
  let attributes = @core.Attributes::new()
  attributes.set_pos(1, Str("position 1"))
  let node = doc.new_block(Paragraph, attributes~)
  debug_inspect(node.attr("1"), content="None")
  assert_false(node.has_attr("1"))
  debug_inspect(node.attributes.get_pos(1), content="Some(Str(\"position 1\"))")
}

///|
test "attr should not retrieve attribute from document if not set on block" {
  let doc = document_from_string(
    "paragraph",
    options=@core.Options::new(attributes=[("name", Str("value"))]),
  )
  debug_inspect(doc.blocks[0].attr("name"), content="None")
}

///|
test "attr looks for attribute on document if fallback name is true" {
  let doc = document_from_string(
    "paragraph",
    options=@core.Options::new(attributes=[("name", Str("value"))]),
  )
  debug_inspect(
    doc.blocks[0].attr("name", inherited=true),
    content="Some(\"value\")",
  )
}

///|
test "attr uses fallback name when looking for attribute on document" {
  let doc = document_from_string(
    "paragraph",
    options=@core.Options::new(attributes=[("alt-name", Str("value"))]),
  )
  debug_inspect(
    doc.blocks[0].attr("name", fallback_name="alt-name"),
    content="Some(\"value\")",
  )
}

///|
test "attr? should not check for attribute on document if not set on block" {
  let doc = document_from_string(
    "paragraph",
    options=@core.Options::new(attributes=[("name", Str("value"))]),
  )
  assert_false(doc.blocks[0].has_attr("name"))
}

///|
test "attr? checks for attribute on document if fallback name is true" {
  let doc = document_from_string(
    "paragraph",
    options=@core.Options::new(attributes=[("name", Str("value"))]),
  )
  assert_true(doc.blocks[0].has_attr("name", inherited=true))
}

///|
test "set_attr should set value to empty string if no value is specified" {
  let node = empty_document().new_block(Paragraph)
  node.set_attr("foo") |> ignore
  debug_inspect(node.attr("foo"), content="Some(\"\")")
}

///|
test "remove_attr should remove attribute and return previous value" {
  let node = empty_document().new_block(
    Paragraph,
    attributes=@core.Attributes::from_array([("foo", Str("bar"))]),
  )
  debug_inspect(node.remove_attr("foo"), content="Some(Str(\"bar\"))")
  debug_inspect(node.attr("foo"), content="None")
}

///|
test "set_attr should not overwrite existing key if overwrite is false" {
  let node = empty_document().new_block(
    Paragraph,
    attributes=@core.Attributes::from_array([("foo", Str("bar"))]),
  )
  debug_inspect(node.attr("foo"), content="Some(\"bar\")")
  assert_false(node.set_attr("foo", value=Str("baz"), overwrite=false))
  debug_inspect(node.attr("foo"), content="Some(\"bar\")")
}

///|
test "set_attr should overwrite existing key by default" {
  let node = empty_document().new_block(
    Paragraph,
    attributes=@core.Attributes::from_array([("foo", Str("bar"))]),
  )
  debug_inspect(node.attr("foo"), content="Some(\"bar\")")
  assert_true(node.set_attr("foo", value=Str("baz")))
  debug_inspect(node.attr("foo"), content="Some(\"baz\")")
}

///|
test "set_attribute should set attribute if key is not locked" {
  let doc = empty_document()
  assert_false(doc.has_attr("foo"))
  debug_inspect(doc.set_attribute("foo", value="baz"), content="Some(\"baz\")")
  debug_inspect(doc.attr("foo"), content="Some(\"baz\")")
}

///|
test "set_attribute should not set key if key is locked" {
  let doc = empty_document(
    options=@core.Options::new(attributes=[("foo", Str("bar"))]),
  )
  debug_inspect(doc.attr("foo"), content="Some(\"bar\")")
  debug_inspect(doc.set_attribute("foo", value="baz"), content="None")
  debug_inspect(doc.attr("foo"), content="Some(\"bar\")")
}

///|
test "set_attribute should update backend attributes" {
  let doc = empty_document(
    options=@core.Options::new(attributes=[("backend", Str("html5@"))]),
  )
  debug_inspect(doc.attr("backend-html5"), content="Some(\"\")")
  assert_true(doc.set_attribute("backend", value="docbook5") is Some(_))
  assert_false(doc.has_attr("backend-html5"))
  debug_inspect(doc.attr("backend-docbook5"), content="Some(\"\")")
}

///|
test "verify toc attribute matrix" {
  // attributes | toc | toc-position | toc-placement | toc-class
  let expected : Array[(String, String?, String?, String?, String?)] = [
    ("toc", Some(""), None, Some("auto"), None),
    ("toc=header", Some(""), None, Some("auto"), None),
    ("toc=beeboo", Some(""), None, Some("auto"), None),
    ("toc=left", Some(""), Some("left"), Some("auto"), Some("toc2")),
    ("toc2", Some(""), Some("left"), Some("auto"), Some("toc2")),
    ("toc=right", Some(""), Some("right"), Some("auto"), Some("toc2")),
    ("toc=preamble", Some(""), Some("content"), Some("preamble"), None),
    ("toc=macro", Some(""), Some("content"), Some("macro"), None),
    (
      "toc toc-placement=macro toc-position=left",
      Some(""),
      Some("content"),
      Some("macro"),
      None,
    ),
    ("toc toc-placement!", Some(""), Some("content"), Some("macro"), None),
  ]
  for row in expected {
    let (raw_attrs, toc, toc_position, toc_placement, toc_class) = row
    let attributes = raw_attrs
      .split(" ")
      .map(e => {
        let (k, _, v) = @rb.partition(e.to_owned(), "=")
        (k, @core.AttrVal::Str(v))
      })
      .collect()
    let doc = document_from_string("", options=@core.Options::new(attributes~))
    let actual = (
      doc.attr("toc"),
      doc.attr("toc-position"),
      doc.attr("toc-placement"),
      doc.attr("toc-class"),
    )
    assert_eq(actual, (toc, toc_position, toc_placement, toc_class))
  }
}
