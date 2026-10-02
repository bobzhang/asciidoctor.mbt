///|
/// Python's keywords (Rouge's `Python.keywords`).
let python_keywords : Array[String] = words(
  (
    #|assert break continue del elif else except exec
    #|finally for global if lambda pass print raise
    #|return try while yield as with from import yield
    #|async await nonlocal
  ),
)

///|
/// Python's builtins (Rouge's `Python.builtins`).
let python_builtins : Array[String] = words(
  (
    #|__import__ abs all any apply ascii basestring bin bool buffer
    #|bytearray bytes callable chr classmethod cmp coerce compile
    #|complex delattr dict dir divmod enumerate eval execfile exit
    #|file filter float format frozenset getattr globals hasattr hash hex id
    #|input int intern isinstance issubclass iter len list locals
    #|long map max memoryview min next object oct open ord pow property range
    #|raw_input reduce reload repr reversed round set setattr slice
    #|sorted staticmethod str sum super tuple type unichr unicode
    #|vars xrange zip
  ),
)

///|
/// Rouge's `Python.builtins_pseudo`.
let python_builtins_pseudo : Array[String] = words(
  "self None Ellipsis NotImplemented False True",
)

///|
/// Python's exceptions (Rouge's `Python.exceptions`).
let python_exceptions : Array[String] = words(
  (
    #|ArithmeticError AssertionError AttributeError
    #|BaseException BlockingIOError BrokenPipeError BufferError
    #|BytesWarning ChildProcessError ConnectionAbortedError
    #|ConnectionError ConnectionRefusedError ConnectionResetError
    #|DeprecationWarning EOFError EnvironmentError
    #|Exception FileExistsError FileNotFoundError
    #|FloatingPointError FutureWarning GeneratorExit IOError
    #|ImportError ImportWarning IndentationError IndexError
    #|InterruptedError IsADirectoryError KeyError KeyboardInterrupt
    #|LookupError MemoryError ModuleNotFoundError NameError
    #|NotADirectoryError NotImplemented NotImplementedError OSError
    #|OverflowError OverflowWarning PendingDeprecationWarning
    #|ProcessLookupError RecursionError ReferenceError ResourceWarning
    #|RuntimeError RuntimeWarning StandardError StopAsyncIteration
    #|StopIteration SyntaxError SyntaxWarning SystemError SystemExit
    #|TabError TimeoutError TypeError UnboundLocalError UnicodeDecodeError
    #|UnicodeEncodeError UnicodeError UnicodeTranslateError
    #|UnicodeWarning UserWarning ValueError VMSError Warning
    #|WindowsError ZeroDivisionError
  ),
)

///|
/// Rouge's `Python` (lexers/python.rb).
pub fn python(options : Map[String, String]) -> Lexer {
  let lx = Lexer::new("python", options~)
  lx.set_fresh(fn() { python(Map([])) })
  let identifier = rx("[[:alpha:]_][[:alnum:]_]*")
  let dotted_identifier = rx("[[:alpha:]_.][[:alnum:]_.]*")
  // the strings being lexed, innermost last: their prefix (lowercased) and
  // delimiter (Rouge's `StringRegister`, kept across lexes as Rouge does)
  let current_string : Array[(String, String)] = []
  fn string_type_is(t : String) -> Bool {
    match current_string.last() {
      Some((prefix, _)) => prefix.contains(t)
      None => abort("rouge: python: no current string")
    }
  }

  lx.state("root", fn(s) {
    s.rule("\\n+", "Text", flags="m")
    s.call(
      "^(:)(\\s*)([ru]{,2}\"\"\".*?\"\"\")",
      fn(lx, _) { lx.groups(["Punctuation", "Text", "Literal.String.Doc"]) },
      flags="mi",
    )
    s.rule("[^\\S\\n]+", "Text")
    s.rule("#(.*)?\\n?", "Comment.Single")
    s.rule("[\\[\\]{}:(),;.]", "Punctuation")
    s.rule("\\\\\\n", "Text")
    s.rule("\\\\", "Text")
    s.rule("(in|is|and|or|not)\\b", "Operator.Word")
    s.rule("(<<|>>|\\/\\/|\\*\\*)=?", "Operator")
    s.rule("[-~+\\/*%=<>&^|@]=?|!=", "Operator")
    s.call(
      "(from)((?:\\\\\\s|\\s)+)(\{dotted_identifier})((?:\\\\\\s|\\s)+)(import)",
      fn(lx, _) {
        lx.groups([
          "Keyword.Namespace", "Text", "Name.Namespace", "Text", "Keyword.Namespace",
        ])
      },
    )
    s.call("(import)(\\s+)(\{dotted_identifier})", fn(lx, _) {
      lx.groups(["Keyword.Namespace", "Text", "Name.Namespace"])
    })
    s.call("(def)((?:\\s|\\\\\\s)+)", fn(lx, _) {
      lx.groups(["Keyword", "Text"])
      lx.push("funcname")
    })
    s.call("(class)((?:\\s|\\\\\\s)+)", fn(lx, _) {
      lx.groups(["Keyword", "Text"])
      lx.push("classname")
    })
    // TODO: not in python 3
    s.rule("`.*?`", "Literal.String.Backtick")
    s.call(
      "([rfbu]{0,2})('''|\"\"\"|['\"])",
      fn(lx, m) {
        lx.groups(["Literal.String.Affix", "Literal.String"])
        current_string.push(
          (script_downcase(group_text(m, 1)), group_text(m, 2)),
        )
        lx.push("generic_string")
      },
      flags="i",
    )
    s.rule("@\{dotted_identifier}", "Name.Decorator", flags="i")
    // using negative lookbehind so we don't match property names
    s.call("(?<!\\.)\{identifier}", fn(lx, m) {
      let name = m.matched()
      if python_keywords.contains(name) {
        lx.token("Keyword")
      } else if python_exceptions.contains(name) {
        lx.token("Name.Builtin")
      } else if python_builtins.contains(name) {
        lx.token("Name.Builtin")
      } else if python_builtins_pseudo.contains(name) {
        lx.token("Name.Builtin.Pseudo")
      } else {
        lx.token("Name")
      }
    })
    s.rule(identifier, "Name")
    let digits = rx("[0-9](_?[0-9])*")
    let decimal = rx("((\{digits})?\\.\{digits}|\{digits}\\.)")
    let exponent = rx("e[+-]?\{digits}", flags="i")
    s.rule("\{decimal}(\{exponent})?j?", "Literal.Number.Float", flags="i")
    s.rule("\{digits}\{exponent}j?", "Literal.Number.Float", flags="i")
    s.rule("\{digits}j", "Literal.Number.Float", flags="i")
    s.rule("0b(_?[0-1])+", "Literal.Number.Bin", flags="i")
    s.rule("0o(_?[0-7])+", "Literal.Number.Oct", flags="i")
    s.rule("0x(_?[a-f0-9])+", "Literal.Number.Hex", flags="i")
    s.rule("\\d+L", "Literal.Number.Integer.Long")
    s.rule("([1-9](_?[0-9])*|0(_?0)*)", "Literal.Number.Integer")
  })
  lx.state("funcname", fn(s) {
    s.rule(identifier, "Name.Function", next="#pop")
  })
  lx.state("classname", fn(s) { s.rule(identifier, "Name.Class", next="#pop") })
  lx.state("raise", fn(s) {
    s.rule("from\\b", "Keyword")
    s.rule("raise\\b", "Keyword")
    s.rule("yield\\b", "Keyword")
    s.rule("\\n", "Text", next="#pop")
    s.rule(";", "Punctuation", next="#pop")
    s.mix_in("root")
  })
  lx.state("yield", fn(s) { s.mix_in("raise") })
  lx.state("generic_string", fn(s) {
    s.rule("[^'\"\\\\{]+", "Literal.String")
    s.rule("{{", "Literal.String")
    s.call("'''|\"\"\"|['\"]", fn(lx, m) {
      lx.token("Literal.String")
      match current_string.last() {
        Some((_, delim)) if delim == m.matched() => {
          ignore(current_string.pop())
          lx.pop()
        }
        Some(_) => ()
        None => abort("rouge: python: no current string")
      }
    })
    s.rule("(?=\\\\)", "Literal.String", next="generic_escape")
    s.call("{", fn(lx, _) {
      if string_type_is("f") {
        lx.token("Literal.String.Interpol")
        lx.push("generic_interpol")
      } else {
        lx.token("Literal.String")
      }
    })
  })
  lx.state("generic_escape", fn(s) {
    s.call(
      (
        #|\\
        #|          ( [\\abfnrtv"']
        #|          | \n
        #|          | newline
        #|          | N{[a-zA-Z][a-zA-Z ]+[a-zA-Z]}
        #|          | u[a-fA-F0-9]{4}
        #|          | U[a-fA-F0-9]{8}
        #|          | x[a-fA-F0-9]{2}
        #|          | [0-7]{1,3}
        #|          )
        #|
      ),
      fn(lx, _) {
        if string_type_is("r") {
          lx.token("Literal.String")
        } else {
          lx.token("Literal.String.Escape")
        }
        lx.pop()
      },
      flags="x",
    )
    s.rule("\\\\.", "Literal.String", next="#pop")
  })
  lx.state("generic_interpol", fn(s) {
    s.call("[^{}!:]+", fn(lx, m) { lx.recurse(text=m.matched()) })
    s.rule("![asr]", "Literal.String.Interpol")
    s.rule(":", "Literal.String.Interpol")
    s.rule("{", "Literal.String.Interpol", next="generic_interpol")
    s.rule("}", "Literal.String.Interpol", next="#pop")
  })
  lx
}
