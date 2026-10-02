///|
/// Rouge's `Conf` (lexers/conf.rb): a generic lexer for configuration
/// files.
pub fn conf(options : Map[String, String]) -> Lexer {
  let lx = Lexer::new("conf", options~)
  // short and sweet
  lx.state("root", fn(s) {
    s.rule("#.*?\\n", "Comment")
    s.rule("\".*?\"", "Literal.String.Double")
    s.rule("'.*?'", "Literal.String.Single")
    s.rule("[a-z]\\w*", "Name", flags="i")
    s.rule("\\d+", "Literal.Number")
    s.rule("[^\\w#\"']+", "Text")
  })
  lx
}
