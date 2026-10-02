///|
/// Rouge's `PlainText` (lexers/plain_text.rb): the whole text as one token,
/// `Text` unless the `token` option names another.
pub fn plain_text(options : Map[String, String]) -> Lexer {
  let lx = Lexer::new("plaintext", options~)
  let tok = match lx.string_option("token") {
    Some(t) if is_token(t) => t
    _ => "Text"
  }
  lx.set_stream(fn(_, text, emit) { emit(tok, text) })
  lx
}
