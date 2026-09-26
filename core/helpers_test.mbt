// Ported from test/helpers_test.rb. Tests marked "(extra)" are not in the Ruby
// file; their expected values were produced by running Ruby Asciidoctor's
// Helpers module on the same inputs.
//
// Skipped: 'Type Resolution' (class_for_name/resolve_class) and 'Require
// Library' (require_library), which are Ruby reflection/loading facilities
// with no counterpart in the port.

///|
test "URI Encoding: should URI encode non-word characters generally" {
  inspect(
    @core.encode_uri_component(" !*/%&?\\="),
    content="%20%21%2A%2F%25%26%3F%5C%3D",
  )
}

///|
test "URI Encoding: should not URI encode select non-word characters" {
  inspect(@core.encode_uri_component("-."), content="-.")
}

///|
test "URI Encoding: encodes multibyte characters as UTF-8 (extra)" {
  inspect(
    @core.encode_uri_component("a~b_c é中"),
    content="a~b_c%20%C3%A9%E4%B8%AD",
  )
}

///|
test "URIs and Paths: rootname should return file name without extension" {
  inspect(@core.rootname("main.adoc"), content="main")
  inspect(@core.rootname("docs/main.adoc"), content="docs/main")
}

///|
test "URIs and Paths: rootname should file name if it has no extension" {
  inspect(@core.rootname("main"), content="main")
  inspect(@core.rootname("docs/main"), content="docs/main")
}

///|
test "URIs and Paths: rootname should ignore dot not in last segment" {
  inspect(@core.rootname("include.d/main"), content="include.d/main")
  inspect(@core.rootname("include.d/main.adoc"), content="include.d/main")
}

///|
test "URIs and Paths: rootname edge cases (extra)" {
  inspect(@core.rootname(".hidden"), content="")
  inspect(@core.rootname("a/.hidden"), content="a/")
  inspect(@core.rootname("a.b.c"), content="a.b")
  inspect(@core.rootname(".adoc"), content="")
}

///|
test "URIs and Paths: extname? should return whether path contains an extname" {
  assert_true(@core.has_extname("document.adoc"))
  assert_true(@core.has_extname("path/to/document.adoc"))
  assert_false(@core.has_extname("basename"))
  assert_false(@core.has_extname("include.d/basename"))
  assert_true(@core.has_extname(".hidden"))
}

///|
test "URIs and Paths: extname with and without fallback (extra)" {
  inspect(@core.extname("document.adoc"), content=".adoc")
  inspect(@core.extname("path/to/document.adoc"), content=".adoc")
  inspect(@core.extname("basename"), content="")
  inspect(@core.extname("include.d/basename"), content="")
  inspect(@core.extname("include.d/basename", fallback="none"), content="none")
  inspect(@core.extname("a.b.c"), content=".c")
  inspect(@core.extname(".hidden"), content=".hidden")
}

///|
test "URIs and Paths: basename with and without drop_ext (extra)" {
  inspect(@core.basename("/path/to/file.adoc"), content="file.adoc")
  inspect(@core.basename("/path/to/file.adoc", drop_ext=true), content="file")
  inspect(@core.basename("file.adoc", drop_ext=true), content="file")
  inspect(@core.basename("file", drop_ext=true), content="file")
  inspect(@core.basename("path/to/"), content="to")
  inspect(@core.basename("include.d/main", drop_ext=true), content="main")
  inspect(@core.basename("path/to//"), content="to")
  inspect(@core.basename("/"), content="/")
  inspect(@core.basename(".adoc", drop_ext=true), content=".adoc")
}

///|
// UriSniffRx is private; uriish? (which is `include?(':') && UriSniffRx =~ path`)
// is equivalent for these inputs because each contains a colon.
test "URIs and Paths: UriSniffRx should detect URIs" {
  assert_true(@core.is_uriish("http://example.com"))
  assert_true(@core.is_uriish("https://example.com"))
  assert_true(
    @core.is_uriish(
      "data:image/gif;base64,R0lGODlhAQABAIAAAAUEBAAAACwAAAAAAQABAAACAkQBADs=",
    ),
  )
}

///|
test "URIs and Paths: UriSniffRx should not detect an absolute Windows path as a URI" {
  assert_false(@core.is_uriish("c:/sample.adoc"))
  assert_false(@core.is_uriish("c:\\sample.adoc"))
}

///|
test "URIs and Paths: uriish? should not detect a classloader path as a URI on JRuby" {
  // not JRuby, so the classloader path is a URI
  assert_true(@core.is_uriish("uri:classloader:/sample.png"))
}

///|
test "URIs and Paths: UriSniffRx should not detect URI that does not start on first line" {
  assert_false(@core.is_uriish("text\nhttps://example.org"))
}

///|
test "URIs and Paths: uriish? other schemes (extra)" {
  assert_true(@core.is_uriish("irc://irc.freenode.org"))
  assert_true(@core.is_uriish("file:///x"))
  assert_false(@core.is_uriish("noscheme"))
  assert_false(@core.is_uriish("a:b"))
}

///|
test "Source preparation: prepare_source_string (extra)" {
  debug_inspect(
    @core.prepare_source_string("\u{FEFF}line one  \r\nline two\t\r\n\r\n"),
    content=(
      #|["line one", "line two", ""]
    ),
  )
  debug_inspect(
    @core.prepare_source_string(
      "\u{FEFF}line one  \r\nline two\t\r\n\r\n",
      trim_end=false,
    ),
    content=(
      #|["line one  ", "line two\t", ""]
    ),
  )
  debug_inspect(
    @core.prepare_source_string("a\nb\n\n"),
    content=(
      #|["a", "b", ""]
    ),
  )
  debug_inspect(@core.prepare_source_string(""), content="[]")
  debug_inspect(
    @core.prepare_source_string("x\ny"),
    content=(
      #|["x", "y"]
    ),
  )
  debug_inspect(
    @core.prepare_source_string("x\r\ny  \n  "),
    content=(
      #|["x", "y", ""]
    ),
  )
}

///|
test "Source preparation: prepare_source_array (extra)" {
  debug_inspect(
    @core.prepare_source_array(["\u{FEFF}foo  ", "bar\t", ""]),
    content=(
      #|["foo", "bar", ""]
    ),
  )
  debug_inspect(
    @core.prepare_source_array(
      ["\u{FEFF}foo  \r", "bar\t\n", ""],
      trim_end=false,
    ),
    content=(
      #|["foo  ", "bar\t", ""]
    ),
  )
  debug_inspect(@core.prepare_source_array([]), content="[]")
}

///|
test "Roman Numeral Conversion: should convert integer to roman numeral" {
  inspect(@rb.int_to_roman(1), content="I")
  inspect(@rb.int_to_roman(4), content="IV")
  inspect(@rb.int_to_roman(64), content="LXIV")
  debug_inspect(
    [9, 14, 40, 90, 400, 1994, 2024, 3999].map(@rb.int_to_roman),
    content=(
      #|["IX", "XIV", "XL", "XC", "CD", "MCMXCIV", "MMXXIV", "MMMCMXCIX"]
    ),
  )
}

///|
test "Roman Numeral Conversion: should convert roman numeral to integer" {
  inspect(@core.roman_to_int("I"), content="1")
  inspect(@core.roman_to_int("IV"), content="4")
  inspect(@core.roman_to_int("LXIV"), content="64")
  debug_inspect(
    ["IX", "XIV", "XL", "XC", "CD", "MCMXCIV", "MMXXIV", "MMMCMXCIX"].map(
      @core.roman_to_int,
    ),
    content="[9, 14, 40, 90, 400, 1994, 2024, 3999]",
  )
}
