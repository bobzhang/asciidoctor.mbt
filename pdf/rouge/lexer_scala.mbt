///|
/// Rouge's `Scala` (lexers/scala.rb).
pub fn scala(options : Map[String, String]) -> Lexer {
  let lx = Lexer::new("scala", options~)
  // As documented in the ENBF section of the scala specification
  // http://www.scala-lang.org/docu/files/ScalaReference.pdf
  let whitespace = rx("\\p{Space}")
  let letter = rx("[\\p{L}$_]")
  let upper = rx("[\\p{Lu}$_]")
  let digits = rx("[0-9]")
  let parens = rx("[(){}\\[\\]]")
  let delims = rx("[‘’\".;,]")
  // negative lookahead to filter out other classes
  let op = rx(
    "\n        (?!\{whitespace}|\{letter}|\{digits}|\{parens}|\{delims})\n        [\\u0020-\\u007F\\p{Sm}\\p{So}]\n      ",
    flags="x",
  )
  let idrest = "\{letter}(?:\{letter}|\{digits})*(?:(?<=_)\{op}+)?" // x
  let idrest_rx = rx(idrest, flags="x")
  let keywords = words(
    (
      #|abstract case catch def do else extends final finally for forSome
      #|if implicit lazy match new override private protected requires return
      #|sealed super this throw try val var while with yield
    ),
  )
  lx.state("root", fn(s) {
    s.call("(class|trait|object)(\\s+)", fn(lx, _) {
      lx.groups(["Keyword", "Text"])
      lx.push("class")
    })
    s.rule("'\{idrest_rx}(?!')", "Literal.String.Symbol")
    s.rule("[^\\S\\n]+", "Text")
    s.rule("//.*", "Comment.Single")
    s.rule("/\\*", "Comment.Multiline", next="comment")
    s.rule("@\{idrest_rx}", "Name.Decorator")
    s.call("(def)(\\s+)(\{idrest_rx}|\{op}+|`[^`]+`)(\\s*)", fn(lx, _) {
      lx.groups(["Keyword", "Text", "Name.Function", "Text"])
    })
    s.call("(val)(\\s+)(\{idrest_rx}|\{op}+|`[^`]+`)(\\s*)", fn(lx, _) {
      lx.groups(["Keyword", "Text", "Name.Variable", "Text"])
    })
    s.call("(this)(\\n*)(\\.)(\{idrest_rx})", fn(lx, _) {
      lx.groups(["Keyword", "Text", "Operator", "Name.Property"])
    })
    s.call("(\{idrest_rx}|_)(\\n*)(\\.)(\{idrest_rx})", fn(lx, _) {
      lx.groups(["Name.Variable", "Text", "Operator", "Name.Property"])
    })
    s.rule("\{upper}\{idrest_rx}\\b", "Name.Class")
    s.call("(\{idrest_rx})(\{whitespace}*)(\\()", fn(lx, _) {
      lx.groups(["Name.Function", "Text", "Operator"])
    })
    s.call("(\\.)(\{idrest_rx})", fn(lx, _) {
      lx.groups(["Operator", "Name.Property"])
    })
    s.rule(
      "\n          (\{alt(keywords)})\\b|\n          (<[%:-]|=>|>:|[#=@_\\u21D2\\u2190])(\\b|(?=\\s)|$)\n        ",
      "Keyword",
      flags="x",
    )
    s.rule(":(?!\{op})", "Keyword", next="type")
    s.rule("(true|false|null)\\b", "Keyword.Constant")
    s.call("(import|package)(\\s+)", fn(lx, _) {
      lx.groups(["Keyword", "Text"])
      lx.push("import")
    })
    s.call("(type)(\\s+)", fn(lx, _) {
      lx.groups(["Keyword", "Text"])
      lx.push("type")
    })
    s.rule("\"\"\".*?\"\"\"(?!\")", "Literal.String", flags="m")
    s.rule("\"(\\\\\\\\|\\\\\"|[^\"])*\"", "Literal.String")
    s.rule("'\\\\.'|'[^\\\\]'|'\\\\u[0-9a-fA-F]{4}'", "Literal.String.Char")
    s.rule(idrest, "Name", flags="x")
    s.rule("`[^`]+`", "Name")
    s.rule("\\[", "Operator", next="typeparam")
    s.rule("[\\(\\)\\{\\};,.#]", "Operator")
    s.rule("\{op}+", "Operator")
    s.rule(
      "([0-9][0-9]*\\.[0-9]*|\\.[0-9]+)([eE][+-]?[0-9]+)?[fFdD]?", "Literal.Number.Float",
    )
    s.rule("([0-9][0-9]*[fFdD])", "Literal.Number.Float")
    s.rule("0x[0-9a-fA-F]+", "Literal.Number.Hex")
    s.rule("[0-9]+L?", "Literal.Number.Integer")
    s.rule("\\n", "Text")
  })
  lx.state("class", fn(s) {
    s.call("(\{idrest_rx}|\{op}+|`[^`]+`)(\\s*)(\\[)", fn(lx, _) {
      lx.groups(["Name.Class", "Text", "Operator"])
      lx.push("typeparam")
    })
    s.rule("\\s+", "Text")
    s.rule("{", "Operator", next="#pop")
    s.rule("\\(", "Operator", next="#pop")
    s.rule("//.*", "Comment.Single", next="#pop")
    s.rule("\{idrest_rx}|\{op}+|`[^`]+`", "Name.Class", next="#pop")
  })
  lx.state("type", fn(s) {
    s.rule("\\s+", "Text")
    s.rule("<[%:]|>:|[#_\\u21D2]|forSome|type", "Keyword")
    s.call("([,\\);}]|=>|=)(\\s*)", fn(lx, _) {
      lx.groups(["Operator", "Text"])
      lx.pop()
    })
    s.rule("[\\(\\{]", "Operator", next="type")
    let typechunk = rx("(?:\{idrest_rx}|\{op}+\\`[^`]+`)")
    s.call("(\{typechunk}(?:\\.\{typechunk})*)(\\s*)(\\[)", fn(lx, _) {
      lx.groups(["Keyword.Type", "Text", "Operator"])
      lx.pop()
      lx.push("typeparam")
    })
    s.call("(\{typechunk}(?:\\.\{typechunk})*)(\\s*)$", fn(lx, _) {
      lx.groups(["Keyword.Type", "Text"])
      lx.pop()
    })
    s.rule("//.*", "Comment.Single", next="#pop")
    s.rule("\\.|\{idrest_rx}|\{op}+|`[^`]+`", "Keyword.Type")
  })
  lx.state("typeparam", fn(s) {
    s.rule("[\\s,]+", "Text")
    s.rule("<[%:]|=>|>:|[#_\\u21D2]|forSome|type", "Keyword")
    s.rule("([\\]\\)\\}])", "Operator", next="#pop")
    s.rule("[\\(\\[\\{]", "Operator", next="typeparam")
    s.rule("\\.|\{idrest_rx}|\{op}+|`[^`]+`", "Keyword.Type")
  })
  lx.state("comment", fn(s) {
    s.rule("[^/\\*]+", "Comment.Multiline")
    s.rule("/\\*", "Comment.Multiline", next="comment")
    s.rule("\\*/", "Comment.Multiline", next="#pop")
    s.rule("[*/]", "Comment.Multiline")
  })
  lx.state("import", fn(s) {
    s.rule("(\{idrest_rx}|\\.)+", "Name.Namespace", next="#pop")
  })
  lx
}
