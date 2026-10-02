///|
/// Rouge's `JSON` (lexers/json.rb).
pub fn json(options : Map[String, String]) -> Lexer {
  let lx = Lexer::new("json", options~)
  json_states(lx)
  lx
}

///|
/// The states of Rouge's `JSON`, shared with `JSONDOC`.
fn json_states(lx : Lexer) -> Unit {
  lx.state("whitespace", fn(s) { s.rule("\\s+", "Text.Whitespace") })
  lx.state("root", fn(s) {
    s.mix_in("whitespace")
    s.rule("{", "Punctuation", next="object")
    s.rule("\\[", "Punctuation", next="array")
    s.mix_in("name")
    s.mix_in("value")
    // These characters may be invalid but syntax correctness is a non-goal
    s.rule("[\\]}]", "Punctuation")
  })
  lx.state("object", fn(s) {
    s.mix_in("whitespace")
    s.mix_in("name")
    s.mix_in("value")
    s.rule("}", "Punctuation", next="#pop")
    s.rule(",", "Punctuation")
  })
  lx.state("name", fn(s) {
    s.call("(\"(?:\\\\.|[^\"\\\\\\n])*?\")(\\s*)(:)", fn(lx, _) {
      lx.groups(["Name.Label", "Text.Whitespace", "Punctuation"])
    })
  })
  lx.state("value", fn(s) {
    s.mix_in("whitespace")
    s.mix_in("constants")
    s.rule("\"", "Literal.String.Double", next="string")
    s.rule("\\[", "Punctuation", next="array")
    s.rule("{", "Punctuation", next="object")
  })
  lx.state("string", fn(s) {
    s.rule("[^\\\\\"]+", "Literal.String.Double")
    s.rule("\\\\.", "Literal.String.Escape")
    s.rule("\"", "Literal.String.Double", next="#pop")
  })
  lx.state("array", fn(s) {
    s.mix_in("value")
    s.rule("\\]", "Punctuation", next="#pop")
    s.rule(",", "Punctuation")
  })
  lx.state("constants", fn(s) {
    s.rule("(?:true|false|null)", "Keyword.Constant")
    s.rule(
      "-?(?:0|[1-9]\\d*)\\.\\d+(?:e[+-]?\\d+)?",
      "Literal.Number.Float",
      flags="i",
    )
    s.rule(
      "-?(?:0|[1-9]\\d*)(?:e[+-]?\\d+)?",
      "Literal.Number.Integer",
      flags="i",
    )
  })
}
