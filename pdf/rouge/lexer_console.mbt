///|
/// A copy of `options` (a Rouge lexer copies the options it is built with).
fn copy_options(options : Map[String, String]) -> Map[String, String] {
  let copy = Map([])
  for k, v in options {
    copy[k] = v
  }
  copy
}

///|
/// Ruby's `String#split(',')`: trailing empty fields dropped.
fn ruby_split_commas(list : Array[String]) -> Array[String] {
  let out = list.copy()
  while out.last() is Some("") {
    ignore(out.pop())
  }
  out
}

///|
/// What distinguishes the console lexers (`ConsoleLexer` and its subclass
/// `IRBLexer`): the lexer of the commands, the lexer of the output, the
/// prompt regex and the strings that start an error message.
priv struct ConsoleSpec {
  lang : Lexer
  output : Lexer
  prompt : @regex.Regex
  error : Array[String]
}

///|
/// `ConsoleLexer#stream_tokens`: line by line, an elision is a comment, a
/// line with a prompt is the prompt and a command (lexed by the language
/// lexer, which keeps its state from command line to command line), a
/// line starting with `#` a comment, a line starting with an error string
/// an error, any other line output (lexed by the output lexer).
fn console_stream(lx : Lexer, spec : ConsoleSpec) -> Unit {
  let snip_re = compile("\\A\\s*(?:<[.]+>|[.]+)\\s*\\z", "")
  let comment_re = compile("\\A\\s*?#", "")
  let space_re = compile("\\A\\s*", "")
  let error_re = if spec.error.is_empty() {
    None
  } else {
    Some(compile("^(?:\{alt(spec.error.map(rx_escape))})", ""))
  }
  lx.set_stream(fn(_, text, emit) {
    spec.lang.reset()
    spec.output.reset()
    let len = text.length()
    let mut pos = 0
    while pos < len {
      // the line, with its newline (`/(.*?)(\n|$)/`)
      let mut end = pos
      while end < len && text.unsafe_get(end) != '\n' {
        end += 1
      }
      if end < len {
        end += 1
      }
      let line = text.unsafe_substring(start=pos, end~)
      pos = end
      if snip_re.find(line) is Some(_) {
        spec.output.reset()
        spec.lang.reset()
        emit("Comment", line)
      } else if spec.prompt.find(line) is Some(m) {
        spec.output.reset()
        emit("Generic.Prompt", m.matched())
        let rest = m.post_match()
        // initial whitespace, before the language lexer gets the line
        let ws = match space_re.find(rest) {
          Some(w) => w.matched()
          None => ""
        }
        if ws != "" {
          emit("Text.Whitespace", ws)
        }
        spec.lang.continue_lex(
          rest.unsafe_substring(start=ws.length(), end=rest.length()),
          emit,
        )
      } else if comment_re.find(ruby_strip(line)) is Some(_) {
        spec.output.reset()
        spec.lang.reset()
        emit("Comment", line)
      } else if error_re is Some(re) && re.find(line) is Some(_) {
        spec.output.reset()
        spec.lang.reset()
        emit("Generic.Error", line)
      } else {
        spec.lang.reset()
        spec.output.continue_lex(line, emit)
      }
    }
  })
}

///|
/// The output lexer by default: plain text as `Generic.Output`.
fn console_output_default() -> Lexer {
  plain_text(Map([("token", "Generic.Output")]))
}

///|
/// Rouge's `ConsoleLexer` (lexers/console.rb): shell sessions, prompts
/// and commands and their output. Options: `lang` (the language of the
/// commands, `shell` by default), `output` (the language of the output),
/// `prompt` (the strings that end a prompt, comma-separated), `comments`
/// (whether a line starting with `#` is a comment rather than a prompt)
/// and `error` (the strings that start an error message).
pub fn console(options : Map[String, String]) -> Lexer {
  let lx = Lexer::new("console", options~)
  let prompt = ruby_split_commas(lx.list_option("prompt").unwrap_or([]))
  let lang = match lx.options.get("lang") {
    Some(_) => lx.lexer_option("lang")
    None => (find_lexer.val)("shell").map(f => f(copy_options(lx.options)))
  }
  let output = match lx.options.get("output") {
    Some(_) => lx.lexer_option("output")
    None => Some(console_output_default())
  }
  let comments : Bool? = match lx.options.get("comments") {
    Some(v) => Some(option_bool(v))
    None => None
  }
  let error = ruby_split_commas(lx.list_option("error").unwrap_or([]))
  // `allow_comments?` (`:guess`: a prompt is given and does not include
  // `#`) and `end_chars`
  let allow_comments = match comments {
    Some(b) => b
    None => !prompt.is_empty() && !prompt.filter(c => c != "").contains("#")
  }
  let end_chars = if !prompt.is_empty() {
    prompt.filter(c => c != "")
  } else if allow_comments {
    ["$", ">", ";"]
  } else {
    ["$", "#", ">", ";"]
  }
  let prefix = if allow_comments {
    rx("[^<#]*?", flags="m")
  } else {
    rx(".*?", flags="m")
  }
  let lang = match lang {
    Some(l) => l
    None => shell(copy_options(lx.options))
  }
  let output = match output {
    Some(l) => l
    None => console_output_default()
  }
  console_stream(lx, {
    lang,
    output,
    prompt: compile("^\{prefix}(?:\{alt(end_chars.map(rx_escape))})", ""),
    error,
  })
  lx
}
