///|
/// The states of Rouge's `SassCommon` (lexers/sass/common.rb), shared by
/// `Sass` and `Scss`; each defines `end_section` and `root` itself.
fn sass_common_states(lx : Lexer) -> Unit {
  let id_src = "[\\w-]+"
  let id = rx(id_src)
  lx.state("content_common", fn(s) {
    s.rule("@for\\b", "Keyword", next="for")
    s.rule(
      "@(debug|warn|if|each|while|else|return|media)",
      "Keyword",
      next="value",
    )
    s.call("(@mixin)(\\s+)(\{id})", fn(lx, _) {
      lx.groups(["Keyword", "Text", "Name.Function"])
      lx.push("value")
    })
    s.call("(@function)(\\s+)(\{id})", fn(lx, _) {
      lx.groups(["Keyword", "Text", "Name.Function"])
      lx.push("value")
    })
    s.rule("@extend\\b", "Keyword", next="selector")
    s.call("(@include)(\\s+)(\{id})", fn(lx, _) {
      lx.groups(["Keyword", "Text", "Name.Decorator"])
      lx.push("value")
    })
    s.rule("@\{id}", "Keyword", next="selector")
    s.rule("&", "Keyword", next="selector")
    // $variable: assignment
    s.call("([$]\{id})([ \\t]*)(:)", fn(lx, _) {
      lx.groups(["Name.Variable", "Text", "Punctuation"])
      lx.push("value")
    })
  })
  lx.state("value", fn(s) {
    s.mix_in("end_section")
    s.rule("[ \\t]+", "Text")
    s.rule("[$]\{id}", "Name.Variable")
    s.rule("url[(]", "Literal.String.Other", next="string_url")
    s.rule("\{id}(?=\\s*[(])", "Name.Function")
    s.rule("%\{id}", "Name.Decorator")
    // named literals
    s.rule("(true|false)\\b", "Name.Builtin.Pseudo")
    s.rule("(and|or|not)\\b", "Operator.Word")
    // colors and numbers
    s.rule("#[a-z0-9]{1,6}", "Literal.Number.Hex", flags="i")
    s.rule("-?\\d+(%|[a-z]+)?", "Literal.Number")
    s.rule("-?\\d*\\.\\d+(%|[a-z]+)?", "Literal.Number.Integer")
    s.mix_in("has_strings")
    s.mix_in("has_interp")
    s.rule("[~^*!&%<>\\|+=@:,.\\/?-]+", "Operator")
    s.rule("[\\[\\]()]+", "Punctuation")
    s.rule("/[*]", "Comment.Multiline", next="inline_comment")
    s.rule("//[^\\n]*", "Comment.Single")
    // identifiers
    s.call(id_src, fn(lx, m) {
      if css_builtins.contains(m.matched()) {
        lx.token("Name.Builtin")
      } else if css_constants.contains(m.matched()) {
        lx.token("Name.Constant")
      } else {
        lx.token("Name")
      }
    })
  })
  lx.state("has_interp", fn(s) {
    s.rule("[#][{]", "Literal.String.Interpol", next="interpolation")
  })
  lx.state("has_strings", fn(s) {
    s.rule("\"", "Literal.String.Double", next="dq")
    s.rule("'", "Literal.String.Single", next="sq")
  })
  lx.state("interpolation", fn(s) {
    s.rule("}", "Literal.String.Interpol", next="#pop")
    s.mix_in("value")
  })
  lx.state("selector", fn(s) {
    s.mix_in("end_section")
    s.mix_in("has_strings")
    s.mix_in("has_interp")
    s.rule("[ \\t]+", "Text")
    s.rule(":", "Name.Decorator", next="pseudo_class")
    s.rule("[.]", "Name.Class", next="class")
    s.rule("#", "Name.Namespace", next="id")
    s.rule("%", "Name.Variable", next="placeholder")
    s.rule(id_src, "Name.Tag")
    s.rule("&", "Keyword")
    s.rule("[~^*!&\\[\\]()<>\\|+=@:;,.\\/?-]", "Operator")
  })
  lx.state("dq", fn(s) {
    s.rule("\"", "Literal.String.Double", next="#pop")
    s.mix_in("has_interp")
    s.rule("(\\\\.|#(?![{])|[^\\n\"#])+", "Literal.String.Double")
  })
  lx.state("sq", fn(s) {
    s.rule("'", "Literal.String.Single", next="#pop")
    s.mix_in("has_interp")
    s.rule("(\\\\.|#(?![{])|[^\\n'#])+", "Literal.String.Single")
  })
  lx.state("string_url", fn(s) {
    s.rule("[)]", "Literal.String.Other", next="#pop")
    s.rule("(\\\\.|#(?![{])|[^\\n)#])+", "Literal.String.Other")
    s.mix_in("has_interp")
  })
  lx.state("selector_piece", fn(s) {
    s.mix_in("has_interp")
    s.call("", fn(lx, _) { lx.pop() })
  })
  lx.state("pseudo_class", fn(s) {
    s.rule(id_src, "Name.Decorator")
    s.mix_in("selector_piece")
  })
  lx.state("class", fn(s) {
    s.rule(id_src, "Name.Class")
    s.mix_in("selector_piece")
  })
  lx.state("id", fn(s) {
    s.rule(id_src, "Name.Namespace")
    s.mix_in("selector_piece")
  })
  lx.state("placeholder", fn(s) {
    s.rule(id_src, "Name.Variable")
    s.mix_in("selector_piece")
  })
  lx.state("for", fn(s) {
    s.rule("(from|to|through)", "Operator.Word")
    s.mix_in("value")
  })
  lx.state("attr_common", fn(s) {
    s.mix_in("has_interp")
    s.call(id_src, fn(lx, m) {
      if css_attributes.contains(m.matched()) {
        lx.token("Name.Label")
      } else {
        lx.token("Name.Attribute")
      }
    })
  })
  lx.state("attribute", fn(s) {
    s.mix_in("attr_common")
    s.call("([ \\t]*)(:)", fn(lx, _) {
      lx.groups(["Text", "Punctuation"])
      lx.push("value")
    })
  })
  lx.state("inline_comment", fn(s) {
    s.rule(
      "(\\\\#|#(?=[^\\n{])|\\*(?=[^\\n\\/])|[^\\n#*])+", "Comment.Multiline",
    )
    s.mix_in("has_interp")
    s.rule("[*]/", "Comment.Multiline", next="#pop")
  })
}
