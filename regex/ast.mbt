///|
/// Error raised when a pattern cannot be compiled.
pub suberror RegexError {
  RegexError(pattern~ : String, pos~ : Int, message~ : String)
} derive(Debug)

///|
pub extend RegexError with Debug::{to_repr}

///|
/// A character-set item. Code points are Unicode scalar values.
priv enum ClassItem {
  Range(Int, Int)
  AsciiDigit(Bool) // \d (ASCII) ; Bool = negated
  AsciiSpace(Bool) // \s (ASCII: space, \t \n \v \f \r)
  AsciiWord(Bool) // \w (ASCII)
  AsciiHex(Bool) // \h (ASCII hex digit)
  Prop(Prop, Bool) // \p{...} / \P{...}
  Nested(CharClass) // nested [..]
}

///|
priv enum Prop {
  Alpha
  Alnum
  Word
  Blank
  Space
  Digit
  Upper
  Lower
  Punct
  Any
}

///|
priv struct CharClass {
  items : Array[ClassItem]
  negated : Bool
  // ASCII fast path: bit set for code points 0..127, computed after parsing
  mut ascii : FixedArray[Bool]
}

///|
priv enum AssertKind {
  BeginLine // ^
  EndLine // $
  BeginText // \A
  EndText // \z
  EndTextOptNewline // \Z
  WordBoundary // \b
  NotWordBoundary // \B
  SearchStart // \G
} derive(Eq)

///|
priv enum Node {
  Empty
  Char(Int) // literal code point
  Any(Bool) // `.`; Bool = dot-all
  Class(CharClass)
  Concat(Array[Node])
  Alt(Array[Node])
  Group(Int?, Node) // capture index (1-based) or non-capturing
  Repeat(Node, Int, Int, Greed) // min, max (-1 = unbounded)
  Assert(AssertKind)
  Backref(Int)
  NamedBackref(String)
  Look(Node, Bool, Bool) // ahead?, negated?
  Atomic(Node)
}

///|
priv enum Greed {
  Greedy
  Lazy
  Possessive
} derive(Eq)

///|
priv struct Parser {
  src : String
  mut pos : Int
  mut ncaps : Int
  names : Map[String, Int]
  mut dotall : Bool
}

///|
fn Parser::fail(self : Parser, msg : String) -> RegexError {
  RegexError(pattern=self.src, pos=self.pos, message=msg)
}

///|
fn Parser::eof(self : Parser) -> Bool {
  self.pos >= self.src.length()
}

///|
fn Parser::peek(self : Parser) -> Int {
  if self.pos < self.src.length() {
    self.src[self.pos].to_int()
  } else {
    -1
  }
}

///|
fn Parser::peek_at(self : Parser, off : Int) -> Int {
  let p = self.pos + off
  if p < self.src.length() {
    self.src[p].to_int()
  } else {
    -1
  }
}

///|
/// Reads one code point (combining surrogate pairs).
fn Parser::next_cp(self : Parser) -> Int {
  let c = self.src[self.pos].to_int()
  self.pos += 1
  if c >= 0xD800 && c <= 0xDBFF && self.pos < self.src.length() {
    let d = self.src[self.pos].to_int()
    if d >= 0xDC00 && d <= 0xDFFF {
      self.pos += 1
      return 0x10000 + ((c - 0xD800) << 10) + (d - 0xDC00)
    }
  }
  c
}

///|
fn parse_pattern(
  src : String,
  dotall : Bool,
) -> (Node, Int, Map[String, Int]) raise RegexError {
  let p = { src, pos: 0, ncaps: 0, names: {}, dotall, }
  let node = p.parse_alt()
  if !p.eof() {
    raise p.fail("unmatched ')'")
  }
  (node, p.ncaps, p.names)
}

///|
fn Parser::parse_alt(self : Parser) -> Node raise RegexError {
  let branches = [self.parse_concat()]
  while self.peek() == '|' {
    self.pos += 1
    branches.push(self.parse_concat())
  }
  if branches.length() == 1 {
    branches[0]
  } else {
    Alt(branches)
  }
}

///|
fn Parser::parse_concat(self : Parser) -> Node raise RegexError {
  let items : Array[Node] = []
  while !self.eof() {
    let c = self.peek()
    if c == '|' || c == ')' {
      break
    }
    let atom = self.parse_atom()
    guard atom is Some(atom) else { continue }
    items.push(self.parse_quantifiers(atom))
  }
  match items.length() {
    0 => Empty
    1 => items[0]
    _ => Concat(items)
  }
}

///|
/// Parses quantifiers following an atom (possibly several, e.g. `a{2}?`).
fn Parser::parse_quantifiers(self : Parser, atom : Node) -> Node {
  let mut node = atom
  while !self.eof() {
    let c = self.peek()
    let (min, max) = if c == '*' {
      self.pos += 1
      (0, -1)
    } else if c == '+' {
      self.pos += 1
      (1, -1)
    } else if c == '?' {
      self.pos += 1
      (0, 1)
    } else if c == '{' {
      match self.try_interval() {
        Some(r) => r
        None => break
      }
    } else {
      break
    }
    let greed = if self.peek() == '?' {
      self.pos += 1
      Lazy
    } else if self.peek() == '+' && c != '{' {
      self.pos += 1
      Possessive
    } else {
      Greedy
    }
    if node is (Assert(_) | Look(_, _, _)) {
      // Onigmo allows quantified anchors; treat `x?`-like as optional.
      node = if min == 0 { Empty } else { node }
      continue
    }
    node = Repeat(node, min, max, greed)
  }
  node
}

///|
/// Tries to parse `{n}`, `{n,}`, `{,m}` or `{n,m}` at the current position.
/// Returns None (without consuming) if it is not a valid interval, in which
/// case Ruby treats `{` as a literal.
fn Parser::try_interval(self : Parser) -> (Int, Int)? {
  let save = self.pos
  self.pos += 1
  let read_int = fn() -> Int? {
    let start = self.pos
    let mut n = 0
    while self.peek() >= '0' && self.peek() <= '9' {
      n = n * 10 + (self.peek() - '0')
      self.pos += 1
    }
    if self.pos == start {
      None
    } else {
      Some(n)
    }
  }
  let lo = read_int()
  let result = if self.peek() == '}' {
    match lo {
      Some(n) => {
        self.pos += 1
        Some((n, n))
      }
      None => None
    }
  } else if self.peek() == ',' {
    self.pos += 1
    let hi = read_int()
    if self.peek() == '}' && (lo is Some(_) || hi is Some(_)) {
      self.pos += 1
      Some((lo.unwrap_or(0), hi.unwrap_or(-1)))
    } else {
      None
    }
  } else {
    None
  }
  if result is None {
    self.pos = save
  }
  result
}

///|
fn Parser::parse_atom(self : Parser) -> Node? raise RegexError {
  let c = self.peek()
  match c {
    '(' => Some(self.parse_group())
    '[' => {
      self.pos += 1
      Some(Class(self.parse_class()))
    }
    '.' => {
      self.pos += 1
      Some(Any(self.dotall))
    }
    '^' => {
      self.pos += 1
      Some(Assert(BeginLine))
    }
    '$' => {
      self.pos += 1
      Some(Assert(EndLine))
    }
    '\\' => Some(self.parse_escape())
    '*' | '+' | '?' =>
      raise self.fail("target of repeat operator is not specified")
    _ => Some(Char(self.next_cp()))
  }
}

///|
fn Parser::parse_group(self : Parser) -> Node raise RegexError {
  self.pos += 1 // (
  if self.peek() == '?' {
    self.pos += 1
    let c = self.peek()
    match c {
      ':' => {
        self.pos += 1
        let n = self.parse_alt()
        self.expect_close()
        Group(None, n)
      }
      '=' | '!' => {
        self.pos += 1
        let n = self.parse_alt()
        self.expect_close()
        Look(n, true, c == '!')
      }
      '>' => {
        self.pos += 1
        let n = self.parse_alt()
        self.expect_close()
        Atomic(n)
      }
      '<' => {
        let c2 = self.peek_at(1)
        if c2 == '=' || c2 == '!' {
          self.pos += 2
          let n = self.parse_alt()
          self.expect_close()
          Look(n, false, c2 == '!')
        } else {
          self.pos += 1
          let name = self.read_name('>')
          self.ncaps += 1
          let idx = self.ncaps
          self.names[name] = idx
          let n = self.parse_alt()
          self.expect_close()
          Group(Some(idx), n)
        }
      }
      '#' => {
        // comment group
        while !self.eof() && self.peek() != ')' {
          self.pos += 1
        }
        self.expect_close()
        Empty
      }
      _ => self.parse_flag_group()
    }
  } else {
    self.ncaps += 1
    let idx = self.ncaps
    let n = self.parse_alt()
    self.expect_close()
    Group(Some(idx), n)
  }
}

///|
/// Parses `(?m)`, `(?-m)`, `(?m:...)`; only the `m` (dot-all) flag is supported.
fn Parser::parse_flag_group(self : Parser) -> Node raise RegexError {
  let saved = self.dotall
  let mut on = true
  while !self.eof() {
    match self.peek() {
      'm' => {
        self.dotall = on
        self.pos += 1
      }
      '-' => {
        on = false
        self.pos += 1
      }
      ':' => {
        self.pos += 1
        let n = self.parse_alt()
        self.expect_close()
        self.dotall = saved
        return Group(None, n)
      }
      ')' => {
        // flags apply to the rest of the enclosing group
        self.pos += 1
        return Empty
      }
      _ => raise self.fail("unsupported group option")
    }
  }
  raise self.fail("end pattern in group")
}

///|
fn Parser::expect_close(self : Parser) -> Unit raise RegexError {
  if self.peek() != ')' {
    raise self.fail("end pattern with unmatched parenthesis")
  }
  self.pos += 1
}

///|
fn Parser::read_name(self : Parser, close : Int) -> String raise RegexError {
  let start = self.pos
  while !self.eof() && self.peek() != close {
    self.pos += 1
  }
  if self.eof() {
    raise self.fail("invalid group name")
  }
  let name = self.src.unsafe_substring(start~, end=self.pos)
  self.pos += 1
  name
}

///|
fn Parser::parse_escape(self : Parser) -> Node raise RegexError {
  self.pos += 1 // backslash
  if self.eof() {
    raise self.fail("too short escape sequence")
  }
  let c = self.peek()
  match c {
    'A' => {
      self.pos += 1
      Assert(BeginText)
    }
    'z' => {
      self.pos += 1
      Assert(EndText)
    }
    'Z' => {
      self.pos += 1
      Assert(EndTextOptNewline)
    }
    'b' => {
      self.pos += 1
      Assert(WordBoundary)
    }
    'B' => {
      self.pos += 1
      Assert(NotWordBoundary)
    }
    'G' => {
      self.pos += 1
      Assert(SearchStart)
    }
    '1'..='9' => {
      let mut n = 0
      while self.peek() >= '0' && self.peek() <= '9' {
        n = n * 10 + (self.peek() - '0')
        self.pos += 1
      }
      Backref(n)
    }
    'k' => {
      self.pos += 1
      if self.peek() != '<' {
        raise self.fail("invalid backref")
      }
      self.pos += 1
      NamedBackref(self.read_name('>'))
    }
    _ =>
      match self.parse_class_escape() {
        Some(item) =>
          Class({
            items: [item],
            negated: false,
            ascii: FixedArray::make(0, false),
          })
        None => Char(self.parse_char_escape())
      }
  }
}

///|
/// Parses an escape that denotes a character set (`\d`, `\p{..}`...).
/// Assumes `self.pos` is just after the backslash. Returns None without
/// consuming if the escape is not a set escape.
fn Parser::parse_class_escape(self : Parser) -> ClassItem? raise RegexError {
  let c = self.peek()
  let item = match c {
    'd' => AsciiDigit(false)
    'D' => AsciiDigit(true)
    's' => AsciiSpace(false)
    'S' => AsciiSpace(true)
    'w' => AsciiWord(false)
    'W' => AsciiWord(true)
    'h' => AsciiHex(false)
    'H' => AsciiHex(true)
    'p' | 'P' => {
      self.pos += 1
      if self.peek() != '{' {
        raise self.fail("invalid character property name")
      }
      self.pos += 1
      let mut neg = c == 'P'
      if self.peek() == '^' {
        neg = !neg
        self.pos += 1
      }
      let name = self.read_name('}')
      let prop = match name.to_lower() {
        "alpha" | "l" | "letter" => Prop::Alpha
        "alnum" => Alnum
        "word" => Word
        "blank" => Blank
        "space" => Space
        "digit" | "nd" => Digit
        "upper" | "lu" => Upper
        "lower" | "ll" => Lower
        "punct" | "p" => Punct
        "any" => Any
        _ => raise self.fail("invalid character property name {\{name}}")
      }
      return Some(Prop(prop, neg))
    }
    _ => return None
  }
  self.pos += 1
  Some(item)
}

///|
/// Parses a single-character escape (after the backslash) and returns its code point.
fn Parser::parse_char_escape(self : Parser) -> Int raise RegexError {
  let c = self.next_cp()
  match c {
    'n' => '\n'
    't' => '\t'
    'r' => '\r'
    'f' => 0x0C
    'v' => 0x0B
    'a' => 0x07
    'e' => 0x1B
    '0' => {
      // octal \0, \0nn
      let mut n = 0
      let mut i = 0
      while i < 2 && self.peek() >= '0' && self.peek() <= '7' {
        n = n * 8 + (self.peek() - '0')
        self.pos += 1
        i += 1
      }
      n
    }
    'x' => self.read_hex(2, braces=true)
    'u' => self.read_hex(4, braces=true)
    _ => c
  }
}

///|
fn Parser::read_hex(
  self : Parser,
  digits : Int,
  braces~ : Bool,
) -> Int raise RegexError {
  let hex = fn(c : Int) -> Int {
    if c >= '0' && c <= '9' {
      c - '0'
    } else if c >= 'a' && c <= 'f' {
      c - 'a' + 10
    } else if c >= 'A' && c <= 'F' {
      c - 'A' + 10
    } else {
      -1
    }
  }
  if braces && self.peek() == '{' {
    self.pos += 1
    let mut n = 0
    while self.peek() != '}' {
      let d = hex(self.peek())
      if d < 0 {
        raise self.fail("invalid Unicode escape")
      }
      n = n * 16 + d
      self.pos += 1
    }
    self.pos += 1
    return n
  }
  let mut n = 0
  let mut i = 0
  while i < digits && hex(self.peek()) >= 0 {
    n = n * 16 + hex(self.peek())
    self.pos += 1
    i += 1
  }
  if i == 0 {
    raise self.fail("invalid hex escape")
  }
  n
}

///|
/// Parses a bracket expression; `self.pos` is just after `[`.
fn Parser::parse_class(self : Parser) -> CharClass raise RegexError {
  let mut negated = false
  if self.peek() == '^' {
    negated = true
    self.pos += 1
  }
  let items : Array[ClassItem] = []
  let mut first = true
  while true {
    if self.eof() {
      raise self.fail("premature end of char-class")
    }
    let c = self.peek()
    if c == ']' && !first {
      self.pos += 1
      break
    }
    first = false
    if c == '[' {
      if self.peek_at(1) == ':' {
        // POSIX bracket [:name:]
        self.pos += 2
        let mut neg = false
        if self.peek() == '^' {
          neg = true
          self.pos += 1
        }
        let name = self.read_name(':')
        if self.peek() != ']' {
          raise self.fail("invalid POSIX bracket")
        }
        self.pos += 1
        let prop = match name {
          "alpha" => Prop::Alpha
          "alnum" => Alnum
          "word" => Word
          "blank" => Blank
          "space" => Space
          "digit" => Digit
          "upper" => Upper
          "lower" => Lower
          "punct" => Punct
          _ => raise self.fail("invalid POSIX bracket type")
        }
        items.push(Prop(prop, neg))
      } else {
        self.pos += 1
        items.push(Nested(self.parse_class()))
      }
      continue
    }
    if c == '&' && self.peek_at(1) == '&' {
      raise self.fail("class intersection is not supported")
    }
    // single char or escape
    let lo = if c == '\\' {
      self.pos += 1
      match self.parse_class_escape() {
        Some(item) => {
          items.push(item)
          continue
        }
        None =>
          if self.peek() == 'b' {
            self.pos += 1
            0x08
          } else {
            self.parse_char_escape()
          }
      }
    } else {
      self.next_cp()
    }
    // range?
    if self.peek() == '-' && self.peek_at(1) != ']' && self.peek_at(1) != -1 {
      self.pos += 1
      let hi = if self.peek() == '\\' {
        self.pos += 1
        self.parse_char_escape()
      } else {
        self.next_cp()
      }
      if hi < lo {
        raise self.fail("empty range in char class")
      }
      items.push(Range(lo, hi))
    } else {
      items.push(Range(lo, lo))
    }
  }
  let cls = { items, negated, ascii: FixedArray::make(0, false), }
  cls
}
