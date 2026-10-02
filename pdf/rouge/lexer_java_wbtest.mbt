///|
/// The pre-test of the Java signature rule agrees with the rule itself at
/// every position of every string of up to six characters over an alphabet
/// of what a signature is made of (and what breaks one).
test "the Java signature pre-test is exact" {
  let re = compile(java_signature, "mx")
  let alphabet = ["a", "_", "1", ".", " ", "\n", "(", ";"]
  let mut strings = [""]
  let mut checked = 0
  for _ in 0..<6 {
    let next = []
    for s in strings {
      for c in alphabet {
        next.push(s + c)
      }
    }
    strings = next
    for text in strings {
      // one pre-test per text, its positions in order, as the lexer asks
      let possible = signature_ahead()
      for pos in 0..<text.length() {
        let expected = (re.try_scan_at(text, pos) catch { _ => None })
          is Some(_)
        if possible(text, pos) != expected {
          fail("\{text.escape()} at \{pos}: the rule says \{expected}")
        }
        checked += 1
      }
    }
  }
  assert_true(checked > 1000000)
}
