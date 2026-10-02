///|
// Pygments for `source-highlighter: pygments` in PDF output: registers
// bobzhang/pygments (a port of Pygments 2.21) as the converter's
// PygmentsBackend, standing in for pygments.rb. Kept out of the converter
// so that only programs that want Pygments link its lexers.

///|
/// Lexers by alias (pygments.rb's `Lexer.find_by_alias`: exact,
/// case-sensitive; a later lexer wins), as (name, first alias).
let alias_index : Map[String, (String, String)] = Map([])

///|
fn find_lexer(alias_ : String) -> (String, String)? {
  if alias_index.is_empty() {
    for entry in @py_lexers.all_lexers {
      let info = entry.0
      if info.aliases.is_empty() {
        continue
      }
      for a in info.aliases {
        alias_index[a] = (info.name, info.aliases[0])
      }
    }
  }
  alias_index.get(alias_)
}

///|
/// pygments.rb's `Lexer.find_by_mimetype` (a later lexer wins).
fn find_lexer_by_mimetype(mimetype : String) -> (String, String)? {
  let mut found = None
  for entry in @py_lexers.all_lexers {
    let info = entry.0
    if info.mimetypes.contains(mimetype) && !info.aliases.is_empty() {
      found = Some((info.name, info.aliases[0]))
    }
  }
  found
}

///|
/// Ruby's `String#rstrip`, as pygments.rb applies it to what Pygments
/// returns.
fn rstrip(s : String) -> String {
  let mut end = s.length()
  while end > 0 {
    let c = s[end - 1]
    if c == ' ' ||
      c == '\t' ||
      c == '\n' ||
      c == '\r' ||
      c == '\u{0B}' ||
      c == '\u{0C}' ||
      c == '\u{00}' {
      end -= 1
    } else {
      break
    }
  }
  s[:end].to_owned()
}

///|
/// `Pygments.highlight`: the options go to the lexer and to the HTML
/// formatter alike; None when Pygments fails.
fn highlight(
  source : String,
  alias_ : String,
  options : Map[String, String],
) -> String? {
  if source == "" {
    return Some(source)
  }
  let options = options.copy()
  options["outencoding"] = "utf-8"
  let html = @py.highlight(
    source,
    @py.get_lexer_by_name(alias_, options~),
    @py.get_formatter_by_name("html", options~),
  ) catch {
    _ => return None
  }
  Some(rstrip(html))
}

///|
/// `Pygments.css(selector, style:)`: the style definitions of the HTML
/// formatter, right-stripped.
fn css(selector : String, style : String) -> String {
  let defs = @py.get_formatter_by_name("html", options={ "style": style }).get_style_defs(
    arg=selector,
  ) catch {
    _ => return ""
  }
  rstrip(defs)
}

///|
/// Make Pygments the converter's highlighter for `source-highlighter:
/// pygments`.
pub fn register() -> Unit {
  @asciidoctor_pdf.register_pygments({
    find_lexer,
    find_lexer_by_mimetype,
    highlight,
    css,
    styles: () => @py_styles.get_all_styles(),
  })
}
