///|
/// Rouge's `Sass` (lexers/sass.rb), with the `Indentation` helpers of
/// util.rb.
pub fn sass(options : Map[String, String]) -> Lexer {
  let lx = Lexer::new("sass", options~)
  sass_common_states(lx)
  // Indentation's @block_state, @block_indentation, @last_indentation
  let mut block_state : String? = None
  let mut block_indentation : String? = None
  let mut last_indentation : String? = None
  lx.start(fn(_) {
    block_state = None
    block_indentation = None
  })
  // push a state for the next indented block
  fn starts_block(state : String) {
    block_state = Some(state)
    block_indentation = Some(last_indentation.unwrap_or(""))
  }

  // handle a single indented line
  fn indentation(lx : Lexer, indent_str : String) {
    last_indentation = Some(indent_str)
    // if it's an indent and we know where to go next, push that state.
    // otherwise, push content and clear the block state.
    match (block_state, block_indentation) {
      (Some(state), Some(block)) if indent_str.has_prefix(block) &&
        indent_str != block => lx.push(state)
      _ => {
        block_state = None
        block_indentation = None
        lx.push("content")
      }
    }
  }

  let id = rx("[\\w-]+")
  lx.state("root", fn(s) {
    s.rule("[ \\t]*\\n", "Text")
    s.call("[ \\t]*", fn(lx, m) {
      lx.token("Text")
      indentation(lx, m.matched())
    })
  })
  lx.state("content", fn(s) {
    // block comments
    s.call("//.*?$", fn(lx, _) {
      lx.token("Comment.Single")
      lx.pop()
      starts_block("single_comment")
    })
    s.call("/[*].*?\\n", fn(lx, _) {
      lx.token("Comment.Multiline")
      lx.pop()
      starts_block("multi_comment")
    })
    s.rule("@import\\b", "Keyword", next="import")
    s.mix_in("content_common")
    s.rule("=\{id}", "Name.Function", next="value")
    s.rule("[+]\{id}", "Name.Decorator", next="value")
    s.rule(":", "Name.Attribute", next="old_style_attr")
    s.call("(?=[^\\[\\n]+?:([^a-z]|$))", fn(lx, _) { lx.push("attribute") })
    s.call("", fn(lx, _) { lx.push("selector") })
  })
  lx.state("single_comment", fn(s) {
    s.rule(".*?$", "Comment.Single", next="#pop")
  })
  lx.state("multi_comment", fn(s) {
    s.rule(".*?\\n", "Comment.Multiline", next="#pop")
  })
  lx.state("import", fn(s) {
    s.rule("[ \\t]+", "Text")
    s.rule("\\S+", "Literal.String")
    s.rule("\\n", "Text", next="#pop")
  })
  lx.state("old_style_attr", fn(s) {
    s.mix_in("attr_common")
    s.call("", fn(lx, _) {
      lx.pop()
      lx.push("value")
    })
  })
  lx.state("end_section", fn(s) {
    s.call("\\n", fn(lx, _) {
      lx.token("Text")
      lx.reset_stack()
    })
  })
  lx
}
