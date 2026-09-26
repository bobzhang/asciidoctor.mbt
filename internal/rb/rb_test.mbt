// Expected values come from Ruby 2.6.

///|
test "strip family" {
  debug_inspect(@rb.strip("\u{0} a \u{0}"), content="\"\\u{00} a\"")
  debug_inspect(@rb.lstrip("\u{0} a \u{0}"), content="\"\\u{00} a \\u{00}\"")
  debug_inspect(
    @rb.strip("\u{a0}a\u{a0}"),
    content=(
      #|" a "
    ),
  )
  debug_inspect(@rb.strip("\u{b}\u{c}a"), content="\"a\"")
}

///|
test "case mapping" {
  inspect(@rb.downcase("ÉCOLE ß İ"), content="école ß i̇")
  inspect(@rb.upcase("straße"), content="STRASSE")
  inspect(@rb.capitalize("éa"), content="Éa")
}

///|
test "float formatting" {
  inspect(@rb.float_to_s(1.0e-5), content="1.0e-05")
  inspect(@rb.float_to_s(1.0e20), content="1.0e+20")
  inspect(@rb.float_to_s(1.0e16), content="1.0e+16")
  inspect(@rb.float_to_s(1.0e15), content="1.0e+15")
  inspect(@rb.float_to_s(0.0001), content="0.0001")
  inspect(@rb.float_to_s(100.0), content="100.0")
  inspect(@rb.float_to_s(12.5), content="12.5")
  inspect(@rb.float_to_s(@rb.float_truncate(100.0 / 3.0, 4)), content="33.3333")
  inspect(@rb.float_to_s(@rb.float_round(33.33333, 4)), content="33.3333")
}

///|
test "to_i" {
  debug_inspect(
    ["12abc", " 12", "1_000", "-3x", "+4", "0x1A", "", "abc", "1__2"].map(
      @rb.to_i,
    ),
    content="[12, 12, 1000, -3, 4, 0, 0, 0, 1]",
  )
}

///|
test "split" {
  debug_inspect(@rb.split_ws("a  b\tc\n"), content="[\"a\", \"b\", \"c\"]")
  debug_inspect(@rb.split_ws(" a b "), content="[\"a\", \"b\"]")
  debug_inspect(@rb.split("a,b,,", ","), content="[\"a\", \"b\"]")
  debug_inspect(
    @rb.split("a,b,,", ",", limit=-1),
    content="[\"a\", \"b\", \"\", \"\"]",
  )
  debug_inspect(@rb.split("abc", ""), content="[\"a\", \"b\", \"c\"]")
  debug_inspect(@rb.split("a=b=c", "=", limit=2), content="[\"a\", \"b=c\"]")
}

///|
test "succ" {
  debug_inspect(
    ["az", "zz", "a9", "Zz", "1.9"].map(@rb.succ),
    content="[\"ba\", \"aaa\", \"b0\", \"AAa\", \"2.0\"]",
  )
}
