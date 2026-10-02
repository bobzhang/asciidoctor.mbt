///|
/// Rouge's `JSX` (lexers/jsx.rb).
pub fn jsx(options : Map[String, String]) -> Lexer {
  let lx = Lexer::new("jsx", options~)
  jsx_states(lx, js_words)
  lx
}

///|
/// The states and start block of Rouge's `JSX` on top of those of
/// `Javascript` with the word lists `w`, shared with `TSX`.
fn jsx_states(lx : Lexer, w : JsWords) -> Unit {
  javascript_states(lx, w)
  let mut html_lexer : Lexer? = None
  lx.start(fn(lx) {
    html_lexer = Some(html(lx.options.copy()))
    lx.push("expr_start")
  })
  lx.prepend("expr_start", fn(s) { s.mix_in("tag") })
  lx.state("tag", fn(s) {
    s.call("<", fn(lx, _) {
      lx.token("Punctuation")
      lx.push("tag_opening")
      lx.push("element")
      lx.push("element_name")
    })
  })
  lx.state("tag_opening", fn(s) {
    s.call("<\\/", fn(lx, _) {
      lx.token("Punctuation")
      lx.goto("element")
      lx.push("element_name")
    })
    s.mix_in("tag")
    s.call("{", fn(lx, _) {
      lx.token("Literal.String.Interpol")
      lx.push("interpol")
      lx.push("expr_start")
    })
    s.call("[^<{]+", fn(lx, _) {
      match html_lexer {
        Some(h) => lx.delegate(h)
        None => abort("rouge: jsx: delegate to nil")
      }
    })
  })
  lx.state("element", fn(s) {
    s.mix_in("comments_and_whitespace")
    s.call("\\/>", fn(lx, _) {
      lx.token("Punctuation")
      lx.pop(times=2)
    })
    s.rule(">", "Punctuation", next="#pop")
    s.call("{", fn(lx, _) {
      lx.token("Literal.String.Interpol")
      lx.push("interpol")
      lx.push("expr_start")
    })
    s.rule("\\w[\\w-]*", "Name.Attribute")
    s.rule("=", "Punctuation")
    s.rule("([\"']).*?(\\1)", "Literal.String")
  })
  lx.state("element_name", fn(s) {
    s.rule("[A-Z]\\w*", "Name.Class")
    s.rule("\\w+", "Name.Tag")
    s.rule("\\.", "Punctuation")
    s.call("", fn(lx, _) { lx.pop() })
  })
  lx.state("interpol", fn(s) {
    s.rule("}", "Literal.String.Interpol", next="#pop")
    s.call("{", fn(lx, _) {
      lx.token("Punctuation")
      lx.push("interpol_inner")
      lx.push("statement")
    })
    s.mix_in("root")
  })
  lx.state("interpol_inner", fn(s) {
    s.call("}", fn(lx, _) {
      lx.token("Punctuation")
      lx.goto("statement")
    })
    s.mix_in("root")
  })
}
