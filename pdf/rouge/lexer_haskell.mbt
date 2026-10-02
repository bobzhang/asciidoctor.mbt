///|
/// Rouge's `Haskell` (lexers/haskell.rb).
pub fn haskell(options : Map[String, String]) -> Lexer {
  let lx = Lexer::new("haskell", options~)
  let reserved = words(
    (
      #|_ case class data default deriving do else if in infix infixl infixr
      #|instance let newtype of then type where
    ),
  )
  let ascii = words(
    (
      #|NUL SOH [SE]TX EOT ENQ ACK BEL BS HT LF VT FF CR S[OI] DLE
      #|DC[1-4] NAK SYN ETB CAN EM SUB ESC [FGRU]S SP DEL
    ),
  )
  lx.state("basic", fn(s) {
    s.rule("\\s+", "Text", flags="m")
    s.rule("{-#", "Comment.Preproc", next="comment_preproc")
    s.rule("{-", "Comment.Multiline", next="comment")
    s.rule("^--\\s+\\|.*?$", "Comment.Doc")
    // this is complicated in order to support custom symbols
    // like -->
    s.rule(
      (
        #|--(?![!#\$\%&*+.\/<=>?@\^\|_~]).*?$
      ),
      "Comment.Single",
    )
  })
  // nested commenting
  lx.state("comment", fn(s) {
    s.rule("-}", "Comment.Multiline", next="#pop")
    s.rule("{-", "Comment.Multiline", next="comment")
    s.rule("[^-{}]+", "Comment.Multiline")
    s.rule("[-{}]", "Comment.Multiline")
  })
  lx.state("comment_preproc", fn(s) {
    s.rule("-}", "Comment.Preproc", next="#pop")
    s.rule("{-", "Comment.Preproc", next="comment")
    s.rule("[^-{}]+", "Comment.Preproc")
    s.rule("[-{}]", "Comment.Preproc")
  })
  lx.state("root", fn(s) {
    s.mix_in("basic")
    s.rule("'(?=(?:.|\\\\\\S+)')", "Literal.String.Char", next="character")
    s.rule("\"", "Literal.String", next="string")
    s.rule("\\d+e[+-]?\\d+", "Literal.Number.Float", flags="i")
    s.rule("\\d+\\.\\d+(e[+-]?\\d+)?", "Literal.Number.Float", flags="i")
    s.rule("0o[0-7]+", "Literal.Number.Oct", flags="i")
    s.rule("0x[\\da-f]+", "Literal.Number.Hex", flags="i")
    s.rule("\\d+", "Literal.Number.Integer")
    s.call("[\\w']+", fn(lx, m) {
      let text = m.matched()
      if text == "import" {
        lx.token("Keyword.Reserved")
        lx.push("import")
      } else if text == "module" {
        lx.token("Keyword.Reserved")
        lx.push("module")
      } else if reserved.contains(text) {
        lx.token("Keyword.Reserved")
      } else if script_match("\\A'?[A-Z]", text) {
        lx.token("Keyword.Type")
      } else {
        lx.token("Name")
      }
    })
    // lambda operator
    s.rule(
      (
        #|\\(?![:!#\$\%&*+.\\/<=>?@^\|~-]+)
      ),
      "Name.Function",
    )
    // special operators
    s.rule(
      (
        #|(<-|::|->|=>|=)(?![:!#\$\%&*+.\\/<=>?@^\|~-]+)
      ),
      "Operator",
    )
    // constructor/type operators
    s.rule(
      (
        #|:[:!#\$\%&*+.\\/<=>?@^\|~-]*
      ),
      "Operator",
    )
    // other operators
    s.rule(
      (
        #|[:!#\$\%&*+.\\/<=>?@^\|~-]+
      ),
      "Operator",
    )
    s.rule("\\[\\s*\\]", "Keyword.Type")
    s.rule("\\(\\s*\\)", "Name.Builtin")
    // Quasiquotations
    s.call("(\\[)([_a-z][\\w']*)(\\|)", fn(lx, m) {
      lx.token("Operator", val=group_text(m, 1))
      lx.token("Name", val=group_text(m, 2))
      lx.token("Operator", val=group_text(m, 3))
      lx.push("quasiquotation")
    })
    s.rule("[\\[\\](),;`{}]", "Punctuation")
  })
  lx.state("import", fn(s) {
    s.rule("\\s+", "Text")
    s.rule("\"", "Literal.String", next="string")
    s.rule("\\bqualified\\b", "Keyword")
    // import X as Y
    s.call("([A-Z][\\w.]*)(\\s+)(as)(\\s+)([A-Z][a-zA-Z0-9_.]*)", fn(lx, _) {
      lx.groups(["Name.Namespace", "Text", "Keyword", "Text", "Name"])
      lx.pop()
    })
    // import X hiding (functions)
    s.call("([A-Z][\\w.]*)(\\s+)(hiding)(\\s+)(\\()", fn(lx, _) {
      lx.groups(["Name.Namespace", "Text", "Keyword", "Text", "Punctuation"])
      lx.goto("funclist")
    })
    // import X (functions)
    s.call("([A-Z][\\w.]*)(\\s+)(\\()", fn(lx, _) {
      lx.groups(["Name.Namespace", "Text", "Punctuation"])
      lx.goto("funclist")
    })
    s.rule("[\\w.]+", "Name.Namespace", next="#pop")
  })
  lx.state("module", fn(s) {
    s.rule("\\s+", "Text")
    // module Foo (functions)
    s.call("([A-Z][\\w.]*)(\\s+)(\\()", fn(lx, _) {
      lx.groups(["Name.Namespace", "Text", "Punctuation"])
      lx.push("funclist")
    })
    s.rule("\\bwhere\\b", "Keyword.Reserved", next="#pop")
    s.rule("[A-Z][a-zA-Z0-9_.]*", "Name.Namespace", next="#pop")
  })
  lx.state("funclist", fn(s) {
    s.mix_in("basic")
    s.rule("[A-Z]\\w*", "Keyword.Type")
    s.rule("(_[\\w\\']+|[a-z][\\w\\']*)", "Name.Function")
    s.rule(",", "Punctuation")
    s.rule(
      (
        #|[:!#\$\%&*+.\\\/<=>?@^\|~-]+
      ),
      "Operator",
    )
    s.rule("\\(", "Punctuation", next="funclist")
    s.rule("\\)", "Punctuation", next="#pop")
  })
  lx.state("character", fn(s) {
    s.call("\\\\", fn(lx, _) {
      lx.token("Literal.String.Escape")
      lx.goto("character_end")
      lx.push("escape")
    })
    s.call(".", fn(lx, _) {
      lx.token("Literal.String.Char")
      lx.goto("character_end")
    })
  })
  lx.state("character_end", fn(s) {
    s.rule("'", "Literal.String.Char", next="#pop")
    s.rule(".", "Error", next="#pop")
  })
  lx.state("quasiquotation", fn(s) {
    s.rule("\\|\\]", "Operator", next="#pop")
    s.rule("[^\\|]+", "Text", flags="m")
    s.rule("\\|", "Text")
  })
  lx.state("string", fn(s) {
    s.rule("\"", "Literal.String", next="#pop")
    s.rule("\\\\", "Literal.String.Escape", next="escape")
    s.rule("[^\\\\\"]+", "Literal.String")
  })
  lx.state("escape", fn(s) {
    s.rule("[abfnrtv\"'&\\\\]", "Literal.String.Escape", next="#pop")
    s.rule("\\^[\\]\\[A-Z@\\^_]", "Literal.String.Escape", next="#pop")
    s.rule(alt(ascii), "Literal.String.Escape", next="#pop")
    s.rule("o[0-7]+", "Literal.String.Escape", flags="i", next="#pop")
    s.rule("x[\\da-f]+", "Literal.String.Escape", flags="i", next="#pop")
    s.rule("\\d+", "Literal.String.Escape", next="#pop")
    s.rule("\\s+\\\\", "Literal.String.Escape", next="#pop")
  })
  lx
}
