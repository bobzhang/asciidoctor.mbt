///|
// The values of a theme, as Ruby asciidoctor-pdf's ThemeLoader stores them:
// YAML scalars and collections (after Psych's scalar resolution), evaluated,
// with colors kept apart from strings (its `HexColorValue`,
// `TransparentColorValue` and `CMYKColorValue`).

///|
/// A theme value.
pub(all) enum Value {
  Null
  Bool(Bool)
  /// a Ruby Integer
  Int(Int64)
  /// a Ruby Float
  Float(Double)
  Str(String)
  Array(Array[Value])
  /// a Ruby Hash (the font catalog, an admonition icon's settings), in
  /// insertion order; `symbols` when Ruby's keys are symbols
  Hash(Map[String, Value], symbols~ : Bool)
  /// `HexColorValue`: six upper-case hex digits (no `#`)
  Hex(String)
  /// `TransparentColorValue`
  Transparent
  /// `CMYKColorValue`: four components, each an Int or a Float (0..100)
  Cmyk(Array[Value])
} derive(Eq, Debug)

///|
/// Ruby's truthiness: everything but nil and false.
pub fn Value::truthy(self : Value) -> Bool {
  !(self is (Null | Bool(false)))
}

///|
/// Ruby `Numeric === value`.
pub fn Value::is_numeric(self : Value) -> Bool {
  self is (Int(_) | Float(_))
}

///|
/// A number as a Double (Ruby `to_f` of a Numeric).
pub fn Value::as_number(self : Value) -> Double? {
  match self {
    Int(i) => Some(i.to_double())
    Float(f) => Some(f)
    _ => None
  }
}

///|
/// Ruby `to_f`: Numeric, String (leading number), nil (0.0).
pub fn Value::to_f(self : Value) -> Double {
  match self {
    Int(i) => i.to_double()
    Float(f) => f
    Str(s) | Hex(s) => ruby_string_to_f(s)
    _ => 0.0
  }
}

///|
/// Ruby's `to_s` of the value (what `"#{value}"` and `gsub` blocks produce).
pub fn Value::to_ruby_s(self : Value) -> String {
  match self {
    Null => ""
    Bool(b) => b.to_string()
    Int(i) => i.to_string()
    Float(f) => ruby_float_to_s(f)
    Str(s) | Hex(s) => s
    Transparent => "transparent"
    Array(_) | Hash(_, ..) => self.inspect_ruby()
    // CMYKColorValue#to_s
    Cmyk(items) => "[" + items.map(v => v.to_ruby_s()).join(", ") + "]"
  }
}

///|
/// Ruby's `inspect` of the value (Array#to_s and Hash#to_s use it).
pub fn Value::inspect_ruby(self : Value) -> String {
  match self {
    Null => "nil"
    Str(s) | Hex(s) => ruby_string_inspect(s)
    Transparent => ruby_string_inspect("transparent")
    Array(items) | Cmyk(items) =>
      "[" + items.map(v => v.inspect_ruby()).join(", ") + "]"
    Hash(map, symbols~) => {
      if map.is_empty() {
        return "{}"
      }
      let parts = []
      for k, v in map {
        if symbols {
          parts.push("\{k}: \{v.inspect_ruby()}")
        } else {
          parts.push("\{ruby_string_inspect(k)} => \{v.inspect_ruby()}")
        }
      }
      "{" + parts.join(", ") + "}"
    }
    _ => self.to_ruby_s()
  }
}

///|
/// Ruby's `String#inspect` for the strings a theme holds: printable
/// characters as they are, the usual escapes for the rest.
fn ruby_string_inspect(s : String) -> String {
  let sb = StringBuilder()
  sb.write_char('"')
  for i, c in s {
    match c {
      '"' => sb.write_string("\\\"")
      '\\' => sb.write_string("\\\\")
      '\n' => sb.write_string("\\n")
      '\t' => sb.write_string("\\t")
      '\r' => sb.write_string("\\r")
      '\u{0C}' => sb.write_string("\\f")
      '\u{0B}' => sb.write_string("\\v")
      '\u{08}' => sb.write_string("\\b")
      '\u{07}' => sb.write_string("\\a")
      '\u{1B}' => sb.write_string("\\e")
      '#' => {
        // `#{`, `#$` and `#@` would interpolate
        let next = s.get_char(i + 1)
        if next is Some('{' | '$' | '@') {
          sb.write_string("\\#")
        } else {
          sb.write_char('#')
        }
      }
      c if c.to_int() < 0x20 || c.to_int() == 0x7F => {
        let hex = c.to_int().to_string(radix=16).to_upper()
        sb.write_string("\\x")
        if hex.length() < 2 {
          sb.write_char('0')
        }
        sb.write_string(hex)
      }
      c => sb.write_char(c)
    }
  }
  sb.write_char('"')
  sb.to_string()
}

///|
/// Ruby's `Float#to_s`: the shortest representation that round-trips, in
/// fixed notation (with at least one fractional digit) when the decimal
/// exponent is between -4 and 16, else `d.ddde+XX`.
pub fn ruby_float_to_s(f : Double) -> String {
  if f.is_nan() {
    return "NaN"
  }
  if f.is_pos_inf() {
    return "Infinity"
  }
  if f.is_neg_inf() {
    return "-Infinity"
  }
  if f == 0.0 {
    return if 1.0 / f < 0.0 { "-0.0" } else { "0.0" }
  }
  let negative = f < 0.0
  // shortest digits and the decimal point's position (value = 0.DIGITS ×
  // 10^decpt), from MoonBit's own shortest representation
  let repr = f.abs().to_string()
  let (mantissa, exp) = match repr.find("e") {
    Some(i) =>
      (
        repr[:i].to_owned(),
        @string.parse_int(repr[i + 1:].to_owned()) catch {
          _ => 0
        },
      )
    None => (repr, 0)
  }
  let (int_part, frac_part) = match mantissa.find(".") {
    Some(i) => (mantissa[:i].to_owned(), mantissa[i + 1:].to_owned())
    None => (mantissa, "")
  }
  let mut digits = int_part + frac_part
  let mut decpt = int_part.length() + exp
  // strip leading zeros (0.0001 → digits 00001)
  let mut lead = 0
  while lead < digits.length() - 1 && digits[lead] == '0' {
    lead += 1
  }
  digits = digits[lead:].to_owned()
  decpt -= lead
  // strip trailing zeros (100 → 1)
  let mut end = digits.length()
  while end > 1 && digits[end - 1] == '0' {
    end -= 1
  }
  digits = digits[:end].to_owned()
  let sb = StringBuilder()
  if negative {
    sb.write_char('-')
  }
  let n = digits.length()
  if decpt > 15 || decpt < -3 {
    sb.write_string(digits[:1].to_owned())
    sb.write_char('.')
    sb.write_string(if n > 1 { digits[1:].to_owned() } else { "0" })
    let e = decpt - 1
    sb.write_char('e')
    sb.write_char(if e < 0 { '-' } else { '+' })
    let abs = if e < 0 { -e } else { e }
    if abs < 10 {
      sb.write_char('0')
    }
    sb.write_string(abs.to_string())
  } else if decpt <= 0 {
    sb.write_string("0.")
    for _ in 0..<-decpt {
      sb.write_char('0')
    }
    sb.write_string(digits)
  } else if decpt >= n {
    sb.write_string(digits)
    for _ in 0..<(decpt - n) {
      sb.write_char('0')
    }
    sb.write_string(".0")
  } else {
    sb.write_string(digits[:decpt].to_owned())
    sb.write_char('.')
    sb.write_string(digits[decpt:].to_owned())
  }
  sb.to_string()
}

///|
fn is_digit(c : Char) -> Bool {
  c >= '0' && c <= '9'
}

///|
fn is_ruby_space(c : Char) -> Bool {
  c == ' ' ||
  c == '\t' ||
  c == '\n' ||
  c == '\r' ||
  c == '\u{0B}' ||
  c == '\u{0C}'
}

///|
/// Digits with single underscores between them (Ruby's number literals in
/// `to_f`/`to_i`), from `start`; returns the end and the digits.
fn scan_digits(s : String, start : Int) -> (Int, String) {
  let sb = StringBuilder()
  let mut i = start
  while i < s.length() {
    let c = s[i].to_int().unsafe_to_char()
    if is_digit(c) {
      sb.write_char(c)
      i += 1
    } else if c == '_' &&
      sb.to_string() != "" &&
      i + 1 < s.length() &&
      is_digit(s[i + 1].to_int().unsafe_to_char()) {
      i += 1
    } else {
      break
    }
  }
  (i, sb.to_string())
}

///|
/// Ruby's `String#to_f`: the longest leading decimal number (after
/// whitespace), else 0.0.
pub fn ruby_string_to_f(s : String) -> Double {
  let mut i = 0
  while i < s.length() && is_ruby_space(s[i].to_int().unsafe_to_char()) {
    i += 1
  }
  let sb = StringBuilder()
  if i < s.length() && (s[i] == '-' || s[i] == '+') {
    sb.write_char(s[i].to_int().unsafe_to_char())
    i += 1
  }
  let (after_int, int_digits) = scan_digits(s, i)
  i = after_int
  sb.write_string(if int_digits == "" { "0" } else { int_digits })
  if i + 1 < s.length() && s[i] == '.' {
    let (after_frac, frac_digits) = scan_digits(s, i + 1)
    if frac_digits != "" {
      sb.write_char('.')
      sb.write_string(frac_digits)
      i = after_frac
    }
  }
  if int_digits == "" && !sb.to_string().contains(".") {
    return 0.0
  }
  if i < s.length() && (s[i] == 'e' || s[i] == 'E') {
    let mut j = i + 1
    let exp = StringBuilder()
    if j < s.length() && (s[j] == '-' || s[j] == '+') {
      exp.write_char(s[j].to_int().unsafe_to_char())
      j += 1
    }
    let (_, exp_digits) = scan_digits(s, j)
    if exp_digits != "" {
      sb.write_char('e')
      sb.write_string(exp.to_string())
      sb.write_string(exp_digits)
    }
  }
  @string.parse_double(sb.to_string()) catch {
    _ => 0.0
  }
}

///|
/// Ruby's `String#to_i`: the leading decimal integer (after whitespace),
/// else 0.
pub fn ruby_string_to_i(s : String) -> Int64 {
  let mut i = 0
  while i < s.length() && is_ruby_space(s[i].to_int().unsafe_to_char()) {
    i += 1
  }
  let mut negative = false
  if i < s.length() && (s[i] == '-' || s[i] == '+') {
    negative = s[i] == '-'
    i += 1
  }
  let (_, digits) = scan_digits(s, i)
  if digits == "" {
    return 0L
  }
  let v = @string.parse_int64(digits) catch { _ => 0L }
  if negative {
    -v
  } else {
    v
  }
}

///|
/// Ruby's `Float#to_i` (truncation), saturating where Ruby would grow a
/// Bignum.
fn float_to_i(f : Double) -> Int64 {
  if f.is_nan() {
    return 0L
  }
  let t = if f < 0.0 { -(-f).floor() } else { f.floor() }
  if t >= 9.2e18 {
    9223372036854775807L
  } else if t <= -9.2e18 {
    -9223372036854775807L
  } else {
    t.to_int64()
  }
}
