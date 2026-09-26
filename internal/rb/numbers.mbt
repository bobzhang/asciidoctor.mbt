///|
/// Ruby `Float#to_s`: shortest round-trip digits, fixed notation when the
/// decimal exponent is in (-4, 16], exponent notation (`1.0e+20`) otherwise.
pub fn float_to_s(x : Double) -> String {
  if x.is_nan() {
    return "NaN"
  }
  if x.is_inf() {
    return if x > 0.0 { "Infinity" } else { "-Infinity" }
  }
  if x == 0.0 {
    return if 1.0 / x < 0.0 { "-0.0" } else { "0.0" }
  }
  let neg = x < 0.0
  let (digits, decpt) = shortest_digits(if neg { -x } else { x })
  let sb = StringBuilder()
  if neg {
    sb.write_char('-')
  }
  let nd = digits.length()
  if decpt > 0 && decpt <= 15 {
    if nd <= decpt {
      sb.write_string(digits)
      for _ in nd..<decpt {
        sb.write_char('0')
      }
      sb.write_string(".0")
    } else {
      sb.write_string(digits.unsafe_substring(start=0, end=decpt))
      sb.write_char('.')
      sb.write_string(digits.unsafe_substring(start=decpt, end=nd))
    }
  } else if decpt <= 0 && decpt > -4 {
    sb.write_string("0.")
    for _ in 0..<-decpt {
      sb.write_char('0')
    }
    sb.write_string(digits)
  } else {
    sb.write_string(digits.unsafe_substring(start=0, end=1))
    sb.write_char('.')
    if nd > 1 {
      sb.write_string(digits.unsafe_substring(start=1, end=nd))
    } else {
      sb.write_char('0')
    }
    sb.write_char('e')
    let e = decpt - 1
    sb.write_char(if e < 0 { '-' } else { '+' })
    let ae = if e < 0 { -e } else { e }
    if ae < 10 {
      sb.write_char('0')
    }
    sb.write_string(ae.to_string())
  }
  sb.to_string()
}

///|
/// Returns the shortest significant digits and the decimal point position
/// (value = 0.DIGITS * 10^decpt) for a positive finite double.
fn shortest_digits(x : Double) -> (String, Int) {
  // MoonBit's Double::to_string produces the shortest round-trip form,
  // either fixed ("33.3333", "100", "0.00001") or with an exponent ("1e+21").
  let s = x.to_string()
  let mut mant = s
  let mut exp = 0
  match s.find("e") {
    Some(i) => {
      mant = s.unsafe_substring(start=0, end=i)
      exp = to_i(s.unsafe_substring(start=i + 1, end=s.length()))
    }
    None => ()
  }
  // split mantissa into integer and fraction digits
  let (int_part, frac_part) = match mant.find(".") {
    Some(i) =>
      (
        mant.unsafe_substring(start=0, end=i),
        mant.unsafe_substring(start=i + 1, end=mant.length()),
      )
    None => (mant, "")
  }
  let all = int_part + frac_part
  // strip leading zeros
  let mut lead = 0
  while lead < all.length() && all[lead] == '0' {
    lead += 1
  }
  let mut trail = all.length()
  while trail > lead && all[trail - 1] == '0' {
    trail -= 1
  }
  let digits = all.unsafe_substring(start=lead, end=trail)
  let decpt = int_part.length() - lead + exp
  (digits, decpt)
}

///|
/// Ruby `Float#truncate(ndigits)` for positive `ndigits`.
pub fn float_truncate(x : Double, ndigits : Int) -> Double {
  let f = @math.pow(10.0, ndigits.to_double())
  if x >= 0.0 {
    let mul = (x * f).floor()
    let res = (mul + 1.0) / f
    if res > x {
      mul / f
    } else {
      res
    }
  } else {
    let mul = (x * f).ceil()
    let res = (mul - 1.0) / f
    if res < x {
      mul / f
    } else {
      res
    }
  }
}

///|
/// Ruby `Float#round(ndigits)` (round half up) for positive `ndigits`.
pub fn float_round(x : Double, ndigits : Int) -> Double {
  let s = @math.pow(10.0, ndigits.to_double())
  let xs = x * s
  let mut f = xs.round()
  if x > 0.0 {
    if (f + 0.5) / s <= x {
      f += 1.0
    }
  } else if x < 0.0 {
    if (f - 0.5) / s >= x {
      f -= 1.0
    }
  }
  f / s
}

///|
/// Whether the double holds an integral value.
pub fn is_integral(x : Double) -> Bool {
  x == x.floor() && x.abs() < 9.0e15
}

///|
/// Converts an integer to an uppercase roman numeral.
pub fn int_to_roman(n : Int) -> String {
  let values = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1]
  let numerals = [
    "M", "CM", "D", "CD", "C", "XC", "L", "XL", "X", "IX", "V", "IV", "I",
  ]
  let sb = StringBuilder()
  let mut v = n
  for i, val in values {
    while v >= val {
      sb.write_string(numerals[i])
      v -= val
    }
  }
  sb.to_string()
}
