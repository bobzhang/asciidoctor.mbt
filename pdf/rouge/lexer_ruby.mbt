///|
/// Ruby's `String#squeeze`: runs of the same character collapsed.
fn squeeze(s : String) -> String {
  let sb = StringBuilder()
  let mut last : Char? = None
  for c in s {
    if last != Some(c) {
      sb.write_char(c)
    }
    last = Some(c)
  }
  sb.to_string()
}

///|
fn is_ruby_space(c : Char) -> Bool {
  c == ' ' ||
  c == '\t' ||
  c == '\n' ||
  c == '\u{0B}' ||
  c == '\u{0C}' ||
  c == '\r' ||
  c == '\u{00}'
}

///|
/// Ruby's `String#strip`.
fn ruby_strip(s : String) -> String {
  s.trim(char_set=" \t\n\u{0B}\u{0C}\r\u{00}").to_owned()
}

///|
/// Ruby's `String#rstrip`.
fn ruby_rstrip(s : String) -> String {
  let mut end = s.length()
  while end > 0 &&
        is_ruby_space(s.unsafe_get(end - 1).to_int().unsafe_to_char()) {
    end -= 1
  }
  s.unsafe_substring(start=0, end~)
}

///|
/// Rouge's `Ruby` (lexers/ruby.rb).
pub fn ruby(options : Map[String, String]) -> Lexer {
  let lx = Lexer::new("ruby", options~)
  lx.set_fresh(fn() { ruby(Map([])) })
  // the heredocs opened on the current line: whether the terminator may be
  // indented (`<<-`, `<<~`), and the terminator
  let heredoc_queue : Array[(Bool, String)] = []
  // where the queue starts (Ruby's `shift`, without moving the rest)
  let heredoc_head = Ref(0)
  lx.state("symbols", fn(s) {
    // symbols
    s.rule(
      (
        #|
        #|          :  # initial :
        #|          @{0,2} # optional ivar, for :@foo and :@@foo
        #|          [a-z_]\w*[!?]? # the symbol
        #|
      ),
      "Literal.String.Symbol",
      flags="xi",
    )
    // special symbols
    s.rule(
      ":(?:\\*\\*|[-+]@|[/\\%&\\|^`~]|\\[\\]=?|<<|>>|<=?>|<=?|===?)", "Literal.String.Symbol",
    )
    s.rule(":'(\\\\\\\\|\\\\'|[^'])*'", "Literal.String.Symbol")
    s.rule(":\"", "Literal.String.Symbol", next="simple_sym")
  })
  lx.state("sigil_strings", fn(s) {
    // %-sigiled strings
    // %(abc), %[abc], %<abc>, %.abc., %r.abc., etc
    s.call("%([rqswQWxiI])?([^\\w\\s])", fn(lx, m) {
      let delim = group_text(m, 2)
      let open = rx_escape(delim)
      let close = rx_escape(
        match delim {
          "{" => "}"
          "[" => "]"
          "(" => ")"
          "<" => ">"
          d => d
        },
      )
      let interp = match m.group(1) {
        Some("r" | "Q" | "W" | "x" | "I") => true
        _ => false
      }
      let mut toktype = "Literal.String.Other"
      // regexes
      if m.group(1) == Some("r") {
        toktype = "Literal.String.Regex"
        lx.push("regex_flags")
      }
      lx.token(toktype)
      let toktype = toktype
      lx.push_rules(fn(s) {
        let uniq_chars = if open == close && open == "\\#" {
          ""
        } else {
          squeeze(open + close)
        }
        s.rule("\\\\[#\{uniq_chars}\\\\]", "Literal.String.Escape")
        // nesting rules only with asymmetric delimiters
        if open != close {
          s.call(open, fn(lx, _) {
            lx.token(toktype)
            lx.push_self()
          })
        }
        s.rule(close, toktype, next="#pop")
        if interp {
          s.mix_in("string_intp_escaped")
          s.rule("#", toktype)
        } else {
          s.rule("[\\\\#]", toktype)
        }
        s.rule("[^#\{uniq_chars}\\\\]+", toktype, flags="m")
      })
    })
  })
  lx.state("strings", fn(s) {
    s.mix_in("symbols")
    s.rule(
      "\\b[a-z_]\\w*?[?!]?:\\s+",
      "Literal.String.Symbol",
      next="expr_start",
    )
    s.rule("'(\\\\\\\\|\\\\'|[^'])*'", "Literal.String.Single")
    s.rule("\"", "Literal.String.Double", next="simple_string")
    s.rule("(?<!\\.)`", "Literal.String.Backtick", next="simple_backtick")
  })
  lx.state("regex_flags", fn(s) {
    s.rule("[mixounse]*", "Literal.String.Regex", next="#pop")
  })
  // double-quoted string and symbol
  for
    spec in [
      ("string", "Literal.String.Double", "\""),
      ("sym", "Literal.String.Symbol", "\""),
      ("backtick", "Literal.String.Backtick", "`"),
    ] {
    let (name, tok, fin) = spec
    lx.state("simple_" + name, fn(s) {
      s.mix_in("string_intp_escaped")
      s.rule("[^\\\\\{fin}#]+", tok, flags="m")
      s.rule("[\\\\#]", tok)
      s.rule(fin, tok, next="#pop")
    })
  }
  let keywords = words(
    (
      #|BEGIN END alias begin break case defined\? do else elsif end
      #|ensure for if in next redo rescue raise retry return super then
      #|undef unless until when while yield
    ),
  )
  let keywords_pseudo = words(
    (
      #|loop include extend raise
      #|alias_method attr catch throw private module_function
      #|public protected true false nil __FILE__ __LINE__
    ),
  )
  let builtins_g = words(
    (
      #|attr_reader attr_writer attr_accessor
      #|
      #|__id__ __send__ abort ancestors at_exit autoload binding callcc
      #|caller catch chomp chop class_eval class_variables clone
      #|const_defined\? const_get const_missing const_set constants
      #|display dup eval exec exit extend fail fork format freeze
      #|getc gets global_variables gsub hash id included_modules
      #|inspect instance_eval instance_method instance_methods
      #|instance_variable_get instance_variable_set instance_variables
      #|lambda load local_variables loop method method_missing
      #|methods module_eval name object_id open p print printf
      #|private_class_method private_instance_methods private_methods proc
      #|protected_instance_methods protected_methods public_class_method
      #|public_instance_methods public_methods putc puts raise rand
      #|readline readlines require require_relative scan select self send set_trace_func
      #|singleton_methods sleep split sprintf srand sub syscall system
      #|taint test throw to_a to_s trace_var trap untaint untrace_var warn
    ),
  )
  let builtins_q = words(
    (
      #|autoload block_given const_defined eql equal frozen
      #|include instance_of is_a iterator kind_of method_defined
      #|nil private_method_defined protected_method_defined
      #|public_method_defined respond_to tainted
    ),
  )
  let builtins_b = words("chomp chop exit gsub sub")
  lx.start(fn(lx) {
    lx.push("expr_start")
    heredoc_queue.clear()
    heredoc_head.val = 0
  })
  lx.state("whitespace", fn(s) {
    s.mix_in("inline_whitespace")
    s.rule("\\n\\s*", "Text", flags="m", next="expr_start")
    s.rule("#.*$", "Comment.Single")
    s.rule("=begin\\b.*?\\n=end\\b", "Comment.Multiline", flags="m")
  })
  lx.state("inline_whitespace", fn(s) { s.rule("[ \\t\\r]+", "Text") })
  lx.state("root", fn(s) {
    s.mix_in("whitespace")
    s.rule("__END__", "Comment.Preproc", next="end_part")
    s.rule("0_?[0-7]+(?:_[0-7]+)*", "Literal.Number.Oct")
    s.rule("0x[0-9A-Fa-f]+(?:_[0-9A-Fa-f]+)*", "Literal.Number.Hex")
    s.rule("0b[01]+(?:_[01]+)*", "Literal.Number.Bin")
    let decimal = rx("[\\d]+(?:_\\d+)*")
    let exp = rx("e[+-]?\\d+", flags="i")
    s.rule("\{decimal}(?:\\.\{decimal}\{exp}?|\{exp})", "Literal.Number.Float")
    s.rule(decimal, "Literal.Number.Integer")
    // names
    s.rule("@@[a-z_]\\w*", "Name.Variable.Class", flags="i")
    s.rule("@[a-z_]\\w*", "Name.Variable.Instance", flags="i")
    s.rule("\\$\\w+", "Name.Variable.Global")
    s.rule("\\$[!@&`'+~=/\\\\,;.<>_*\\$?:\"]", "Name.Variable.Global")
    s.rule("\\$-[0adFiIlpvw]", "Name.Variable.Global")
    s.rule("::", "Operator")
    s.mix_in("strings")
    s.rule("(?:\{alt(keywords)})(?=\\W|$)", "Keyword", next="expr_start")
    s.rule(
      "(?:\{alt(keywords_pseudo)})\\b",
      "Keyword.Pseudo",
      next="expr_start",
    )
    s.call(
      (
        #|
        #|          (module)
        #|          (\s+)
        #|          ([a-zA-Z_][a-zA-Z0-9_]*(::[a-zA-Z_][a-zA-Z0-9_]*)*)
        #|
      ),
      fn(lx, _) { lx.groups(["Keyword", "Text", "Name.Namespace"]) },
      flags="x",
    )
    s.call("(def\\b)(\\s*)", fn(lx, _) {
      lx.groups(["Keyword", "Text"])
      lx.push("funcname")
    })
    s.call("(class\\b)(\\s*)", fn(lx, _) {
      lx.groups(["Keyword", "Text"])
      lx.push("classname")
    })
    s.rule("(?:\{alt(builtins_q)})[?]", "Name.Builtin", next="expr_start")
    s.rule("(?:\{alt(builtins_b)})!", "Name.Builtin", next="expr_start")
    s.rule(
      "(?<!\\.)(?:\{alt(builtins_g)})\\b",
      "Name.Builtin",
      next="method_call",
    )
    s.mix_in("has_heredocs")
    // `..` and `...` for ranges must have higher priority than `.`
    // Otherwise, they will be parsed as :method_call
    s.rule("\\.{2,3}", "Operator", next="expr_start")
    s.rule("[A-Z][a-zA-Z0-9_]*", "Name.Constant", next="method_call")
    s.call("(\\.|::)(\\s*)([a-z_]\\w*[!?]?|[*%&^`~+-\\/\\[<>=])", fn(lx, _) {
      lx.groups(["Punctuation", "Text", "Name.Function"])
      lx.push("method_call")
    })
    s.rule("[a-zA-Z_]\\w*[?!]", "Name", next="expr_start")
    s.rule("[a-zA-Z_]\\w*", "Name", next="method_call")
    s.rule(
      "\\*\\*|<<?|>>?|>=|<=|<=>|=~|={3}|!~|&&?|\\|\\||\\.",
      "Operator",
      next="expr_start",
    )
    s.rule("[-+\\/*%=<>&!^|~]=?", "Operator", next="expr_start")
    s.call("[?]", fn(lx, _) {
      lx.token("Punctuation")
      lx.push("ternary")
      lx.push("expr_start")
    })
    s.rule("[\\[({,:\\\\;/]", "Punctuation", next="expr_start")
    s.rule("[\\])}]", "Punctuation")
  })
  lx.state("has_heredocs", fn(s) {
    s.call("(?<!\\w)(<<[-~]?)([\"`']?)([a-zA-Z_]\\w*)(\\2)", fn(lx, m) {
      lx.token("Operator", val=group_text(m, 1))
      lx.token(
        "Name.Constant",
        val=group_text(m, 2) + group_text(m, 3) + group_text(m, 4),
      )
      let op = group_text(m, 1)
      heredoc_queue.push((op == "<<-" || op == "<<~", group_text(m, 3)))
      if !lx.state_is("heredoc_queue") {
        lx.push("heredoc_queue")
      }
    })
    s.call("(<<[-~]?)([\"'])(\\2)", fn(lx, m) {
      lx.token("Operator", val=group_text(m, 1))
      lx.token("Name.Constant", val=group_text(m, 2) + group_text(m, 3))
      let op = group_text(m, 1)
      heredoc_queue.push((op == "<<-" || op == "<<~", ""))
      if !lx.state_is("heredoc_queue") {
        lx.push("heredoc_queue")
      }
    })
  })
  lx.state("heredoc_queue", fn(s) {
    s.call("(?=\\n)", fn(lx, _) { lx.goto("resolve_heredocs") })
    s.mix_in("root")
  })
  lx.state("resolve_heredocs", fn(s) {
    s.mix_in("string_intp_escaped")
    s.rule("\\n", "Literal.String.Heredoc", next="test_heredoc")
    s.rule("[#\\\\\\n]", "Literal.String.Heredoc")
    s.rule("[^#\\\\\\n]+", "Literal.String.Heredoc")
  })
  lx.state("test_heredoc", fn(s) {
    s.call("[^#\\\\\\n]*$", fn(lx, m) {
      let check = match heredoc_queue.get(heredoc_head.val) {
        Some((true, _)) => Some(ruby_strip(m.matched()))
        Some((false, _)) => Some(ruby_rstrip(m.matched()))
        None => None
      }
      // check if we found the end of the heredoc
      if check is Some(c) &&
        heredoc_queue.get(heredoc_head.val) is Some((_, name)) &&
        c == name {
        heredoc_head.val += 1
        // if there's no more, we're done looking.
        if heredoc_head.val >= heredoc_queue.length() {
          lx.pop()
        }
        lx.token("Name.Constant")
      } else {
        lx.token("Literal.String.Heredoc")
      }
      lx.pop()
    })
    s.call("", fn(lx, _) { lx.pop() })
  })
  lx.state("funcname", fn(s) {
    s.rule("\\s+", "Text")
    s.rule("\\(", "Punctuation", next="defexpr")
    s.call(
      (
        #|
        #|          (?:([a-zA-Z_]\w*)(\.))?
        #|          (
        #|            [a-zA-Z_]\w*[!?]? |
        #|            \*\*? | [-+]@? | [/%&\|^`~] | \[\]=? |
        #|            <<? | >>? | <=>? | >= | ===?
        #|          )
        #|
      ),
      fn(lx, _) {
        lx.groups(["Name.Class", "Operator", "Name.Function"])
        lx.pop()
      },
      flags="x",
    )
    s.call("", fn(lx, _) { lx.pop() })
  })
  lx.state("classname", fn(s) {
    s.rule("\\s+", "Text")
    s.rule("\\w+(::\\w+)+", "Name.Class")
    s.call("\\(", fn(lx, _) {
      lx.token("Punctuation")
      lx.push("defexpr")
      lx.push("expr_start")
    })
    // class << expr
    s.call("<<", fn(lx, _) {
      lx.token("Operator")
      lx.goto("expr_start")
    })
    s.rule("[A-Z_]\\w*", "Name.Class", next="#pop")
    s.call("", fn(lx, _) { lx.pop() })
  })
  lx.state("ternary", fn(s) {
    s.call("(:)(\\s+)", fn(lx, _) {
      lx.groups(["Punctuation", "Text"])
      lx.goto("expr_start")
    })
    s.call(":(?![^#\\n]*?[:\\\\])", fn(lx, _) {
      lx.token("Punctuation")
      lx.goto("expr_start")
    })
    s.mix_in("root")
  })
  lx.state("defexpr", fn(s) {
    s.call("(\\))(\\.|::)?", fn(lx, _) {
      lx.groups(["Punctuation", "Operator"])
      lx.pop()
    })
    s.call("\\(", fn(lx, _) {
      lx.token("Punctuation")
      lx.push("defexpr")
      lx.push("expr_start")
    })
    s.mix_in("root")
  })
  lx.state("in_interp", fn(s) {
    s.rule("}", "Literal.String.Interpol", next="#pop")
    s.mix_in("root")
  })
  lx.state("string_intp", fn(s) {
    s.rule("[#][{]", "Literal.String.Interpol", next="in_interp")
    s.rule("#(@@?|\\$)[a-z_]\\w*", "Literal.String.Interpol", flags="i")
  })
  lx.state("string_intp_escaped", fn(s) {
    s.mix_in("string_intp")
    s.rule(
      "\\\\([\\\\abefnrstv#\"']|x[a-fA-F0-9]{1,2}|[0-7]{1,3})", "Literal.String.Escape",
    )
    s.rule("\\\\.", "Literal.String.Escape")
  })
  lx.state("method_call", fn(s) {
    s.call("/|%", fn(lx, _) {
      lx.token("Operator")
      lx.goto("expr_start")
    })
    s.call("(?=\\n)", fn(lx, _) { lx.pop() })
    s.call("", fn(lx, _) { lx.goto("method_call_spaced") })
  })
  lx.state("method_call_spaced", fn(s) {
    s.mix_in("whitespace")
    s.call("[%/]=", fn(lx, _) {
      lx.token("Operator")
      lx.goto("expr_start")
    })
    s.call("(/)(?=\\S|\\s*/)", fn(lx, _) {
      lx.token("Literal.String.Regex")
      lx.goto("slash_regex")
    })
    s.mix_in("sigil_strings")
    s.call("(?=\\s*/)", fn(lx, _) { lx.pop() })
    s.call("\\s+", fn(lx, _) {
      lx.token("Text")
      lx.goto("expr_start")
    })
    s.call("", fn(lx, _) { lx.pop() })
  })
  lx.state("expr_start", fn(s) {
    s.mix_in("inline_whitespace")
    s.call("/", fn(lx, _) {
      lx.token("Literal.String.Regex")
      lx.goto("slash_regex")
    })
    // char operator.  ?x evaulates to "x", unless there's a digit
    // beforehand like x>=0?n[x]:""
    s.rule(
      (
        #|
        #|          [?](\\[MC]-)*     # modifiers
        #|          (\\([\\abefnrstv\#"']|x[a-fA-F0-9]{1,2}|[0-7]{1,3})|\S)
        #|          (?!\w)
        #|
      ),
      "Literal.String.Char",
      flags="x",
      next="#pop",
    )
    // special case for using a single space.  Ruby demands that these be
    // in a single line, otherwise it would make no sense.
    s.call("(\\s*)(%[rqswQWxiI]? \\S* )", fn(lx, _) {
      lx.groups(["Text", "Literal.String.Other"])
      lx.pop()
    })
    s.mix_in("sigil_strings")
    s.call("", fn(lx, _) { lx.pop() })
  })
  lx.state("slash_regex", fn(s) {
    s.mix_in("string_intp")
    s.rule("\\\\\\\\", "Literal.String.Regex")
    s.rule("\\\\/", "Literal.String.Regex")
    s.rule("[\\\\#]", "Literal.String.Regex")
    s.rule("[^\\\\/#]+", "Literal.String.Regex", flags="m")
    s.call("/", fn(lx, _) {
      lx.token("Literal.String.Regex")
      lx.goto("regex_flags")
    })
  })
  lx.state("end_part", fn(s) {
    // eat up the rest of the stream as Comment::Preproc
    s.rule(".+", "Comment.Preproc", flags="m", next="#pop")
  })
  lx
}
