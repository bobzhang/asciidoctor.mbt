///|
/// The milliseconds lexing `unit` repeated to `kb` kilobytes takes with the
/// lexer of `lang`, checking that the tokens add up to the input.
fn lex_time(lang : String, unit : String, kb : Int) -> Int raise {
  let text = unit.repeat(kb * 1024 / unit.length())
  let lexer = @rouge.find(lang).unwrap()(Map([]))
  let start = @env.now()
  let tokens = lexer.tokens(text)
  let ms = (@env.now() - start).to_int()
  assert_eq(tokens.map(t => t.1).join(""), text)
  ms
}

///|
/// Whether lexing grows linearly: four times the input takes at most eight
/// times as long, give or take 50 ms of noise. A quadratic lexer takes
/// sixteen times as long.
fn assert_linear(lang : String, unit : String) -> Unit raise {
  let small = lex_time(lang, unit, 16)
  let large = lex_time(lang, unit, 64)
  if large > 8 * small + 50 {
    fail("\{lang}: 16 KB in \{small} ms, 64 KB in \{large} ms: not linear")
  }
}

///|
/// Each rule is matched where the scan is (`try_scan_at`), not on a copy of
/// the rest of the input, which made 64 KB of `x+` take seconds.
test "lexing takes linear time" {
  assert_linear("ruby", "x+x+x+x+x+x+x+\n")
}

///|
/// The Java method-signature rule scans the run of identifiers and spaces
/// ahead; without its `can_match` it rescans the rest of the run at each
/// identifier.
test "Java identifiers without a signature take linear time" {
  assert_linear("java", "a ")
}

///|
/// Ruby's heredoc queue is shifted by moving its head, not by removing its
/// first element.
test "many heredocs take linear time" {
  assert_linear("ruby", "f(<<A, <<B)\nx\nA\ny\nB\n")
}
