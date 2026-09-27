///|
/// Backtracking matcher state for one search operation over one input.
///
/// A `Vm` is reusable: `Regex::acquire` takes one from the regex's pool (or
/// allocates one) and resets it for a new operation, `Regex::release` returns
/// it. Every observable piece of state is reset, so a reused matcher behaves
/// exactly like a fresh one.
priv struct Vm {
  prog : FixedArray[Inst]
  classes : FixedArray[CharClass]
  sub_starts : FixedArray[Int]
  mut input : String
  mut len : Int
  caps : FixedArray[Int]
  regs : FixedArray[Int]
  // backtrack stack of triples (kind, a, b); `sp` is its logical length
  mut stack : FixedArray[Int]
  mut sp : Int
  mut search_start : Int
  // remaining step budget; a step is one branch (Split) or one (sub)program run
  mut fuel : Int
  mut limit : Int
  mut timed_out : Bool
  // memo of the required-unit prefilter: the scan for `required[i]` that
  // started at `req_from[i]` (-1: none yet) found it at `req_at[i]` (len: absent)
  req_from : FixedArray[Int]
  req_at : FixedArray[Int]
}

///|
/// Initial capacity of the backtrack stack (in ints, i.e. 3 per entry).
const STACK_INIT = 96

///|
/// Largest backtrack stack a pooled matcher keeps between operations (4096 entries).
const STACK_RETAIN = 12288

///|
fn Vm::new(re : Regex) -> Vm {
  let nreq = re.required.length()
  {
    prog: re.prog,
    classes: re.classes,
    sub_starts: re.sub_starts,
    input: "",
    len: 0,
    caps: FixedArray::make(2 * (re.ncaps + 1), -1),
    regs: FixedArray::make(re.nregs, -1),
    stack: FixedArray::make(STACK_INIT, 0),
    sp: 0,
    search_start: 0,
    fuel: 0,
    limit: 0,
    timed_out: false,
    req_from: FixedArray::make(nreq, -1),
    req_at: FixedArray::make(nreq, 0),
  }
}

///|
/// Prepares the matcher for a new search operation over `input`, leaving it in
/// the same state as a freshly allocated one.
fn Vm::reset(self : Vm, re : Regex, input : String) -> Unit {
  let len = input.length()
  let limit = re.step_limit_for(len)
  self.input = input
  self.len = len
  self.caps.fill(-1)
  self.regs.fill(-1)
  self.sp = 0
  self.search_start = 0
  self.fuel = limit
  self.limit = limit
  self.timed_out = false
  self.req_from.fill(-1)
}

///|
/// Takes a matcher for one search operation over `input`. Matchers are pooled
/// per regex; a nested operation on the same regex (e.g. from a `replace`
/// callback) simply takes another one.
fn Regex::acquire(self : Regex, input : String) -> Vm {
  let vm = match self.pool.pop() {
    Some(vm) => vm
    None => Vm::new(self)
  }
  vm.reset(self, input)
  vm
}

///|
/// Maximum number of idle matchers kept per regex.
const POOL_MAX = 4

///|
/// Returns a matcher to the pool once its operation is over.
fn Regex::release(self : Regex, vm : Vm) -> Unit {
  // do not keep the input (possibly a whole document) or a huge stack alive
  vm.input = ""
  if vm.stack.length() > STACK_RETAIN {
    vm.stack = FixedArray::make(STACK_INIT, 0)
  }
  if self.pool.length() < POOL_MAX {
    self.pool.push(vm)
  }
}

///|
const KIND_BRANCH = 0

///|
const KIND_CAP = 1

///|
const KIND_REG = 2

///|
/// `KIND_LOOP + 2 * pc` (greedy) and `KIND_LOOP + 2 * pc + 1` (lazy) mark the
/// pending iterations of the `Star` loop at `pc`.
const KIND_LOOP = 3

///|
/// Whether `s[i]`, `s[i + 1]` form a surrogate pair (both indices in range).
fn is_pair(s : String, i : Int) -> Bool {
  let c = s.unsafe_get(i).to_int()
  let d = s.unsafe_get(i + 1).to_int()
  c >= 0xD800 && c <= 0xDBFF && d >= 0xDC00 && d <= 0xDFFF
}

///|
/// Runs the one-character instruction `inst` (the body of a `Star` loop) at
/// `pos`; returns the position after the character, or -1.
fn Vm::step1(self : Vm, inst : Inst, pos : Int) -> Int {
  if pos >= self.len {
    return -1
  }
  match inst {
    Unit(u) =>
      if self.input.unsafe_get(pos).to_int() == u {
        pos + 1
      } else {
        -1
      }
    AnyChar(dotall) => {
      let cp = self.cp_at(pos)
      let w = cp_width_of(cp)
      if !dotall && cp == '\n' {
        -1
      } else {
        pos + w
      }
    }
    Set(ci) => {
      let c = self.input.unsafe_get(pos).to_int()
      if c < 128 {
        if self.classes[ci].ascii[c] {
          pos + 1
        } else {
          -1
        }
      } else {
        let cp = self.cp_at(pos)
        let w = cp_width_of(cp)
        if self.classes[ci].contains(cp) {
          pos + w
        } else {
          -1
        }
      }
    }
    _ => abort("Star body is not a one-character instruction")
  }
}

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
/// Decodes the code point at `pos` (`pos` must be < len). Its width in code
/// units is `cp_width_of(cp)`: only a surrogate pair decodes above U+FFFF.
/// (Returns a plain Int: a tuple would be heap-allocated on every call.)
fn Vm::cp_at(self : Vm, pos : Int) -> Int {
  let c = self.input.unsafe_get(pos).to_int()
  if c >= 0xD800 && c <= 0xDBFF && pos + 1 < self.len {
    let d = self.input.unsafe_get(pos + 1).to_int()
    if d >= 0xDC00 && d <= 0xDFFF {
      return 0x10000 + ((c - 0xD800) << 10) + (d - 0xDC00)
    }
  }
  c
}

///|
/// Width in UTF-16 code units of a code point decoded by `cp_at`.
fn cp_width_of(cp : Int) -> Int {
  if cp >= 0x10000 {
    2
  } else {
    1
  }
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
      let after = pos < self.len && is_unicode_word(self.cp_at(pos))
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
      let a = self.cp_at(i)
      let wa = cp_width_of(a)
      let b = self.cp_at(j)
      let wb = cp_width_of(b)
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
  let sp = self.sp
  if sp + 3 > self.stack.length() {
    let bigger = FixedArray::make(2 * self.stack.length(), 0)
    self.stack.blit_to(bigger, len=sp)
    self.stack = bigger
  }
  let stack = self.stack
  stack.unsafe_set(sp, kind)
  stack.unsafe_set(sp + 1, a)
  stack.unsafe_set(sp + 2, b)
  self.sp = sp + 3
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
  let base = self.sp
  let prog = self.prog
  let input = self.input
  let len = self.len
  let mut pc = pc0
  let mut pos = pos0
  while true {
    let mut ok = true
    match prog.unsafe_get(pc) {
      Unit(u) =>
        if pos < len && input.unsafe_get(pos).to_int() == u {
          pc += 1
          pos += 1
        } else {
          ok = false
        }
      AnyChar(dotall) =>
        if pos < len {
          let cp = self.cp_at(pos)
          let w = cp_width_of(cp)
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
          let c = input.unsafe_get(pos).to_int()
          if c < 128 {
            if self.classes[ci].ascii[c] {
              pc += 1
              pos += 1
            } else {
              ok = false
            }
          } else {
            let cp = self.cp_at(pos)
            let w = cp_width_of(cp)
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
          self.sp = base
          return -1
        }
        self.push(KIND_BRANCH, b, pos)
        pc = a
      }
      Star(greedy) =>
        if greedy {
          // `Split(pc + 1, pc + 3)` per iteration: one step each, the last
          // one after the body has failed
          let inst = prog.unsafe_get(pc + 1)
          let mut p = pos
          while true {
            self.fuel -= 1
            if self.fuel < 0 {
              self.timed_out = true
              self.sp = base
              return -1
            }
            let q = self.step1(inst, p)
            if q < 0 {
              break
            }
            p = q
          }
          // the pending alternatives: every earlier iteration boundary
          if p > pos {
            self.push(KIND_LOOP + 2 * pc, pos, p)
          }
          pc += 3
          pos = p
        } else {
          self.fuel -= 1
          if self.fuel < 0 {
            self.timed_out = true
            self.sp = base
            return -1
          }
          self.push(KIND_LOOP + 2 * pc + 1, 0, pos)
          pc += 3
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
          self.sp = base
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
          self.sp = base
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
          self.sp = base
          return pos
        } else {
          ok = false
        }
    }
    if !ok {
      // backtrack
      let mut resumed = false
      let stack = self.stack
      while self.sp > base {
        let n = self.sp - 3
        let kind = stack.unsafe_get(n)
        let a = stack.unsafe_get(n + 1)
        let b = stack.unsafe_get(n + 2)
        self.sp = n
        if kind == KIND_BRANCH {
          pc = a
          pos = b
          resumed = true
          break
        } else if kind == KIND_CAP {
          self.caps[a] = b
        } else if kind == KIND_REG {
          self.regs[a] = b
        } else if (kind - KIND_LOOP) % 2 == 0 {
          // greedy `Star` loop that started at `a` and now ends at `b`:
          // resume after the loop one character earlier
          let star = (kind - KIND_LOOP) / 2
          let prev = if b - 2 >= a && is_pair(input, b - 2) {
            b - 2
          } else {
            b - 1
          }
          if prev > a {
            stack.unsafe_set(n + 2, prev)
            self.sp = n + 3
          }
          pc = star + 3
          pos = prev
          resumed = true
          break
        } else {
          // lazy `Star` loop, now at `b`: one more iteration, then resume
          // after the loop
          let star = (kind - KIND_LOOP) / 2
          let q = self.step1(prog.unsafe_get(star + 1), b)
          if q >= 0 {
            self.fuel -= 1
            if self.fuel < 0 {
              self.timed_out = true
              self.sp = base
              return -1
            }
            stack.unsafe_set(n + 2, q)
            self.sp = n + 3
            pc = star + 3
            pos = q
            resumed = true
            break
          }
        }
      }
      if !resumed {
        return -1
      }
    }
  }
  -1
}
