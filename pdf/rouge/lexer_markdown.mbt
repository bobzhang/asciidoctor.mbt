///|
/// Rouge's `Markdown` (lexers/markdown.rb). Inline HTML goes to the HTML
/// lexer and front matter to the YAML lexer (plain text while those are
/// not ported); fenced code to the lexer its language names.
pub fn markdown(options : Map[String, String]) -> Lexer {
  let lx = Lexer::new("markdown", options~)
  let html = script_lexer_or_text("html", lx.options.copy())
  lx.start(fn(_) { html.reset() })
  let edot = rx("\\\\.|[^\\\\\\n]")
  lx.state("root", fn(s) {
    // YAML frontmatter
    s.call(
      "\\A(---\\s*\\n.*?\\n?)^(---\\s*$\\n?)",
      fn(lx, _) {
        lx.delegate_new(fn() { script_lexer_or_text("yaml", Map([])) })
      },
      flags="m",
    )
    s.rule("\\\\.", "Literal.String.Escape")
    s.rule("^[\\S ]+\\n(?:---*)\\n", "Generic.Heading")
    s.rule("^[\\S ]+\\n(?:===*)\\n", "Generic.Subheading")
    s.rule("^#(?=[^#]).*?$", "Generic.Heading")
    s.rule("^##*.*?$", "Generic.Subheading")
    s.call(
      "^([ \\t]*)(`{3,}|~{3,})([^\\n]*\\n)((.*?)(\\n\\1)(\\2))?",
      fn(lx, m) {
        let name = ruby_strip(group_text(m, 3))
        let sublexer = match
          script_find_fancy(
            if name == "" {
              "guess"
            } else {
              name
            },
            m.group(5),
            lx.options,
          ) {
          Some(l) => l
          None => {
            let opts = lx.options.copy()
            opts["token"] = "Literal.String.Backtick"
            plain_text(opts)
          }
        }
        sublexer.reset()
        lx.token("Text", val=group_text(m, 1))
        lx.token("Punctuation", val=group_text(m, 2))
        lx.token("Name.Label", val=group_text(m, 3))
        if m.group(5) is Some(code) {
          lx.delegate(sublexer, text=code)
        }
        lx.token("Text", val=group_text(m, 6))
        if m.group(7) is Some(fence) {
          lx.token("Punctuation", val=fence)
        } else {
          let fence = group_text(m, 2)
          lx.push_rules(fn(s) {
            s.call("^([ \\t]*)(\{fence})", fn(lx, mb) {
              lx.pop()
              lx.token("Text", val=group_text(mb, 1))
              lx.token("Punctuation", val=group_text(mb, 2))
            })
            s.call("^.*\\n", fn(lx, _) { lx.delegate(sublexer) })
          })
        }
      },
      flags="m",
    )
    s.rule("\\n\\n((    |\\t).*?\\n|\\n)+", "Literal.String.Backtick")
    s.rule("(`+)(?:\{edot}|\\n)+?\\1", "Literal.String.Backtick")
    // various uses of * are in order of precedence

    // line breaks
    s.rule("^(\\s*[*]){3,}\\s*$", "Punctuation")
    s.rule("^(\\s*[-]){3,}\\s*$", "Punctuation")
    // bulleted lists
    s.rule("^\\s*[*+-](?=\\s)", "Punctuation")
    // numbered lists
    s.rule("^\\s*\\d+\\.", "Punctuation")
    // blockquotes
    s.rule("^\\s*>.*?$", "Generic.Traceback")
    // link references
    // [foo]: bar "baz"
    s.call(
      (
        #|^
        #|          (\s*) # leading whitespace
      ) +
      "\n          (\\[) (\{edot}+?) (\\]) # the reference\n" +
      (
        #|          (\s*) (:) # colon
        #|
      ),
      fn(lx, _) {
        lx.groups([
          "Text", "Punctuation", "Literal.String.Symbol", "Punctuation", "Text",
          "Punctuation",
        ])
        lx.push("title")
        lx.push("url")
      },
      flags="x",
    )
    // links and images
    s.call("(!?\\[)(\{edot}*?|[^\\]]*?)(\\])(?=[\\[(])", fn(lx, _) {
      lx.groups(["Punctuation", "Name.Variable", "Punctuation"])
      lx.push("link")
    })
    s.rule("[*][*]\{edot}*?[*][*]", "Generic.Strong")
    s.rule("__\{edot}*?__", "Generic.Strong")
    s.rule("[*]\{edot}*?[*]", "Generic.Emph")
    s.rule("_\{edot}*?_", "Generic.Emph")
    // Automatic links
    s.rule("<.*?@.+[.].+>", "Name.Variable")
    s.rule("<(https?|mailto|ftp)://\{edot}*?>", "Name.Variable")
    s.rule("[^\\\\`\\[*\\n&<]+", "Text")
    // inline html
    s.call("&\\S*;", fn(lx, _) { lx.delegate(html) })
    s.call("<\{edot}*?>", fn(lx, _) { lx.delegate(html) })
    s.rule("[&<]", "Text")
    // An opening square bracket that is not a link
    s.rule("\\[", "Text")
    s.rule("\\n", "Text")
  })
  lx.state("link", fn(s) {
    s.call("(\\[)(\{edot}*?)(\\])", fn(lx, _) {
      lx.groups(["Punctuation", "Literal.String.Symbol", "Punctuation"])
      lx.pop()
    })
    s.call("[(]", fn(lx, _) {
      lx.token("Punctuation")
      lx.push("inline_title")
      lx.push("inline_url")
    })
    s.rule("[ \\t]+", "Text")
    s.call("", fn(lx, _) { lx.pop() })
  })
  lx.state("url", fn(s) {
    s.rule("[ \\t]+", "Text")
    // the url
    s.call("(<)(\{edot}*?)(>)", fn(lx, _) {
      lx.groups(["Name.Tag", "Literal.String.Other", "Name.Tag"])
      lx.pop()
    })
    s.rule("\\S+", "Literal.String.Other", next="#pop")
  })
  lx.state("title", fn(s) {
    s.rule("\"\{edot}*?\"", "Name.Namespace")
    s.rule("'\{edot}*?'", "Name.Namespace")
    s.rule("[(]\{edot}*?[)]", "Name.Namespace")
    s.rule("\\s*(?=[\"'()])", "Text")
    s.call("", fn(lx, _) { lx.pop() })
  })
  lx.state("inline_title", fn(s) {
    s.rule("[)]", "Punctuation", next="#pop")
    s.mix_in("title")
  })
  lx.state("inline_url", fn(s) {
    s.rule("[^<\\s)]+", "Literal.String.Other", next="#pop")
    s.rule("\\s+", "Text", flags="m")
    s.mix_in("url")
  })
  lx
}
