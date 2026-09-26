// Black-box tests ported from asciidoctor/test/parser_test.rb (the tests that
// go through a document rather than calling Parser helpers directly; see
// parser_api_wbtest.mbt for those). Helpers live in reader_api_test.mbt.

///|
test "removes formatting before partitioning author defined using author attribute" {
  // Ruby calls Parser.parse_header_metadata on the attribute entry directly;
  // here the entry is parsed as part of a document header. Converting the
  // link in the pass macro requires a converter.
  @html5.register()
  let input =
    #|= Document Title
    #|:author: pass:n[http://example.org/community/team.html[Ze_**Project** team]]
    #|
  let doc = @core.new_document(
    Some(@core.prepare_source_string(input)),
    @core.Options::new(parse_header_only=true),
  ).parse()
  debug_inspect(doc.attributes.get("authorcount"), content="Some(Int(1))")
  inspect(
    doc.attributes.str("authors").unwrap(),
    content=(
      #|<a href="http://example.org/community/team.html">Ze <strong>Project</strong> team</a>
    ),
  )
  inspect(doc.attributes.str("firstname").unwrap(), content="Ze Project")
  inspect(doc.attributes.str("lastname").unwrap(), content="team")
  inspect(doc.attributes.str("authorinitials").unwrap(), content="Zt")
}

///|
test "should resolve attribute references in rev number, data, and remark" {
  let input =
    #|= Document Title
    #|Author Name
    #|{project-version}, {release-date}: {release-summary}
    #|
  let doc = document_from_string(input, attributes=[
    ("project-version", Str("1.0.1")),
    ("release-date", Str("2018-05-15")),
    ("release-summary", Str("The one you can count on!")),
  ])
  debug_inspect(doc.attr("revnumber"), content="Some(\"1.0.1\")")
  debug_inspect(doc.attr("revdate"), content="Some(\"2018-05-15\")")
  debug_inspect(
    doc.attr("revremark"),
    content="Some(\"The one you can count on!\")",
  )
}

///|
test "should warn if inline anchor is already in use" {
  let input =
    #|[#in-use]
    #|A paragraph with an id.
    #|
    #|Another paragraph
    #|[[in-use]]that uses an id
    #|which is already in use.
    #|
  let (_, messages) = @core.with_memory_logger(() => {
    document_from_string(input) |> ignore
  })
  inspect(
    fmt_logs(messages),
    content="WARN: <stdin>: line 5: id assigned to anchor already in use: in-use",
  )
}
