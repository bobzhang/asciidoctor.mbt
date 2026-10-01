///|
// Headings (asciidoctor-pdf's `ink_heading` and `arrange_heading` in the
// `theme_font :heading, level: n` font).

///|
/// The heading font of `level` and its line height; the heading's font
/// style is inherited by its text as markup would be (`apply_text_decoration
/// font_styles`), so it holds against the text's own font.
fn heading_font(level : Int) -> (Style, Double) {
  let (style, line_height) = theme_font_heading(
    base_style(),
    base_line_height(),
    level,
  )
  ({ ..style, bold: style.doc_bold, italic: style.doc_italic, }, line_height)
}

///|
/// A heading level's key, else the `heading_*` one.
fn heading_key(level : Int, name : String) -> @theme.Value {
  match tv("heading_h\{level}_\{name}") {
    Null => tv("heading_\{name}")
    v => v
  }
}

///|
/// The alignment of a heading of `level`: `heading_h<n>_text_align`, else
/// `heading_text_align`, else the base alignment.
fn Converter::heading_align(self : Converter, level : Int) -> Alignment {
  match value_str(heading_key(level, "text_align")) {
    Some(align) => alignment_of(align)
    None => self.text_align
  }
}

///|
/// asciidoctor-pdf's `@section_indent` (`section_indent`, expanded by
/// `expand_indent_value`): how far the body is indented from the left and
/// the right; section titles, the TOC title, footnotes, the abstract and
/// the index are outdented back.
fn section_indent() -> (Double, Double)? {
  match tv("section_indent") {
    Null | Bool(false) => None
    Array(items) =>
      Some(
        (
          items.get(0).map(v => v.to_f()).unwrap_or(0.0),
          items.get(1).map(v => v.to_f()).unwrap_or(0.0),
        ),
      )
    v => Some((v.to_f(), v.to_f()))
  }
}

///|
/// `outdent_section`: `body` outside the section indent (when `enabled`).
fn[T] Converter::outdent_section(
  self : Converter,
  enabled? : Bool = true,
  body : () -> T,
) -> T {
  match section_indent() {
    Some((left, right)) if enabled => self.flow.indent(-left, -right, body)
    _ => body()
  }
}

///|
/// A heading at `level` (1 is the document title), asciidoctor-pdf's
/// `ink_heading` in the heading font: its top margin (none at the top of a
/// page, where `heading_margin_page_top` applies), the text, its bottom
/// margin; outside the section indent with `outdent`.
fn Converter::ink_heading(
  self : Converter,
  title : String,
  level : Int,
  align? : Alignment,
  category? : String,
  outdent? : Bool = false,
) -> Unit {
  self.outdent_section(enabled=outdent, () => {
    self.ink_heading_text(title, level, align?, category?)
  })
}

///|
fn Converter::ink_heading_text(
  self : Converter,
  title : String,
  level : Int,
  align? : Alignment,
  category? : String,
) -> Unit {
  let (style, line_height) = heading_font(level)
  // a heading of a category of its own (`toc_title`) in that font too
  let (style, line_height) = match category {
    Some(c) => {
      let (s, lh) = theme_font(style, line_height, c)
      ({ ..s, bold: s.doc_bold, italic: s.doc_italic, }, lh)
    }
    None => (style, line_height)
  }
  let flow = self.flow
  if flow.at_page_top() {
    let page_top = value_num(heading_key(level, "margin_page_top")).unwrap_or(
      0.0,
    )
    if page_top > 0.0 {
      flow.move_down(page_top)
    }
  } else {
    flow.margin(value_num(heading_key(level, "margin_top")).unwrap_or(0.0))
  }
  let title = match style.text_transform {
    Some(transform) => transform_text(title, transform)
    None => title
  }
  let style = { ..style, text_transform: None, }
  let face = flow.font(style)
  let category = "heading_h\{level}"
  let start_y = flow.y
  let start_page = flow.page
  // `pad_box <category>_padding`
  let (pad_top, pad_right, pad_bottom, pad_left) = match
    tv(category + "_padding") {
    Null => (0.0, 0.0, 0.0, 0.0)
    v => expand_rect(v)
  }
  flow.move_down(pad_top)
  flow.indent(pad_left, pad_right, () => {
    flow.typeset(
      parse_formatted(title, style, normalize=false),
      line_metrics(line_height, face, style.size),
      style,
      align=align.unwrap_or(self.heading_align(level)),
    )
  })
  if tv(category + "_padding") != Null {
    flow.pad_bottom(pad_bottom)
  }
  // the border around the heading and its padding
  // (`theme_fill_and_stroke_bounds`), from where it started on this page
  match tv(category + "_border_width") {
    Null => ()
    width => {
      let top = if flow.page == start_page { start_y } else { flow.top }
      let color = match tv(category + "_border_color") {
        Null => base_border_color()
        v => value_color(v)
      }
      match color {
        Some(color) =>
          flow
          .items()
          .append(
            border_items(width, color, flow.left, flow.right, top, flow.y),
          )
        None => ()
      }
    }
  }
  flow.margin(value_num(heading_key(level, "margin_bottom")).unwrap_or(0.0))
}

///|
/// asciidoctor-pdf's `fill_and_stroke_bounds` without a fill: a border of
/// `width` (one width, or per side: [top, right, bottom, left], [vertical,
/// horizontal]) around the box; per-side borders are rules, projected by
/// half the adjacent sides' widths.
fn border_items(
  width : @theme.Value,
  color : Color,
  left : Double,
  right : Double,
  top : Double,
  bottom : Double,
) -> Array[@pagelayout.PageItem] {
  match width {
    Array(items) => {
      let w = items.map(v => value_num(v).unwrap_or(0.0))
      let w = if w.length() == 2 { [w[0], w[1], w[0], w[1]] } else { w }
      let at = (i : Int) => w.get(i).unwrap_or(0.0)
      let (wt, wr, wb, wl) = (at(0), at(1), at(2), at(3))
      let items = []
      if wt > 0.0 {
        items.push(hrule(left - wl * 0.5, right - wr * 0.5, top, wt, color))
      }
      if wr > 0.0 {
        items.push(vrule(right, top - wt * 0.5, bottom + wb * 0.5, wr, color))
      }
      if wb > 0.0 {
        items.push(hrule(left - wl * 0.5, right - wr * 0.5, bottom, wb, color))
      }
      if wl > 0.0 {
        items.push(vrule(left, top - wt * 0.5, bottom + wb * 0.5, wl, color))
      }
      items
    }
    v =>
      match value_num(v) {
        Some(w) if w > 0.0 =>
          [
            rect_item(
              left,
              top,
              right - left,
              bottom - top,
              stroke=color,
              stroke_width=w,
            ),
          ]
        _ => []
      }
  }
}

///|
/// asciidoctor-pdf's `arrange_heading` with a numeric (or no)
/// `heading_min_height_after`: keep a heading with the content after it,
/// when there is some, by starting a new page unless the heading, its top
/// margin and that much room below it fit here.
fn Converter::arrange_heading(
  self : Converter,
  title : String,
  hlevel : Int,
  content_after : Bool,
) -> Unit {
  let flow = self.flow
  let (style, line_height) = heading_font(hlevel)
  if style.size > flow.cursor() {
    flow.advance_page()
    return
  }
  let face = flow.font(style)
  let min_height_after = match tv("heading_min_height_after") {
    Str("auto") => {
      unsupported("theme", "heading_min_height_after: auto", self.doc)
      0.0
    }
    v => value_num(v).unwrap_or(0.0)
  }
  let space_below = if min_height_after > 0.0 && content_after {
    min_height_after +
    value_num(heading_key(hlevel, "margin_bottom")).unwrap_or(0.0)
  } else {
    0.0
  }
  let title = match style.text_transform {
    Some(transform) => transform_text(title, transform)
    None => title
  }
  let height = flow.height_of(
    parse_formatted(title, { ..style, text_transform: None, }, normalize=false),
    line_metrics(line_height, face, style.size),
    style,
  )
  let margin_top = value_num(tv("heading_h\{hlevel}_margin_top"))
    .or_some(t_num("heading_margin_top"))
    .unwrap_or(0.0)
  if flow.cursor() < height + margin_top + space_below {
    flow.advance_page()
  }
}
