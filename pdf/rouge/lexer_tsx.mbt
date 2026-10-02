///|
/// Rouge's `TSX` (lexers/tsx.rb): JSX extended with `TypescriptCommon`.
pub fn tsx(options : Map[String, String]) -> Lexer {
  let lx = Lexer::new("tsx", options~)
  jsx_states(lx, ts_words)
  typescript_common_states(lx)
  lx.prepend("element_name", fn(s) {
    s.call("(\\w+)(,)", fn(lx, _) {
      lx.groups(["Name.Other", "Punctuation"])
      lx.pop(times=3)
    })
  })
  lx
}
