///|
/// Rouge's `ERB` (lexers/erb.rb), a `TemplateLexer` (template_lexer.rb):
/// the text outside the tags goes to the `parent` lexer (default: HTML).
pub fn erb(options : Map[String, String]) -> Lexer {
  let ruby_lexer = ruby(options.copy())
  let lx = Lexer::new("erb", options~)
  // TemplateLexer#parent: built on first use
  let mut parent_lexer : Lexer? = None
  fn parent() -> Lexer {
    match parent_lexer {
      Some(p) => p
      None => {
        let p = match lx.lexer_option("parent") {
          Some(p) => p
          None => html(lx.options.copy())
        }
        parent_lexer = Some(p)
        p
      }
    }
  }

  lx.start(fn(_) { parent().reset() })
  lx.start(fn(_) {
    parent().reset()
    ruby_lexer.reset()
  })
  let open_src = "<%%|<%=|<%#|<%-|<%"
  let close_src = "%%>|-%>|%>"
  let open = rx(open_src)
  let close = rx(close_src)
  lx.state("root", fn(s) {
    s.rule("<%#", "Comment", next="comment")
    s.rule(open_src, "Comment.Preproc", next="ruby")
    s.call(".+?(?=\{open})|.+", fn(lx, _) { lx.delegate(parent()) }, flags="m")
  })
  lx.state("comment", fn(s) {
    s.rule(close_src, "Comment", next="#pop")
    s.rule(".+?(?=\{close})|.+", "Comment", flags="m")
  })
  lx.state("ruby", fn(s) {
    s.rule(close_src, "Comment.Preproc", next="#pop")
    s.call(
      ".+?(?=\{close})|.+",
      fn(lx, _) { lx.delegate(ruby_lexer) },
      flags="m",
    )
  })
  lx
}
