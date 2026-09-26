///|
/// Error raised when a pattern (or a flag string) cannot be compiled.
pub suberror RegexError {
  RegexError(pattern~ : String, pos~ : Int, message~ : String)
} derive(Debug)

///|
pub extend RegexError with Debug::{to_repr}

///|
/// Maximum group nesting depth accepted by the parser (Onigmo's limit is 4096;
/// ours is lower so that the recursive parser/compiler/matcher stay well within
/// the host stack on every backend).
const MAX_NESTING = 200

///|
/// Maximum depth of the syntax tree (groups, alternations, stacked quantifiers).
/// The compiler and its analyses recurse over the tree; measured stack
/// exhaustion starts around depth 600 on wasm and 960 on js/wasm-gc.
const MAX_TREE_DEPTH = 300

///|
/// Largest repeat count in `{n,m}` (same as Onigmo's ONIG_MAX_REPEAT_NUM).
const MAX_REPEAT = 100000

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
  Letter // \p{L}
  UppercaseLetter // \p{Lu}
  LowercaseLetter // \p{Ll}
  Punct // \p{Punct}: general category P
  PosixPunct // [[:punct:]]: P plus the ASCII symbols $+<=>^`|~
  XDigit
  Cntrl
  Ascii
  Any
}

///|
priv struct CharClass {
  items : Array[ClassItem]
  negated : Bool
  // case-insensitive: literal ranges and cased properties match case variants
  icase : Bool
  // ASCII fast path: bit set for code points 0..127, computed after parsing
  mut ascii : FixedArray[Bool]
}

///|
fn CharClass::new(
  items : Array[ClassItem],
  negated? : Bool = false,
  icase? : Bool = false,
) -> CharClass {
  { items, negated, icase, ascii: FixedArray::make(0, false), }
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
  Backref(Int, Bool) // group, ignore case?
  NamedBackref(String, Bool) // name, ignore case?
  Look(Node, Bool, Bool) // ahead?, negated?
  Atomic(Node)
  Keep // \K: the reported match starts here
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
  mut icase : Bool
  mut extended : Bool
  mut depth : Int
  // Onigmo: once a pattern has named groups, plain groups do not capture and
  // numbered backreferences are rejected
  named_only : Bool
  mut plain_caps : Bool
  numbered_refs : Array[(Int, Int)] // (group, source position)
  lookbehinds : Array[(Node, Int)] // (body, source position)
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
/// Reads one code point (combining surrogate pairs). Unpaired surrogates in
/// the pattern are rejected, so literals never split a surrogate pair.
fn Parser::next_cp(self : Parser) -> Int raise RegexError {
  let c = self.src[self.pos].to_int()
  if c >= 0xD800 && c <= 0xDBFF && self.pos + 1 < self.src.length() {
    let d = self.src[self.pos + 1].to_int()
    if d >= 0xDC00 && d <= 0xDFFF {
      self.pos += 2
      return 0x10000 + ((c - 0xD800) << 10) + (d - 0xDC00)
    }
  }
  if c >= 0xD800 && c <= 0xDFFF {
    raise self.fail("invalid multibyte character")
  }
  self.pos += 1
  c
}

///|
/// In extended mode (`x`), skips whitespace and `#` comments between tokens.
fn Parser::skip_extended(self : Parser) -> Unit {
  if !self.extended {
    return
  }
  while !self.eof() {
    let c = self.peek()
    if c == ' ' || (c >= 0x09 && c <= 0x0D) {
      self.pos += 1
    } else if c == '#' {
      while !self.eof() && self.peek() != '\n' {
        self.pos += 1
      }
    } else {
      break
    }
  }
}

///|
/// A literal code point, expanded to its case variants under `i`.
fn Parser::literal(self : Parser, cp : Int) -> Node {
  if self.icase && fold_next_of(cp) != cp {
    let items = [Range(cp, cp)]
    let mut c = fold_next_of(cp)
    while c != cp {
      items.push(Range(c, c))
      c = fold_next_of(c)
    }
    Class(CharClass::new(items))
  } else {
    Char(cp)
  }
}

///|
fn parse_pattern(
  src : String,
  dotall : Bool,
  icase : Bool,
  extended : Bool,
) -> (Node, Int, Map[String, Int]) raise RegexError {
  let run = fn(named_only : Bool) -> (Parser, Node) raise RegexError {
    let p : Parser = {
      src,
      pos: 0,
      ncaps: 0,
      names: {},
      dotall,
      icase,
      extended,
      depth: 0,
      named_only,
      plain_caps: false,
      numbered_refs: [],
      lookbehinds: [],
    }
    let node = p.parse_alt()
    if !p.eof() {
      raise p.fail("unmatched close parenthesis")
    }
    (p, node)
  }
  let (p, node) = {
    let (p, node) = run(false)
    if !p.names.is_empty() && (p.plain_caps || !p.numbered_refs.is_empty()) {
      run(true)
    } else {
      (p, node)
    }
  }
  for r in p.numbered_refs {
    let (n, pos) = r
    if n > p.ncaps {
      raise RegexError(pattern=src, pos~, message="invalid backref number/name")
    }
  }
  check_tree_depth(src, node)
  // Onigmo requires bounded look-behind; unbounded ones are rejected
  for lb in p.lookbehinds {
    let (n, pos) = lb
    if width(n).1 < 0 {
      raise RegexError(
        pattern=src,
        pos~,
        message="invalid pattern in look-behind",
      )
    }
  }
  (node, p.ncaps, p.names)
}

///|
/// Rejects syntax trees deeper than `MAX_TREE_DEPTH` (iteratively, so that the
/// check itself cannot exhaust the stack).
fn check_tree_depth(src : String, node : Node) -> Unit raise RegexError {
  let stack = [(node, 1)]
  while stack.pop() is Some((n, d)) {
    if d > MAX_TREE_DEPTH {
      raise RegexError(pattern=src, pos=0, message="parse depth limit over")
    }
    match n {
      Concat(items) | Alt(items) =>
        for it in items {
          stack.push((it, d + 1))
        }
      Group(_, x) | Atomic(x) | Look(x, _, _) | Repeat(x, _, _, _) =>
        stack.push((x, d + 1))
      _ => ()
    }
  }
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
  while true {
    self.skip_extended()
    if self.eof() {
      break
    }
    let c = self.peek()
    if c == '|' || c == ')' {
      break
    }
    let atom = self.parse_atom()
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
fn Parser::parse_quantifiers(
  self : Parser,
  atom : Node,
) -> Node raise RegexError {
  let mut node = atom
  while true {
    self.skip_extended()
    if self.eof() {
      break
    }
    let c = self.peek()
    let qstart = self.pos
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
    // Ruby syntax: a fixed interval `{n}` is greedy only, so `x{2}?` is
    // `(?:x{2})?` (the `?` is left for the next iteration)
    let fixed = c == '{' &&
      !self.src.unsafe_substring(start=qstart, end=self.pos).contains(",")
    let greed = if self.peek() == '?' && !fixed {
      self.pos += 1
      Lazy
    } else if self.peek() == '+' && c != '{' {
      self.pos += 1
      Possessive
    } else {
      Greedy
    }
    if node is (Assert(_) | Look(_, _, _) | Keep) {
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
fn Parser::try_interval(self : Parser) -> (Int, Int)? raise RegexError {
  let save = self.pos
  self.pos += 1
  let read_int = fn() -> Int? raise RegexError {
    let start = self.pos
    let mut n = 0
    while self.peek() >= '0' && self.peek() <= '9' {
      n = n * 10 + (self.peek() - '0')
      if n > MAX_REPEAT {
        raise self.fail("too big number for repeat range")
      }
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
      let lo = lo.unwrap_or(0)
      match hi {
        Some(h) if h < lo =>
          raise self.fail("upper is smaller than lower in repeat range")
        _ => ()
      }
      Some((lo, hi.unwrap_or(-1)))
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
fn Parser::parse_atom(self : Parser) -> Node raise RegexError {
  let c = self.peek()
  match c {
    '(' => self.parse_group()
    '[' => {
      self.pos += 1
      let cls = self.parse_class()
      match cls {
        // Onigmo turns a one-character class into a string, which (unlike a
        // class) case-folds characters in U+0080..U+00FF too
        { items: [Range(lo, hi)], negated: false, icase: true, .. } if lo == hi =>
          self.literal(lo)
        _ => Class(cls)
      }
    }
    '.' => {
      self.pos += 1
      Any(self.dotall)
    }
    '^' => {
      self.pos += 1
      Assert(BeginLine)
    }
    '$' => {
      self.pos += 1
      Assert(EndLine)
    }
    '\\' => self.parse_escape()
    '*' | '+' | '?' =>
      raise self.fail("target of repeat operator is not specified")
    _ => self.literal(self.next_cp())
  }
}

///|
fn Parser::parse_group(self : Parser) -> Node raise RegexError {
  self.depth += 1
  if self.depth > MAX_NESTING {
    raise self.fail("parse depth limit over")
  }
  self.pos += 1 // (
  let node = if self.peek() == '?' {
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
      '<' if self.peek_at(1) == '=' || self.peek_at(1) == '!' => {
        let start = self.pos - 2
        let neg = self.peek_at(1) == '!'
        self.pos += 2
        let n = self.parse_alt()
        self.expect_close()
        // validated once the tree depth is known to be safe
        self.lookbehinds.push((n, start))
        Look(n, false, neg)
      }
      '<' | '\'' => {
        self.pos += 1
        let name = self.read_group_name(if c == '<' { '>' } else { '\'' })
        self.ncaps += 1
        let idx = self.ncaps
        self.names[name] = idx
        let n = self.parse_alt()
        self.expect_close()
        Group(Some(idx), n)
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
  } else if self.named_only {
    let n = self.parse_alt()
    self.expect_close()
    Group(None, n)
  } else {
    self.plain_caps = true
    self.ncaps += 1
    let idx = self.ncaps
    let n = self.parse_alt()
    self.expect_close()
    Group(Some(idx), n)
  }
  self.depth -= 1
  node
}

///|
/// Parses option groups: `(?imx-imx)` applies to the rest of the enclosing
/// group (including later alternatives, as in Onigmo), `(?imx-imx:...)` to its
/// body only.
fn Parser::parse_flag_group(self : Parser) -> Node raise RegexError {
  let saved_dotall = self.dotall
  let saved_icase = self.icase
  let saved_extended = self.extended
  let restore = fn() {
    self.dotall = saved_dotall
    self.icase = saved_icase
    self.extended = saved_extended
  }
  let mut on = true
  while true {
    match self.peek() {
      'm' => self.dotall = on
      'i' => self.icase = on
      'x' => self.extended = on
      '-' if on => on = false
      ':' => {
        self.pos += 1
        let n = self.parse_alt()
        self.expect_close()
        restore()
        return Group(None, n)
      }
      ')' => {
        self.pos += 1
        let n = self.parse_alt()
        restore()
        return Group(None, n)
      }
      'a' | 'd' | 'u' => raise self.fail("unsupported group option")
      -1 => raise self.fail("end pattern in group")
      _ => raise self.fail("undefined group option")
    }
    self.pos += 1
  }
  Empty
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
/// Reads a group name: word characters, not starting with a digit.
fn Parser::read_group_name(
  self : Parser,
  close : Int,
) -> String raise RegexError {
  let start = self.pos
  let name = self.read_name(close)
  let valid = name != "" &&
    !(name[0] >= '0' && name[0] <= '9') &&
    name.iter().all(ch => is_unicode_word(ch.to_int()))
  if !valid {
    self.pos = start
    raise self.fail("invalid group name <\{name}>")
  }
  name
}

///|
/// `\R`: `(?>\r\n|[\n\v\f\r\u0085  ])`.
fn linebreak() -> Node {
  Atomic(
    Alt([
      Concat([Char('\r'), Char('\n')]),
      Class(
        CharClass::new([
          Range(0x0A, 0x0D),
          Range(0x85, 0x85),
          Range(0x2028, 0x2029),
        ]),
      ),
    ]),
  )
}

///|
fn Parser::parse_escape(self : Parser) -> Node raise RegexError {
  let start = self.pos
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
    'K' => {
      self.pos += 1
      Keep
    }
    'R' => {
      self.pos += 1
      linebreak()
    }
    'X' => raise self.fail("\\X (extended grapheme cluster) is not supported")
    'g' => raise self.fail("\\g (subexpression call) is not supported")
    '1'..='9' => {
      let digits = self.pos
      let mut n = 0
      while self.peek() >= '0' && self.peek() <= '9' {
        if n <= MAX_REPEAT {
          n = n * 10 + (self.peek() - '0')
        }
        self.pos += 1
      }
      if n <= 9 || n <= self.ncaps {
        if self.named_only {
          self.pos = start
          raise self.fail("numbered backref/call is not allowed. (use name)")
        }
        self.numbered_refs.push((n, start))
        Backref(n, self.icase)
      } else {
        // not a group number: an octal escape (or a literal 8/9)
        self.pos = digits
        self.literal(self.parse_char_escape())
      }
    }
    'k' => {
      self.pos += 1
      let close : Int = match self.peek() {
        '<' => '>'
        '\'' => '\''
        _ => raise self.fail("invalid backref number/name")
      }
      self.pos += 1
      let name = self.read_name(close)
      match parse_int_opt(name) {
        Some(n) => {
          let idx = if n < 0 { self.ncaps + n + 1 } else { n }
          if idx <= 0 || n == 0 {
            self.pos = start
            raise self.fail("invalid backref number/name")
          }
          if self.named_only {
            self.pos = start
            raise self.fail("numbered backref/call is not allowed. (use name)")
          }
          self.numbered_refs.push((idx, start))
          Backref(idx, self.icase)
        }
        None => NamedBackref(name, self.icase)
      }
    }
    _ =>
      match self.parse_class_escape() {
        Some(item) => Class(CharClass::new([item], icase=self.icase))
        None => self.literal(self.parse_char_escape())
      }
  }
}

///|
/// Parses `[+-]digits`; None if `s` is not an integer.
fn parse_int_opt(s : String) -> Int? {
  if s == "" {
    return None
  }
  let neg = s[0] == '-'
  let from = if neg || s[0] == '+' { 1 } else { 0 }
  if from >= s.length() {
    return None
  }
  let mut n = 0
  for i in from..<s.length() {
    let d = s[i].to_int() - '0'
    if d < 0 || d > 9 {
      return None
    }
    if n <= MAX_REPEAT {
      n = n * 10 + d
    }
  }
  Some(if neg { -n } else { n })
}

///|
/// Normalizes a property name like Onigmo: case, spaces, `_` and `-` are ignored.
fn normalize_prop_name(name : String) -> String {
  let sb = StringBuilder()
  for ch in name.to_lower() {
    if ch != ' ' && ch != '_' && ch != '-' {
      sb.write_char(ch)
    }
  }
  sb.to_string()
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
      let prop = match normalize_prop_name(name) {
        "alpha" | "alphabetic" => Prop::Alpha
        "alnum" => Alnum
        "word" => Word
        "blank" => Blank
        "space" | "whitespace" => Space
        "digit" | "nd" | "decimalnumber" => Digit
        "upper" | "uppercase" => Upper
        "lower" | "lowercase" => Lower
        "l" | "letter" => Letter
        "lu" | "uppercaseletter" => UppercaseLetter
        "ll" | "lowercaseletter" => LowercaseLetter
        "punct" | "p" | "punctuation" => Punct
        "xdigit" | "asciihexdigit" => XDigit
        "cntrl" | "cc" | "control" => Cntrl
        "ascii" => Ascii
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
/// Whether the escape at `self.pos` (just after a backslash) denotes a set.
fn Parser::at_class_escape(self : Parser) -> Bool {
  let c = self.peek()
  c == 'd' ||
  c == 'D' ||
  c == 's' ||
  c == 'S' ||
  c == 'w' ||
  c == 'W' ||
  c == 'h' ||
  c == 'H' ||
  c == 'p' ||
  c == 'P'
}

///|
fn Parser::check_scalar(self : Parser, cp : Int) -> Int raise RegexError {
  if cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF) {
    raise self.fail("invalid Unicode range")
  }
  cp
}

///|
/// Reads up to `max` octal digits (at least `min`).
fn Parser::read_octal(self : Parser, max : Int) -> Int raise RegexError {
  let mut n = 0
  let mut i = 0
  while i < max && self.peek() >= '0' && self.peek() <= '7' {
    n = n * 8 + (self.peek() - '0')
    self.pos += 1
    i += 1
  }
  if n >= 0x80 {
    raise self.fail("invalid multibyte escape")
  }
  n
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
    '0' => self.read_octal(2)
    '1'..='7' => {
      self.pos -= 1
      self.read_octal(3)
    }
    'x' => self.read_hex_bytes()
    'u' => self.read_unicode()
    'c' => self.read_control()
    'C' => {
      if self.peek() != '-' {
        raise self.fail("invalid control-code syntax")
      }
      self.pos += 1
      self.read_control()
    }
    'M' => raise self.fail("too short escaped multibyte character")
    _ => c
  }
}

///|
/// `\cX` / `\C-X`: the control character for X.
fn Parser::read_control(self : Parser) -> Int raise RegexError {
  if self.eof() {
    raise self.fail("too short control escape")
  }
  let c = self.next_cp()
  if c >= 128 {
    raise self.fail("invalid control-code syntax")
  }
  c & 0x9F
}

///|
fn hex_digit(c : Int) -> Int {
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

///|
/// Reads the 1-2 hex digits of a `\x` escape.
fn Parser::read_hex_byte(self : Parser) -> Int raise RegexError {
  let mut n = 0
  let mut i = 0
  while i < 2 && hex_digit(self.peek()) >= 0 {
    n = n * 16 + hex_digit(self.peek())
    self.pos += 1
    i += 1
  }
  if i == 0 {
    raise self.fail("invalid hex escape")
  }
  n
}

///|
/// `\xHH`; bytes >= 0x80 must form a UTF-8 sequence of `\xHH` escapes.
fn Parser::read_hex_bytes(self : Parser) -> Int raise RegexError {
  let b0 = self.read_hex_byte()
  if b0 < 0x80 {
    return b0
  }
  let (extra, init) = if b0 >= 0xC2 && b0 <= 0xDF {
    (1, b0 & 0x1F)
  } else if b0 >= 0xE0 && b0 <= 0xEF {
    (2, b0 & 0x0F)
  } else if b0 >= 0xF0 && b0 <= 0xF4 {
    (3, b0 & 0x07)
  } else {
    raise self.fail("invalid multibyte escape")
  }
  let mut cp = init
  for _ in 0..<extra {
    if self.peek() != '\\' || self.peek_at(1) != 'x' {
      raise self.fail("too short multibyte code string")
    }
    self.pos += 2
    let b = self.read_hex_byte()
    if b < 0x80 || b > 0xBF {
      raise self.fail("invalid multibyte escape")
    }
    cp = (cp << 6) | (b & 0x3F)
  }
  let min = if extra == 1 { 0x80 } else if extra == 2 { 0x800 } else { 0x10000 }
  if cp < min {
    raise self.fail("invalid multibyte escape")
  }
  self.check_scalar(cp)
}

///|
/// `\uHHHH` or `\u{H...}` (a single code point).
fn Parser::read_unicode(self : Parser) -> Int raise RegexError {
  if self.peek() == '{' {
    self.pos += 1
    let mut n = 0
    let mut digits = 0
    while hex_digit(self.peek()) >= 0 {
      if n <= 0x10FFFF {
        n = n * 16 + hex_digit(self.peek())
      }
      self.pos += 1
      digits += 1
    }
    if self.peek() != '}' || digits == 0 {
      raise self.fail("invalid Unicode escape")
    }
    self.pos += 1
    return self.check_scalar(n)
  }
  let mut n = 0
  for _ in 0..<4 {
    let d = hex_digit(self.peek())
    if d < 0 {
      raise self.fail("invalid Unicode escape")
    }
    n = n * 16 + d
    self.pos += 1
  }
  self.check_scalar(n)
}

///|
/// Parses a bracket expression; `self.pos` is just after `[`.
fn Parser::parse_class(self : Parser) -> CharClass raise RegexError {
  self.depth += 1
  if self.depth > MAX_NESTING {
    raise self.fail("parse depth limit over")
  }
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
          "punct" => PosixPunct
          "xdigit" => XDigit
          "cntrl" => Cntrl
          "ascii" => Ascii
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
      if self.eof() {
        raise self.fail("premature end of char-class")
      }
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
        if self.at_class_escape() {
          raise self.fail("char-class value at end of range")
        }
        self.parse_char_escape()
      } else if self.peek() == '[' {
        raise self.fail("char-class value at end of range")
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
  self.depth -= 1
  CharClass::new(items, negated~, icase=self.icase)
}
