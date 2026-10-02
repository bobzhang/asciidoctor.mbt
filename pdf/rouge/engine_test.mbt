///|
/// Tokens as `type:text`, one per line.
fn show(tokens : Array[(String, String)]) -> String {
  tokens.map(t => "\{t.0}:\{t.1.escape()}").join("\n")
}

///|
/// A lexer whose start block goes to another state: Rouge's `stack`
/// accessor makes `[:root]` first, so `goto` replaces it.
fn starts_elsewhere() -> @rouge.Lexer {
  let lx = @rouge.Lexer::new("test")
  lx.state("root", s => s.rule("a", "Keyword"))
  lx.state("other", s => {
    s.rule("a", "Name")
    s.call("b", (lx, _) => {
      lx.token("Literal.String")
      lx.push("root")
    })
  })
  lx.start(lx => lx.goto("other"))
  lx
}

///|
test "a start block may go to another state" {
  let lx = starts_elsewhere()
  inspect(
    show(lx.tokens("aba")),
    content=(
      #|Name:"a"
      #|Literal.String:"b"
      #|Keyword:"a"
    ),
  )
  // and again from its start, not where the last lex left the stack
  inspect(lx.stack_size(), content="2")
  inspect(
    show(lx.tokens("aba")),
    content=(
      #|Name:"a"
      #|Literal.String:"b"
      #|Keyword:"a"
    ),
  )
}

///|
test "push, pop, push_self, mixins and in_state" {
  let lx = @rouge.Lexer::new("test")
  lx.state("root", s => {
    s.rule("\\(", "Punctuation", next="paren")
    s.rule("[a-z]+", "Name")
  })
  lx.state("common", s => s.rule("\\s+", "Text"))
  lx.state("paren", s => {
    s.mix_in("common")
    s.call("\\(", (lx, _) => {
      lx.token(if lx.in_state("paren") { "Operator" } else { "Error" })
      lx.push_self()
    })
    s.rule("\\)", "Punctuation", next="#pop")
    s.rule("[a-z]+", "Literal.String")
  })
  inspect(
    show(lx.tokens("a(b (c)) d")),
    content=(
      #|Name:"a"
      #|Punctuation:"("
      #|Literal.String:"b"
      #|Text:" "
      #|Operator:"("
      #|Literal.String:"c"
      #|Punctuation:"))"
      #|Error:" "
      #|Name:"d"
    ),
  )
}

///|
test "five empty matches in a row yield error characters" {
  // as in Rouge, the count is reset only by a match that consumes, so
  // once over five the empty rule keeps failing the step
  let lx = @rouge.Lexer::new("test")
  lx.state("root", s => {
    s.call("", (_, _) => ())
    s.rule("x", "Name")
  })
  inspect(
    show(lx.tokens("ax")),
    content=(
      #|Error:"ax"
    ),
  )
}

///|
test "a lexer keeps its own copy of the options it is given" {
  // the option readers delete what they read, as Rouge's do on the copy
  // Lexer#initialize makes
  let options = { "token": "Name" }
  let first = @rouge.plain_text(options)
  let second = @rouge.plain_text(options)
  inspect(show(first.tokens("x")), content="Name:\"x\"")
  inspect(show(second.tokens("x")), content="Name:\"x\"")
  inspect(options.get("token") == Some("Name"), content="true")
}

///|
test "delegating to an instance keeps its state, to a class does not" {
  let inner = starts_elsewhere()
  let outer = @rouge.Lexer::new("outer")
  outer.state("root", s => {
    s.call("\\[([^\\]]*)\\]", (lx, m) => {
      lx.delegate(inner, text=@rouge.group_text(m, 1))
    })
    s.call("\\{([^}]*)\\}", (lx, m) => {
      lx.delegate_new(starts_elsewhere, text=@rouge.group_text(m, 1))
    })
  })
  // the instance was never reset: it starts in root; its stack carries on
  // from one delegation to the next; the class starts afresh each time
  inspect(
    show(outer.tokens("[a][b][a]{a}{a}")),
    content=(
      #|Keyword:"a"
      #|Error:"b"
      #|Keyword:"a"
      #|Name:"aa"
    ),
  )
}

///|
test "a start block may pop the root state and push another" {
  // Rouge's `stack` makes `[:root]` before the start block pops it
  let lx = @rouge.Lexer::new("test")
  lx.state("root", s => s.rule("a", "Keyword"))
  lx.state("other", s => s.rule("a", "Name"))
  let depths = []
  lx.start(lx => {
    lx.pop()
    depths.push(lx.stack_size())
    lx.push("other")
  })
  inspect(show(lx.tokens("a")), content="Name:\"a\"")
  inspect(depths.map(d => d.to_string()).join(","), content="0")
  inspect(lx.stack_size(), content="1")
}

///|
/// A lexer whose `)` pops five states, more than there are.
fn pops_too_many() -> @rouge.Lexer {
  let lx = @rouge.Lexer::new("test")
  lx.state("root", s => {
    s.rule("\\(", "Punctuation", next="inner")
    s.rule("a", "Name")
  })
  lx.state("inner", s => {
    s.call("\\)", (lx, _) => {
      lx.token("Punctuation")
      lx.pop(times=5)
    })
  })
  lx
}

///|
test "popping more states than there are empties the stack" {
  // Ruby's Array#pop(n) takes what there is: no error until a state is
  // needed again, here never, as the text ends
  let lx = pops_too_many()
  inspect(
    show(lx.tokens("a()")),
    content=(
      #|Name:"a"
      #|Punctuation:"()"
    ),
  )
  inspect(lx.stack_size(), content="0")
}

///|
test "panic lexing on with an emptied stack fails, as Rouge's empty stack!" {
  ignore(pops_too_many().tokens("()a"))
}

///|
test "panic a start block that pops the root state leaves nothing to lex with" {
  let lx = @rouge.Lexer::new("test")
  lx.state("root", s => s.rule("a", "Keyword"))
  lx.start(lx => lx.pop())
  ignore(lx.tokens("a"))
}
