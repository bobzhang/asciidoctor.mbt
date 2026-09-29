///|
// Formatted text: the HTML-like inline markup the converter produces
// (asciidoctor-pdf's FormattedText::Parser tag set) parsed into styled
// fragments.

///|
/// Character formatting of a fragment.
priv struct Style {
  family : String
  size : Double
  bold : Bool
  italic : Bool
  color : Color
  /// `#name` for an internal link, otherwise a URI
  link : String?
  background : Color?
  /// 1 for superscript, -1 for subscript (Prawn raises a superscript by 0.85
  /// of its ascender and drops a subscript by its descender)
  script : Int
  /// padding around the text inside its background (mark, kbd): widens the
  /// fragment by twice this, as asciidoctor-pdf's `border_offset` does
  border_offset : Double
  underline : Bool
  strike : Bool
}

///|
fn Style::new(
  family? : String = base_font_family,
  size? : Double = base_font_size,
  bold? : Bool = false,
  italic? : Bool = false,
  color? : Color = base_font_color,
) -> Style {
  {
    family,
    size,
    bold,
    italic,
    color,
    link: None,
    background: None,
    script: 0,
    border_offset: 0.0,
    underline: false,
    strike: false,
  }
}

///|
/// A run of text in one style. An `anchor` fragment has no text and marks
/// a named destination at its position.
priv struct Fragment {
  text : String
  style : Style
  anchor : String?
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
  match tag {
    "strong" | "b" => { ..style, bold: true, }
    "em" | "i" => { ..style, italic: true, }
    "code" => { ..style, family: mono_font_family, color: codespan_font_color, }
    "kbd" =>
      {
        ..style,
        family: mono_font_family,
        background: Some(rgb_hex(0xF5F5F5)),
        border_offset: 2.0,
      }
    "button" => { ..style, bold: true, }
    "sup" => { ..style, size: style.size * 0.583, script: 1, }
    "sub" => { ..style, size: style.size * 0.583, script: -1, }
    "mark" =>
      { ..style, background: Some(rgb_hex(0xFFFF00)), border_offset: 1.0, }
    "u" => { ..style, underline: true, }
    "del" | "s" | "strikethrough" => { ..style, strike: true, }
    "a" =>
      match attrs.get("href") {
        Some(href) => { ..style, link: Some(href), color: link_font_color, }
        None =>
          match attrs.get("anchor") {
            Some(anchor) =>
              { ..style, link: Some("#" + anchor), color: link_font_color, }
            None => style
          }
      }
    "font" | "color" | "span" => {
      let mut s = style
      match attrs.get("size") {
        Some(size) => s = { ..s, size: parse_size(size, s.size), }
        None => ()
      }
      match attrs.get("name") {
        Some(family) => s = { ..s, family, }
        None => ()
      }
      match
        (match attrs.get("color") {
          Some(c) => Some(c)
          None => attrs.get("rgb")
        }) {
        Some(color) =>
          match parse_color(color) {
            Some(c) => s = { ..s, color: c, }
            None => ()
          }
        None => ()
      }
      match attrs.get("class") {
        Some(classes) =>
          for role in classes.split(" ") {
            match role.to_owned() {
              "underline" => s = { ..s, underline: true, }
              "line-through" => s = { ..s, strike: true, }
              "big" => s = { ..s, size: s.size * 1.2, }
              "small" => s = { ..s, size: s.size * 0.8, }
              "subtitle" =>
                s = { ..s, size: s.size * 0.8, color: rgb_hex(0x999999), }
              _ => ()
            }
          }
        None => ()
      }
      s
    }
    _ => style
  }
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
  let fragments : Array[Fragment] = []
  let stack : Array[(String, Style)] = []
  let mut style = base
  let text = StringBuilder()
  fn flush() {
    if !text.is_empty() {
      let raw = decode_entities(text.to_string())
      let content = if normalize { collapse_whitespace(raw) } else { raw }
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
        let tag = inner[1:].to_owned().trim(chars=" ").to_owned()
        // pop to the matching open tag
        let mut k = stack.length() - 1
        while k >= 0 && stack[k].0 != tag {
          k -= 1
        }
        if k >= 0 {
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
          flush()
          fragments.push({ text: "", style, anchor: Some(id), })
          if !self_closing {
            stack.push((tag, style))
          }
        }
        "img" => ()
        _ =>
          if !self_closing {
            flush()
            stack.push((tag, style))
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
