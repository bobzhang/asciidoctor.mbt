///|
/// Rouge's `Diff` (lexers/diff.rb): unified diffs and patches.
pub fn diff(options : Map[String, String]) -> Lexer {
  let lx = Lexer::new("diff", options~)
  lx.state("root", fn(s) {
    s.rule("^ .*$\\n?", "Text")
    s.rule("^---$\\n?", "Punctuation")
    s.rule("^[+>]+.*$\\n?", "Generic.Inserted")
    s.rule("^\\+.*$\\n?", "Generic.Inserted")
    s.rule("^[-<]+.*$\\n?", "Generic.Deleted")
    s.rule("^!.*$\\n?", "Generic.Strong")
    s.rule("^([Ii]ndex|diff).*$\\n?", "Generic.Heading")
    s.call("^(@@[^@]*@@)([^\\n]*\\n)", fn(lx, _) {
      lx.groups(["Punctuation", "Text"])
    })
    s.rule("^\\w.*$\\n?", "Punctuation")
    s.rule("^=.*$\\n?", "Generic.Heading")
    s.rule("\\s.*$\\n?", "Text")
  })
  lx
}
