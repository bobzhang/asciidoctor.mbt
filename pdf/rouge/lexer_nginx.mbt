///|
/// Rouge's `Nginx` (lexers/nginx.rb): nginx configuration files.
pub fn nginx(options : Map[String, String]) -> Lexer {
  let lx = Lexer::new("nginx", options~)
  let id = rx("[^\\s$;{}()#]+")
  lx.state("root", fn(s) {
    s.call("(include)(\\s+)([^\\s;]+)", fn(lx, _) {
      lx.groups(["Keyword", "Text", "Name"])
    })
    s.rule(id, "Keyword", next="statement")
    s.mix_in("base")
  })
  lx.state("block", fn(s) {
    s.rule("}", "Punctuation", next="#pop")
    s.rule(id, "Keyword.Namespace", next="statement")
    s.mix_in("base")
  })
  lx.state("statement", fn(s) {
    s.call("{", fn(lx, _) {
      lx.token("Punctuation")
      lx.pop()
      lx.push("block")
    })
    s.rule(";", "Punctuation", next="#pop")
    s.mix_in("base")
  })
  lx.state("base", fn(s) {
    s.rule("\\s+", "Text")
    s.rule("#.*", "Comment.Single")
    s.rule("(?:on|off)\\b", "Name.Constant")
    s.rule("[$][\\w-]+", "Name.Variable")
    // host/port
    s.call(
      "([a-z0-9.-]+)(:)([0-9]+)",
      fn(lx, _) {
        lx.groups(["Name.Function", "Punctuation", "Literal.Number.Integer"])
      },
      flags="i",
    )
    // mimetype
    s.rule("[a-z-]+/[a-z-]+", "Name.Class", flags="i")
    s.rule("[0-9]+[kmg]?\\b", "Literal.Number.Integer", flags="i")
    s.call("(~)(\\s*)([^\\s{]+)", fn(lx, _) {
      lx.groups(["Punctuation", "Text", "Literal.String.Regex"])
    })
    s.rule("[:=~]", "Punctuation")
    // pathname
    s.rule("/\{id}?", "Name")
    s.rule("[^#\\s;{}$\\\\]+", "Literal.String") // catchall
    s.rule("[$;]", "Text")
  })
  lx
}
