///|
// Helpers of the scripting languages group (lexers_script.mbt).

///|
/// Ruby's `String#downcase` as far as a lookup in sets of ASCII words can
/// tell: ASCII capitals and the Kelvin sign (the one non-ASCII character
/// that lowercases to an ASCII one) are lowered; other characters are kept,
/// as their lowercase is not ASCII either.
fn script_downcase(s : String) -> String {
  let sb = StringBuilder()
  for c in s {
    if c >= 'A' && c <= 'Z' {
      sb.write_char((c.to_int() + 32).unsafe_to_char())
    } else if c == '\u{212A}' {
      sb.write_char('k')
    } else {
      sb.write_char(c)
    }
  }
  sb.to_string()
}

///|
/// Whether the Ruby regex `pattern` matches somewhere in `s` (`s =~ re`).
fn script_match(pattern : String, s : String, flags? : String = "") -> Bool {
  compile(pattern, flags).find(s) is Some(_)
}

///|
/// `find` and `lookup_fancy`, for the lexers that look up others: the lexer
/// list holds these lexers, so calling those directly would make its
/// definition cyclic; set by `init`.
let script_registry : Ref[
  ((String) -> LexerFactory?, (String) -> (LexerFactory?, Map[String, String])),
] = { val: (fn(_) { None }, fn(_) { (None, Map([])) }), }

///|
fn init {
  script_registry.val = (find, lookup_fancy)
}

///|
/// Rouge's `Lexer.find` (see `script_registry`).
fn script_find(name : String) -> LexerFactory? {
  (script_registry.val.0)(name)
}

///|
/// A lexer of `tag` with `options` when one is ported, else plain text (for
/// the lexers this group delegates to that other groups port).
fn script_lexer_or_text(tag : String, options : Map[String, String]) -> Lexer {
  match script_find(tag) {
    Some(f) => f(options)
    None => plain_text(Map([]))
  }
}

///|
/// Rouge's `Lexer.find_fancy(spec, code, default_options)`: the lexer of a
/// language with cgi-style options, built with `defaults` and the options of
/// `spec` (an option of `spec` replaces all the values `defaults` has for
/// it); None when the language is unknown. `guess` guesses from `code`
/// (`guess`; an ambiguous guess takes the first lexer, as Markdown does,
/// and a guessed lexer that is not ported is plain text).
fn script_find_fancy(
  spec : String,
  code : String?,
  defaults : Map[String, String],
) -> Lexer? {
  let options = defaults.copy()
  if !spec.contains("?") && spec != "guess" {
    return script_find(spec).map(f => f(options))
  }
  let (factory, opts) = (script_registry.val.1)(spec)
  for k, _ in opts {
    options.remove(all_values_key(k))
  }
  for k, v in opts {
    options[k] = v
  }
  let name = match spec.find("?") {
    Some(i) => spec.unsafe_substring(start=0, end=i)
    None => spec
  }
  match factory {
    Some(f) => Some(f(options))
    None if name == "guess" =>
      Some(
        match guess(code, mimetype?=options.get("mimetype")).get(0) {
          Some(tag) =>
            match script_find(tag) {
              Some(f) => f(options)
              None => plain_text(options)
            }
          None => plain_text(options)
        },
      )
    None => None
  }
}
