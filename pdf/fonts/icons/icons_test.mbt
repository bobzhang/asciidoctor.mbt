///|
/// The glyph of icon `name` in the bundled table of `set`.
fn glyph(set : String, name : String) -> Int? raise {
  let table = @utf8.decode(@icons.fonts().get("\{set}/glyphs.txt").unwrap())
  for line in table.split("\n") {
    if line.has_prefix(name + ": ") {
      return line[name.length() + 2:].get_char(0).map(c => c.to_int())
    }
  }
  None
}

///|
test "each icon set has its font and its icon names" {
  let bundle = @icons.fonts()
  for set in ["fab", "far", "fas", "fi", "pf"] {
    assert_true(bundle.contains("\{set}/glyphs.txt"))
  }
  assert_eq(bundle.names().length(), 10)
  // prawn-icon's legends are not bundled
  assert_false(bundle.contains("fas/fas.yml"))
}

///|
test "icon names as prawn-icon's legends have them" {
  // Font Awesome: glyph names, standard Macintosh ones too
  assert_eq(glyph("fas", "heart"), Some(0xf004))
  assert_eq(glyph("fab", "apple"), Some(0xf179))
  assert_eq(glyph("fab", "less"), Some(0xf41d))
  // listed by Font Awesome's metadata, missing from the fonts
  assert_eq(glyph("fab", "font-awesome-logo-full"), Some(0xf4e6))
  // Foundation Icons and PaymentFont: their stylesheets
  assert_eq(glyph("fi", "address-book"), Some(0xf100))
  assert_eq(glyph("pf", "amazon"), Some(0xf000))
  assert_eq(glyph("pf", "no-such-icon"), None)
}
