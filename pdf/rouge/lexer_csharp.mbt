///|
/// Rouge's `CSharp` (lexers/csharp.rb).
pub fn csharp(options : Map[String, String]) -> Lexer {
  let lx = Lexer::new("csharp", options~)
  // TODO: support more of unicode
  let id = rx("@?[_a-z]\\w*", flags="i")
  // Reserved Identifiers, Contextual Keywords, LINQ Query Expressions
  let keywords = words(
    (
      #|abstract as base break case catch checked const continue
      #|default delegate do else enum event explicit extern false
      #|finally fixed for foreach goto if implicit in interface
      #|internal is lock new null operator out override params private
      #|protected public readonly ref return sealed sizeof stackalloc
      #|static switch this throw true try typeof unchecked unsafe
      #|virtual void volatile while
      #|add alias async await get global partial remove set value where
      #|yield nameof
      #|ascending by descending equals from group in into join let on
      #|orderby select
    ),
  )
  let keywords_type = words(
    (
      #|bool byte char decimal double dynamic float int long object
      #|sbyte short string uint ulong ushort var
    ),
  )
  let cpp_keywords = words(
    (
      #|if endif else elif define undef line error warning region
      #|endregion pragma
    ),
  )
  lx.state("whitespace", fn(s) {
    s.rule("\\s+", "Text", flags="m")
    s.rule("//.*?$", "Comment.Single")
    s.rule("/[*].*?[*]/", "Comment.Multiline", flags="m")
  })
  lx.state("nest", fn(s) {
    s.rule("{", "Punctuation", next="nest")
    s.rule("}", "Punctuation", next="#pop")
    s.mix_in("root")
  })
  lx.state("splice_string", fn(s) {
    s.rule("\\\\.", "Literal.String")
    s.rule("{", "Punctuation", next="nest")
    s.rule("\"|\\n", "Literal.String", next="#pop")
    s.rule(".", "Literal.String")
  })
  lx.state("splice_literal", fn(s) {
    s.rule("\"\"", "Literal.String")
    s.rule("{", "Punctuation", next="nest")
    s.rule("\"", "Literal.String", next="#pop")
    s.rule(".", "Literal.String")
  })
  lx.state("root", fn(s) {
    s.mix_in("whitespace")
    s.rule("[$]\\s*\"", "Literal.String", next="splice_string")
    s.rule("[$]@\\s*\"", "Literal.String", next="splice_literal")
    s.rule("(<\\[)\\s*(\{id}:)?", "Keyword")
    s.rule("\\]>", "Keyword")
    s.rule("[~!%^&*()+=|\\[\\]{}:;,.<>\\/?-]", "Punctuation")
    s.rule("@\"(\"\"|[^\"])*\"", "Literal.String", flags="m")
    s.rule("\"(\\\\.|.)*?[\"\\n]", "Literal.String")
    s.rule("'(\\\\.|.)'", "Literal.String.Char")
    s.rule("0x[0-9a-f]+[lu]?", "Literal.Number", flags="i")
    s.rule(
      (
        #|
        #|          [0-9]
        #|          ([.][0-9]*)? # decimal
        #|          (e[+-][0-9]+)? # exponent
        #|          [fldu]? # type
        #|
      ),
      "Literal.Number",
      flags="ix",
    )
    s.rule("\\b(?:class|struct|interface)\\b", "Keyword", next="class")
    s.rule("\\b(?:namespace|using)\\b", "Keyword", next="namespace")
    s.rule("^#[ \\t]*(\{alt(cpp_keywords)})\\b.*?\\n", "Comment.Preproc")
    s.rule("\\b(\{alt(keywords)})\\b", "Keyword")
    s.rule("\\b(\{alt(keywords_type)})\\b", "Keyword.Type")
    s.rule("\{id}(?=\\s*[(])", "Name.Function")
    s.rule(id, "Name")
  })
  lx.state("class", fn(s) {
    s.mix_in("whitespace")
    s.rule(id, "Name.Class", next="#pop")
  })
  lx.state("namespace", fn(s) {
    s.mix_in("whitespace")
    s.rule("(?=[(])", "Text", next="#pop")
    s.rule("(\{id}|[.])+", "Name.Namespace", next="#pop")
  })
  lx
}
