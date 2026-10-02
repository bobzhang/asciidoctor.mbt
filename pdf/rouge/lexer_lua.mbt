///|
/// Rouge's `Lua` (lexers/lua.rb).
///
/// Its options `function_highlighting` and `disabled_modules` are read with
/// symbol keys before Rouge turns the keys into strings, so options given
/// by name (`lua?disabled_modules=...`) never reach them: every builtin
/// module is highlighted, as here.
pub fn lua(options : Map[String, String]) -> Lexer {
  let lx = Lexer::new("lua", options~)
  let builtins : Set[String] = Set([])
  for entry in lua_builtins {
    for f in entry.1 {
      builtins.add(f)
    }
  }
  lx.state("root", fn(s) {
    // lua allows a file to start with a shebang
    s.rule("#!(.*?)$", "Comment.Preproc")
    s.rule("", "Text", next="base")
  })
  lx.state("base", fn(s) {
    s.rule("--\\[(=*)\\[.*?\\]\\1\\]", "Comment.Multiline", flags="m")
    s.rule("--.*$", "Comment.Single")
    // (the quote that ends this pattern is Rouge's)
    s.rule(
      "(?i)(\\d*\\.\\d+|\\d+\\.\\d*)(e[+-]?\\d+)?'", "Literal.Number.Float",
    )
    s.rule("(?i)\\d+e[+-]?\\d+", "Literal.Number.Float")
    s.rule("(?i)0x[0-9a-f]*", "Literal.Number.Hex")
    s.rule("\\d+", "Literal.Number.Integer")
    s.rule("\\n", "Text")
    s.rule("[^\\S\\n]", "Text")
    // multiline strings
    s.rule("\\[(=*)\\[.*?\\]\\1\\]", "Literal.String", flags="m")
    s.rule("(==|~=|<=|>=|\\.\\.\\.|\\.\\.|[=+\\-*/%^<>#])", "Operator")
    s.rule("[\\[\\]\\{\\}\\(\\)\\.,:;]", "Punctuation")
    s.rule("(and|or|not)\\b", "Operator.Word")
    s.rule(
      "(break|do|else|elseif|end|for|if|in|repeat|return|then|until|while)\\b", "Keyword",
    )
    s.rule("(local)\\b", "Keyword.Declaration")
    s.rule("(true|false|nil)\\b", "Keyword.Constant")
    s.rule("(function)\\b", "Keyword", next="function_name")
    s.call("[A-Za-z_][A-Za-z0-9_]*(\\.[A-Za-z_][A-Za-z0-9_]*)?", fn(lx, m) {
      let name = m.matched()
      if name == "gsub" {
        lx.token("Name.Builtin")
        lx.push("gsub")
      } else if builtins.contains(name) {
        lx.token("Name.Builtin")
      } else if name.find(".") is Some(i) {
        lx.token("Name", val=name.unsafe_substring(start=0, end=i))
        lx.token("Punctuation", val=".")
        lx.token(
          "Name",
          val=name.unsafe_substring(start=i + 1, end=name.length()),
        )
      } else {
        lx.token("Name")
      }
    })
    s.rule("'", "Literal.String.Single", next="escape_sqs")
    s.rule("\"", "Literal.String.Double", next="escape_dqs")
  })
  lx.state("function_name", fn(s) {
    s.rule("\\s+", "Text")
    s.call("(?:([A-Za-z_][A-Za-z0-9_]*)(\\.))?([A-Za-z_][A-Za-z0-9_]*)", fn(
      lx,
      _,
    ) {
      lx.groups(["Name.Class", "Punctuation", "Name.Function"])
      lx.pop()
    })
    // inline function
    s.rule("\\(", "Punctuation", next="#pop")
  })
  lx.state("gsub", fn(s) {
    s.rule("\\)", "Punctuation", next="#pop")
    s.rule("[(,]", "Punctuation")
    s.rule("\\s+", "Text")
    s.rule("\"", "Literal.String.Regex", next="regex")
  })
  lx.state("regex", fn(s) {
    s.call("\"", fn(lx, _) {
      lx.token("Literal.String.Regex")
      lx.goto("regex_end")
    })
    s.rule("\\[\\^?", "Literal.String.Escape", next="regex_group")
    s.rule("\\\\.", "Literal.String.Escape")
    s.rule("[(][?][:=<!]", "Literal.String.Escape")
    s.rule("[{][\\d,]+[}]", "Literal.String.Escape")
    s.rule("[()?]", "Literal.String.Escape")
    s.rule(".", "Literal.String.Regex")
  })
  lx.state("regex_end", fn(s) {
    s.rule("[$]+", "Literal.String.Regex", next="#pop")
    s.call("", fn(lx, _) { lx.pop() })
  })
  lx.state("regex_group", fn(s) {
    s.rule("/", "Literal.String.Escape")
    s.rule("\\]", "Literal.String.Escape", next="#pop")
    s.call("(\\\\)(.)", fn(lx, _) {
      lx.groups(["Literal.String.Escape", "Literal.String.Regex"])
    })
    s.rule(".", "Literal.String.Regex")
  })
  lx.state("escape_sqs", fn(s) {
    s.mix_in("string_escape")
    s.mix_in("sqs")
  })
  lx.state("escape_dqs", fn(s) {
    s.mix_in("string_escape")
    s.mix_in("dqs")
  })
  lx.state("string_escape", fn(s) {
    s.rule("\\\\([abfnrtv\\\\\"']|\\d{1,3})", "Literal.String.Escape")
  })
  lx.state("sqs", fn(s) {
    s.rule("'", "Literal.String.Single", next="#pop")
    s.rule("[^']+", "Literal.String.Single")
  })
  lx.state("dqs", fn(s) {
    s.rule("\"", "Literal.String.Double", next="#pop")
    s.rule("[^\"]+", "Literal.String.Double")
  })
  lx
}
