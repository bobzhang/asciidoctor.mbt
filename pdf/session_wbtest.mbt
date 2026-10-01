///|
/// Load `text` for the `pdf` backend, reproducibly (no dates).
fn load_pdf(text : String) -> @core.Node {
  @asciidoctor.load(
    text,
    options=@core.Options::new(backend="pdf", standalone=true, attributes=[
      ("reproducible", Str("")),
    ]),
  )
}

///|
/// A document in the base theme (12pt text), with what keeps state across
/// its load and conversion: index terms, footnotes, bibliography
/// references.
let doc_a : String =
  #|= Document A
  #|:doctype: book
  #|:pdf-theme: base
  #|
  #|== Chapter
  #|
  #|A paragraph about ((apples)) and ((pears)).footnote:[A note in A.]
  #|See <<ref-a>>.
  #|
  #|[bibliography]
  #|== References
  #|
  #|* [[[ref-a]]] A reference.
  #|
  #|[index]
  #|== Index
  #|

///|
/// A document in the default theme (10.5pt text), with state of its own.
let doc_b : String =
  #|= Document B
  #|:doctype: book
  #|
  #|== First
  #|
  #|Text with ((bananas)).footnote:[The first note of B.]
  #|footnote:[The second note of B.]
  #|
  #|== Second
  #|
  #|More ((cherries)).footnote:[The third note of B.]
  #|
  #|[index]
  #|== Index
  #|

///|
test "documents loaded one after the other keep their own state" {
  register()
  // each alone
  let alone_a = convert_document(load_pdf(doc_a), test_catalog())
  let warnings_a = conversion_warnings()
  let alone_b = convert_document(load_pdf(doc_b), test_catalog())
  // loaded A then B, converted B then A
  let a = load_pdf(doc_a)
  let b = load_pdf(doc_b)
  let interleaved_b = convert_document(b, test_catalog())
  let interleaved_a = convert_document(a, test_catalog())
  inspect(interleaved_a == alone_a, content="true")
  inspect(interleaved_b == alone_b, content="true")
  inspect(conversion_warnings() == warnings_a, content="true")
  // and the base theme's 12pt text is not the default theme's 10.5pt
  inspect(alone_a == alone_b, content="false")
}

///|
test "a theme warning given while loading is reported by the conversion" {
  register()
  // the section title is converted while the document is loaded, its
  // quotes from the theme
  let doc = load_pdf(
    "= Title\n:pdf-theme: no-such\n\n== A \"`quoted`\" title\n\ntext\n",
  )
  // another document loaded in between
  ignore(load_pdf("other"))
  ignore(convert_document(doc, test_catalog()))
  inspect(
    conversion_warnings().join("\n"),
    content=(
      #|WARNING could not locate or load the built-in pdf theme `no-such' because of No such file or directory @ rb_sysopen - /asciidoctor-pdf/data/themes/no-such-theme.yml; reverting to default theme at <document>
    ),
  )
}
