///|
priv struct MaxDepth {
  abs : Int
  curr : Int
  rel : Int
}

///|
priv struct IncludeFrame {
  lines : Array[String]
  file : String?
  dir : String
  path : String
  lineno : Int
  maxdepth : MaxDepth?
  process_lines : Bool
}

///|
priv struct Conditional {
  name : String
  target : String?
  expr : String?
  skip : Bool
  skipping : Bool
  source_location : Cursor?
}

///|
priv struct PreState {
  document : Node
  sourcemap : Bool
  mut maxdepth : MaxDepth?
  mut include_stack : Array[IncludeFrame]
  includes : Map[String, Bool]
  mut skipping : Bool
  mut conditional_stack : Array[Conditional]
}

///|
priv struct ReaderSnapshot {
  file : String?
  dir : String
  path : String
  lineno : Int
  lines : Array[String]
  mark : Cursor?
  look_ahead : Int
  process_lines : Bool
  unescape_next_line : Bool
  unterminated : Bool
  pre : (MaxDepth?, Array[IncludeFrame], Bool, Array[Conditional])?
}

///|
/// A line reader over AsciiDoc source (Ruby `Reader`), optionally with
/// preprocessing of conditionals and includes (Ruby `PreprocessorReader`).
pub struct Reader {
  priv mut file : String?
  priv mut dir : String
  priv mut path : String
  priv mut lineno : Int
  priv mut lines : Array[String] // reversed: next line is last
  source_lines : Array[String]
  priv mut mark_ : Cursor?
  priv mut look_ahead : Int
  mut process_lines : Bool
  priv mut unescape_next_line : Bool
  mut unterminated : Bool
  priv mut saved : ReaderSnapshot?
  priv pre : PreState?
  // list continuation markers carried by line (parallel to `lines`); Ruby
  // tracks these through string identity (ListContinuationMarker)
  priv mut marks : Array[Bool]?
  priv mut last_marked : Bool
}

///|
fn reader_init(cursor : Cursor?) -> (String?, String, String, Int) {
  match cursor {
    None => (None, ".", "<stdin>", 1)
    Some(c) =>
      match c.file {
        Some(f) =>
          (
            Some(f),
            c.dir.unwrap_or(dirname(f)),
            c.path.unwrap_or(basename(f)),
            c.lineno,
          )
        None =>
          (None, c.dir.unwrap_or("."), c.path.unwrap_or("<stdin>"), c.lineno)
      }
  }
}

///|
/// Creates a reader over `data` (lines without line terminators).
pub fn Reader::new(
  data : Array[String],
  cursor? : Cursor,
  normalize? : Bool = false,
) -> Reader {
  let (file, dir, path, lineno) = reader_init(cursor)
  let source_lines = if normalize {
    prepare_source_array(data)
  } else {
    data.copy()
  }
  let lines = source_lines.copy()
  lines.rev_in_place()
  {
    file,
    dir,
    path,
    lineno,
    lines,
    source_lines,
    mark_: None,
    look_ahead: 0,
    process_lines: true,
    unescape_next_line: false,
    unterminated: false,
    saved: None,
    pre: None,
    marks: None,
    last_marked: false,
  }
}

///|
/// Creates a reader whose lines carry list-continuation markers.
fn Reader::new_marked(
  data : Array[String],
  marks : Array[Bool],
  cursor? : Cursor,
) -> Reader {
  let r = Reader::new(data, cursor?)
  if marks.iter().any(m => m) {
    let m = marks.copy()
    m.rev_in_place()
    r.marks = Some(m)
  }
  r
}

///|
/// Whether the line most recently consumed carried a list continuation marker.
fn Reader::last_line_marked(self : Reader) -> Bool {
  self.last_marked
}

///|
/// Restores a line with its marker flag.
fn Reader::unshift_marked(self : Reader, line : String, mark : Bool) -> Unit {
  if mark && self.marks is None {
    self.marks = Some(Array::make(self.lines.length(), false))
  }
  self.lineno -= 1
  self.look_ahead += 1
  self.lines.push(line)
  match self.marks {
    Some(m) => m.push(mark)
    None => ()
  }
}

///|
/// Creates a reader from a string (Ruby `Reader.new str`: chomp + split on LF).
pub fn Reader::from_string(data : String, cursor? : Cursor) -> Reader {
  Reader::new(@rb.split(@rb.chomp(data), "\n", limit=-1), cursor?)
}

///|
/// Creates a preprocessor reader (Ruby `PreprocessorReader.new`).
pub fn Reader::new_preprocessor(
  document : Node,
  data : Array[String],
  cursor? : Cursor,
  normalize? : Bool = false,
) -> Reader {
  let (file, dir, path, lineno) = reader_init(cursor)
  let default_depth = match document.attributes.get("max-include-depth") {
    Some(v) if v.truthy() => v.to_i()
    _ => 64
  }
  let pre : PreState = {
    document,
    sourcemap: document.sourcemap(),
    maxdepth: if default_depth > 0 {
      Some({ abs: default_depth, curr: default_depth, rel: default_depth, })
    } else {
      None
    },
    include_stack: [],
    includes: document.catalog().includes,
    skipping: false,
    conditional_stack: [],
  }
  let r : Reader = {
    file,
    dir,
    path,
    lineno,
    lines: [],
    source_lines: [],
    mark_: None,
    look_ahead: 0,
    process_lines: true,
    unescape_next_line: false,
    unterminated: false,
    saved: None,
    pre: Some(pre),
    marks: None,
    last_marked: false,
  }
  let skip_front_matter = document.attributes.truthy("skip-front-matter")
  let prepared = r.pre_prepare_lines(
    data,
    normalize_chomp=false,
    normalize~,
    for_include=false,
    skip_front_matter~,
  )
  for l in prepared {
    r.source_lines.push(l)
  }
  let lines = prepared.copy()
  lines.rev_in_place()
  r.lines = lines
  r
}

///|
fn Reader::pre_prepare_lines(
  self : Reader,
  data : Array[String],
  normalize_chomp~ : Bool,
  normalize~ : Bool,
  for_include~ : Bool,
  indent? : Int,
  skip_front_matter? : Bool = false,
) -> Array[String] {
  let result = if normalize || normalize_chomp {
    prepare_source_array(data, trim_end=!normalize_chomp)
  } else {
    data.copy()
  }
  let pre = self.pre.unwrap()
  if skip_front_matter {
    match self.skip_front_matter(result) {
      Some(front_matter) =>
        if !for_include {
          pre.document.attributes.set_str(
            "front-matter",
            front_matter.join("\n"),
          )
        }
      None => ()
    }
  }
  if for_include {
    match indent {
      Some(i) =>
        adjust_indentation(
          result,
          indent_size=i,
          tab_size=pre.document.attributes
            .get("tabsize")
            .map(v => v.to_i())
            .unwrap_or(0),
        )
      None => ()
    }
  } else {
    while result.length() > 0 && result[result.length() - 1] == "" {
      result.pop() |> ignore
    }
  }
  result
}

///|
fn Reader::skip_front_matter(
  self : Reader,
  data : Array[String],
) -> Array[String]? {
  guard data.get(0) is Some(delim) && (delim == "---" || delim == "+++") else {
    return None
  }
  let mut i = 1
  let front_matter = []
  while i < data.length() && data[i] != delim {
    front_matter.push(data[i])
    i += 1
  }
  if i >= data.length() {
    return None
  }
  // remove delimiter lines and front matter
  for _ in 0..<=i {
    data.remove(0) |> ignore
  }
  self.lineno += i + 1
  Some(front_matter)
}

///|
pub fn Reader::file(self : Reader) -> String? {
  self.file
}

///|
pub fn Reader::dir(self : Reader) -> String {
  self.dir
}

///|
pub fn Reader::path(self : Reader) -> String {
  self.path
}

///|
pub fn Reader::lineno(self : Reader) -> Int {
  self.lineno
}

///|
/// Whether there are more lines (processing directives as needed).
pub fn Reader::has_more_lines(self : Reader) -> Bool {
  if self.pre is Some(_) {
    return self.peek_line() is Some(_)
  }
  if self.lines.is_empty() {
    self.look_ahead = 0
    false
  } else {
    true
  }
}

///|
pub fn Reader::is_empty(self : Reader) -> Bool {
  !self.has_more_lines()
}

///|
pub fn Reader::next_line_empty(self : Reader) -> Bool {
  match self.peek_line() {
    Some(l) => l == ""
    None => true
  }
}

///|
fn Reader::base_peek_line(self : Reader, direct : Bool) -> String? {
  while true {
    let n = self.lines.length()
    if direct || self.look_ahead > 0 {
      if n == 0 {
        return None
      }
      let next_line = self.lines[n - 1]
      return Some(
        if self.unescape_next_line {
          @rb.from(next_line, 1)
        } else {
          next_line
        },
      )
    }
    if n > 0 {
      match self.process_line(self.lines[n - 1]) {
        Some(line) => return Some(line)
        None => continue
      }
    } else {
      self.look_ahead = 0
      return None
    }
  }
  None
}

///|
/// The next line without consuming it.
pub fn Reader::peek_line(self : Reader, direct? : Bool = false) -> String? {
  match self.base_peek_line(direct) {
    Some(line) => Some(line)
    None =>
      match self.pre {
        None => None
        Some(pre) =>
          if pre.include_stack.is_empty() {
            let mut end_cursor : Cursor? = None
            for c in pre.conditional_stack {
              let loc = match c.source_location {
                Some(l) => l
                None =>
                  match end_cursor {
                    Some(e) => e
                    None => {
                      let e = self.cursor_at_prev_line()
                      end_cursor = Some(e)
                      e
                    }
                  }
              }
              log_error(
                "detected unterminated preprocessor conditional directive: \{c.name}::\{c.target.unwrap_or("")}[\{c.expr.unwrap_or("")}]",
                source_location=loc,
              )
            }
            pre.conditional_stack = []
            None
          } else {
            self.pop_include()
            self.peek_line(direct~)
          }
      }
  }
}

///|
/// Peeks up to `num` lines (processing directives unless `direct`).
pub fn Reader::peek_lines(
  self : Reader,
  num? : Int,
  direct? : Bool = false,
) -> Array[String] {
  let old_look_ahead = self.look_ahead
  let result = []
  let limit = num.unwrap_or(2147483647)
  for _ in 0..<limit {
    let line = if direct { self.shift() } else { self.read_line() }
    match line {
      Some(l) => result.push(l)
      None => {
        if direct {
          self.lineno -= 1
        }
        break
      }
    }
  }
  if !result.is_empty() {
    self.unshift_all(result)
    if direct {
      self.look_ahead = old_look_ahead
    }
  }
  result
}

///|
/// Reads (consumes) the next line.
pub fn Reader::read_line(self : Reader) -> String? {
  if self.look_ahead > 0 || self.has_more_lines() {
    self.shift()
  } else {
    None
  }
}

///|
/// Reads all remaining lines.
pub fn Reader::read_lines(self : Reader) -> Array[String] {
  let lines = []
  while self.has_more_lines() {
    match self.shift() {
      Some(l) => lines.push(l)
      None => break
    }
  }
  lines
}

///|
/// Reads all remaining lines joined with LF.
pub fn Reader::read(self : Reader) -> String {
  self.read_lines().join("\n")
}

///|
/// Advances past the next line; returns whether a line was consumed.
pub fn Reader::advance(self : Reader) -> Bool {
  self.shift() is Some(_)
}

///|
pub fn Reader::unshift_line(self : Reader, line : String) -> Unit {
  self.unshift(line)
}

///|
pub fn Reader::unshift_lines(self : Reader, lines : Array[String]) -> Unit {
  self.unshift_all(lines)
}

///|
/// Replaces the next line (Ruby `replace_next_line`).
pub fn Reader::replace_next_line(self : Reader, replacement : String) -> Bool {
  self.shift() |> ignore
  self.unshift(replacement)
  true
}

///|
/// Skips blank lines; returns the number skipped, or None if at end.
pub fn Reader::skip_blank_lines(self : Reader) -> Int? {
  if self.is_empty() {
    return None
  }
  let mut num_skipped = 0
  while self.peek_line() is Some(next_line) {
    if next_line != "" {
      return Some(num_skipped)
    }
    self.shift() |> ignore
    num_skipped += 1
  }
  None
}

///|
/// Skips comment lines and comment blocks.
pub fn Reader::skip_comment_lines(self : Reader) -> Unit {
  if self.is_empty() {
    return
  }
  while self.peek_line() is Some(next_line) && next_line != "" {
    if !next_line.has_prefix("//") {
      break
    }
    if next_line.has_prefix("///") {
      let ll = next_line.length()
      if !(ll > 3 && next_line == @rb.repeat("/", ll)) {
        break
      }
      self.read_lines_until(
        terminator=next_line,
        skip_first_line=true,
        read_last_line=true,
        skip_processing=true,
        context=Some("comment"),
      )
      |> ignore
    } else {
      self.shift() |> ignore
    }
  }
}

///|
/// Skips single-line comments, returning them.
pub fn Reader::skip_line_comments(self : Reader) -> Array[String] {
  if self.is_empty() {
    return []
  }
  let comment_lines = []
  while self.peek_line() is Some(next_line) && next_line != "" {
    if !next_line.has_prefix("//") {
      break
    }
    match self.shift() {
      Some(l) => comment_lines.push(l)
      None => break
    }
  }
  comment_lines
}

///|
/// Discards all remaining lines.
pub fn Reader::terminate(self : Reader) -> Unit {
  self.lineno += self.lines.length()
  self.lines.clear()
  self.marks = None
  self.look_ahead = 0
}

///|
/// Reads lines until a terminator or break condition (Ruby `read_lines_until`).
/// `context`: None → use terminator in the warning; Some(None) → no warning.
pub fn Reader::read_lines_until(
  self : Reader,
  terminator? : String,
  skip_processing? : Bool = false,
  break_on_blank_lines? : Bool = false,
  break_on_list_continuation? : Bool = false,
  skip_line_comments? : Bool = false,
  skip_first_line? : Bool = false,
  read_last_line? : Bool = false,
  preserve_last_line? : Bool = false,
  context? : String?,
  cursor? : Cursor,
  cursor_at_mark? : Bool = false,
  break_if? : (String) -> Bool,
) -> Array[String] {
  let result = []
  let mut restore_process_lines = false
  if self.process_lines && skip_processing {
    self.process_lines = false
    restore_process_lines = true
  }
  let mut start_cursor : Cursor? = None
  let mut break_on_blank_lines = break_on_blank_lines
  let mut break_on_list_continuation = break_on_list_continuation
  if terminator is Some(_) {
    start_cursor = match cursor {
      Some(c) => Some(c)
      None => if cursor_at_mark { None } else { Some(self.cursor()) }
    }
    break_on_blank_lines = false
    break_on_list_continuation = false
  }
  let mut preserve_last_line = preserve_last_line
  let mut line_read = false
  let mut line_restored = false
  if skip_first_line {
    self.shift() |> ignore
  }
  let mut last_line : String? = None
  while self.read_line() is Some(line) {
    last_line = Some(line)
    let stop = match terminator {
      Some(t) => line == t
      None =>
        (break_on_blank_lines && line == "") ||
        (
          break_on_list_continuation &&
          line_read &&
          line == "+" &&
          ({
            preserve_last_line = true
            true
          })
        ) ||
        (match break_if {
          Some(f) => f(line)
          None => false
        })
    }
    if stop {
      if read_last_line {
        result.push(line)
      }
      if preserve_last_line {
        self.unshift(line)
        line_restored = true
      }
      break
    }
    if !(skip_line_comments && line.has_prefix("//") && !line.has_prefix("///")) {
      result.push(line)
      line_read = true
    }
    last_line = None
  }
  if restore_process_lines {
    self.process_lines = true
    if line_restored && terminator is None {
      self.look_ahead -= 1
    }
  }
  match terminator {
    Some(t) if last_line != Some(t) => {
      let ctx = match context {
        Some(c) => c
        None => Some(t)
      }
      match ctx {
        Some(ctx) => {
          let loc = match start_cursor {
            Some(c) => c
            None => self.cursor_at_mark()
          }
          log_warn("unterminated \{ctx} block", source_location=loc)
          self.unterminated = true
        }
        None => ()
      }
    }
    _ => ()
  }
  result
}

///|
/// Consumes the next line.
pub fn Reader::shift(self : Reader) -> String? {
  if self.pre is Some(_) && self.unescape_next_line {
    self.unescape_next_line = false
    match self.base_shift() {
      Some(line) => Some(@rb.from(line, 1))
      None => None
    }
  } else {
    self.base_shift()
  }
}

///|
fn Reader::base_shift(self : Reader) -> String? {
  self.lineno += 1
  if self.look_ahead != 0 {
    self.look_ahead -= 1
  }
  self.last_marked = match self.marks {
    Some(m) => m.pop().unwrap_or(false)
    None => false
  }
  self.lines.pop()
}

///|
fn Reader::unshift(self : Reader, line : String) -> Unit {
  self.lineno -= 1
  self.look_ahead += 1
  self.lines.push(line)
  match self.marks {
    Some(m) => m.push(false)
    None => ()
  }
}

///|
fn Reader::unshift_all(self : Reader, lines : Array[String]) -> Unit {
  self.lineno -= lines.length()
  self.look_ahead += lines.length()
  for i = lines.length() - 1; i >= 0; i = i - 1 {
    self.lines.push(lines[i])
    match self.marks {
      Some(m) => m.push(false)
      None => ()
    }
  }
}

///|
pub fn Reader::cursor(self : Reader) -> Cursor {
  Cursor::new(file?=self.file, dir=self.dir, path=self.path, lineno=self.lineno)
}

///|
pub fn Reader::cursor_at_line(self : Reader, lineno : Int) -> Cursor {
  Cursor::new(file?=self.file, dir=self.dir, path=self.path, lineno~)
}

///|
pub fn Reader::cursor_at_mark(self : Reader) -> Cursor {
  match self.mark_ {
    Some(m) => m.dup()
    None => self.cursor()
  }
}

///|
pub fn Reader::cursor_before_mark(self : Reader) -> Cursor {
  match self.mark_ {
    Some(m) => {
      let c = m.dup()
      c.lineno -= 1
      c
    }
    None =>
      Cursor::new(
        file?=self.file,
        dir=self.dir,
        path=self.path,
        lineno=self.lineno - 1,
      )
  }
}

///|
pub fn Reader::cursor_at_prev_line(self : Reader) -> Cursor {
  Cursor::new(
    file?=self.file,
    dir=self.dir,
    path=self.path,
    lineno=self.lineno - 1,
  )
}

///|
/// Marks the current position; returns the marked cursor.
pub fn Reader::mark(self : Reader) -> Cursor {
  let c = self.cursor()
  self.mark_ = Some(c)
  c.dup()
}

///|
pub fn Reader::line_info(self : Reader) -> String {
  "\{self.path}: line \{self.lineno}"
}

///|
/// The remaining lines (in order).
pub fn Reader::lines(self : Reader) -> Array[String] {
  let l = self.lines.copy()
  l.rev_in_place()
  l
}

///|
/// The remaining lines joined by LF.
pub fn Reader::string(self : Reader) -> String {
  self.lines().join("\n")
}

///|
/// The source lines joined by LF.
pub fn Reader::source(self : Reader) -> String {
  self.source_lines.join("\n")
}

///|
/// Saves the reader state.
pub fn Reader::save(self : Reader) -> Unit {
  self.saved = Some({
    file: self.file,
    dir: self.dir,
    path: self.path,
    lineno: self.lineno,
    lines: self.lines.copy(),
    mark: self.mark_,
    look_ahead: self.look_ahead,
    process_lines: self.process_lines,
    unescape_next_line: self.unescape_next_line,
    unterminated: self.unterminated,
    pre: self.pre.map(p => {
      (
        p.maxdepth,
        p.include_stack.copy(),
        p.skipping,
        p.conditional_stack.copy(),
      )
    }),
  })
}

///|
/// Restores the saved reader state.
pub fn Reader::restore_save(self : Reader) -> Unit {
  guard self.saved is Some(s) else { return }
  self.file = s.file
  self.dir = s.dir
  self.path = s.path
  self.lineno = s.lineno
  self.lines = s.lines
  self.mark_ = s.mark
  self.look_ahead = s.look_ahead
  self.process_lines = s.process_lines
  self.unescape_next_line = s.unescape_next_line
  self.unterminated = s.unterminated
  match (self.pre, s.pre) {
    (Some(p), Some((md, istack, sk, cs))) => {
      p.maxdepth = md
      p.include_stack = istack
      p.skipping = sk
      p.conditional_stack = cs
    }
    _ => ()
  }
  self.saved = None
}

///|
pub fn Reader::discard_save(self : Reader) -> Unit {
  self.saved = None
}

// ---------------------------------------------------------------------------
// Preprocessor

///|
fn Reader::process_line(self : Reader, line : String) -> String? {
  guard self.pre is Some(pre) && self.process_lines else {
    if self.process_lines {
      self.look_ahead += 1
    }
    return Some(line)
  }
  if line == "" {
    if pre.skipping {
      self.shift() |> ignore
      return None
    }
    self.look_ahead += 1
    return Some(line)
  }
  if line.has_suffix("]") && !line.has_prefix("[") && line.contains("::") {
    if line.contains("if") && conditional_directive_rx.find(line) is Some(m) {
      if m.group(1) == Some("\\") {
        self.unescape_next_line = true
        self.look_ahead += 1
        return Some(@rb.from(line, 1))
      } else if self.preprocess_conditional_directive(
          m.at(2),
          m.at(3),
          m.group(4),
          m.group(5),
        ) {
        self.shift() |> ignore
        return None
      } else {
        self.look_ahead += 1
        return Some(line)
      }
    } else if pre.skipping {
      self.shift() |> ignore
      return None
    } else if (line.has_prefix("inc") || line.has_prefix("\\inc")) &&
      include_directive_rx.find(line) is Some(m) {
      if m.group(1) == Some("\\") {
        self.unescape_next_line = true
        self.look_ahead += 1
        return Some(@rb.from(line, 1))
      } else {
        match self.preprocess_include_directive(m.at(2), m.group(3)) {
          true => return None
          false => {
            self.look_ahead += 1
            return Some(line)
          }
        }
      }
    } else {
      self.look_ahead += 1
      return Some(line)
    }
  } else if pre.skipping {
    self.shift() |> ignore
    None
  } else {
    self.look_ahead += 1
    Some(line)
  }
}

///|
/// A value of an ifeval expression operand.
priv enum ExprVal {
  EStr(String)
  EInt(Int)
  EFloat(Double)
  EBool(Bool)
  ENil
} derive(Eq)

///|
fn compare_expr(lhs : ExprVal, op : String, rhs : ExprVal) -> Bool raise {
  let num = fn(v : ExprVal) -> Double? {
    match v {
      EInt(i) => Some(i.to_double())
      EFloat(f) => Some(f)
      _ => None
    }
  }
  match op {
    "==" =>
      match (num(lhs), num(rhs)) {
        (Some(a), Some(b)) => a == b
        _ => lhs == rhs
      }
    "!=" =>
      match (num(lhs), num(rhs)) {
        (Some(a), Some(b)) => a != b
        _ => lhs != rhs
      }
    _ => {
      let c = match (lhs, rhs) {
        (EStr(a), EStr(b)) => @rb.lex_compare(a, b)
        _ =>
          match (num(lhs), num(rhs)) {
            (Some(a), Some(b)) => a.compare(b)
            _ => raise Failure("incomparable")
          }
      }
      match op {
        "<" => c < 0
        "<=" => c <= 0
        ">" => c > 0
        ">=" => c >= 0
        _ => raise Failure("bad op")
      }
    }
  }
}

///|
fn Reader::resolve_expr_val(self : Reader, val : String) -> ExprVal {
  let mut val = val
  let mut quoted = false
  if (val.has_prefix("\"") && val.has_suffix("\"")) ||
    (val.has_prefix("'") && val.has_suffix("'")) {
    quoted = true
    val = @rb.slice(val, 1, val.length() - 1)
  }
  if val.contains("{") {
    val = self.pre.unwrap().document.sub_attributes(
      val,
      attribute_missing="drop",
    )
  }
  if quoted {
    EStr(val)
  } else if val == "" {
    ENil
  } else if val == "true" {
    EBool(true)
  } else if val == "false" {
    EBool(false)
  } else if @rb.rstrip(val) == "" {
    EStr(" ")
  } else if val.contains(".") {
    EFloat(@rb.to_f(val))
  } else {
    EInt(@rb.to_i(val))
  }
}

///|
fn Reader::preprocess_conditional_directive(
  self : Reader,
  name : String,
  target : String,
  delimiter : String?,
  text : String?,
) -> Bool {
  let pre = self.pre.unwrap()
  let doc = pre.document
  let no_target = target == ""
  let target = if no_target { target } else { @rb.downcase(target) }
  let mut skip = false
  if name == "endif" {
    if text is Some(t) {
      log_error(
        "malformed preprocessor directive - text not permitted: endif::\{target}[\{t}]",
        source_location=self.cursor(),
      )
    } else if pre.conditional_stack.is_empty() {
      log_error(
        "unmatched preprocessor directive: endif::\{target}[]",
        source_location=self.cursor(),
      )
    } else {
      let top = pre.conditional_stack[pre.conditional_stack.length() - 1]
      if no_target || Some(target) == top.target {
        pre.conditional_stack.pop() |> ignore
        pre.skipping = match pre.conditional_stack.last() {
          Some(c) => c.skipping
          None => false
        }
      } else {
        log_error(
          "mismatched preprocessor directive: endif::\{target}[], expected endif::\{top.target.unwrap_or("")}[]",
          source_location=self.cursor(),
        )
      }
    }
    return true
  } else if pre.skipping {
    if name == "ifeval" {
      if !(no_target &&
        (match text {
          Some(t) => eval_expression_rx.matches(@rb.strip(t))
          None => false
        })) {
        return true
      }
    } else if no_target {
      return true
    }
    skip = false
  } else {
    match name {
      "ifdef" => {
        if no_target {
          log_error(
            "malformed preprocessor directive - missing target: ifdef::[\{text.unwrap_or("")}]",
            source_location=self.cursor(),
          )
          return true
        }
        skip = match delimiter {
          Some(",") =>
            @rb.split(target, ",", limit=-1)
            .iter()
            .all(n => !doc.attributes.contains(n))
          Some("+") =>
            @rb.split(target, "+", limit=-1)
            .iter()
            .any(n => !doc.attributes.contains(n))
          _ => !doc.attributes.contains(target)
        }
      }
      "ifndef" => {
        if no_target {
          log_error(
            "malformed preprocessor directive - missing target: ifndef::[\{text.unwrap_or("")}]",
            source_location=self.cursor(),
          )
          return true
        }
        skip = match delimiter {
          Some(",") =>
            @rb.split(target, ",", limit=-1)
            .iter()
            .any(n => doc.attributes.contains(n))
          Some("+") =>
            @rb.split(target, "+", limit=-1)
            .iter()
            .all(n => doc.attributes.contains(n))
          _ => doc.attributes.contains(target)
        }
      }
      "ifeval" =>
        if no_target {
          match text {
            Some(t) if eval_expression_rx.find(@rb.strip(t)) is Some(m) => {
              let lhs = self.resolve_expr_val(m.at(1))
              let op = m.at(2)
              let rhs = self.resolve_expr_val(m.at(3))
              skip = !(compare_expr(lhs, op, rhs) catch { _ => false })
            }
            _ => {
              log_error(
                "malformed preprocessor directive - \{if text is Some(_) { "invalid expression" } else { "missing expression" }}: ifeval::[\{text.unwrap_or("")}]",
                source_location=self.cursor(),
              )
              return true
            }
          }
        } else {
          log_error(
            "malformed preprocessor directive - target not permitted: ifeval::\{target}[\{text.unwrap_or("")}]",
            source_location=self.cursor(),
          )
          return true
        }
      _ => ()
    }
  }
  if name == "ifeval" {
    if skip {
      pre.skipping = true
    }
    pre.conditional_stack.push({
      name,
      target: None,
      expr: text,
      skip,
      skipping: pre.skipping,
      source_location: if pre.sourcemap {
        Some(self.cursor())
      } else {
        None
      },
    })
  } else {
    match text {
      Some(t) =>
        if !pre.skipping && !skip {
          self.replace_next_line(@rb.rstrip(t)) |> ignore
          self.unshift("")
          if t.has_prefix("include::") {
            self.look_ahead -= 1
          }
        }
      None => {
        if skip {
          pre.skipping = true
        }
        pre.conditional_stack.push({
          name,
          target: Some(target),
          expr: None,
          skip,
          skipping: pre.skipping,
          source_location: if pre.sourcemap {
            Some(self.cursor())
          } else {
            None
          },
        })
      }
    }
  }
  true
}

///|
fn split_delimited_value(val : String) -> Array[String] {
  if val.contains(",") {
    @rb.split(val, ",")
  } else {
    @rb.split(val, ";")
  }
}

///|
fn Reader::preprocess_include_directive(
  self : Reader,
  target : String,
  attrlist : String?,
) -> Bool {
  let pre = self.pre.unwrap()
  let doc = pre.document
  let attrlist_s = attrlist.unwrap_or("")
  let mut expanded_target = target
  if target.contains("{") {
    let attr_missing = doc.attributes
      .str("attribute-missing")
      .unwrap_or(compliance.attribute_missing)
    expanded_target = doc.sub_attributes(
      target,
      attribute_missing=if attr_missing == "warn" {
        "drop-line"
      } else {
        attr_missing
      },
    )
    if expanded_target == "" {
      let dropped_due_to_missing = fn() {
        doc.sub_attributes(
          target + " ",
          attribute_missing="drop-line",
          drop_line_ignore=true,
        ) ==
        ""
      }
      if attr_missing == "drop-line" && dropped_due_to_missing() {
        log_info(
          "include dropped due to missing attribute: include::\{target}[\{attrlist_s}]",
          source_location=self.cursor(),
        )
        self.shift() |> ignore
        return true
      } else if doc
        .parse_attributes(attrlist_s, [], sub_input=true)
        .truthy("optional-option") {
        let reason = if attr_missing == "warn" && dropped_due_to_missing() {
          "due to missing attribute"
        } else {
          "because resolved target is blank"
        }
        log_info(
          "optional include dropped \{reason}: include::\{target}[\{attrlist_s}]",
          source_location=self.cursor(),
        )
        self.shift() |> ignore
        return true
      } else {
        let reason = if attr_missing == "warn" && dropped_due_to_missing() {
          "due to missing attribute"
        } else {
          "because resolved target is blank"
        }
        log_warn(
          "include dropped \{reason}: include::\{target}[\{attrlist_s}]",
          source_location=self.cursor(),
        )
        return self.replace_next_line(
          "Unresolved directive in \{self.path} - include::\{target}[\{attrlist_s}]",
        )
      }
    }
  }
  match doc.extensions() {
    Some(exts) =>
      for ext in exts.include_processors() {
        if (ext.handles)(doc, expanded_target) {
          self.shift() |> ignore
          (ext.process)(
            doc,
            self,
            expanded_target,
            doc.parse_attributes(attrlist_s, [], sub_input=true),
          )
          return true
        }
      }
    None => ()
  }
  if doc.safe() >= SAFE_SECURE {
    let t = if expanded_target.contains(" ") {
      "pass:c[\{expanded_target}]"
    } else {
      expanded_target
    }
    let link_attrlist = if doc.has_attr("compat-mode") {
      attrlist_s
    } else {
      "role=include\{match attrlist { Some(a) => "," + a; None => "" }}"
    }
    return self.replace_next_line("link:\{t}[\{link_attrlist}]")
  }
  guard pre.maxdepth is Some(maxdepth) else { return false }
  if pre.include_stack.length() >= maxdepth.curr {
    log_error(
      "maximum include depth of \{maxdepth.rel} exceeded",
      source_location=self.cursor(),
    )
    return false
  }
  let parsed_attrs = doc.parse_attributes(attrlist_s, [], sub_input=true)
  let (inc_path, relpath) = match
    self.resolve_include_path(expanded_target, attrlist, parsed_attrs) {
    IncludeResolved(p, r) => (p, r)
    IncludeHandled(b) => return b
  }
  let encoding = parsed_attrs.str("encoding")
  let read_text = fn() -> String? {
    doc.vfs().read(inc_path).map(data => decode_text_with(data, encoding))
  }
  let mut inc_linenos : Array[Int]? = None // -1 means "to the end"
  let mut inc_tags : Array[(String, Bool)]? = None
  if attrlist is Some(_) {
    if parsed_attrs.contains("lines") {
      let linenos = []
      let mut open_end = false
      for
        linedef in split_delimited_value(
          parsed_attrs.str("lines").unwrap_or(""),
        ) {
        if linedef.contains("..") {
          let (from, _, to) = @rb.partition(linedef, "..")
          let to_i = @rb.to_i(to)
          if to == "" || to_i < 0 {
            linenos.push(@rb.to_i(from))
            open_end = true
          } else {
            for i in @rb.to_i(from)..<=to_i {
              linenos.push(i)
            }
          }
        } else {
          linenos.push(@rb.to_i(linedef))
        }
      }
      if !linenos.is_empty() {
        linenos.sort()
        let uniq = []
        for v in linenos {
          if uniq.is_empty() || uniq[uniq.length() - 1] != v {
            uniq.push(v)
          }
        }
        if open_end {
          uniq.push(-1)
        }
        inc_linenos = Some(uniq)
      } else if open_end {
        inc_linenos = Some([-1])
      }
    } else if parsed_attrs.contains("tag") {
      let tag = parsed_attrs.str("tag").unwrap_or("")
      if tag != "" && tag != "!" {
        inc_tags = Some(
          if tag.has_prefix("!") {
            [(@rb.from(tag, 1), false)]
          } else {
            [(tag, true)]
          },
        )
      }
    } else if parsed_attrs.contains("tags") {
      let tags : Array[(String, Bool)] = []
      let put = fn(k : String, v : Bool) {
        match tags.search_by(t => t.0 == k) {
          Some(i) => tags[i] = (k, v)
          None => tags.push((k, v))
        }
      }
      for
        tagdef in split_delimited_value(parsed_attrs.str("tags").unwrap_or("")) {
        if tagdef != "" && tagdef != "!" {
          if tagdef.has_prefix("!") {
            put(@rb.from(tagdef, 1), false)
          } else {
            put(tagdef, true)
          }
        }
      }
      if !tags.is_empty() {
        inc_tags = Some(tags)
      }
    }
  }
  let unresolved = fn() {
    log_error(
      "include file not readable: \{inc_path}",
      source_location=self.cursor(),
    )
    self.replace_next_line(
      "Unresolved directive in \{self.path} - include::\{expanded_target}[\{attrlist_s}]",
    )
  }
  match inc_linenos {
    Some(linenos) => {
      guard read_text() is Some(content) else { return unresolved() }
      let inc_lines = []
      let mut inc_offset : Int? = None
      let mut inc_lineno = 0
      let mut remaining = linenos
      let mut select_remaining = false
      for l in each_line(content) {
        inc_lineno += 1
        if select_remaining || (remaining.length() > 0 && remaining[0] == -1) {
          select_remaining = true
          if inc_offset is None {
            inc_offset = Some(inc_lineno)
          }
          inc_lines.push(l)
        } else {
          if remaining.length() > 0 && remaining[0] == inc_lineno {
            if inc_offset is None {
              inc_offset = Some(inc_lineno)
            }
            inc_lines.push(l)
            remaining = remaining[1:].to_owned()
          }
          if remaining.is_empty() {
            break
          }
        }
      }
      self.shift() |> ignore
      match inc_offset {
        Some(off) => {
          parsed_attrs.set_str("partial-option", "")
          self.push_include(
            inc_lines,
            Some(inc_path),
            Some(relpath),
            off,
            parsed_attrs,
          )
        }
        None => ()
      }
    }
    None =>
      match inc_tags {
        Some(tags0) => {
          guard read_text() is Some(content) else { return unresolved() }
          let tags = tags0.copy()
          let get_tag = fn(k : String) -> Bool? {
            match tags.search_by(t => t.0 == k) {
              Some(i) => Some(tags[i].1)
              None => None
            }
          }
          let remove_tag = fn(k : String) -> Bool? {
            match tags.search_by(t => t.0 == k) {
              Some(i) => Some(tags.remove(i).1)
              None => None
            }
          }
          let inc_lines = []
          let mut inc_offset : Int? = None
          let mut inc_lineno = 0
          let tag_stack : Array[(String, Bool, Int)] = []
          let tags_selected : Array[String] = []
          let mut active_tag : String? = None
          let mut select = false
          let mut base_select = false
          let mut wildcard : Bool? = None
          if get_tag("**") is Some(_) {
            select = remove_tag("**").unwrap()
            base_select = select
            if get_tag("*") is Some(_) {
              wildcard = remove_tag("*")
            } else if !select && tags.length() > 0 && !tags[0].1 {
              wildcard = Some(true)
            }
          } else if get_tag("*") is Some(_) {
            if tags[0].0 == "*" {
              wildcard = remove_tag("*")
              select = !wildcard.unwrap()
              base_select = select
            } else {
              select = false
              base_select = false
              wildcard = remove_tag("*")
            }
          } else {
            select = !tags.iter().any(t => t.1)
            base_select = select
          }
          for l in each_line(content) {
            inc_lineno += 1
            if l.contains("::") &&
              l.contains("[]") &&
              tag_directive_rx.find(l) is Some(m) {
              let this_tag = m.at(2)
              if m.has(1) {
                if Some(this_tag) == active_tag {
                  tag_stack.pop() |> ignore
                  match tag_stack.last() {
                    Some((t, s, _)) => {
                      active_tag = Some(t)
                      select = s
                    }
                    None => {
                      active_tag = None
                      select = base_select
                    }
                  }
                } else if get_tag(this_tag) is Some(_) {
                  let include_cursor = self.create_include_cursor(
                    inc_path, expanded_target, inc_lineno,
                  )
                  match tag_stack.search_by(t => t.0 == this_tag) {
                    Some(idx) => {
                      tag_stack.remove(idx) |> ignore
                      log_warn(
                        "mismatched end tag (expected '\{active_tag.unwrap_or("")}' but found '\{this_tag}') at line \{inc_lineno} of include file: \{inc_path}",
                        source_location=self.cursor(),
                        include_location=include_cursor,
                      )
                    }
                    None =>
                      log_warn(
                        "unexpected end tag '\{this_tag}' at line \{inc_lineno} of include file: \{inc_path}",
                        source_location=self.cursor(),
                        include_location=include_cursor,
                      )
                  }
                }
              } else {
                match get_tag(this_tag) {
                  Some(v) => {
                    select = v
                    if v {
                      tags_selected.push(this_tag)
                    }
                    active_tag = Some(this_tag)
                    tag_stack.push((this_tag, select, inc_lineno))
                  }
                  None =>
                    match wildcard {
                      Some(w) => {
                        select = if active_tag is Some(_) && !select {
                          false
                        } else {
                          w
                        }
                        active_tag = Some(this_tag)
                        tag_stack.push((this_tag, select, inc_lineno))
                      }
                      None => ()
                    }
                }
              }
            } else if select {
              if inc_offset is None {
                inc_offset = Some(inc_lineno)
              }
              inc_lines.push(l)
            }
          }
          for t in tag_stack {
            log_warn(
              "detected unclosed tag '\{t.0}' starting at line \{t.2} of include file: \{inc_path}",
              source_location=self.cursor(),
              include_location=self.create_include_cursor(
                inc_path,
                expanded_target,
                t.2,
              ),
            )
          }
          let missing = tags
            .filter(t => t.1 && !tags_selected.contains(t.0))
            .map(t => t.0)
          if !missing.is_empty() {
            log_warn(
              "tag\{if missing.length() > 1 { "s" } else { "" }} '\{missing.join(", ")}' not found in include file: \{inc_path}",
              source_location=self.cursor(),
            )
          }
          self.shift() |> ignore
          match inc_offset {
            Some(off) => {
              if !(base_select && wildcard != Some(false) && tags.is_empty()) {
                parsed_attrs.set_str("partial-option", "")
              }
              self.push_include(
                inc_lines,
                Some(inc_path),
                Some(relpath),
                off,
                parsed_attrs,
              )
            }
            None => ()
          }
        }
        None => {
          guard read_text() is Some(content) else { return unresolved() }
          self.shift() |> ignore
          self.push_include_string(
            content,
            Some(inc_path),
            Some(relpath),
            1,
            parsed_attrs,
          )
        }
      }
  }
  true
}

///|
/// Splits text into lines keeping their line terminators (Ruby `each_line`).
fn each_line(content : String) -> Array[String] {
  let out = []
  let n = content.length()
  let mut start = 0
  for i in 0..<n {
    if content[i] == '\n' {
      out.push(content.unsafe_substring(start~, end=i + 1))
      start = i + 1
    }
  }
  if start < n {
    out.push(content.unsafe_substring(start~, end=n))
  }
  out
}

///|
priv enum IncludeResolution {
  IncludeResolved(String, String)
  IncludeHandled(Bool)
}

///|
fn Reader::resolve_include_path(
  self : Reader,
  target : String,
  attrlist : String?,
  attributes : Attributes,
) -> IncludeResolution {
  let doc = self.pre.unwrap().document
  let attrlist_s = attrlist.unwrap_or("")
  if is_uriish(target) || is_uriish(self.dir) {
    let target = if is_uriish(target) {
      target
    } else {
      "\{self.dir}/\{target}"
    }
    if !doc.has_attr("allow-uri-read") {
      log_warn(
        "cannot include contents of URI: \{target} (allow-uri-read attribute not enabled)",
        source_location=self.cursor(),
      )
      let t = if target.contains(" ") { "pass:c[\{target}]" } else { target }
      let link_attrlist = if doc.has_attr("compat-mode") {
        attrlist_s
      } else {
        "role=include\{match attrlist { Some(a) => "," + a; None => "" }}"
      }
      return IncludeHandled(
        self.replace_next_line("link:\{t}[\{link_attrlist}]"),
      )
    }
    return IncludeResolved(target, target)
  }
  let inc_path = doc.normalize_system_path(
    target,
    start=self.dir,
    target_name="include file",
  )
  if !doc.vfs().is_file(inc_path) {
    if attributes.truthy("optional-option") {
      log_info(
        "optional include dropped because include file not found: \{inc_path}",
        source_location=self.cursor(),
      )
      self.shift() |> ignore
      return IncludeHandled(true)
    } else {
      log_error(
        "include file not found: \{inc_path}",
        source_location=self.cursor(),
      )
      return IncludeHandled(
        self.replace_next_line(
          "Unresolved directive in \{self.path} - include::\{target}[\{attrlist_s}]",
        ),
      )
    }
  }
  let relpath = doc.path_resolver().relative_path(inc_path, doc.base_dir())
  IncludeResolved(inc_path, relpath)
}

///|
fn Reader::create_include_cursor(
  _self : Reader,
  file : String,
  path : String,
  lineno : Int,
) -> Cursor {
  Cursor::new(file~, dir=dirname(file), path~, lineno~)
}

///|
/// Pushes include content given as lines with terminators.
fn Reader::push_include(
  self : Reader,
  data : Array[String],
  file : String?,
  path : String?,
  lineno : Int,
  attributes : Attributes,
) -> Unit {
  self.push_include_impl(data, file, path, lineno, attributes)
}

///|
fn Reader::push_include_string(
  self : Reader,
  data : String,
  file : String?,
  path : String?,
  lineno : Int,
  attributes : Attributes,
) -> Unit {
  self.push_include_impl(each_line(data), file, path, lineno, attributes)
}

///|
/// Pushes include content (Ruby `push_include`), also usable by include processors.
pub fn Reader::push_include_lines(
  self : Reader,
  data : Array[String],
  file? : String,
  path? : String,
  lineno? : Int = 1,
  attributes? : Attributes = Attributes::new(),
) -> Unit {
  self.push_include_impl(data, file, path, lineno, attributes)
}

///|
fn Reader::push_include_impl(
  self : Reader,
  data : Array[String],
  file : String?,
  path : String?,
  lineno : Int,
  attributes : Attributes,
) -> Unit {
  let pre = self.pre.unwrap()
  pre.include_stack.push({
    lines: self.lines,
    file: self.file,
    dir: self.dir,
    path: self.path,
    lineno: self.lineno,
    maxdepth: pre.maxdepth,
    process_lines: self.process_lines,
  })
  self.file = file
  match file {
    Some(f) => {
      self.dir = dirname(f)
      let p = path.unwrap_or(basename(f))
      self.path = p
      self.process_lines = [".adoc", ".asciidoc", ".asc", ".ad", ".txt"]
        .iter()
        .any(ext => f.has_suffix(ext))
      if self.process_lines {
        let key = match p.rev_find(".") {
          Some(i) => @rb.slice(p, 0, i)
          None => p
        }
        if !pre.includes.contains(key) || pre.includes[key] == false {
          pre.includes[key] = !attributes.truthy("partial-option")
        }
      }
    }
    None => {
      self.dir = "."
      self.process_lines = true
      match path {
        Some(p) => {
          self.path = p
          let key = rootname(p)
          if !pre.includes.contains(key) || pre.includes[key] == false {
            pre.includes[key] = !attributes.truthy("partial-option")
          }
        }
        None => self.path = "<stdin>"
      }
    }
  }
  self.lineno = lineno
  match pre.maxdepth {
    Some(md) if attributes.contains("depth") => {
      let rel = attributes.get("depth").unwrap().to_i()
      if rel > 0 {
        let mut curr = pre.include_stack.length() + rel
        let mut rel = rel
        if curr > md.abs {
          curr = md.abs
          rel = md.abs
        }
        pre.maxdepth = Some({ abs: md.abs, curr, rel, })
      } else {
        pre.maxdepth = Some({
          abs: md.abs,
          curr: pre.include_stack.length(),
          rel: 0,
        })
      }
    }
    _ => ()
  }
  let indent = match attributes.get("indent") {
    Some(v) if v.truthy() => Some(v.to_i())
    _ => None
  }
  let lines = self.pre_prepare_lines(
    data,
    normalize_chomp=!self.process_lines,
    normalize=self.process_lines,
    for_include=true,
    indent?,
    skip_front_matter=attributes.truthy("skip-front-matter-option"),
  )
  if lines.is_empty() {
    self.pop_include()
  } else {
    if attributes.contains("leveloffset") {
      let leveloffset = pre.document.attr("leveloffset")
      let head = match leveloffset {
        Some(l) => ":leveloffset: \{l}"
        None => ":leveloffset!:"
      }
      // the line stack is reversed: the last element is read first
      lines.rev_in_place()
      self.lines = [head, ""] +
        lines +
        ["", ":leveloffset: \{attributes.str("leveloffset").unwrap_or("")}"]
      self.lineno -= 2
    } else {
      lines.rev_in_place()
      self.lines = lines
    }
    self.look_ahead = 0
  }
}

///|
fn Reader::pop_include(self : Reader) -> Unit {
  guard self.pre is Some(pre) && pre.include_stack.pop() is Some(frame) else {
    return
  }
  self.lines = frame.lines
  self.file = frame.file
  self.dir = frame.dir
  self.path = frame.path
  self.lineno = frame.lineno
  pre.maxdepth = frame.maxdepth
  self.process_lines = frame.process_lines
  self.look_ahead = 0
}

///|
/// Current include depth.
pub fn Reader::include_depth(self : Reader) -> Int {
  match self.pre {
    Some(p) => p.include_stack.length()
    None => 0
  }
}
