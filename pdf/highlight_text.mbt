///|
// Text helpers of asciidoctor-pdf's source highlighting (convert_code):
// tab expansion, callout extraction and restoration, indentation guards.

///|
let tab_size = 4

///|
/// asciidoctor-pdf's `expand_tabs`: tabs to spaces, at 4-column stops.
fn expand_tabs(text : String) -> String {
  if !text.contains("\t") {
    return text
  }
  let sb = StringBuilder()
  let mut column = 0
  for c in text {
    if c == '\t' {
      let spaces = tab_size - column % tab_size
      for _ in 0..<spaces {
        sb.write_char(' ')
      }
      column += spaces
    } else {
      sb.write_char(c)
      column = if c == '\n' { 0 } else { column + 1 }
    }
  }
  sb.to_string()
}

///|
/// The callouts asciidoctor-pdf takes out of the source before it is
/// highlighted (`extract_conums`): by line (0-based), the white space that
/// preceded them, if any, and their numbers.
priv struct Conums {
  lines : Map[Int, (String?, Array[Int])]
}

///|
/// asciidoctor-pdf's `CalloutExtractRx`.
let callout_extract_rx : @regex.Regex = @regex.re(
  "(?:(?://|#|--|;;) ?)?(\\\\)?<!?(|--)(\\d+|\\.)\\2> ?(?=(?:\\\\?<!?\\2(?:\\d+|\\.)\\2> ?)*$)",
)

///|
/// asciidoctor-pdf's `extract_conums`: the source without its callouts
/// (an escaped one loses its backslash) and where they were. Like Ruby's
/// `split`, trailing empty lines are dropped.
fn extract_conums(text : String) -> (String, Conums?) {
  let lines = text.split("\n").map(l => l.to_owned()).collect()
  while lines.length() > 0 && lines[lines.length() - 1] == "" {
    ignore(lines.pop())
  }
  let mapping : Map[Int, (String?, Array[Int])] = Map([])
  let mut auto_num = 0
  let out = []
  for line_num, line in lines {
    let mut line = line
    if line.contains("<") {
      line = callout_extract_rx.replace(line, fn(m) {
        if m.group(1) == Some("\\") {
          // honor the escape: the match without its first backslash
          let matched = m.matched()
          match matched.find("\\") {
            Some(i) => matched[:i].to_owned() + matched[i + 1:].to_owned()
            None => matched
          }
        } else {
          let number = if m.group(3) == Some(".") {
            auto_num += 1
            auto_num
          } else {
            ruby_to_i(m.group(3).unwrap_or("0"))
          }
          match mapping.get(line_num) {
            Some((_, numbers)) => numbers.push(number)
            None => mapping[line_num] = (None, [number])
          }
          ""
        }
      })
      // the white space before the callouts is kept apart
      match mapping.get(line_num) {
        Some((_, numbers)) if line.has_suffix(" ") => {
          let trimmed = ruby_rstrip(line)
          mapping[line_num] = (
            Some(line[trimmed.length():].to_owned()),
            numbers,
          )
          line = trimmed
        }
        _ => ()
      }
    }
    out.push(line)
  }
  (
    out.join("\n"),
    if mapping.is_empty() {
      None
    } else {
      Some({ lines: mapping, })
    },
  )
}

///|
/// Ruby's `String#rstrip` (white space and NUL).
fn ruby_rstrip(s : String) -> String {
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
/// The glyphs of the conum numbers `numbers` (asciidoctor-pdf's
/// `conum_glyph`), joined by spaces.
fn conum_text(numbers : Array[Int]) -> String {
  numbers.map(n => conum_glyph(n.to_string())).join(" ")
}

///|
/// asciidoctor-pdf's `restore_conums`: the fragments regrouped by line,
/// each line given its line number (`linenums`, the first line's number,
/// right-aligned with spaces, in `code_linenum_font_color`) and the mark
/// of its highlight (`highlight`: the background by line number), and
/// ended by its callouts (in the conum font and colour).
fn restore_conums(
  fragments : Array[Fragment],
  conums : Conums?,
  base : Style,
  linenums? : Int,
  highlight? : Map[Int, Color],
) -> Array[Fragment] {
  let lines : Array[Array[Fragment]] = [[]]
  for fragment in fragments {
    let text = fragment.text
    if text == "\n" {
      lines.push([])
    } else if text.contains("\n") {
      for idx, part in text.split("\n").collect() {
        if idx > 0 {
          lines.push([])
        }
        if part != "" {
          lines[lines.length() - 1].push({ ..fragment, text: part.to_owned(), })
        }
      }
    } else {
      lines[lines.length() - 1].push(fragment)
    }
  }
  let conum_family = match t_str("conum_font_family") {
    Some(f) if f != base.family => Some(f)
    _ => None
  }
  let conum_color = t_color("conum_font_color")
  let last = lines.length() - 1
  let pad = (last + 1).to_string().length()
  let linenum_color = t_color_or("code_linenum_font_color", rgb_hex(0x999999))
  let out : Array[Fragment] = []
  for index, line in lines {
    let visible = index + linenums.unwrap_or(1)
    if linenums is Some(_) {
      let number = visible.to_string()
      let padded = " ".repeat(@cmp.maximum(0, pad - number.length())) +
        number +
        " "
      out.push({
        text: padded,
        style: { ..base, color: linenum_color, linenum: true, },
        anchor: None,
      })
    }
    match highlight.bind(h => h.get(visible)) {
      Some(color) => out.push(line_mark(base, color, FullLine))
      None => ()
    }
    out.append(line)
    match conums.bind(c => c.lines.get(index)) {
      Some((space, numbers)) => {
        match space {
          Some(s) => out.push({ text: s, style: base, anchor: None, })
          None => ()
        }
        let style = {
          ..base,
          color: conum_color.unwrap_or(base.color),
          family: conum_family.unwrap_or(base.family),
          font_set: base.font_set || conum_family is Some(_),
        }
        out.push({ text: conum_text(numbers), style, anchor: None, })
      }
      None => ()
    }
    if index != last {
      out.push({ text: "\n", style: base, anchor: None, })
    }
  }
  out
}

///|
/// The zero-width mark that paints a highlighted source line (Rouge's
/// `highlight_line_fragment`, asciidoctor-pdf's `restore_conums`).
fn line_mark(base : Style, color : Color, extent : CodeBackground) -> Fragment {
  {
    text: "\u{200B}",
    style: {
      ..base,
      background: Some(color),
      code_background: Some(extent),
      line_mark: true,
    },
    anchor: None,
  }
}
