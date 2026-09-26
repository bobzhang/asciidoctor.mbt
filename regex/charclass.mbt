///|
/// Binary search in a flattened list of inclusive [lo, hi] ranges.
fn in_ranges(ranges : FixedArray[Int], cp : Int) -> Bool {
  let n = ranges.length() / 2
  for lo = 0, hi = n; lo < hi; {
    let mid = lo + (hi - lo) / 2
    if cp < ranges[2 * mid] {
      continue lo, mid
    } else if cp > ranges[2 * mid + 1] {
      continue mid + 1, hi
    } else {
      break true
    }
  } nobreak {
    false
  }
}

///|
fn is_ascii_word(cp : Int) -> Bool {
  (cp >= 'a' && cp <= 'z') ||
  (cp >= 'A' && cp <= 'Z') ||
  (cp >= '0' && cp <= '9') ||
  cp == '_'
}

///|
/// Unicode word character as used by `\b` and `\p{Word}`.
fn is_unicode_word(cp : Int) -> Bool {
  if cp < 128 {
    is_ascii_word(cp)
  } else {
    in_ranges(word_ranges, cp)
  }
}

///|
fn prop_contains(prop : Prop, cp : Int) -> Bool {
  match prop {
    Alpha =>
      if cp < 128 {
        (cp >= 'a' && cp <= 'z') || (cp >= 'A' && cp <= 'Z')
      } else {
        in_ranges(alpha_ranges, cp)
      }
    Alnum =>
      if cp < 128 {
        (cp >= 'a' && cp <= 'z') ||
        (cp >= 'A' && cp <= 'Z') ||
        (cp >= '0' && cp <= '9')
      } else {
        in_ranges(alnum_ranges, cp)
      }
    Word => is_unicode_word(cp)
    Blank =>
      cp == ' ' || cp == '\t' || (cp >= 128 && in_ranges(blank_ranges, cp))
    Space =>
      if cp < 128 {
        cp == ' ' || (cp >= 0x09 && cp <= 0x0D)
      } else {
        in_ranges(space_ranges, cp)
      }
    Digit => cp >= '0' && cp <= '9'
    Upper => cp >= 'A' && cp <= 'Z'
    Lower => cp >= 'a' && cp <= 'z'
    Punct =>
      (cp >= 0x21 && cp <= 0x2F) ||
      (cp >= 0x3A && cp <= 0x40) ||
      (cp >= 0x5B && cp <= 0x60) ||
      (cp >= 0x7B && cp <= 0x7E)
    Any => true
  }
}

///|
fn item_contains(item : ClassItem, cp : Int) -> Bool {
  match item {
    Range(lo, hi) => cp >= lo && cp <= hi
    AsciiDigit(neg) => (cp >= '0' && cp <= '9') != neg
    AsciiSpace(neg) => (cp == ' ' || (cp >= 0x09 && cp <= 0x0D)) != neg
    AsciiWord(neg) => is_ascii_word(cp) != neg
    AsciiHex(neg) =>
      (
        (cp >= '0' && cp <= '9') ||
        (cp >= 'a' && cp <= 'f') ||
        (cp >= 'A' && cp <= 'F')
      ) !=
      neg
    Prop(p, neg) => prop_contains(p, cp) != neg
    Nested(cls) => cls.contains(cp)
  }
}

///|
fn CharClass::contains_slow(self : CharClass, cp : Int) -> Bool {
  let mut found = false
  for item in self.items {
    if item_contains(item, cp) {
      found = true
      break
    }
  }
  found != self.negated
}

///|
fn CharClass::contains(self : CharClass, cp : Int) -> Bool {
  if cp < 128 && self.ascii.length() == 128 {
    self.ascii[cp]
  } else {
    self.contains_slow(cp)
  }
}

///|
/// Precomputes the ASCII lookup table (recursively for nested classes).
fn CharClass::prepare(self : CharClass) -> Unit {
  for item in self.items {
    if item is Nested(c) {
      c.prepare()
    }
  }
  let table = FixedArray::make(128, false)
  for cp in 0..<128 {
    table[cp] = self.contains_slow(cp)
  }
  self.ascii = table
}
