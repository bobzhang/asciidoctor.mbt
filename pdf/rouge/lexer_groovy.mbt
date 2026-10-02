///|
/// Rouge's `Groovy.keywords`.
let groovy_keywords : Set[String] = word_set(
  (
    #|assert break case catch continue default do else finally for
    #|if goto instanceof new return switch this throw try while in as
  ),
)

///|
/// Rouge's `Groovy.declarations`.
let groovy_declarations : Set[String] = word_set(
  (
    #|abstract const enum extends final implements native private
    #|protected public static strictfp super synchronized throws
    #|transient volatile
  ),
)

///|
/// Rouge's `Groovy.types`.
let groovy_types : Set[String] = word_set(
  "def boolean byte char double float int long short void",
)

///|
/// Rouge's `Groovy.constants`.
let groovy_constants : Set[String] = word_set("true false null")

///|
/// A copy of the lexer that shares its state stack (Ruby's `self.clone`,
/// which copies the instance variables by reference: what the copy pushes
/// and pops, the original sees).
fn Lexer::clone_sharing_stack(self : Lexer) -> Lexer {
  { ..self, }
}

///|
/// Rouge's `Groovy` (lexers/groovy.rb).
pub fn groovy(options : Map[String, String]) -> Lexer {
  let lx = Lexer::new("groovy", options~)
  groovy_states(lx, groovy_keywords, groovy_types)
  lx
}

///|
/// The states of Rouge's `Groovy`, with the class's keyword and type sets
/// (`Gradle` extends them).
fn groovy_states(
  lx : Lexer,
  keywords : Set[String],
  types : Set[String],
) -> Unit {
  lx.state("root", fn(s) {
    s.call(
      (
        #|^
        #|          (\s*(?:\w[\w.\[\]]*\s+)+?) # return arguments
        #|          (\w\w*) # method name
        #|          (\s*) (\() # signature start
        #|
      ),
      fn(lx, m) {
        lx.delegate(lx.clone_sharing_stack(), text=group_text(m, 1))
        lx.token("Name.Function", val=group_text(m, 2))
        lx.token("Text", val=group_text(m, 3))
        lx.token("Operator", val=group_text(m, 4))
      },
      flags="x",
    )
    // whitespace
    s.rule("[^\\S\\n]+", "Text")
    s.rule("//.*?$", "Comment.Single")
    s.rule("/[*].*?[*]/", "Comment.Multiline", flags="m")
    s.rule("@\\w[\\w.]*", "Name.Decorator")
    s.rule("(class|interface|trait)\\b", "Keyword.Declaration", next="class")
    s.rule("package\\b", "Keyword.Namespace", next="import")
    s.rule("import\\b", "Keyword.Namespace", next="import")
    // TODO: highlight backslash escapes
    s.rule("\"\"\".*?\"\"\"", "Literal.String.Double", flags="m")
    s.rule("'''.*?'''", "Literal.String.Single", flags="m")
    s.rule("\"(\\\\.|\\\\\\n|.)*?\"", "Literal.String.Double")
    s.rule("'(\\\\.|\\\\\\n|.)*?'", "Literal.String.Single")
    s.rule("\\$/(\\$.|.)*?/\\$", "Literal.String", flags="m")
    s.rule("/(\\\\.|\\\\\\n|.)*?/", "Literal.String")
    s.rule("'\\\\.'|'[^\\\\]'|'\\\\u[0-9a-f]{4}'", "Literal.String.Char")
    s.call("(\\.)([a-zA-Z_][a-zA-Z0-9_]*)", fn(lx, _) {
      lx.groups(["Operator", "Name.Attribute"])
    })
    s.rule("[a-zA-Z_][a-zA-Z0-9_]*:", "Name.Label")
    s.call("[a-zA-Z_\\$][a-zA-Z0-9_]*", fn(lx, m) {
      let name = m.matched()
      if keywords.contains(name) {
        lx.token("Keyword")
      } else if groovy_declarations.contains(name) {
        lx.token("Keyword.Declaration")
      } else if types.contains(name) {
        lx.token("Keyword.Type")
      } else if groovy_constants.contains(name) {
        lx.token("Keyword.Constant")
      } else {
        lx.token("Name")
      }
    })
    s.rule("[~^*!%&\\[\\](){}<>\\|+=:;,./?-]", "Operator")
    // numbers
    s.rule("\\d+\\.\\d+([eE]\\d+)?[fd]?", "Literal.Number.Float")
    s.rule("0x[0-9a-f]+", "Literal.Number.Hex")
    s.rule("[0-9]+L?", "Literal.Number.Integer")
    s.rule("\\n", "Text")
  })
  lx.state("class", fn(s) {
    s.rule("\\s+", "Text")
    s.rule("\\w\\w*", "Name.Class", next="#pop")
  })
  lx.state("import", fn(s) {
    s.rule("\\s+", "Text")
    s.rule("[\\w.]+[*]?", "Name.Namespace", next="#pop")
  })
}
