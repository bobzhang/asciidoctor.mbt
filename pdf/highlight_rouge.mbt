///|
// asciidoctor-pdf's Rouge formatter (ext/rouge/formatters/prawn.rb): a
// Rouge token stream as formatted text fragments in a theme's colours.

///|
/// Rouge's line-oriented token types, whose background spans the line.
let line_oriented_tokens : Array[String] = [
  "Generic.Inserted", "Generic.Deleted", "Generic.Heading", "Generic.Subheading",
]

///|
/// The formatter of a document (asciidoctor-pdf keeps one per converter):
/// its theme, the theme's background, the line gap and the colour of
/// highlighted lines.
priv struct RougeFormatter {
  theme : @rouge.Theme
  background : String?
  line_gap : Double
  highlight_color : Color
}

///|
/// The formatter for `rouge-style` (asciidoctor-pdf's default theme when
/// unset or unknown).
fn RougeFormatter::new(style : String?) -> RougeFormatter {
  let theme = match style.bind(@rouge.Theme::find) {
    Some(t) => t
    None => @rouge.Theme::default()
  }
  let background = theme.style_for("Text").bind(s => s.bg).map(normalize_color)
  {
    theme,
    background,
    line_gap: t_num_or("code_line_gap", 0.0),
    highlight_color: t_color("code_highlight_background_color").unwrap_or(
      rgb_hex(0xFFFFCC),
    ),
  }
}

///|
/// Rouge's `normalize_color`: without the `#`, three digits doubled.
fn normalize_color(raw : String) -> String {
  let hex = if raw.has_prefix("#") { raw[1:].to_owned() } else { raw }
  if hex.length() == 3 {
    let sb = StringBuilder()
    for c in hex {
      sb.write_char(c)
      sb.write_char(c)
    }
    sb.to_string()
  } else {
    hex
  }
}

///|
/// The background of the block when the theme gives its text one
/// (`background_color`).
fn RougeFormatter::block_background(self : RougeFormatter) -> Color? {
  self.background.bind(parse_color)
}

///|
/// Rouge's `create_fragment`: `text` in the style the theme gives `tok`
/// (with `inline_block` from the caller: a token that ends a line).
fn RougeFormatter::fragment(
  self : RougeFormatter,
  base : Style,
  tok : String,
  text : String,
  inline_block? : Bool = false,
) -> Fragment {
  let mut style = base
  match self.theme.style_for(tok) {
    Some(rules) => {
      match rules.bg.map(normalize_color) {
        Some(bg) if Some(bg) != self.background =>
          match parse_color(bg) {
            Some(color) => {
              let line_oriented = line_oriented_tokens.contains(tok)
              style = {
                ..style,
                background: Some(color),
                code_background: if line_oriented || inline_block {
                  Some(Gap(self.line_gap, line_oriented))
                } else {
                  None
                },
              }
            }
            None => ()
          }
        _ => ()
      }
      match rules.fg.map(normalize_color).bind(parse_color) {
        Some(color) => style = { ..style, color, }
        None => ()
      }
      if rules.bold || rules.italic {
        style = { ..style, bold: rules.bold, italic: rules.italic, }
      }
      if rules.underline {
        style = { ..style, underline: true, }
      }
    }
    None => ()
  }
  { text, style, anchor: None, }
}

///|
/// Rouge's `stream`: the fragments of `tokens`, each line given its number
/// (`start_line`, at least 1, padded with no-break spaces to the widest)
/// when `line_numbers`, and the highlight mark when its number is in
/// `highlight_lines`; the first space of a line is guarded unless a line
/// number precedes it.
fn RougeFormatter::format(
  self : RougeFormatter,
  base : Style,
  tokens : Array[(String, String)],
  line_numbers? : Bool = false,
  start_line? : Int = 1,
  highlight_lines? : Map[Int, Bool],
) -> Array[Fragment] {
  let out : Array[Fragment] = []
  let plain = fn(text : String) -> Fragment {
    { text, style: base, anchor: None, }
  }
  if !line_numbers && highlight_lines is None {
    let mut start_of_line = true
    for token in tokens {
      let (tok, val) = token
      if val.iter().all(c => c == '\n') {
        start_of_line = true
        out.push(plain(val))
        continue
      }
      let mut val = val
      if start_of_line && val.has_prefix(" ") {
        val = "\u{a0}" + val[1:].to_owned()
      }
      if val.contains("\n ") {
        val = val.replace_all(old="\n ", new="\n\u{a0}")
      }
      let ends_line = val.has_suffix("\n")
      let fragment = if ruby_rstrip(val) == "" {
        plain(val)
      } else {
        self.fragment(base, tok, val, inline_block=ends_line)
      }
      // a fragment ending a line is an inline block (its background, if
      // any, spans the line gap)
      start_of_line = ends_line
      out.push(fragment)
    }
    return out
  }
  let highlighted = fn(n : Int) {
    highlight_lines.bind(h => h.get(n)) is Some(true)
  }
  let mut linenum = if start_line > 0 { start_line } else { 1 }
  let mut start_of_line = false
  let linenum_fragment = fn(n : Int) -> Fragment {
    let f = self.fragment(base, "Generic.Lineno", "\{n} ")
    { ..f, style: { ..f.style, linenum: true, }, }
  }
  let mark = fn() {
    line_mark(base, self.highlight_color, Gap(self.line_gap, true))
  }
  let next_line = fn(n : Int) {
    if line_numbers {
      out.push(linenum_fragment(n))
    } else {
      start_of_line = true
    }
    if highlighted(n) {
      out.push(mark())
    }
  }
  next_line(linenum)
  for token in tokens {
    let (tok, val) = token
    if val == "\n" {
      out.push(plain("\n"))
      linenum += 1
      next_line(linenum)
    } else if val.contains("\n") {
      // a token ending in a line feed is taken for a line-oriented form
      let line_oriented = val.has_suffix("\n")
      let base_fragment = self.fragment(base, tok, val)
      let lines = val.split("\n").map(l => l.to_owned()).collect()
      for idx, line in lines {
        let last = idx == lines.length() - 1
        if last && line == "" {
          break
        }
        let mut text = if last { line } else { line + "\n" }
        if start_of_line {
          if text.has_prefix(" ") {
            text = "\u{a0}" + text[1:].to_owned()
          }
          start_of_line = false
        }
        let style = if line_oriented &&
          base_fragment.style.background is Some(_) {
          {
            ..base_fragment.style,
            code_background: Some(
              match base_fragment.style.code_background {
                Some(Gap(gap, to_edge)) => Gap(gap, to_edge)
                _ => Gap(self.line_gap, false)
              },
            ),
          }
        } else {
          base_fragment.style
        }
        out.push({ text, style, anchor: None, })
        if !last {
          linenum += 1
          next_line(linenum)
        }
      }
    } else {
      let mut val = val
      if start_of_line {
        if val.has_prefix(" ") {
          val = "\u{a0}" + val[1:].to_owned()
        }
        start_of_line = false
      }
      out.push(self.fragment(base, tok, val))
    }
  }
  // the line numbers right-aligned to the widest, with no-break spaces
  let width = linenum.to_string().length()
  if line_numbers && width > 1 {
    let width = width + 1
    out.map(f => {
      if f.style.linenum && f.text.length() < width {
        { ..f, text: "\u{a0}".repeat(width - f.text.length()) + f.text, }
      } else {
        f
      }
    })
  } else {
    out
  }
}
