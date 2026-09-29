///|
// Line breaking of formatted text, following Prawn's greedy wrap
// (Prawn::Text::Formatted::LineWrap): each fragment is cut into tokens —
// runs of word characters (ending in hyphens or a soft hyphen when they
// have them), runs of whitespace, and runs of hyphens with the word after
// them — and a line may break between any two tokens, and between
// fragments. A token longer than the line wraps by character, spaces
// starting a line are dropped and trailing ones do not count, and a
// justified line widens its spaces, except on the last line of a paragraph
// and before a hard break.
//
// Two widths are tracked per character. `fit` is Prawn's (glyph widths
// truncated to 1/1000 em, kerned within a token only, as Prawn measures
// token by token) and decides where lines break, so breaks match Ruby;
// `draw` is the width the PDF declares for the glyph, kerned with the next
// character of the fragment as Prawn draws it, and places glyphs, so the
// emitted text needs a displacement only where kerning or justification
// moves a glyph.

///|
priv enum Alignment {
  Left
  Center
  Right
  Justify
} derive(Eq)

///|
priv struct Item {
  unit : Int
  fragment : Int
  mut fit : Double
  draw : Double
  /// kerning with the next character, points; part of `draw`, and of
  /// `fit` unless a token boundary falls between the two
  kern : Double
  hard_break : Bool
  anchor : String?
}

///|
/// One placed run of a line; `x` is relative to the line's left edge.
priv struct LineRun {
  text : String
  style : Style
  face : Face
  x : Double
  advances : Array[Double]
  width : Double
}

///|
priv struct Line {
  runs : Array[LineRun]
  anchors : Array[(String, Double)]
  /// the width Prawn measures (truncated glyph widths)
  fit_width : Double
  ascender : Double
  descender : Double
  height : Double
}

///|
/// The unit of an item that only takes up room: the padding a fragment
/// with a `border_offset` has on each side.
let pad_unit = -1

///|
fn is_break_space(unit : Int) -> Bool {
  unit == 0x20
}

///|
/// Prawn's whitespace break characters: space, tab, zero-width space.
fn is_whitespace(unit : Int) -> Bool {
  unit == 0x20 || unit == 0x09 || unit == 0x200B
}

///|
/// Where Prawn's tokens start: `starts[i]` when a line may break before
/// `items[i]`.
fn token_starts(items : Array[Item]) -> Array[Bool] {
  let n = items.length()
  let starts = Array::make(n, false)
  let kind = fn(i : Int) -> Int {
    let unit = items[i].unit
    // an anchor stands for asciidoctor-pdf's zero-width-space placeholder
    if is_whitespace(unit) || items[i].anchor is Some(_) {
      1
    } else if unit == 0x2D {
      2
    } else if unit == 0xAD {
      3
    } else {
      0
    }
  }
  let mut i = 0
  while i < n {

    // tokens run across fragments: Prawn pulls the last word of a fragment
    // onto the next line with the word the next fragment starts with (its
    // `pull_preceding_fragment_to_join_this_one?`), so a style change
    // inside a word is no break opportunity; a hard break ends every token
    let mut end = i + 1
    while end < n && !items[end].hard_break {
      end += 1
    }
    let mut pos = i
    while pos < end {
      starts[pos] = true
      let mut j = pos
      match kind(pos) {
        0 => {
          while j < end && kind(j) == 0 {
            j += 1
          }
          if j < end && kind(j) == 3 {
            j += 1
          } else {
            while j < end && kind(j) == 2 {
              j += 1
            }
          }
        }
        1 =>
          while j < end && kind(j) == 1 {
            j += 1
          }
        2 => {
          while j < end && kind(j) == 2 {
            j += 1
          }
          while j < end && kind(j) == 0 {
            j += 1
          }
        }
        _ => j += 1
      }
      pos = j
    }
    i = end
  }
  starts
}

///|
fn build_items(
  fragments : Array[Fragment],
  catalog : FontCatalog,
) -> (Array[Item], Array[Face]) {
  let items : Array[Item] = []
  let faces : Array[Face] = []
  for index, fragment in fragments {
    let style = fragment.style
    let (bold, italic) = style.face_style()
    let face = catalog.face(style.family, bold, italic)
    faces.push(face)
    let blank : Item = {
      unit: 0,
      fragment: index,
      fit: 0.0,
      draw: 0.0,
      kern: 0.0,
      hard_break: false,
      anchor: None,
    }
    match fragment.anchor {
      Some(name) => {
        items.push({ ..blank, anchor: Some(name), })
        continue
      }
      None => ()
    }
    let text = fragment.text
    let n = text.length()
    let scale = style.size / 1000.0
    let pad : Item = {
      ..blank,
      unit: pad_unit,
      fit: style.border_offset,
      draw: style.border_offset,
    }
    if style.border_offset > 0.0 && n > 0 {
      items.push(pad)
    }
    for i in 0..<n {
      let unit = text[i].to_int()
      if unit == 0x0A {
        items.push({ ..blank, unit, hard_break: true, })
        continue
      }
      // a zero-width space is a break opportunity that draws nothing; the
      // low half of a surrogate pair rides on the high half's advance
      if unit == 0x200B || (unit >= 0xDC00 && unit <= 0xDFFF) {
        items.push({ ..blank, unit, })
        continue
      }
      let cp = if unit >= 0xD800 && unit <= 0xDBFF && i + 1 < n {
        0x10000 + ((unit - 0xD800) << 10) + (text[i + 1].to_int() - 0xDC00)
      } else {
        unit
      }
      let kern = if i + 1 < n {
        face.kerning(cp, text[i + 1].to_int()) * scale
      } else {
        0.0
      }
      items.push({
        ..blank,
        unit,
        fit: face.prawn_width(cp) * scale,
        draw: face.drawn_width(cp) * scale + kern,
        kern,
      })
    }
    if style.border_offset > 0.0 && n > 0 {
      items.push(pad)
    }
  }
  (items, faces)
}

///|
/// Break `fragments` into lines of at most `width` (the first line
/// `first_width`) and place them.
fn typeset_lines(
  fragments : Array[Fragment],
  catalog : FontCatalog,
  width : Double,
  align : Alignment,
  first_width? : Double = width,
) -> Array[Line] {
  let (items, faces) = build_items(fragments, catalog)
  let n = items.length()
  let starts = token_starts(items)
  // kerning counts towards fitting only inside a token
  for i in 0..<n {
    if i + 1 >= n || !starts[i + 1] {
      items[i].fit += items[i].kern
    }
  }
  let ranges : Array[(Int, Int, Bool)] = [] // start, end, ended by hard break
  let mut start = 0
  while start <= n {
    if start >= n {
      if ranges.is_empty() || ranges[ranges.length() - 1].2 {
        ranges.push((start, start, false))
      }
      break
    }
    let limit = if ranges.is_empty() { first_width } else { width }
    let mut w = 0.0
    // spaces a line starts with are dropped, as Prawn strips the first
    // fragment of each line (anchors in front of them notwithstanding)
    let mut visible = false
    let mut last_break = -1
    let mut i = start
    let mut end = -1
    let mut hard = false
    while i < n {
      let item = items[i]
      if item.hard_break {
        end = i
        hard = true
        break
      }
      if visible && starts[i] {
        last_break = i
      }
      if is_break_space(item.unit) {
        if !visible {
          // dropped: it becomes a zero-width space, which draws nothing
          items[i] = { ..item, unit: 0x200B, fit: 0.0, draw: 0.0, }
        } else {
          w += item.fit
        }
        i += 1
        continue
      }
      if w + item.fit > limit + 0.0001 && visible {
        end = if last_break > start {
          pull_back_limit(items, start, last_break, i)
        } else {
          i
        }
        break
      }
      w += item.fit
      if item.anchor is None && item.unit != 0x200B {
        visible = true
      }
      i += 1
    }
    if end < 0 {
      end = n
    }
    ranges.push((start, end, hard))
    start = if hard { end + 1 } else { end }
    if hard && start == n {
      // a trailing hard break ends the text
      break
    }
  }
  let lines : Array[Line] = []
  for index, range in ranges {
    let (from, to, hard) = range
    let is_last = index == ranges.length() - 1
    let limit = if index == 0 { first_width } else { width }
    lines.push(
      place_line(
        fragments,
        faces,
        items,
        from,
        to,
        limit,
        align,
        align == Justify && !is_last && !hard,
      ),
    )
  }
  lines
}

///|
/// Prawn's break characters (`LineWrap#break_chars`): whitespace, the
/// zero-width space, the soft hyphen and the hyphen.
fn is_break_char(unit : Int) -> Bool {
  is_whitespace(unit) || unit == 0xAD || unit == 0x2D
}

///|
/// Where a line that overflows at `items[i]` ends, when the word that does
/// not fit starts at `token` (a token start after the line's `start`).
///
/// Prawn wraps fragment by fragment: when not even the first segment of a
/// fragment fits, it moves the last word of the fragment before it to the
/// next line with it (`pull_preceding_fragment_to_join_this_one?`), but no
/// further back. So a word made of several fragments (`(` `iss91v2` `),`)
/// breaks at the start of the last word of the fragment before the one
/// that overflowed, even when the word began in an earlier fragment.
fn pull_back_limit(
  items : Array[Item],
  start : Int,
  token : Int,
  i : Int,
) -> Int {
  let fragment = items[i].fragment
  if items[token].fragment == fragment {
    return token
  }
  // the first item of the overflowing fragment on this line
  let mut first = i
  while first > start && items[first - 1].fragment == fragment {
    first -= 1
  }
  if first <= token {
    return token
  }
  // the last word of the fragment before it
  let previous = items[first - 1].fragment
  let mut word = first
  while word > start &&
        items[word - 1].fragment == previous &&
        !is_break_char(items[word - 1].unit) {
    word -= 1
  }
  @cmp.maximum(word, token)
}

///|
fn place_line(
  fragments : Array[Fragment],
  faces : Array[Face],
  items : Array[Item],
  from : Int,
  to : Int,
  limit : Double,
  align : Alignment,
  justify : Bool,
) -> Line {
  // trailing spaces are not part of the line
  let mut visible_end = to
  while visible_end > from && is_break_space(items[visible_end - 1].unit) {
    visible_end -= 1
  }
  let mut draw_width = 0.0
  let mut fit_width = 0.0
  let mut spaces = 0
  for i in from..<visible_end {
    draw_width += items[i].draw
    fit_width += items[i].fit
    if is_break_space(items[i].unit) {
      spaces += 1
    }
  }
  let extra = if justify && spaces > 0 && limit > draw_width {
    (limit - draw_width) / spaces.to_double()
  } else {
    0.0
  }
  let offset = match align {
    Center => (limit - draw_width) / 2.0
    Right => limit - draw_width
    _ => 0.0
  }
  let runs : Array[LineRun] = []
  let anchors : Array[(String, Double)] = []
  let mut x = offset
  let mut i = from
  let mut ascender = 0.0
  let mut descender = 0.0
  let mut height = 0.0
  fn measure(fragment : Int) {
    let style = fragments[fragment].style
    let face = faces[fragment]
    let a = face.ascender_pt(style.size)
    let d = face.descender_pt(style.size)
    let h = face.height_pt(style.size)
    if a > ascender {
      ascender = a
    }
    if d > descender {
      descender = d
    }
    if h > height {
      height = h
    }
  }

  while i < visible_end {
    let fragment = items[i].fragment
    if items[i].unit == pad_unit {
      x += items[i].draw
      i += 1
      continue
    }
    match items[i].anchor {
      Some(name) => {
        anchors.push((name, x))
        i += 1
        continue
      }
      None => ()
    }
    let sb = StringBuilder()
    let advances : Array[Double] = []
    let run_x = x
    while i < visible_end &&
          items[i].fragment == fragment &&
          items[i].anchor is None &&
          items[i].unit != pad_unit {
      let item = items[i]
      if item.unit != 0x200B {
        sb.write_char(item.unit.unsafe_to_char())
        let advance = item.draw +
          (if is_break_space(item.unit) { extra } else { 0.0 })
        advances.push(advance)
        x += advance
      }
      i += 1
    }
    if advances.length() > 0 {
      runs.push({
        text: sb.to_string(),
        style: fragments[fragment].style,
        face: faces[fragment],
        x: run_x,
        advances,
        width: x - run_x,
      })
      measure(fragment)
    }
  }
  if runs.is_empty() {
    // an empty line takes the metrics of the fragment it sits in
    let fragment = if from < items.length() {
      items[from].fragment
    } else if from > 0 {
      items[from - 1].fragment
    } else {
      -1
    }
    if fragment >= 0 {
      measure(fragment)
    }
  }
  { runs, anchors, fit_width, ascender, descender, height, }
}
