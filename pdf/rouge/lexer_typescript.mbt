///|
/// The word lists of `TypescriptCommon` (lexers/typescript/common.rb):
/// JavaScript's and its own.
let ts_words : JsWords = {
  keywords: word_set(
    js_keywords_src +
    "\nis namespace static private protected public implements readonly",
  ),
  declarations: word_set(js_declarations_src + "\ntype abstract"),
  reserved: word_set(
    js_reserved_src +
    "\nstring any void number namespace module declare default interface keyof",
  ),
  constants: word_set(js_constants_src),
  builtins: word_set(js_builtins_src + "\nPick Partial Readonly Record"),
}

///|
/// What extending a lexer with `TypescriptCommon` prepends to its states.
fn typescript_common_states(lx : Lexer) -> Unit {
  lx.prepend("root", fn(s) {
    s.rule("[?][.]", "Punctuation")
    s.rule("[?]{2}", "Operator")
  })
  lx.prepend("statement", fn(s) {
    s.call("(\{rx(js_id_src, flags="i")})(\\??)(\\s*)(:)", fn(lx, _) {
      lx.groups(["Name.Label", "Punctuation", "Text", "Punctuation"])
      lx.push("expr_start")
    })
  })
}

///|
/// Rouge's `Typescript` (lexers/typescript.rb).
pub fn typescript(options : Map[String, String]) -> Lexer {
  let lx = Lexer::new("typescript", options~)
  javascript_states(lx, ts_words)
  typescript_common_states(lx)
  lx
}
