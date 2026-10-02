///|
/// A lexer to delegate to: an instance, lexing on in its current state,
/// or a lexer class, lexing each text from scratch (Rouge's `delegate`
/// with an instance or a class).
priv enum Delegatee {
  Instance(Lexer)
  Class(() -> Lexer)
}

///|
fn Lexer::delegate_to(self : Lexer, target : Delegatee?) -> Unit {
  match target {
    Some(Instance(lexer)) => self.delegate(lexer)
    Some(Class(make)) => self.delegate_new(make)
    None => abort("rouge: \{self.tag}: delegate to nil")
  }
}

///|
/// The instance variables of Rouge's `HTML` (`@javascript`, `@css`,
/// `@lang`), which its start block sets.
priv struct HtmlVars {
  mut javascript : Lexer?
  mut css : Lexer?
  mut lang : Delegatee?
}

///|
/// Rouge's `HTML` (lexers/html.rb).
pub fn html(options : Map[String, String]) -> Lexer {
  let lx = Lexer::new("html", options~)
  ignore(html_states(lx))
  lx
}

///|
/// The states and start block of Rouge's `HTML`, shared with `Vue`; the
/// lexer's instance variables.
fn html_states(lx : Lexer) -> HtmlVars {
  let vars : HtmlVars = { javascript: None, css: None, lang: None, }
  lx.start(fn(lx) {
    vars.javascript = Some(javascript(lx.options.copy()))
    vars.css = Some(css(lx.options.copy()))
  })
  lx.state("root", fn(s) {
    s.rule("[^<&]+", "Text", flags="m")
    s.rule("&\\S*?;", "Name.Entity")
    s.rule("<!DOCTYPE .*?>", "Comment.Preproc", flags="im")
    s.rule("<!\\[CDATA\\[.*?\\]\\]>", "Comment.Preproc", flags="m")
    s.rule("<!--", "Comment", next="comment")
    s.rule("<\\?.*?\\?>", "Comment.Preproc", flags="m") // php? really?
    s.call(
      "<\\s*script\\s*",
      fn(lx, _) {
        lx.token("Name.Tag")
        if vars.javascript is Some(js) {
          js.reset()
        }
        lx.push("script_content")
        lx.push("tag")
      },
      flags="m",
    )
    s.call(
      "<\\s*style\\s*",
      fn(lx, _) {
        lx.token("Name.Tag")
        if vars.css is Some(css) {
          css.reset()
        }
        vars.lang = vars.css.map(l => Instance(l))
        lx.push("style_content")
        lx.push("tag")
      },
      flags="m",
    )
    s.rule("</", "Name.Tag", next="tag_end")
    s.rule("<", "Name.Tag", next="tag_start")
    s.rule("<\\s*[\\p{L}:_-][\\p{Word}\\p{Cf}:.·-]*", "Name.Tag", next="tag") // opening tags
    s.rule("<\\s*/\\s*[\\p{L}:_-][\\p{Word}\\p{Cf}:.·-]*\\s*>", "Name.Tag") // closing tags
  })
  lx.state("tag_end", fn(s) {
    s.mix_in("tag_end_end")
    s.call("[\\p{L}:_-][\\p{Word}\\p{Cf}:.·-]*", fn(lx, _) {
      lx.token("Name.Tag")
      lx.goto("tag_end_end")
    })
  })
  lx.state("tag_end_end", fn(s) {
    s.rule("\\s+", "Text")
    s.rule(">", "Name.Tag", next="#pop")
  })
  lx.state("tag_start", fn(s) {
    s.rule("\\s+", "Text")
    s.call("[\\p{L}:_-][\\p{Word}\\p{Cf}:.·-]*", fn(lx, _) {
      lx.token("Name.Tag")
      lx.goto("tag")
    })
    s.call("", fn(lx, _) { lx.goto("tag") })
  })
  lx.state("comment", fn(s) {
    s.rule("[^-]+", "Comment")
    s.rule("-->", "Comment", next="#pop")
    s.rule("-", "Comment")
  })
  lx.state("tag", fn(s) {
    s.rule("\\s+", "Text", flags="m")
    s.rule(
      "[\\p{L}:_\\[\\]()*.-][\\p{Word}\\p{Cf}:.·\\[\\]()*-]*\\s*=\\s*",
      "Name.Attribute",
      flags="m",
      next="attr",
    )
    s.rule("[\\p{L}:_*#-][\\p{Word}\\p{Cf}:.·*#-]*", "Name.Attribute")
    s.rule("/?\\s*>", "Name.Tag", flags="m", next="#pop")
  })
  lx.state("attr", fn(s) {
    // TODO: are backslash escapes valid here?
    s.call("\"", fn(lx, _) {
      lx.token("Literal.String")
      lx.goto("dq")
    })
    s.call("'", fn(lx, _) {
      lx.token("Literal.String")
      lx.goto("sq")
    })
    s.rule("[^\\s>]+", "Literal.String", next="#pop")
  })
  lx.state("dq", fn(s) {
    s.rule("\"", "Literal.String", next="#pop")
    s.rule("[^\"]+", "Literal.String")
  })
  lx.state("sq", fn(s) {
    s.rule("'", "Literal.String", next="#pop")
    s.rule("[^']+", "Literal.String")
  })
  lx.state("script_content", fn(s) {
    s.call("[^<]+", fn(lx, _) {
      lx.delegate_to(vars.javascript.map(l => Instance(l)))
    })
    s.rule("<\\s*/\\s*script\\s*>", "Name.Tag", flags="m", next="#pop")
    s.call("<", fn(lx, _) {
      lx.delegate_to(vars.javascript.map(l => Instance(l)))
    })
  })
  lx.state("style_content", fn(s) {
    s.call("[^<]+", fn(lx, _) { lx.delegate_to(vars.lang) })
    s.rule("<\\s*/\\s*style\\s*>", "Name.Tag", flags="m", next="#pop")
    s.call("<", fn(lx, _) { lx.delegate_to(vars.lang) })
  })
  vars
}
