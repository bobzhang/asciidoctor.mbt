///|
/// Rouge's `XML` (lexers/xml.rb).
pub fn xml(options : Map[String, String]) -> Lexer {
  let lx = Lexer::new("xml", options~)
  lx.state("root", fn(s) {
    s.rule("[^<&]+", "Text")
    s.rule("&\\S*?;", "Name.Entity")
    s.rule("<!\\[CDATA\\[.*?\\]\\]\\>", "Comment.Preproc")
    s.rule("<!--", "Comment", next="comment")
    s.rule("<\\?.*?\\?>", "Comment.Preproc")
    s.rule("<![^>]*>", "Comment.Preproc")
    // open tags
    s.rule(
      "<\\s*[\\p{L}:_][\\p{Word}\\p{Cf}:.·-]*",
      "Name.Tag",
      flags="m",
      next="tag",
    )
    // self-closing tags
    s.rule(
      "<\\s*/\\s*[\\p{L}:_][\\p{Word}\\p{Cf}:.·-]*\\s*>",
      "Name.Tag",
      flags="m",
    )
  })
  lx.state("comment", fn(s) {
    s.rule("[^-]+", "Comment", flags="m")
    s.rule("-->", "Comment", next="#pop")
    s.rule("-", "Comment")
  })
  lx.state("tag", fn(s) {
    s.rule("\\s+", "Text", flags="m")
    s.rule(
      "[\\p{L}:_][\\p{Word}\\p{Cf}:.·-]*\\s*=",
      "Name.Attribute",
      flags="m",
      next="attr",
    )
    s.rule("/?\\s*>", "Name.Tag", next="#pop")
  })
  lx.state("attr", fn(s) {
    s.rule("\\s+", "Text", flags="m")
    s.rule("\".*?\"|'.*?'|[^\\s>]+", "Literal.String", flags="m", next="#pop")
  })
  lx
}
