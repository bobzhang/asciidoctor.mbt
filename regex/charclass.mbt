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
/// Next member of `cp`'s case-insensitive equivalence class (cyclic), or `cp`
/// itself when the class is trivial.
fn fold_next_of(cp : Int) -> Int {
  if cp < 0x41 {
    return cp
  }
  for lo = 0, hi = fold_keys.length(); lo < hi; {
    let mid = lo + (hi - lo) / 2
    let k = fold_keys[mid]
    if cp < k {
      continue lo, mid
    } else if cp > k {
      continue mid + 1, hi
    } else {
      break fold_next[mid]
    }
  } nobreak {
    cp
  }
}

///|
/// Whether `a` and `b` are equal ignoring case (Onigmo simple case folding).
fn fold_eq(a : Int, b : Int) -> Bool {
  if a == b {
    return true
  }
  let mut c = fold_next_of(a)
  while c != a {
    if c == b {
      return true
    }
    c = fold_next_of(c)
  }
  false
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
    Digit => in_ranges(digit_ranges, cp)
    Upper => in_ranges(upper_ranges, cp)
    Lower => in_ranges(lower_ranges, cp)
    Letter => in_ranges(letter_ranges, cp)
    UppercaseLetter => in_ranges(lu_ranges, cp)
    LowercaseLetter => in_ranges(ll_ranges, cp)
    Punct => in_ranges(punct_ranges, cp)
    PosixPunct =>
      in_ranges(punct_ranges, cp) ||
      cp == '$' ||
      cp == '+' ||
      cp == '<' ||
      cp == '=' ||
      cp == '>' ||
      cp == '^' ||
      cp == '`' ||
      cp == '|' ||
      cp == '~'
    XDigit =>
      (cp >= '0' && cp <= '9') ||
      (cp >= 'a' && cp <= 'f') ||
      (cp >= 'A' && cp <= 'F')
    Cntrl => cp < 0x20 || (cp >= 0x7F && cp <= 0x9F)
    Ascii => cp < 128
    Any => true
  }
}

///|
/// Whether a property is closed under case folding when `i` is on (Onigmo
/// applies the case-fold closure to the cased properties only).
fn prop_folds(prop : Prop) -> Bool {
  prop is (Upper | Lower | UppercaseLetter | LowercaseLetter)
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
/// Whether some other member of `cp`'s case-equivalence class satisfies `pred`.
/// Like Onigmo (for UTF-8), bracket classes do not case-fold input characters
/// in U+0080..U+00FF: `/[à-ÿ]/i` does not match `À`. The exception is `ß`,
/// which Onigmo reaches through its multi-character fold (`ẞ` = `ss` = `ß`).
fn any_case_variant(cp : Int, pred : (Int) -> Bool) -> Bool {
  if cp >= 0x80 && cp <= 0xFF && cp != 0xDF {
    return false
  }
  let mut c = fold_next_of(cp)
  while c != cp {
    if pred(c) {
      return true
    }
    c = fold_next_of(c)
  }
  false
}

///|
/// Membership of an item under case-insensitive matching: literal ranges and
/// cased properties (before their negation) also match case variants of `cp`.
fn item_contains_fold(item : ClassItem, cp : Int) -> Bool {
  match item {
    Range(lo, hi) =>
      (cp >= lo && cp <= hi) || any_case_variant(cp, c => c >= lo && c <= hi)
    Prop(p, neg) if prop_folds(p) =>
      (prop_contains(p, cp) || any_case_variant(cp, c => prop_contains(p, c))) !=
      neg
    _ => item_contains(item, cp)
  }
}

///|
fn CharClass::contains_slow(self : CharClass, cp : Int) -> Bool {
  let mut found = false
  for item in self.items {
    if (if self.icase {
        item_contains_fold(item, cp)
      } else {
        item_contains(item, cp)
      }) {
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
/// Idempotent: a class shared by several instructions is prepared once.
fn CharClass::prepare(self : CharClass) -> Unit {
  if self.ascii.length() == 128 {
    return
  }
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
