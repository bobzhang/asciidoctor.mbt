// White-box tests of Parser helpers ported from asciidoctor/test/parser_test.rb
// (the Ruby tests call `Asciidoctor::Parser.xxx` directly). Snapshots of
// header metadata use the rendering `size=N` followed by `key: value` lines
// sorted by key, and were compared with the output of the same rendering in
// Ruby Asciidoctor.

///|
fn lex_compare(a : String, b : String) -> Int {
  let n = if a.length() < b.length() { a.length() } else { b.length() }
  for i in 0..<n {
    if a[i] != b[i] {
      return a[i].to_int() - b[i].to_int()
    }
  }
  a.length() - b.length()
}

///|
fn dump_sorted(attrs : Attributes) -> String {
  let pairs = []
  for k, v in attrs.iter() {
    if k is Name(n) {
      pairs.push((n, if v == Nil { "<nil>" } else { v.to_s() }))
    }
  }
  pairs.sort_by((a, b) => lex_compare(a.0, b.0))
  pairs.map(p => "\{p.0}: \{p.1}").join("\n")
}

///|
/// Ruby `metadata.size` followed by the sorted entries.
fn dump_metadata(metadata : Attributes) -> String {
  let body = dump_sorted(metadata)
  "size=\{metadata.length()}" + (if body == "" { "" } else { "\n" + body })
}

///|
/// Document attributes that were added by the parser (plus authorcount).
fn dump_new_doc_attrs(doc : Node, before : Array[String]) -> String {
  let added = Attributes::new()
  for k, v in doc.attributes.iter() {
    if k is Name(n) && (!before.contains(n) || n == "authorcount") {
      added.set(n, v)
    }
  }
  dump_sorted(added)
}

///|
/// Ruby `Hash#inspect` rendering of an attributes hash (insertion order).
fn inspect_attrs(attrs : Attributes) -> String {
  let parts = []
  for k, v in attrs.iter() {
    let key = match k {
      Pos(i) => i.to_string()
      Name(n) => "\"\{n}\""
    }
    let value = match v {
      Nil => "nil"
      Int(i) => i.to_string()
      _ => "\"\{v.to_s()}\""
    }
    parts.push("\{key}=>\{value}")
  }
  "{" + parts.join(", ") + "}"
}

///|
/// Ruby test helper `parse_header_metadata`.
fn parse_header_metadata_from(source : String, doc? : Node) -> Attributes {
  parse_header_metadata(Reader::new(@rb.split(source, "\n")), doc)
}

///|
/// Ruby test helper `empty_document`.
fn empty_document(attributes? : Array[(String, AttrVal)] = []) -> Node {
  new_document(Some([]), wb_options(attributes~))
}

///|
test "is_section_title?" {
  debug_inspect(
    is_section_title("AsciiDoc Home Page", Some("==================")),
    content="Some(0)",
  )
  debug_inspect(
    is_section_title("=== AsciiDoc Home Page", None),
    content="Some(2)",
  )
}

///|
test "sanitize attribute name" {
  inspect(sanitize_attribute_name("Foo Bar"), content="foobar")
  inspect(sanitize_attribute_name("foo"), content="foo")
  inspect(sanitize_attribute_name("Foo 3^ # - Bar["), content="foo3-bar")
}

///|
test "store attribute with value" {
  debug_inspect(
    store_attribute("foo", Some("bar"), doc=None, attrs=None),
    content="(\"foo\", Some(\"bar\"))",
  )
}

///|
test "store attribute with negated value" {
  for name in ["foo!", "!foo", "foo"] {
    debug_inspect(
      store_attribute(name, None, doc=None, attrs=None),
      content="(\"foo\", None)",
    )
  }
}

///|
test "store accessible attribute on document with value" {
  let doc = empty_document()
  doc.set_attribute("foo", value="baz") |> ignore
  let attrs = Attributes::new()
  debug_inspect(
    store_attribute("foo", Some("bar"), doc=Some(doc), attrs=Some(attrs)),
    content="(\"foo\", Some(\"bar\"))",
  )
  debug_inspect(doc.attr("foo"), content="Some(\"bar\")")
  debug_inspect(
    attrs.entries,
    content="Some([{ name: \"foo\", value: Some(\"bar\"), negate: false }])",
  )
}

///|
test "store accessible attribute on document with value that contains attribute reference" {
  let doc = empty_document()
  doc.set_attribute("foo", value="baz") |> ignore
  doc.set_attribute("release", value="ultramega") |> ignore
  let attrs = Attributes::new()
  debug_inspect(
    store_attribute("foo", Some("{release}"), doc=Some(doc), attrs=Some(attrs)),
    content="(\"foo\", Some(\"ultramega\"))",
  )
  debug_inspect(doc.attr("foo"), content="Some(\"ultramega\")")
  debug_inspect(
    attrs.entries,
    content="Some([{ name: \"foo\", value: Some(\"ultramega\"), negate: false }])",
  )
}

///|
test "store inaccessible attribute on document with value" {
  let doc = empty_document(attributes=[("foo", Str("baz"))])
  let attrs = Attributes::new()
  debug_inspect(
    store_attribute("foo", Some("bar"), doc=Some(doc), attrs=Some(attrs)),
    content="(\"foo\", Some(\"bar\"))",
  )
  debug_inspect(doc.attr("foo"), content="Some(\"baz\")")
  debug_inspect(attrs.entries, content="None")
}

///|
test "store accessible attribute on document with negated value" {
  for name in ["foo!", "!foo", "foo"] {
    let doc = empty_document()
    doc.set_attribute("foo", value="baz") |> ignore
    let attrs = Attributes::new()
    debug_inspect(
      store_attribute(name, None, doc=Some(doc), attrs=Some(attrs)),
      content="(\"foo\", None)",
    )
    debug_inspect(
      attrs.entries,
      content="Some([{ name: \"foo\", value: None, negate: true }])",
    )
  }
}

///|
test "store inaccessible attribute on document with negated value" {
  for name in ["foo!", "!foo", "foo"] {
    let doc = empty_document(attributes=[("foo", Str("baz"))])
    let attrs = Attributes::new()
    debug_inspect(
      store_attribute(name, None, doc=Some(doc), attrs=Some(attrs)),
      content="(\"foo\", None)",
    )
    debug_inspect(attrs.entries, content="None")
  }
}

///|
fn style_attrs(pairs : Array[(AttrKey, AttrVal)]) -> Attributes {
  let attrs = Attributes::new()
  for p in pairs {
    attrs.set_key(p.0, p.1)
  }
  attrs
}

///|
test "parse style attribute with id and role" {
  let attributes = style_attrs([(Pos(1), Str("style#id.role"))])
  debug_inspect(
    parse_style_attribute(attributes, None),
    content="Some(\"style\")",
  )
  inspect(
    inspect_attrs(attributes),
    content=(
      #|{1=>"style#id.role", "style"=>"style", "id"=>"id", "role"=>"role"}
    ),
  )
}

///|
test "parse style attribute with style, role, id and option" {
  let attributes = style_attrs([(Pos(1), Str("style.role#id%fragment"))])
  debug_inspect(
    parse_style_attribute(attributes, None),
    content="Some(\"style\")",
  )
  inspect(
    inspect_attrs(attributes),
    content=(
      #|{1=>"style.role#id%fragment", "style"=>"style", "id"=>"id", "role"=>"role", "fragment-option"=>""}
    ),
  )
  assert_false(attributes.contains("options"))
}

///|
test "parse style attribute with style, id and multiple roles" {
  let attributes = style_attrs([(Pos(1), Str("style#id.role1.role2"))])
  debug_inspect(
    parse_style_attribute(attributes, None),
    content="Some(\"style\")",
  )
  inspect(
    inspect_attrs(attributes),
    content=(
      #|{1=>"style#id.role1.role2", "style"=>"style", "id"=>"id", "role"=>"role1 role2"}
    ),
  )
}

///|
test "parse style attribute with style, multiple roles and id" {
  let attributes = style_attrs([(Pos(1), Str("style.role1.role2#id"))])
  debug_inspect(
    parse_style_attribute(attributes, None),
    content="Some(\"style\")",
  )
  inspect(
    inspect_attrs(attributes),
    content=(
      #|{1=>"style.role1.role2#id", "style"=>"style", "id"=>"id", "role"=>"role1 role2"}
    ),
  )
}

///|
test "parse style attribute with positional and original style" {
  let attributes = style_attrs([
    (Pos(1), Str("new_style")),
    (Name("style"), Str("original_style")),
  ])
  debug_inspect(
    parse_style_attribute(attributes, None),
    content="Some(\"new_style\")",
  )
  inspect(
    inspect_attrs(attributes),
    content=(
      #|{1=>"new_style", "style"=>"new_style"}
    ),
  )
}

///|
test "parse style attribute with id and role only" {
  let attributes = style_attrs([(Pos(1), Str("#id.role"))])
  debug_inspect(parse_style_attribute(attributes, None), content="None")
  inspect(
    inspect_attrs(attributes),
    content=(
      #|{1=>"#id.role", "id"=>"id", "role"=>"role"}
    ),
  )
}

///|
test "parse empty style attribute" {
  let attributes = style_attrs([(Pos(1), Nil)])
  debug_inspect(parse_style_attribute(attributes, None), content="None")
  inspect(
    inspect_attrs(attributes),
    content=(
      #|{1=>nil, "style"=>nil}
    ),
  )
}

///|
test "parse style attribute with option should preserve existing options" {
  let attributes = style_attrs([
    (Pos(1), Str("%header")),
    (Name("footer-option"), Str("")),
  ])
  debug_inspect(parse_style_attribute(attributes, None), content="None")
  inspect(
    inspect_attrs(attributes),
    content=(
      #|{1=>"%header", "footer-option"=>"", "header-option"=>""}
    ),
  )
}

///|
test "adjust indentation to 0" {
  let lines = @rb.split("    def names\n\n      @name.split\n\n    end\n", "\n")
  adjust_indentation(lines)
  inspect(
    lines.join("\n"),
    content=(
      #|def names
      #|
      #|  @name.split
      #|
      #|end
    ),
  )
}

///|
test "adjust indentation mixed with tabs and spaces to 0" {
  let lines = @rb.split("    def names\n\n\t  @name.split\n\n    end\n", "\n")
  adjust_indentation(lines, indent_size=0, tab_size=4)
  inspect(
    lines.join("\n"),
    content=(
      #|def names
      #|
      #|  @name.split
      #|
      #|end
    ),
  )
}

///|
test "expands tabs to spaces" {
  let input = "Filesystem\t\t\t\tSize\tUsed\tAvail\tUse%\tMounted on\nFilesystem              Size    Used    Avail   Use%    Mounted on\ndevtmpfs\t\t\t\t3.9G\t   0\t 3.9G\t  0%\t/dev\n/dev/mapper/fedora-root\t 48G\t 18G\t  29G\t 39%\t/\n"
  let lines = @rb.split(input, "\n")
  adjust_indentation(lines, indent_size=0, tab_size=4)
  inspect(
    lines.join("\n"),
    content=(
      #|Filesystem              Size    Used    Avail   Use%    Mounted on
      #|Filesystem              Size    Used    Avail   Use%    Mounted on
      #|devtmpfs                3.9G       0     3.9G     0%    /dev
      #|/dev/mapper/fedora-root  48G     18G      29G    39%    /
    ),
  )
}

///|
test "adjust indentation to non-zero" {
  let lines = @rb.split("    def names\n\n      @name.split\n\n    end\n", "\n")
  adjust_indentation(lines, indent_size=2)
  inspect(
    lines.join("\n"),
    content=(
      #|  def names
      #|
      #|    @name.split
      #|
      #|  end
    ),
  )
}

///|
test "preserve block indent if indent is -1" {
  let input = "    def names\n\n      @name.split\n\n    end\n"
  // Ruby: input.lines (each line keeps its LF)
  let lines = [
    "    def names\n", "\n", "      @name.split\n", "\n", "    end\n",
  ]
  adjust_indentation(lines, indent_size=-1)
  assert_eq(lines.join(""), input)
}

///|
test "adjust indentation handles empty lines gracefully" {
  let lines : Array[String] = []
  adjust_indentation(lines)
  debug_inspect(lines, content="[]")
}

///|
test "process_line returns nil if cursor advanced" {
  let input = "ifdef::asciidoctor[]\nAsciidoctor!\nendif::asciidoctor[]\n"
  let doc = new_document(Some(prepare_source_string(input)), wb_options())
  let reader = doc.reader().unwrap()
  debug_inspect(reader.process_line(reader.lines()[0]), content="None")
}

///|
test "process_line returns line if cursor not advanced" {
  let input = "content\nifdef::asciidoctor[]\nAsciidoctor!\nendif::asciidoctor[]\n"
  let doc = new_document(Some(prepare_source_string(input)), wb_options())
  let reader = doc.reader().unwrap()
  debug_inspect(
    reader.process_line(reader.lines()[0]),
    content="Some(\"content\")",
  )
}

///|
test "parse author first" {
  inspect(
    dump_metadata(parse_header_metadata_from("Stuart")),
    content=(
      #|size=5
      #|author: Stuart
      #|authorcount: 1
      #|authorinitials: S
      #|authors: Stuart
      #|firstname: Stuart
    ),
  )
}

///|
test "parse author first last" {
  inspect(
    dump_metadata(parse_header_metadata_from("Yukihiro Matsumoto")),
    content=(
      #|size=6
      #|author: Yukihiro Matsumoto
      #|authorcount: 1
      #|authorinitials: YM
      #|authors: Yukihiro Matsumoto
      #|firstname: Yukihiro
      #|lastname: Matsumoto
    ),
  )
}

///|
test "parse author first middle last" {
  inspect(
    dump_metadata(parse_header_metadata_from("David Heinemeier Hansson")),
    content=(
      #|size=7
      #|author: David Heinemeier Hansson
      #|authorcount: 1
      #|authorinitials: DHH
      #|authors: David Heinemeier Hansson
      #|firstname: David
      #|lastname: Hansson
      #|middlename: Heinemeier
    ),
  )
}

///|
test "parse author first middle last email" {
  inspect(
    dump_metadata(
      parse_header_metadata_from(
        "David Heinemeier Hansson <rails@ruby-lang.org>",
      ),
    ),
    content=(
      #|size=8
      #|author: David Heinemeier Hansson
      #|authorcount: 1
      #|authorinitials: DHH
      #|authors: David Heinemeier Hansson
      #|email: rails@ruby-lang.org
      #|firstname: David
      #|lastname: Hansson
      #|middlename: Heinemeier
    ),
  )
}

///|
test "parse author first email" {
  inspect(
    dump_metadata(parse_header_metadata_from("Stuart <founder@asciidoc.org>")),
    content=(
      #|size=6
      #|author: Stuart
      #|authorcount: 1
      #|authorinitials: S
      #|authors: Stuart
      #|email: founder@asciidoc.org
      #|firstname: Stuart
    ),
  )
}

///|
test "parse author first last email" {
  inspect(
    dump_metadata(
      parse_header_metadata_from("Stuart Rackham <founder@asciidoc.org>"),
    ),
    content=(
      #|size=7
      #|author: Stuart Rackham
      #|authorcount: 1
      #|authorinitials: SR
      #|authors: Stuart Rackham
      #|email: founder@asciidoc.org
      #|firstname: Stuart
      #|lastname: Rackham
    ),
  )
}

///|
test "parse author with hyphen" {
  inspect(
    dump_metadata(
      parse_header_metadata_from("Tim Berners-Lee <founder@www.org>"),
    ),
    content=(
      #|size=7
      #|author: Tim Berners-Lee
      #|authorcount: 1
      #|authorinitials: TB
      #|authors: Tim Berners-Lee
      #|email: founder@www.org
      #|firstname: Tim
      #|lastname: Berners-Lee
    ),
  )
}

///|
test "parse author with single quote" {
  inspect(
    dump_metadata(
      parse_header_metadata_from("Stephen O'Grady <founder@redmonk.com>"),
    ),
    content=(
      #|size=7
      #|author: Stephen O'Grady
      #|authorcount: 1
      #|authorinitials: SO
      #|authors: Stephen O'Grady
      #|email: founder@redmonk.com
      #|firstname: Stephen
      #|lastname: O'Grady
    ),
  )
}

///|
test "parse author with dotted initial" {
  inspect(
    dump_metadata(parse_header_metadata_from("Heiko W. Rupp <hwr@example.de>")),
    content=(
      #|size=8
      #|author: Heiko W. Rupp
      #|authorcount: 1
      #|authorinitials: HWR
      #|authors: Heiko W. Rupp
      #|email: hwr@example.de
      #|firstname: Heiko
      #|lastname: Rupp
      #|middlename: W.
    ),
  )
}

///|
test "parse author with underscore" {
  inspect(
    dump_metadata(parse_header_metadata_from("Tim_E Fella")),
    content=(
      #|size=6
      #|author: Tim E Fella
      #|authorcount: 1
      #|authorinitials: TF
      #|authors: Tim E Fella
      #|firstname: Tim E
      #|lastname: Fella
    ),
  )
}

///|
test "parse author name with letters outside basic latin" {
  inspect(
    dump_metadata(parse_header_metadata_from("Stéphane Brontë")),
    content=(
      #|size=6
      #|author: Stéphane Brontë
      #|authorcount: 1
      #|authorinitials: SB
      #|authors: Stéphane Brontë
      #|firstname: Stéphane
      #|lastname: Brontë
    ),
  )
}

///|
test "parse ideographic author names" {
  inspect(
    dump_metadata(parse_header_metadata_from("李 四 <si.li@example.com>")),
    content=(
      #|size=7
      #|author: 李 四
      #|authorcount: 1
      #|authorinitials: 李四
      #|authors: 李 四
      #|email: si.li@example.com
      #|firstname: 李
      #|lastname: 四
    ),
  )
}

///|
test "parse author condenses whitespace" {
  inspect(
    dump_metadata(
      parse_header_metadata_from(
        "Stuart       Rackham     <founder@asciidoc.org>",
      ),
    ),
    content=(
      #|size=7
      #|author: Stuart Rackham
      #|authorcount: 1
      #|authorinitials: SR
      #|authors: Stuart Rackham
      #|email: founder@asciidoc.org
      #|firstname: Stuart
      #|lastname: Rackham
    ),
  )
}

///|
test "parse invalid author line becomes author" {
  inspect(
    dump_metadata(
      parse_header_metadata_from(
        "   Stuart       Rackham, founder of AsciiDoc   <founder@asciidoc.org>",
      ),
    ),
    content=(
      #|size=5
      #|author: Stuart Rackham, founder of AsciiDoc <founder@asciidoc.org>
      #|authorcount: 1
      #|authorinitials: S
      #|authors: Stuart Rackham, founder of AsciiDoc <founder@asciidoc.org>
      #|firstname: Stuart Rackham, founder of AsciiDoc <founder@asciidoc.org>
    ),
  )
}

///|
test "parse multiple authors" {
  inspect(
    dump_metadata(
      parse_header_metadata_from(
        "Doc Writer <doc.writer@asciidoc.org>; John Smith <john.smith@asciidoc.org>",
      ),
    ),
    content=(
      #|size=17
      #|author: Doc Writer
      #|author_1: Doc Writer
      #|author_2: John Smith
      #|authorcount: 2
      #|authorinitials: DW
      #|authorinitials_1: DW
      #|authorinitials_2: JS
      #|authors: Doc Writer, John Smith
      #|email: doc.writer@asciidoc.org
      #|email_1: doc.writer@asciidoc.org
      #|email_2: john.smith@asciidoc.org
      #|firstname: Doc
      #|firstname_1: Doc
      #|firstname_2: John
      #|lastname: Writer
      #|lastname_1: Writer
      #|lastname_2: Smith
    ),
  )
}

///|
test "should not parse multiple authors if semi-colon is not followed by space" {
  inspect(
    dump_metadata(parse_header_metadata_from("Joe Doe;Smith Johnson")),
    content=(
      #|size=5
      #|author: Joe Doe;Smith Johnson
      #|authorcount: 1
      #|authorinitials: J
      #|authors: Joe Doe;Smith Johnson
      #|firstname: Joe Doe;Smith Johnson
    ),
  )
}

///|
test "skips blank author entries in implicit author line" {
  inspect(
    dump_metadata(
      parse_header_metadata_from(
        "Doc Writer; ; John Smith <john.smith@asciidoc.org>;",
      ),
    ),
    content=(
      #|size=15
      #|author: Doc Writer
      #|author_1: Doc Writer
      #|author_2: John Smith
      #|authorcount: 2
      #|authorinitials: DW
      #|authorinitials_1: DW
      #|authorinitials_2: JS
      #|authors: Doc Writer, John Smith
      #|email_2: john.smith@asciidoc.org
      #|firstname: Doc
      #|firstname_1: Doc
      #|firstname_2: John
      #|lastname: Writer
      #|lastname_1: Writer
      #|lastname_2: Smith
    ),
  )
}

///|
test "parse rev number date remark" {
  inspect(
    dump_metadata(
      parse_header_metadata_from(
        "Ryan Waldron\nv0.0.7, 2013-12-18: The first release you can stand on\n",
      ),
    ),
    content=(
      #|size=9
      #|author: Ryan Waldron
      #|authorcount: 1
      #|authorinitials: RW
      #|authors: Ryan Waldron
      #|firstname: Ryan
      #|lastname: Waldron
      #|revdate: 2013-12-18
      #|revnumber: 0.0.7
      #|revremark: The first release you can stand on
    ),
  )
}

///|
test "parse rev number, data, and remark as attribute references" {
  inspect(
    dump_metadata(
      parse_header_metadata_from(
        "Author Name\nv{project-version}, {release-date}: {release-summary}\n",
      ),
    ),
    content=(
      #|size=9
      #|author: Author Name
      #|authorcount: 1
      #|authorinitials: AN
      #|authors: Author Name
      #|firstname: Author
      #|lastname: Name
      #|revdate: {release-date}
      #|revnumber: {project-version}
      #|revremark: {release-summary}
    ),
  )
}

///|
test "parse rev date" {
  inspect(
    dump_metadata(parse_header_metadata_from("Ryan Waldron\n2013-12-18\n")),
    content=(
      #|size=7
      #|author: Ryan Waldron
      #|authorcount: 1
      #|authorinitials: RW
      #|authors: Ryan Waldron
      #|firstname: Ryan
      #|lastname: Waldron
      #|revdate: 2013-12-18
    ),
  )
}

///|
test "parse rev number with trailing comma" {
  inspect(
    dump_metadata(parse_header_metadata_from("Stuart Rackham\nv8.6.8,\n")),
    content=(
      #|size=7
      #|author: Stuart Rackham
      #|authorcount: 1
      #|authorinitials: SR
      #|authors: Stuart Rackham
      #|firstname: Stuart
      #|lastname: Rackham
      #|revnumber: 8.6.8
    ),
  )
}

///|
test "parse rev number" {
  inspect(
    dump_metadata(parse_header_metadata_from("Stuart Rackham\nv8.6.8\n")),
    content=(
      #|size=7
      #|author: Stuart Rackham
      #|authorcount: 1
      #|authorinitials: SR
      #|authors: Stuart Rackham
      #|firstname: Stuart
      #|lastname: Rackham
      #|revnumber: 8.6.8
    ),
  )
}

///|
test "treats arbitrary text on rev line as revdate" {
  inspect(
    dump_metadata(parse_header_metadata_from("Ryan Waldron\nfoobar\n")),
    content=(
      #|size=7
      #|author: Ryan Waldron
      #|authorcount: 1
      #|authorinitials: RW
      #|authors: Ryan Waldron
      #|firstname: Ryan
      #|lastname: Waldron
      #|revdate: foobar
    ),
  )
}

///|
test "parse rev date remark" {
  inspect(
    dump_metadata(
      parse_header_metadata_from(
        "Ryan Waldron\n2013-12-18:  The first release you can stand on\n",
      ),
    ),
    content=(
      #|size=8
      #|author: Ryan Waldron
      #|authorcount: 1
      #|authorinitials: RW
      #|authors: Ryan Waldron
      #|firstname: Ryan
      #|lastname: Waldron
      #|revdate: 2013-12-18
      #|revremark: The first release you can stand on
    ),
  )
}

///|
test "should not mistake attribute entry as rev remark" {
  inspect(
    dump_metadata(parse_header_metadata_from("Joe Cool\n:page-layout: post\n")),
    content=(
      #|size=6
      #|author: Joe Cool
      #|authorcount: 1
      #|authorinitials: JC
      #|authors: Joe Cool
      #|firstname: Joe
      #|lastname: Cool
    ),
  )
}

///|
test "parse rev remark only" {
  inspect(
    dump_metadata(
      parse_header_metadata_from(
        "Joe Cool\n :Must start revremark-only line with space\n",
      ),
    ),
    content=(
      #|size=7
      #|author: Joe Cool
      #|authorcount: 1
      #|authorinitials: JC
      #|authors: Joe Cool
      #|firstname: Joe
      #|lastname: Cool
      #|revremark: Must start revremark-only line with space
    ),
  )
}

///|
test "skip line comments before author" {
  inspect(
    dump_metadata(
      parse_header_metadata_from(
        "// Asciidoctor\n// release artist\nRyan Waldron\n",
      ),
    ),
    content=(
      #|size=6
      #|author: Ryan Waldron
      #|authorcount: 1
      #|authorinitials: RW
      #|authors: Ryan Waldron
      #|firstname: Ryan
      #|lastname: Waldron
    ),
  )
}

///|
test "skip block comment before author" {
  inspect(
    dump_metadata(
      parse_header_metadata_from(
        "////\nAsciidoctor\nrelease artist\n////\nRyan Waldron\n",
      ),
    ),
    content=(
      #|size=6
      #|author: Ryan Waldron
      #|authorcount: 1
      #|authorinitials: RW
      #|authors: Ryan Waldron
      #|firstname: Ryan
      #|lastname: Waldron
    ),
  )
}

///|
test "skip block comment before rev" {
  inspect(
    dump_metadata(
      parse_header_metadata_from(
        "Ryan Waldron\n////\nAsciidoctor\nrelease info\n////\nv0.0.7, 2013-12-18\n",
      ),
    ),
    content=(
      #|size=8
      #|author: Ryan Waldron
      #|authorcount: 1
      #|authorinitials: RW
      #|authors: Ryan Waldron
      #|firstname: Ryan
      #|lastname: Waldron
      #|revdate: 2013-12-18
      #|revnumber: 0.0.7
    ),
  )
}

///|
test "break header at line with three forward slashes" {
  inspect(
    dump_metadata(parse_header_metadata_from("Joe Cool\nv1.0\n///\nstuff\n")),
    content=(
      #|size=7
      #|author: Joe Cool
      #|authorcount: 1
      #|authorinitials: JC
      #|authors: Joe Cool
      #|firstname: Joe
      #|lastname: Cool
      #|revnumber: 1.0
    ),
  )
}

///|
test "returns empty hash if document has no authors and invoked without document" {
  inspect(
    dump_metadata(parse_header_metadata_from("")),
    content=(
      #|size=0
    ),
  )
}

///|
test "parse name with more than 3 parts in author attribute" {
  let doc = empty_document()
  let before = doc.attributes.names()
  let metadata = parse_header_metadata_from(
    ":author: Leroy  Harold  Scherer,  Jr.",
    doc~,
  )
  inspect(
    dump_metadata(metadata),
    content=(
      #|size=7
      #|author: Leroy Harold Scherer, Jr.
      #|authorcount: 1
      #|authorinitials: LHS
      #|authors: Leroy Harold Scherer, Jr.
      #|firstname: Leroy
      #|lastname: Scherer, Jr.
      #|middlename: Harold
    ),
  )
  inspect(
    dump_new_doc_attrs(doc, before),
    content=(
      #|author: Leroy Harold Scherer, Jr.
      #|authorcount: 1
      #|authorinitials: LHS
      #|authors: Leroy Harold Scherer, Jr.
      #|firstname: Leroy
      #|lastname: Scherer, Jr.
      #|middlename: Harold
    ),
  )
}

///|
test "use explicit authorinitials if set after implicit author line" {
  let doc = empty_document()
  let before = doc.attributes.names()
  let metadata = parse_header_metadata_from(
    "Jean-Claude Van Damme\n:authorinitials: JCVD\n",
    doc~,
  )
  inspect(
    dump_metadata(metadata),
    content=(
      #|size=7
      #|author: Jean-Claude Van Damme
      #|authorcount: 1
      #|authorinitials: JVD
      #|authors: Jean-Claude Van Damme
      #|firstname: Jean-Claude
      #|lastname: Damme
      #|middlename: Van
    ),
  )
  inspect(
    dump_new_doc_attrs(doc, before),
    content=(
      #|author: Jean-Claude Van Damme
      #|authorcount: 1
      #|authorinitials: JCVD
      #|authors: Jean-Claude Van Damme
      #|firstname: Jean-Claude
      #|lastname: Damme
      #|middlename: Van
    ),
  )
}

///|
test "use explicit authorinitials if set after author attribute" {
  let doc = empty_document()
  let before = doc.attributes.names()
  let metadata = parse_header_metadata_from(
    ":author: Jean-Claude Van Damme\n:authorinitials: JCVD\n",
    doc~,
  )
  inspect(
    dump_metadata(metadata),
    content=(
      #|size=6
      #|author: Jean-Claude Van Damme
      #|authorcount: 1
      #|authors: Jean-Claude Van Damme
      #|firstname: Jean-Claude
      #|lastname: Damme
      #|middlename: Van
    ),
  )
  inspect(
    dump_new_doc_attrs(doc, before),
    content=(
      #|author: Jean-Claude Van Damme
      #|authorcount: 1
      #|authorinitials: JCVD
      #|authors: Jean-Claude Van Damme
      #|firstname: Jean-Claude
      #|lastname: Damme
      #|middlename: Van
    ),
  )
}

///|
test "use implicit authors if value of authors attribute matches computed value" {
  let doc = empty_document()
  let before = doc.attributes.names()
  let metadata = parse_header_metadata_from(
    "Doc Writer; Junior Writer\n:authors: Doc Writer, Junior Writer\n",
    doc~,
  )
  inspect(
    dump_metadata(metadata),
    content=(
      #|size=14
      #|author: Doc Writer
      #|author_1: Doc Writer
      #|author_2: Junior Writer
      #|authorcount: 2
      #|authorinitials: DW
      #|authorinitials_1: DW
      #|authorinitials_2: JW
      #|authors: Doc Writer, Junior Writer
      #|firstname: Doc
      #|firstname_1: Doc
      #|firstname_2: Junior
      #|lastname: Writer
      #|lastname_1: Writer
      #|lastname_2: Writer
    ),
  )
  inspect(
    dump_new_doc_attrs(doc, before),
    content=(
      #|author: Doc Writer
      #|author_1: Doc Writer
      #|author_2: Junior Writer
      #|authorcount: 2
      #|authorinitials: DW
      #|authorinitials_1: DW
      #|authorinitials_2: JW
      #|authors: Doc Writer, Junior Writer
      #|firstname: Doc
      #|firstname_1: Doc
      #|firstname_2: Junior
      #|lastname: Writer
      #|lastname_1: Writer
      #|lastname_2: Writer
    ),
  )
}

///|
test "replace implicit authors if value of authors attribute does not match computed value" {
  let doc = empty_document()
  let before = doc.attributes.names()
  let metadata = parse_header_metadata_from(
    "Doc Writer; Junior Writer\n:authors: Stuart Rackham; Dan Allen; Sarah White\n",
    doc~,
  )
  inspect(
    dump_metadata(metadata),
    content=(
      #|size=18
      #|author: Stuart Rackham
      #|author_1: Stuart Rackham
      #|author_2: Dan Allen
      #|author_3: Sarah White
      #|authorcount: 3
      #|authorinitials: SR
      #|authorinitials_1: SR
      #|authorinitials_2: DA
      #|authorinitials_3: SW
      #|authors: Stuart Rackham, Dan Allen, Sarah White
      #|firstname: Stuart
      #|firstname_1: Stuart
      #|firstname_2: Dan
      #|firstname_3: Sarah
      #|lastname: Rackham
      #|lastname_1: Rackham
      #|lastname_2: Allen
      #|lastname_3: White
    ),
  )
  inspect(
    dump_new_doc_attrs(doc, before),
    content=(
      #|author: Stuart Rackham
      #|author_1: Stuart Rackham
      #|author_2: Dan Allen
      #|author_3: Sarah White
      #|authorcount: 3
      #|authorinitials: SR
      #|authorinitials_1: SR
      #|authorinitials_2: DA
      #|authorinitials_3: SW
      #|authors: Stuart Rackham, Dan Allen, Sarah White
      #|firstname: Stuart
      #|firstname_1: Stuart
      #|firstname_2: Dan
      #|firstname_3: Sarah
      #|lastname: Rackham
      #|lastname_1: Rackham
      #|lastname_2: Allen
      #|lastname_3: White
    ),
  )
}

///|
test "sets authorcount to 0 if document has no authors" {
  let doc = empty_document()
  let before = doc.attributes.names()
  let metadata = parse_header_metadata_from("", doc~)
  inspect(
    dump_metadata(metadata),
    content=(
      #|size=1
      #|authorcount: 0
    ),
  )
  inspect(
    dump_new_doc_attrs(doc, before),
    content=(
      #|authorcount: 0
    ),
  )
}

///|
test "does not drop name joiner when using multiple authors" {
  let doc = empty_document()
  let before = doc.attributes.names()
  let metadata = parse_header_metadata_from(
    "Kismet Chameleon; Lazarus het_Draeke",
    doc~,
  )
  inspect(
    dump_metadata(metadata),
    content=(
      #|size=14
      #|author: Kismet Chameleon
      #|author_1: Kismet Chameleon
      #|author_2: Lazarus het Draeke
      #|authorcount: 2
      #|authorinitials: KC
      #|authorinitials_1: KC
      #|authorinitials_2: Lh
      #|authors: Kismet Chameleon, Lazarus het Draeke
      #|firstname: Kismet
      #|firstname_1: Kismet
      #|firstname_2: Lazarus
      #|lastname: Chameleon
      #|lastname_1: Chameleon
      #|lastname_2: het Draeke
    ),
  )
  inspect(
    dump_new_doc_attrs(doc, before),
    content=(
      #|author: Kismet Chameleon
      #|author_1: Kismet Chameleon
      #|author_2: Lazarus het Draeke
      #|authorcount: 2
      #|authorinitials: KC
      #|authorinitials_1: KC
      #|authorinitials_2: Lh
      #|authors: Kismet Chameleon, Lazarus het Draeke
      #|firstname: Kismet
      #|firstname_1: Kismet
      #|firstname_2: Lazarus
      #|lastname: Chameleon
      #|lastname_1: Chameleon
      #|lastname_2: het Draeke
    ),
  )
}

///|
test "allows authors to be overridden using explicit author attributes" {
  let doc = empty_document()
  let before = doc.attributes.names()
  let metadata = parse_header_metadata_from(
    "Kismet Chameleon; Johnny Bravo; Lazarus het_Draeke\n:author_2: Danger Mouse\n",
    doc~,
  )
  inspect(
    dump_metadata(metadata),
    content=(
      #|size=18
      #|author: Kismet Chameleon
      #|author_1: Kismet Chameleon
      #|author_2: Danger Mouse
      #|author_3: Lazarus het Draeke
      #|authorcount: 3
      #|authorinitials: KC
      #|authorinitials_1: KC
      #|authorinitials_2: DM
      #|authorinitials_3: Lh
      #|authors: Kismet Chameleon, Danger Mouse, Lazarus het Draeke
      #|firstname: Kismet
      #|firstname_1: Kismet
      #|firstname_2: Danger
      #|firstname_3: Lazarus
      #|lastname: Chameleon
      #|lastname_1: Chameleon
      #|lastname_2: Mouse
      #|lastname_3: het Draeke
    ),
  )
  inspect(
    dump_new_doc_attrs(doc, before),
    content=(
      #|author: Kismet Chameleon
      #|author_1: Kismet Chameleon
      #|author_2: Danger Mouse
      #|author_3: Lazarus het Draeke
      #|authorcount: 3
      #|authorinitials: KC
      #|authorinitials_1: KC
      #|authorinitials_2: DM
      #|authorinitials_3: Lh
      #|authors: Kismet Chameleon, Danger Mouse, Lazarus het Draeke
      #|firstname: Kismet
      #|firstname_1: Kismet
      #|firstname_2: Danger
      #|firstname_3: Lazarus
      #|lastname: Chameleon
      #|lastname_1: Chameleon
      #|lastname_2: Mouse
      #|lastname_3: het Draeke
    ),
  )
}

///|
test "attribute entry overrides generated author initials" {
  let doc = empty_document()
  let before = doc.attributes.names()
  let metadata = parse_header_metadata_from(
    "Stuart Rackham <founder@asciidoc.org>\n:Author Initials: SJR",
    doc~,
  )
  inspect(
    dump_metadata(metadata),
    content=(
      #|size=7
      #|author: Stuart Rackham
      #|authorcount: 1
      #|authorinitials: SR
      #|authors: Stuart Rackham
      #|email: founder@asciidoc.org
      #|firstname: Stuart
      #|lastname: Rackham
    ),
  )
  inspect(
    dump_new_doc_attrs(doc, before),
    content=(
      #|author: Stuart Rackham
      #|authorcount: 1
      #|authorinitials: SJR
      #|authors: Stuart Rackham
      #|email: founder@asciidoc.org
      #|firstname: Stuart
      #|lastname: Rackham
    ),
  )
}

// ---------------------------------------------------------------------------
// Additional direct-API tests (not in parser_test.rb) for parser helpers the
// Ruby suite only exercises through conversion. Expected values were produced
// by calling the same Ruby methods (Parser.parse_section_title,
// Parser.parse_colspecs, Parser.process_attribute_entry).

///|
fn section_title_of(src : String) -> (String?, String?, String, Int, Bool) {
  let doc = new_document(Some([]), wb_options())
  parse_section_title(Reader::new(@rb.split(src, "\n")), doc, None)
}

///|
test "parse_section_title returns id, reftext, title, level and atx flag" {
  debug_inspect(
    section_title_of("== Section Title"),
    content="(None, None, \"Section Title\", 1, true)",
  )
  debug_inspect(
    section_title_of("=== Section Title ==="),
    content="(None, None, \"Section Title\", 2, true)",
  )
  debug_inspect(
    section_title_of("== Section Title [[sect-id]]"),
    content="(Some(\"sect-id\"), None, \"Section Title\", 1, true)",
  )
  debug_inspect(
    section_title_of("== Section Title [[sect-id,Ref Text]]"),
    content="(Some(\"sect-id\"), Some(\"Ref Text\"), \"Section Title\", 1, true)",
  )
  debug_inspect(
    section_title_of("Section Title\n-------------"),
    content="(None, None, \"Section Title\", 1, false)",
  )
  debug_inspect(
    section_title_of("Section Title [[sect-id]]\n~~~~~~~~~~~~~~~~~~~~~~~~~~"),
    content="(Some(\"sect-id\"), None, \"Section Title\", 2, false)",
  )
  debug_inspect(
    section_title_of("====== Level 5"),
    content="(None, None, \"Level 5\", 5, true)",
  )
  debug_inspect(
    section_title_of("= Document Title"),
    content="(None, None, \"Document Title\", 0, true)",
  )
  debug_inspect(
    section_title_of("== Title ending in escaped anchor \\[[not-id]]"),
    content="(None, None, \"Title ending in escaped anchor \\\\[[not-id]]\", 1, true)",
  )
}

///|
fn colspecs_of(spec : String) -> String {
  parse_colspecs(spec)
  .map(c => {
    let parts = ["width=\{c.width}"]
    if c.halign is Some(h) {
      parts.push("halign=\{h}")
    }
    if c.valign is Some(v) {
      parts.push("valign=\{v}")
    }
    if c.style is Some(s) {
      parts.push("style=\{s}")
    }
    "{" + parts.join(" ") + "}"
  })
  .join(", ")
}

///|
test "parse_colspecs" {
  inspect(colspecs_of("3"), content="{width=1}, {width=1}, {width=1}")
  inspect(colspecs_of("1,2,3"), content="{width=1}, {width=2}, {width=3}")
  inspect(colspecs_of("3*"), content="{width=1}, {width=1}, {width=1}")
  inspect(colspecs_of("2*,3"), content="{width=1}, {width=1}, {width=3}")
  inspect(
    colspecs_of("1,^2,>3"),
    content="{width=1}, {width=2 halign=center}, {width=3 halign=right}",
  )
  inspect(
    colspecs_of("<.^1,.>2a"),
    content="{width=1 halign=left valign=middle}, {width=2 valign=bottom style=asciidoc}",
  )
  inspect(colspecs_of("50%,50%"), content="{width=50}, {width=50}")
  inspect(
    colspecs_of("1e,2l"),
    content="{width=1 style=emphasis}, {width=2 style=literal}",
  )
  inspect(
    colspecs_of("3*^"),
    content="{width=1 halign=center}, {width=1 halign=center}, {width=1 halign=center}",
  )
  inspect(colspecs_of("*"), content="")
  inspect(colspecs_of("~,2"), content="{width=-1}, {width=2}")
  inspect(colspecs_of(" 1 , 2 "), content="{width=1}, {width=2}")
  inspect(colspecs_of("^.>3*2"), content="")
  inspect(colspecs_of("1;2;3"), content="{width=1}, {width=2}, {width=3}")
}

///|
fn attribute_entry_of(
  src : String,
) -> (Bool, Array[AttributeEntry], Array[String]) {
  let doc = new_document(Some([]), wb_options())
  let reader = Reader::new(@rb.split(src, "\n"))
  let attrs = Attributes::new()
  let r = process_attribute_entry(reader, Some(doc), Some(attrs), None)
  (r, attrs.entries.unwrap_or([]), reader.lines())
}

///|
test "process_attribute_entry" {
  debug_inspect(
    attribute_entry_of(":name: value"),
    content=(
      #|(
      #|  true,
      #|  [{ name: "name", value: Some("value"), negate: false }],
      #|  [":name: value"],
      #|)
    ),
  )
  debug_inspect(
    attribute_entry_of(":name!:"),
    content=(
      #|(true, [{ name: "name", value: None, negate: true }], [":name!:"])
    ),
  )
  debug_inspect(
    attribute_entry_of(":!name:"),
    content=(
      #|(true, [{ name: "name", value: None, negate: true }], [":!name:"])
    ),
  )
  debug_inspect(
    attribute_entry_of(":name: first line \\\nsecond line"),
    content=(
      #|(
      #|  true,
      #|  [{ name: "name", value: Some("first line second line"), negate: false }],
      #|  ["second line"],
      #|)
    ),
  )
  debug_inspect(
    attribute_entry_of(":name: line one +\nline two +\nline three"),
    content=(
      #|(
      #|  true,
      #|  [
      #|    {
      #|      name: "name",
      #|      value: Some("line one line two line three"),
      #|      negate: false,
      #|    },
      #|  ],
      #|  ["line three"],
      #|)
    ),
  )
  debug_inspect(
    attribute_entry_of(":Name With Spaces: val"),
    content=(
      #|(
      #|  true,
      #|  [{ name: "namewithspaces", value: Some("val"), negate: false }],
      #|  [":Name With Spaces: val"],
      #|)
    ),
  )
  debug_inspect(
    attribute_entry_of(":leveloffset: +2"),
    content=(
      #|(
      #|  true,
      #|  [{ name: "leveloffset", value: Some("2"), negate: false }],
      #|  [":leveloffset: +2"],
      #|)
    ),
  )
  debug_inspect(
    attribute_entry_of(":numbered:"),
    content=(
      #|(
      #|  true,
      #|  [{ name: "sectnums", value: Some(""), negate: false }],
      #|  [":numbered:"],
      #|)
    ),
  )
  debug_inspect(
    attribute_entry_of(":hardbreaks:"),
    content=(
      #|(
      #|  true,
      #|  [{ name: "hardbreaks-option", value: Some(""), negate: false }],
      #|  [":hardbreaks:"],
      #|)
    ),
  )
  debug_inspect(
    attribute_entry_of(":showtitle!:"),
    content=(
      #|(
      #|  true,
      #|  [
      #|    { name: "notitle", value: Some(""), negate: false },
      #|    { name: "showtitle", value: None, negate: true },
      #|  ],
      #|  [":showtitle!:"],
      #|)
    ),
  )
}
