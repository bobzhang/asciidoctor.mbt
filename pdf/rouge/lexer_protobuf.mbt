///|
/// Rouge's `Protobuf` (lexers/protobuf.rb).
pub fn protobuf(options : Map[String, String]) -> Lexer {
  let lx = Lexer::new("protobuf", options~)
  let kw = "\\b(ctype|default|extensions|import|max|oneof|option|optional|packed|repeated|required|returns|rpc|to)\\b"
  let datatype = "\\b(bool|bytes|double|fixed32|fixed64|float|int32|int64|sfixed32|sfixed64|sint32|sint64|string|uint32|uint64)\\b"
  lx.state("root", fn(s) {
    s.rule("[\\s]+", "Text")
    s.rule("[,;{}\\[\\]()]", "Punctuation")
    s.rule("\\/(\\\\\\n)?\\/($|(.|\\n)*?[^\\\\]$)", "Comment.Single")
    s.rule("\\/(\\\\\\n)?\\*(.|\\n)*?\\*(\\\\\\n)?\\/", "Comment.Multiline")
    s.rule(kw, "Keyword")
    s.rule(datatype, "Keyword.Type")
    s.rule("true|false", "Keyword.Constant")
    s.call("(package)(\\s+)", fn(lx, _) {
      lx.groups(["Keyword.Namespace", "Text"])
      lx.push("package")
    })
    s.call("(message|extend)(\\s+)", fn(lx, _) {
      lx.groups(["Keyword.Declaration", "Text"])
      lx.push("message")
    })
    s.call("(enum|group|service)(\\s+)", fn(lx, _) {
      lx.groups(["Keyword.Declaration", "Text"])
      lx.push("type")
    })
    s.rule("\".*?\"", "Literal.String")
    s.rule("'.*?'", "Literal.String")
    s.rule(
      "(\\d+\\.\\d*|\\.\\d+|\\d+)[eE][+-]?\\d+[LlUu]*", "Literal.Number.Float",
    )
    s.rule("(\\d+\\.\\d*|\\.\\d+|\\d+[fF])[fF]?", "Literal.Number.Float")
    s.rule("(\\-?(inf|nan))\\b", "Literal.Number.Float")
    s.rule("0x[0-9a-fA-F]+[LlUu]*", "Literal.Number.Hex")
    s.rule("0[0-7]+[LlUu]*", "Literal.Number.Oct")
    s.rule("\\d+[LlUu]*", "Literal.Number.Integer")
    s.rule("[+-=]", "Operator")
    s.call("([a-zA-Z_][\\w.]*)([ \\t]*)(=)", fn(lx, _) {
      lx.groups(["Name.Attribute", "Text", "Operator"])
    })
    s.rule("[a-zA-Z_][\\w.]*", "Name")
  })
  for
    spec in [
      ("package", "Name.Namespace"),
      ("message", "Name.Class"),
      ("type", "Name"),
    ] {
    let (name, tok) = spec
    lx.state(name, fn(s) {
      s.rule("[a-zA-Z_]\\w*", tok, next="#pop")
      s.call("", fn(lx, _) { lx.pop() })
    })
  }
  lx
}
