///|
test "the default fonts decode to the gem's files" {
  let fonts = @fonts.default_fonts()
  let sizes = [
    ("notoserif-regular-subset.ttf", 236848),
    ("notoserif-bold-subset.ttf", 237580),
    ("notoserif-italic-subset.ttf", 224136),
    ("notoserif-bold_italic-subset.ttf", 250720),
    ("mplus1mn-regular-subset.ttf", 63220),
    ("mplus1mn-bold-subset.ttf", 55556),
    ("mplus1mn-italic-subset.ttf", 55976),
    ("mplus1mn-bold_italic-subset.ttf", 55624),
    ("fa-legacy-mapping.yml", 22365),
  ]
  assert_eq(fonts.names().length(), sizes.length())
  for entry in sizes {
    let (name, size) = entry
    assert_true(fonts.contains(name))
    let data = fonts.get(name).unwrap()
    assert_eq(data.length(), size)
    if name.has_suffix(".ttf") {
      // a TrueType sfnt
      assert_eq(data[0:4].to_owned(), b"\x00\x01\x00\x00")
    }
    // decoded once, then kept
    assert_true(physical_equal(fonts.get(name).unwrap(), data))
  }
  assert_eq(fonts.get("notosans-regular-subset.ttf"), None)
}

///|
test "a bundle of other files" {
  let bundle = @fonts.Bundle::new([("a.txt", () => b"alpha")])
  assert_eq(bundle.get("a.txt"), Some(b"alpha"))
  assert_eq(bundle.get("b.txt"), None)
  assert_eq(bundle.names(), ["a.txt"])
}
