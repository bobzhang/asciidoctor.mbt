///|
// YAML loading as Ruby's `YAML.safe_load` (Psych 5) does it: the syntax
// comes from moonbit-community/yaml's event parser; the values are built
// here, with Psych's resolution of plain scalars (`ScalarScanner#tokenize`:
// YAML 1.1 booleans such as `yes`/`off`, octal and sexagesimal integers,
// integers with `,`/`_` separators), aliases, merge keys (`<<`), duplicate
// keys (the last value wins, in the first one's place) and the classes
// `safe_load` refuses (dates, times, symbols).

///|
/// Raised when a theme cannot be loaded: malformed YAML, a value
/// `safe_load` refuses, a missing file.
pub suberror ThemeError {
  ThemeError(String)
} derive(Debug)

///|
pub impl Show for ThemeError with fn output(self, logger) {
  let ThemeError(message) = self
  logger.write_string(message)
}

///|
priv enum Frame {
  Seq(Array[Value], Int)
  /// a mapping: its entries, its anchor, the pending key (with whether it
  /// is the merge key `<<`)
  Mapping(Map[String, Value], Int, mut key~ : (String, Bool)?)
}

///|
priv struct Builder {
  stack : Array[Frame]
  anchors : Map[Int, Value]
  mut root : Value?
  mut error : String?
}

///|
impl @yaml.MarkedEventReceiver for Builder with fn on_event(self, ev, mark) {
  if self.error is Some(_) || self.root is Some(_) {
    return
  }
  self.handle(ev) catch {
    ThemeError(message) =>
      self.error = Some("\{message} at line \{mark.line} column \{mark.col}")
  }
}

///|
fn Builder::handle(self : Builder, ev : @yaml.Event) -> Unit raise ThemeError {
  match ev {
    StreamStart | StreamEnd | DocumentStart => ()
    DocumentEnd => if self.root is None { self.root = Some(Null) }
    SequenceStart(id~, ..) => self.stack.push(Seq([], id))
    MappingStart(id~, ..) => self.stack.push(Mapping(Map([]), id, key=None))
    SequenceEnd =>
      match self.stack.pop() {
        Some(Seq(items, id)) => self.insert(Array(items), id, false)
        _ => raise ThemeError("unbalanced sequence")
      }
    MappingEnd =>
      match self.stack.pop() {
        Some(Mapping(map, id, ..)) =>
          self.insert(Hash(map, symbols=false), id, false)
        _ => raise ThemeError("unbalanced mapping")
      }
    Scalar(value~, style~, id~, tag~) => {
      let plain = style is Plain
      let v = if !plain {
        match tag {
          Some(t) => tagged_scalar(t, value, false)
          None => Str(value)
        }
      } else {
        match tag {
          Some(t) => tagged_scalar(t, value, true)
          None => tokenize(value)
        }
      }
      self.insert(v, id, plain && tag is None && value == "<<")
    }
    Alias(id~) =>
      match self.anchors.get(id) {
        Some(v) => self.insert(v, 0, false)
        None => raise ThemeError("unknown alias")
      }
  }
}

///|
fn Builder::insert(
  self : Builder,
  v : Value,
  anchor : Int,
  merge_key : Bool,
) -> Unit {
  if anchor > 0 {
    self.anchors[anchor] = v
  }
  match self.stack.last() {
    None => self.root = Some(v)
    Some(Seq(items, _)) => items.push(v)
    Some(Mapping(_, _, key=None) as frame) =>
      frame.key = Some((hash_key(v), merge_key))
    Some(Mapping(map, _, key=Some((key, is_merge))) as frame) => {
      frame.key = None
      if is_merge {
        // Psych's `revive_hash`: a mapping merges in; a sequence merges its
        // mappings, the earlier ones winning
        match v {
          Hash(other, ..) =>
            for k, x in other {
              map[k] = x
            }
          Array(items) if items.iter().all(i => i is Hash(_, ..)) => {
            let merged : Map[String, Value] = Map([])
            for i = items.length() - 1; i >= 0; i = i - 1 {
              guard items[i] is Hash(other, ..) else { continue }
              for k, x in other {
                merged[k] = x
              }
            }
            for k, x in merged {
              map[k] = x
            }
          }
          _ => map[key] = v
        }
      } else {
        map[key] = v
      }
    }
  }
}

///|
/// A mapping key: theme keys are strings; any other scalar stands for its
/// Ruby `to_s`.
fn hash_key(v : Value) -> String {
  v.to_ruby_s()
}

///|
/// A scalar with an explicit tag (`!!str`, `!!int`, ...).
fn tagged_scalar(
  tag : @yaml.Tag,
  value : String,
  plain : Bool,
) -> Value raise ThemeError {
  let name = if tag.handle == "!!" || tag.handle == "tag:yaml.org,2002:" {
    tag.suffix
  } else {
    raise ThemeError(
      "tried to load unspecified class: \{tag.handle}\{tag.suffix}",
    )
  }
  match name {
    "str" => Str(value)
    "float" =>
      match tokenize(value) {
        Int(i) => Float(i.to_double())
        Float(f) => Float(f)
        _ => raise ThemeError("invalid value for Float(): \{value}")
      }
    "int" | "bool" | "null" => if plain { tokenize(value) } else { Str(value) }
    "seq" | "map" => Str(value)
    _ => raise ThemeError("tried to load unspecified class: !!\{name}")
  }
}

///|
/// Parse YAML text as `YAML.safe_load(text, aliases: true)`: the first
/// document's value (Null for an empty document).
pub fn safe_load(text : String) -> Value raise ThemeError {
  let parser = @yaml.Parser::new(text)
  let builder : Builder = {
    stack: [],
    anchors: Map([]),
    root: None,
    error: None,
  }
  parser.load(builder, false) catch {
    @yaml.YamlError(mark~, info~) =>
      raise ThemeError(
        "(<unknown>): \{info} at line \{mark.line} column \{mark.col}",
      )
  }
  match builder.error {
    Some(e) => raise ThemeError(e)
    None => ()
  }
  builder.root.unwrap_or(Null)
}

///|
fn is_alpha(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') ||
  (c >= 'A' && c <= 'Z') ||
  (
  // beyond ASCII, approximately `[[:alpha:]]`: letters, not spaces,
  // digits, punctuation or symbols
    c.to_int() >= 0xC0 &&
    !c.is_whitespace() &&
    !c.is_numeric() &&
    c.is_printable() &&
    !(c.to_int() >= 0x2000 && c.to_int() < 0x2C00) &&
    !(c.to_int() >= 0x3000 && c.to_int() < 0x3040) &&
    c != '×' &&
    c != '÷'
  )
}

///|
/// `[[:alpha:]_\s!@#$%\^&*(){}<>|/\\~;=]`: the characters of Psych's
/// string-looking prefix.
fn is_wordish(c : Char) -> Bool {
  is_alpha(c) || is_ruby_space(c) || "_!@#$%^&*(){}<>|/\\~;=".contains_char(c)
}

///|
fn all_chars(s : String, f : (Char) -> Bool) -> Bool {
  s.iter().all(f)
}

///|
/// `[-+]?` then the rest.
fn strip_sign(s : String) -> (String, String) {
  if s.has_prefix("-") || s.has_prefix("+") {
    (s[:1].to_owned(), s[1:].to_owned())
  } else {
    ("", s)
  }
}

///|
/// Psych's `INTEGER_LEGACY`.
fn is_legacy_integer(s : String) -> Bool {
  let (_, body) = strip_sign(s)
  if body == "" {
    return false
  }
  let chars = body.iter().collect()
  // base 2: 0b[_,]*[0-1][0-1_,]*
  if body.has_prefix("0b") {
    let rest = chars[2:]
    let mut i = 0
    while i < rest.length() && (rest[i] == '_' || rest[i] == ',') {
      i += 1
    }
    return i < rest.length() &&
      (rest[i] == '0' || rest[i] == '1') &&
      rest[i:].iter().all(c => c == '0' || c == '1' || c == '_' || c == ',')
  }
  // base 16: 0x[_,]*[0-9a-fA-F][0-9a-fA-F_,]*
  if body.has_prefix("0x") {
    let rest = chars[2:]
    let is_hex = (c : Char) => {
      is_digit(c) || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')
    }
    let mut i = 0
    while i < rest.length() && (rest[i] == '_' || rest[i] == ',') {
      i += 1
    }
    return i < rest.length() &&
      is_hex(rest[i]) &&
      rest[i:].iter().all(c => is_hex(c) || c == '_' || c == ',')
  }
  // base 8: 0[_,]*[0-7][0-7_,]*
  if chars[0] == '0' && chars.length() > 1 {
    let rest = chars[1:]
    let mut i = 0
    while i < rest.length() && (rest[i] == '_' || rest[i] == ',') {
      i += 1
    }
    if i < rest.length() &&
      rest[i] >= '0' &&
      rest[i] <= '7' &&
      rest[i:].iter().all(c => (c >= '0' && c <= '7') || c == '_' || c == ',') {
      return true
    }
  }
  // base 10: 0|[1-9](?:[0-9]|,[0-9]|_[0-9])*
  if body == "0" {
    return true
  }
  if !(chars[0] >= '1' && chars[0] <= '9') {
    return false
  }
  let mut i = 1
  while i < chars.length() {
    if is_digit(chars[i]) {
      i += 1
    } else if (chars[i] == ',' || chars[i] == '_') &&
      i + 1 < chars.length() &&
      is_digit(chars[i + 1]) {
      i += 2
    } else {
      return false
    }
  }
  true
}

///|
/// Ruby's `Integer(str)` for what `is_legacy_integer` accepts, with the
/// separators deleted.
fn parse_legacy_integer(s : String) -> Value {
  let cleaned = s.iter().filter(c => c != ',' && c != '_').collect()
  let text = String::from_array(cleaned)
  let (sign, body) = strip_sign(text)
  let (digits, radix) = if body.has_prefix("0b") {
    (body[2:].to_owned(), 2)
  } else if body.has_prefix("0x") {
    (body[2:].to_owned(), 16)
  } else if body.length() > 1 && body.has_prefix("0") {
    (body[1:].to_owned(), 8)
  } else {
    (body, 10)
  }
  let v = @string.parse_int64(digits, base=radix) catch { _ => return Str(s) }
  Int(if sign == "-" { -v } else { v })
}

///|
/// Psych's `FLOAT`: `[-+]?([0-9][0-9_,]*)?\.[0-9]*([eE][-+][0-9]+)?`.
fn is_psych_float(s : String) -> Bool {
  let (_, body) = strip_sign(s)
  let chars : Array[Char] = body.iter().collect()
  let mut i = 0
  if i < chars.length() && is_digit(chars[i]) {
    i += 1
    while i < chars.length() &&
          (is_digit(chars[i]) || chars[i] == '_' || chars[i] == ',') {
      i += 1
    }
  }
  if i >= chars.length() || chars[i] != '.' {
    return false
  }
  i += 1
  while i < chars.length() && is_digit(chars[i]) {
    i += 1
  }
  if i < chars.length() && (chars[i] == 'e' || chars[i] == 'E') {
    i += 1
    if i >= chars.length() || !(chars[i] == '-' || chars[i] == '+') {
      return false
    }
    i += 1
    let start = i
    while i < chars.length() && is_digit(chars[i]) {
      i += 1
    }
    if i == start {
      return false
    }
  }
  i == chars.length()
}

///|
/// `^[-+]?[0-9][0-9_]*(:[0-5]?[0-9]){1,2}` then `$` (integer) or
/// `\.[0-9_]*$` (float); returns the parts.
fn sexagesimal(s : String, float : Bool) -> Array[String]? {
  let (_, body) = strip_sign(s)
  let (main, frac_ok) = if float {
    match body.find(".") {
      Some(i) => {
        let frac = body[i + 1:].to_owned()
        (body[:i].to_owned(), all_chars(frac, c => is_digit(c) || c == '_'))
      }
      None => return None
    }
  } else {
    (body, true)
  }
  if !frac_ok {
    return None
  }
  let parts = main.split(":").map(p => p.to_owned()).collect()
  if parts.length() < 2 || parts.length() > 3 {
    return None
  }
  let head = parts[0]
  if head == "" ||
    !is_digit(head.get_char(0).unwrap_or('x')) ||
    !all_chars(head, c => is_digit(c) || c == '_') {
    return None
  }
  for p in parts[1:] {
    let ok = match p.length() {
      1 => is_digit(p.get_char(0).unwrap_or('x'))
      2 => {
        let a = p.get_char(0).unwrap_or('x')
        a >= '0' && a <= '5' && is_digit(p.get_char(1).unwrap_or('x'))
      }
      _ => false
    }
    if !ok {
      return None
    }
  }
  Some(s.split(":").map(p => p.to_owned()).collect())
}

///|
/// `^-?\d{4}-\d{1,2}-\d{1,2}(?:[Tt]|\s+)\d{1,2}:\d\d:\d\d...`: a
/// timestamp (a Ruby Time, which `safe_load` refuses).
fn looks_like_time(s : String) -> Bool {
  let body = if s.has_prefix("-") { s[1:].to_owned() } else { s }
  let chars : Array[Char] = body.iter().collect()
  let mut i = 0
  let digits = (min : Int, max : Int) => {
    let start = i
    while i < chars.length() && is_digit(chars[i]) && i - start < max {
      i += 1
    }
    i - start >= min
  }
  if !digits(4, 4) || i >= chars.length() || chars[i] != '-' {
    return false
  }
  i += 1
  if !digits(1, 2) || i >= chars.length() || chars[i] != '-' {
    return false
  }
  i += 1
  if !digits(1, 2) || i >= chars.length() {
    return false
  }
  if chars[i] == 'T' || chars[i] == 't' {
    i += 1
  } else if is_ruby_space(chars[i]) {
    while i < chars.length() && is_ruby_space(chars[i]) {
      i += 1
    }
  } else {
    return false
  }
  if !digits(1, 2) || i >= chars.length() || chars[i] != ':' {
    return false
  }
  i += 1
  if !digits(2, 2) || i >= chars.length() || chars[i] != ':' {
    return false
  }
  i += 1
  // the seconds; the fraction and zone are not checked further (a
  // timestamp-looking value is refused either way)
  digits(2, 2)
}

///|
/// `^\d{4}-(?:1[012]|0\d|\d)-(?:[12]\d|3[01]|0\d|\d)$` with a valid date:
/// a Ruby Date, which `safe_load` refuses.
fn looks_like_date(s : String) -> Bool {
  let parts = s.split("-").map(p => p.to_owned()).collect()
  if parts.length() != 3 {
    return false
  }
  let (y, m, d) = (parts[0], parts[1], parts[2])
  if y.length() != 4 || !all_chars(y, is_digit) {
    return false
  }
  if m.length() < 1 || m.length() > 2 || !all_chars(m, is_digit) {
    return false
  }
  if d.length() < 1 || d.length() > 2 || !all_chars(d, is_digit) {
    return false
  }
  let month = @string.parse_int(m) catch { _ => 0 }
  let day = @string.parse_int(d) catch { _ => 0 }
  if m.length() == 2 && m[0] == '1' && month > 12 {
    return false
  }
  if d.length() == 2 && ((d[0] == '3' && day > 31) || d[0] > '3') {
    return false
  }
  // strptime refuses an impossible date (the scalar stays a string)
  let year = @string.parse_int(y) catch { _ => 0 }
  let leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
  let days = [
    31,
    if leap {
      29
    } else {
      28
    },
    31,
    30,
    31,
    30,
    31,
    31,
    30,
    31,
    30,
    31,
  ]
  month >= 1 && month <= 12 && day >= 1 && day <= days[month - 1]
}

///|
/// Psych's `ScalarScanner#tokenize` (strict_integer: false) for a plain
/// scalar.
pub fn tokenize(s : String) -> Value raise ThemeError {
  if s == "" {
    return Null
  }
  let chars : Array[Char] = s.iter().collect()
  // `^[^\d.:-]?[[:alpha:]_\s!@#$%\^&*(){}<>|/\\~;=]+` or a newline
  let wordish = is_wordish(chars[0]) ||
    (
      chars.length() > 1 &&
      !(is_digit(chars[0]) ||
      chars[0] == '.' ||
      chars[0] == ':' ||
      chars[0] == '-') &&
      is_wordish(chars[1])
    )
  if wordish || s.contains("\n") {
    if chars.length() > 5 {
      return Str(s)
    }
    let lower = s.to_lower()
    let first = lower.get_char(0).unwrap_or(' ')
    if !"ytonf~".contains_char(first) {
      return Str(s)
    } else if s == "~" || lower == "null" {
      return Null
    } else if lower == "yes" || lower == "true" || lower == "on" {
      return Bool(true)
    } else if lower == "no" || lower == "false" || lower == "off" {
      return Bool(false)
    } else {
      return Str(s)
    }
  }
  if looks_like_time(s) {
    raise ThemeError("Tried to load unspecified class: Time")
  }
  if looks_like_date(s) {
    raise ThemeError("Tried to load unspecified class: Date")
  }
  let lower = s.to_lower()
  if lower == ".inf" || lower == "+.inf" {
    return Float(@double.infinity)
  }
  if lower == "-.inf" {
    return Float(@double.neg_infinity)
  }
  if lower == ".nan" {
    return Float(@double.not_a_number)
  }
  if chars.length() > 1 && chars[0] == ':' {
    raise ThemeError("Tried to load unspecified class: Symbol")
  }
  match sexagesimal(s, false) {
    Some(parts) => {
      let mut total = 0L
      for e, n in parts {
        let p = (e - 2).abs()
        let mut scale = 1L
        for _ in 0..<p {
          scale = scale * 60L
        }
        total = total + ruby_string_to_i(n) * scale
      }
      return Int(total)
    }
    None => ()
  }
  match sexagesimal(s, true) {
    Some(parts) => {
      let mut total = 0.0
      for e, n in parts {
        let p = (e - 2).abs()
        let mut scale = 1.0
        for _ in 0..<p {
          scale = scale * 60.0
        }
        total = total + ruby_string_to_f(n) * scale
      }
      return Float(total)
    }
    None => ()
  }
  if is_psych_float(s) {
    if s == "." || s == "-." || s == "+." {
      return Str(s)
    }
    // Float(string.delete(',_').gsub(/\.([Ee]|$)/, '\1'))
    let cleaned = String::from_array(
      s.iter().filter(c => c != ',' && c != '_').collect(),
    )
    let cleaned = cleaned
      .replace_all(old=".e", new="e")
      .replace_all(old=".E", new="E")
    let cleaned = if cleaned.has_suffix(".") {
      cleaned[:cleaned.length() - 1].to_owned()
    } else {
      cleaned
    }
    return Float(ruby_string_to_f(cleaned))
  }
  if is_legacy_integer(s) {
    return parse_legacy_integer(s)
  }
  Str(s)
}
