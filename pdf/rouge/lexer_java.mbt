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
      java_signature,
      fn(lx, m) {
        lx.delegate_new(fn() { java(Map([])) }, text=group_text(m, 1))
        lx.token("Name.Function", val=group_text(m, 2))
        lx.token("Text", val=group_text(m, 3))
        lx.token("Operator", val=group_text(m, 4))
      },
      flags="mx",
      can_match=signature_ahead(),
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

///|
/// Rouge's Java method-signature rule (flags `mx`).
let java_signature : String =
  #|
  #|          (\s*(?:[a-zA-Z_][a-zA-Z0-9_.\[\]<>]*\s+)+?) # return arguments
  #|          ([a-zA-Z_][a-zA-Z0-9_]*)                  # method name
  #|          (\s*)(\()                                 # signature start
  #|

///|
/// Whether a character can be part of a Java method signature before its
/// `(` (the signature rule's `[a-zA-Z0-9_.\[\]<>]` and `\s`).
fn is_signature_char(c : UInt16) -> Bool {
  let c = c.to_int()
  (c >= 'a'.to_int() && c <= 'z'.to_int()) ||
  (c >= 'A'.to_int() && c <= 'Z'.to_int()) ||
  (c >= '0'.to_int() && c <= '9'.to_int()) ||
  c == '_'.to_int() ||
  c == '.'.to_int() ||
  c == '['.to_int() ||
  c == ']'.to_int() ||
  c == '<'.to_int() ||
  c == '>'.to_int() ||
  c == ' '.to_int() ||
  (c >= 0x09 && c <= 0x0D)
}

///|
/// Whether a signature character is a blank (`\s`).
fn is_signature_blank(c : UInt16) -> Bool {
  let c = c.to_int()
  c == ' '.to_int() || (c >= 0x09 && c <= 0x0D)
}

///|
/// Whether a character starts a word of a signature (`[a-zA-Z_]`).
fn is_signature_start(c : UInt16) -> Bool {
  let c = c.to_int()
  (c >= 'a'.to_int() && c <= 'z'.to_int()) ||
  (c >= 'A'.to_int() && c <= 'Z'.to_int()) ||
  c == '_'.to_int()
}

///|
/// The signature rule's `can_match`, exact: whether the rule matches at a
/// position. Its characters are signature characters, so a match runs to
/// the end of their run, which must be a `(`; before it, after optional
/// blanks, come words separated by blanks (and optional blanks before the
/// `(`): at least two, each starting with `[a-zA-Z_]`, the last (the method
/// name) all `[a-zA-Z0-9_]`. What decides that is worked out once per run
/// (the rule would rescan the rest of the run at each identifier, quadratic
/// in a long run, whether or not it ends in a `(`), so the positions of a
/// run are checked in constant time.
fn signature_ahead() -> (String, Int) -> Bool {
  let last_text : Ref[String] = Ref("")
  let run_start = Ref(-1)
  let run_end = Ref(-1)
  // the start of the run's last word, -1 when no method name can end it
  let name_start = Ref(-1)
  // the last word start before the method name that is not [a-zA-Z_]
  let last_bad = Ref(-1)
  // the last run of blanks skipped, for the positions in it
  let blank_from = Ref(-1)
  let blank_to = Ref(-1)
  fn(text, pos) {
    if !(physical_equal(text, last_text.val) &&
      pos >= run_start.val &&
      pos <= run_end.val) {
      let mut end = pos
      while end < text.length() && is_signature_char(text.unsafe_get(end)) {
        end += 1
      }
      last_text.val = text
      run_start.val = pos
      run_end.val = end
      blank_from.val = -1
      blank_to.val = -1
      name_start.val = -1
      last_bad.val = -1
      if end < text.length() && text.unsafe_get(end) == '(' {
        // the method name: the last word, all [a-zA-Z0-9_]
        let mut i = end
        while i > pos && is_signature_blank(text.unsafe_get(i - 1)) {
          i -= 1
        }
        let word_end = i
        while i > pos && !is_signature_blank(text.unsafe_get(i - 1)) {
          i -= 1
        }
        let word = text.view(start_offset=i, end_offset=word_end)
        let is_name = word.length() > 0 &&
          is_signature_start(word.unsafe_get(0)) &&
          word
          .iter()
          .all(c => c.is_ascii_alphabetic() || c.is_ascii_digit() || c == '_')
        if is_name {
          name_start.val = i
          for k in (pos + 1)..<i {
            if is_signature_blank(text.unsafe_get(k - 1)) &&
              !is_signature_blank(text.unsafe_get(k)) &&
              !is_signature_start(text.unsafe_get(k)) {
              last_bad.val = k
            }
          }
        }
      }
    }
    guard name_start.val >= 0 else { return false }
    // the first word: after the blanks at `pos`
    let first = if pos >= blank_from.val && pos < blank_to.val {
      blank_to.val
    } else {
      let mut i = pos
      while i < run_end.val && is_signature_blank(text.unsafe_get(i)) {
        i += 1
      }
      if i > pos {
        blank_from.val = pos
        blank_to.val = i
      }
      i
    }
    first < name_start.val &&
    is_signature_start(text.unsafe_get(first)) &&
    last_bad.val <= first
  }
}
