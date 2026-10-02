///|
/// Builds a lexer from its options.
pub type LexerFactory = (Map[String, String]) -> Lexer

///|
/// The ported lexers: tag, aliases and factory (Rouge's `Lexer.register`
/// through `tag` and `aliases`), in groups (lexers_*.mbt); where two
/// register the same name, the later wins. A function, not a `let`, and so
/// is a group whose lexers look others up (`find`, as `lexer_option`
/// does): a `let` would be a definition cycle.
fn lexer_list() -> Array[(String, Array[String], LexerFactory)] {
  [..core_lexers, ..web_lexers(), ..c_lexers, ..shell_lexers, ..script_lexers]
}

///|
/// The first lexers ported.
let core_lexers : Array[(String, Array[String], LexerFactory)] = [
  ("plaintext", ["text"], plain_text),
  ("diff", ["patch", "udiff"], diff),
  ("java", [], java),
  ("xml", [], xml),
  ("ruby", ["rb"], ruby),
]

///|
let registry_cache : Map[String, LexerFactory] = Map([])

///|
/// The ported lexers by tag and alias, built on first use.
fn registry() -> Map[String, LexerFactory] {
  if registry_cache.is_empty() {
    for entry in lexer_list() {
      registry_cache[entry.0] = entry.2
      for alias_ in entry.1 {
        registry_cache[alias_] = entry.2
      }
    }
  }
  registry_cache
}

///|
/// The lexer registered as `name` (Rouge's `Lexer.find`), by tag or alias.
pub fn find(name : String) -> LexerFactory? {
  registry().get(name)
}

///|
/// `find`, for lexers that look lexers up by name: the registry lists
/// them, so calling `find` from them directly would be a definition cycle;
/// it is set at initialization.
let find_lexer : Ref[(String) -> LexerFactory?] = Ref(fn(_) { None })

///|
fn init {
  find_lexer.val = find
}

///|
/// Rouge's `lexer_option` on a lexer name: the option removed from the
/// options, and the lexer it names built with the remaining options (None
/// when the option is unset or names no ported lexer).
pub fn Lexer::lexer_option(self : Lexer, name : String) -> Lexer? {
  match self.options.get(name) {
    Some(v) => {
      self.options.remove(name)
      self.options.remove(all_values_key(name))
      (find_lexer.val)(v).map(f => f(self.options.copy()))
    }
    None => None
  }
}

///|
/// The tags of the ported lexers.
pub fn lexer_tags() -> Array[String] {
  lexer_list().map(e => e.0)
}

///|
/// Rouge's `CGI.unescape`: `+` is a space, `%XX` a byte (UTF-8).
fn cgi_unescape(s : String) -> String {
  if !s.contains("+") && !s.contains("%") {
    return s
  }
  let bytes = Buffer()
  let n = s.length()
  let mut i = 0
  while i < n {
    let c = s.unsafe_get(i).to_int()
    if c == '+'.to_int() {
      bytes.write_byte(b' ')
      i += 1
    } else if c == '%'.to_int() &&
      i + 2 < n + 0 &&
      hex_value(s.unsafe_get(i + 1).to_int()) >= 0 &&
      hex_value(s.unsafe_get(i + 2).to_int()) >= 0 {
      bytes.write_byte(
        (hex_value(s.unsafe_get(i + 1).to_int()) * 16 +
        hex_value(s.unsafe_get(i + 2).to_int())).to_byte(),
      )
      i += 3
    } else {
      bytes.write_string_utf8(s.unsafe_substring(start=i, end=i + 1))
      i += 1
    }
  }
  @utf8.decode_lossy(bytes.contents())
}

///|
fn hex_value(c : Int) -> Int {
  if c >= '0'.to_int() && c <= '9'.to_int() {
    c - '0'.to_int()
  } else if c >= 'a'.to_int() && c <= 'f'.to_int() {
    c - 'a'.to_int() + 10
  } else if c >= 'A'.to_int() && c <= 'F'.to_int() {
    c - 'A'.to_int() + 10
  } else {
    -1
  }
}

///|
/// Rouge's `Lexer.lookup_fancy` on a language with cgi-style options
/// (`php?start_inline=1`): the lexer (None when unknown) and its options.
/// An option without a value is true (the empty string here); of several
/// values the last counts. Guessing (`guess`, or no name) is not
/// supported and finds no lexer.
pub fn lookup_fancy(spec : String) -> (LexerFactory?, Map[String, String]) {
  let options : Map[String, String] = Map([])
  guard spec.find("?") is Some(q) else { return (find(spec), options) }
  // every value of each option, in order (an option without one is true)
  let values : Map[String, Array[String]] = Map([])
  let name = spec.unsafe_substring(start=0, end=q)
  let query = spec.unsafe_substring(start=q + 1, end=spec.length())
  for pair in query.split("&") {
    for pair in pair.split(";") {
      let pair = pair.to_owned()
      let (key, value) = match pair.find("=") {
        Some(i) =>
          (
            cgi_unescape(pair.unsafe_substring(start=0, end=i)),
            Some(
              cgi_unescape(
                pair.unsafe_substring(start=i + 1, end=pair.length()),
              ),
            ),
          )
        None => (cgi_unescape(pair), None)
      }
      if key == "" && value is None {
        continue
      }
      match values.get(key) {
        Some(vs) => if value is Some(v) { vs.push(v) }
        None => values[key] = if value is Some(v) { [v] } else { [] }
      }
    }
  }
  for key, vs in values {
    // a scalar reader takes the last value; a list reader takes them all
    options[key] = vs.last().unwrap_or("")
    if vs.length() > 1 {
      options[all_values_key(key)] = vs.join("\u{0}")
    }
  }
  (if name == "guess" { None } else { find(name) }, options)
}

///|
/// Rouge's `Lexer.find_fancy`: the lexer of a language with cgi-style
/// options, built with them.
pub fn find_fancy(spec : String) -> Lexer? {
  let (factory, options) = lookup_fancy(spec)
  factory.map(f => f(options))
}

///|
/// Rouge's `as_bool` on an option value: false for `0`, `false` and
/// `off`.
pub fn option_bool(value : String) -> Bool {
  !(value == "0" || value == "false" || value == "off")
}

///|
/// Rouge's `bool_option`: the option as a boolean, `default` when unset.
pub fn Lexer::bool_option(self : Lexer, name : String, default : Bool) -> Bool {
  match self.options.get(name) {
    Some(v) => option_bool(v)
    None => default
  }
}

///|
/// Rouge's `list_option`: the option split at commas, removed from the
/// options.
pub fn Lexer::list_option(self : Lexer, name : String) -> Array[String]? {
  match self.options.get(name) {
    Some(v) => {
      self.options.remove(name)
      let all = match self.options.get(all_values_key(name)) {
        Some(joined) => {
          self.options.remove(all_values_key(name))
          joined.split("\u{0}").map(s => s.to_owned()).collect()
        }
        None => [v]
      }
      Some(all.map(ruby_split_comma).flatten())
    }
    None => None
  }
}

///|
/// Where `lookup_fancy` keeps all the values of an option given more than
/// once (Rouge keeps them as an Array), NUL-separated; the option itself
/// holds the last.
fn all_values_key(name : String) -> String {
  "\u{1}all:" + name
}

///|
/// Ruby's `String#split(',')`: trailing empty fields dropped.
fn ruby_split_comma(s : String) -> Array[String] {
  let fields = s.split(",").map(f => f.to_owned()).collect()
  while fields.last() is Some("") {
    ignore(fields.pop())
  }
  fields
}

///|
/// Rouge's `string_option`: the option, removed from the options.
pub fn Lexer::string_option(self : Lexer, name : String) -> String? {
  match self.options.get(name) {
    Some(v) => {
      self.options.remove(name)
      self.options.remove(all_values_key(name))
      Some(v)
    }
    None => None
  }
}
