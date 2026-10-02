///|
// Formatted text: the HTML-like inline markup the converter produces
// (asciidoctor-pdf's FormattedText::Parser tag set) parsed into styled
// fragments.

///|
/// A style in the theme's base font (`base_font_family` and the rest),
/// overridden by what is given.
fn text_style(
  family? : String = base_font_family(),
  size? : Double = base_font_size(),
  bold? : Bool = false,
  italic? : Bool = false,
  doc_bold? : Bool = base_font_style().0,
  doc_italic? : Bool = base_font_style().1,
  color? : Color = base_font_color(),
) -> Style {
  {
    family,
    size,
    bold,
    italic,
    doc_bold,
    doc_italic,
    font_set: false,
    text_transform: None,
    color,
    link: None,
    background: None,
    script: 0,
    border_offset: 0.0,
    underline: false,
    strike: false,
    wj: false,
    image: -1,
    callback: -1,
    code_background: None,
    linenum: false,
    line_mark: false,
    wrap_break: false,
  }
}

///|
fn decode_entity(name : String) -> String? {
  match name {
    "amp" => Some("&")
    "lt" => Some("<")
    "gt" => Some(">")
    "quot" => Some("\"")
    "apos" => Some("'")
    "nbsp" => Some(" ")
    _ =>
      if name.has_prefix("#x") || name.has_prefix("#X") {
        let hex = name[2:].to_owned()
        parse_int_radix(hex, 16).map(code_to_string)
      } else if name.has_prefix("#") {
        parse_int_radix(name[1:].to_owned(), 10).map(code_to_string)
      } else {
        None
      }
  }
}

///|
fn parse_int_radix(text : String, radix : Int) -> Int? {
  if text.is_empty() {
    return None
  }
  let mut value = 0
  for c in text {
    let digit = if c >= '0' && c <= '9' {
      c.to_int() - '0'.to_int()
    } else if c >= 'a' && c <= 'f' {
      c.to_int() - 'a'.to_int() + 10
    } else if c >= 'A' && c <= 'F' {
      c.to_int() - 'A'.to_int() + 10
    } else {
      return None
    }
    if digit >= radix {
      return None
    }
    value = value * radix + digit
  }
  Some(value)
}

///|
fn code_to_string(code : Int) -> String {
  let sb = StringBuilder()
  sb.write_char(code.unsafe_to_char())
  sb.to_string()
}

///|
/// Decode character references in plain text.
fn decode_entities(text : String) -> String {
  if !text.contains("&") {
    return text
  }
  let sb = StringBuilder()
  let mut i = 0
  let n = text.length()
  while i < n {
    let c = text[i]
    if c == '&' {
      let mut j = i + 1
      while j < n && j - i < 12 && text[j] != ';' && text[j] != '&' {
        j += 1
      }
      if j < n && text[j] == ';' {
        match decode_entity(text[i + 1:j].to_owned()) {
          Some(decoded) => {
            sb.write_string(decoded)
            i = j + 1
            continue
          }
          None => ()
        }
      }
    }
    sb.write_char(c.to_int().unsafe_to_char())
    i += 1
  }
  sb.to_string()
}

///|
/// Parse `name="value"` pairs of a start tag.
fn parse_tag_attributes(source : String) -> Map[String, String] {
  let attrs : Map[String, String] = Map([])
  let mut i = 0
  let n = source.length()
  while i < n {
    while i < n && (source[i] == ' ' || source[i] == '\n' || source[i] == '\t') {
      i += 1
    }
    let name_start = i
    while i < n && source[i] != '=' && source[i] != ' ' && source[i] != '/' {
      i += 1
    }
    let name = source[name_start:i].to_owned()
    if i < n && source[i] == '=' {
      i += 1
      if i < n && (source[i] == '"' || source[i] == '\'') {
        let quote = source[i]
        i += 1
        let value_start = i
        while i < n && source[i] != quote {
          i += 1
        }
        attrs[name] = decode_entities(source[value_start:i].to_owned())
        i += 1
      } else {
        let value_start = i
        while i < n && source[i] != ' ' {
          i += 1
        }
        attrs[name] = source[value_start:i].to_owned()
      }
    } else if !name.is_empty() {
      attrs[name] = ""
    } else {
      i += 1
    }
  }
  attrs
}

///|
/// Parse `#rrggbb` / `rrggbb`.
fn parse_color(value : String) -> Color? {
  let hex = if value.has_prefix("#") { value[1:].to_owned() } else { value }
  if hex.length() != 6 {
    return None
  }
  parse_int_radix(hex, 16).map(rgb_hex)
}

///|
/// A font size attribute: `1.2em`, `85%` or points.
fn parse_size(value : String, current : Double) -> Double {
  if value.has_suffix("em") {
    parse_decimal(value[:value.length() - 2].to_owned()) * current
  } else if value.has_suffix("%") {
    parse_decimal(value[:value.length() - 1].to_owned()) / 100.0 * current
  } else {
    parse_decimal(value)
  }
}

///|
fn parse_decimal(text : String) -> Double {
  @string.parse_double(text) catch {
    _ => 0.0
  }
}

///|
/// Apply the style of an opening tag.
fn open_tag(tag : String, attrs : Map[String, String], style : Style) -> Style {
  let tagged = tag_style(tag, attrs, style)
  // then the roles of its classes the theme styles, whatever the tag
  // (Transform#build_fragment)
  match attrs.get("class") {
    Some(classes) => apply_roles(tagged, classes)
    None => tagged
  }
}

///|
/// The tag names asciidoctor-pdf's markup grammar knows (`tag_name`,
/// `void_tag_name` in formatted_text/parser.treetop), in its order.
let markup_tag_names : Array[String] = [
  "a", "strong", "em", "code", "font", "span", "button", "kbd", "sup", "sub", "mark",
  "menu", "del",
]

///|
let markup_void_tag_names : Array[String] = ["br", "img"]

///|
/// Match the first of `names` that `s` has at `pos`, as a PEG ordered
/// choice does; the position after it.
fn match_name(s : String, pos : Int, names : Array[String]) -> Int? {
  for name in names {
    if s[pos:].has_prefix(name) {
      return Some(pos + name.length())
    }
  }
  None
}

///|
/// `attributes`: ` name="value"` pairs, names in [a-z_]; the position
/// after them.
fn match_markup_attributes(s : String, pos : Int) -> Int {
  let n = s.length()
  let mut p = pos
  while true {
    let mut q = p
    while q < n && s[q] == ' ' {
      q += 1
    }
    if q == p {
      break
    }
    let name_start = q
    while q < n && ((s[q] >= 'a' && s[q] <= 'z') || s[q] == '_') {
      q += 1
    }
    if q == name_start || q + 1 >= n || s[q] != '=' || s[q + 1] != '"' {
      break
    }
    q += 2
    while q < n && s[q] != '"' {
      q += 1
    }
    if q >= n {
      break
    }
    p = q + 1
  }
  p
}

///|
/// Whether asciidoctor-pdf's markup grammar parses `s`: text, character
/// references (`&amp;`, `&#8217;`, `&#x2019;`), the known void and start
/// tags with double-quoted attributes, and end tags that close whatever
/// element is open. Formatted text it cannot parse is shown as it is,
/// markup and all (Formatter#format).
fn markup_parses(s : String) -> Bool {
  let n = s.length()
  let mut depth = 0
  let mut i = 0
  while i < n {
    let c = s[i]
    if c == '<' {
      if i + 1 < n && s[i + 1] == '/' {
        // an end tag closes the element open here; at the top level
        // there is none
        guard match_name(s, i + 2, markup_tag_names) is Some(p) &&
          p < n &&
          s[p] == '>' &&
          depth > 0 else {
          return false
        }
        depth -= 1
        i = p + 1
        continue
      }
      match match_name(s, i + 1, markup_void_tag_names) {
        Some(p) => {
          let mut q = match_markup_attributes(s, p)
          let mut r = q
          while r < n && s[r] == ' ' {
            r += 1
          }
          if r < n && s[r] == '/' {
            q = r + 1
          }
          if q < n && s[q] == '>' {
            i = q + 1
            continue
          }
        }
        None => ()
      }
      guard match_name(s, i + 1, markup_tag_names) is Some(p) else {
        return false
      }
      let q = match_markup_attributes(s, p)
      guard q < n && s[q] == '>' else { return false }
      depth += 1
      i = q + 1
    } else if c == '&' {
      let mut j = i + 1
      let digits = fn(from : Int, hex : Bool) {
        let mut k = from
        while k < n &&
              (
                (s[k] >= '0' && s[k] <= '9') ||
                (
                  hex &&
                  ((s[k] >= 'a' && s[k] <= 'f') || (s[k] >= 'A' && s[k] <= 'F'))
                )
              ) {
          k += 1
        }
        k
      }
      if s[j:].has_prefix("#x") {
        let k = digits(j + 2, true)
        guard k - (j + 2) >= 2 && k - (j + 2) <= 5 else { return false }
        j = k
      } else if s[j:].has_prefix("#") {
        let k = digits(j + 1, false)
        guard k - (j + 1) >= 2 && k - (j + 1) <= 6 else { return false }
        j = k
      } else {
        guard match_name(s, j, ["amp", "apos", "gt", "lt", "nbsp", "quot"])
          is Some(k) else {
          return false
        }
        j = k
      }
      guard j < n && s[j] == ';' else { return false }
      i = j + 1
    } else {
      i += 1
    }
  }
  depth == 0
}

///|
/// Parse formatted text into fragments. `<br>` becomes a "\n" fragment;
/// with `normalize`, runs of whitespace (including newlines) collapse to
/// one space, as asciidoctor-pdf's formatter does for prose.
fn parse_formatted(
  markup : String,
  base : Style,
  normalize? : Bool = true,
) -> Array[Fragment] {
  if !markup_parses(markup) {
    // shown as it is, markup and all
    let text = if normalize { collapse_whitespace(markup) } else { markup }
    return [{ text, style: base, anchor: None, }]
  }
  let fragments : Array[Fragment] = []
  // each open element: its tag, the style outside it, how many fragments
  // there were when it opened (-1 for an anchor, which is never empty),
  // and the text fragment just before it (-1: none)
  let stack : Array[(String, Style, Int, Int)] = []
  let mut style = base
  let text = StringBuilder()
  fn flush() {
    if !text.is_empty() {
      let raw = decode_entities(text.to_string())
      let content = if normalize { collapse_whitespace(raw) } else { raw }
      let content = match style.text_transform {
        Some(transform) => transform_text(content, transform)
        None => content
      }
      if !content.is_empty() {
        fragments.push({ text: content, style, anchor: None, })
      }
      text.reset()
    }
  }

  let n = markup.length()
  let mut i = 0
  while i < n {
    let c = markup[i]
    if c == '<' {
      // find the end of the tag
      let mut j = i + 1
      while j < n && markup[j] != '>' {
        j += 1
      }
      if j >= n {
        text.write_char('<')
        i += 1
        continue
      }
      let inner = markup[i + 1:j].to_owned()
      i = j + 1
      if inner.has_prefix("/") {
        // an end tag closes the innermost open element, whatever its name
        // (the markup grammar matches `start_tag complex end_tag` without
        // comparing names)
        let k = stack.length() - 1
        if k >= 0 {
          let (_, _, opened, before) = stack[k]
          if opened >= 0 && text.is_empty() && fragments.length() == opened {
            // an element with nothing in it takes the space before it
            // away (Transform#apply)
            if before >= 0 && fragments[before].text.has_suffix(" ") {
              let t = fragments[before].text
              fragments[before] = {
                ..fragments[before],
                text: t[:t.length() - 1].to_owned(),
              }
            }
          }
          flush()
          style = stack[k].1
          while stack.length() > k {
            ignore(stack.pop())
          }
        }
        continue
      }
      let self_closing = inner.has_suffix("/")
      let body = if self_closing {
        inner[:inner.length() - 1].to_owned()
      } else {
        inner
      }
      let mut name_end = 0
      while name_end < body.length() &&
            body[name_end] != ' ' &&
            body[name_end] != '\n' {
        name_end += 1
      }
      let tag = body[:name_end].to_owned()
      let attrs = parse_tag_attributes(body[name_end:].to_owned())
      match tag {
        "br" => {
          flush()
          fragments.push({ text: "\n", style, anchor: None, })
        }
        "a" if attrs.get("id") is Some(id) &&
          !attrs.contains("href") &&
          !attrs.contains("anchor") => {
          // a concealed index term swallows the space before it
          // (asciidoctor-pdf's Transform#apply)
          if attrs.get("type") == Some("indexterm") &&
            !attrs.contains("visible") &&
            !text.is_empty() {
            let pending = text.to_string()
            let mut end = pending.length()
            if normalize {
              while end > 0 &&
                    (
                      pending[end - 1] == ' ' ||
                      pending[end - 1] == '\n' ||
                      pending[end - 1] == '\t'
                    ) {
                end -= 1
              }
            } else if pending[end - 1] == ' ' {
              end -= 1
            }
            text.reset()
            text.write_string(pending[:end].to_owned())
          }
          flush()
          // a fresh fragment (Transform#build_fragment): none of the
          // markup around it applies, so it is in the text's own font and
          // size, which count towards its line's height
          fragments.push({
            text: "",
            style: { ..base, wj: style.wj, },
            anchor: Some(id),
          })
          if !self_closing {
            stack.push((tag, style, -1, -1))
          }
        }
        "img" => {
          // an inline image: a placeholder the size of the image (see
          // `inline_image_size`), drawn as the image
          let index = match attrs.get("src") {
            Some(s) => @string.parse_int(s) catch { _ => -1 }
            None => -1
          }
          if index >= 0 && index < session().inline_images.length() {
            flush()
            match session().inline_images[index].dropped {
              // an image the arranger drops: its alt text, a fragment of its
              // own (the img element's), whose callback warns when inked
              Some((alt, _, _)) =>
                fragments.push({
                  text: alt,
                  style: { ..style, callback: index, },
                  anchor: None,
                })
              None =>
                fragments.push({
                  text: "\u{2063}",
                  style: { ..style, image: index, },
                  anchor: None,
                })
            }
          }
        }
        _ =>
          if !self_closing {
            let before = if text.is_empty() { -1 } else { fragments.length() }
            flush()
            let before = if before >= 0 && fragments.length() > before {
              before
            } else {
              -1
            }
            stack.push((tag, style, fragments.length(), before))
            style = open_tag(tag, attrs, style)
          }
      }
    } else {
      text.write_char(c.to_int().unsafe_to_char())
      i += 1
    }
  }
  flush()
  fragments
}

///|
fn collapse_whitespace(text : String) -> String {
  let sb = StringBuilder()
  let mut in_space = false
  for c in text {
    if c == ' ' || c == '\n' || c == '\t' || c == '\r' {
      if !in_space {
        sb.write_char(' ')
      }
      in_space = true
    } else {
      sb.write_char(c)
      in_space = false
    }
  }
  sb.to_string()
}
