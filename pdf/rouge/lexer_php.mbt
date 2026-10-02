///|
/// PHP's keywords (Rouge's `PHP.keywords`).
let php_keywords : Set[String] = word_set(
  (
    #|old_function cfunction
    #|__class__ __dir__ __file__ __function__ __halt_compiler __line__
    #|__method__ __namespace__ __trait__ abstract and array as break case
    #|catch clone continue declare default die do echo else elseif empty
    #|enddeclare endfor endforeach endif endswitch endwhile eval exit
    #|extends final finally fn for foreach global goto if implements
    #|include include_once instanceof insteadof isset list match new or
    #|parent print private protected public readonly require require_once
    #|return self static switch throw try unset var while xor yield
  ),
)

///|
/// Rouge's `PHP` (lexers/php.rb), a `TemplateLexer`: the text outside
/// `<?php ... ?>` goes to the parent lexer, HTML (plain text when the HTML
/// lexer is not ported).
///
/// Options: `start_inline` (start in PHP code; unset: guess from the text),
/// `funcnamehighlighting` (default true), `disabledmodules` (builtin
/// modules not to highlight).
pub fn php(options : Map[String, String]) -> Lexer {
  let lx = Lexer::new("php", options~)
  // true, false, or None to guess
  let start_inline = match lx.options.get("start_inline") {
    Some(v) => Some(option_bool(v))
    None => None
  }
  let funcnamehighlighting = lx.bool_option("funcnamehighlighting", true)
  let disabledmodules = lx.list_option("disabledmodules").unwrap_or([])
  // the parent (TemplateLexer#parent): the lexer the `parent` option names,
  // else HTML, with the options left
  let parent = match lx.string_option("parent") {
    Some(name) if script_find(name) is Some(f) => f(lx.options.copy())
    _ => script_lexer_or_text("html", lx.options.copy())
  }
  let builtins : Set[String] = Set([])
  if funcnamehighlighting {
    for entry in php_builtins {
      if !disabledmodules.contains(entry.0) {
        for f in entry.1 {
          builtins.add(f)
        }
      }
    }
  }
  let id = rx("[\\p{L}_][\\p{L}\\p{N}_]*")
  let ns = rx("(?:\{id}\\\\)+")
  let id_with_ns = rx("(?:\{ns})?\{id}")
  lx.start(fn(_) { parent.reset() })
  lx.start(fn(lx) {
    match start_inline {
      Some(true) => lx.push("php")
      None => lx.push("start")
      Some(false) => ()
    }
  })
  lx.state("escape", fn(s) {
    s.call("\\?>", fn(lx, _) {
      lx.token("Comment.Preproc")
      lx.reset_stack()
    })
  })
  lx.state("return", fn(s) { s.call("", fn(lx, _) { lx.pop() }) })
  lx.state("start", fn(s) {
    // We enter this state if we aren't sure whether the PHP in the text is
    // delimited by <?php (or <?=) tags or not. These two rules check
    // whether there is an opening angle bracket and, if there is, delegates
    // the tokens before it to the HTML lexer.
    s.call(
      "\\s*(?=<)",
      fn(lx, _) {
        lx.delegate(parent)
        lx.pop()
      },
      flags="m",
    )
    s.call(
      "[^$]+(?=<\\?(php|=))",
      fn(lx, _) {
        lx.delegate(parent)
        lx.pop()
      },
      flags="i",
    )
    s.call("", fn(lx, _) { lx.goto("php") })
  })
  lx.state("names", fn(s) {
    s.call("\{id_with_ns}(?=\\s*\\()", fn(lx, m) {
      let name = script_downcase(m.matched())
      if php_keywords.contains(name) {
        lx.token("Keyword")
      } else if builtins.contains(name) {
        lx.token("Name.Builtin")
      } else {
        lx.token("Name.Function")
      }
    })
    s.call(id_with_ns, fn(lx, m) {
      let text = m.matched()
      let name = script_downcase(text)
      if name == "use" {
        lx.push("in_use")
        lx.token("Keyword.Namespace")
      } else if name == "const" {
        lx.push("in_const")
        lx.token("Keyword")
      } else if name == "catch" {
        lx.push("in_catch")
        lx.token("Keyword")
      } else if name == "public" || name == "protected" || name == "private" {
        lx.push("in_visibility")
        lx.token("Keyword")
      } else if name == "stdClass" {
        lx.token("Name.Class")
      } else if php_keywords.contains(name) {
        lx.token("Keyword")
      } else if script_match("^__.*?__$", text) {
        lx.token("Name.Builtin")
      } else if script_match("^(E|PHP)(_[[:upper:]]+)+$", text) {
        lx.token("Keyword.Constant")
      } else if script_match(
          "(\\\\|^)[[:upper:]][[[:upper:]][[:digit:]]_]+$", text,
        ) {
        lx.token("Name.Constant")
      } else if script_match("(\\\\|^)[[:upper:]][[:alnum:]]*?$", text) {
        lx.token("Name.Class")
      } else {
        lx.token("Name")
      }
    })
  })
  lx.state("operators", fn(s) { s.rule("[~!%^&*+\\|:.<>\\/@-]+", "Operator") })
  lx.state("string", fn(s) {
    s.rule("\"", "Literal.String.Double", next="#pop")
    s.rule("[^\\\\{$\"]+", "Literal.String.Double")
    s.rule("\\\\u\\{[0-9a-fA-F]+\\}", "Literal.String.Escape")
    s.rule(
      "\\\\([efrntv\\\"$\\\\]|[0-7]{1,3}|[xX][0-9a-fA-F]{1,2})", "Literal.String.Escape",
    )
    s.rule("\\$\{id}(\\[\\S+\\]|->\{id})?", "Name.Variable")
    s.rule("\\{\\$\\{", "Literal.String.Interpol", next="string_interp_double")
    s.rule("\\{(?=\\$)", "Literal.String.Interpol", next="string_interp_single")
    s.call("(\\{)(\\S+)(\\})", fn(lx, _) {
      lx.groups([
        "Literal.String.Interpol", "Name.Variable", "Literal.String.Interpol",
      ])
    })
    s.rule("[${\\\\]+", "Literal.String.Double")
  })
  lx.state("string_interp_double", fn(s) {
    s.rule("\\}\\}", "Literal.String.Interpol", next="#pop")
    s.mix_in("php")
  })
  lx.state("string_interp_single", fn(s) {
    s.rule("\\}", "Literal.String.Interpol", next="#pop")
    s.mix_in("php")
  })
  lx.state("values", fn(s) {
    // heredocs
    s.rule(
      "<<<([\"']?)(\{id})\\1\\n.*?\\n\\s*\\2;?",
      "Literal.String.Heredoc",
      flags="im",
    )
    // numbers
    s.rule(
      "(\\d[_\\d]*)?\\.(\\d[_\\d]*)?(e[+-]?\\d[_\\d]*)?",
      "Literal.Number.Float",
      flags="i",
    )
    s.rule("0[0-7][0-7_]*", "Literal.Number.Oct")
    s.rule("0b[01][01_]*", "Literal.Number.Bin", flags="i")
    s.rule("0x[a-f0-9][a-f0-9_]*", "Literal.Number.Hex", flags="i")
    s.rule("\\d[_\\d]*", "Literal.Number.Integer")
    // strings
    s.rule("'([^'\\\\]*(?:\\\\.[^'\\\\]*)*)'", "Literal.String.Single")
    s.rule("`([^`\\\\]*(?:\\\\.[^`\\\\]*)*)`", "Literal.String.Backtick")
    s.rule("\"", "Literal.String.Double", next="string")
    // functions
    s.call(
      "(function|fn)\\b",
      fn(lx, _) {
        lx.push("in_function_return")
        lx.push("in_function_params")
        lx.push("in_function_name")
        lx.token("Keyword")
      },
      flags="i",
    )
    // constants
    s.rule("(true|false|null)\\b", "Keyword.Constant", flags="i")
    // objects
    s.rule("new\\b", "Keyword", flags="i", next="in_new")
  })
  lx.state("variables", fn(s) {
    s.rule("\\$\\{\\$+\{id}\\}", "Name.Variable")
    s.rule("\\$+\{id}", "Name.Variable")
  })
  lx.state("whitespace", fn(s) {
    s.rule("\\s+", "Text")
    s.rule("#.*?$", "Comment.Single")
    s.rule("//.*?$", "Comment.Single")
    s.rule("/\\*\\*(?!/).*?\\*/", "Comment.Doc", flags="m")
    s.rule("/\\*.*?\\*/", "Comment.Multiline", flags="m")
  })
  lx.state("root", fn(s) {
    s.rule("<\\?(php|=)?", "Comment.Preproc", flags="i", next="php")
    s.call(".*?(?=<\\?)|.*", fn(lx, _) { lx.delegate(parent) }, flags="m")
  })
  lx.state("php", fn(s) {
    s.mix_in("escape")
    s.mix_in("whitespace")
    s.mix_in("variables")
    s.mix_in("values")
    s.call(
      (
        #|(namespace)
        #|                (\s+)
      ) +
      "                (\{id_with_ns})",
      fn(lx, _) { lx.groups(["Keyword.Namespace", "Text", "Name.Namespace"]) },
      flags="ix",
    )
    s.call(
      (
        #|(class|interface|trait|extends|implements)
        #|                (\s+)
      ) +
      "                (\{id_with_ns})",
      fn(lx, _) { lx.groups(["Keyword.Declaration", "Text", "Name.Class"]) },
      flags="ix",
    )
    s.mix_in("names")
    s.rule("[;,\\(\\)\\{\\}\\[\\]]", "Punctuation")
    s.mix_in("operators")
    s.rule("[=?]", "Operator")
  })
  lx.state("in_assign", fn(s) {
    s.rule(",", "Punctuation", next="#pop")
    s.rule("[\\[\\]]", "Punctuation")
    s.rule("\\(", "Punctuation", next="in_assign_function")
    s.mix_in("escape")
    s.mix_in("whitespace")
    s.mix_in("values")
    s.mix_in("variables")
    s.mix_in("names")
    s.mix_in("operators")
    s.mix_in("return")
  })
  lx.state("in_assign_function", fn(s) {
    s.rule("\\)", "Punctuation", next="#pop")
    s.rule(",", "Punctuation")
    s.mix_in("in_assign")
  })
  lx.state("in_catch", fn(s) {
    s.rule("\\(", "Punctuation")
    s.rule("\\|", "Operator")
    s.rule(id, "Name.Class")
    s.mix_in("escape")
    s.mix_in("whitespace")
    s.mix_in("return")
  })
  lx.state("in_const", fn(s) {
    s.rule(id, "Name.Constant")
    s.rule("=", "Operator", next="in_assign")
    s.mix_in("escape")
    s.mix_in("whitespace")
    s.mix_in("return")
  })
  lx.state("in_function_body", fn(s) {
    s.rule("{", "Punctuation", next="#push")
    s.rule("}", "Punctuation", next="#pop")
    s.mix_in("php")
  })
  lx.state("in_function_name", fn(s) {
    s.rule("&", "Operator")
    s.rule(id, "Name")
    s.rule("\\(", "Punctuation", next="#pop")
    s.mix_in("escape")
    s.mix_in("whitespace")
    s.mix_in("return")
  })
  lx.state("in_function_params", fn(s) {
    s.rule("\\)", "Punctuation", next="#pop")
    s.rule(",", "Punctuation")
    s.rule("[.]{3}", "Punctuation")
    s.rule("=", "Operator", next="in_assign")
    s.rule("\\b(?:public|protected|private|readonly)\\b", "Keyword", flags="i")
    s.rule("\\??\{id}", "Keyword.Type", next="in_assign")
    s.mix_in("escape")
    s.mix_in("whitespace")
    s.mix_in("variables")
    s.mix_in("return")
  })
  lx.state("in_function_return", fn(s) {
    s.rule(":", "Punctuation")
    s.rule("use\\b", "Keyword", flags="i", next="in_function_use")
    s.rule("\\??\{id}", "Keyword.Type", next="in_assign")
    s.call("\\{", fn(lx, _) {
      lx.token("Punctuation")
      lx.goto("in_function_body")
    })
    s.mix_in("escape")
    s.mix_in("whitespace")
    s.mix_in("return")
  })
  lx.state("in_function_use", fn(s) {
    s.rule("[,\\(]", "Punctuation")
    s.rule("&", "Operator")
    s.rule("\\)", "Punctuation", next="#pop")
    s.mix_in("escape")
    s.mix_in("whitespace")
    s.mix_in("variables")
    s.mix_in("return")
  })
  lx.state("in_new", fn(s) {
    s.call(
      "class\\b",
      fn(lx, _) {
        lx.token("Keyword.Declaration")
        lx.goto("in_new_class")
      },
      flags="i",
    )
    s.rule(id_with_ns, "Name.Class", next="#pop")
    s.mix_in("escape")
    s.mix_in("whitespace")
    s.mix_in("return")
  })
  lx.state("in_new_class", fn(s) {
    s.rule("\\}", "Punctuation", next="#pop")
    s.rule("\\{", "Punctuation")
    s.mix_in("php")
  })
  lx.state("in_use", fn(s) {
    s.rule("[,\\}]", "Punctuation")
    s.rule("(function|const)\\b", "Keyword", flags="i")
    s.call("(\{ns})(\\{)", fn(lx, _) {
      lx.groups(["Name.Namespace", "Punctuation"])
    })
    s.rule("\{id_with_ns}(_\{id})+", "Name.Function")
    s.mix_in("escape")
    s.mix_in("whitespace")
    s.mix_in("names")
    s.mix_in("return")
  })
  lx.state("in_visibility", fn(s) {
    s.rule("\\b(?:readonly|static)\\b", "Keyword", flags="i")
    s.rule(
      "(?=(abstract|const|function)\\b)",
      "Keyword",
      flags="i",
      next="#pop",
    )
    s.rule("\\??\{id}", "Keyword.Type", next="#pop")
    s.mix_in("escape")
    s.mix_in("whitespace")
    s.mix_in("return")
  })
  lx
}
