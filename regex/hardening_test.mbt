// Adversarial tests: supplementary characters, flags, resource bounds and
// invalid patterns. Expected values agree with Ruby 2.6 (Onigmo).

///|
fn matched_all(re : @regex.Regex, s : String) -> Array[String] {
  re.find_all(s).map(m => m.matched())
}

///|
fn offsets_all(re : @regex.Regex, s : String) -> Array[(Int, Int)] {
  re.find_all(s).map(m => (m.begin(), m.end()))
}

///|
/// The error message of compiling `pattern`, or "ok".
fn compile_error(pattern : String, flags? : String = "") -> String {
  try @regex.compile(pattern, flags~) catch {
    @regex.RegexError(message~, ..) => message
  } noraise {
    _ => "ok"
  }
}

///|
test "matches never start inside a surrogate pair" {
  // the lead surrogate of 😀 fails [^😀]; the trail surrogate must not be tried
  let neg = @regex.re("[^😀]")
  debug_inspect(
    neg.find("😀x").map(m => (m.begin(), m.end())),
    content="Some((2, 3))",
  )
  debug_inspect(offsets_all(neg, "😀😀"), content="[]")
  debug_inspect(
    matched_all(@regex.re("."), "a😀b"),
    content=(
      #|["a", "😀", "b"]
    ),
  )
  debug_inspect(
    matched_all(@regex.re("[^a]"), "😀a😀"),
    content=(
      #|["😀", "😀"]
    ),
  )
  debug_inspect(
    matched_all(@regex.re("\\W"), "x😀"),
    content=(
      #|["😀"]
    ),
  )
  debug_inspect(
    matched_all(@regex.re("[😀-😂]+"), "a😀😁😂b😃"),
    content=(
      #|["😀😁😂"]
    ),
  )
  debug_inspect(
    matched_all(@regex.re("\\u{1F600}+"), "😀😀x"),
    content=(
      #|["😀😀"]
    ),
  )
  debug_inspect(
    matched_all(@regex.re("(.)\\1"), "😀😀x"),
    content=(
      #|["😀😀"]
    ),
  )
  // `.$` must take the whole code point before the end
  debug_inspect(
    @regex.re(".$").find("a😀").map(m => m.begin()),
    content="Some(1)",
  )
}

///|
test "word boundaries next to supplementary characters" {
  debug_inspect(
    @regex.re("\\bx").find("😀x").map(m => m.begin()),
    content="Some(2)",
  )
  debug_inspect(
    offsets_all(@regex.re("\\b"), "😀a😀"),
    content="[(2, 2), (3, 3)]",
  )
  // no \B inside the pairs (offsets 1 and 4)
  debug_inspect(
    offsets_all(@regex.re("\\B"), "😀a😀"),
    content="[(0, 0), (5, 5)]",
  )
  inspect(@regex.re("\\B").gsub("😀a😀", "-"), content="-😀a😀-")
  // 𝒜 (U+1D49C) is a word character
  debug_inspect(
    matched_all(@regex.re("\\b\\p{Word}+\\b"), "𝒜bc 𝒜"),
    content=(
      #|["𝒜bc", "𝒜"]
    ),
  )
}

///|
test "lookbehind steps back by code points" {
  // stepping back one code unit would test [^😀] against the lone trail surrogate
  inspect(@regex.re("(?<=[^😀])x").matches("😀x"), content="false")
  inspect(@regex.re("(?<=[^😀])x").matches("ax"), content="true")
  inspect(@regex.re("(?<=😀)x").matches("😀x"), content="true")
  inspect(@regex.re("(?<!😀)x").matches("😀x"), content="false")
  debug_inspect(
    @regex.re("(?<=^.)x").find("😀x").map(m => m.begin()),
    content="Some(2)",
  )
  debug_inspect(
    matched_all(@regex.re("(?<=\\p{Word})\\p{Word}"), "𝒜𝒜"),
    content=(
      #|["𝒜"]
    ),
  )
}

///|
test "empty matches advance by whole code points" {
  debug_inspect(
    offsets_all(@regex.re(""), "😀a😀"),
    content="[(0, 0), (2, 2), (3, 3), (5, 5)]",
  )
  inspect(@regex.re("x*").gsub("😀a😀", "-"), content="-😀-a-😀-")
  debug_inspect(
    @regex.re("").split("😀a😀"),
    content=(
      #|["😀", "a", "😀"]
    ),
  )
  debug_inspect(
    @regex.re("(?=😀)").split("a😀b😀"),
    content=(
      #|["a", "😀b", "😀"]
    ),
  )
}

///|
test "offsets inside a surrogate pair" {
  // a search starting inside a pair starts at the next code point
  debug_inspect(
    @regex.re(".").find("😀x", start=1).map(m => m.matched()),
    content=(
      #|Some("x")
    ),
  )
  debug_inspect(
    @regex.re("").find("😀", start=1).map(m => m.begin()),
    content="Some(2)",
  )
  assert_true(@regex.re(".").match_at("😀x", 1) is None)
  debug_inspect(
    @regex.re(".").match_at("😀x", 2).map(m => m.matched()),
    content=(
      #|Some("x")
    ),
  )
  // unpaired surrogates in the input are single characters
  let lone = "a" + "😀".unsafe_substring(start=0, end=1) + "b"
  inspect(@regex.re("a.b").matches(lone), content="true")
}

///|
test "flags: unknown options are rejected" {
  inspect(compile_error("a", flags="q"), content="unknown regexp option: q")
  inspect(compile_error("a", flags="mg"), content="unknown regexp option: g")
  inspect(compile_error("a", flags="mix"), content="ok")
  inspect(compile_error("(?z)a"), content="undefined group option")
  inspect(compile_error("(?u)\\w"), content="unsupported group option")
  inspect(compile_error("(?i"), content="end pattern in group")
}

///|
test "flags: ignore case" {
  let i = fn(p : String, s : String) { @regex.re(p, flags="i").matches(s) }
  inspect(i("HELLO", "say hello"), content="true")
  inspect(i("[a-z]+", "QUIET"), content="true")
  inspect(i("[^a]", "A"), content="false")
  inspect(i("k", "\u{212A}"), content="true") // KELVIN SIGN
  inspect(i("[a-z]", "\u{212A}"), content="true")
  inspect(i("\\w", "\u{212A}"), content="false") // \w is ASCII and not folded
  inspect(i("σ", "ς"), content="true")
  inspect(i("ǅ", "ǆ"), content="true")
  inspect(i("ß", "ẞ"), content="true")
  inspect(i("𐐀", "𐐨"), content="true") // DESERET (supplementary)
  inspect(i("é", "É"), content="true")
  inspect(i("[à-ÿ]", "À"), content="false") // Onigmo quirk for classes
  inspect(i("\\p{Lower}", "A"), content="true")
  inspect(i("\\P{Lower}", "A"), content="false")
  inspect(i("(a)\\1", "aA"), content="true")
  inspect(i("(?<x>é)\\k<x>", "éÉ"), content="true")
  inspect(@regex.re("(a)\\1").matches("aA"), content="false")
  // multi-character folds are not supported
  inspect(i("ss", "ß"), content="false")
}

///|
test "flags: extended" {
  let x = fn(p : String, s : String) {
    @regex.re(p, flags="x").find(s).map(m => m.matched())
  }
  debug_inspect(x("a b # comment", "xab"), content="Some(\"ab\")")
  debug_inspect(x("a b # c\n c", "abc"), content="Some(\"abc\")")
  debug_inspect(x("[ a]+", " a"), content="Some(\" a\")")
  debug_inspect(x("a\\ b", "a b"), content="Some(\"a b\")")
  debug_inspect(x("a +", "aaa"), content="Some(\"aaa\")")
  debug_inspect(x("\\#", "#"), content="Some(\"#\")")
}

///|
test "inline options follow Onigmo scoping" {
  // an isolated option applies to the rest of the enclosing group, alternatives included
  inspect(@regex.re("a(?i)b|c").matches("c"), content="false")
  inspect(@regex.re("a(?i)b|c").matches("aC"), content="true")
  inspect(@regex.re("(a(?i)b)c").matches("aBc"), content="true")
  inspect(@regex.re("(a(?i)b)c").matches("aBC"), content="false")
  inspect(@regex.re("(?i:a)b").matches("Ab"), content="true")
  inspect(@regex.re("(?i:a)b").matches("AB"), content="false")
  inspect(@regex.re("(?i)a(?-i)b").matches("AB"), content="false")
  inspect(@regex.re("(?x) a  b").matches("ab"), content="true")
  inspect(@regex.re("(?mi)a.").matches("A\n"), content="true")
  inspect(@regex.re("(?-m:.)", flags="m").matches("\n"), content="false")
}

///|
test "escapes and syntax Ruby accepts" {
  inspect(
    @regex.re("\\R").find("a\r\nb").map(m => m.end()).unwrap(),
    content="3",
  )
  debug_inspect(
    @regex.re("a\\Kb").find("ab").map(m => (m.begin(), m.end())),
    content="Some((1, 2))",
  )
  inspect(@regex.re("a\\Kb").gsub("abab", "X"), content="aXaX")
  inspect(@regex.re("\\101\\cA\\C-b").matches("A\u{1}\u{2}"), content="true")
  inspect(@regex.re("\\xC3\\xA9").matches("é"), content="true")
  inspect(@regex.re("(a)\\10").matches("a\u{8}"), content="true") // octal, not group 10
  inspect(@regex.re("[\\1]").matches("\u{1}"), content="true")
  // with named groups, plain groups do not capture
  inspect(@regex.re("(?<n>a)(b)\\k<n>").group_count(), content="1")
  inspect(@regex.re("(?'n'x)\\k'n'").matches("xx"), content="true")
  inspect(@regex.re("(a)\\k<-1>").matches("aa"), content="true")
  // a fixed interval is greedy only: `x{2}?` is `(?:x{2})?`
  debug_inspect(
    @regex.re("x{2}?").find("xxxx").map(m => m.matched()),
    content=(
      #|Some("xx")
    ),
  )
  debug_inspect(
    @regex.re("x{2}?").find("x").map(m => m.matched()),
    content=(
      #|Some("")
    ),
  )
  debug_inspect(
    @regex.re("x{1,2}?").find("xx").map(m => m.matched()),
    content=(
      #|Some("x")
    ),
  )
}

///|
test "invalid patterns raise RegexError" {
  let cases = [
    ("(", "end pattern with unmatched parenthesis"),
    (")", "unmatched close parenthesis"),
    ("a)", "unmatched close parenthesis"),
    ("[a", "premature end of char-class"),
    ("[", "premature end of char-class"),
    ("\\", "too short escape sequence"),
    ("*", "target of repeat operator is not specified"),
    ("a{3,2}", "upper is smaller than lower in repeat range"),
    ("a{100001}", "too big number for repeat range"),
    ("(?<=a+)b", "invalid pattern in look-behind"),
    ("(?<!a*)b", "invalid pattern in look-behind"),
    ("(a)\\2", "invalid backref number/name"),
    ("\\k<zz>", "undefined name <zz> reference"),
    ("(?<1a>x)", "invalid group name <1a>"),
    ("(?<n>a)\\1", "numbered backref/call is not allowed. (use name)"),
    ("\\u{D800}", "invalid Unicode range"),
    ("\\u{110000}", "invalid Unicode range"),
    ("\\u12", "invalid Unicode escape"),
    ("\\xff", "invalid multibyte escape"),
    ("\\377", "invalid multibyte escape"),
    ("\\p{Foo}", "invalid character property name {Foo}"),
    ("[z-a]", "empty range in char class"),
    ("[a-\\d]", "char-class value at end of range"),
    ("\\c", "too short control escape"),
    ("\\X", "\\X (extended grapheme cluster) is not supported"),
    ("\\g<1>(a)", "\\g (subexpression call) is not supported"),
    ("[a&&b]", "class intersection is not supported"),
    ("😀".unsafe_substring(start=0, end=1), "invalid multibyte character"),
  ]
  for c in cases {
    let (pattern, message) = c
    assert_eq(compile_error(pattern), message, msg="pattern /\{pattern}/")
  }
}

///|
test "resource limits on pattern size and nesting" {
  // deep nesting is rejected instead of exhausting the host stack
  let deep = "(".repeat(100000) + "a" + ")".repeat(100000)
  inspect(compile_error(deep), content="parse depth limit over")
  inspect(
    compile_error("a" + "?".repeat(5000)),
    content="parse depth limit over",
  )
  inspect(
    compile_error("[".repeat(5000) + "a" + "]".repeat(5000)),
    content="parse depth limit over",
  )
  inspect(
    compile_error("(?:a{1000}){1000}"),
    content="pattern too large (compiled program exceeds 1000000 instructions)",
  )
  // repeats of empty bodies compile to nothing, quickly
  inspect(compile_error("(?:){100000}{100000}{100000}"), content="ok")
  // nested alternations of required literals compile in linear time
  inspect(
    compile_error("(?:".repeat(200) + "a|a" + ")".repeat(200)),
    content="ok",
  )
}

///|
test "nesting up to the limits works on every backend" {
  // (these sizes are just below MAX_NESTING = 200 / MAX_TREE_DEPTH = 300)
  let n = 199
  let groups = @regex.re("(".repeat(n) + "a" + ")".repeat(n))
  debug_inspect(
    groups.find("xa").map(m => m.group(n)),
    content="Some(Some(\"a\"))",
  )
  inspect(
    compile_error("(".repeat(201) + "a" + ")".repeat(201)),
    content="parse depth limit over",
  )
  // nested lookarounds and atomic groups recurse in the matcher
  let looks = @regex.re("(?=".repeat(n) + "a" + ")".repeat(n) + "a")
  inspect(looks.matches("a"), content="true")
  let atomics = @regex.re("(?>".repeat(n) + "a" + ")".repeat(n))
  inspect(atomics.matches("a"), content="true")
  let behinds = @regex.re("(?<=".repeat(n) + "a" + ")".repeat(n) + "b")
  inspect(behinds.matches("ab"), content="true")
  let classes = @regex.re("[".repeat(n) + "a" + "]".repeat(n))
  inspect(classes.matches("a"), content="true")
  // deep trees: 4 levels per group, 2 per possessive quantifier
  let m = 74
  let deep = @regex.re("(?:a|".repeat(m) + "b" + "){1}{1}".repeat(m))
  inspect(deep.matches("b"), content="true")
  let possessive = @regex.re("a" + "*+".repeat(145) + "b")
  inspect(possessive.matches("aaab"), content="true")
  let atomic_alts = @regex.re("(?>a|".repeat(140) + "b" + ")".repeat(140) + "c")
  inspect(atomic_alts.matches("bc"), content="true")
  let behind_alts = @regex.re(
    "(?<=" + "(?:a|".repeat(140) + "b" + ")".repeat(140) + ")c",
  )
  inspect(behind_alts.matches("bc"), content="true")
}

///|
test "catastrophic backtracking raises RegexTimeout" {
  let re = @regex.re("(a+)+$")
  let s = "a".repeat(30) + "!"
  try re.try_find(s) catch {
    @regex.RegexTimeout(pattern~, limit~) => {
      inspect(pattern, content="(a+)+$")
      assert_true(limit >= 10_000_000)
    }
  } noraise {
    _ => fail("expected RegexTimeout")
  }
  // (explicit small budgets keep these fast; the default one is exercised above)
  let alt = @regex.compile("(a|a)*\\d", step_limit=200_000)
  let long = "a".repeat(3000)
  try alt.try_find_all(long) catch {
    @regex.RegexTimeout(..) => ()
  } noraise {
    _ => fail("expected RegexTimeout")
  }
  try alt.try_replace(long, _ => "") catch {
    @regex.RegexTimeout(..) => ()
  } noraise {
    _ => fail("expected RegexTimeout")
  }
  try alt.try_split(long) catch {
    @regex.RegexTimeout(..) => ()
  } noraise {
    _ => fail("expected RegexTimeout")
  }
  // nested quantifiers inside lookarounds are bounded too
  let look = @regex.compile("(?=(a*)*b)", step_limit=200_000)
  try look.try_find("a".repeat(40)) catch {
    @regex.RegexTimeout(..) => ()
  } noraise {
    _ => fail("expected RegexTimeout")
  }
}

///|
test "step limits are configurable" {
  let tight = @regex.compile("(a|b)*\\d", step_limit=50)
  try tight.try_find("ab".repeat(100)) catch {
    @regex.RegexTimeout(limit~, ..) => inspect(limit, content="50")
  } noraise {
    _ => fail("expected RegexTimeout")
  }
  // linear work well within the default budget
  let text = "word ".repeat(20000) + "end"
  inspect(
    @regex.re("\\bend\\b").find(text).map(m => m.begin()).unwrap(),
    content="100000",
  )
  inspect(@regex.re("(\\w+)\\s").find_all(text).length(), content="20000")
  // polynomial (not exponential) backtracking still completes: quadratic on a
  // long input, cubic on a short one
  assert_true(@regex.re("a*[bc]").find("a".repeat(2000)) is None)
  assert_true(@regex.re("a*a*[bc]").find("a".repeat(150)) is None)
}

///|
test "panic non-raising API aborts on budget exhaustion" {
  ignore(@regex.re("(a+)+$", step_limit=1000).find("a".repeat(40) + "!"))
}
