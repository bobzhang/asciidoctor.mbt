///|
/// The functions of `make` (Make.functions).
let make_functions : Array[String] = words(
  (
    #|abspath addprefix addsuffix and basename call dir error eval file
    #|filter filter-out findstring firstword flavor foreach if join lastword
    #|notdir or origin patsubst realpath shell sort strip subst suffix value
    #|warning wildcard word wordlist words
  ),
)

///|
/// Rouge's `Make` (lexers/make.rb): Makefiles, recipes lexed as shell.
pub fn make(options : Map[String, String]) -> Lexer {
  let lx = Lexer::new("make", options~)
  // the shell lexer of the recipes and assignments, kept for the lexer's
  // life and reset at each lex
  let sh = shell(copy_options(options))
  lx.start(fn(_) { sh.reset() })
  lx.state("root", fn(s) {
    s.rule("\\s+", "Text")
    s.rule("#.*?\\n", "Comment")
    s.call("([-s]?include)((?:[\\t ]+[^\\t\\n #]+)+)", fn(lx, _) {
      lx.groups(["Keyword", "Literal.String.Other"])
    })
    s.call("(ifn?def|ifn?eq)([\\t ]+)([^#\\n]+)", fn(lx, _) {
      lx.groups(["Keyword", "Text", "Name.Variable"])
    })
    s.rule("(?:else|endif)[\\t ]*(?=[#\\n])", "Keyword")
    s.call("(export)([\\t ]+)(?=[\\w\\${}()\\t -]+\\n)", fn(lx, _) {
      lx.groups(["Keyword", "Text"])
      lx.push("export")
    })
    s.rule("export[\\t ]+", "Keyword")
    // assignment
    s.call(
      "([\\w${}().-]+)([\\t ]*)([!?:+]?=)",
      fn(lx, m) {
        lx.token("Name.Variable", val=group_text(m, 1))
        lx.token("Text", val=group_text(m, 2))
        lx.token("Operator", val=group_text(m, 3))
        lx.push("shell_line")
      },
      flags="m",
    )
    s.rule("\"(\\\\\\\\|\\\\.|[^\"\\\\])*\"", "Literal.String.Double")
    s.rule("'(\\\\\\\\|\\\\.|[^'\\\\])*'", "Literal.String.Single")
    s.call("([^\\n:]+)(:+)([ \\t]*)", fn(lx, _) {
      lx.groups(["Name.Label", "Operator", "Text"])
      lx.push("block_header")
    })
  })
  lx.state("export", fn(s) {
    s.rule("[\\w\\${}()-]", "Name.Variable")
    s.rule("\\n", "Text", next="#pop")
    s.rule("[\\t ]+", "Text")
  })
  lx.state("block_header", fn(s) {
    s.rule("[^,\\\\\\n#]+", "Name.Function")
    s.rule(",", "Punctuation")
    s.rule("#.*?", "Comment")
    s.rule("\\\\\\n", "Text")
    s.rule("\\\\.", "Text")
    s.call("\\n", fn(lx, _) {
      lx.token("Text")
      lx.goto("block_body")
    })
  })
  lx.state("block_body", fn(s) {
    s.call("(ifn?def|ifn?eq)([\\t ]+)([^#\\n]+)(#.*)?(\\n)", fn(lx, _) {
      lx.groups(["Keyword", "Text", "Name.Variable", "Comment", "Text"])
    })
    s.call("(else|endif)([\\t ]*)(#.*)?(\\n)", fn(lx, _) {
      lx.groups(["Keyword", "Text", "Comment", "Text"])
    })
    s.call("(\\t[\\t ]*)([@-]?)", fn(lx, _) {
      lx.groups(["Text", "Punctuation"])
      lx.push("shell_line")
    })
    s.call("", fn(lx, _) {
      sh.reset()
      lx.pop()
    })
  })
  lx.state("shell", fn(s) {
    // macro interpolation
    s.rule("\\$[({][\\t ]*\\w[\\w:=%.]*[\\t ]*[)}]", "Name.Variable", flags="i")
    // function invocation
    s.call(
      "(\\$[({])([\\t ]*)(\{alt(make_functions)})([\\t ]+)",
      fn(lx, _) {
        lx.groups(["Name.Function", "Text", "Name.Builtin", "Text"])
        lx.push("shell_expr")
      },
      flags="m",
    )
    s.call("\\\\.", fn(lx, _) { lx.delegate(sh) }, flags="m")
    let stop = "\\$\\(|\\$\\{|\\(|\\)|\\}|\\\\|$"
    s.call(".+?(?=\{rx(stop)})", fn(lx, _) { lx.delegate(sh) }, flags="m")
    s.call(stop, fn(lx, _) { lx.delegate(sh) })
  })
  lx.state("shell_expr", fn(s) {
    s.call("[({]", fn(lx, _) {
      lx.delegate(sh)
      lx.push_self()
    })
    s.rule("[)}]", "Name.Function", next="#pop")
    s.mix_in("shell")
  })
  lx.state("shell_line", fn(s) {
    s.rule("\\n", "Text", next="#pop")
    s.mix_in("shell")
  })
  lx
}
