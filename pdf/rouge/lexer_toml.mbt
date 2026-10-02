///|
/// Rouge's `TOML` (lexers/toml.rb).
pub fn toml(options : Map[String, String]) -> Lexer {
  let lx = Lexer::new("toml", options~)
  // bare keys and quoted keys
  let identifier = rx("(?:\\S+|\"[^\"]+\"|'[^']+')")
  lx.state("basic", fn(s) {
    s.rule("\\s+", "Text")
    s.rule("#.*?$", "Comment")
    s.rule("(true|false)", "Keyword.Constant")
    s.call("(\{identifier})(\\s*)(=)(\\s*)(\\{)", fn(lx, _) {
      lx.groups(["Name.Namespace", "Text", "Operator", "Text", "Punctuation"])
      lx.push("inline")
    })
    s.rule("(?<!=)\\s*\\[[\\S]+\\]", "Name.Namespace")
    s.rule("\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z", "Literal.Date")
    s.rule(
      "[+-]?\\d+(?:_\\d+)*\\.\\d+(?:_\\d+)*(?:[eE][+-]?\\d+(?:_\\d+)*)?", "Literal.Number.Float",
    )
    s.rule("[+-]?\\d+(?:_\\d+)*[eE][+-]?\\d+(?:_\\d+)*", "Literal.Number.Float")
    s.rule("[+-]?(?:nan|inf)", "Literal.Number.Float")
    s.rule("0x\\h+(?:_\\h+)*", "Literal.Number.Hex")
    s.rule("0o[0-7]+(?:_[0-7]+)*", "Literal.Number.Oct")
    s.rule("0b[01]+(?:_[01]+)*", "Literal.Number.Bin")
    s.rule("[+-]?\\d+(?:_\\d+)*", "Literal.Number.Integer")
  })
  lx.state("root", fn(s) {
    s.mix_in("basic")
    s.call("(\{identifier})(\\s*)(=)", fn(lx, _) {
      lx.groups(["Name.Property", "Text", "Punctuation"])
      lx.push("value")
    })
  })
  lx.state("value", fn(s) {
    s.rule("\\n", "Text", next="#pop")
    s.mix_in("content")
  })
  lx.state("content", fn(s) {
    s.mix_in("basic")
    s.call("(\{identifier})(\\s*)(=)", fn(lx, _) {
      lx.groups(["Name.Property", "Text", "Punctuation"])
    })
    s.rule("\"\"\"", "Literal.String", next="mdq")
    s.rule("\"", "Literal.String", next="dq")
    s.rule("'''", "Literal.String", next="msq")
    s.rule("'", "Literal.String", next="sq")
    s.mix_in("esc_str")
    s.rule("\\,", "Punctuation")
    s.rule("\\[", "Punctuation", next="array")
  })
  lx.state("dq", fn(s) {
    s.rule("\"", "Literal.String", next="#pop")
    s.rule("\\n", "Error", next="#pop")
    s.mix_in("esc_str")
    s.rule("[^\\\\\"\\n]+", "Literal.String")
  })
  lx.state("mdq", fn(s) {
    s.rule("\"\"\"", "Literal.String", next="#pop")
    s.mix_in("esc_str")
    s.rule("[^\\\\\"]+", "Literal.String")
    s.rule("\"+", "Literal.String")
  })
  lx.state("sq", fn(s) {
    s.rule("'", "Literal.String", next="#pop")
    s.rule("\\n", "Error", next="#pop")
    s.rule("[^'\\n]+", "Literal.String")
  })
  lx.state("msq", fn(s) {
    s.rule("'''", "Literal.String", next="#pop")
    s.rule("[^']+", "Literal.String")
    s.rule("'+", "Literal.String")
  })
  lx.state("esc_str", fn(s) {
    s.rule("\\\\[0t\\tn\\n \"\\\\r]", "Literal.String.Escape")
  })
  lx.state("array", fn(s) {
    s.mix_in("content")
    s.rule("\\]", "Punctuation", next="#pop")
  })
  lx.state("inline", fn(s) {
    s.mix_in("content")
    s.rule("\\}", "Punctuation", next="#pop")
  })
  lx
}
