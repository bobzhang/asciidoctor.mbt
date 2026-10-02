///|
/// The match of `pattern` at `pos` of `s` as `try_scan_at` finds it.
fn scan(pattern : String, s : String, pos : Int) -> String raise {
  match @regex.re(pattern).try_scan_at(s, pos) {
    Some(m) => "\{m.begin()}..\{m.end()} \{m.matched()}"
    None => "none"
  }
}

///|
test "try_scan_at sees the text from the scan position, as StringScanner" {
  // Ruby 4.0: s = StringScanner.new("a.b xy"); s.pos = 2; s.scan(/(?<!\.)b/)
  // => "b"; s.pos = 5; s.scan(/\By/) => nil; s.scan(/\Ay/) => "y"
  inspect(scan("(?<!\\.)b", "a.b xy", 2), content="2..3 b")
  inspect(scan("\\Ay", "a.b xy", 5), content="5..6 y")
  inspect(scan("\\By", "a.b xy", 5), content="none")
  inspect(scan("\\by", "a.b xy", 5), content="5..6 y")
  inspect(scan("^x", "a.b xy", 4), content="4..5 x")
  inspect(scan("(?<=b )x", "a.b xy", 4), content="none")
  // past the scan position the text is the whole string's
  inspect(scan("x\\by", "a.b x y", 4), content="none")
  inspect(scan(".*\\z", "a.b xy", 4), content="4..6 xy")
  // match_at sees the text before the position
  inspect(
    @regex.re("(?<!\\.)b").try_match_at("a.b xy", 2) is None,
    content="true",
  )
}
