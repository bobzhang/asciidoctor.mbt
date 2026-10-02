///|
/// Rouge's `Java` (lexers/java.rb).
pub fn java(options : Map[String, String]) -> Lexer {
  let lx = Lexer::new("java", options~)
  lx.set_fresh(fn() { java(Map([])) })
  let keywords = words(
    "assert break case catch continue default do else finally for if goto instanceof new return switch this throw try while",
  )
  let declarations = words(
    "abstract const enum extends final implements native private protected public static strictfp super synchronized throws transient volatile",
  )
  let types = words("boolean byte char double float int long short var void")
  let id = rx("[[:alpha:]_][[:word:]]*")
  let const_name = rx("[[:upper:]][[:upper:][:digit:]_]*\\b")
  let class_name = rx("[[:upper:]][[:alnum:]]*\\b")
  lx.state("root", fn(s) {
    s.rule("[^\\S\\n]+", "Text")
    s.rule("//.*?$", "Comment.Single")
    s.rule("/\\*.*?\\*/", "Comment.Multiline", flags="m")
    // keywords: go before method names to avoid lexing "throw new XYZ" as a
    // method signature
    s.rule("(?:\{alt(keywords)})\\b", "Keyword")
    s.call(
      (
        #|
        #|          (\s*(?:[a-zA-Z_][a-zA-Z0-9_.\[\]<>]*\s+)+?) # return arguments
        #|          ([a-zA-Z_][a-zA-Z0-9_]*)                  # method name
        #|          (\s*)(\()                                 # signature start
        #|
      ),
      fn(lx, m) {
        lx.delegate_new(fn() { java(Map([])) }, text=group_text(m, 1))
        lx.token("Name.Function", val=group_text(m, 2))
        lx.token("Text", val=group_text(m, 3))
        lx.token("Operator", val=group_text(m, 4))
      },
      flags="mx",
    )
    s.rule("@\{id}", "Name.Decorator")
    s.rule("(?:\{alt(declarations)})\\b", "Keyword.Declaration")
    s.rule("(?:\{alt(types)})\\b", "Keyword.Type")
    s.rule("(?:true|false|null)\\b", "Keyword.Constant")
    s.rule("(?:class|interface)\\b", "Keyword.Declaration", next="class")
    s.rule("(?:import|package)\\b", "Keyword.Namespace", next="import")
    s.rule("\"(\\\\\\\\|\\\\\"|[^\"])*\"", "Literal.String")
    s.rule("'(?:\\\\.|[^\\\\]|\\\\u[0-9a-f]{4})'", "Literal.String.Char")
    s.call("(\\.)(\{id})", fn(lx, _) {
      lx.groups(["Operator", "Name.Attribute"])
    })
    s.rule("\{id}:", "Name.Label")
    s.rule(const_name, "Name.Constant")
    s.rule(class_name, "Name.Class")
    s.rule("\\$?\{id}", "Name")
    s.rule("[~^*!%&\\[\\](){}<>\\|+=:;,.\\/?-]", "Operator")
    let digit = rx("[0-9]_+[0-9]|[0-9]")
    let bin_digit = rx("[01]_+[01]|[01]")
    let oct_digit = rx("[0-7]_+[0-7]|[0-7]")
    let hex_digit = rx("[0-9a-f]_+[0-9a-f]|[0-9a-f]", flags="i")
    s.rule("\{digit}+\\.\{digit}+([eE]\{digit}+)?[fd]?", "Literal.Number.Float")
    s.rule("0b\{bin_digit}+", "Literal.Number.Bin", flags="i")
    s.rule("0x\{hex_digit}+", "Literal.Number.Hex", flags="i")
    s.rule("0\{oct_digit}+", "Literal.Number.Oct")
    s.rule("\{digit}+L?", "Literal.Number.Integer")
    s.rule("\\n", "Text")
  })
  lx.state("class", fn(s) {
    s.rule("\\s+", "Text", flags="m")
    s.rule(id, "Name.Class", next="#pop")
  })
  lx.state("import", fn(s) {
    s.rule("\\s+", "Text", flags="m")
    s.rule("[a-z0-9_.]+\\*?", "Name.Namespace", flags="i", next="#pop")
  })
  lx
}
