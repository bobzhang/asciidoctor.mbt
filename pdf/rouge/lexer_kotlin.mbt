///|
/// Rouge's `Kotlin` (lexers/kotlin.rb).
pub fn kotlin(options : Map[String, String]) -> Lexer {
  let lx = Lexer::new("kotlin", options~)
  let keywords = words(
    (
      #|abstract annotation as break by catch class companion const
      #|constructor continue crossinline do dynamic else enum
      #|external false final finally for fun get if import in infix
      #|inline inner interface internal is lateinit noinline null
      #|object open operator out override package private protected
      #|public reified return sealed set super suspend tailrec this
      #|throw true try typealias typeof val var vararg when where
      #|while yield
    ),
  )
  let name_chars = rx(
    "[-_\\p{Lu}\\p{Ll}\\p{Lt}\\p{Lm}\\p{Nl}\\p{Nd}\\p{Pc}\\p{Cf}\\p{Mn}\\p{Mc}]*",
  )
  let class_name = rx("`?[\\p{Lu}]\{name_chars}`?")
  let name = rx("`?[_\\p{Lu}\\p{Ll}\\p{Lt}\\p{Lm}\\p{Nl}]\{name_chars}`?")
  lx.state("root", fn(s) {
    s.call("\\b(companion)(\\s+)(object)\\b", fn(lx, _) {
      lx.groups(["Keyword", "Text", "Keyword"])
    })
    s.call("\\b(class|data\\s+class|interface|object)(\\s+)", fn(lx, _) {
      lx.groups(["Keyword.Declaration", "Text"])
      lx.push("class")
    })
    s.call("\\b(fun)(\\s+)", fn(lx, _) {
      lx.groups(["Keyword", "Text"])
      lx.push("function")
    })
    s.call("\\b(package|import)(\\s+)", fn(lx, _) {
      lx.groups(["Keyword", "Text"])
      lx.push("package")
    })
    s.call("\\b(val|var)(\\s+)(\\()", fn(lx, _) {
      lx.groups(["Keyword.Declaration", "Text", "Punctuation"])
      lx.push("destructure")
    })
    s.call("\\b(val|var)(\\s+)", fn(lx, _) {
      lx.groups(["Keyword.Declaration", "Text"])
      lx.push("property")
    })
    s.call("(return|continue|break|this|super)(@\{name})?\\b", fn(lx, _) {
      lx.groups(["Keyword", "Name.Decorator"])
    })
    s.rule("\\bfun\\b", "Keyword")
    s.rule("\\b(?:\{alt(keywords)})\\b", "Keyword")
    s.rule("^\\s*\\[.*?\\]", "Name.Attribute")
    s.rule("[^\\S\\n]+", "Text")
    s.rule("\\\\\\n", "Text") // line continuation
    s.rule("//.*?$", "Comment.Single")
    s.rule("/[*].*[*]/", "Comment.Multiline") // single line block comment
    s.rule("/[*].*", "Comment.Multiline", next="comment") // multiline block comment
    s.rule("\\n", "Text")
    s.call("(::)(class)", fn(lx, _) { lx.groups(["Operator", "Keyword"]) })
    s.rule("::|!!|\\?[:.]", "Operator")
    s.rule("(\\.\\.)", "Operator")
    // Number literals
    let dec_digits = rx("([0-9][0-9_]*[0-9])|[0-9]")
    let exponent = rx("[eE][+-]?(\{dec_digits})")
    let double = rx(
      "((\{dec_digits})?\\.\{dec_digits}(\{exponent})?)|(\{dec_digits}\{exponent})",
    )
    s.rule("(\{double}[fF]?)|(\{dec_digits}[fF])", "Literal.Number.Float")
    s.rule("0[bB]([01][01_]*[01]|[01])[uU]?L?", "Literal.Number.Bin")
    s.rule(
      "0[xX]([0-9a-fA-F][0-9a-fA-F_]*[0-9a-fA-F]|[0-9a-fA-F])[uU]?L?", "Literal.Number.Hex",
    )
    s.rule("(([1-9][0-9_]*[0-9])|[0-9])[uU]?L?", "Literal.Number.Integer")
    s.rule("[~!%^&*()+=|\\[\\]:;,.<>/?-]", "Punctuation")
    s.rule("[{}]", "Punctuation")
    s.rule("@\"(\"\"|[^\"])*\"", "Literal.String", flags="m")
    s.rule("\"\"\".*?\"\"\"", "Literal.String", flags="m")
    s.rule("\"(\\\\\\\\|\\\\\"|[^\"\\n])*[\"\\n]", "Literal.String", flags="m")
    s.rule("'\\\\.'|'[^\\\\]'", "Literal.String.Char")
    s.rule("(@\{class_name})", "Name.Decorator")
    s.call("(\{class_name})(<)", fn(lx, _) {
      lx.groups(["Name.Class", "Punctuation"])
      lx.push("generic_parameters")
    })
    s.rule(class_name, "Name.Class")
    s.rule("(\{name})(?=\\s*[({])", "Name.Function")
    s.rule("(\{name})@", "Name.Decorator") // label
    s.rule(name, "Name")
  })
  lx.state("package", fn(s) { s.rule("\\S+", "Name.Namespace", next="#pop") })
  lx.state("class", fn(s) { s.rule(class_name, "Name.Class", next="#pop") })
  lx.state("function", fn(s) {
    s.rule("(<)", "Punctuation", next="generic_parameters")
    s.rule("(\\s+)", "Text")
    s.call("(\{class_name})(\\.)", fn(lx, _) {
      lx.groups(["Name.Class", "Punctuation"])
    })
    s.rule(name, "Name.Function", next="#pop")
  })
  lx.state("generic_parameters", fn(s) {
    s.rule(class_name, "Name.Class")
    s.rule("(<)", "Punctuation", next="generic_parameters")
    s.rule("(reified|out|in)", "Keyword")
    s.rule("([,:.?])", "Punctuation")
    s.rule("(\\s+)", "Text")
    s.rule("(>)", "Punctuation", next="#pop")
  })
  lx.state("property", fn(s) {
    s.rule("(<)", "Punctuation", next="generic_parameters")
    s.rule("(\\s+)", "Text")
    s.rule(name, "Name.Property", next="#pop")
  })
  lx.state("destructure", fn(s) {
    s.rule("(,)", "Punctuation")
    s.rule("(\\))", "Punctuation", next="#pop")
    s.rule("(\\s+)", "Text")
    s.rule(name, "Name.Property")
  })
  lx.state("comment", fn(s) {
    s.rule("/[*]", "Comment.Multiline", next="comment")
    s.rule("[*]/", "Comment.Multiline", next="#pop")
    s.rule("[^/*]+", "Comment.Multiline")
    s.rule("[/*]", "Comment.Multiline")
  })
  lx
}
