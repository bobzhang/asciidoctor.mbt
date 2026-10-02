///|
/// Rouge's `Dart` (lexers/dart.rb).
pub fn dart(options : Map[String, String]) -> Lexer {
  let lx = Lexer::new("dart", options~)
  let keywords = words(
    (
      #|as assert await break case catch continue default do else finally for
      #|if in is new rethrow return super switch this throw try while with yield
    ),
  )
  let declarations = words(
    (
      #|abstract async dynamic const covariant external extends factory final get
      #|implements late native on operator required set static sync typedef var
    ),
  )
  let types = words(
    "bool Comparable double Dynamic enum Function int List Map Never Null num Object Pattern Set String Symbol Type Uri void",
  )
  let imports = words("import deferred export library part\\s*of part source")
  let id = rx("[a-zA-Z_]\\w*")
  lx.state("root", fn(s) {
    s.call(
      (
        #|^
        #|          (\s*(?:[a-zA-Z_][a-zA-Z\d_.\[\]]*\s+)+?) # return arguments
        #|          ([a-zA-Z_]\w*)                           # method name
        #|          (\s*)(\()                                # signature start
        #|
      ),
      fn(lx, m) {
        // TODO: do this better, this shouldn't need a delegation
        lx.delegate_new(fn() { dart(Map([])) }, text=group_text(m, 1))
        lx.token("Name.Function", val=group_text(m, 2))
        lx.token("Text", val=group_text(m, 3))
        lx.token("Punctuation", val=group_text(m, 4))
      },
      flags="mx",
    )
    s.rule("\\s+", "Text")
    s.rule("//.*?$", "Comment.Single")
    s.rule("/\\*.*?\\*/", "Comment.Multiline", flags="m")
    s.rule("\"", "Literal.String", next="dqs")
    s.rule("'", "Literal.String", next="sqs")
    s.rule("r\"[^\"]*\"", "Literal.String.Other")
    s.rule("r'[^']*'", "Literal.String.Other")
    s.rule("#\{id}*", "Literal.String.Symbol", flags="i")
    s.rule("@\{id}", "Name.Decorator")
    s.rule("(?:\{alt(keywords)})\\b", "Keyword")
    s.rule("(?:\{alt(declarations)})\\b", "Keyword.Declaration")
    s.rule("(?:\{alt(types)})\\b", "Keyword.Type")
    s.rule("(?:true|false|null)\\b", "Keyword.Constant")
    s.rule("(?:class|interface|mixin)\\b", "Keyword.Declaration", next="class")
    s.rule("(?:\{alt(imports)})\\b", "Keyword.Namespace", next="import")
    s.call("(\\.)(\{id})", fn(lx, _) {
      lx.groups(["Operator", "Name.Attribute"])
    })
    s.rule("\{id}:", "Name.Label")
    s.rule("\\$?\{id}", "Name")
    s.rule("[~^*!%&\\|+=:\\/?-]", "Operator")
    s.rule("[\\[\\](){}<>\\.,;]", "Punctuation")
    s.rule("\\d*\\.\\d+([eE]\\-?\\d+)?", "Literal.Number.Float")
    s.rule("0x[\\da-fA-F]+", "Literal.Number.Hex")
    s.rule("\\d+L?", "Literal.Number.Integer")
    s.rule("\\n", "Text")
  })
  lx.state("class", fn(s) {
    s.rule("\\s+", "Text", flags="m")
    s.rule(id, "Name.Class", next="#pop")
  })
  lx.state("dqs", fn(s) {
    s.rule("\"", "Literal.String", next="#pop")
    s.rule("[^\\\\\\$\"]+", "Literal.String")
    s.mix_in("string")
  })
  lx.state("sqs", fn(s) {
    s.rule("'", "Literal.String", next="#pop")
    s.rule("[^\\\\\\$']+", "Literal.String")
    s.mix_in("string")
  })
  lx.state("import", fn(s) {
    s.rule(";", "Operator", next="#pop")
    s.rule("(?:show|hide)\\b", "Keyword.Declaration")
    s.mix_in("root")
  })
  lx.state("string", fn(s) {
    s.mix_in("interpolation")
    s.rule("\\\\[nrt\\\"\\'\\\\]", "Literal.String.Escape")
  })
  lx.state("interpolation", fn(s) {
    s.rule("\\$\{id}", "Literal.String.Interpol")
    s.rule("\\$\\{[^\\}]+\\}", "Literal.String.Interpol")
  })
  lx
}
