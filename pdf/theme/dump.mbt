///|
// Canonical dumps of theme values and themes, to compare this loader with
// Ruby's (scripts/pdf_theme/harvest.rb writes the same form).

///|
/// A string in double quotes, `"` and `\` escaped, control characters as
/// `\uXXXX`.
fn dump_quote(s : String) -> String {
  let sb = StringBuilder()
  sb.write_char('"')
  for c in s {
    match c {
      '"' | '\\' => {
        sb.write_char('\\')
        sb.write_char(c)
      }
      c if c.to_int() < 0x20 => {
        let hex = c.to_int().to_string(radix=16)
        sb.write_string("\\u")
        for _ in 0..<(4 - hex.length()) {
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
/// A canonical, typed form of the value: `nil`, `true`, `12`, `f12.0` (a
/// Float, as Ruby prints it), `"text"`, `hex"FFFFFF"`, `transparent`,
/// `cmyk[0, 50, 100, 100]`, `[...]`, `{"key" => ...}` (`{:key => ...}`
/// for symbol keys).
pub fn Value::dump(self : Value) -> String {
  match self {
    Null => "nil"
    Bool(b) => b.to_string()
    Int(i) => i.to_string()
    Float(f) => "f" + ruby_float_to_s(f)
    Str(s) => dump_quote(s)
    Hex(s) => "hex" + dump_quote(s)
    Transparent => "transparent"
    Cmyk(items) => "cmyk[" + items.map(v => v.dump()).join(", ") + "]"
    Array(items) => "[" + items.map(v => v.dump()).join(", ") + "]"
    Hash(map, symbols~) => {
      let parts = []
      for k, v in map {
        let key = if symbols { ":" + k } else { dump_quote(k) }
        parts.push(key + " => " + v.dump())
      }
      "{" + parts.join(", ") + "}"
    }
  }
}

///|
/// The theme as `key: value` lines (see `Value::dump`) in the order the
/// keys were set.
pub fn Theme::dump(self : Theme) -> String {
  let lines = []
  for k, v in self.table {
    lines.push("\{k}: \{v.dump()}")
  }
  lines.join("\n")
}
