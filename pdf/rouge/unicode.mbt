///|
/// The ranges of an expandable property, by name as written in `\p{...}`.
fn property_ranges(name : String) -> FixedArray[Int]? {
  let key = StringBuilder()
  for c in name {
    if c != ' ' && c != '_' && c != '-' {
      key.write_char(c.to_ascii_lowercase())
    }
  }
  let key = key.to_string()
  for entry in property_table {
    if entry.0 == key {
      return Some(entry.1)
    }
  }
  None
}

///|
/// One code point as it may appear in a bracket expression.
fn write_class_char(sb : StringBuilder, code : Int) -> Unit {
  if code < 0x80 {
    let c = code.unsafe_to_char()
    if c.is_ascii_alphabetic() || c.is_ascii_digit() {
      sb.write_char(c)
    } else {
      sb.write_string("\\x")
      if code < 0x10 {
        sb.write_char('0')
      }
      sb.write_string(code.to_string(radix=16))
    }
  } else {
    sb.write_string("\\u{\{code.to_string(radix=16)}}")
  }
}

///|
/// The bracket-expression items of `ranges`, or of their complement.
fn class_items(ranges : FixedArray[Int], negate : Bool) -> String {
  let pairs : Array[(Int, Int)] = []
  if negate {
    let mut next = 0
    let mut i = 0
    while i < ranges.length() {
      if ranges[i] > next {
        pairs.push((next, ranges[i] - 1))
      }
      next = ranges[i + 1] + 1
      i += 2
    }
    if next <= 0x10FFFF {
      pairs.push((next, 0x10FFFF))
    }
  } else {
    let mut i = 0
    while i < ranges.length() {
      pairs.push((ranges[i], ranges[i + 1]))
      i += 2
    }
  }
  let sb = StringBuilder()
  for pair in pairs {
    write_class_char(sb, pair.0)
    if pair.1 != pair.0 {
      sb.write_char('-')
      write_class_char(sb, pair.1)
    }
  }
  sb.to_string()
}

///|
/// Rewrite the `\p{...}` (and `\P{...}`, `\p{^...}`) the regex engine does
/// not know (`property_table`) as the code point ranges Onigmo gives them:
/// in a bracket expression as its items, elsewhere as a bracket expression.
fn expand_properties(pattern : String) -> String {
  if !pattern.contains("\\p{") && !pattern.contains("\\P{") {
    return pattern
  }
  let sb = StringBuilder()
  let n = pattern.length()
  let mut depth = 0
  let mut i = 0
  while i < n {
    let c = pattern.unsafe_get(i)
    if c == '\\' && i + 1 < n {
      let e = pattern.unsafe_get(i + 1)
      if (e == 'p' || e == 'P') && i + 2 < n && pattern.unsafe_get(i + 2) == '{' {
        let close = {
          let mut j = i + 3
          while j < n && pattern.unsafe_get(j) != '}' {
            j += 1
          }
          j
        }
        if close < n {
          let mut name = pattern.unsafe_substring(start=i + 3, end=close)
          let mut negate = e == 'P'
          if name.has_prefix("^") {
            negate = !negate
            name = name.unsafe_substring(start=1, end=name.length())
          }
          match property_ranges(name) {
            Some(ranges) => {
              let body = class_items(ranges, negate)
              if depth > 0 {
                sb.write_string(body)
              } else {
                sb.write_string("[\{body}]")
              }
              i = close + 1
              continue
            }
            None => ()
          }
        }
      }
      sb.write_string(pattern.unsafe_substring(start=i, end=i + 2))
      i += 2
      continue
    }
    if c == '[' {
      if depth > 0 && i + 1 < n && pattern.unsafe_get(i + 1) == ':' {
        // a POSIX bracket `[:name:]`
        let mut j = i + 2
        while j + 1 < n &&
              !(pattern.unsafe_get(j) == ':' && pattern.unsafe_get(j + 1) == ']') {
          j += 1
        }
        sb.write_string(pattern.unsafe_substring(start=i, end=j + 2))
        i = j + 2
        continue
      }
      depth += 1
      sb.write_char('[')
      i += 1
      // a `]` right after `[` or `[^` is literal
      if i < n && pattern.unsafe_get(i) == '^' {
        sb.write_char('^')
        i += 1
      }
      if i < n && pattern.unsafe_get(i) == ']' {
        sb.write_char(']')
        i += 1
      }
      continue
    }
    if c == ']' && depth > 0 {
      depth -= 1
    }
    sb.write_string(pattern.unsafe_substring(start=i, end=i + 1))
    i += 1
  }
  sb.to_string()
}
