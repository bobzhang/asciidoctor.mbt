///|
test "manpage paragraphs drop Unicode blanks around line breaks" {
  // Ruby's WrappedIndentRx uses \p{Blank}, which includes U+3000
  // (seen in git/Documentation/RelNotes/2.3.0.adoc)
  let out = @asciidoctor.convert(
    "= cmd(1)\n\n== NAME\n\ncmd - does things\n\n== DESCRIPTION\n\nfirst line\u{3000}\n\u{3000}second line\n",
    options=@core.Options::new(backend="manpage", standalone=false),
  )
  inspect(out.has_suffix(".sp\nfirst line\nsecond line"), content="true")
}
