///|
/// Rouge's `D` (lexers/d.rb).
pub fn d(options : Map[String, String]) -> Lexer {
  let lx = Lexer::new("d", options~)
  let keywords = words(
    (
      #|abstract alias align asm assert auto body
      #|break case cast catch class const continue
      #|debug default delegate delete deprecated do else
      #|enum export extern finally final foreach_reverse
      #|foreach for function goto if immutable import
      #|interface invariant inout in is lazy mixin
      #|module new nothrow out override package pragma
      #|private protected public pure ref return scope
      #|shared static struct super switch synchronized
      #|template this throw try typedef typeid typeof
      #|union unittest version volatile while with
      #|__gshared __traits __vector __parameters
    ),
  )
  let keywords_type = words(
    (
      #|bool byte cdouble cent cfloat char creal
      #|dchar double float idouble ifloat int ireal
      #|long real short ubyte ucent uint ulong
      #|ushort void wchar
    ),
  )
  let keywords_pseudo = words(
    (
      #|__FILE__ __FILE_FULL_PATH__ __MODULE__ __LINE__ __FUNCTION__
      #|__PRETTY_FUNCTION__ __DATE__ __EOF__ __TIME__ __TIMESTAMP__
      #|__VENDOR__ __VERSION__
    ),
  )
  lx.state("whitespace", fn(s) {
    s.rule("\\n", "Text", flags="m")
    s.rule("\\s+", "Text", flags="m")
  })
  lx.state("root", fn(s) {
    s.mix_in("whitespace")
    // Comments
    s.rule("//.*", "Comment.Single")
    s.rule("/(\\\\\\n)?[*](.|\\n)*?[*](\\\\\\n)?/", "Comment.Multiline")
    s.rule("/\\+", "Comment.Multiline", next="nested_comment")
    // Keywords
    s.rule("(\{alt(keywords)})\\b", "Keyword")
    s.rule("(\{alt(keywords_type)})\\b", "Keyword.Type")
    s.rule("(false|true|null)\\b", "Keyword.Constant")
    s.rule("(\{alt(keywords_pseudo)})\\b", "Keyword.Pseudo")
    s.rule("macro\\b", "Keyword.Reserved")
    s.rule("(string|wstring|dstring|size_t|ptrdiff_t)\\b", "Name.Builtin")
    // Literals
    // HexFloat
    s.rule(
      "0[xX]([0-9a-fA-F_]*\\.[0-9a-fA-F_]+|[0-9a-fA-F_]+)[pP][+\\-]?[0-9_]+[fFL]?[i]?",
      "Literal.Number.Float",
    )
    // DecimalFloat
    s.rule(
      "[0-9_]+(\\.[0-9_]+[eE][+\\-]?[0-9_]+|\\.[0-9_]*|[eE][+\\-]?[0-9_]+)[fFL]?[i]?",
      "Literal.Number.Float",
    )
    s.rule(
      "\\.(0|[1-9][0-9_]*)([eE][+\\-]?[0-9_]+)?[fFL]?[i]?", "Literal.Number.Float",
    )
    // IntegerLiteral
    // Binary
    s.rule("0[Bb][01_]+", "Literal.Number.Bin")
    // Octal
    // TODO: 0[0-7] isn't supported use octal![0-7] instead
    s.rule("0[0-7_]+", "Literal.Number.Oct")
    // Hexadecimal
    s.rule("0[xX][0-9a-fA-F_]+", "Literal.Number.Hex")
    // Decimal
    s.rule("(0|[1-9][0-9_]*)([LUu]|Lu|LU|uL|UL)?", "Literal.Number.Integer")
    // CharacterLiteral
    s.rule(
      "'(\\\\['\"?\\\\abfnrtv]|\\\\x[0-9a-fA-F]{2}|\\\\[0-7]{1,3}|\\\\u[0-9a-fA-F]{4}|\\\\U[0-9a-fA-F]{8}|\\\\&\\w+;|.)'",
      "Literal.String.Char",
    )
    // StringLiteral
    // WysiwygString
    s.rule("r\"[^\"]*\"[cwd]?", "Literal.String")
    // Alternate WysiwygString
    s.rule("`[^`]*`[cwd]?", "Literal.String")
    // DoubleQuotedString
    s.rule("\"(\\\\\\\\|\\\\\"|[^\"])*\"[cwd]?", "Literal.String")
    // EscapeSequence
    s.rule(
      "\\\\(['\\\"?\\\\abfnrtv]|x[0-9a-fA-F]{2}|[0-7]{1,3}|u[0-9a-fA-F]{4}|U[0-9a-fA-F]{8}|&\\w+;)",
      "Literal.String",
    )
    // HexString
    s.rule("x\"[0-9a-fA-F_\\s]*\"[cwd]?", "Literal.String")
    // DelimitedString
    s.rule("q\"\\[", "Literal.String", next="delimited_bracket")
    s.rule("q\"\\(", "Literal.String", next="delimited_parenthesis")
    s.rule("q\"<", "Literal.String", next="delimited_angle")
    s.rule("q\"\\{", "Literal.String", next="delimited_curly")
    s.rule("q\"([a-zA-Z_]\\w*)\\n.*?\\n\\1\"", "Literal.String")
    s.rule("q\"(.).*?\\1\"", "Literal.String")
    // TokenString
    s.rule("q\\{", "Literal.String", next="token_string")
    // Attributes
    s.rule("@([a-zA-Z_]\\w*)?", "Name.Decorator")
    // Tokens
    s.rule(
      "(~=|\\^=|%=|\\*=|==|!>=|!<=|!<>=|!<>|!<|!>|!=|>>>=|>>>|>>=|>>|>=|<>=|<>|<<=|<<|<=|\\+\\+|\\+=|--|-=|\\|\\||\\|=|&&|&=|\\.\\.\\.|\\.\\.|/=)|[/.&|\\-+<>!()\\[\\]{}?,;:$=*%^~]",
      "Punctuation",
    )
    // Identifier
    s.rule("[a-zA-Z_]\\w*", "Name")
    // Line
    s.rule("#line\\s.*\\n", "Comment.Special")
  })
  lx.state("nested_comment", fn(s) {
    s.rule("[^+/]+", "Comment.Multiline")
    s.rule("/\\+", "Comment.Multiline", next="#push")
    s.rule("\\+/", "Comment.Multiline", next="#pop")
    s.rule("[+/]", "Comment.Multiline")
  })
  lx.state("token_string", fn(s) {
    s.rule("\\{", "Punctuation", next="token_string_nest")
    s.rule("\\}", "Literal.String", next="#pop")
    s.mix_in("root")
  })
  lx.state("token_string_nest", fn(s) {
    s.rule("\\{", "Punctuation", next="#push")
    s.rule("\\}", "Punctuation", next="#pop")
    s.mix_in("root")
  })
  for
    spec in [
      ("bracket", "\\[", "\\]"),
      ("parenthesis", "\\(", "\\)"),
      ("angle", "<", ">"),
      ("curly", "\\{", "\\}"),
    ] {
    let (name, open, close) = spec
    let not_delims = match name {
      "bracket" => "[^\\[\\]]+"
      "parenthesis" => "[^()]+"
      "angle" => "[^<>]+"
      _ => "[^{}]+"
    }
    lx.state("delimited_" + name, fn(s) {
      s.rule(not_delims, "Literal.String")
      s.rule(open, "Literal.String", next="delimited_inside_" + name)
      s.rule(close + "\"", "Literal.String", next="#pop")
    })
    lx.state("delimited_inside_" + name, fn(s) {
      s.rule(not_delims, "Literal.String")
      s.rule(open, "Literal.String", next="#push")
      s.rule(close, "Literal.String", next="#pop")
    })
  }
  lx
}
