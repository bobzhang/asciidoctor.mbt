///|
/// A compiled regular expression using Ruby (Onigmo) syntax and semantics,
/// operating on UTF-16 strings with absolute code-unit offsets.
///
/// Semantics follow Ruby: `^`/`$` are always line anchors, the `m` flag makes
/// `.` match newlines (dot-all), `\w`/`\d`/`\s` are ASCII-only while `\b` and
/// `\p{Word}` are Unicode-aware, and an unset group never matches a backreference.
/// Matching works on code points: a match never starts or ends inside a
/// surrogate pair, even though offsets are reported in UTF-16 code units.
///
/// Each search operation runs under a step budget (see `compile`); the `try_*`
/// methods raise `RegexTimeout` when it is exhausted, the other methods abort.
pub struct Regex {
  source : String
  priv prog : FixedArray[Inst]
  priv classes : FixedArray[CharClass]
  priv sub_starts : FixedArray[Int]
  priv ncaps : Int
  priv nregs : Int
  priv names : Map[String, Int]
  priv anchor : Anchor
  priv first : FirstSet?
  priv required : FixedArray[Int]
  priv lead : (Int, Int, Int)?
  priv step_limit : Int
}

///|
/// Raised when a search exceeds its backtracking step budget (the analogue of
/// Ruby's `Regexp::TimeoutError`). `limit` is the budget that was exhausted.
pub suberror RegexTimeout {
  RegexTimeout(pattern~ : String, limit~ : Int)
} derive(Debug)

///|
pub extend RegexTimeout with Debug::{to_repr}

///|
/// Minimum step budget of one search operation.
const STEP_FLOOR = 10_000_000

///|
/// Budget cap (keeps the counter within 32 bits).
const STEP_CAP = 0x7FFF_0000

///|
/// The step budget of a search operation over `len` code units.
///
/// The default is `10M + (len + 1) * (len + 16 * program size)`: a scan costs
/// about `len * program size` steps and quadratic backtracking (which Ruby
/// completes, if slowly) about `len * len`, so both fit with ample headroom,
/// while exponential blowups exhaust it quickly. On the Asciidoctor corpus
/// the worst search used under 50 steps per code unit.
fn Regex::step_limit_for(self : Regex, len : Int) -> Int {
  if self.step_limit > 0 {
    return self.step_limit
  }
  let n = len.to_int64() + 1L
  let limit = STEP_FLOOR.to_int64() +
    n * (n + 16L * self.prog.length().to_int64())
  if limit >= STEP_CAP.to_int64() {
    STEP_CAP
  } else {
    limit.to_int()
  }
}

///|
/// The pattern source in Ruby literal form, e.g. `/a+/`.
pub fn Regex::to_string(self : Regex) -> String {
  "/\{self.source}/"
}

///|
/// Compiles `pattern`. `flags` may contain Ruby's options: `m` (dot-all),
/// `i` (ignore case, using Unicode simple case folding; multi-character folds
/// such as `ß` = `ss` are not supported) and `x` (extended: whitespace and
/// `#` comments outside classes are ignored). Any other flag is an error.
/// The inline forms `(?imx-imx)` and `(?imx-imx:...)` are supported too.
///
/// `step_limit` bounds the backtracking work of each search operation (a
/// step is one branch or one sub-match); 0 selects the default, which is
/// generous (10M steps plus roughly the square of the input length, see
/// `step_limit_for`) so that it only trips on catastrophic backtracking.
///
/// Patterns that Onigmo rejects, or that would exceed internal limits
/// (group nesting beyond 256, programs beyond 1M instructions), raise
/// `RegexError`.
///
/// ```mbt check
/// test {
///   let re = @regex.compile("(\\w+)@(\\w+)")
///   guard re.find("mail: joe@example") is Some(m) else { fail("no match") }
///   debug_inspect(m.group(2), content="Some(\"example\")")
///   inspect(@regex.compile("HELLO", flags="i").matches("hello"), content="true")
/// }
/// ```
pub fn compile(
  pattern : String,
  flags? : String = "",
  step_limit? : Int = 0,
) -> Regex raise RegexError {
  let mut dotall = false
  let mut icase = false
  let mut extended = false
  for ch in flags {
    match ch {
      'm' => dotall = true
      'i' => icase = true
      'x' => extended = true
      _ =>
        raise RegexError(
          pattern~,
          pos=0,
          message="unknown regexp option: \{ch}",
        )
    }
  }
  let (node, ncaps, names) = parse_pattern(pattern, dotall, icase, extended)
  let c : Compiler = {
    prog: [],
    classes: [],
    sub_nodes: [],
    sub_starts: [],
    nregs: 0,
    names,
    pattern,
  }
  c.compile(node)
  c.emit(SubEnd) |> ignore
  // sub-programs may themselves register more sub-programs
  let mut i = 0
  while i < c.sub_nodes.length() {
    c.sub_starts.push(c.pc())
    c.compile(c.sub_nodes[i])
    c.emit(SubEnd) |> ignore
    i += 1
  }
  let (first, is_nullable) = first_info(node)
  {
    source: pattern,
    prog: FixedArray::from_array(c.prog),
    classes: FixedArray::from_array(c.classes),
    sub_starts: FixedArray::from_array(c.sub_starts),
    ncaps,
    nregs: c.nregs,
    names,
    anchor: leading_anchor(node),
    first: if is_nullable {
      None
    } else {
      first
    },
    required: FixedArray::from_array(required_units(node)),
    lead: lead_literal(node),
    step_limit: if step_limit > 0 {
      step_limit
    } else {
      0
    },
  }
}

///|
/// Like `compile` but aborts on an invalid pattern. Intended for literal patterns.
pub fn re(
  pattern : String,
  flags? : String = "",
  step_limit? : Int = 0,
) -> Regex {
  compile(pattern, flags~, step_limit~) catch {
    RegexError(message~, pos~, ..) =>
      abort("invalid regex /\{pattern}/ at \{pos}: \{message}")
  }
}

///|
/// Number of capture groups.
pub fn Regex::group_count(self : Regex) -> Int {
  self.ncaps
}

///|
/// Result of a successful match.
pub struct MatchData {
  input : String
  priv offsets : FixedArray[Int]
  priv names : Map[String, Int]
}

///|
/// All groups (including group 0) as optional strings.
pub fn MatchData::groups(self : MatchData) -> Array[String?] {
  Array::makei(self.offsets.length() / 2, i => self.group(i))
}

///|
/// Captured text of group `i` (0 = whole match), or None if the group did not participate.
pub fn MatchData::group(self : MatchData, i : Int) -> String? {
  if 2 * i + 1 >= self.offsets.length() {
    return None
  }
  let s = self.offsets[2 * i]
  let e = self.offsets[2 * i + 1]
  if s < 0 || e < 0 {
    None
  } else {
    Some(self.input.unsafe_substring(start=s, end=e))
  }
}

///|
/// Captured text of group `i`, or "" if it did not participate.
pub fn MatchData::at(self : MatchData, i : Int) -> String {
  self.group(i).unwrap_or("")
}

///|
/// Whether group `i` participated in the match.
pub fn MatchData::has(self : MatchData, i : Int) -> Bool {
  2 * i + 1 < self.offsets.length() && self.offsets[2 * i] >= 0
}

///|
/// Text of a named group.
pub fn MatchData::named(self : MatchData, name : String) -> String? {
  match self.names.get(name) {
    Some(i) => self.group(i)
    None => None
  }
}

///|
/// Whether the pattern has named groups.
pub fn MatchData::has_names(self : MatchData) -> Bool {
  !self.names.is_empty()
}

///|
/// Start offset of group `i` (-1 if unset).
pub fn MatchData::begin(self : MatchData, i? : Int = 0) -> Int {
  self.offsets[2 * i]
}

///|
/// End offset of group `i` (-1 if unset).
pub fn MatchData::end(self : MatchData, i? : Int = 0) -> Int {
  self.offsets[2 * i + 1]
}

///|
/// The whole matched text.
pub fn MatchData::matched(self : MatchData) -> String {
  self.input.unsafe_substring(start=self.offsets[0], end=self.offsets[1])
}

///|
/// Text before the match.
pub fn MatchData::pre_match(self : MatchData) -> String {
  self.input.unsafe_substring(start=0, end=self.offsets[0])
}

///|
/// Text after the match.
pub fn MatchData::post_match(self : MatchData) -> String {
  self.input.unsafe_substring(start=self.offsets[1], end=self.input.length())
}

///|
/// Number of groups including group 0.
pub fn MatchData::size(self : MatchData) -> Int {
  self.offsets.length() / 2
}

///|
fn Regex::timeout(self : Regex, vm : Vm) -> RegexTimeout {
  RegexTimeout(pattern=self.source, limit=vm.limit)
}

///|
/// Aborts on an exhausted step budget (for the non-raising API).
fn[T] timeout_abort(err : RegexTimeout) -> T {
  let RegexTimeout(pattern~, limit~) = err
  abort("regex /\{pattern}/ exceeded its step limit (\{limit} steps)")
}

///|
/// Tries a match starting exactly at `pos` (a code point boundary).
fn Regex::try_at(
  self : Regex,
  vm : Vm,
  pos : Int,
) -> MatchData? raise RegexTimeout {
  vm.caps.fill(-1)
  let e = vm.run(0, pos, -1)
  if e >= 0 {
    let offsets = vm.caps.copy()
    // group 0's start is only set in advance by \K
    if offsets[0] < 0 {
      offsets[0] = pos
    }
    offsets[1] = e
    Some({ input: vm.input, offsets, names: self.names, })
  } else if vm.timed_out {
    raise self.timeout(vm)
  } else {
    None
  }
}

///|
/// Like `match_at`, but raises `RegexTimeout` when the step budget runs out.
pub fn Regex::try_match_at(
  self : Regex,
  s : String,
  pos : Int,
) -> MatchData? raise RegexTimeout {
  if pos < 0 || pos > s.length() || splits_pair(s, pos) {
    return None
  }
  let vm = Vm::new(self, s)
  vm.search_start = pos
  self.try_at(vm, pos)
}

///|
/// Matches only at position `pos` (like Ruby's `\G`-anchored match). There is
/// no match at an offset inside a surrogate pair.
pub fn Regex::match_at(self : Regex, s : String, pos : Int) -> MatchData? {
  self.try_match_at(s, pos) catch {
    e => timeout_abort(e)
  }
}

///|
/// Whether a match can start at `pos` according to the first-unit prefilter.
fn FirstSet::admits(self : FirstSet, s : String, pos : Int) -> Bool {
  let c = s[pos].to_int()
  if c < 128 {
    self.ascii[c]
  } else {
    self.non_ascii && !splits_pair(s, pos)
  }
}

///|
/// Finds the first match starting at a code point boundary at or after `start`.
fn Regex::find_with(
  self : Regex,
  vm : Vm,
  start : Int,
) -> MatchData? raise RegexTimeout {
  let s = vm.input
  let len = s.length()
  // an offset inside a surrogate pair means the next code point boundary
  let start = if splits_pair(s, start) { start + 1 } else { start }
  vm.search_start = start
  // prefilter: every required code unit must occur at or after `start`
  for u in self.required {
    let mut i = start
    while i < len && s[i].to_int() != u {
      i += 1
    }
    if i >= len {
      return None
    }
  }
  match self.anchor {
    TextStart => return if start == 0 { self.try_at(vm, 0) } else { None }
    LineStart => {
      let mut pos = start
      while pos <= len {
        if pos == 0 || s[pos - 1] == '\n' {
          match self.try_at(vm, pos) {
            Some(m) => return Some(m)
            None => ()
          }
        }
        // advance to next line start
        while pos < len && s[pos] != '\n' {
          pos += 1
        }
        pos += 1
      }
      return None
    }
    NoAnchor => ()
  }
  let mut pos = start
  match self.lead {
    Some((unit, min_off, max_off)) => {
      // jump from one occurrence of the literal to the next; only starts
      // within [q - max_off, q - min_off] can place the literal at q. The
      // literal is a BMP non-surrogate, so `q` is always a boundary.
      while true {
        let mut q = pos + min_off
        while q < len && s[q].to_int() != unit {
          q += 1
        }
        if q >= len {
          return None
        }
        let from = if q - max_off > pos { q - max_off } else { pos }
        let to = q - min_off
        let mut st = from
        while st <= to {
          let possible = match self.first {
            Some(first) => first.admits(s, st)
            None => !splits_pair(s, st)
          }
          if possible {
            match self.try_at(vm, st) {
              Some(m) => return Some(m)
              None => ()
            }
          }
          st += 1
        }
        pos = to + 1
      }
      return None
    }
    None => ()
  }
  match self.first {
    Some(first) => {
      // (the hottest loop of every search: `admits`, inlined)
      let ascii = first.ascii
      let non_ascii = first.non_ascii
      while pos < len {
        let c = s[pos].to_int()
        if (if c < 128 { ascii[c] } else { non_ascii && !splits_pair(s, pos) }) {
          match self.try_at(vm, pos) {
            Some(m) => return Some(m)
            None => ()
          }
        }
        pos += 1
      }
    }
    None =>
      while pos <= len {
        if !splits_pair(s, pos) {
          match self.try_at(vm, pos) {
            Some(m) => return Some(m)
            None => ()
          }
        }
        pos += 1
      }
  }
  None
}

///|
/// Like `find`, but raises `RegexTimeout` when the step budget runs out.
pub fn Regex::try_find(
  self : Regex,
  s : String,
  start? : Int = 0,
) -> MatchData? raise RegexTimeout {
  if start < 0 || start > s.length() {
    return None
  }
  self.find_with(Vm::new(self, s), start)
}

///|
/// Finds the first match at or after `start` (Ruby's `String#match(re, start)`).
/// A `start` inside a surrogate pair is rounded up to the next code point.
pub fn Regex::find(self : Regex, s : String, start? : Int = 0) -> MatchData? {
  self.try_find(s, start~) catch {
    e => timeout_abort(e)
  }
}

///|
/// Whether the pattern matches anywhere in `s` (Ruby's `match?`).
pub fn Regex::matches(self : Regex, s : String) -> Bool {
  self.find(s) is Some(_)
}

///|
/// Width of the code point at `pos` (1 or 2).
fn cp_width(s : String, pos : Int) -> Int {
  let c = s[pos].to_int()
  if c >= 0xD800 && c <= 0xDBFF && pos + 1 < s.length() {
    let d = s[pos + 1].to_int()
    if d >= 0xDC00 && d <= 0xDFFF {
      return 2
    }
  }
  1
}

///|
/// Like `find_all`, but raises `RegexTimeout` when the step budget (shared by
/// the whole scan) runs out.
pub fn Regex::try_find_all(
  self : Regex,
  s : String,
) -> Array[MatchData] raise RegexTimeout {
  let out = []
  let vm = Vm::new(self, s)
  let len = s.length()
  let mut pos = 0
  while pos <= len {
    match self.find_with(vm, pos) {
      None => break
      Some(m) => {
        out.push(m)
        let e = m.end()
        pos = if e == m.begin() {
          if e >= len {
            break
          }
          e + cp_width(s, e)
        } else {
          e
        }
      }
    }
  }
  out
}

///|
/// All successive non-overlapping matches (Ruby's `scan`).
pub fn Regex::find_all(self : Regex, s : String) -> Array[MatchData] {
  self.try_find_all(s) catch {
    e => timeout_abort(e)
  }
}

///|
/// Like `replace` (or `replace_first` when `once` is true), but raises
/// `RegexTimeout` when the step budget (shared by the whole operation) runs out.
pub fn Regex::try_replace(
  self : Regex,
  s : String,
  f : (MatchData) -> String,
  once? : Bool = false,
) -> String raise RegexTimeout {
  let vm = Vm::new(self, s)
  let len = s.length()
  let mut pos = 0
  let mut last = 0
  let mut sb : StringBuilder? = None
  while pos <= len {
    match self.find_with(vm, pos) {
      None => break
      Some(m) => {
        let buf = match sb {
          Some(b) => b
          None => {
            let b = StringBuilder(size_hint=len + 16)
            sb = Some(b)
            b
          }
        }
        let b = m.begin()
        let e = m.end()
        buf.write_substring(s, last, b - last)
        buf.write_string(f(m))
        if once {
          last = e
          break
        }
        if e == b {
          if e >= len {
            last = e
            break
          }
          let w = cp_width(s, e)
          buf.write_substring(s, e, w)
          pos = e + w
          last = pos
        } else {
          pos = e
          last = e
        }
      }
    }
  }
  match sb {
    None => s
    Some(buf) => {
      buf.write_substring(s, last, len - last)
      buf.to_string()
    }
  }
}

///|
/// Replaces every match with the result of `f` (Ruby's `gsub` with a block).
pub fn Regex::replace(
  self : Regex,
  s : String,
  f : (MatchData) -> String,
) -> String {
  self.try_replace(s, f) catch {
    e => timeout_abort(e)
  }
}

///|
/// Replaces the first match with the result of `f` (Ruby's `sub` with a block).
pub fn Regex::replace_first(
  self : Regex,
  s : String,
  f : (MatchData) -> String,
) -> String {
  self.try_replace(s, f, once=true) catch {
    e => timeout_abort(e)
  }
}

///|
/// Expands a Ruby replacement template: `\0`/`\&`, `\1`..`\9`, `\k<name>`,
/// `` \` ``, `\'`, `\\`.
pub fn MatchData::expand(self : MatchData, template : String) -> String {
  if !template.contains("\\") {
    return template
  }
  let sb = StringBuilder()
  let n = template.length()
  let mut i = 0
  while i < n {
    let c = template[i]
    if c == '\\' && i + 1 < n {
      let d = template[i + 1]
      match d {
        '0'..='9' => {
          sb.write_string(self.at(d.to_int() - '0'))
          i += 2
        }
        '&' => {
          sb.write_string(self.at(0))
          i += 2
        }
        '`' => {
          sb.write_string(self.pre_match())
          i += 2
        }
        '\'' => {
          sb.write_string(self.post_match())
          i += 2
        }
        '\\' => {
          sb.write_char('\\')
          i += 2
        }
        'k' if i + 2 < n && template[i + 2] == '<' => {
          let close = index_from(template, ">", i + 3)
          match close {
            Some(j) => {
              let name = template.unsafe_substring(start=i + 3, end=j)
              sb.write_string(self.named(name).unwrap_or(""))
              i = j + 1
            }
            None => {
              sb.write_char('\\')
              i += 1
            }
          }
        }
        _ => {
          sb.write_char('\\')
          i += 1
        }
      }
    } else {
      sb.write_substring(template, i, 1)
      i += 1
    }
  }
  sb.to_string()
}

///|
fn index_from(s : String, needle : String, from : Int) -> Int? {
  match s.unsafe_substring(start=from, end=s.length()).find(needle) {
    Some(k) => Some(from + k)
    None => None
  }
}

///|
/// Ruby's `gsub(re, template)`.
pub fn Regex::gsub(self : Regex, s : String, template : String) -> String {
  self.replace(s, m => m.expand(template))
}

///|
/// Ruby's `sub(re, template)`.
pub fn Regex::sub(self : Regex, s : String, template : String) -> String {
  self.replace_first(s, m => m.expand(template))
}

///|
/// Like `split`, but raises `RegexTimeout` when the step budget (shared by the
/// whole operation) runs out.
pub fn Regex::try_split(
  self : Regex,
  s : String,
  limit? : Int = 0,
) -> Array[String] raise RegexTimeout {
  let out : Array[String] = []
  let len = s.length()
  if len == 0 {
    return out
  }
  let vm = Vm::new(self, s)
  let mut beg = 0
  let mut start = 0
  let mut last_null = false
  let mut count = 1
  while limit <= 0 || count < limit {
    guard self.find_with(vm, start) is Some(m) else { break }
    let mb = m.begin()
    let me = m.end()
    if start == mb && mb == me {
      if last_null {
        let w = if beg < len { cp_width(s, beg) } else { 0 }
        out.push(s.unsafe_substring(start=beg, end=beg + w))
        beg = start
      } else {
        start += if start < len { cp_width(s, start) } else { 1 }
        last_null = true
        if start > len {
          break
        }
        continue
      }
    } else {
      out.push(s.unsafe_substring(start=beg, end=mb))
      beg = me
      start = me
    }
    last_null = false
    for g in 1..<m.size() {
      match m.group(g) {
        Some(t) => out.push(t)
        None => ()
      }
    }
    count += 1
  }
  if len > 0 && (limit != 0 || len > beg || limit < 0) {
    out.push(s.unsafe_substring(start=beg, end=len))
  }
  if limit == 0 {
    while out.length() > 0 && out[out.length() - 1] == "" {
      out.pop() |> ignore
    }
  }
  out
}

///|
/// Ruby's `String#split(re, limit)`. With `limit == 0` (default) trailing
/// empty strings are removed; captured groups are included in the result.
pub fn Regex::split(
  self : Regex,
  s : String,
  limit? : Int = 0,
) -> Array[String] {
  self.try_split(s, limit~) catch {
    e => timeout_abort(e)
  }
}
