///|
/// The word lists of a JavaScript-like lexer (Rouge's `self.keywords`,
/// `self.declarations`... class methods, which TypeScript and TSX extend).
priv struct JsWords {
  keywords : Set[String]
  declarations : Set[String]
  reserved : Set[String]
  constants : Set[String]
  builtins : Set[String]
}

///|
let js_keywords_src : String =
  #|as async await break case catch continue debugger default delete
  #|do else export finally from for if import in instanceof new of
  #|return super switch this throw try typeof void while yield

///|
let js_declarations_src : String =
  #|var let const with function class
  #|extends constructor get set static

///|
let js_reserved_src : String =
  #|enum implements interface
  #|package private protected public

///|
let js_constants_src : String = "true false null NaN Infinity undefined"

///|
let js_builtins_src : String =
  #|Array Boolean Date Error Function Math netscape
  #|Number Object Packages RegExp String sun decodeURI
  #|decodeURIComponent encodeURI encodeURIComponent
  #|Error eval isFinite isNaN parseFloat parseInt
  #|document window navigator self global
  #|Promise Set Map WeakSet WeakMap Symbol Proxy Reflect
  #|Int8Array Uint8Array Uint8ClampedArray
  #|Int16Array Uint16Array Uint16ClampedArray
  #|Int32Array Uint32Array Uint32ClampedArray
  #|Float32Array Float64Array DataView ArrayBuffer

///|
let js_words : JsWords = {
  keywords: word_set(js_keywords_src),
  declarations: word_set(js_declarations_src),
  reserved: word_set(js_reserved_src),
  constants: word_set(js_constants_src),
  builtins: word_set(js_builtins_src),
}

///|
/// `Javascript.id_regex` (flags `i`).
let js_id_src : String = "[\\p{L}\\p{Nl}$_][\\p{Word}]*"

///|
/// Rouge's `Javascript` (lexers/javascript.rb).
pub fn javascript(options : Map[String, String]) -> Lexer {
  let lx = Lexer::new("javascript", options~)
  javascript_states(lx, js_words)
  lx
}

///|
/// The states of Rouge's `Javascript`, shared with its subclasses
/// (TypeScript, JSX, TSX), which differ in their word lists.
fn javascript_states(lx : Lexer, w : JsWords) -> Unit {
  let id = rx(js_id_src, flags="i")
  lx.state("multiline_comment", fn(s) {
    s.rule("[*]/", "Comment.Multiline", next="#pop")
    s.rule("[^*/]+", "Comment.Multiline")
    s.rule("[*/]", "Comment.Multiline")
  })
  lx.state("comments_and_whitespace", fn(s) {
    s.rule("\\s+", "Text")
    s.rule("<!--", "Comment") // really...?
    s.rule("//.*?$", "Comment.Single")
    s.rule("/[*]", "Comment.Multiline", next="multiline_comment")
  })
  lx.state("expr_start", fn(s) {
    s.mix_in("comments_and_whitespace")
    s.call("/", fn(lx, _) {
      lx.token("Literal.String.Regex")
      lx.goto("regex")
    })
    s.call("[{]", fn(lx, _) {
      lx.token("Punctuation")
      lx.goto("object")
    })
    s.rule("", "Text", next="#pop")
  })
  lx.state("regex", fn(s) {
    s.call("/", fn(lx, _) {
      lx.token("Literal.String.Regex")
      lx.goto("regex_end")
    })
    s.rule("[^/]\\n", "Error", next="#pop")
    s.rule("\\n", "Error", next="#pop")
    s.rule("\\[\\^", "Literal.String.Escape", next="regex_group")
    s.rule("\\[", "Literal.String.Escape", next="regex_group")
    s.rule("\\\\.", "Literal.String.Escape")
    s.rule("[(][?][:=<!]", "Literal.String.Escape")
    s.rule("[{][\\d,]+[}]", "Literal.String.Escape")
    s.rule("[()?]", "Literal.String.Escape")
    s.rule(".", "Literal.String.Regex")
  })
  lx.state("regex_end", fn(s) {
    s.rule("[gimuy]+", "Literal.String.Regex", next="#pop")
    s.call("", fn(lx, _) { lx.pop() })
  })
  lx.state("regex_group", fn(s) {
    // specially highlight / in a group to indicate that it doesn't
    // close the regex
    s.rule("/", "Literal.String.Escape")
    s.call("[^/]\\n", fn(lx, _) {
      lx.token("Error")
      lx.pop(times=2)
    })
    s.rule("\\]", "Literal.String.Escape", next="#pop")
    s.rule("\\\\.", "Literal.String.Escape")
    s.rule(".", "Literal.String.Regex")
  })
  lx.state("bad_regex", fn(s) { s.rule("[^\\n]+", "Error", next="#pop") })
  lx.state("root", fn(s) {
    s.rule("\\A\\s*#!.*?\\n", "Comment.Preproc", flags="m", next="statement")
    s.rule("(?<=\\n)(?=\\s|/|<!--)", "Text", next="expr_start")
    s.mix_in("comments_and_whitespace")
    s.rule(
      (
        #|\+\+ | -- | ~ | \?\?=? | && | \|\| | \\(?=\n) | << | >>>? | ===
        #|               | !==
      ),
      "Operator",
      flags="x",
      next="expr_start",
    )
    s.rule("[-<>+*%&|\\^/!=]=?", "Operator", next="expr_start")
    s.rule("[(\\[,]", "Punctuation", next="expr_start")
    s.rule(";", "Punctuation", next="statement")
    s.rule("[)\\].]", "Punctuation")
    s.call("`", fn(lx, _) {
      lx.token("Literal.String.Double")
      lx.push("template_string")
    })
    // special case for the safe navigation operator ?.
    // so that we don't start detecting a ternary expr
    s.rule("[?][.]", "Punctuation")
    s.call("[?]", fn(lx, _) {
      lx.token("Punctuation")
      lx.push("ternary")
      lx.push("expr_start")
    })
    s.call("(\\@)(\\w+)?", fn(lx, _) {
      lx.groups(["Punctuation", "Name.Decorator"])
      lx.push("expr_start")
    })
    s.rule("[{}]", "Punctuation", next="statement")
    s.call(
      js_id_src,
      fn(lx, m) {
        let word = m.matched()
        if w.keywords.contains(word) {
          lx.token("Keyword")
          lx.push("expr_start")
        } else if w.declarations.contains(word) {
          lx.token("Keyword.Declaration")
          lx.push("expr_start")
        } else if w.reserved.contains(word) {
          lx.token("Keyword.Reserved")
        } else if w.constants.contains(word) {
          lx.token("Keyword.Constant")
        } else if w.builtins.contains(word) {
          lx.token("Name.Builtin")
        } else {
          lx.token("Name.Other")
        }
      },
      flags="i",
    )
    s.rule("[0-9][0-9]*\\.[0-9]+([eE][0-9]+)?[fd]?", "Literal.Number.Float")
    s.rule("0x[0-9a-fA-F]+", "Literal.Number.Hex", flags="i")
    s.rule("0o[0-7][0-7_]*", "Literal.Number.Oct", flags="i")
    s.rule("0b[01][01_]*", "Literal.Number.Bin", flags="i")
    s.rule("[0-9]+", "Literal.Number.Integer")
    s.rule("\"", "Literal.String.Delimiter", next="dq")
    s.rule("'", "Literal.String.Delimiter", next="sq")
    s.rule(":", "Punctuation")
  })
  lx.state("dq", fn(s) {
    s.rule("\\\\[\\\\nrt\"]?", "Literal.String.Escape")
    s.rule("[^\\\\\"]+", "Literal.String.Double")
    s.rule("\"", "Literal.String.Delimiter", next="#pop")
  })
  lx.state("sq", fn(s) {
    s.rule("\\\\[\\\\nrt']?", "Literal.String.Escape")
    s.rule("[^\\\\']+", "Literal.String.Single")
    s.rule("'", "Literal.String.Delimiter", next="#pop")
  })
  // braced parts that aren't object literals
  lx.state("statement", fn(s) {
    s.call("case\\b", fn(lx, _) {
      lx.token("Keyword")
      lx.goto("expr_start")
    })
    s.call("(\{id})(\\s*)(:)", fn(lx, _) {
      lx.groups(["Name.Label", "Text", "Punctuation"])
    })
    s.mix_in("expr_start")
  })
  // object literals
  lx.state("object", fn(s) {
    s.mix_in("comments_and_whitespace")
    s.call("[{]", fn(lx, _) {
      lx.token("Punctuation")
      lx.push_self()
    })
    s.call("[}]", fn(lx, _) {
      lx.token("Punctuation")
      lx.goto("statement")
    })
    s.call("(\{id})(\\s*)(:)", fn(lx, _) {
      lx.groups(["Name.Attribute", "Text", "Punctuation"])
      lx.push("expr_start")
    })
    s.rule(":", "Punctuation")
    s.mix_in("root")
  })
  // ternary expressions, where <id>: is not a label!
  lx.state("ternary", fn(s) {
    s.call(":", fn(lx, _) {
      lx.token("Punctuation")
      lx.goto("expr_start")
    })
    s.mix_in("root")
  })
  // template strings
  lx.state("template_string", fn(s) {
    s.rule("[$]{", "Punctuation", next="template_string_expr")
    s.rule("`", "Literal.String.Double", next="#pop")
    s.rule("\\\\[$`]", "Literal.String.Escape")
    s.rule("[^$`\\\\]+", "Literal.String.Double")
    s.rule("[\\\\$]", "Literal.String.Double")
  })
  lx.state("template_string_expr", fn(s) {
    s.rule("}", "Punctuation", next="#pop")
    s.mix_in("root")
  })
}
