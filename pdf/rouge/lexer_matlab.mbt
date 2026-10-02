///|
/// MATLAB's keywords (Rouge's `Matlab.keywords`).
let matlab_keywords : Set[String] = word_set(
  (
    #|arguments break case catch classdef continue else elseif end for
    #|function global if import methods otherwise parfor persistent
    #|properties return spmd switch try while
  ),
)

///|
/// Rouge's `Matlab` (lexers/matlab.rb). Shell escapes (`!command`) go to
/// the shell lexer (plain text while it is not ported).
pub fn matlab(options : Map[String, String]) -> Lexer {
  let lx = Lexer::new("matlab", options~)
  lx.state("root", fn(s) {
    s.rule("\\s+", "Text", flags="m") // Whitespace
    s.rule("[{]%.*?%[}]", "Comment.Multiline", flags="m")
    s.rule("%.*$", "Comment.Single")
    s.call("([.][.][.])(.*?)$", fn(lx, _) { lx.groups(["Keyword", "Comment"]) })
    s.call("^(!)(.*?)(?=%|$)", fn(lx, m) {
      lx.token("Keyword", val=group_text(m, 1))
      lx.delegate_new(
        fn() { script_lexer_or_text("shell", Map([])) },
        text=group_text(m, 2),
      )
    })
    s.call(
      "[a-zA-Z][_a-zA-Z0-9]*",
      fn(lx, m) {
        let name = m.matched()
        if matlab_keywords.contains(name) {
          lx.token("Keyword")
        } else if matlab_builtins.contains(name) {
          lx.token("Name.Builtin")
        } else {
          lx.token("Name")
        }
      },
      flags="m",
    )
    s.rule(
      (
        #|[(){};:,\/\\\]\[]
      ),
      "Punctuation",
    )
    s.rule("~=|==|<<|>>|[-~+\\/*%=<>&^|.@]", "Operator")
    s.rule(
      "(\\d+\\.\\d*|\\d*\\.\\d+)(e[+-]?[0-9]+)?",
      "Literal.Number.Float",
      flags="i",
    )
    s.rule("\\d+e[+-]?[0-9]+", "Literal.Number.Float", flags="i")
    s.rule("\\d+L", "Literal.Number.Integer.Long")
    s.rule("\\d+", "Literal.Number.Integer")
    s.rule("'(?=(.*'))", "Literal.String.Single", next="chararray")
    s.rule("\"(?=(.*\"))", "Literal.String.Double", next="string")
    s.rule("'", "Operator")
  })
  lx.state("chararray", fn(s) {
    s.rule("[^']+", "Literal.String.Single")
    s.rule("''", "Literal.String.Escape")
    s.rule("'", "Literal.String.Single", next="#pop")
  })
  lx.state("string", fn(s) {
    s.rule("[^\"]+", "Literal.String.Double")
    s.rule("\"\"", "Literal.String.Escape")
    s.rule("\"", "Literal.String.Double", next="#pop")
  })
  lx
}
