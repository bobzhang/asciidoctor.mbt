///|
/// The instructions of `docker` (Docker::KEYWORDS).
let docker_keywords : String = alt(
  words(
    "FROM MAINTAINER CMD LABEL EXPOSE ENV ADD COPY ENTRYPOINT VOLUME USER WORKDIR ARG STOPSIGNAL HEALTHCHECK SHELL",
  ),
)

///|
/// Rouge's `Docker` (lexers/docker.rb): Dockerfiles, `RUN` lines lexed as
/// shell.
pub fn docker(options : Map[String, String]) -> Lexer {
  let lx = Lexer::new("docker", options~)
  // the shell lexer of `RUN` lines, a new one per lex
  let mut sh = shell(copy_options(options))
  lx.start(fn(_) { sh = shell(copy_options(options)) })
  lx.state("root", fn(s) {
    s.rule("\\s+", "Text")
    s.call(
      "^(FROM)(\\s+)(.*)(\\s+)(AS)(\\s+)(.*)",
      fn(lx, _) {
        lx.groups([
          "Keyword", "Text.Whitespace", "Literal.String", "Text.Whitespace", "Keyword",
          "Text.Whitespace", "Literal.String",
        ])
      },
      flags="i",
    )
    s.call(
      "^(ONBUILD)(\\s+)(\{docker_keywords})(.*)",
      fn(lx, _) {
        lx.groups(["Keyword", "Text.Whitespace", "Keyword", "Literal.String"])
      },
      flags="i",
    )
    s.call(
      "^(\{docker_keywords})\\b(.*)",
      fn(lx, _) { lx.groups(["Keyword", "Literal.String"]) },
      flags="i",
    )
    s.rule("#.*?$", "Comment")
    s.call(
      "^(ONBUILD\\s+)?RUN(\\s+)",
      fn(lx, _) {
        lx.token("Keyword")
        lx.push("run")
        sh.reset()
      },
      flags="i",
    )
    s.rule("\\w+", "Text")
    s.rule("[^\\w]+", "Text")
    s.rule(".", "Text")
  })
  lx.state("run", fn(s) {
    s.rule("\\n", "Text", next="#pop")
    s.rule("\\\\.", "Literal.String.Escape", flags="m")
    s.call("(\\\\.|[^\\n\\\\])+", fn(lx, _) { lx.delegate(sh) })
  })
  lx
}
