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
  inspect(scan("x\\by", "a.b xy", 4), content="none")
  inspect(scan("x\\b y", "a.b x y", 4), content="4..7 x y")
  inspect(scan(".*\\z", "a.b xy", 4), content="4..6 xy")
  // match_at sees the text before the position
  inspect(
    @regex.re("(?<!\\.)b").try_match_at("a.b xy", 2) is None,
    content="true",
  )
}

///|
test "try_scan_at: later lines, empty matches, surrogate pairs" {
  // Ruby 4.0 StringScanner: later line boundaries are the string's
  inspect(scan("x\\n^y", "ab x\ny", 3), content="3..6 x\ny")
  // an empty match at the end
  inspect(scan("\\z", "abc", 3), content="3..3 ")
  inspect(scan("a?", "abc", 3), content="3..3 ")
  // offsets are UTF-16; a position inside a surrogate pair matches nothing
  let s = "a\u{1F600}b"
  inspect(scan("(.)b", s, 1), content="1..4 \u{1F600}b")
  inspect(scan(".", s, 2), content="none")
  let m = @regex.re("(.)b").try_scan_at(s, 1).unwrap()
  inspect(m.group(1).unwrap(), content="\u{1F600}")
}

///|
test "try_scan_at leaves a reused regex as it was" {
  let r = @regex.re("(?<!\\.)b")
  // after a match, a failure and a match, try_match_at still sees the text
  // before the position
  inspect(r.try_scan_at("a.b xy", 2) is Some(_), content="true")
  inspect(r.try_match_at("a.b xy", 2) is None, content="true")
  inspect(r.try_scan_at("a.c xy", 2) is None, content="true")
  inspect(r.try_match_at("a.b xy", 2) is None, content="true")
  inspect(r.try_match_at("acb", 2) is Some(_), content="true")
  let a = @regex.re("\\Ab")
  inspect(a.try_scan_at("ab", 1) is Some(_), content="true")
  inspect(a.try_match_at("ab", 1) is None, content="true")
}
