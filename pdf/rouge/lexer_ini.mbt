///|
/// Rouge's `INI` (lexers/ini.rb).
pub fn ini(options : Map[String, String]) -> Lexer {
  let lx = Lexer::new("ini", options~)
  let identifier = rx("[\\w\\-.]+")
  lx.state("basic", fn(s) {
    s.rule("[;#].*?\\n", "Comment")
    s.rule("\\s+", "Text")
    s.rule("\\\\\\n", "Literal.String.Escape")
  })
  lx.state("root", fn(s) {
    s.mix_in("basic")
    s.call("(\{identifier})(\\s*)(=)", fn(lx, _) {
      lx.groups(["Name.Property", "Text", "Punctuation"])
      lx.push("value")
    })
    s.rule("\\[.*?\\]", "Name.Namespace")
  })
  lx.state("value", fn(s) {
    s.rule("\\n", "Text", next="#pop")
    s.mix_in("basic")
    s.rule("\"", "Literal.String", next="dq")
    s.rule("'.*?'", "Literal.String")
    s.mix_in("esc_str")
    s.rule("[^\\\\\\n]+", "Literal.String")
  })
  lx.state("dq", fn(s) {
    s.rule("\"", "Literal.String", next="#pop")
    s.mix_in("esc_str")
    s.rule("[^\\\\\"]+", "Literal.String", flags="m")
  })
  lx.state("esc_str", fn(s) {
    s.rule("\\\\.", "Literal.String.Escape", flags="m")
  })
  lx
}
