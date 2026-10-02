///|
/// Ruby's `String#to_i` on a short numeric string: an optional sign and
/// the digits that follow, 0 without digits.
fn ruby_to_i(s : String) -> Int {
  let mut i = 0
  let mut neg = false
  if s.length() > 0 && (s.unsafe_get(0) == '+' || s.unsafe_get(0) == '-') {
    neg = s.unsafe_get(0) == '-'
    i = 1
  }
  let mut n = 0
  while i < s.length() && s.unsafe_get(i) >= '0' && s.unsafe_get(i) <= '9' {
    n = n * 10 + (s.unsafe_get(i).to_int() - '0'.to_int())
    i += 1
  }
  if neg {
    -n
  } else {
    n
  }
}

///|
/// Rouge's `YAML` (lexers/yaml.rb), which tracks block indentation.
pub fn yaml(options : Map[String, String]) -> Lexer {
  let lx = Lexer::new("yaml", options~)
  // the indentation levels (`@indent_stack`), the indentation of the line
  // being lexed (`@next_indent`) and of the block scalar being lexed
  let indent_stack : Array[Int] = [0]
  let mut next_indent = 0
  let mut block_scalar_indent : Int? = None
  fn reset_indent() {
    indent_stack.clear()
    indent_stack.push(0)
    next_indent = 0
    block_scalar_indent = None
  }

  fn indent() -> Int {
    match indent_stack.last() {
      Some(i) => i
      None => abort("empty indent stack!")
    }
  }

  // save a possible indentation level: the indentation and what dedents
  // to a level not previously indented to (an error)
  fn save_indent(m : String) -> (String, String) {
    next_indent = m.length()
    if next_indent < indent() {
      while next_indent < indent() {
        ignore(indent_stack.pop())
      }
      let i = indent()
      (
        m.unsafe_substring(start=0, end=i),
        m.unsafe_substring(start=i, end=m.length()),
      )
    } else {
      (m, "")
    }
  }

  fn continue_indent(m : String) {
    next_indent += m.length()
  }

  fn set_indent(m : String, implicit : Bool) {
    if indent() < next_indent {
      indent_stack.push(next_indent)
    }
    if !implicit {
      next_indent += m.length()
    }
  }

  let plain_scalar_start = rx("[^ \\t\\n\\r\\f\\v?:,\\[\\]{}#&*!\\|>'\"%@`]")
  lx.start(fn(_) { reset_indent() })
  lx.state("basic", fn(s) { s.rule("#.*$", "Comment.Single") })
  lx.state("root", fn(s) {
    s.mix_in("basic")
    s.rule("\\n+", "Text")
    // trailing or pre-comment whitespace
    s.rule("[ ]+(?=#|$)", "Text")
    s.call("^%YAML\\b", fn(lx, _) {
      lx.token("Name.Tag")
      reset_indent()
      lx.push("yaml_directive")
    })
    s.call("^%TAG\\b", fn(lx, _) {
      lx.token("Name.Tag")
      reset_indent()
      lx.push("tag_directive")
    })
    // doc-start and doc-end indicators
    s.call("^(?:---|\\.\\.\\.)(?= |$)", fn(lx, _) {
      lx.token("Name.Namespace")
      reset_indent()
      lx.push("block_line")
    })
    // indentation spaces
    s.call("[ ]*(?!\\s|$)", fn(lx, m) {
      let (text, err) = save_indent(m.matched())
      lx.token("Text", val=text)
      lx.token("Error", val=err)
      lx.push("block_line")
      lx.push("indentation")
    })
  })
  lx.state("indentation", fn(s) {
    s.call("\\s*?\\n", fn(lx, _) {
      lx.token("Text")
      lx.pop(times=2)
    })
    // whitespace preceding block collection indicators
    s.call("[ ]+(?=[-:?](?:[ ]|$))", fn(lx, m) {
      lx.token("Text")
      continue_indent(m.matched())
    })
    // block collection indicators
    s.call("[?:-](?=[ ]|$)", fn(lx, m) {
      set_indent(m.matched(), false)
      lx.token("Punctuation.Indicator")
    })
    // the beginning of a block line
    s.call("[ ]*", fn(lx, m) {
      lx.token("Text")
      continue_indent(m.matched())
      lx.pop()
    })
  })
  // indented line in the block context
  lx.state("block_line", fn(s) {
    // line end
    s.rule("[ ]*(?=#|$)", "Text", next="#pop")
    s.rule("[ ]+", "Text")
    // tags, anchors, and aliases
    s.mix_in("descriptors")
    // block collections and scalars
    s.mix_in("block_nodes")
    // flow collections and quoed scalars
    s.mix_in("flow_nodes")
    // a plain scalar
    s.call("(?=\{plain_scalar_start}|[?:-][^ \\t\\n\\r\\f\\v])", fn(lx, _) {
      lx.token("Name.Variable")
      lx.push("plain_scalar_in_block_context")
    })
  })
  lx.state("descriptors", fn(s) {
    // a full-form tag
    s.rule("!<[0-9A-Za-z;\\/?:@&=+$,_.!~*'()\\[\\]%-]+>", "Keyword.Type")
    // a tag in the form '!', '!suffix' or '!handle!suffix'
    s.rule(
      (
        #|
        #|          (?:![\w-]+)? # handle
        #|          !(?:[\w;/?:@&=+$,.!~*\'()\[\]%-]*) # suffix
        #|
      ),
      "Keyword.Type",
      flags="x",
    )
    // an anchor
    s.rule("&[\\p{L}\\p{Nl}\\p{Nd}_-]+", "Name.Label")
    // an alias
    s.rule("\\*[\\p{L}\\p{Nl}\\p{Nd}_-]+", "Name.Variable")
  })
  lx.state("block_nodes", fn(s) {
    // implicit key
    s.call("([^#,:?\\[\\]{}\"'\\n]+)(:)(?=\\s|$)", fn(lx, m) {
      lx.groups(["Name.Attribute", "Punctuation.Indicator"])
      set_indent(m.matched(), true)
    })
    // literal and folded scalars
    s.call("[\\|>][+-]?", fn(lx, _) {
      lx.token("Punctuation.Indicator")
      lx.push("block_scalar_content")
      lx.push("block_scalar_header")
    })
  })
  lx.state("flow_nodes", fn(s) {
    s.rule("\\[", "Punctuation.Indicator", next="flow_sequence")
    s.rule("\\{", "Punctuation.Indicator", next="flow_mapping")
    s.rule("'", "Literal.String.Single", next="single_quoted_scalar")
    s.rule("\"", "Literal.String.Double", next="double_quoted_scalar")
  })
  lx.state("flow_collection", fn(s) {
    s.rule("\\s+", "Text", flags="m")
    s.mix_in("basic")
    s.rule("[?:,]", "Punctuation.Indicator")
    s.mix_in("descriptors")
    s.mix_in("flow_nodes")
    s.call("(?=\{plain_scalar_start})", fn(lx, _) {
      lx.push("plain_scalar_in_flow_context")
    })
  })
  lx.state("flow_sequence", fn(s) {
    s.rule("\\]", "Punctuation.Indicator", next="#pop")
    s.mix_in("flow_collection")
  })
  lx.state("flow_mapping", fn(s) {
    s.rule("\\}", "Punctuation.Indicator", next="#pop")
    s.mix_in("flow_collection")
  })
  lx.state("block_scalar_content", fn(s) {
    s.rule("\\n+", "Text")
    // empty lines never dedent, but they might be part of the scalar.
    s.call("^[ ]+$", fn(lx, m) {
      let text = m.matched()
      let size = text.length()
      let mark = block_scalar_indent.unwrap_or(size)
      // `text[0...mark]` and `text[mark..-1]` (a negative index counts
      // from the end)
      let end = if mark < 0 { mark + size } else { mark }
      let end = if end < 0 { 0 } else if end > size { size } else { end }
      lx.token("Text", val=text.unsafe_substring(start=0, end~))
      let start = if mark < 0 { mark + size } else { mark }
      if start >= 0 && start <= size {
        lx.token("Name.Constant", val=text.unsafe_substring(start~, end=size))
      }
    })
    s.call("^[ ]*", fn(lx, m) {
      lx.token("Text")
      let size = m.matched().length()
      let dedent_level = block_scalar_indent.unwrap_or(indent())
      if block_scalar_indent is None {
        block_scalar_indent = Some(size)
      }
      if size < dedent_level {
        ignore(save_indent(m.matched()))
        lx.pop()
        lx.push("indentation")
      }
    })
    s.rule("[^\\n\\r\\f\\v]+", "Literal.String")
  })
  lx.state("block_scalar_header", fn(s) {
    // optional indentation indicator and chomping flag, in either order
    s.call(
      (
        #|
        #|          (
        #|            ([1-9])[+-]? | [+-]?([1-9])?
        #|          )(?=[ ]|$)
        #|
      ),
      fn(lx, m) {
        block_scalar_indent = None
        lx.goto("ignored_line")
        if m.matched() == "" {
          return
        }
        // `m[1] || m[2]`: the first group always takes part
        let increment = group_text(m, 1)
        block_scalar_indent = Some(indent() + ruby_to_i(increment))
        lx.token("Punctuation.Indicator")
      },
      flags="x",
    )
  })
  lx.state("ignored_line", fn(s) {
    s.mix_in("basic")
    s.rule("[ ]+", "Text")
    s.rule("\\n", "Text", next="#pop")
  })
  lx.state("quoted_scalar_whitespaces", fn(s) {
    // leading and trailing whitespace is ignored
    s.rule("^[ ]+", "Text")
    s.rule("[ ]+$", "Text")
    s.rule("\\n+", "Text", flags="m")
    s.rule("[ ]+", "Name.Variable")
  })
  lx.state("single_quoted_scalar", fn(s) {
    s.mix_in("quoted_scalar_whitespaces")
    s.rule("\\\\'", "Literal.String.Escape")
    s.rule("'", "Literal.String", next="#pop")
    s.rule("[^\\s']+", "Literal.String")
  })
  lx.state("double_quoted_scalar", fn(s) {
    s.rule("\"", "Literal.String", next="#pop")
    s.mix_in("quoted_scalar_whitespaces")
    // escapes
    s.rule("\\\\[0abt\\tn\\nvfre \"\\\\N_LP]", "Literal.String.Escape")
    s.rule(
      "\\\\(?:x[0-9A-Fa-f]{2}|u[0-9A-Fa-f]{4}|U[0-9A-Fa-f]{8})", "Literal.String.Escape",
    )
    s.rule("[^ \\t\\n\\r\\f\\v\"\\\\]+", "Literal.String")
  })
  lx.state("plain_scalar_in_block_context_new_line", fn(s) {
    s.rule("^[ ]+\\n", "Text")
    s.rule("\\n+", "Text", flags="m")
    s.call("^(?=---|\\.\\.\\.)", fn(lx, _) { lx.pop(times=3) })
    // dedent detection
    s.call("^[ ]*", fn(lx, m) {
      lx.token("Text")
      lx.pop()
      let size = m.matched().length()
      // dedent = end of scalar
      if size <= indent() {
        lx.pop()
        ignore(save_indent(m.matched()))
        lx.push("indentation")
      }
    })
  })
  lx.state("plain_scalar_in_block_context", fn(s) {
    // the : indicator ends a scalar
    s.rule("[ ]*(?=:[ \\n]|:$)", "Text", next="#pop")
    s.rule("[ ]*:\\S+", "Literal.String")
    s.rule("[ ]+(?=#)", "Text", next="#pop")
    s.rule("[ ]+$", "Text")
    // check for new documents or dedents at the new line
    s.call("\\n+", fn(lx, _) {
      lx.token("Text")
      lx.push("plain_scalar_in_block_context_new_line")
    })
    s.rule("[ ]+", "Literal.String")
    s.rule("true|false|null", "Name.Constant")
    s.rule("\\d+(?:\\.\\d+)?(?=(\\r?\\n)| +#)", "Literal.Number", next="#pop")
    // regular non-whitespace characters
    s.rule("[^\\s:]+", "Literal.String")
  })
  lx.state("plain_scalar_in_flow_context", fn(s) {
    s.rule("[ ]*(?=[,:?\\[\\]{}])", "Text", next="#pop")
    s.rule("[ ]+(?=#)", "Text", next="#pop")
    s.rule("^[ ]+", "Text")
    s.rule("[ ]+$", "Text")
    s.rule("\\n+", "Text")
    s.rule("[ ]+", "Name.Variable")
    s.rule("[^\\s,:?\\[\\]{}]+", "Name.Variable")
  })
  lx.state("yaml_directive", fn(s) {
    s.call("([ ]+)(\\d+\\.\\d+)", fn(lx, _) {
      lx.groups(["Text", "Literal.Number"])
      lx.goto("ignored_line")
    })
  })
  lx.state("tag_directive", fn(s) {
    s.call(
      (
        #|
        #|          ([ ]+)(!|![\w-]*!) # prefix
        #|          ([ ]+)(!|!?[\w;/?:@&=+$,.!~*'()\[\]%-]+) # tag handle
        #|
      ),
      fn(lx, _) {
        lx.groups(["Text", "Keyword.Type", "Text", "Keyword.Type"])
        lx.goto("ignored_line")
      },
      flags="x",
    )
  })
  lx
}
