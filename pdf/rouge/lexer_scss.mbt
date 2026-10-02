///|
/// Rouge's `Scss` (lexers/scss.rb).
pub fn scss(options : Map[String, String]) -> Lexer {
  let lx = Lexer::new("scss", options~)
  sass_common_states(lx)
  lx.state("root", fn(s) {
    s.rule("\\s+", "Text")
    s.rule("//.*?$", "Comment.Single")
    s.rule("/[*].*?[*]/", "Comment.Multiline", flags="m")
    s.rule("@import\\b", "Keyword", next="value")
    s.mix_in("content_common")
    s.call("(?=[^;{}][;}])", fn(lx, _) { lx.push("attribute") })
    s.call("(?=[^;{}:\\[]+:[^a-z])", fn(lx, _) { lx.push("attribute") })
    s.call("", fn(lx, _) { lx.push("selector") })
  })
  lx.state("end_section", fn(s) {
    s.rule("\\n", "Text")
    s.call("[;{}]", fn(lx, _) {
      lx.token("Punctuation")
      lx.reset_stack()
    })
  })
  lx
}
