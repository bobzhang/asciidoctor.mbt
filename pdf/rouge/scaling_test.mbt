///|
/// Lexing time grows linearly with the input: each rule is matched where
/// the scan is (`try_scan_at`), not on a copy of the rest of the input. A
/// copy per step made 64 KB of `x+` take seconds even in a release build;
/// now 64 KB takes about four times as long as 16 KB, well under a second
/// in a debug build. The bound is loose enough for slow machines and still
/// catches the quadratic behaviour.
test "lexing a large block takes linear time" {
  let line = "x+x+x+x+x+x+x+\n"
  let times = []
  for kb in [16, 64] {
    let text = line.repeat(kb * 1024 / line.length())
    let lexer = @rouge.find("ruby").unwrap()(Map([]))
    let start = @env.now()
    let tokens = lexer.tokens(text)
    times.push((@env.now() - start).to_int())
    assert_eq(tokens.map(t => t.1).join(""), text)
  }
  assert_true(times[1] < 5000)
}
