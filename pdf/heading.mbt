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
/// A heading at `level` (1 is the document title), asciidoctor-pdf's
/// `ink_heading` in the heading font: its top margin (none at the top of a
/// page, where `heading_margin_page_top` applies), the text, its bottom
/// margin.
fn Converter::ink_heading(
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
  if t_set("heading_h\{level}_padding") ||
    t_set("heading_h\{level}_border_width") {
    unsupported("theme", "heading_h\{level} padding or border", self.doc)
  }
  let title = match style.text_transform {
    Some(transform) => transform_text(title, transform)
    None => title
  }
  let style = { ..style, text_transform: None, }
  let face = flow.font(style)
  flow.typeset(
    parse_formatted(title, style, normalize=false),
    line_metrics(line_height, face, style.size),
    style,
    align=align.unwrap_or(self.heading_align(level)),
  )
  flow.margin(value_num(heading_key(level, "margin_bottom")).unwrap_or(0.0))
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
