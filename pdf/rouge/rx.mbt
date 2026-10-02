///|
/// A Ruby regex interpolated into another (`#{re}`): Ruby's `Regexp#to_s`,
/// the source in a group that sets the regex's options (`m`, `i`, `x`) and
/// clears the others, `(?-mix:src)` for a regex without options.
pub fn rx(source : String, flags? : String = "") -> String {
  let on = StringBuilder()
  let off = StringBuilder()
  for c in ['m', 'i', 'x'] {
    if flags.contains_char(c) {
      on.write_char(c)
    } else {
      off.write_char(c)
    }
  }
  let off = off.to_string()
  if off == "" {
    "(?\{on}:\{source})"
  } else {
    "(?\{on}-\{off}:\{source})"
  }
}

///|
/// `Regexp.escape`: `s` as a regex that matches it literally.
pub fn rx_escape(s : String) -> String {
  let sb = StringBuilder()
  for c in s {
    match c {
      '.'
      | '*'
      | '?'
      | '+'
      | '^'
      | '$'
      | '|'
      | '('
      | ')'
      | '['
      | ']'
      | '{'
      | '}'
      | '\\'
      | '-' => {
        sb.write_char('\\')
        sb.write_char(c)
      }
      ' ' => sb.write_string("\\ ")
      '\n' => sb.write_string("\\n")
      '\t' => sb.write_string("\\t")
      '\r' => sb.write_string("\\r")
      '\u{0C}' => sb.write_string("\\f")
      '\u{0B}' => sb.write_string("\\v")
      '#' => sb.write_string("\\#")
      _ => sb.write_char(c)
    }
  }
  sb.to_string()
}

///|
/// `words.join('|')`.
pub fn alt(words : Array[String]) -> String {
  words.join("|")
}

///|
/// `%w(...)`: the words of `s`, split at whitespace.
pub fn words(s : String) -> Array[String] {
  let out = []
  let sb = StringBuilder()
  for c in s {
    if c == ' ' || c == '\n' || c == '\t' || c == '\r' {
      if !sb.is_empty() {
        out.push(sb.to_string())
        sb.reset()
      }
    } else {
      sb.write_char(c)
    }
  }
  if !sb.is_empty() {
    out.push(sb.to_string())
  }
  out
}

///|
/// A set of words (`Set.new %w(...)`).
pub fn word_set(s : String) -> Set[String] {
  Set::from_array(words(s))
}
