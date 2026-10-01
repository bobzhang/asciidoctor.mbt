// Helpers exposed to backends that live outside this module (the PDF
// backend). Expected values are Ruby's.

///|
test "ruby_upcase and ruby_downcase follow Ruby's full Unicode case mapping" {
  inspect(@core.ruby_upcase("straße"), content="STRASSE")
  inspect(@core.ruby_upcase("ŉ"), content="ʼN")
  inspect(@core.ruby_downcase("ÉCOLE Ǆ"), content="école ǆ")
}

///|
test "ruby_capitalize titlecases the first character as Ruby does" {
  inspect(@core.ruby_capitalize("élan VITAL"), content="Élan vital")
  inspect(@core.ruby_capitalize("ǆungla"), content="ǅungla")
  inspect(@core.ruby_capitalize("ǳa"), content="ǲa")
  inspect(@core.ruby_capitalize("ß"), content="Ss")
  inspect(@core.ruby_capitalize("ﬀx"), content="Ffx")
  inspect(@core.ruby_capitalize("ŉ"), content="ʼN")
  inspect(@core.ruby_capitalize("ᾀ"), content="ᾈ")
  inspect(@core.ruby_capitalize(""), content="")
}

///|
test "attribute_modified matches Ruby's @attributes_modified" {
  // Ruby records an attribute the document unsets in its header, not the
  // ones it sets there: @attributes_modified is ["sectids"] here
  let doc = @asciidoctor.load("= Title\n:icons: font\n:!sectids:\n\ntext\n")
  inspect(doc.attribute_modified("sectids"), content="true")
  inspect(doc.attribute_modified("icons"), content="false")
  inspect(doc.attribute_modified("doctype"), content="false")
}
