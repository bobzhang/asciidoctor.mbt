///|
let coffee_keywords : Set[String] = word_set(
  (
    #|for by while until loop break continue return
    #|switch when then if else do yield throw try catch finally await
    #|new delete typeof instanceof super extends this class
    #|import export debugger
  ),
)

///|
let coffee_constants : Set[String] = word_set(
  "true false yes no on off null NaN Infinity undefined",
)

///|
let coffee_builtins : Set[String] = word_set(
  (
    #|Array Boolean Date Error Function Math netscape Number Object
    #|Packages RegExp String sun decodeURI decodeURIComponent
    #|encodeURI encodeURIComponent eval isFinite isNaN parseFloat
    #|parseInt document window
  ),
)

///|
/// Rouge's `Coffeescript` (lexers/coffeescript.rb).
pub fn coffeescript(options : Map[String, String]) -> Lexer {
  let lx = Lexer::new("coffeescript", options~)
  let id_src = "[$a-zA-Z_][a-zA-Z0-9_]*"
  let id = rx(id_src)
  lx.state("comments", fn(s) {
    s.rule("###[^#].*?###", "Comment.Multiline", flags="m")
    s.rule("#.*$", "Comment.Single")
  })
  lx.state("whitespace", fn(s) { s.rule("\\s+", "Text", flags="m") })
  lx.state("regex_comment", fn(s) {
    s.rule("^#(?!\\{).*$", "Comment.Single")
    s.call("(\\s+)(#(?!\\{).*)$", fn(lx, _) {
      lx.groups(["Text", "Comment.Single"])
    })
  })
  lx.state("multiline_regex_begin", fn(s) {
    s.call("///", fn(lx, _) {
      lx.token("Literal.String.Regex")
      lx.goto("multiline_regex")
    })
  })
  lx.state("multiline_regex_end", fn(s) {
    s.rule("///([gimy]+\\b|\\B)", "Literal.String.Regex", next="#pop")
  })
  lx.state("multiline_regex", fn(s) {
    s.mix_in("multiline_regex_end")
    s.mix_in("regex_comment")
    s.mix_in("has_interpolation")
    s.mix_in("comments")
    s.mix_in("whitespace")
    s.mix_in("code_escape")
    s.rule("\\\\\\D", "Literal.String.Escape")
    s.rule("\\\\\\d+", "Name.Variable")
    s.rule(".", "Literal.String.Regex", flags="m")
  })
  lx.state("slash_starts_regex", fn(s) {
    s.mix_in("comments")
    s.mix_in("whitespace")
    s.mix_in("multiline_regex_begin")
    s.rule(
      (
        #|
        #|          /(\\.|[^\[/\\\n]|\[(\\.|[^\]\\\n])*\])+/ # a regex
        #|          ([gimy]+\b|\B)
        #|
      ),
      "Literal.String.Regex",
      flags="x",
      next="#pop",
    )
    s.call("", fn(lx, _) { lx.pop() })
  })
  lx.state("root", fn(s) {
    s.call("^(?=\\s|/|<!--)", fn(lx, _) { lx.push("slash_starts_regex") })
    s.mix_in("comments")
    s.mix_in("whitespace")
    s.rule(
      (
        #|
        #|          [+][+]|--|~|&&|\band\b|\bor\b|\bis\b|\bisnt\b|\bnot\b|\bin\b|\bof\b|
        #|          [?]|:|=|[|][|]|\\(?=\n)|(<<|>>>?|==?|!=?|[-<>+*`%&|^/])=?
        #|
      ),
      "Operator",
      flags="x",
      next="slash_starts_regex",
    )
    s.rule("[-=]>", "Name.Function")
    s.call("(@)([ \\t]*)(\{id})", fn(lx, _) {
      lx.groups(["Name.Variable.Instance", "Text", "Name.Attribute"])
      lx.push("slash_starts_regex")
    })
    s.call("([.])([ \\t]*)(\{id})", fn(lx, _) {
      lx.groups(["Punctuation", "Text", "Name.Attribute"])
      lx.push("slash_starts_regex")
    })
    s.rule("\{id}(?=\\s*:)", "Name.Attribute", next="slash_starts_regex")
    s.call(id, fn(lx, m) {
      let word = m.matched()
      if coffee_keywords.contains(word) {
        lx.token("Keyword")
      } else if coffee_constants.contains(word) {
        lx.token("Name.Constant")
      } else if coffee_builtins.contains(word) {
        lx.token("Name.Builtin")
      } else {
        lx.token("Name.Other")
      }
      lx.push("slash_starts_regex")
    })
    s.rule("[{(\\[;,]", "Punctuation", next="slash_starts_regex")
    s.rule("[})\\].]", "Punctuation")
    s.rule("\\d+[.]\\d+([eE]\\d+)?[fd]?", "Literal.Number.Float")
    s.rule("0x[0-9a-fA-F]+", "Literal.Number.Hex")
    s.rule("\\d+", "Literal.Number.Integer")
    s.rule("\"\"\"", "Literal.String", next="tdqs")
    s.rule("'''", "Literal.String", next="tsqs")
    s.rule("\"", "Literal.String", next="dqs")
    s.rule("'", "Literal.String", next="sqs")
  })
  lx.state("code_escape", fn(s) {
    s.rule(
      (
        #|\\(
        #|          c[A-Z]|
        #|          x[0-9a-fA-F]{2}|
        #|          u[0-9a-fA-F]{4}|
        #|          u\{[0-9a-fA-F]{4}\}
        #|        )
      ),
      "Literal.String.Escape",
      flags="x",
    )
  })
  lx.state("strings", fn(s) {
    // all coffeescript strings are multi-line
    s.rule("[^#\\\\'\"]+", "Literal.String", flags="m")
    s.mix_in("code_escape")
    s.rule("\\\\.", "Literal.String.Escape")
    s.rule("#", "Literal.String")
  })
  lx.state("double_strings", fn(s) {
    s.rule("'", "Literal.String")
    s.mix_in("has_interpolation")
    s.mix_in("strings")
  })
  lx.state("single_strings", fn(s) {
    s.rule("\"", "Literal.String")
    s.mix_in("strings")
  })
  lx.state("interpolation", fn(s) {
    s.rule("}", "Literal.String.Interpol", next="#pop")
    s.mix_in("root")
  })
  lx.state("has_interpolation", fn(s) {
    s.rule("[#][{]", "Literal.String.Interpol", next="interpolation")
  })
  lx.state("dqs", fn(s) {
    s.rule("\"", "Literal.String", next="#pop")
    s.mix_in("double_strings")
  })
  lx.state("tdqs", fn(s) {
    s.rule("\"\"\"", "Literal.String", next="#pop")
    s.rule("\"", "Literal.String")
    s.mix_in("double_strings")
  })
  lx.state("sqs", fn(s) {
    s.rule("'", "Literal.String", next="#pop")
    s.mix_in("single_strings")
  })
  lx.state("tsqs", fn(s) {
    s.rule("'''", "Literal.String", next="#pop")
    s.rule("'", "Literal.String")
    s.mix_in("single_strings")
  })
  lx
}
