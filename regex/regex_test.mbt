// Expected values were produced by Ruby 2.6 (see scripts/gen_regex_oracle.rb for the
// large differential suite).

///|
test "gsub with empty matches" {
  inspect(@regex.re("x*").gsub("abc", "-"), content="-a-b-c-")
  inspect(@regex.re("a*?").gsub("aaa", "-"), content="-a-a-a-")
  inspect(@regex.re("(a)(?=a)").gsub("aaa", "<\\1>"), content="<a><a>a")
}

///|
test "split follows Ruby semantics" {
  debug_inspect(
    @regex.re(",").split("a,b,,c,,"),
    content=(
      #|["a", "b", "", "c"]
    ),
  )
  debug_inspect(
    @regex.re(",").split("a,b,,c,,", limit=-1),
    content=(
      #|["a", "b", "", "c", "", ""]
    ),
  )
  debug_inspect(
    @regex.re("(\\d)").split("a1b2c"),
    content=(
      #|["a", "1", "b", "2", "c"]
    ),
  )
  debug_inspect(
    @regex.re("").split("abc"),
    content=(
      #|["a", "b", "c"]
    ),
  )
  debug_inspect(
    @regex.re("\\s+").split("a b  c", limit=2),
    content=(
      #|["a", "b  c"]
    ),
  )
  debug_inspect(
    @regex.re(" ").split(" a b"),
    content=(
      #|["", "a", "b"]
    ),
  )
}

///|
test "templates, named groups, lookbehind, surrogates" {
  inspect(
    @regex.re("(\\w+) (\\w+)").sub("John Smith", "\\2, \\1"),
    content="Smith, John",
  )
  inspect(
    @regex.re(".").replace("😀a😀", m => "[\{m.matched()}]"),
    content="[😀][a][😀]",
  )
  debug_inspect(
    @regex.re("(?<=😀).").find_all("x😀y").map(m => m.matched()),
    content=(
      #|["y"]
    ),
  )
  inspect(@regex.re("(?<!o)\\.").gsub("foo.bar", "!"), content="foo.bar")
  guard @regex.re("(?<x>a)b\\k<x>").find("abab") is Some(m) else {
    fail("no match")
  }
  inspect(m.matched(), content="aba")
  debug_inspect(m.named("x"), content="Some(\"a\")")
  debug_inspect(
    @regex.re("^.").find_all("ab\nc").map(m => m.matched()),
    content=(
      #|["a", "c"]
    ),
  )
  inspect(@regex.re("\\{\\w\\}").find_all("a{b}")[0].matched(), content="{b}")
  inspect(@regex.re("x{1,}y").matches("xxy"), content="true")
  inspect(@regex.re("x\\{1,\\}y").matches("x{1,}y"), content="true")
  inspect(
    @regex.re("a{2,3}").find("aaaa").map(m => m.matched()).unwrap(),
    content="aaa",
  )
}

///|
test "anchors follow Ruby" {
  // `^` does not match after a trailing newline at end of string; `$` matches before \n and at end
  inspect(@regex.re("^").find_all("a\n").length(), content="1")
  inspect(@regex.re("$").find_all("a\n").length(), content="2")
  inspect(@regex.re("a\\Z").matches("a\n"), content="true")
  inspect(@regex.re("a\\Z").matches("a\n\n"), content="false")
  inspect(@regex.re("b$").matches("ab\r\n"), content="false")
  // \b is Unicode aware but \w is ASCII only
  inspect(@regex.re("\\ba").matches("éa"), content="false")
  inspect(@regex.re("\\w").matches("é"), content="false")
  inspect(@regex.re("\\p{Word}").matches("é"), content="true")
  // unset groups never match a backreference
  inspect(@regex.re("(a)?\\1b").matches("xb"), content="false")
}

///|
test "dot-all flag" {
  inspect(@regex.re("a.b").matches("a\nb"), content="false")
  inspect(@regex.re("a.b", flags="m").matches("a\nb"), content="true")
  inspect(@regex.re("(?m:a.b)").matches("a\nb"), content="true")
}

///|
test "invalid patterns raise" {
  try @regex.compile("(a") catch {
    @regex.RegexError(message~, ..) =>
      inspect(message, content="end pattern with unmatched parenthesis")
  } noraise {
    _ => fail("expected error")
  }
}
