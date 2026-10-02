///|
/// The token stream as harvest.rb writes it: `shortname:length` (UTF-16
/// code units) per token, separated by spaces.
fn encode_tokens(tokens : Array[(String, String)]) -> String {
  tokens
  .map(t => "\{@rouge.shortname(t.0).unwrap_or("?" + t.0)}:\{t.1.length()}")
  .join(" ")
}

///|
/// Lex `input` with the lexer of `spec` (a language, with cgi-style
/// options) and compare with Rouge's token stream; on a difference, report
/// the first differing token of each side with its text.
fn check_lex(spec : String, input : String, expected : String) -> Unit raise {
  let lexer = match @rouge.find_fancy(spec) {
    Some(l) => l
    None => fail("no lexer for \{spec}")
  }
  let tokens = lexer.tokens(input)
  let text = tokens.map(t => t.1).join("")
  if text != input {
    fail("\{spec}: the tokens do not add up to the input")
  }
  let got = encode_tokens(tokens)
  if got == expected {
    return
  }
  let want = expected.split(" ").map(s => s.to_owned()).collect()
  let mut offset = 0
  for i, tok in tokens {
    let code = "\{@rouge.shortname(tok.0).unwrap_or("?" + tok.0)}:\{tok.1.length()}"
    if i >= want.length() || want[i] != code {
      let context = input.unsafe_substring(
        start=offset,
        end=if offset + 60 < input.length() {
          offset + 60
        } else {
          input.length()
        },
      )
      fail(
        "\{spec}: token \{i} at \{offset}: got \{tok.0} \{tok.1.escape()}, Rouge has \{want.get(i).unwrap_or("nothing")}; text there: \{context.escape()}",
      )
    }
    offset += tok.1.length()
  }
  fail(
    "\{spec}: Rouge has more tokens: \{want[tokens.length():].to_owned().join(" ")}",
  )
}
