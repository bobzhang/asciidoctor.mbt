///|
/// Rouge's `IRBLexer` (lexers/irb.rb): IRB and Pry sessions, a
/// `ConsoleLexer` whose commands are Ruby and whose output is
/// `irb_output`. Of the console options only `error` applies.
pub fn irb(options : Map[String, String]) -> Lexer {
  let lx = Lexer::new("irb", options~)
  // `ConsoleLexer#initialize` reads (and removes) the options it knows
  ignore(lx.list_option("prompt"))
  ignore(lx.string_option("lang"))
  ignore(lx.string_option("output"))
  let error = ruby_split_commas(lx.list_option("error").unwrap_or([]))
  console_stream(lx, {
    lang: ruby(copy_options(lx.options)),
    output: irb_output(copy_options(lx.options)),
    prompt: compile("^.*?(irb|pry).*?[>\"*]", ""),
    error,
  })
  lx
}

///|
/// Rouge's `IRBOutputLexer` (lexers/irb.rb): the output of IRB, a `Ruby`
/// lexer that starts in `stdout` and lexes `#<...>` objects.
pub fn irb_output(options : Map[String, String]) -> Lexer {
  let lx = Lexer::new("irb_output", options~)
  // the states and start blocks of the superclass
  let base = ruby(Map([]))
  for name, state in base.states {
    lx.states[name] = state
  }
  for f in base.starts {
    lx.starts.push(f)
  }
  lx.set_fresh(fn() { irb_output(Map([])) })
  lx.start(fn(lx) { lx.push("stdout") })
  lx.state("has_irb_output", fn(s) {
    s.rule("=>", "Punctuation", next="#pop")
    s.rule(".+?(\\n|$)", "Generic.Output")
  })
  lx.state("irb_error", fn(s) {
    s.rule(".+?(\\n|$)", "Generic.Error")
    s.mix_in("has_irb_output")
  })
  lx.state("stdout", fn(s) {
    s.rule(
      "\\w+?(Error|Exception):.+?(\\n|$)",
      "Generic.Error",
      next="irb_error",
    )
    s.mix_in("has_irb_output")
  })
  lx.prepend("root", fn(s) { s.rule("#<", "Keyword.Type", next="irb_object") })
  lx.state("irb_object", fn(s) {
    s.rule(">", "Keyword.Type", next="#pop")
    s.mix_in("root")
  })
  lx
}
