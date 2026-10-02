///|
/// Rouge's `Rust.keywords`.
let rust_keywords : Array[String] = words(
  (
    #|as async await break const continue crate dyn else enum extern false
    #|fn for if impl in let log loop match mod move mut pub ref return self
    #|Self static struct super trait true type unsafe use where while
    #|abstract become box do final macro
    #|override priv typeof unsized virtual
    #|yield try
    #|union
  ),
)

///|
/// Rouge's `Rust.builtins`.
let rust_builtins : Set[String] = word_set(
  (
    #|Add BitAnd BitOr BitXor bool c_char c_double c_float char
    #|c_int clock_t c_long c_longlong Cons Const Copy c_schar c_short
    #|c_uchar c_uint c_ulong c_ulonglong c_ushort c_void dev_t DIR
    #|dirent Div Either Eq Err f32 f64 Failure FILE float fpos_t
    #|i16 i32 i64 i8 isize Index ino_t int intptr_t Left mode_t Modulo Mul
    #|Neg Nil None Num off_t Ok Option Ord Owned pid_t Ptr ptrdiff_t
    #|Right Send Shl Shr size_t Some ssize_t str Sub Success time_t
    #|u16 u32 u64 u8 usize uint uintptr_t
    #|Box Vec String Gc Rc Arc
    #|u128 i128 Result Sync Pin Unpin Sized Drop drop Fn FnMut FnOnce
    #|Clone PartialEq PartialOrd AsMut AsRef From Into Default
    #|DoubleEndedIterator ExactSizeIterator Extend IntoIterator Iterator
  ),
)

///|
/// Rouge's `Rust` (lexers/rust.rb).
pub fn rust(options : Map[String, String]) -> Lexer {
  let lx = Lexer::new("rust", options~)
  // the open macro delimiters, by closing delimiter (`@macro_delims`)
  let macro_delims : Map[String, Int] = Map([])
  let macro_closed = fn() { macro_delims.values().all(n => n == 0) }
  lx.start(fn(lx) {
    macro_delims.clear()
    macro_delims["]"] = 0
    macro_delims[")"] = 0
    macro_delims["}"] = 0
    lx.push("bol")
  })
  let delim_map = fn(open : String) {
    match open {
      "[" => "]"
      "(" => ")"
      _ => "}"
    }
  }
  let id = rx("[\\p{XID_Start}_]\\p{XID_Continue}*")
  let hex = rx("[0-9a-f]", flags="i")
  let escapes = "\n        \\\\ ([nrt'\"\\\\0] | x\{hex}{2} | u\\{(\{hex}_*){1,6}\\})\n      " // x
  let size = rx("8|16|32|64|128|size")
  // Although not officially part of Rust, the rustdoc tool allows code in
  // comments to begin with `#`. Code like this will be evaluated but not
  // included in the HTML output produced by rustdoc. So that code intended
  // for these comments can be higlighted with Rouge, the  Rust lexer needs
  // to check if the beginning of the line begins with a `# `.
  lx.state("bol", fn(s) {
    s.mix_in("whitespace")
    s.rule("#\\s[^\\n]*", "Comment.Special")
    s.call("", fn(lx, _) { lx.pop() })
  })
  lx.state("attribute", fn(s) {
    s.mix_in("whitespace")
    s.mix_in("has_literals")
    s.rule("[(,)=:]", "Name.Decorator")
    s.rule("\\]", "Name.Decorator", next="#pop")
    s.rule(id, "Name.Decorator")
  })
  lx.state("whitespace", fn(s) {
    s.rule("\\s+", "Text")
    s.mix_in("comments")
  })
  lx.state("comments", fn(s) {
    // Only 3 slashes are doc comments, `////` and beyond become normal
    // comments again (for some reason), so match this before the doc line
    // comments rather than figure out a
    s.rule("////+[^\\n]*", "Comment.Single")
    // doc line comments — either inner (`//!`), or outer (`///`).
    s.rule("//[/!][^\\n]*", "Comment.Doc")
    // otherwise, `//` is just a plain line comme
    s.rule("//[^\\n]*", "Comment.Single")
    // /**/ and /***/ are self-closing block comments, not doc. Because this
    // is self-closing, it doesn't enter the states for nested comments
    s.rule("/\\*\\*\\*?/", "Comment.Multiline")
    // 3+ stars and it's a normal non-doc block comment.
    s.rule("/\\*\\*\\*+", "Comment.Multiline", next="nested_plain_block")
    // `/*!` and `/**` begin doc comments. These nest and can have internal
    // block/doc comments, but they're still part of the documentation
    // inside.
    s.rule("/[*][*!]", "Comment.Doc", next="nested_doc_block")
    // any other /* is a plain multiline comment
    s.rule("/[*]", "Comment.Multiline", next="nested_plain_block")
  })
  // Multiline/block comments fully nest, those marked as documentation
  // too: if (on the outermost level) the comment starts as one kind of
  // block comment (either doc/non-doc), then everything inside of it,
  // including nested block comments of the opposite type, stays that type.
  for
    spec in [
      ("nested_plain_block", "Comment.Multiline"),
      ("nested_doc_block", "Comment.Doc"),
    ] {
    let (state_name, comment_token) = spec
    lx.state(state_name, fn(s) {
      s.rule("\\*/", comment_token, next="#pop")
      s.rule("/\\*", comment_token, next=state_name)
      // We only want to eat at most one `[*/]` at a time, but we can skip
      // past non-`[*/]` in bulk.
      s.rule("[^*/]+|[*/]", comment_token)
    })
  }
  lx.state("root", fn(s) {
    s.rule("\\n", "Text", next="bol")
    s.mix_in("whitespace")
    s.rule("#!?\\[", "Name.Decorator", next="attribute")
    s.rule("\\b(?:\{alt(rust_keywords)})\\b", "Keyword")
    s.mix_in("has_literals")
    s.rule("[=-]>", "Keyword")
    s.rule("<->", "Keyword")
    s.rule("[()\\[\\]{}|,:;]", "Punctuation")
    s.rule("[*\\/!@~&+%^<>=\\?-]|\\.{2,3}", "Operator")
    s.rule("([.]\\s*)?\{id}(?=\\s*[(])", "Name.Function", flags="m")
    s.rule("[.]\\s*await\\b", "Keyword")
    s.rule("[.]\\s*\{id}", "Name.Property")
    s.rule("[.]\\s*\\d+", "Name.Attribute")
    s.call(
      "(\{id})(::)",
      fn(lx, _) { lx.groups(["Name.Namespace", "Punctuation"]) },
      flags="m",
    )
    // macros
    s.rule("\\bmacro_rules!", "Name.Decorator", next="macro_rules")
    s.rule("\{id}!", "Name.Decorator", next="macro")
    s.rule("'static\\b", "Keyword")
    s.rule("'\{id}", "Name.Variable")
    s.call(id, fn(lx, m) {
      if rust_builtins.contains(m.matched()) {
        lx.token("Name.Builtin")
      } else {
        lx.token("Name")
      }
    })
  })
  lx.state("macro", fn(s) {
    s.mix_in("has_literals")
    s.call("[\\[{(]", fn(lx, m) {
      let close = delim_map(m.matched())
      macro_delims[close] = macro_delims.get(close).unwrap_or(0) + 1
      lx.token("Punctuation")
    })
    s.call("[\\]})]", fn(lx, m) {
      let close = m.matched()
      macro_delims[close] = macro_delims.get(close).unwrap_or(0) - 1
      if macro_closed() {
        lx.pop()
      }
      lx.token("Punctuation")
    })
    // same as the rule in root, but don't push another macro state
    s.rule("\{id}!", "Name.Decorator")
    s.mix_in("root")
    // No syntax errors in macros
    s.rule(".", "Text")
  })
  lx.state("macro_rules", fn(s) {
    s.rule("[$]\{id}(:\{id})?", "Name.Variable")
    s.rule("[$]", "Name.Variable")
    s.mix_in("macro")
  })
  lx.state("has_literals", fn(s) {
    // constants
    s.rule("\\b(?:true|false)\\b", "Keyword.Constant")
    // characters/bytes
    s.rule(
      "\n          b?' (?: \{rx(escapes, flags="x")} | [^\\\\] ) '\n        ",
      "Literal.String.Char",
      flags="x",
    )
    s.rule("b?\"", "Literal.String", next="string")
    s.rule("b?r(#*)\".*?\"\\1", "Literal.String", flags="m")
    // numbers
    let dot = rx("[.][0-9][0-9_]*")
    let exp = rx("[eE][-+]?[0-9_]+")
    let flt = rx("f32|f64")
    s.rule(
      "\n          [0-9][0-9_]*\n          (\{dot}  \{exp}? \{flt}?\n          |\{dot}? \{exp}  \{flt}?\n          |\{dot}? \{exp}? \{flt}\n          |[.](?![._\\p{XID_Start}])\n          )\n        ",
      "Literal.Number.Float",
      flags="x",
    )
    s.rule(
      "\n          ( 0b[10_]+\n          | 0x[0-9a-fA-F_]+\n          | 0o[0-7_]+\n          | [0-9][0-9_]*\n          ) (u\{size}?|i\{size})?\n        ",
      "Literal.Number.Integer",
      flags="x",
    )
  })
  lx.state("string", fn(s) {
    s.rule("\"", "Literal.String", next="#pop")
    s.rule(escapes, "Literal.String.Escape", flags="x")
    s.rule("[^\"\\\\]+", "Literal.String", flags="m")
  })
  lx
}
