// Ruby String semantics used by the Asciidoctor port. All offsets are UTF-16
// code units; functions that Ruby defines per character are careful not to
// split surrogate pairs.

///|
/// Ruby whitespace for strip/lstrip: `\t \n \v \f \r` and space.
pub fn is_space(c : UInt16) -> Bool {
  c == ' ' || (c >= 0x09 && c <= 0x0D)
}

///|
/// Ruby `String#lstrip` (leading whitespace; NUL is not stripped).
pub fn lstrip(s : String) -> String {
  let n = s.length()
  let mut i = 0
  while i < n && is_space(s[i]) {
    i += 1
  }
  if i == 0 {
    s
  } else {
    s.unsafe_substring(start=i, end=n)
  }
}

///|
/// Ruby `String#rstrip` (trailing whitespace and NUL).
pub fn rstrip(s : String) -> String {
  let n = s.length()
  let mut j = n
  while j > 0 && (is_space(s[j - 1]) || s[j - 1] == 0) {
    j -= 1
  }
  if j == n {
    s
  } else {
    s.unsafe_substring(start=0, end=j)
  }
}

///|
/// Ruby `String#strip`.
pub fn strip(s : String) -> String {
  rstrip(lstrip(s))
}

///|
/// Ruby `String#chomp` without argument: removes one trailing `\n`, `\r\n` or `\r`.
pub fn chomp(s : String) -> String {
  let n = s.length()
  if n == 0 {
    s
  } else if s[n - 1] == '\n' {
    if n >= 2 && s[n - 2] == '\r' {
      s.unsafe_substring(start=0, end=n - 2)
    } else {
      s.unsafe_substring(start=0, end=n - 1)
    }
  } else if s[n - 1] == '\r' {
    s.unsafe_substring(start=0, end=n - 1)
  } else {
    s
  }
}

///|
/// Ruby `String#chomp(suffix)`.
pub fn chomp_suffix(s : String, suffix : String) -> String {
  if suffix != "" && s.has_suffix(suffix) {
    s.unsafe_substring(start=0, end=s.length() - suffix.length())
  } else {
    s
  }
}

///|
/// Ruby `String#chop`: removes the last character (or `\r\n`).
pub fn chop(s : String) -> String {
  let n = s.length()
  if n == 0 {
    return s
  }
  if s[n - 1] == '\n' && n >= 2 && s[n - 2] == '\r' {
    return s.unsafe_substring(start=0, end=n - 2)
  }
  let c = s[n - 1]
  if c >= 0xDC00 &&
    c <= 0xDFFF &&
    n >= 2 &&
    s[n - 2] >= 0xD800 &&
    s[n - 2] <= 0xDBFF {
    s.unsafe_substring(start=0, end=n - 2)
  } else {
    s.unsafe_substring(start=0, end=n - 1)
  }
}

///|
/// Substring by UTF-16 offsets `[start, end)`, clamped to the string bounds.
pub fn slice(s : String, start : Int, end : Int) -> String {
  let n = s.length()
  let a = if start < 0 { 0 } else if start > n { n } else { start }
  let b = if end < a { a } else if end > n { n } else { end }
  if a == 0 && b == n {
    s
  } else {
    s.unsafe_substring(start=a, end=b)
  }
}

///|
/// Everything from `start` (clamped) to the end.
pub fn from(s : String, start : Int) -> String {
  slice(s, start, s.length())
}

///|
/// The first `n` code units (clamped).
pub fn take(s : String, n : Int) -> String {
  slice(s, 0, n)
}

///|
/// Ruby `String#squeeze(chars)`: collapses runs of the same character that
/// appears in `chars` (all characters when `chars` is empty).
pub fn squeeze(s : String, chars? : String = "") -> String {
  let sb = StringBuilder()
  let mut prev : Char? = None
  let mut changed = false
  for c in s {
    if prev is Some(p) && p == c && (chars == "" || chars.contains_char(c)) {
      changed = true
      continue
    }
    sb.write_char(c)
    prev = Some(c)
  }
  if changed {
    sb.to_string()
  } else {
    s
  }
}

///|
/// Ruby `String#delete(chars)` for a plain set of characters (no ranges).
pub fn delete_chars(s : String, chars : String) -> String {
  let sb = StringBuilder()
  let mut changed = false
  for c in s {
    if chars.contains_char(c) {
      changed = true
    } else {
      sb.write_char(c)
    }
  }
  if changed {
    sb.to_string()
  } else {
    s
  }
}

///|
/// Ruby `String#tr_s(from_chars, to_char)` where `to` is a single character:
/// replaces every character in `from_chars` by `to` and squeezes runs of `to`
/// produced by the translation.
pub fn tr_s(s : String, from_chars : String, to : Char) -> String {
  let sb = StringBuilder()
  let mut last_translated = false
  for c in s {
    if from_chars.contains_char(c) {
      if !last_translated {
        sb.write_char(to)
      }
      last_translated = true
    } else {
      sb.write_char(c)
      last_translated = false
    }
  }
  sb.to_string()
}

///|
/// Ruby `String#split(" ")` (awk-style): splits on runs of whitespace and
/// ignores leading/trailing whitespace.
pub fn split_ws(s : String) -> Array[String] {
  let out = []
  let n = s.length()
  let mut i = 0
  while i < n {
    while i < n && (is_space(s[i]) || s[i] == 0) {
      i += 1
    }
    if i >= n {
      break
    }
    let start = i
    while i < n && !(is_space(s[i]) || s[i] == 0) {
      i += 1
    }
    out.push(s.unsafe_substring(start~, end=i))
  }
  out
}

///|
/// Whether `needle` occurs in `s` at offset `i` (`i + needle.length()` must
/// not exceed `s.length()`).
fn matches_at(s : String, i : Int, needle : String) -> Bool {
  for j in 0..<needle.length() {
    if s.unsafe_get(i + j) != needle.unsafe_get(j) {
      return false
    }
  }
  true
}

///|
/// Ruby `String#split(sep, limit)` with a literal (non-space) separator.
/// With `limit == 0` trailing empty fields are removed; negative keeps them;
/// positive limits the number of fields.
pub fn split(s : String, sep : String, limit? : Int = 0) -> Array[String] {
  let out : Array[String] = []
  let n = s.length()
  if n == 0 {
    return out
  }
  if sep == "" {
    for c in s {
      out.push(c.to_string())
    }
    return out
  }
  let m = sep.length()
  let first = sep.unsafe_get(0)
  let mut start = 0
  let mut i = 0
  while i + m <= n {
    if limit > 0 && out.length() == limit - 1 {
      break
    }
    if s.unsafe_get(i) == first && matches_at(s, i, sep) {
      out.push(s.unsafe_substring(start~, end=i))
      i += m
      start = i
    } else {
      i += 1
    }
  }
  out.push(s.unsafe_substring(start~, end=n))
  if limit == 0 {
    while out.length() > 0 && out[out.length() - 1] == "" {
      out.pop() |> ignore
    }
  }
  out
}

///|
/// Ruby `String#partition(sep)`.
pub fn partition(s : String, sep : String) -> (String, String, String) {
  match s.find(sep) {
    Some(i) =>
      (
        s.unsafe_substring(start=0, end=i),
        sep,
        s.unsafe_substring(start=i + sep.length(), end=s.length()),
      )
    None => (s, "", "")
  }
}

///|
/// Ruby `String#rpartition(sep)`.
pub fn rpartition(s : String, sep : String) -> (String, String, String) {
  match s.rev_find(sep) {
    Some(i) =>
      (
        s.unsafe_substring(start=0, end=i),
        sep,
        s.unsafe_substring(start=i + sep.length(), end=s.length()),
      )
    None => ("", "", s)
  }
}

///|
/// Index of `needle` at or after `from`.
pub fn index_of(s : String, needle : String, from? : Int = 0) -> Int? {
  let n = s.length()
  let m = needle.length()
  if from > n {
    return None
  }
  if from <= 0 {
    return s.find(needle)
  }
  let mut i = from
  while i + m <= n {
    let mut j = 0
    while j < m && s[i + j] == needle[j] {
      j += 1
    }
    if j == m {
      return Some(i)
    }
    i += 1
  }
  None
}

///|
/// Count of non-overlapping occurrences of `needle`.
pub fn count(s : String, needle : String) -> Int {
  if needle == "" {
    return 0
  }
  let mut c = 0
  let mut pos = 0
  while index_of(s, needle, from=pos) is Some(i) {
    c += 1
    pos = i + needle.length()
  }
  c
}

///|
/// Ruby `String#to_i`: parses a leading (optionally signed) decimal integer,
/// allowing single underscores between digits; returns 0 if none.
pub fn to_i(s : String) -> Int {
  let n = s.length()
  let mut i = 0
  while i < n && is_space(s[i]) {
    i += 1
  }
  let mut neg = false
  if i < n && (s[i] == '-' || s[i] == '+') {
    neg = s[i] == '-'
    i += 1
  }
  let mut v = 0L
  let mut seen = false
  while i < n {
    let c = s[i]
    if c >= '0' && c <= '9' {
      v = v * 10L + (c.to_int() - '0').to_int64()
      if v > 0x7FFFFFFFL {
        v = 0x7FFFFFFFL
      }
      seen = true
      i += 1
    } else if c == '_' &&
      seen &&
      i + 1 < n &&
      s[i + 1] >= '0' &&
      s[i + 1] <= '9' {
      i += 1
    } else {
      break
    }
  }
  let r = v.to_int()
  if neg {
    -r
  } else {
    r
  }
}

///|
/// Strict integer parse (Ruby `Integer(str)` for decimal strings); None if invalid.
pub fn parse_int(s : String) -> Int? {
  let t = strip(s)
  let n = t.length()
  if n == 0 {
    return None
  }
  let mut i = 0
  if t[0] == '-' || t[0] == '+' {
    i = 1
  }
  if i >= n {
    return None
  }
  for j in i..<n {
    let c = t[j]
    if !(c >= '0' && c <= '9') && !(c == '_' && j > i && j < n - 1) {
      return None
    }
  }
  Some(to_i(t))
}

///|
/// Ruby `String#to_f` (lenient).
pub fn to_f(s : String) -> Double {
  let t = lstrip(s)
  let n = t.length()
  let mut i = 0
  if i < n && (t[i] == '-' || t[i] == '+') {
    i += 1
  }
  while i < n && t[i] >= '0' && t[i] <= '9' {
    i += 1
  }
  if i < n && t[i] == '.' && i + 1 < n && t[i + 1] >= '0' && t[i + 1] <= '9' {
    i += 1
    while i < n && t[i] >= '0' && t[i] <= '9' {
      i += 1
    }
  }
  let num = t.unsafe_substring(start=0, end=i)
  @string.parse_double(num) catch {
    _ => 0.0
  }
}

///|
fn lookup_case(
  keys : FixedArray[Int],
  vals : FixedArray[String],
  cp : Int,
) -> String? {
  for lo = 0, hi = keys.length(); lo < hi; {
    let mid = lo + (hi - lo) / 2
    if keys[mid] < cp {
      continue mid + 1, hi
    } else if keys[mid] > cp {
      continue lo, mid
    } else {
      break Some(vals[mid])
    }
  } nobreak {
    None
  }
}

///|
/// Ruby `String#downcase` (full Unicode mapping).
pub fn downcase(s : String) -> String {
  let sb = StringBuilder(size_hint=s.length())
  for c in s {
    let cp = c.to_int()
    if cp < 128 {
      sb.write_char(
        if cp >= 'A' && cp <= 'Z' {
          (cp + 32).unsafe_to_char()
        } else {
          c
        },
      )
    } else {
      match lookup_case(lower_keys, lower_vals, cp) {
        Some(m) => sb.write_string(m)
        None => sb.write_char(c)
      }
    }
  }
  sb.to_string()
}

///|
/// Ruby `String#upcase` (full Unicode mapping).
pub fn upcase(s : String) -> String {
  let sb = StringBuilder(size_hint=s.length())
  for c in s {
    let cp = c.to_int()
    if cp < 128 {
      sb.write_char(
        if cp >= 'a' && cp <= 'z' {
          (cp - 32).unsafe_to_char()
        } else {
          c
        },
      )
    } else {
      match lookup_case(upper_keys, upper_vals, cp) {
        Some(m) => sb.write_string(m)
        None => sb.write_char(c)
      }
    }
  }
  sb.to_string()
}

///|
/// ASCII-only lowercase (Ruby `downcase(:ascii)`), cheaper for keywords.
pub fn downcase_ascii(s : String) -> String {
  s.to_lower()
}

///|
/// Ruby `String#succ` for the alphanumeric cases used by Asciidoctor counters.
pub fn succ(s : String) -> String {
  if s == "" {
    return ""
  }
  let chars = s.to_array()
  // find rightmost alphanumeric
  let is_alnum = fn(c : Char) {
    (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')
  }
  let mut has_alnum = false
  for c in chars {
    if is_alnum(c) {
      has_alnum = true
      break
    }
  }
  if !has_alnum {
    // increment last char code point
    let last = chars.length() - 1
    chars[last] = (chars[last].to_int() + 1).unsafe_to_char()
    return String::from_array(chars)
  }
  let mut i = chars.length() - 1
  while i >= 0 {
    let c = chars[i]
    if !is_alnum(c) {
      i -= 1
      continue
    }
    if c == 'z' {
      chars[i] = 'a'
    } else if c == 'Z' {
      chars[i] = 'A'
    } else if c == '9' {
      chars[i] = '0'
    } else {
      chars[i] = (c.to_int() + 1).unsafe_to_char()
      return String::from_array(chars)
    }
    // carry: find next alnum to the left
    let carry = c
    let mut j = i - 1
    while j >= 0 && !is_alnum(chars[j]) {
      j -= 1
    }
    if j < 0 {
      let ins = if carry == 'z' {
        'a'
      } else if carry == 'Z' {
        'A'
      } else {
        '1'
      }
      chars.insert(i, ins)
      return String::from_array(chars)
    }
    i = j
  }
  String::from_array(chars)
}

///|
/// Number of Unicode scalar values (Ruby `String#length`).
pub fn char_length(s : String) -> Int {
  let mut n = 0
  for _ in s {
    n += 1
  }
  n
}

///|
/// UTF-8 byte length (Ruby `String#bytesize`).
pub fn bytesize(s : String) -> Int {
  let mut n = 0
  for c in s {
    let cp = c.to_int()
    n += if cp < 0x80 {
      1
    } else if cp < 0x800 {
      2
    } else if cp < 0x10000 {
      3
    } else {
      4
    }
  }
  n
}

///|
/// Truncates to at most `max` UTF-8 bytes without splitting a character.
pub fn limit_bytesize(s : String, max : Int) -> String {
  let mut n = 0
  let mut end = 0
  for c in s {
    let cp = c.to_int()
    let w = if cp < 0x80 {
      1
    } else if cp < 0x800 {
      2
    } else if cp < 0x10000 {
      3
    } else {
      4
    }
    if n + w > max {
      return s.unsafe_substring(start=0, end~)
    }
    n += w
    end += if cp >= 0x10000 { 2 } else { 1 }
  }
  s
}

///|
/// Ruby `String#capitalize`.
pub fn capitalize(s : String) -> String {
  if s == "" {
    return s
  }
  let w = if s[0] >= 0xD800 && s[0] <= 0xDBFF && s.length() > 1 { 2 } else { 1 }
  let head = s.unsafe_substring(start=0, end=w)
  let tail = s.unsafe_substring(start=w, end=s.length())
  upcase(head) + downcase(tail)
}

///|
/// Ruby `String#*`.
pub fn repeat(s : String, n : Int) -> String {
  let sb = StringBuilder()
  for _ in 0..<n {
    sb.write_string(s)
  }
  sb.to_string()
}

///|
/// Ruby `String#ljust`.
pub fn ljust(s : String, width : Int, pad? : Char = ' ') -> String {
  let len = char_length(s)
  if len >= width {
    return s
  }
  let sb = StringBuilder()
  sb.write_string(s)
  for _ in len..<width {
    sb.write_char(pad)
  }
  sb.to_string()
}

///|
/// Ruby `String#rjust`.
pub fn rjust(s : String, width : Int, pad? : Char = ' ') -> String {
  let len = char_length(s)
  if len >= width {
    return s
  }
  let sb = StringBuilder()
  for _ in len..<width {
    sb.write_char(pad)
  }
  sb.write_string(s)
  sb.to_string()
}

///|
/// Lexicographic comparison by code units (Ruby `String#<=>` for ASCII/BMP text).
/// Note MoonBit's `String::compare` orders by length first.
pub fn lex_compare(a : String, b : String) -> Int {
  let n = if a.length() < b.length() { a.length() } else { b.length() }
  for i in 0..<n {
    let x = a[i].to_int()
    let y = b[i].to_int()
    if x != y {
      return x - y
    }
  }
  a.length() - b.length()
}
