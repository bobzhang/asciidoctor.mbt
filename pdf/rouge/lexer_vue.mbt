///|
/// Rouge's `Vue#lookup_lang`: the lexer class of a `lang` attribute value.
fn vue_lookup_lang(lang : String) -> Delegatee {
  let lang = lang
    .to_lower()
    .replace_all(old="\"", new="")
    .replace_all(old="'", new="")
  Class(
    match lang {
      "html" => fn() { html(Map([])) }
      "css" => fn() { css(Map([])) }
      "javascript" => fn() { javascript(Map([])) }
      "sass" => fn() { sass(Map([])) }
      "scss" => fn() { scss(Map([])) }
      "coffee" => fn() { coffeescript(Map([])) }
      // TODO: add more when the lexers are done
      _ => fn() { plain_text(Map([])) }
    },
  )
}

///|
/// Rouge's `Vue` (lexers/vue.rb): single-file components, an `HTML`
/// subclass.
pub fn vue(options : Map[String, String]) -> Lexer {
  let lx = Lexer::new("vue", options~)
  let vars = html_states(lx)
  let js = javascript(lx.options.copy())
  lx.start(fn(_) { js.reset() })
  lx.prepend("root", fn(s) {
    s.call("(<)(\\s*)(template)", fn(lx, _) {
      lx.groups(["Name.Tag", "Text", "Keyword"])
      vars.lang = Some(Class(fn() { html(Map([])) }))
      lx.push("template")
      lx.push("lang_tag")
    })
    s.call("(<)(\\s*)(style)", fn(lx, _) {
      lx.groups(["Name.Tag", "Text", "Keyword"])
      vars.lang = Some(Class(fn() { css(Map([])) }))
      lx.push("style")
      lx.push("lang_tag")
    })
    s.call("(<)(\\s*)(script)", fn(lx, _) {
      lx.groups(["Name.Tag", "Text", "Keyword"])
      vars.lang = Some(Class(fn() { javascript(Map([])) }))
      lx.push("script")
      lx.push("lang_tag")
    })
  })
  lx.prepend("tag", fn(s) {
    s.rule(
      "[a-zA-Z0-9_:#\\[\\]()*.-]+\\s*=\\s*",
      "Name.Attribute",
      flags="m",
      next="attr",
    )
  })
  lx.state("style", fn(s) {
    s.call("(<\\s*\\/\\s*)(style)(\\s*>)", fn(lx, _) {
      lx.groups(["Name.Tag", "Keyword", "Name.Tag"])
      lx.pop()
    })
    s.mix_in("style_content")
    s.mix_in("embed")
  })
  lx.state("script", fn(s) {
    s.call("(<\\s*\\/\\s*)(script)(\\s*>)", fn(lx, _) {
      lx.groups(["Name.Tag", "Keyword", "Name.Tag"])
      lx.pop()
    })
    s.mix_in("script_content")
    s.mix_in("embed")
  })
  lx.state("lang_tag", fn(s) {
    s.call(
      "(lang\\s*=)(\\s*)(\"(?:\\\\.|[^\\\\])*?\"|'(\\\\.|[^\\\\])*?'|[^\\s>]+)",
      fn(lx, m) {
        lx.groups(["Name.Attribute", "Text", "Literal.String"])
        vars.lang = Some(vue_lookup_lang(group_text(m, 3)))
      },
    )
    s.mix_in("tag")
  })
  lx.state("template", fn(s) {
    s.call("(<\\s*/\\s*)(template)(\\s*>)", fn(lx, _) {
      lx.groups(["Name.Tag", "Keyword", "Name.Tag"])
      lx.pop()
    })
    s.call("{{", fn(lx, _) {
      lx.token("Literal.String.Interpol")
      lx.push("template_interpol")
      js.reset()
    })
    s.mix_in("embed")
  })
  lx.state("template_interpol", fn(s) {
    s.rule("}}", "Literal.String.Interpol", next="#pop")
    s.rule("}", "Error")
    s.mix_in("template_interpol_inner")
  })
  lx.state("template_interpol_inner", fn(s) {
    s.call("{", fn(lx, _) {
      lx.delegate(js)
      lx.push_self()
    })
    s.call("}", fn(lx, _) {
      lx.delegate(js)
      lx.pop()
    })
    s.call("[^{}]+", fn(lx, _) { lx.delegate(js) })
  })
  lx.state("embed", fn(s) {
    s.call("[^{<]+", fn(lx, _) { lx.delegate_to(vars.lang) })
    s.call("[<{][^<{]*", fn(lx, _) { lx.delegate_to(vars.lang) })
  })
  lx
}
