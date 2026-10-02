///|
/// Rouge's `Elixir` (lexers/elixir.rb).
pub fn elixir(options : Map[String, String]) -> Lexer {
  let lx = Lexer::new("elixir", options~)
  lx.state("root", fn(s) {
    s.rule("\\s+", "Text", flags="m")
    s.rule("#.*$", "Comment.Single")
    s.rule(
      (
        #|\b(case|cond|end|bc|lc|if|unless|try|loop|receive|fn|defmodule|
        #|             defp?|defprotocol|defimpl|defrecord|defmacrop?|defdelegate|
        #|             defexception|defguardp?|defstruct|exit|raise|throw|after|rescue|catch|else)\b(?![?!])|
        #|             (?<!\.)\b(do|\-\>)\b
      ),
      "Keyword",
      flags="x",
    )
    s.rule(
      "\\b(import|require|use|recur|quote|unquote|super|refer)\\b(?![?!])", "Keyword.Namespace",
    )
    s.rule("(?<!\\.)\\b(and|not|or|when|xor|in)\\b", "Operator.Word")
    s.rule(
      (
        #|%=|\*=|\*\*=|\+=|\-=|\^=|\|\|=|
        #|             <=>|<(?!<|=)|>(?!<|=|>)|<=|>=|===|==|=~|!=|!~|(?=[\s])\?|
        #|             (?<=[\s])!+|&(&&?|(?!\d))|\|\||\^|\*|\+|\-|/|
        #|             \||\+\+|\-\-|\*\*|\/\/|\<\-|\<\>|<<|>>|=|\.|~~~
      ),
      "Operator",
      flags="x",
    )
    // (not an x-mode pattern: the line breaks and indents are in it)
    s.rule(
      (
        #|(?<!:)(:)([a-zA-Z_]\w*([?!]|=(?![>=]))?|\<\>|===?|>=?|<=?|
        #|             <=>|&&?|%\(\)|%\[\]|%\{\}|\+\+?|\-\-?|\|\|?|\!|//|[%&`/\|]|
        #|             \*\*?|=?~|<\-)|([a-zA-Z_]\w*([?!])?)(:)(?!:)
      ),
      "Literal.String.Symbol",
    )
    s.rule(":\"", "Literal.String.Symbol", next="interpoling_symbol")
    s.rule("\\b(nil|true|false)\\b(?![?!])|\\b[A-Z]\\w*\\b", "Name.Constant")
    s.rule(
      "\\b(__(FILE|LINE|MODULE|MAIN|FUNCTION)__)\\b(?![?!])", "Name.Builtin.Pseudo",
    )
    s.rule("[a-zA-Z_!]\\w*[!\\?]?", "Name")
    s.rule(
      (
        #|::|[%(){};,/\|:\\\[\]]
      ),
      "Punctuation",
    )
    s.rule("@[a-zA-Z_]\\w*|&\\d", "Name.Variable")
    s.rule(
      "\\b\\d(_?\\d)*(\\.(?![^\\d\\s])(_?\\d)+)([eE][-+]?\\d(_?\\d)*)?\\b", "Literal.Number.Float",
    )
    s.rule("\\b0x[0-9A-Fa-f](_?[0-9A-Fa-f])*\\b", "Literal.Number.Hex")
    s.rule("\\b0o[0-7](_?[0-7])*\\b", "Literal.Number.Oct")
    s.rule("\\b0b[01](_?[01])*\\b", "Literal.Number.Bin")
    s.rule("\\b\\d(_?\\d)*\\b", "Literal.Number.Integer")
    s.mix_in("strings")
    s.mix_in("sigil_strings")
  })
  lx.state("strings", fn(s) {
    s.rule("(%[A-Ba-z])?\"\"\"(?:.|\\n)*?\"\"\"", "Literal.String.Doc")
    s.rule("'''(?:.|\\n)*?'''", "Literal.String.Doc")
    s.rule("\"", "Literal.String.Double", next="dqs")
    s.rule("'", "Literal.String.Single", next="sqs")
    s.rule(
      (
        #|(?<!\w)\?(\\(x\d{1,2}|\h{1,2}(?!\h)\b|0[0-7]{0,2}(?![0-7])\b[^x0MC])|(\\[MC]-)+\w|[^\s\\])
      ),
      "Literal.String.Other",
    )
  })
  lx.state("dqs", fn(s) {
    s.mix_in("escapes")
    s.mix_in("interpoling")
    s.rule("[^#\"\\\\]+", "Literal.String.Double")
    s.rule("\"", "Literal.String.Double", next="#pop")
    s.rule("[#\\\\]", "Literal.String.Double")
  })
  lx.state("sqs", fn(s) {
    s.mix_in("escapes")
    s.mix_in("interpoling")
    s.rule("[^#'\\\\]+", "Literal.String.Single")
    s.rule("'", "Literal.String.Single", next="#pop")
    s.rule("[#\\\\]", "Literal.String.Single")
  })
  lx.state("interpoling", fn(s) {
    s.rule("#\\{", "Literal.String.Interpol", next="interpoling_string")
  })
  lx.state("interpoling_string", fn(s) {
    s.rule("\\}", "Literal.String.Interpol", next="#pop")
    s.mix_in("root")
  })
  lx.state("escapes", fn(s) {
    s.rule("\\\\x\\h{2}", "Literal.String.Escape")
    s.rule("\\\\u\\{?\\d+\\}?", "Literal.String.Escape")
    s.rule("\\\\[\\\\abdefnrstv0\"']", "Literal.String.Escape")
  })
  lx.state("interpoling_symbol", fn(s) {
    s.rule("\"", "Literal.String.Symbol", next="#pop")
    s.mix_in("interpoling")
    s.rule("[^#\"]+", "Literal.String.Symbol")
  })
  lx.state("sigil_strings", fn(s) {
    // ~-sigiled strings
    // ~(abc), ~[abc], ~<abc>, ~|abc|, ~r/abc/, etc
    // Cribbed and adjusted from Ruby lexer
    // Match a-z for custom sigils too (Regexp.union of the delimiters)
    let sigil_opens = rx(
      (
        #|\{|\[|\(|<|\||\/|'|"
      ),
    )
    s.call("~([A-Za-z])?(\{sigil_opens})", fn(lx, m) {
      let delim = group_text(m, 2)
      let open = rx_escape(delim)
      let close = rx_escape(
        match delim {
          "{" => "}"
          "[" => "]"
          "(" => ")"
          "<" => ">"
          d => d
        },
      )
      let sigil = m.group(1)
      let interp = sigil is Some("S" | "R" | "C" | "W")
      let mut toktype = "Literal.String.Other"
      // regexes (Rouge's `'Rr'.include? m[1]` raises on a sigil without a
      // letter; it is false here)
      if sigil is Some("R" | "r") {
        toktype = "Literal.String.Regex"
        lx.push("regex_flags")
      }
      if sigil is Some("W" | "w") {
        lx.push("list_flags")
      }
      lx.token(toktype)
      let toktype = toktype
      lx.push_rules(fn(s) {
        s.rule(close, toktype, next="#pop")
        if interp {
          s.mix_in("interpoling")
          s.rule("#", toktype)
        } else {
          s.rule("[\\\\#]", toktype)
        }
        let uniq_chars = squeeze(open + close)
        s.rule("[^#\{uniq_chars}\\\\]+", toktype, flags="m")
      })
    })
  })
  lx.state("regex_flags", fn(s) {
    s.rule("[fgimrsux]*", "Literal.String.Regex", next="#pop")
  })
  lx.state("list_flags", fn(s) {
    s.rule("[csa]?", "Literal.String.Other", next="#pop")
  })
  lx
}
