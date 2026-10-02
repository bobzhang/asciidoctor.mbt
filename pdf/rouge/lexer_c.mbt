///|
/// Rouge's `C.keywords`.
let c_keywords : Set[String] = word_set(
  (
    #|auto break case const continue default do else enum extern
    #|for goto if register restricted return sizeof static struct
    #|switch typedef union volatile virtual while
    #|
    #|_Alignas _Alignof _Atomic _Generic _Imaginary
    #|_Noreturn _Static_assert _Thread_local
  ),
)

///|
/// Rouge's `C.keywords_type`.
let c_keywords_type : Set[String] = word_set(
  (
    #|int long float short double char unsigned signed void
    #|
    #|jmp_buf FILE DIR div_t ldiv_t mbstate_t sig_atomic_t fpos_t
    #|clock_t time_t va_list size_t ssize_t off_t wchar_t ptrdiff_t
    #|wctrans_t wint_t wctype_t
    #|
    #|_Bool _Complex int8_t int16_t int32_t int64_t
    #|uint8_t uint16_t uint32_t uint64_t int_least8_t
    #|int_least16_t int_least32_t int_least64_t
    #|uint_least8_t uint_least16_t uint_least32_t
    #|uint_least64_t int_fast8_t int_fast16_t int_fast32_t
    #|int_fast64_t uint_fast8_t uint_fast16_t uint_fast32_t
    #|uint_fast64_t intptr_t uintptr_t intmax_t
    #|uintmax_t
    #|
    #|char16_t char32_t
  ),
)

///|
/// Rouge's `C.reserved`.
let c_reserved : Set[String] = word_set(
  (
    #|__asm __int8 __based __except __int16 __stdcall __cdecl
    #|__fastcall __int32 __declspec __finally __int61 __try __leave
    #|inline _inline __inline naked _naked __naked restrict _restrict
    #|__restrict thread _thread __thread typename _typename __typename
  ),
)

///|
/// Rouge's `C` (lexers/c.rb).
pub fn c(options : Map[String, String]) -> Lexer {
  let lx = Lexer::new("c", options~)
  lx.set_fresh(fn() { c(Map([])) })
  c_states(lx, c_keywords, c_keywords_type, c_reserved, Set([]))
  lx
}

///|
/// The states of Rouge's `C`, with the class's keyword sets (`Cpp`
/// overrides them).
fn c_states(
  lx : Lexer,
  keywords : Set[String],
  keywords_type : Set[String],
  reserved : Set[String],
  builtins : Set[String],
) -> Unit {
  // optional comment or whitespace
  let ws = rx("(?:\\s|//.*?\\n|/[*].*?[*]/)+")
  let id = rx("[a-zA-Z_][a-zA-Z0-9_]*")
  lx.start(fn(lx) { lx.push("bol") })
  lx.state("expr_bol", fn(s) {
    s.mix_in("inline_whitespace")
    s.rule("#if\\s0", "Comment", next="if_0")
    s.rule("#", "Comment.Preproc", next="macro")
    s.call("", fn(lx, _) { lx.pop() })
  })
  // :expr_bol is the same as :bol but without labels, since labels can
  // only appear at the beginning of a statement.
  lx.state("bol", fn(s) {
    s.rule("\{id}:(?!:)", "Name.Label")
    s.mix_in("expr_bol")
  })
  lx.state("inline_whitespace", fn(s) {
    s.rule("[ \\t\\r]+", "Text")
    s.rule("\\\\\\n", "Text") // line continuation
    s.rule("/(\\\\\\n)?[*].*?[*](\\\\\\n)?/", "Comment.Multiline", flags="m")
  })
  lx.state("whitespace", fn(s) {
    s.rule("\\n+", "Text", flags="m", next="bol")
    s.rule("//(\\\\.|.)*?$", "Comment.Single", next="bol")
    s.mix_in("inline_whitespace")
  })
  lx.state("expr_whitespace", fn(s) {
    s.rule("\\n+", "Text", flags="m", next="expr_bol")
    s.mix_in("whitespace")
  })
  lx.state("statements", fn(s) {
    s.mix_in("whitespace")
    s.rule("(u8|u|U|L)?\"", "Literal.String", next="string")
    s.rule(
      "(u8|u|U|L)?'(\\\\.|\\\\[0-7]{1,3}|\\\\x[a-f0-9]{1,2}|[^\\\\'\\n])'",
      "Literal.String.Char",
      flags="i",
    )
    s.rule(
      "(\\d+[.]\\d*|[.]?\\d+)e[+-]?\\d+[lu]*",
      "Literal.Number.Float",
      flags="i",
    )
    s.rule("\\d+e[+-]?\\d+[lu]*", "Literal.Number.Float", flags="i")
    s.rule("0x[0-9a-f]+[lu]*", "Literal.Number.Hex", flags="i")
    s.rule("0[0-7]+[lu]*", "Literal.Number.Oct", flags="i")
    s.rule("\\d+[lu]*", "Literal.Number.Integer", flags="i")
    s.rule("\\*/", "Error")
    s.rule("[~!%^&*+=\\|?:<>/-]", "Operator")
    s.rule("[()\\[\\],.;]", "Punctuation")
    s.rule("\\bcase\\b", "Keyword", next="case")
    s.rule("(?:true|false|NULL)\\b", "Name.Builtin")
    s.call(id, fn(lx, m) {
      let name = m.matched()
      if keywords.contains(name) {
        lx.token("Keyword")
      } else if keywords_type.contains(name) {
        lx.token("Keyword.Type")
      } else if reserved.contains(name) {
        lx.token("Keyword.Reserved")
      } else if builtins.contains(name) {
        lx.token("Name.Builtin")
      } else {
        lx.token("Name")
      }
    })
  })
  lx.state("case", fn(s) {
    s.rule(":", "Punctuation", next="#pop")
    s.mix_in("statements")
  })
  lx.state("root", fn(s) {
    s.mix_in("expr_whitespace")
    s.call(
      (
        #|
        #|          ([\w*\s]+?[\s*]) # return arguments
        #|          (
      ) +
      id +
      (
        #|)          # function name
        #|          (\s*\([^;]*?\))  # signature
        #|          (
      ) +
      ws +
      (
        #|?)({|;)    # open brace or semicolon
        #|
      ),
      fn(lx, m) {
        // TODO: do this better.
        lx.recurse(text=group_text(m, 1))
        lx.token("Name.Function", val=group_text(m, 2))
        lx.recurse(text=group_text(m, 3))
        lx.recurse(text=group_text(m, 4))
        lx.token("Punctuation", val=group_text(m, 5))
        if group_text(m, 5) == "{" {
          lx.push("function")
        }
      },
      flags="mx",
    )
    s.rule("\\{", "Punctuation", next="function")
    s.mix_in("statements")
  })
  lx.state("function", fn(s) {
    s.mix_in("whitespace")
    s.mix_in("statements")
    s.rule(";", "Punctuation")
    s.rule("{", "Punctuation", next="function")
    s.rule("}", "Punctuation", next="#pop")
  })
  lx.state("string", fn(s) {
    s.rule("\"", "Literal.String", next="#pop")
    s.rule(
      "\\\\([\\\\abfnrtv\"']|x[a-fA-F0-9]{2,4}|[0-7]{1,3})", "Literal.String.Escape",
    )
    s.rule("[^\\\\\"\\n]+", "Literal.String")
    s.rule("\\\\\\n", "Literal.String")
    s.rule("\\\\", "Literal.String") // stray backslash
  })
  lx.state("macro", fn(s) {
    s.mix_in("include")
    s.rule("[^/\\n\\\\]+", "Comment.Preproc")
    s.rule("\\\\.", "Comment.Preproc", flags="m")
    s.mix_in("inline_whitespace")
    s.rule("/", "Comment.Preproc")
    // NB: pop! goes back to :bol
    s.rule("\\n", "Comment.Preproc", next="#pop")
  })
  lx.state("include", fn(s) {
    s.call("(include)(\\s*)(<[^>]+>)([^\\n]*)", fn(lx, _) {
      lx.groups([
        "Comment.Preproc", "Text", "Comment.PreprocFile", "Comment.Single",
      ])
    })
    s.call("(include)(\\s*)(\"[^\"]+\")([^\\n]*)", fn(lx, _) {
      lx.groups([
        "Comment.Preproc", "Text", "Comment.PreprocFile", "Comment.Single",
      ])
    })
  })
  lx.state("if_0", fn(s) {
    // NB: no \b here, to cover #ifdef and #ifndef
    s.rule("^\\s*#if", "Comment", next="if_0")
    s.rule("^\\s*#\\s*el(?:se|if)", "Comment", next="#pop")
    s.rule(
      "^\\s*#\\s*endif\\b.*?(?<!\\\\)\\n",
      "Comment",
      flags="m",
      next="#pop",
    )
    s.rule(".*?\\n", "Comment")
  })
}
