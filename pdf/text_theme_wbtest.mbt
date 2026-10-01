///|
test "transform_text leaves markup and character references alone" {
  assert_eq(transform_text("über étudier", "uppercase"), "ÜBER ÉTUDIER")
  assert_eq(
    transform_text("&lt;tom &amp; jerry&gt;", "uppercase"),
    "&lt;TOM &amp; JERRY&gt;",
  )
  assert_eq(
    transform_text("here we go <strong>again</strong>", "uppercase"),
    "HERE WE GO <strong>AGAIN</strong>",
  )
  assert_eq(transform_text("a & b", "uppercase"), "A & B")
  assert_eq(
    transform_text("<EM>WAVE</EM> &AMP;", "lowercase"),
    "<EM>wave</EM> &amp;",
  )
  assert_eq(
    transform_text("foo-bar baz HTML", "capitalize"),
    "Foo-bar Baz Html",
  )
  assert_eq(
    transform_text("here <em>we</em> go", "capitalize"),
    "Here <em>We</em> Go",
  )
  assert_eq(transform_text("Here we go", "smallcaps"), "Hᴇʀᴇ ᴡᴇ ɢo")
  assert_eq(transform_text("Here", "none"), "Here")
}
