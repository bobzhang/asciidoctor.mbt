///|
/// The milliseconds lexing `text` takes with the lexer of `lang`, checking
/// that the tokens add up to the input.
fn lex_time(lang : String, text : String) -> Int raise {
  let lexer = @rouge.find(lang).unwrap()(Map([]))
  let start = @env.now()
  let tokens = lexer.tokens(text)
  let ms = (@env.now() - start).to_int()
  assert_eq(tokens.map(t => t.1).join(""), text)
  ms
}

///|
/// The fastest of three `lex_time`s, so that one slow run (a collection, a
/// busy CI runner) does not count as the lexer's time.
fn best_lex_time(lang : String, text : String) -> Int raise {
  let mut best = lex_time(lang, text)
  for _ in 0..<2 {
    let ms = lex_time(lang, text)
    if ms < best {
      best = ms
    }
  }
  best
}

///|
/// Whether lexing grows linearly: the input `make` builds for 64 KB takes
/// at most eight times as long as the one for 16 KB, give or take 50 ms of
/// noise. A quadratic lexer takes sixteen times as long.
fn assert_linear_with(lang : String, make : (Int) -> String) -> Unit raise {
  let small = best_lex_time(lang, make(16 * 1024))
  let large = best_lex_time(lang, make(64 * 1024))
  if large > 8 * small + 50 {
    fail("\{lang}: 16 KB in \{small} ms, 64 KB in \{large} ms: not linear")
  }
}

///|
/// `assert_linear_with` for `unit` repeated.
fn assert_linear(lang : String, unit : String) -> Unit raise {
  assert_linear_with(lang, size => unit.repeat(size / unit.length()))
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
  assert_linear("java", "\n")
  // the run ends in `(`, but no signature matches: a number before it
  assert_linear_with("java", size => "a ".repeat(size / 2) + "1(")
  // a signature at the end of a long run
  assert_linear_with("java", size => "a ".repeat(size / 2) + "f(")
}

///|
/// Ruby's heredoc queue is shifted by moving its head, not by removing its
/// first element: many heredocs opened on one line, then their bodies.
test "many heredocs take linear time" {
  assert_linear("ruby", "f(<<A, <<B)\nx\nA\ny\nB\n")
  assert_linear_with("ruby", size => {
    let n = size / 16
    let heads = Array::makei(n, i => "<<H\{i}").join(", ")
    let bodies = Array::makei(n, i => "x\nH\{i}\n").join("")
    "f(\{heads})\n\{bodies}"
  })
}
