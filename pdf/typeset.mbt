///|
// Line breaking of formatted text, following Prawn's greedy wrap: break
// after spaces, hyphens and zero-width spaces; a word longer than the line
// wraps by character; trailing spaces do not count; a justified line
// widens its spaces, except on the last line of a paragraph and before a
// hard break.
//
// Two widths are tracked per character. `fit` is Prawn's (glyph widths
// truncated to 1/1000 em) and decides where lines break, so breaks match
// Ruby; `draw` is the width the PDF declares for the glyph, and places
// glyphs, so the emitted text needs no per-glyph correction. Both include
// kerning with the next character of the same fragment.

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
  fit : Double
  draw : Double
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
/// Whether a line may break after `items[i]`: the end of a run of hyphens
/// that follows a word character (Prawn's `[^break]+-+` token). A run that
/// starts a word, as in `--staged`, stays with the word.
fn breaks_after_hyphen(items : Array[Item], i : Int) -> Bool {
  if items[i].unit != 0x2D {
    return false
  }
  if i + 1 < items.length() && items[i + 1].unit == 0x2D {
    return false
  }
  let mut j = i
  while j >= 0 && items[j].unit == 0x2D {
    j -= 1
  }
  j >= 0 &&
  !is_break_space(items[j].unit) &&
  items[j].unit != 0x200B &&
  !items[j].hard_break
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
    let face = catalog.face(style.family, style.bold, style.italic)
    faces.push(face)
    match fragment.anchor {
      Some(name) => {
        items.push({
          unit: 0,
          fragment: index,
          fit: 0.0,
          draw: 0.0,
          hard_break: false,
          anchor: Some(name),
        })
        continue
      }
      None => ()
    }
    let text = fragment.text
    let n = text.length()
    let scale = style.size / 1000.0
    let pad : Item = {
      unit: pad_unit,
      fragment: index,
      fit: style.border_offset,
      draw: style.border_offset,
      hard_break: false,
      anchor: None,
    }
    if style.border_offset > 0.0 && n > 0 {
      items.push(pad)
    }
    for i in 0..<n {
      let unit = text[i].to_int()
      if unit == 0x0A {
        items.push({
          unit,
          fragment: index,
          fit: 0.0,
          draw: 0.0,
          hard_break: true,
          anchor: None,
        })
        continue
      }
      // a zero-width space is a break opportunity that draws nothing
      if unit == 0x200B || (unit >= 0xDC00 && unit <= 0xDFFF) {
        items.push({
          unit,
          fragment: index,
          fit: 0.0,
          draw: 0.0,
          hard_break: false,
          anchor: None,
        })
        continue
      }
      let cp = if unit >= 0xD800 && unit <= 0xDBFF && i + 1 < n {
        0x10000 + ((unit - 0xD800) << 10) + (text[i + 1].to_int() - 0xDC00)
      } else {
        unit
      }
      let next = if i + 1 < n { text[i + 1].to_int() } else { -1 }
      let kern = if next >= 0 { face.kerning(cp, next) } else { 0.0 }
      // Prawn measures each word and each run of spaces on its own, so a
      // pair straddling a word boundary kerns when drawn but not when
      // fitting
      let boundary = is_break_space(unit) != is_break_space(next) ||
        unit == 0x2D
      items.push({
        unit,
        fragment: index,
        fit: (face.prawn_width(cp) + (if boundary { 0.0 } else { kern })) *
        scale,
        draw: (face.drawn_width(cp) + kern) * scale,
        hard_break: false,
        anchor: None,
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
  let ranges : Array[(Int, Int, Bool)] = [] // start, end, ended by hard break
  let n = items.length()
  // spaces a line starts with are dropped, as Prawn strips the first
  // fragment of each line (anchors in front of them notwithstanding)
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
      if is_break_space(item.unit) {
        if !visible {
          // dropped: it becomes a zero-width space, which draws nothing
          items[i] = { ..item, unit: 0x200B, fit: 0.0, draw: 0.0, }
        } else {
          w += item.fit
          last_break = i + 1
        }
        i += 1
        continue
      }
      if w + item.fit > limit + 0.0001 && visible {
        end = if last_break > start { last_break } else { i }
        break
      }
      w += item.fit
      if item.anchor is None {
        visible = true
      }
      if item.unit == 0x200B || breaks_after_hyphen(items, i) {
        last_break = i + 1
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
