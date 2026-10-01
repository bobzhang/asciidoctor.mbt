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
  // values checked against Ruby Asciidoctor: header entries that set or
  // unset are recorded; in the body only unsetting is; `icons` is locked in
  // the default secure mode, so its entry is ignored
  let doc = @asciidoctor.load(
    "= Title\n:hset: x\n:!hunset:\n:icons: font\n:!sectids:\n\n:bset: y\n\n:!bunset:\n\ntext\n",
  )
  doc.convert() |> ignore
  inspect(doc.attribute_modified("hset"), content="true")
  inspect(doc.attribute_modified("hunset"), content="true")
  inspect(doc.attribute_modified("sectids"), content="true")
  inspect(doc.attribute_modified("bset"), content="false")
  inspect(doc.attribute_modified("bunset"), content="true")
  inspect(doc.attribute_modified("icons"), content="false")
  inspect(doc.attribute_modified("doctype"), content="false")
}
