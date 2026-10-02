///|
/// Whether `s` matches the Ruby regex `pattern` somewhere (`s =~ re`).
fn rx_search(pattern : String, s : String, flags? : String = "") -> Bool {
  compile(pattern, flags).find(s) is Some(_)
}

///|
/// Rouge's `Swift` (lexers/swift.rb).
pub fn swift(options : Map[String, String]) -> Lexer {
  let lx = Lexer::new("swift", options~)
  let id_head = rx("_|(?!\\p{Mc})\\p{Alpha}|[^\\u0000-\\uFFFF]")
  let id_rest = rx("[\\p{Alnum}_]|[^\\u0000-\\uFFFF]")
  let id = rx("\{id_head}\{id_rest}*")
  let keywords = word_set(
    (
      #|await break case continue default do else fallthrough if in for return switch where while try catch throw guard defer repeat
      #|
      #|as dynamicType is new super self Self Type __COLUMN__ __FILE__ __FUNCTION__ __LINE__
      #|
      #|associativity async didSet get infix inout isolated mutating none nonmutating operator override postfix precedence prefix set unowned weak willSet throws rethrows precedencegroup
      #|
      #|#available #colorLiteral #column #else #elseif #endif #error #file #fileLiteral #function #if #imageLiteral #line #selector #sourceLocation #warning
    ),
  )
  let declarations = word_set(
    (
      #|actor class deinit enum convenience extension final func import init internal lazy let nonisolated optional private protocol public required static struct subscript typealias var dynamic indirect associatedtype open fileprivate some
    ),
  )
  let constants = word_set("true false nil")
  lx.start(fn(lx) { lx.push("bol") })
  // beginning of line
  lx.state("bol", fn(s) {
    s.rule("#.*", "Comment.Preproc")
    s.mix_in("inline_whitespace")
    s.call("", fn(lx, _) { lx.pop() })
  })
  lx.state("inline_whitespace", fn(s) {
    s.rule("\\s+", "Text", flags="m")
    s.mix_in("has_comments")
  })
  lx.state("whitespace", fn(s) {
    s.rule("\\n+", "Text", flags="m", next="bol")
    s.rule("\\/\\/.*?$", "Comment.Single", next="bol")
    s.mix_in("inline_whitespace")
  })
  lx.state("has_comments", fn(s) {
    s.rule("/[*]", "Comment.Multiline", next="nested_comment")
  })
  lx.state("nested_comment", fn(s) {
    s.mix_in("has_comments")
    s.rule("[*]/", "Comment.Multiline", next="#pop")
    s.rule("[^*/]+", "Comment.Multiline", flags="m")
    s.rule(".", "Comment.Multiline")
  })
  lx.state("root", fn(s) {
    s.mix_in("whitespace")
    s.rule("\\$(([1-9]\\d*)?\\d)", "Name.Variable")
    s.rule("[()\\[\\]{}:;,?\\\\]", "Punctuation")
    s.rule("[-/=+*%<>!&|^.~]+", "Operator")
    s.rule("@?\"", "Literal.String", next="dq")
    s.rule("'(\\\\.|.)'", "Literal.String.Char")
    s.rule(
      "(\\d+(?:_\\d+)*\\*|(?:\\d+(?:_\\d+)*)*\\.\\d+(?:_\\d)*)(e[+-]?\\d+(?:_\\d)*)?",
      "Literal.Number.Float",
      flags="i",
    )
    s.rule("\\d+e[+-]?[0-9]+", "Literal.Number.Float", flags="i")
    s.rule("0o?[0-7]+(?:_[0-7]+)*", "Literal.Number.Oct")
    s.rule(
      "0x[0-9A-Fa-f]+(?:_[0-9A-Fa-f]+)*((\\.[0-9A-F]+(?:_[0-9A-F]+)*)?p[+-]?\\d+)?",
      "Literal.Number.Hex",
    )
    s.rule("0b[01]+(?:_[01]+)*", "Literal.Number.Bin")
    s.rule("[\\d]+(?:_\\d+)*", "Literal.Number.Integer")
    s.rule("@\{id}", "Keyword.Declaration")
    s.call("(private|internal)(\\([ ]*)(\\w+)([ ]*\\))", fn(lx, m) {
      if group_text(m, 3) == "set" {
        lx.token("Keyword.Declaration")
      } else {
        lx.groups([
          "Keyword.Declaration", "Keyword.Declaration", "Error", "Keyword.Declaration",
        ])
      }
    })
    s.call("(unowned\\([ ]*)(\\w+)([ ]*\\))", fn(lx, m) {
      if group_text(m, 2) == "safe" || group_text(m, 2) == "unsafe" {
        lx.token("Keyword.Declaration")
      } else {
        lx.groups(["Keyword.Declaration", "Error", "Keyword.Declaration"])
      }
    })
    s.rule("#available\\([^)]+\\)", "Keyword.Declaration")
    s.call("(#(?:selector|keyPath)\\()([^)]+?(?:[(].*?[)])?)(\\))", fn(lx, _) {
      lx.groups(["Keyword.Declaration", "Name.Function", "Keyword.Declaration"])
    })
    s.rule("#(line|file|column|function|dsohandle)", "Keyword.Declaration")
    s.call("(let|var)\\b(\\s*)(\{id})", fn(lx, _) {
      lx.groups(["Keyword", "Text", "Name.Variable"])
    })
    s.call("(let|var)\\b(\\s*)([(])", fn(lx, _) {
      lx.groups(["Keyword", "Text", "Punctuation"])
      lx.push("tuple")
    })
    s.call(
      "(?!\\b(if|while|for|private|internal|unowned|switch|case)\\b)\\b\{id}(?=(\\?|!)?\\s*[(])",
      fn(lx, m) {
        if rx_search("^[[:upper:]]", m.matched()) {
          lx.token("Keyword.Type")
        } else {
          lx.token("Name.Function")
        }
      },
    )
    s.rule("as[?!]?(?=\\s)", "Keyword")
    s.rule("try[!]?(?=\\s)", "Keyword")
    s.call("(#?(?!default)(?![[:upper:]])\{id})(\\s*)(:)", fn(lx, _) {
      lx.groups(["Name.Variable", "Text", "Punctuation"])
    })
    s.call(id, fn(lx, m) {
      let name = m.matched()
      if keywords.contains(name) {
        lx.token("Keyword")
      } else if declarations.contains(name) {
        lx.token("Keyword.Declaration")
      } else if constants.contains(name) {
        lx.token("Keyword.Constant")
      } else if rx_search("^[[:upper:]]", name) {
        lx.token("Keyword.Type")
      } else {
        lx.token("Name")
      }
    })
    s.call("(`)(\{id})(`)", fn(lx, _) {
      lx.groups(["Punctuation", "Name.Variable", "Punctuation"])
    })
  })
  lx.state("tuple", fn(s) {
    s.rule("(\{id})", "Name.Variable")
    s.call("(`)(\{id})(`)", fn(lx, _) {
      lx.groups(["Punctuation", "Name.Variable", "Punctuation"])
    })
    s.rule(",", "Punctuation")
    s.rule("[(]", "Punctuation", next="#push")
    s.rule("[)]", "Punctuation", next="#pop")
    s.mix_in("inline_whitespace")
  })
  lx.state("dq", fn(s) {
    s.rule("\\\\[\\\\0tnr'\"]", "Literal.String.Escape")
    s.rule("\\\\[(]", "Literal.String.Escape", next="interp")
    s.rule("\\\\u\\{\\h{1,8}\\}", "Literal.String.Escape")
    s.rule("[^\\\\\"]+", "Literal.String")
    s.rule("\"\"\"", "Literal.String", next="#pop")
    s.rule("\"", "Literal.String", next="#pop")
  })
  lx.state("interp", fn(s) {
    s.rule("[(]", "Punctuation", next="interp_inner")
    s.rule("[)]", "Literal.String.Escape", next="#pop")
    s.mix_in("root")
  })
  lx.state("interp_inner", fn(s) {
    s.rule("[(]", "Punctuation", next="#push")
    s.rule("[)]", "Punctuation", next="#pop")
    s.mix_in("root")
  })
  lx
}
