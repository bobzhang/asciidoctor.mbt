///|
/// The lexers of the web group (see `lexer_list`); a function since ERB
/// looks its parent lexer up (`find`).
fn web_lexers() -> Array[(String, Array[String], LexerFactory)] {
  [
    ("javascript", ["js"], javascript),
    ("json", [], json),
    ("json-doc", ["jsonc"], json_doc),
    ("css", [], css),
    ("html", [], html),
    ("sass", [], sass),
    ("scss", [], scss),
    ("typescript", ["ts"], typescript),
    ("jsx", ["jsx", "react"], jsx),
    ("tsx", [], tsx),
    ("erb", ["eruby", "rhtml"], erb),
    ("coffeescript", ["coffee", "coffee-script"], coffeescript),
    ("vue", ["vuejs"], vue),
  ]
}
