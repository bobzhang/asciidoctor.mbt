///|
/// Backtracking matcher state for one search operation over one input.
priv struct Vm {
  prog : FixedArray[Inst]
  classes : FixedArray[CharClass]
  sub_starts : FixedArray[Int]
  input : String
  len : Int
  caps : FixedArray[Int]
  regs : FixedArray[Int]
  stack : Array[Int] // triples: (kind, a, b)
  mut search_start : Int
  // remaining step budget; a step is one branch (Split) or one (sub)program run
  mut fuel : Int
  limit : Int
  mut timed_out : Bool
}

///|
fn Vm::new(re : Regex, input : String) -> Vm {
  let len = input.length()
  let limit = re.step_limit_for(len)
  {
    prog: re.prog,
    classes: re.classes,
    sub_starts: re.sub_starts,
    input,
    len,
    caps: FixedArray::make(2 * (re.ncaps + 1), -1),
    regs: FixedArray::make(re.nregs, -1),
    stack: [],
    search_start: 0,
    fuel: limit,
    limit,
    timed_out: false,
  }
}

///|
const KIND_BRANCH = 0

///|
const KIND_CAP = 1

///|
const KIND_REG = 2

///|
/// Whether `pos` lies between the two code units of a surrogate pair of `s`.
/// Matches never start or end there: Ruby matches on code points.
fn splits_pair(s : String, pos : Int) -> Bool {
  pos > 0 &&
  pos < s.length() &&
  s[pos].to_int() >= 0xDC00 &&
  s[pos].to_int() <= 0xDFFF &&
  s[pos - 1].to_int() >= 0xD800 &&
  s[pos - 1].to_int() <= 0xDBFF
}

///|
/// Decodes the code point at `pos`; returns (cp, width). `pos` must be < len.
fn Vm::cp_at(self : Vm, pos : Int) -> (Int, Int) {
  let c = self.input[pos].to_int()
  if c >= 0xD800 && c <= 0xDBFF && pos + 1 < self.len {
    let d = self.input[pos + 1].to_int()
    if d >= 0xDC00 && d <= 0xDFFF {
      return (0x10000 + ((c - 0xD800) << 10) + (d - 0xDC00), 2)
    }
  }
  (c, 1)
}

///|
/// Decodes the code point ending just before `pos` (pos > 0).
fn Vm::cp_before(self : Vm, pos : Int) -> Int {
  let d = self.input[pos - 1].to_int()
  if d >= 0xDC00 && d <= 0xDFFF && pos >= 2 {
    let c = self.input[pos - 2].to_int()
    if c >= 0xD800 && c <= 0xDBFF {
      return 0x10000 + ((c - 0xD800) << 10) + (d - 0xDC00)
    }
  }
  d
}

///|
fn Vm::check_assert(self : Vm, kind : AssertKind, pos : Int) -> Bool {
  match kind {
    BeginLine => pos == 0 || (self.input[pos - 1] == '\n' && pos < self.len)
    EndLine => pos == self.len || self.input[pos] == '\n'
    BeginText => pos == 0
    EndText => pos == self.len
    EndTextOptNewline =>
      pos == self.len || (pos == self.len - 1 && self.input[pos] == '\n')
    WordBoundary | NotWordBoundary => {
      let before = pos > 0 && is_unicode_word(self.cp_before(pos))
      let after = pos < self.len && is_unicode_word(self.cp_at(pos).0)
      (before != after) == (kind == WordBoundary)
    }
    SearchStart => pos == self.search_start
  }
}

///|
/// Matches the text of capture `[s, e)` at `pos`; returns the end or -1.
fn Vm::backref(self : Vm, s : Int, e : Int, pos : Int, icase : Bool) -> Int {
  let input = self.input
  let len = self.len
  let end = if !icase {
    let l = e - s
    if pos + l > len {
      return -1
    }
    for i in 0..<l {
      if input[s + i] != input[pos + i] {
        return -1
      }
    }
    pos + l
  } else {
    let mut i = s
    let mut j = pos
    while i < e {
      if j >= len {
        return -1
      }
      let (a, wa) = self.cp_at(i)
      let (b, wb) = self.cp_at(j)
      if !fold_eq(a, b) {
        return -1
      }
      i += wa
      j += wb
    }
    j
  }
  // a capture ending in an unpaired lead surrogate must not end mid-pair here
  if splits_pair(input, end) {
    -1
  } else {
    end
  }
}

///|
fn Vm::push(self : Vm, kind : Int, a : Int, b : Int) -> Unit {
  self.stack.push(kind)
  self.stack.push(a)
  self.stack.push(b)
}

///|
/// Runs a nested sub-program atomically. Returns the end position or -1.
/// On success, state changes made by the sub-program are recorded on the
/// outer backtrack stack so they are undone if the outer match backtracks.
fn Vm::run_sub(
  self : Vm,
  sub : Int,
  pos : Int,
  target : Int,
  writes : Bool,
) -> Int {
  if !writes {
    return self.run(self.sub_starts[sub], pos, target)
  }
  let caps_snap = self.caps.copy()
  let regs_snap = self.regs.copy()
  let r = self.run(self.sub_starts[sub], pos, target)
  if r >= 0 {
    for i in 0..<self.caps.length() {
      if self.caps[i] != caps_snap[i] {
        self.push(KIND_CAP, i, caps_snap[i])
      }
    }
    for i in 0..<self.regs.length() {
      if self.regs[i] != regs_snap[i] {
        self.push(KIND_REG, i, regs_snap[i])
      }
    }
  }
  r
}

///|
/// Restores capture/register state to the given snapshot without recording.
fn Vm::restore(
  self : Vm,
  caps_snap : FixedArray[Int],
  regs_snap : FixedArray[Int],
) -> Unit {
  caps_snap.blit_to(self.caps, len=caps_snap.length())
  regs_snap.blit_to(self.regs, len=regs_snap.length())
}

///|
/// Executes the program from `pc0` at `pos0`. Returns the end position of the
/// first successful path, or -1. If `target >= 0`, the program must end exactly
/// at `target` (used for lookbehind).
///
/// Every run and every branch consumes one unit of `fuel`; when it runs out,
/// `timed_out` is set and -1 is returned all the way up. Recursion (for
/// lookaround and atomic groups) is bounded by the syntactic nesting depth,
/// which the parser limits.
fn Vm::run(self : Vm, pc0 : Int, pos0 : Int, target : Int) -> Int {
  self.fuel -= 1
  if self.fuel < 0 {
    self.timed_out = true
    return -1
  }
  let base = self.stack.length()
  let prog = self.prog
  let input = self.input
  let len = self.len
  let mut pc = pc0
  let mut pos = pos0
  while true {
    let mut ok = true
    match prog[pc] {
      Unit(u) =>
        if pos < len && input[pos].to_int() == u {
          pc += 1
          pos += 1
        } else {
          ok = false
        }
      AnyChar(dotall) =>
        if pos < len {
          let (cp, w) = self.cp_at(pos)
          if !dotall && cp == '\n' {
            ok = false
          } else {
            pc += 1
            pos += w
          }
        } else {
          ok = false
        }
      Set(ci) =>
        if pos < len {
          let c = input[pos].to_int()
          if c < 128 {
            if self.classes[ci].ascii[c] {
              pc += 1
              pos += 1
            } else {
              ok = false
            }
          } else {
            let (cp, w) = self.cp_at(pos)
            if self.classes[ci].contains(cp) {
              pc += 1
              pos += w
            } else {
              ok = false
            }
          }
        } else {
          ok = false
        }
      Split(a, b) => {
        self.fuel -= 1
        if self.fuel < 0 {
          self.timed_out = true
          self.stack.truncate(base)
          return -1
        }
        self.push(KIND_BRANCH, b, pos)
        pc = a
      }
      Jmp(a) => pc = a
      Save(slot) => {
        self.push(KIND_CAP, slot, self.caps[slot])
        self.caps[slot] = pos
        pc += 1
      }
      Assert(kind) =>
        if self.check_assert(kind, pos) {
          pc += 1
        } else {
          ok = false
        }
      Backref(n, icase) => {
        let s = if 2 * n + 1 < self.caps.length() {
          self.caps[2 * n]
        } else {
          -1
        }
        let e = if s >= 0 { self.caps[2 * n + 1] } else { -1 }
        if s < 0 || e < 0 {
          ok = false
        } else {
          let r = self.backref(s, e, pos, icase)
          if r < 0 {
            ok = false
          } else {
            pc += 1
            pos = r
          }
        }
      }
      Look(sub, ahead, neg, minw, maxw, writes) => {
        let matched = if ahead {
          if neg && writes {
            let cs = self.caps.copy()
            let rs = self.regs.copy()
            let r = self.run(self.sub_starts[sub], pos, -1)
            self.restore(cs, rs)
            r >= 0
          } else if neg {
            self.run(self.sub_starts[sub], pos, -1) >= 0
          } else {
            self.run_sub(sub, pos, -1, writes) >= 0
          }
        } else {
          let lowest = if maxw < 0 {
            0
          } else if pos - maxw > 0 {
            pos - maxw
          } else {
            0
          }
          let mut found = false
          let mut start = pos - minw
          while start >= lowest && !self.timed_out {
            // candidate starts are code point boundaries only
            if !splits_pair(input, start) {
              let r = if neg {
                let cs = self.caps.copy()
                let rs = self.regs.copy()
                let r = self.run(self.sub_starts[sub], start, pos)
                self.restore(cs, rs)
                r
              } else {
                self.run_sub(sub, start, pos, writes)
              }
              if r >= 0 {
                found = true
                break
              }
            }
            start -= 1
          }
          found
        }
        if self.timed_out {
          self.stack.truncate(base)
          return -1
        }
        if matched != neg {
          pc += 1
        } else {
          ok = false
        }
      }
      Atomic(sub, writes) => {
        let r = self.run_sub(sub, pos, -1, writes)
        if r >= 0 {
          pc += 1
          pos = r
        } else if self.timed_out {
          self.stack.truncate(base)
          return -1
        } else {
          ok = false
        }
      }
      Mark(r) => {
        self.push(KIND_REG, r, self.regs[r])
        self.regs[r] = pos
        pc += 1
      }
      Progress(r) => if pos > self.regs[r] { pc += 1 } else { ok = false }
      SubEnd =>
        if target < 0 || pos == target {
          self.stack.truncate(base)
          return pos
        } else {
          ok = false
        }
    }
    if !ok {
      // backtrack
      let mut resumed = false
      while self.stack.length() > base {
        let n = self.stack.length()
        let b = self.stack[n - 1]
        let a = self.stack[n - 2]
        let kind = self.stack[n - 3]
        self.stack.truncate(n - 3)
        if kind == KIND_BRANCH {
          pc = a
          pos = b
          resumed = true
          break
        } else if kind == KIND_CAP {
          self.caps[a] = b
        } else {
          self.regs[a] = b
        }
      }
      if !resumed {
        return -1
      }
    }
  }
  -1
}
