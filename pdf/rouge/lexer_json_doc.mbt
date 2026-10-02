///|
/// Rouge's `JSONDOC` (lexers/json_doc.rb): JSON with comments and
/// unquoted keys.
pub fn json_doc(options : Map[String, String]) -> Lexer {
  let lx = Lexer::new("json-doc", options~)
  json_states(lx)
  lx.prepend("name", fn(s) {
    s.call("([$\\w]+)(\\s*)(:)", fn(lx, _) {
      lx.groups(["Name.Attribute", "Text", "Punctuation"])
    })
  })
  lx.prepend("value", fn(s) {
    s.rule("/[*].*?[*]/", "Comment")
    s.rule("//.*?$", "Comment.Single")
    s.rule("(\\.\\.\\.)", "Comment.Single")
  })
  lx
}
