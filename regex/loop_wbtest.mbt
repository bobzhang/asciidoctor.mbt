///|
/// Result of one search in the differential loop test: the offsets (or "none"
/// or "timeout") and the steps it used.
fn loop_probe(re : Regex, input : String, start : Int) -> String {
  let vm = re.acquire(input)
  defer re.release(vm)
  let before = vm.fuel
  let result = re.find_with(vm, start) catch {
    RegexTimeout(_) => return "timeout steps=\{before - vm.fuel}"
  }
  // the matcher is left clean for the next attempt (see `Regex::try_at`)
  if vm.caps.iter().any(c => c != -1) || vm.regs.iter().any(r => r != -1) {
    return "dirty matcher state"
  }
  let result = match result {
    Some(m) => {
      let sb = StringBuilder()
      for o in m.offsets {
        sb.write_string("\{o} ")
      }
      sb.to_string()
    }
    None => "none"
  }
  "\{result} steps=\{before - vm.fuel}"
}

///|
test "Star loops behave exactly like their Split expansion" {
  let patterns = [
    ("a*", ""),
    ("a*?", ""),
    ("(.*)$", ""),
    ("(.*)(.)", ""),
    ("([^a]*)(.)b", ""),
    ("(.*?)(.)$", ""),
    (".*?b", ""),
    ("(.*?)(b+)", ""),
    ("^[ \\t]*(-|\\*\\**|\\u2022)[ \\t]+(.*)$", ""),
    ("(\\S|\\S.*?\\S)_", ""),
    ("x[^x]*x", ""),
    ("[\\p{Alpha}]*\\d", ""),
    ("(a).*\\1", ""),
    ("(?<=a.)b", ""),
    ("(?=.*c)a", ""),
    ("(?!.*?z).+", ""),
    ("(?>.*)b", ""),
    (".*", "m"),
    ("[ab]*?c", "i"),
    ("😀*b", ""),
    ("(?:😀)*b", ""),
    ("[😀a]*b", ""),
    ("x\\s*", ""),
    ("[^😀]*b", ""),
    (".*.*.*=", ""),
    ("(a|b.*)*c", ""),
  ]
  let lead = "😀".unsafe_substring(start=0, end=1)
  let trail = "😀".unsafe_substring(start=1, end=2)
  let inputs = [
    "",
    "a",
    "aaab",
    "b",
    "- item text",
    "  * nested item\nnext",
    "x_y_ foo_",
    "xax xbx",
    "abc123",
    "aaa",
    "ab\nab",
    "cab",
    "a😀😀b",
    "😀b" + lead,
    trail + "a" + lead + "b",
    "a" + trail + "😀" + lead + lead + "b",
    "zzz",
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    "ABcC",
  ]
  for p in patterns {
    let (src, flags) = p
    for limit in [0, 40] {
      let with_star = compile_with(src, flags, limit, true) catch {
        RegexError(message~, ..) => fail("/\{src}/: \{message}")
      }
      let without = compile_with(src, flags, limit, false)
      assert_true(with_star.prog.length() == without.prog.length())
      for input in inputs {
        for start in 0..<=input.length() {
          let a = loop_probe(with_star, input, start)
          let b = loop_probe(without, input, start)
          if a != b {
            fail(
              "/\{src}/\{flags} (limit \{limit}) on \{input.escape()} from \{start}: \{a} vs \{b}",
            )
          }
        }
      }
    }
  }
}
