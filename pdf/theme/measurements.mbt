///|
// asciidoctor-pdf's `Measurements`: units of measurement to PDF points.

///|
/// `to_pt num, units`: the number in points; None for an unknown unit
/// (Ruby raises).
pub fn to_pt(num : Double, units : String) -> Double? {
  match units {
    "" | "pt" => Some(num)
    "in" => Some(num * 72.0)
    "mm" => Some(num * (72.0 / 25.4))
    "cm" => Some(num * (720.0 / 25.4))
    // assuming a canvas of 96 dpi
    "px" => Some(num * 0.75)
    "pc" => Some(num * 12.0)
    _ => None
  }
}

///|
/// Whether `s[i:]` starts with a unit of `(in|mm|cm|p[txc])`; its length.
fn unit_at(s : String, i : Int) -> String? {
  if i + 2 > s.length() {
    return None
  }
  let u = s[i:i + 2].to_owned()
  match u {
    "in" | "mm" | "cm" | "pt" | "px" | "pc" => Some(u)
    _ => None
  }
}

///|
/// `str_to_pt`: `MeasurementValueRx = /(\d+|\d*\.\d+)(in|mm|cm|p[txc])?$/`
/// matched against the value's end, converted; else `to_f`.
pub fn str_to_pt(val : String) -> Double {
  // the unit, if the value ends with one
  let (body, units) = if val.length() >= 2 &&
    unit_at(val, val.length() - 2) is Some(u) {
    (val[:val.length() - 2].to_owned(), u)
  } else {
    (val, "")
  }
  // the number just before it: digits, optionally with one decimal point
  let mut i = body.length()
  while i > 0 && is_digit(body[i - 1].to_int().unsafe_to_char()) {
    i -= 1
  }
  let frac_start = i
  let mut number_start = i
  if i > 0 && body[i - 1] == '.' && frac_start < body.length() {
    let mut j = i - 1
    while j > 0 && is_digit(body[j - 1].to_int().unsafe_to_char()) {
      j -= 1
    }
    number_start = j
  }
  if number_start == body.length() {
    // no number at the end
    if units != "" {
      return ruby_string_to_f(val)
    }
    return ruby_string_to_f(val)
  }
  let num = ruby_string_to_f(body[number_start:].to_owned())
  to_pt(num, units).unwrap_or(num)
}

///|
/// `InsetMeasurementValueRx`:
/// `(?<=^| |\()(-?\d+(?:\.\d+)?)(in|mm|cm|p[txc])(?=$| |\))` — every
/// measurement in the string converted to points (Ruby's `Float#to_s`),
/// when some digit is followed by a unit (`MeasurementValueHintRx`).
pub fn resolve_measurement_values(str : String) -> String {
  // MeasurementValueHintRx: /\d(in|mm|cm|p[txc])/
  let mut hint = false
  for i in 0..<str.length() {
    if is_digit(str[i].to_int().unsafe_to_char()) &&
      unit_at(str, i + 1) is Some(_) {
      hint = true
      break
    }
  }
  if !hint {
    return str
  }
  let sb = StringBuilder()
  let n = str.length()
  let mut i = 0
  while i < n {
    let at_boundary = i == 0 || str[i - 1] == ' ' || str[i - 1] == '('
    if at_boundary {
      match match_inset_measurement(str, i) {
        Some((end, num, units)) => {
          let pt = to_pt(ruby_string_to_f(num), units).unwrap_or(0.0)
          sb.write_string(ruby_float_to_s(pt))
          i = end
          continue
        }
        None => ()
      }
    }
    sb.write_char(str[i].to_int().unsafe_to_char())
    i += 1
  }
  sb.to_string()
}

///|
/// `-?\d+(?:\.\d+)?` then a unit then the end, a space or `)`, at `start`:
/// (end, number, unit).
fn match_inset_measurement(s : String, start : Int) -> (Int, String, String)? {
  let n = s.length()
  let mut i = start
  if i < n && s[i] == '-' {
    i += 1
  }
  let digits_start = i
  while i < n && is_digit(s[i].to_int().unsafe_to_char()) {
    i += 1
  }
  if i == digits_start {
    return None
  }
  // the fraction, when digits follow the point (the regex backtracks over
  // a point without digits)
  if i + 1 < n && s[i] == '.' && is_digit(s[i + 1].to_int().unsafe_to_char()) {
    i += 1
    while i < n && is_digit(s[i].to_int().unsafe_to_char()) {
      i += 1
    }
  }
  guard unit_at(s, i) is Some(units) else { return None }
  let end = i + 2
  if end < n && s[end] != ' ' && s[end] != ')' {
    return None
  }
  Some((end, s[start:i].to_owned(), units))
}
