///|
priv enum Inst {
  Unit(Int) // one UTF-16 code unit
  AnyChar(Bool) // `.`, dot-all?
  Set(Int) // index into classes
  Split(Int, Int) // try first, push second
  // `Star(greedy)` at pc heads the loop `Star; <one-char inst>; Jmp(pc)` and
  // behaves exactly like `Split(pc + 1, pc + 3)` (greedy) or
  // `Split(pc + 3, pc + 1)` (lazy) in its place, but keeps one backtrack
  // entry for the whole loop instead of one per iteration
  Star(Bool)
  Jmp(Int)
  Save(Int)
  Assert(AssertKind)
  Backref(Int, Bool) // group, ignore case?
  Look(Int, Bool, Bool, Int, Int, Bool) // sub index, ahead?, negated?, min width, max width (-1 unbounded), sub writes state?
  Atomic(Int, Bool) // sub index, sub writes state?
  Mark(Int) // regs[r] = pos
  Progress(Int) // fail unless pos > regs[r]
  SubEnd // end of a (sub)program
}

///|
/// Upper bound on compiled program size: counted repeats are expanded, so
/// nested intervals like `(?:a{1000}){1000}` would otherwise exhaust memory.
const MAX_PROGRAM = 1_000_000

///|
priv struct Compiler {
  prog : Array[Inst]
  classes : Array[CharClass]
  sub_nodes : Array[Node]
  sub_starts : Array[Int]
  mut nregs : Int
  names : Map[String, Int]
  pattern : String
  loops : Bool // emit `Star` for one-character loops
}

///|
fn nullable(node : Node) -> Bool {
  match node {
    Empty | Assert(_) | Look(_, _, _) => true
    Char(_) | Any(_) | Class(_) => false
    Concat(items) => items.iter().all(nullable)
    Alt(items) => items.iter().any(nullable)
    Group(_, n) | Atomic(n) => nullable(n)
    Repeat(n, min, _, _) => min == 0 || nullable(n)
    Backref(_, _) | NamedBackref(_, _) | Keep => true
  }
}

///|
/// Whether `node` compiles to one instruction that consumes exactly one
/// character (`Unit`, `AnyChar` or `Set`) or fails.
fn single_unit_step(node : Node) -> Bool {
  match node {
    Char(cp) => cp < 0x10000
    Any(_) | Class(_) => true
    Group(None, n) => single_unit_step(n)
    _ => false
  }
}

///|
/// Whether the node contains capture groups (so a sub-run must snapshot state).
fn writes_state(node : Node) -> Bool {
  match node {
    Empty
    | Assert(_)
    | Char(_)
    | Any(_)
    | Class(_)
    | Backref(_, _)
    | NamedBackref(_, _) => false
    Concat(items) | Alt(items) => items.iter().any(writes_state)
    Group(Some(_), _) | Keep => true
    Group(None, n) | Atomic(n) | Look(n, _, _) => writes_state(n)
    Repeat(n, _, max, _) => (max < 0 && nullable(n)) || writes_state(n)
  }
}

///|
/// Minimum and maximum width in UTF-16 code units (-1 = unbounded).
fn width(node : Node) -> (Int, Int) {
  match node {
    Empty | Assert(_) | Look(_, _, _) | Keep => (0, 0)
    Char(cp) => if cp >= 0x10000 { (2, 2) } else { (1, 1) }
    Any(_) | Class(_) => (1, 2)
    Concat(items) => {
      let mut lo = 0
      let mut hi = 0
      for it in items {
        let (a, b) = width(it)
        lo += a
        hi = if hi < 0 || b < 0 { -1 } else { hi + b }
      }
      (lo, hi)
    }
    Alt(items) => {
      let mut lo = -1
      let mut hi = 0
      for it in items {
        let (a, b) = width(it)
        lo = if lo < 0 || a < lo { a } else { lo }
        hi = if hi < 0 || b < 0 { -1 } else if b > hi { b } else { hi }
      }
      (if lo < 0 { 0 } else { lo }, hi)
    }
    Group(_, n) | Atomic(n) => width(n)
    Repeat(n, min, max, _) => {
      let (a, b) = width(n)
      (a * min, if max < 0 || b < 0 { -1 } else { b * max })
    }
    Backref(_, _) | NamedBackref(_, _) => (0, -1)
  }
}

///|
fn Compiler::emit(self : Compiler, inst : Inst) -> Int raise RegexError {
  if self.prog.length() >= MAX_PROGRAM {
    raise RegexError(
      pattern=self.pattern,
      pos=0,
      message="pattern too large (compiled program exceeds \{MAX_PROGRAM} instructions)",
    )
  }
  self.prog.push(inst)
  self.prog.length() - 1
}

///|
fn Compiler::pc(self : Compiler) -> Int {
  self.prog.length()
}

///|
fn Compiler::add_sub(self : Compiler, node : Node) -> Int {
  self.sub_nodes.push(node)
  self.sub_nodes.length() - 1
}

///|
fn Compiler::compile(self : Compiler, node : Node) -> Unit raise RegexError {
  match node {
    Empty => ()
    Char(cp) =>
      if cp >= 0x10000 {
        let v = cp - 0x10000
        self.emit(Unit(0xD800 + (v >> 10))) |> ignore
        self.emit(Unit(0xDC00 + (v & 0x3FF))) |> ignore
      } else {
        self.emit(Unit(cp)) |> ignore
      }
    Any(dotall) => self.emit(AnyChar(dotall)) |> ignore
    Class(cls) => {
      cls.prepare()
      self.classes.push(cls)
      self.emit(Set(self.classes.length() - 1)) |> ignore
    }
    Concat(items) =>
      for it in items {
        self.compile(it)
      }
    Alt(items) => {
      let jumps = []
      for i, it in items {
        if i < items.length() - 1 {
          let split = self.emit(Split(0, 0))
          self.compile(it)
          jumps.push(self.emit(Jmp(0)))
          self.prog[split] = Split(split + 1, self.pc())
        } else {
          self.compile(it)
        }
      }
      let end = self.pc()
      for j in jumps {
        self.prog[j] = Jmp(end)
      }
    }
    Group(Some(i), n) => {
      self.emit(Save(2 * i)) |> ignore
      self.compile(n)
      self.emit(Save(2 * i + 1)) |> ignore
    }
    Group(None, n) => self.compile(n)
    Assert(k) => self.emit(Assert(k)) |> ignore
    Keep => self.emit(Save(0)) |> ignore
    Backref(n, icase) => self.emit(Backref(n, icase)) |> ignore
    NamedBackref(name, icase) =>
      match self.names.get(name) {
        Some(n) => self.emit(Backref(n, icase)) |> ignore
        None =>
          raise RegexError(
            pattern=self.pattern,
            pos=0,
            message="undefined name <\{name}> reference",
          )
      }
    Look(n, ahead, neg) => {
      let (lo, hi) = width(n)
      let sub = self.add_sub(n)
      self.emit(Look(sub, ahead, neg, lo, hi, writes_state(n))) |> ignore
    }
    Atomic(n) => {
      let sub = self.add_sub(n)
      self.emit(Atomic(sub, writes_state(n))) |> ignore
    }
    Repeat(n, min, max, Possessive) =>
      self.compile(Atomic(Repeat(n, min, max, Greedy)))
    Repeat(n, min, max, greed) => {
      for _ in 0..<min {
        let before = self.pc()
        self.compile(n)
        if self.pc() == before {
          // `n` emits nothing (e.g. `(?:){100000}`): further copies would too
          break
        }
      }
      if max < 0 {
        let loop_pc = self.emit(Split(0, 0))
        let body = self.pc()
        let check = nullable(n)
        let reg = self.nregs
        if check {
          self.nregs += 1
          self.emit(Mark(reg)) |> ignore
        }
        self.compile(n)
        if check {
          self.emit(Progress(reg)) |> ignore
        }
        self.emit(Jmp(loop_pc)) |> ignore
        let end = self.pc()
        self.prog[loop_pc] = if self.loops &&
          end == body + 2 &&
          single_unit_step(n) {
          // `Star` runs this three-instruction loop in place (same layout,
          // same steps and backtracking order)
          Star(greed == Greedy)
        } else if greed == Greedy {
          Split(body, end)
        } else {
          Split(end, body)
        }
      } else if max > min {
        let splits = []
        for _ in min..<max {
          splits.push(self.emit(Split(0, 0)))
          self.compile(n)
        }
        let end = self.pc()
        for s in splits {
          self.prog[s] = if greed == Greedy {
            Split(s + 1, end)
          } else {
            Split(end, s + 1)
          }
        }
      }
    }
  }
}

///|
/// A set of possible first code units of a match (conservative).
priv struct FirstSet {
  ascii : FixedArray[Bool]
  non_ascii : Bool
}

///|
fn FirstSet::all() -> FirstSet? {
  None
}

///|
fn union_first(a : FirstSet?, b : FirstSet?) -> FirstSet? {
  match (a, b) {
    (Some(x), Some(y)) => {
      let t = FixedArray::make(128, false)
      for i in 0..<128 {
        t[i] = x.ascii[i] || y.ascii[i]
      }
      Some({ ascii: t, non_ascii: x.non_ascii || y.non_ascii, })
    }
    _ => None
  }
}

///|
fn empty_first() -> FirstSet? {
  Some({ ascii: FixedArray::make(128, false), non_ascii: false, })
}

///|
/// Returns the possible first code units and whether the node is nullable.
fn first_info(node : Node) -> (FirstSet?, Bool) {
  match node {
    Empty | Assert(_) | Look(_, _, _) | Keep => (empty_first(), true)
    Char(cp) => {
      let s = { ascii: FixedArray::make(128, false), non_ascii: cp >= 128, }
      if cp < 128 {
        s.ascii[cp] = true
      }
      (Some(s), false)
    }
    Any(_) => (FirstSet::all(), false)
    Class(cls) => {
      cls.prepare()
      let s = { ascii: FixedArray::make(128, false), non_ascii: true, }
      for i in 0..<128 {
        s.ascii[i] = cls.ascii[i]
      }
      (Some(s), false)
    }
    Concat(items) => {
      let mut acc = empty_first()
      let mut all_nullable = true
      for it in items {
        let (f, n) = first_info(it)
        acc = union_first(acc, f)
        if !n {
          all_nullable = false
          break
        }
      }
      (acc, all_nullable)
    }
    Alt(items) => {
      let mut acc = empty_first()
      let mut any_nullable = false
      for it in items {
        let (f, n) = first_info(it)
        acc = union_first(acc, f)
        any_nullable = any_nullable || n
      }
      (acc, any_nullable)
    }
    Group(_, n) | Atomic(n) => first_info(n)
    Repeat(n, min, _, _) => {
      let (f, nl) = first_info(n)
      (f, nl || min == 0)
    }
    Backref(_, _) | NamedBackref(_, _) => (FirstSet::all(), true)
  }
}

///|
priv enum Anchor {
  NoAnchor
  TextStart // \A
  LineStart // ^
} derive(Eq)

///|
fn leading_anchor(node : Node) -> Anchor {
  match node {
    Assert(BeginText) => TextStart
    Assert(BeginLine) => LineStart
    Concat(items) if items.length() > 0 => leading_anchor(items[0])
    Group(_, n) | Atomic(n) => leading_anchor(n)
    Alt(items) => {
      let first = leading_anchor(items[0])
      if items.iter().all(fn(it) { leading_anchor(it) == first }) {
        first
      } else {
        NoAnchor
      }
    }
    _ => NoAnchor
  }
}

///|
/// Code units that must occur in every match (used as a fast prefilter).
fn required_units(node : Node) -> Array[Int] {
  match node {
    Char(cp) => if cp < 0x10000 { [cp] } else { [] }
    Concat(items) => {
      let out = []
      for it in items {
        for u in required_units(it) {
          if !out.contains(u) {
            out.push(u)
          }
        }
      }
      out
    }
    Group(_, n) | Atomic(n) => required_units(n)
    Repeat(n, min, _, _) => if min > 0 { required_units(n) } else { [] }
    Alt(items) => {
      // intersection of all branches
      if items.is_empty() {
        return []
      }
      // compute each branch once (recomputing per unit is exponential in the
      // nesting depth of alternations)
      let sets = items.map(required_units)
      sets[0].filter(u => sets.iter().all(s => s.contains(u)))
    }
    _ => []
  }
}

///|
/// Most code units a `lead_set` may have.
const MAX_LEAD_UNITS = 4

///|
/// Like `lead_literal`, for patterns whose top-level concatenation continues,
/// after a prefix of bounded width, with a non-nullable remainder that can
/// only start with one of a few ASCII code units: (units, min offset, max
/// offset). E.g. `(^|[^\w])(?:\[[^\]]+\])?#...` has the units `[` and `#` at
/// offset 0 or 1. The search jumps between occurrences of these units.
fn lead_set(node : Node) -> (FixedArray[Bool], Int, Int)? {
  let items = match node {
    Concat(items) => items
    Group(_, Concat(items)) => items
    _ => return None
  }
  // first-set and nullability of every suffix `items[i:]`, computed once from
  // the back (analyzing each suffix separately is quadratic in the length)
  let n = items.length()
  let suffixes : Array[(FirstSet?, Bool)] = Array::make(
    n + 1,
    (empty_first(), true),
  )
  for i = n - 1; i >= 0; i = i - 1 {
    let (f, nullable) = first_info(items[i])
    suffixes[i] = if nullable {
      let (rest, rest_nullable) = suffixes[i + 1]
      (union_first(f, rest), rest_nullable)
    } else {
      (union_first(empty_first(), f), false)
    }
  }
  let mut lo = 0
  let mut hi = 0
  for i, it in items {
    let (first, nullable) = suffixes[i]
    if !nullable && first is Some(f) && !f.non_ascii {
      let n = f.ascii.iter().filter(b => b).count()
      if n >= 1 && n <= MAX_LEAD_UNITS {
        return Some((f.ascii, lo, hi))
      }
    }
    let (a, b) = width(it)
    if b < 0 {
      return None
    }
    lo += a
    hi += b
  }
  None
}

///|
/// A mandatory literal code unit at a bounded offset from the match start:
/// (unit, min offset, max offset). Lets the search jump between occurrences.
fn lead_literal(node : Node) -> (Int, Int, Int)? {
  let items = match node {
    Concat(items) => items
    Group(_, Concat(items)) => items
    _ => return None
  }
  let mut lo = 0
  let mut hi = 0
  for it in items {
    match it {
      Char(cp) if cp < 0x10000 => return Some((cp, lo, hi))
      _ => {
        let (a, b) = width(it)
        if b < 0 {
          return None
        }
        lo += a
        hi += b
      }
    }
  }
  None
}
