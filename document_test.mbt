// Direct-API tests ported from asciidoctor/test/document_test.rb. Each test is
// named after the Ruby test it ports. Helpers live in api_test.mbt.

// ---------------------------------------------------------------------------
// Document > Default settings

///|
test "safe mode level set to SECURE by default" {
  let doc = empty_document()
  assert_eq(doc.safe(), @core.SAFE_SECURE)
}

///|
test "safe mode level set using string" {
  // the MoonBit option is an Int; names are resolved with safe_mode_value_for_name
  let doc = empty_document(
    options=@core.Options::new(safe?=@core.safe_mode_value_for_name("server")),
  )
  assert_eq(doc.safe(), @core.SAFE_SERVER)
  let doc = empty_document(
    options=@core.Options::new(safe?=@core.safe_mode_value_for_name("foo")),
  )
  assert_eq(doc.safe(), @core.SAFE_SECURE)
}

///|
test "safe mode level set using integer" {
  let doc = empty_document(options=@core.Options::new(safe=10))
  assert_eq(doc.safe(), @core.SAFE_SERVER)
  let doc = empty_document(options=@core.Options::new(safe=100))
  inspect(doc.safe(), content="100")
  debug_inspect(doc.attributes.get("safe-mode-level"), content="Some(Int(100))")
  // Ruby: the name of an unrecognized level is nil, so safe-mode-name is unset
  assert_false(doc.has_attr("safe-mode-name"))
  assert_true(doc.has_attr("safe-mode-"))
}

///|
test "safe mode attributes are set on document" {
  let doc = empty_document()
  debug_inspect(doc.attributes.get("safe-mode-level"), content="Some(Int(20))")
  debug_inspect(doc.attr("safe-mode-name"), content="Some(\"secure\")")
  assert_true(doc.has_attr("safe-mode-secure"))
  assert_false(doc.has_attr("safe-mode-unsafe"))
  assert_false(doc.has_attr("safe-mode-safe"))
  assert_false(doc.has_attr("safe-mode-server"))
}

///|
test "safe mode level can be set in the constructor" {
  let doc = new_document(Some([]), @core.Options::new(safe=@core.SAFE_SAFE))
  assert_eq(doc.safe(), @core.SAFE_SAFE)
}

///|
test "toc and sectnums should be enabled by default in DocBook backend" {
  let doc = document_from_string(
    "content",
    options=@core.Options::new(backend="docbook"),
  )
  assert_true(doc.has_attr("toc"))
  assert_true(doc.has_attr("sectnums"))
  let result = doc.convert()
  assert_true(result.contains("<?asciidoc-toc?>"))
  assert_true(result.contains("<?asciidoc-numbered?>"))
}

///|
test "maxdepth attribute should be set on asciidoc-toc and asciidoc-numbered processing instructions in DocBook backend" {
  let doc = document_from_string(
    "content",
    options=@core.Options::new(backend="docbook", attributes=[
      ("toclevels", Str("1")),
      ("sectnumlevels", Str("1")),
    ]),
  )
  assert_true(doc.has_attr("toc"))
  assert_true(doc.has_attr("sectnums"))
  let result = doc.convert()
  assert_true(result.contains("<?asciidoc-toc maxdepth=\"1\"?>"))
  assert_true(result.contains("<?asciidoc-numbered maxdepth=\"1\"?>"))
}

///|
test "should be able to disable toc and sectnums in document header in DocBook backend" {
  let input =
    #|= Document Title
    #|:toc!:
    #|:sectnums!:
    #|
  let doc = document_from_string(
    input,
    options=@core.Options::new(backend="docbook"),
  )
  assert_false(doc.has_attr("toc"))
  assert_false(doc.has_attr("sectnums"))
}

///|
test "noheader attribute should suppress info element when converting to DocBook" {
  let input =
    #|= Document Title
    #|:noheader:
    #|
    #|content
    #|
  let result = document_from_string(
    input,
    options=@core.Options::new(backend="docbook"),
  ).convert()
  assert_true(result.contains("<article "))
  assert_false(result.contains("<info>"))
}

///|
test "should be able to disable section numbering using numbered attribute in document header in DocBook backend" {
  let doc = document_from_string(
    "= Document Title\n:numbered!:\n",
    options=@core.Options::new(backend="docbook"),
  )
  assert_false(doc.has_attr("sectnums"))
}

// ---------------------------------------------------------------------------
// Document > Converter

///|
test "convert methods on built-in converter are registered by default" {
  let doc = document_from_string("")
  debug_inspect(doc.attributes.get("backend"), content="Some(Str(\"html5\"))")
  assert_true(doc.attributes.contains("backend-html5"))
  debug_inspect(
    doc.attributes.get("basebackend"),
    content="Some(Str(\"html\"))",
  )
  assert_true(doc.attributes.contains("basebackend-html"))
  inspect(doc.converter().backend_traits().basebackend, content="html")
}

///|
test "convert methods on built-in converter are registered when backend is docbook5" {
  let doc = document_from_string(
    "",
    options=@core.Options::new(attributes=[("backend", Str("docbook5"))]),
  )
  debug_inspect(
    doc.attributes.get("backend"),
    content="Some(Str(\"docbook5\"))",
  )
  assert_true(doc.attributes.contains("backend-docbook5"))
  debug_inspect(
    doc.attributes.get("basebackend"),
    content="Some(Str(\"docbook\"))",
  )
  assert_true(doc.attributes.contains("basebackend-docbook"))
  inspect(doc.converter().backend_traits().basebackend, content="docbook")
}

// ---------------------------------------------------------------------------
// Document > Structure

///|
test "document with no doctitle" {
  let doc = document_from_string("Snorf")
  debug_inspect(doc.doctitle(), content="None")
  assert_false(doc.has_header())
  assert_true(doc.header() is None)
}

///|
let legacy_doctitle_input : String =
  #|Document Title
  #|==============
  #|
  #|+content+
  #|

///|
test "should enable compat mode for document with legacy doctitle" {
  let doc = document_from_string(legacy_doctitle_input)
  assert_true(doc.has_attr("compat-mode"))
  assert_true(doc.convert().contains("<code>content</code>"))
}

///|
test "should not enable compat mode for document with legacy doctitle if compat mode disable by header" {
  let input =
    #|Document Title
    #|==============
    #|:compat-mode!:
    #|
    #|+content+
    #|
  let doc = document_from_string(input)
  debug_inspect(doc.attr("compat-mode"), content="None")
  assert_false(doc.convert().contains("<code>content</code>"))
}

///|
test "should not enable compat mode for document with legacy doctitle if compat mode is locked by API" {
  let doc = document_from_string(
    legacy_doctitle_input,
    options=@core.Options::new(attributes=[("compat-mode", Nil)]),
  )
  assert_true(doc.attribute_locked("compat-mode"))
  debug_inspect(doc.attr("compat-mode"), content="None")
  assert_false(doc.convert().contains("<code>content</code>"))
}

///|
test "title partition API with default separator" {
  let title = @core.DocTitle::new("Main Title: And More: Subtitle")
  inspect(title.main, content="Main Title: And More")
  debug_inspect(title.subtitle, content="Some(\"Subtitle\")")
}

///|
test "title partition API with custom separator" {
  let title = @core.DocTitle::new(
    "Main Title:: And More:: Subtitle",
    separator="::",
  )
  inspect(title.main, content="Main Title:: And More")
  debug_inspect(title.subtitle, content="Some(\"Subtitle\")")
}

///|
test "document with subtitle" {
  let input =
    #|= Main Title: *Subtitle*
    #|Author Name
    #|
    #|content
    #|
  let doc = document_from_string(input)
  let title = doc.doctitle_partitioned(sanitize=true).unwrap()
  assert_true(title.has_subtitle())
  assert_true(title.sanitized)
  debug_inspect(
    title,
    content=(
      #|{
      #|  main: "Main Title",
      #|  subtitle: Some("Subtitle"),
      #|  combined: "Main Title: Subtitle",
      #|  sanitized: true,
      #|}
    ),
  )
}

///|
test "document with subtitle and custom separator" {
  let input =
    #|[separator=::]
    #|= Main Title:: *Subtitle*
    #|Author Name
    #|
    #|content
    #|
  let doc = document_from_string(input)
  let title = doc.doctitle_partitioned(sanitize=true).unwrap()
  assert_true(title.has_subtitle())
  assert_true(title.sanitized)
  inspect(title.main, content="Main Title")
  debug_inspect(title.subtitle, content="Some(\"Subtitle\")")
}

///|
test "should not honor custom separator for doctitle if attribute is locked by API" {
  let input =
    #|[separator=::]
    #|= Main Title - *Subtitle*
    #|Author Name
    #|
    #|content
    #|
  let doc = document_from_string(
    input,
    options=@core.Options::new(attributes=[("title-separator", Str(" -"))]),
  )
  let title = doc.doctitle_partitioned(sanitize=true).unwrap()
  assert_true(title.has_subtitle())
  assert_true(title.sanitized)
  inspect(title.main, content="Main Title")
  debug_inspect(title.subtitle, content="Some(\"Subtitle\")")
}

///|
test "document with doctitle defined as attribute entry" {
  let input =
    #|:doctitle: Document Title
    #|
    #|preamble
    #|
    #|== First Section
    #|
  let doc = document_from_string(input)
  debug_inspect(doc.doctitle(), content="Some(\"Document Title\")")
  assert_true(doc.has_header())
  debug_inspect(
    doc.header().unwrap().title(),
    content="Some(\"Document Title\")",
  )
  debug_inspect(
    doc.first_section().unwrap().title(),
    content="Some(\"Document Title\")",
  )
}

///|
test "document with doctitle defined as attribute entry followed by block with title" {
  let input =
    #|:doctitle: Document Title
    #|
    #|.Block title
    #|Block content
    #|
  let doc = document_from_string(input)
  debug_inspect(doc.doctitle(), content="Some(\"Document Title\")")
  assert_true(doc.has_header())
  inspect(doc.blocks.length(), content="1")
  debug_inspect(doc.blocks[0].context, content="Paragraph")
  debug_inspect(doc.blocks[0].title(), content="Some(\"Block title\")")
}

///|
test "document with title attribute entry overrides doctitle" {
  let input =
    #|= Document Title
    #|:title: Override
    #|
    #|{doctitle}
    #|
    #|== First Section
    #|
  let doc = document_from_string(input)
  debug_inspect(doc.doctitle(), content="Some(\"Override\")")
  debug_inspect(doc.title(), content="Some(\"Override\")")
  assert_true(doc.has_header())
  debug_inspect(
    doc.header().unwrap().title(),
    content="Some(\"Document Title\")",
  )
  debug_inspect(
    doc.first_section().unwrap().title(),
    content="Some(\"Document Title\")",
  )
  assert_true(
    doc
    .convert()
    .contains(
      "<div id=\"preamble\">\n<div class=\"sectionbody\">\n<div class=\"paragraph\">\n<p>Document Title</p>",
    ),
  )
}

///|
test "document with blank title attribute entry overrides doctitle" {
  let input =
    #|= Document Title
    #|:title:
    #|
    #|{doctitle}
    #|
    #|== First Section
    #|
  let doc = document_from_string(input)
  debug_inspect(doc.doctitle(), content="Some(\"\")")
  debug_inspect(doc.title(), content="Some(\"\")")
  assert_true(doc.has_header())
  debug_inspect(
    doc.header().unwrap().title(),
    content="Some(\"Document Title\")",
  )
  debug_inspect(
    doc.first_section().unwrap().title(),
    content="Some(\"Document Title\")",
  )
  assert_true(
    doc
    .convert()
    .contains(
      "<div id=\"preamble\">\n<div class=\"sectionbody\">\n<div class=\"paragraph\">\n<p>Document Title</p>",
    ),
  )
}

///|
test "document header can reference intrinsic doctitle attribute" {
  let input =
    #|= ACME Documentation
    #|:intro: Welcome to the {doctitle}!
    #|
    #|{intro}
    #|
  let doc = document_from_string(input)
  debug_inspect(
    doc.attr("intro"),
    content="Some(\"Welcome to the ACME Documentation!\")",
  )
  assert_true(
    doc.convert().contains("<p>Welcome to the ACME Documentation!</p>"),
  )
}

///|
test "document with title attribute entry overrides doctitle attribute entry" {
  let input =
    #|= Document Title
    #|:snapshot: {doctitle}
    #|:doctitle: doctitle
    #|:title: Override
    #|
    #|{snapshot}, {doctitle}
    #|
    #|== First Section
    #|
  let doc = document_from_string(input)
  debug_inspect(doc.doctitle(), content="Some(\"Override\")")
  debug_inspect(doc.title(), content="Some(\"Override\")")
  assert_true(doc.has_header())
  debug_inspect(doc.header().unwrap().title(), content="Some(\"doctitle\")")
  debug_inspect(
    doc.first_section().unwrap().title(),
    content="Some(\"doctitle\")",
  )
  assert_true(doc.convert().contains("<p>Document Title, doctitle</p>"))
}

///|
test "document with doctitle attribute entry overrides implicit doctitle" {
  let input =
    #|= Document Title
    #|:snapshot: {doctitle}
    #|:doctitle: Override
    #|
    #|{snapshot}, {doctitle}
    #|
    #|== First Section
    #|
  let doc = document_from_string(input)
  debug_inspect(doc.doctitle(), content="Some(\"Override\")")
  debug_inspect(doc.attributes.get("title"), content="None")
  assert_true(doc.has_header())
  debug_inspect(doc.header().unwrap().title(), content="Some(\"Override\")")
  debug_inspect(
    doc.first_section().unwrap().title(),
    content="Some(\"Override\")",
  )
  assert_true(doc.convert().contains("<p>Document Title, Override</p>"))
}

///|
test "doctitle attribute entry above header overrides implicit doctitle" {
  let input =
    #|:doctitle: Override
    #|= Document Title
    #|
    #|{doctitle}
    #|
    #|== First Section
    #|
  let doc = document_from_string(input)
  debug_inspect(doc.doctitle(), content="Some(\"Override\")")
  debug_inspect(doc.attributes.get("title"), content="None")
  assert_true(doc.has_header())
  debug_inspect(doc.header().unwrap().title(), content="Some(\"Override\")")
  debug_inspect(
    doc.first_section().unwrap().title(),
    content="Some(\"Override\")",
  )
  assert_true(
    doc
    .convert()
    .contains(
      "<div id=\"preamble\">\n<div class=\"sectionbody\">\n<div class=\"paragraph\">\n<p>Override</p>",
    ),
  )
}

///|
test "should apply header substitutions to value of the doctitle attribute assigned from implicit doctitle" {
  let input =
    #|= <Foo> {plus} <Bar>
    #|
    #|The name of the game is {doctitle}.
    #|
  let doc = document_from_string(input)
  debug_inspect(
    doc.attr("doctitle"),
    content="Some(\"&lt;Foo&gt; &#43; &lt;Bar&gt;\")",
  )
  assert_true(doc.blocks[0].content().contains("&lt;Foo&gt; &#43; &lt;Bar&gt;"))
}

///|
test "should substitute attribute reference in implicit document title for attribute defined earlier in header" {
  let input =
    #|:project-name: ACME
    #|= {project-name} Docs
    #|
    #|{doctitle}
    #|
  let (doc, messages) = @core.with_memory_logger(() => {
    document_from_string(
      input,
      options=@core.Options::new(attributes=[("attribute-missing", Str("warn"))]),
    )
  })
  assert_true(messages.is_empty())
  debug_inspect(doc.attr("doctitle"), content="Some(\"ACME Docs\")")
  debug_inspect(doc.doctitle(), content="Some(\"ACME Docs\")")
  assert_true(doc.convert().contains("<p>ACME Docs</p>"))
}

///|
test "should not warn if implicit document title contains attribute reference for attribute defined later in header" {
  let input =
    #|= {project-name} Docs
    #|:project-name: ACME
    #|
    #|{doctitle}
    #|
  let (doc, messages) = @core.with_memory_logger(() => {
    document_from_string(
      input,
      options=@core.Options::new(attributes=[("attribute-missing", Str("warn"))]),
    )
  })
  assert_true(messages.is_empty())
  debug_inspect(doc.attr("doctitle"), content="Some(\"{project-name} Docs\")")
  debug_inspect(doc.doctitle(), content="Some(\"ACME Docs\")")
  let (output, messages) = @core.with_memory_logger(() => doc.convert())
  assert_true(messages.is_empty())
  assert_true(output.contains("<p>{project-name} Docs</p>"))
}

///|
test "should recognize document title when preceded by blank lines" {
  let input =
    #|
    #|= Title
    #|
    #|preamble
    #|
    #|== Section 1
    #|
    #|text
    #|
  let doc = document_from_string(
    input,
    options=@core.Options::new(safe=@core.SAFE_SAFE),
  )
  assert_true(doc.has_header())
  debug_inspect(doc.doctitle(), content="Some(\"Title\")")
  debug_inspect(doc.blocks.map(b => b.context), content="[Preamble, Section]")
}

///|
test "should recognize document title when preceded by blank lines introduced by a preprocessor conditional" {
  let input =
    #|ifdef::sectids[]
    #|
    #|:foo: bar
    #|endif::[]
    #|= Title
    #|
    #|preamble
    #|
    #|== Section 1
    #|
    #|text
    #|
  let doc = document_from_string(
    input,
    options=@core.Options::new(safe=@core.SAFE_SAFE),
  )
  assert_true(doc.has_header())
  debug_inspect(doc.doctitle(), content="Some(\"Title\")")
  debug_inspect(doc.blocks.map(b => b.context), content="[Preamble, Section]")
}

///|
test "should recognize document title when preceded by blank lines after an attribute entry" {
  let input =
    #|:doctype: book
    #|
    #|= Title
    #|
    #|preamble
    #|
    #|== Section 1
    #|
    #|text
    #|
  let doc = document_from_string(
    input,
    options=@core.Options::new(safe=@core.SAFE_SAFE),
  )
  assert_true(doc.has_header())
  debug_inspect(doc.doctitle(), content="Some(\"Title\")")
  debug_inspect(doc.blocks.map(b => b.context), content="[Preamble, Section]")
}

///|
test "document with multiline attribute entry but only one line should not crash" {
  let doc = document_from_string(":foo: bar +")
  debug_inspect(doc.attributes.get("foo"), content="Some(Str(\"bar\"))")
}

///|
test "should not choke on empty source" {
  let doc = new_document(Some([]), @core.Options::new())
  assert_true(doc.blocks.is_empty())
  debug_inspect(doc.doctitle(), content="None")
  assert_false(doc.has_header())
  assert_true(doc.header() is None)
}

///|
test "should not choke on nil source" {
  let doc = new_document(None, @core.Options::new())
  assert_true(doc.blocks.is_empty())
  debug_inspect(doc.doctitle(), content="None")
  assert_false(doc.has_header())
  assert_true(doc.header() is None)
}

///|
test "should parse revision line if date is empty" {
  let input =
    #|= Document Title
    #|Author Name
    #|v1.0.0,:remark
    #|
    #|content
    #|
  let doc = document_from_string(input)
  debug_inspect(doc.attributes.get("revnumber"), content="Some(Str(\"1.0.0\"))")
  debug_inspect(doc.attributes.get("revdate"), content="None")
  debug_inspect(
    doc.attributes.get("revremark"),
    content="Some(Str(\"remark\"))",
  )
}

///|
test "should process author defined by attribute when implicit doctitle is absent" {
  let input =
    #|:author: Doc Writer
    #|
    #|{lastname}, {firstname} ({authorinitials})
    #|
  let doc = document_from_string(
    input,
    options=@core.Options::new(standalone=false),
  )
  debug_inspect(doc.attr("author"), content="Some(\"Doc Writer\")")
  debug_inspect(doc.attr("author_1"), content="None")
  debug_inspect(doc.attr("lastname"), content="Some(\"Writer\")")
  debug_inspect(doc.attr("firstname"), content="Some(\"Doc\")")
  debug_inspect(doc.attr("authorinitials"), content="Some(\"DW\")")
  debug_inspect(doc.attributes.get("authorcount"), content="Some(Int(1))")
  assert_true(doc.convert().contains("<p>Writer, Doc (DW)</p>"))
}

///|
test "should process author and authorinitials defined by attribute when implicit doctitle is absent" {
  let input =
    #|:authorinitials: DOC
    #|:author: Doc Writer
    #|
    #|{lastname}, {firstname} ({authorinitials})
    #|
  let doc = document_from_string(
    input,
    options=@core.Options::new(standalone=false),
  )
  debug_inspect(doc.attr("author"), content="Some(\"Doc Writer\")")
  debug_inspect(doc.attr("authorinitials"), content="Some(\"DOC\")")
  debug_inspect(doc.attributes.get("authorcount"), content="Some(Int(1))")
  assert_true(doc.convert().contains("<p>Writer, Doc (DOC)</p>"))
}

///|
test "should process authors defined by attribute when implicit doctitle is absent" {
  let input =
    #|:authors: Doc Writer; Other Author
    #|
    #|{lastname}, {firstname} ({authorinitials})
    #|
  let doc = document_from_string(
    input,
    options=@core.Options::new(standalone=false),
  )
  let names = [
    "author", "authors", "author_1", "lastname", "lastname_1", "firstname", "firstname_1",
    "authorinitials", "authorinitials_1", "author_2", "authorinitials_2",
  ]
  debug_inspect(
    names.map(n => doc.attr(n).unwrap_or("<nil>")),
    content=(
      #|[
      #|  "Doc Writer",
      #|  "Doc Writer, Other Author",
      #|  "Doc Writer",
      #|  "Writer",
      #|  "Writer",
      #|  "Doc",
      #|  "Doc",
      #|  "DW",
      #|  "DW",
      #|  "Other Author",
      #|  "OA",
      #|]
    ),
  )
  debug_inspect(doc.attributes.get("authorcount"), content="Some(Int(2))")
  assert_true(doc.convert().contains("<p>Writer, Doc (DW)</p>"))
}

///|
test "should process authors and authorinitials defined by attribute when implicit doctitle is absent" {
  let input =
    #|:authorinitials: DOC
    #|:authors: Doc Writer; Other Author
    #|
    #|{lastname}, {firstname} ({authorinitials})
    #|
  let doc = document_from_string(
    input,
    options=@core.Options::new(standalone=false),
  )
  debug_inspect(doc.attr("author"), content="Some(\"Doc Writer\")")
  debug_inspect(doc.attr("author_1"), content="Some(\"Doc Writer\")")
  // FIXME (upstream) this should be DOC
  debug_inspect(doc.attr("authorinitials"), content="Some(\"DW\")")
  debug_inspect(doc.attr("author_2"), content="Some(\"Other Author\")")
  debug_inspect(doc.attributes.get("authorcount"), content="Some(Int(2))")
  assert_true(doc.convert().contains("<p>Writer, Doc (DW)</p>"))
}

///|
test "should set authorcount to 0 if document has no header" {
  let doc = document_from_string("content")
  debug_inspect(doc.attributes.get("authorcount"), content="Some(Int(0))")
}

///|
test "should set authorcount to 0 if author not set by attribute and implicit doctitle is missing" {
  let input =
    #|:idprefix:
    #|
    #|== Section Title
    #|
    #|content
    #|
  let doc = document_from_string(input)
  debug_inspect(doc.attributes.get("authorcount"), content="Some(Int(0))")
}

///|
test "should set authorcount to 0 if author not set by attribute and document starts with level-0 section with style" {
  let input =
    #|:doctype: book
    #|
    #|[preface]
    #|= Preface
    #|
    #|content
    #|
    #|= Part
    #|
    #|== Chapter
    #|
    #|content
    #|
  let doc = document_from_string(input)
  debug_inspect(doc.attributes.get("authorcount"), content="Some(Int(0))")
}

///|
test "with author defined by indexed attribute name" {
  let input =
    #|= Document Title
    #|:author_1: Doc Writer
    #|
    #|{author}
    #|
  let doc = document_from_string(input)
  debug_inspect(doc.attr("author"), content="Some(\"Doc Writer\")")
  debug_inspect(doc.attr("author_1"), content="Some(\"Doc Writer\")")
}

///|
test "with header footer" {
  let doc = document_from_string("= Title\n\nparagraph")
  assert_false(doc.has_attr("embedded"))
  let result = doc.convert()
  assert_true(result.contains("<html"))
  assert_true(result.contains("<div id=\"header\">\n<h1>Title</h1>"))
  assert_true(result.contains("<div id=\"footer\">"))
  assert_true(result.contains("<div id=\"content\">"))
}

///|
test "should create embedded document if standalone option passed to constructor is false" {
  let doc = new_document(
    Some(["= Document Title", "", "content"]),
    @core.Options::new(standalone=false),
  ).parse()
  assert_true(doc.has_attr("embedded"))
  inspect(
    doc.convert(),
    content=(
      #|<div class="paragraph">
      #|<p>content</p>
      #|</div>
    ),
  )
}

///|
test "should create embedded document if standalone option passed to convert method is false" {
  let doc = new_document(
    Some(["= Document Title", "", "content"]),
    @core.Options::new(standalone=true),
  ).parse()
  assert_false(doc.has_attr("embedded"))
  inspect(
    doc.convert_with(standalone=false),
    content=(
      #|<h1>Document Title</h1>
      #|<div class="paragraph">
      #|<p>content</p>
      #|</div>
    ),
  )
}

///|
test "parse header only" {
  let input =
    #|= Document Title
    #|Author Name
    #|:foo: bar
    #|
    #|preamble
    #|
  let doc = document_from_string(
    input,
    options=@core.Options::new(parse_header_only=true),
  )
  debug_inspect(doc.doctitle(), content="Some(\"Document Title\")")
  debug_inspect(doc.author(), content="Some(\"Author Name\")")
  debug_inspect(doc.attributes.get("foo"), content="Some(Str(\"bar\"))")
  inspect(doc.blocks.length(), content="0")
}

///|
test "should parse header only when docytpe is manpage" {
  let input =
    #|= cmd(1)
    #|Author Name
    #|:doctype: manpage
    #|
    #|== Name
    #|
    #|cmd - does stuff
    #|
  let doc = document_from_string(
    input,
    options=@core.Options::new(parse_header_only=true),
  )
  debug_inspect(doc.doctitle(), content="Some(\"cmd(1)\")")
  debug_inspect(doc.author(), content="Some(\"Author Name\")")
  debug_inspect(doc.attr("mantitle"), content="Some(\"cmd\")")
  debug_inspect(doc.attr("manvolnum"), content="Some(\"1\")")
  debug_inspect(doc.attr("manname"), content="None")
  debug_inspect(doc.attr("manpurpose"), content="None")
  inspect(doc.blocks.length(), content="0")
}

///|
test "should not warn when parsing header only when docytpe is manpage and body is empty" {
  let input =
    #|= cmd(1)
    #|Author Name
    #|:doctype: manpage
    #|
  let (doc, messages) = @core.with_memory_logger(() => {
    document_from_string(
      input,
      options=@core.Options::new(parse_header_only=true),
    )
  })
  assert_true(messages.is_empty())
  debug_inspect(doc.doctitle(), content="Some(\"cmd(1)\")")
  debug_inspect(doc.author(), content="Some(\"Author Name\")")
  debug_inspect(doc.attr("mantitle"), content="Some(\"cmd\")")
  debug_inspect(doc.attr("manvolnum"), content="Some(\"1\")")
  debug_inspect(doc.attr("manname"), content="None")
  debug_inspect(doc.attr("manpurpose"), content="None")
  inspect(doc.blocks.length(), content="0")
}

///|
test "outputs footnotes in footer" {
  let input =
    #|A footnote footnote:[An example footnote.];
    #|a second footnote with a reference ID footnote:note2[Second footnote.];
    #|and finally a reference to the second footnote footnote:note2[].
    #|
  let doc = document_from_string(input)
  // footnotes are registered during conversion
  assert_false(doc.has_footnotes())
  let output = doc.convert()
  debug_inspect(
    doc.footnotes(),
    content=(
      #|[
      #|  { index: 1, id: None, text: "An example footnote." },
      #|  { index: 2, id: Some("note2"), text: "Second footnote." },
      #|]
    ),
  )
  assert_true(
    output.contains(
      "<div class=\"footnote\" id=\"_footnotedef_1\">\n<a href=\"#_footnoteref_1\">1</a>. An example footnote.\n</div>",
    ),
  )
  assert_true(
    output.contains(
      "<div class=\"footnote\" id=\"_footnotedef_2\">\n<a href=\"#_footnoteref_2\">2</a>. Second footnote.\n</div>",
    ),
  )
}

// ---------------------------------------------------------------------------
// Document > Catalog

///|
test "should alias document catalog as document references" {
  let input =
    #|= Document Title
    #|
    #|== Section A
    #|
    #|Content
    #|
    #|== Section B
    #|
    #|Content.footnote:[commentary]
    #|
  let doc = document_from_string(input)
  let refs = doc.catalog().refs.keys().collect()
  debug_inspect(refs, content="[\"_section_a\", \"_section_b\"]")
  debug_inspect(doc.resolve_id("Section A"), content="Some(\"_section_a\")")
}

///|
test "should return nil if there is already an entry for ID in the :refs table" {
  let doc = empty_document()
  let anchor = doc.new_inline(
    Anchor,
    text="[tigers]",
    type_="ref",
    target="tigers",
  )
  assert_true(doc.register_ref("tigers", anchor))
  assert_false(doc.register_ref("tigers", anchor))
  assert_true(physical_equal(doc.catalog().refs["tigers"], anchor))
}

///|
test "should record imagesdir when image is registered with catalog" {
  let doc = empty_document(
    options=@core.Options::new(
      attributes=[("imagesdir", Str("img"))],
      catalog_assets=true,
    ),
  )
  doc.register_image("diagram.svg")
  debug_inspect(
    doc.catalog().images,
    content=(
      #|[{ target: "diagram.svg", imagesdir: Some("img") }]
    ),
  )
}

///|
test "should catalog assets inside nested document" {
  let input =
    #|image::outer.png[]
    #|
    #||===
    #|a|
    #|image::inner.png[]
    #||===
    #|
  let doc = document_from_string(
    input,
    options=@core.Options::new(catalog_assets=true),
  )
  debug_inspect(
    doc.catalog().images.map(i => i.target),
    content="[\"outer.png\", \"inner.png\"]",
  )
}

// ---------------------------------------------------------------------------
// Document > Backends and Doctypes

///|
test "xhtml5 backend should map to html5 and set htmlsyntax to xml" {
  let doc = document_from_string(
    "content",
    options=@core.Options::new(backend="xhtml5"),
  )
  inspect(doc.backend(), content="html5")
  debug_inspect(doc.attr("htmlsyntax"), content="Some(\"xml\")")
}

///|
test "xhtml backend should map to html5 and set htmlsyntax to xml" {
  let doc = document_from_string(
    "content",
    options=@core.Options::new(backend="xhtml"),
  )
  inspect(doc.backend(), content="html5")
  debug_inspect(doc.attr("htmlsyntax"), content="Some(\"xml\")")
}

///|
test "honor htmlsyntax attribute passed via API if backend is html" {
  let doc = document_from_string(
    "---",
    options=@core.Options::new(safe=@core.SAFE_SAFE, attributes=[
      ("htmlsyntax", Str("xml")),
    ]),
  )
  inspect(doc.backend(), content="html5")
  debug_inspect(doc.attr("htmlsyntax"), content="Some(\"xml\")")
  inspect(doc.convert_with(standalone=false), content="<hr/>")
}

///|
test "honor htmlsyntax attribute in document header if followed by backend attribute" {
  let input =
    #|:htmlsyntax: xml
    #|:backend: html5
    #|
    #|---
    #|
  let doc = document_from_string(
    input,
    options=@core.Options::new(safe=@core.SAFE_SAFE),
  )
  inspect(doc.backend(), content="html5")
  debug_inspect(doc.attr("htmlsyntax"), content="Some(\"xml\")")
  inspect(doc.convert_with(standalone=false), content="<hr/>")
}

///|
test "does not honor htmlsyntax attribute in document header if not followed by backend attribute" {
  let input =
    #|:backend: html5
    #|:htmlsyntax: xml
    #|
    #|---
    #|
  let result = convert_string_to_embedded(
    input,
    options=@core.Options::new(safe=@core.SAFE_SAFE),
  )
  inspect(result, content="<hr>")
}

///|
test "should apply replacements substitution to value of mantitle attribute used in DocBook output" {
  let input =
    #|= foo\--bar(1)
    #|Author Name
    #|:doctype: manpage
    #|:man manual: Foo Bar Manual
    #|:man source: Foo Bar 1.0
    #|
    #|== NAME
    #|
    #|foo--bar - puts the foo in your bar
    #|
  let doc = @asciidoctor.load(
    input,
    options=@core.Options::new(backend="docbook", standalone=true),
  )
  debug_inspect(doc.attr("mantitle"), content="Some(\"foo\\\\--bar\")")
  let result = doc.convert()
  assert_true(result.contains("<title>foo--bar(1)</title>"))
  assert_true(result.contains("<refentrytitle>foo--bar</refentrytitle>"))
}

///|
test "should be able to set backend using :backend option key" {
  let doc = empty_document(options=@core.Options::new(backend="html5"))
  debug_inspect(doc.attributes.get("backend"), content="Some(Str(\"html5\"))")
}

///|
test ":backend option should override backend attribute" {
  let doc = empty_document(
    options=@core.Options::new(backend="html5", attributes=[
      ("backend", Str("docbook5")),
    ]),
  )
  debug_inspect(doc.attributes.get("backend"), content="Some(Str(\"html5\"))")
}

///|
test "should be able to set doctype using :doctype option key" {
  let doc = empty_document(options=@core.Options::new(doctype="book"))
  debug_inspect(doc.attributes.get("doctype"), content="Some(Str(\"book\"))")
}

///|
test ":doctype option should override doctype attribute" {
  let doc = empty_document(
    options=@core.Options::new(doctype="book", attributes=[
      ("doctype", Str("article")),
    ]),
  )
  debug_inspect(doc.attributes.get("doctype"), content="Some(Str(\"book\"))")
}

///|
test "do not override explicit author initials" {
  let input =
    #|= AsciiDoc
    #|Stuart Rackham <founder@asciidoc.org>
    #|:Author Initials: SJR
    #|
    #|more info...
    #|
  let doc = document_from_string(
    input,
    options=@core.Options::new(attributes=[("backend", Str("docbook5"))]),
  )
  debug_inspect(doc.attr("authorinitials"), content="Some(\"SJR\")")
  assert_true(doc.convert().contains("<authorinitials>SJR</authorinitials>"))
}

///|
test "attribute entry can appear immediately after document title" {
  let input =
    #|Reference Guide
    #|===============
    #|:toc:
    #|
    #|preamble
    #|
  let doc = document_from_string(input)
  assert_true(doc.has_attr("toc"))
  debug_inspect(doc.attr("toc"), content="Some(\"\")")
}

///|
test "attribute entry can appear before author line under document title" {
  let input =
    #|Reference Guide
    #|===============
    #|:toc:
    #|Dan Allen
    #|
    #|preamble
    #|
  let doc = document_from_string(input)
  assert_true(doc.has_attr("toc"))
  debug_inspect(doc.attr("toc"), content="Some(\"\")")
  debug_inspect(doc.attr("author"), content="Some(\"Dan Allen\")")
}

///|
test "should parse mantitle and manvolnum from document title for manpage doctype" {
  let input =
    #|= asciidoctor ( 1 )
    #|:doctype: manpage
    #|
    #|== NAME
    #|
    #|asciidoctor - converts AsciiDoc source files to HTML, DocBook and other formats
    #|
  let doc = document_from_string(input)
  debug_inspect(doc.attr("mantitle"), content="Some(\"asciidoctor\")")
  debug_inspect(doc.attr("manvolnum"), content="Some(\"1\")")
}

///|
test "should perform attribute substitution on mantitle in manpage doctype" {
  let input =
    #|= {app}(1)
    #|:doctype: manpage
    #|:app: Asciidoctor
    #|
    #|== NAME
    #|
    #|asciidoctor - converts AsciiDoc source files to HTML, DocBook and other formats
    #|
  let doc = document_from_string(input)
  debug_inspect(doc.attr("mantitle"), content="Some(\"asciidoctor\")")
}

///|
let manpage_name_input : String =
  #|= asciidoctor(1)
  #|:doctype: manpage
  #|
  #|== NAME
  #|
  #|asciidoctor - converts AsciiDoc source files to HTML, DocBook and other formats
  #|

///|
test "should consume name section as manname and manpurpose for manpage doctype" {
  let doc = document_from_string(manpage_name_input)
  debug_inspect(doc.attr("manname"), content="Some(\"asciidoctor\")")
  debug_inspect(
    doc.attr("manpurpose"),
    content="Some(\"converts AsciiDoc source files to HTML, DocBook and other formats\")",
  )
  debug_inspect(doc.attr("manname-id"), content="Some(\"_name\")")
  inspect(doc.blocks.length(), content="0")
}

///|
test "should set docname and outfilesuffix from manname and manvolnum for manpage backend and doctype" {
  let doc = document_from_string(
    manpage_name_input,
    options=@core.Options::new(backend="manpage"),
  )
  debug_inspect(
    doc.attributes.get("docname"),
    content="Some(Str(\"asciidoctor\"))",
  )
  debug_inspect(
    doc.attributes.get("outfilesuffix"),
    content="Some(Str(\".1\"))",
  )
}

///|
test "should mark synopsis as special section in manpage doctype" {
  let input =
    #|= asciidoctor(1)
    #|:doctype: manpage
    #|
    #|== NAME
    #|
    #|asciidoctor - converts AsciiDoc source files to HTML, DocBook and other formats
    #|
    #|== SYNOPSIS
    #|
    #|*asciidoctor* ['OPTION']... 'FILE'..
    #|
  let doc = document_from_string(input)
  let synopsis_section = doc.blocks[0]
  debug_inspect(synopsis_section.context, content="Section")
  assert_true(synopsis_section.special)
  debug_inspect(synopsis_section.sectname, content="Some(\"synopsis\")")
}

// ---------------------------------------------------------------------------
// Document > Secure Asset Path

///|
fn secure_asset_vfs() -> @core.MemoryVfs {
  @core.MemoryVfs::new(cwd="/project", home="/home/user")
}

///|
test "allows us to specify a path relative to the current dir" {
  let doc = empty_document(options=@core.Options::new(vfs=secure_asset_vfs()))
  let legit_path = "/project/foo"
  inspect(doc.normalize_asset_path(legit_path), content="/project/foo")
}

///|
test "keeps naughty absolute paths from getting outside" {
  let naughty_path = "/etc/passwd"
  let (secure_path, messages) = @core.with_memory_logger(() => {
    let doc = empty_document(options=@core.Options::new(vfs=secure_asset_vfs()))
    doc.normalize_asset_path(naughty_path)
  })
  inspect(secure_path, content="/project/etc/passwd")
  debug_inspect(
    messages.map(m => (m.severity, m.text)),
    content=(
      #|[(Warn, "path is outside of jail; recovering automatically")]
    ),
  )
}

///|
test "keeps naughty relative paths from getting outside" {
  let naughty_path = "safe/ok/../../../../../etc/passwd"
  let (secure_path, _) = @core.with_memory_logger(() => {
    let doc = empty_document(options=@core.Options::new(vfs=secure_asset_vfs()))
    doc.normalize_asset_path(naughty_path)
  })
  assert_true(secure_path != naughty_path)
  assert_true(secure_path.has_prefix("/project"))
}

// ---------------------------------------------------------------------------
// Document > Date time attributes

///|
test "should compute docyear and docdatetime from docdate and doctime" {
  let doc = new_document(
    Some([]),
    @core.Options::new(attributes=[
      ("docdate", Str("2015-01-01")),
      ("doctime", Str("10:00:00-0700")),
    ]),
  )
  debug_inspect(doc.attr("docdate"), content="Some(\"2015-01-01\")")
  debug_inspect(doc.attr("docyear"), content="Some(\"2015\")")
  debug_inspect(doc.attr("doctime"), content="Some(\"10:00:00-0700\")")
  debug_inspect(
    doc.attr("docdatetime"),
    content="Some(\"2015-01-01 10:00:00-0700\")",
  )
}

///|
test "should allow docdate and doctime to be overridden" {
  let options = @core.Options::new(attributes=[
    ("docdate", Str("2015-01-01")),
    ("doctime", Str("10:00:00-0700")),
  ])
  options.input_mtime = Some(1546398245L)
  let doc = new_document(Some([]), options)
  debug_inspect(doc.attr("docdate"), content="Some(\"2015-01-01\")")
  debug_inspect(doc.attr("docyear"), content="Some(\"2015\")")
  debug_inspect(doc.attr("doctime"), content="Some(\"10:00:00-0700\")")
  debug_inspect(
    doc.attr("docdatetime"),
    content="Some(\"2015-01-01 10:00:00-0700\")",
  )
}

///|
test "should compute docdatetime from doctime" {
  let doc = new_document(
    Some([]),
    @core.Options::new(attributes=[("doctime", Str("10:00:00-0700"))]),
  )
  debug_inspect(doc.attr("doctime"), content="Some(\"10:00:00-0700\")")
  assert_true(doc.attr("docdatetime").unwrap().has_suffix(" 10:00:00-0700"))
}

///|
test "should compute docyear from docdate" {
  let doc = new_document(
    Some([]),
    @core.Options::new(attributes=[("docdate", Str("2015-01-01"))]),
  )
  debug_inspect(doc.attr("docyear"), content="Some(\"2015\")")
  assert_true(doc.attr("docdatetime").unwrap().has_prefix("2015-01-01 "))
}

///|
test "should allow doctime to be overridden" {
  // Ruby uses Time.new(2019, 1, 2, 3, 4, 5, '+06:00'); the port takes the
  // input mtime as seconds since the epoch and formats it in UTC, so the
  // equivalent UTC instant 2019-01-02T03:04:05Z is used here
  let options = @core.Options::new(attributes=[
    ("doctime", Str("10:00:00-0700")),
  ])
  options.input_mtime = Some(1546398245L)
  let doc = new_document(Some([]), options)
  debug_inspect(doc.attr("docdate"), content="Some(\"2019-01-02\")")
  debug_inspect(doc.attr("docyear"), content="Some(\"2019\")")
  debug_inspect(doc.attr("doctime"), content="Some(\"10:00:00-0700\")")
  debug_inspect(
    doc.attr("docdatetime"),
    content="Some(\"2019-01-02 10:00:00-0700\")",
  )
}

///|
test "should allow docdate to be overridden" {
  // see above: Ruby's '+0600' zone becomes UTC in the port
  let options = @core.Options::new(attributes=[("docdate", Str("2015-01-01"))])
  options.input_mtime = Some(1546398245L)
  let doc = new_document(Some([]), options)
  debug_inspect(doc.attr("docdate"), content="Some(\"2015-01-01\")")
  debug_inspect(doc.attr("docyear"), content="Some(\"2015\")")
  debug_inspect(
    doc.attr("docdatetime"),
    content="Some(\"2015-01-01 03:04:05 UTC\")",
  )
}
