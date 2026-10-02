///|
// A port of Rouge 3.30's lexer core (lib/rouge/lexer.rb and
// regex_lexer.rb): stateful regex lexers that turn source text into
// `(token, text)` pairs, token for token as Rouge does.
//
// A Rouge lexer class becomes a function that builds a `Lexer`: its states
// are defined with `Lexer::state` and `StateBuilder` (Rouge's `state`,
// `rule`, `mixin`), its `start` blocks with `Lexer::start`, and the Ruby
// blocks of its rules become callbacks that receive the lexer and the match
// and use `token`, `groups`, `push`, `pop`, `goto`, `delegate`... as the
// blocks do. Instance variables of the Ruby lexer are variables the
// building function captures.
//
// Rules are matched as Ruby's StringScanner does without `fixed_anchor`:
// against the rest of the input as if it were the whole string, so `\A`,
// `\b` and lookbehind do not see what precedes the scan position, and a
// rule whose pattern starts with `^` is only tried at the beginning of a
// line (Rouge's workaround).

///|
/// What a rule does when its pattern matches.
priv enum Action {
  /// yield the match as a token
  Emit(String)
  /// yield the match, then push the named state (`#push`: the current
  /// state again, `#pop`: pop the stack instead)
  EmitThen(String, String)
  /// run a block
  Call((Lexer, @regex.MatchData) -> Unit)
}

///|
/// A rule of a state: a pattern and its action, or the rules of another
/// state mixed in (by name, resolved when the rule is tried).
priv enum Rule {
  Match(@regex.Regex, Bool, Action)
  Mixin(String)
}

///|
/// A named set of rules (Rouge's `RegexLexer::State`).
struct State {
  name : String
  rules : Array[Rule]
}

///|
/// Rules being defined for a state (Rouge's `StateDSL`).
pub struct StateBuilder {
  priv rules : Array[Rule]
}

///|
/// A lexer: Rouge's `Lexer` instance, a `RegexLexer` unless it was built
/// with a custom `stream` function (as `PlainText` and `ConsoleLexer` are).
pub struct Lexer {
  /// the lexer's tag (`ruby`, `java`...)
  tag : String
  /// the options given (Rouge's `@options`, string keys); `list_option`
  /// and the other `*_option` readers that delete remove theirs
  options : Map[String, String]
  priv states : Map[String, State]
  priv starts : Array[(Lexer) -> Unit]
  priv mut stack : Array[State]
  /// the current match (Rouge's `@current_stream`)
  priv mut current : @regex.MatchData?
  /// where tokens go (Rouge's `@output_stream`)
  priv mut output : (String, String) -> Unit
  priv mut null_steps : Int
  priv mut custom : ((Lexer, String, (String, String) -> Unit) -> Unit)?
  /// builds a fresh lexer of the same kind with no options (`self.class`)
  priv mut fresh : (() -> Lexer)?
}

///|
/// The number of successive scans permitted without consuming input.
const MAX_NULL_SCANS = 5

///|
let regex_cache : Map[String, @regex.Regex] = Map([])

///|
/// Compile a Ruby regex (`flags` among `i`, `m`, `x`), once per pattern.
/// Unicode properties the regex engine lacks are expanded first (see
/// `expand_properties`). A pattern that does not compile is a porting
/// error.
fn compile(pattern : String, flags : String) -> @regex.Regex {
  let key = flags + "/" + pattern
  match regex_cache.get(key) {
    Some(re) => re
    None => {
      let re = @regex.compile(expand_properties(pattern), flags~) catch {
        _ => abort("rouge: cannot compile /\{pattern}/\{flags}")
      }
      regex_cache[key] = re
      re
    }
  }
}

///|
pub fn Lexer::new(
  tag : String,
  options? : Map[String, String] = Map([]),
) -> Lexer {
  {
    tag,
    options,
    states: Map([]),
    starts: [],
    stack: [],
    current: None,
    output: fn(_, _) {  },
    null_steps: 0,
    custom: None,
    fresh: None,
  }
}

///|
/// Define the state `name` (Rouge's `state :name do ... end`).
pub fn Lexer::state(
  self : Lexer,
  name : String,
  defn : (StateBuilder) -> Unit,
) -> Unit {
  let b = { rules: [], }
  defn(b)
  self.states[name] = { name, rules: b.rules, }
}

///|
/// Add rules in front of the state `name` (Rouge's `prepend`).
pub fn Lexer::prepend(
  self : Lexer,
  name : String,
  defn : (StateBuilder) -> Unit,
) -> Unit {
  let b = { rules: [], }
  defn(b)
  match self.states.get(name) {
    Some(state) =>
      self.states[name] = { name, rules: [..b.rules, ..state.rules], }
    None => abort("rouge: no such state \{name}")
  }
}

///|
/// Add rules after the ones of the state `name` (Rouge's `append`).
pub fn Lexer::append(
  self : Lexer,
  name : String,
  defn : (StateBuilder) -> Unit,
) -> Unit {
  let b = { rules: [], }
  defn(b)
  match self.states.get(name) {
    Some(state) =>
      self.states[name] = { name, rules: [..state.rules, ..b.rules], }
    None => abort("rouge: no such state \{name}")
  }
}

///|
/// Run `f` at the start of every fresh lex (Rouge's `start do ... end`).
pub fn Lexer::start(self : Lexer, f : (Lexer) -> Unit) -> Unit {
  self.starts.push(f)
}

///|
/// Make this a lexer that streams its tokens itself (a Rouge `Lexer` that
/// is not a `RegexLexer`).
pub fn Lexer::set_stream(
  self : Lexer,
  f : (Lexer, String, (String, String) -> Unit) -> Unit,
) -> Unit {
  self.custom = Some(f)
}

///|
/// How `recurse` and `delegate_new(self)` build a fresh lexer of this kind.
pub fn Lexer::set_fresh(self : Lexer, f : () -> Lexer) -> Unit {
  self.fresh = Some(f)
}

///|
/// `rule re, tok` / `rule re, tok, :next_state` (`next` is a state name,
/// `#push` or `#pop`).
pub fn StateBuilder::rule(
  self : StateBuilder,
  pattern : String,
  tok : String,
  flags? : String = "",
  next? : String,
) -> Unit {
  let action = match next {
    Some(state) => EmitThen(tok, state)
    None => Emit(tok)
  }
  self.rules.push(
    Match(compile(pattern, flags), pattern.has_prefix("^"), action),
  )
}

///|
/// `rule re do |m| ... end`.
pub fn StateBuilder::call(
  self : StateBuilder,
  pattern : String,
  f : (Lexer, @regex.MatchData) -> Unit,
  flags? : String = "",
) -> Unit {
  self.rules.push(
    Match(compile(pattern, flags), pattern.has_prefix("^"), Call(f)),
  )
}

///|
/// `mixin :name`.
pub fn StateBuilder::mix_in(self : StateBuilder, name : String) -> Unit {
  self.rules.push(Mixin(name))
}

///|
fn Lexer::get_state(self : Lexer, name : String) -> State {
  match self.states.get(name) {
    Some(state) => state
    None => abort("rouge: \{self.tag}: unknown state \{name}")
  }
}

///|
/// Reset the lexer for a fresh lex (Rouge's `reset!`): the stack back to
/// `[:root]`, then the start blocks.
pub fn Lexer::reset(self : Lexer) -> Unit {
  self.stack = []
  self.current = None
  for f in self.starts {
    f(self)
  }
}

///|
fn Lexer::ensure_stack(self : Lexer) -> Unit {
  if self.stack.is_empty() && self.custom is None {
    self.stack.push(self.get_state("root"))
  }
}

///|
/// Lex `text` from a fresh state (Rouge's `Lexer#lex`): consecutive tokens
/// of the same type are merged, empty ones dropped.
pub fn Lexer::lex(
  self : Lexer,
  text : String,
  emit : (String, String) -> Unit,
) -> Unit {
  self.reset()
  self.continue_lex(text, emit)
}

///|
/// Lex `text` and collect the tokens.
pub fn Lexer::tokens(self : Lexer, text : String) -> Array[(String, String)] {
  let out = []
  self.lex(text, fn(tok, val) { out.push((tok, val)) })
  out
}

///|
/// Lex `text` in the current state (Rouge's `continue_lex`).
pub fn Lexer::continue_lex(
  self : Lexer,
  text : String,
  emit : (String, String) -> Unit,
) -> Unit {
  let mut last_tok : String? = None
  let last_val = StringBuilder()
  self.stream_tokens(text, fn(tok, val) {
    if val == "" {
      return
    }
    match last_tok {
      Some(t) if t == tok => {
        last_val.write_string(val)
        return
      }
      Some(t) => emit(t, last_val.to_string())
      None => ()
    }
    last_tok = Some(tok)
    last_val.reset()
    last_val.write_string(val)
  })
  if last_tok is Some(t) {
    emit(t, last_val.to_string())
  }
}

///|
/// Rouge's `stream_tokens`: step through `text`, one rule match at a time;
/// where no rule matches, one character is an `Error` token.
fn Lexer::stream_tokens(
  self : Lexer,
  text : String,
  emit : (String, String) -> Unit,
) -> Unit {
  if self.custom is Some(f) {
    f(self, text, emit)
    return
  }
  self.ensure_stack()
  self.output = emit
  self.null_steps = 0
  let mut pos = 0
  let len = text.length()
  while pos < len {
    let rest = text.unsafe_substring(start=pos, end=len)
    let bol = pos == 0 || text.unsafe_get(pos - 1) == '\n'
    match self.step(self.top_state(), rest, bol) {
      Some(size) => pos += size
      None => {
        let size = if text.unsafe_get(pos).is_leading_surrogate() &&
          pos + 1 < len {
          2
        } else {
          1
        }
        emit("Error", text.unsafe_substring(start=pos, end=pos + size))
        pos += size
      }
    }
  }
}

///|
/// The state on top of the stack.
fn Lexer::top_state(self : Lexer) -> State {
  match self.stack.last() {
    Some(state) => state
    None => abort("rouge: \{self.tag}: empty stack!")
  }
}

///|
/// Rouge's `step`: try the rules of `state` in order at the start of
/// `rest`; the number of characters consumed by the first that matches.
fn Lexer::step(self : Lexer, state : State, rest : String, bol : Bool) -> Int? {
  for rule in state.rules {
    match rule {
      Mixin(name) =>
        match self.step(self.get_state(name), rest, bol) {
          Some(size) => return Some(size)
          None => ()
        }
      Match(re, at_bol, action) => {
        if at_bol && !bol {
          continue
        }
        let m = re.try_match_at(rest, 0) catch { _ => None }
        guard m is Some(m) else { continue }
        self.current = Some(m)
        let size = m.end()
        match action {
          Emit(tok) => (self.output)(tok, m.matched())
          EmitThen(tok, next) => {
            (self.output)(tok, m.matched())
            match next {
              "#pop" => ignore(self.stack.pop())
              "#push" => self.stack.push(self.top_state())
              name => self.stack.push(self.get_state(name))
            }
          }
          Call(f) => f(self, m)
        }
        if size == 0 {
          self.null_steps += 1
          if self.null_steps > MAX_NULL_SCANS {
            return None
          }
        } else {
          self.null_steps = 0
        }
        return Some(size)
      }
    }
  }
  None
}

///|
/// Yield a token (Rouge's `token`): `val`, else the whole current match.
pub fn Lexer::token(self : Lexer, tok : String, val? : String) -> Unit {
  let val = match val {
    Some(v) => v
    None =>
      match self.current {
        Some(m) => m.matched()
        None => ""
      }
  }
  if val != "" {
    (self.output)(tok, val)
  }
}

///|
/// Yield the groups of the current match as `toks` (Rouge's `groups`);
/// groups that did not participate yield nothing.
pub fn Lexer::groups(self : Lexer, toks : Array[String]) -> Unit {
  guard self.current is Some(m) else { return }
  for i, tok in toks {
    match m.group(i + 1) {
      Some(v) if v != "" => (self.output)(tok, v)
      _ => ()
    }
  }
}

///|
/// Delegate `text` (default: the current match) to `lexer` in its current
/// state (Rouge's `delegate` with a lexer instance).
pub fn Lexer::delegate(self : Lexer, lexer : Lexer, text? : String) -> Unit {
  let text = match text {
    Some(t) => t
    None =>
      match self.current {
        Some(m) => m.matched()
        None => ""
      }
  }
  let out = self.output
  lexer.continue_lex(text, fn(tok, val) { if val != "" { out(tok, val) } })
}

///|
/// Delegate to a fresh lexer (Rouge's `delegate` with a lexer class: the
/// class lexes `text` from scratch).
pub fn Lexer::delegate_new(
  self : Lexer,
  make : () -> Lexer,
  text? : String,
) -> Unit {
  let lexer = make()
  lexer.reset()
  self.delegate(lexer, text?)
}

///|
/// Lex `text` with a fresh lexer of this kind (Rouge's `recurse`).
pub fn Lexer::recurse(self : Lexer, text? : String) -> Unit {
  match self.fresh {
    Some(make) => self.delegate_new(make, text?)
    None => abort("rouge: \{self.tag}: recurse without set_fresh")
  }
}

///|
/// Push the state `name` (Rouge's `push :name`).
pub fn Lexer::push(self : Lexer, name : String) -> Unit {
  self.ensure_stack()
  self.stack.push(self.get_state(name))
}

///|
/// Push the current state again (Rouge's bare `push`).
pub fn Lexer::push_self(self : Lexer) -> Unit {
  self.ensure_stack()
  self.stack.push(self.top_state())
}

///|
/// Push an anonymous state (Rouge's `push do ... end`).
pub fn Lexer::push_rules(self : Lexer, defn : (StateBuilder) -> Unit) -> Unit {
  self.ensure_stack()
  let b = { rules: [], }
  defn(b)
  self.stack.push({ name: "#anonymous", rules: b.rules, })
}

///|
/// Pop `times` states (Rouge's `pop!`).
pub fn Lexer::pop(self : Lexer, times? : Int = 1) -> Unit {
  if self.stack.is_empty() {
    abort("rouge: \{self.tag}: empty stack!")
  }
  for _ in 0..<times {
    ignore(self.stack.pop())
  }
}

///|
/// Replace the top of the stack with `name` (Rouge's `goto`).
pub fn Lexer::goto(self : Lexer, name : String) -> Unit {
  if self.stack.is_empty() {
    abort("rouge: \{self.tag}: empty stack!")
  }
  self.stack[self.stack.length() - 1] = self.get_state(name)
}

///|
/// Back to `[:root]` (Rouge's `reset_stack`).
pub fn Lexer::reset_stack(self : Lexer) -> Unit {
  self.stack = [self.get_state("root")]
}

///|
/// Whether `name` is on the stack (Rouge's `in_state?`).
pub fn Lexer::in_state(self : Lexer, name : String) -> Bool {
  self.ensure_stack()
  self.stack.iter().any(s => s.name == name)
}

///|
/// Whether `name` is on top of the stack (Rouge's `state?`).
pub fn Lexer::state_is(self : Lexer, name : String) -> Bool {
  self.ensure_stack()
  self.stack.last() is Some(s) && s.name == name
}

///|
/// The depth of the state stack.
pub fn Lexer::stack_size(self : Lexer) -> Int {
  self.stack.length()
}

///|
/// The text of group `i` of `m`, empty when it did not participate (where
/// Ruby code tests `m[i]` for nil, use `MatchData::group`).
pub fn group_text(m : @regex.MatchData, i : Int) -> String {
  m.group(i).unwrap_or("")
}
