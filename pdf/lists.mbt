///|
// Lists (asciidoctor-pdf's `convert_ulist`, `convert_olist`,
// `convert_colist`, `convert_dlist` and `convert_list_item`), styled by
// the theme's `list_*`, `ulist_marker_*`, `olist_marker_*`,
// `callout_list_*`, `conum_*` and `description_list_*` keys.

///|
/// asciidoctor-pdf's bullet type for an unordered list (`convert_ulist`):
/// its style's (`bibliography` is a square, an unknown style a disc), else
/// the one for its depth; None for `unstyled` and `no-bullet`, which have
/// no marker and a narrower indent.
fn ulist_marker_type(node : @core.Node, depth : Int) -> String? {
  match node.style {
    Some("circle") => Some("circle")
    Some("square") | Some("bibliography") => Some("square")
    Some("none") => Some("none")
    Some("disc") => Some("disc")
    Some("unstyled") | Some("no-bullet") => None
    Some(_) => Some("disc")
    None =>
      match depth {
        1 => Some("disc")
        2 => Some("circle")
        _ => Some("square")
      }
  }
}

///|
/// A bullet type's marker: the theme's `ulist_marker_<type>_content`, else
/// the built-in bullet (`Bullets`, `BallotBox`).
fn ulist_marker_content(marker_type : String) -> String {
  match t_str("ulist_marker_\{marker_type}_content") {
    Some(content) => content
    None =>
      match marker_type {
        "disc" => "\u{2022}"
        "circle" => "\u{25e6}"
        "square" => "\u{25aa}"
        "checked" => "\u{2611}"
        "unchecked" => "\u{2610}"
        _ => ""
      }
  }
}

///|
/// Nesting level among unordered and ordered lists (asciidoctor-pdf's
/// `list_level`).
fn list_level(node : @core.Node) -> Int {
  let mut level = 1
  let mut ancestor = node.parent()
  while ancestor is Some(a) {
    if a.context == Ulist || a.context == Olist {
      level += 1
    }
    ancestor = a.parent()
  }
  level
}

///|
/// A list item's marker and the theme keys that style it (most specific
/// first: `ulist_marker_disc`, `ulist_marker`).
priv struct Marker {
  text : String
  keys : Array[String]
}

///|
fn Converter::convert_ulist(self : Converter, node : @core.Node) -> Unit {
  self.add_dest(node)
  if node.has_option("checklist") {
    // a checkbox for an item that has one, nothing for the others
    self.convert_list(node, fn(_index, item) {
      if !item.has_attr("checkbox") {
        { text: "", keys: [], }
      } else {
        let kind = if item.has_attr("checked") {
          "checked"
        } else {
          "unchecked"
        }
        {
          text: ulist_marker_content(kind),
          keys: ["ulist_marker_\{kind}", "ulist_marker"],
        }
      }
    })
    return
  }
  match ulist_marker_type(node, list_level(node)) {
    Some(kind) => {
      let marker : Marker = {
        text: ulist_marker_content(kind),
        keys: ["ulist_marker_\{kind}", "ulist_marker"],
      }
      self.convert_list(node, fn(_index, _item) { marker })
    }
    None =>
      self.convert_list(
        node,
        fn(_index, _item) { { text: "", keys: [], } },
        unmarked=true,
      )
  }
}

///|
fn roman(n : Int, upper : Bool) -> String {
  let values = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1]
  let symbols = [
    "m", "cm", "d", "cd", "c", "xc", "l", "xl", "x", "ix", "v", "iv", "i",
  ]
  let sb = StringBuilder()
  let mut rest = n
  for i, value in values {
    while rest >= value {
      sb.write_string(symbols[i])
      rest -= value
    }
  }
  if upper {
    sb.to_string().to_upper()
  } else {
    sb.to_string()
  }
}

///|
fn alpha(n : Int, upper : Bool) -> String {
  let base = if upper { 'A'.to_int() } else { 'a'.to_int() }
  let sb = StringBuilder()
  let mut rest = n
  let digits = []
  while rest > 0 {
    rest -= 1
    digits.push(base + rest % 26)
    rest = rest / 26
  }
  for i = digits.length() - 1; i >= 0; i = i - 1 {
    sb.write_char(digits[i].unsafe_to_char())
  }
  sb.to_string()
}

///|
/// The block before `node` among its parent's blocks.
fn previous_sibling(node : @core.Node) -> @core.Node? {
  guard node.parent() is Some(parent) else { return None }
  let mut previous : @core.Node? = None
  for block in parent.blocks {
    if physical_equal(block, node) {
      return previous
    }
    previous = Some(block)
  }
  None
}

///|
/// The alignment of a list's item text: its `text-*` role, else
/// `list_text_align` (a bibliography's is left).
fn list_text_align(node : @core.Node) -> Alignment? {
  match text_align_from_roles(node.roles()) {
    Some(align) => Some(align)
    None =>
      if node.style == Some("bibliography") {
        Some(Left)
      } else {
        t_str("list_text_align").map(alignment_of)
      }
  }
}

///|
/// asciidoctor-pdf's `convert_colist`: after a code block it moves by
/// `callout_list_margin_top_after_code`; each item's number, in the conum
/// font, is centred in a column as wide as the number and an `x`, and the
/// item's text is indented by that column (`convert_colist_item`); items
/// are `callout_list_item_spacing` apart.
fn Converter::convert_colist(self : Converter, node : @core.Node) -> Unit {
  let flow = self.flow
  if !flow.at_page_top() &&
    previous_sibling(node) is Some(prev) &&
    (prev.context == Listing || prev.context == Literal) {
    flow.margin(t_num_or("callout_list_margin_top_after_code", 0.0))
  }
  self.add_dest(node)
  let (base, base_lh) = theme_font(
    base_style(),
    base_line_height(),
    "callout_list",
  )
  let (conum, conum_lh) = conum_style(base, base_lh)
  let conum_face = flow.font(conum)
  // allocate_space_for_list_item with the conum font's line metrics (in
  // `theme_font :conum`, the base line height is the conum line height)
  let metrics = line_metrics(conum_lh, conum_face, conum.size)
  let marker_color = t_color("callout_list_marker_font_color").unwrap_or(
    conum.color,
  )
  let item_spacing = t_num("callout_list_item_spacing").unwrap_or(
    list_item_spacing(),
  )
  let align = match text_align_from_roles(node.roles()) {
    Some(a) => Some(a)
    None => t_str("list_text_align").map(alignment_of)
  }
  let items = node.items()
  for index, item in items {
    if !flow.at_page_top() &&
      flow.cursor() <
      conum_lh * conum.size + metrics.leading + metrics.padding_top {
      flow.advance_page()
    }
    self.traced(item, "list_item", () => {
      let marker = conum_glyph((index + 1).to_string())
      let marker_width = typeset_lines(
          [{ text: marker + "x", style: conum, anchor: None, }],
          flow.catalog,
          1.0e6,
          Left,
        )[0].fit_width
      let (page, y) = (flow.page, flow.y)
      flow.indent(0.0, flow.width() - marker_width, () => {
        self.ink_prose(
          marker,
          style={ ..conum, color: marker_color, },
          align=Center,
          margin_bottom=0.0,
          normalize=false,
          line_height=conum_lh,
        )
      })
      flow.page = page
      flow.y = y
      let margin_bottom = if index == items.length() - 1 {
        0.0
      } else {
        item_spacing
      }
      flow.indent(marker_width, 0.0, () => {
        match item.text() {
          Some(text) if !text.is_empty() =>
            self.ink_prose(
              text,
              style=base,
              align?,
              margin_bottom~,
              line_height=base_lh,
              normalize_line_height=true,
            )
          _ =>
            if !item.has_blocks() {
              self.ink_prose(
                "",
                style=base,
                margin_bottom~,
                line_height=base_lh,
                normalize_line_height=true,
              )
            }
        }
        self.traverse(item)
      })
    })
  }
  if next_enclosed_block(node) is Some(_) {
    flow.margin(prose_margin_bottom())
  }
}

///|
/// The conum font (`theme_font :conum` over `base`), which names its font
/// (the markup of a callout does), and its line height.
fn conum_style(base : Style, line_height : Double) -> (Style, Double) {
  let (style, line_height) = theme_font(base, line_height, "conum")
  (
    { ..style, font_set: true, bold: style.doc_bold, italic: style.doc_italic, },
    line_height,
  )
}

///|
fn Converter::convert_olist(self : Converter, node : @core.Node) -> Unit {
  self.add_dest(node)
  let start = match node.attr("start") {
    Some(s) => @string.parse_int(s) catch { _ => 1 }
    None => 1
  }
  // a style the marker implies (`a.`) is a Symbol in Asciidoctor, which
  // asciidoctor-pdf's `case node.style when 'loweralpha'` never matches:
  // (the core marks such a style: it has no list marker keyword)
  let style = match node.style {
    Some("loweralpha" | "upperalpha" | "lowerroman" | "upperroman") if node.list_marker_keyword()
      is None => "arabic"
    Some(style) => style
    None => "arabic"
  }
  // `unstyled`, `unnumbered` and `no-bullet` have no numbers and a narrower
  // indent; `none` has empty ones
  let unmarked = style == "unstyled" ||
    style == "unnumbered" ||
    style == "no-bullet"
  self.convert_list(
    node,
    fn(index, _item) {
      let n = start + index
      let text = match style {
        "loweralpha" => "\{alpha(n, false)}."
        "upperalpha" => "\{alpha(n, true)}."
        "lowerroman" => "\{roman(n, false)}."
        "upperroman" => "\{roman(n, true)}."
        // LowercaseGreekA, counted on by `String#next` one code point a step
        // (a start below 1 does not count back from a letter)
        "lowergreek" =>
          "\{Int::unsafe_to_char(0x3B1 + @cmp.maximum(start - 1, 0) + index)}."
        "none" | "unstyled" | "unnumbered" | "no-bullet" => ""
        "decimal" => if n < 10 { "0\{n}." } else { "\{n}." }
        _ => "\{n}."
      }
      { text, keys: if text == "" { [] } else { ["olist_marker"] }, }
    },
    unmarked~,
  )
}

///|
fn Converter::convert_list(
  self : Converter,
  node : @core.Node,
  marker_of : (Int, @core.Node) -> Marker,
  unmarked? : Bool = false,
) -> Unit {
  let flow = self.flow
  if node.has_title() {
    self.ink_caption(node.title().unwrap_or(""), category="list")
  }
  let base = base_style()
  let face = flow.font(base)
  let metrics = line_metrics(base_line_height(), face, base.size)
  // a list without markers is indented less: not at all when unstyled,
  // else by the room a marker and an `x` would take less
  let indent = if !unmarked {
    list_indent()
  } else if node.style == Some("unstyled") {
    0.0
  } else {
    let sample = if node.context == Ulist { "\u{2022}x" } else { "1.x" }
    @cmp.maximum(list_indent() - flow.width_of(sample, base), 0.0)
  }
  // the items' text (not their blocks) aligns by the list's role, a
  // bibliography's to the left, else by `list_text_align`
  let align = list_text_align(node)
  flow.indent(indent, 0.0, fn() {
    for index, item in node.items() {
      // allocate_space_for_list_item
      if !flow.at_page_top() &&
        flow.cursor() <
        base_line_height() * base.size + metrics.leading + metrics.padding_top {
        flow.advance_page()
      }
      let marker = marker_of(index, item)
      self.traced(item, "list_item", () => {
        self.convert_list_item(item, marker, metrics, align?)
      })
    }
  })
  if !list_nested(node) && next_enclosed_block(node) is Some(_) {
    self.flow.margin(prose_margin_bottom())
  }
}

///|
/// asciidoctor-pdf's `List#nested?`: the list sits in a list item.
fn list_nested(node : @core.Node) -> Bool {
  node.parent() is Some(parent) && parent.context == ListItem
}

///|
/// Ruby's `ListItem#compound?`: blocks other than a single nested list.
fn is_compound_item(item : @core.Node) -> Bool {
  match item.blocks {
    [] => false
    [only] => !(only.context == Ulist || only.context == Olist)
    _ => true
  }
}

///|
/// The style of a list marker: the current font, in `list_marker_font_color`,
/// with the marker's own `font_color`, `font_family`, `font_size`,
/// `font_style` and `line_height` keys (`keys`, most specific first); and
/// its line height.
fn marker_style(base : Style, keys : Array[String]) -> (Style, Double) {
  let key = (prop : String) => {
    for k in keys {
      match tv("\{k}_\{prop}") {
        Null => ()
        v => return v
      }
    }
    Null
  }
  let mut style = {
    ..base,
    color: t_color("list_marker_font_color").unwrap_or(base.color),
  }
  match value_color(key("font_color")) {
    Some(color) => style = { ..style, color, }
    None => ()
  }
  match value_str(key("font_family")) {
    Some(family) => style = { ..style, family, }
    None => ()
  }
  match resolve_font_size(key("font_size"), style.size) {
    Some(size) => style = { ..style, size, }
    None => ()
  }
  match value_str(key("font_style")) {
    Some(fs) => {
      let (doc_bold, doc_italic) = font_style_of(fs)
      style = { ..style, doc_bold, doc_italic, }
    }
    None => ()
  }
  (style, value_num(key("line_height")).unwrap_or(base_line_height()))
}

///|
fn Converter::convert_list_item(
  self : Converter,
  item : @core.Node,
  marker : Marker,
  _metrics : LineMetrics,
  align? : Alignment,
) -> Unit {
  let flow = self.flow
  let base = base_style()
  if !marker.text.is_empty() {
    // the marker hangs in the indent, right-aligned one `x` before the
    // text, in a float that does not move the cursor
    let (mstyle, mline_height) = marker_style(base, marker.keys)
    let face = flow.font(base)
    let gap = face.prawn_width('x'.to_int()) * base.size / 1000.0
    let mface = flow.font(mstyle)
    let mmetrics = line_metrics(mline_height, mface, mstyle.size)
    let lines = typeset_lines(
      [{ text: marker.text, style: mstyle, anchor: None, }],
      flow.catalog,
      1000.0,
      Left,
    )
    let width = if lines.length() > 0 { lines[0].fit_width } else { 0.0 }
    let y = flow.y
    let page = flow.page
    // the marker's text box stretches to the bottom margin: when its line
    // does not fit above it, the marker goes to the top of the next page,
    // where the item's text will follow it (`flow_bounding_box`)
    let a = mface.ascender_pt(mstyle.size)
    if !flow.at_page_top() &&
      mmetrics.padding_top + a + mface.descender_pt(mstyle.size) >
      flow.cursor() + 0.0001 {
      flow.advance_page()
    }
    let baseline = flow.y + mmetrics.padding_top + a
    if lines.length() > 0 {
      // set with `character_spacing: -0.5`, which Prawn does not count
      // after the last glyph: right-aligned in a box as wide as the marker
      // without it, the text starts 0.5pt in per glyph after the first,
      // plus the 0.5pt asciidoctor-pdf adds back
      // (`character_spacing_correction`)
      let mut glyphs = 0
      for run in lines[0].runs {
        for i in 0..<run.advances.length() {
          run.advances[i] -= 0.5
          glyphs += 1
        }
      }
      let shift = 0.5 * glyphs.to_double()
      flow.ink_line(lines[0], flow.left - width - gap + shift, baseline)
    }
    flow.page = page
    flow.y = y
  }
  let margin_bottom = if is_compound_item(item) {
    prose_margin_bottom()
  } else if next_enclosed_block(item, descend=true) is Some(_) {
    list_item_spacing()
  } else {
    0.0
  }
  match item.text() {
    Some(text) if !text.is_empty() =>
      self.ink_prose(text, align?, margin_bottom~, normalize_line_height=true)
    // an item without text or blocks still takes a line (`DummyText`)
    _ =>
      if !item.has_blocks() {
        self.ink_prose("", margin_bottom~, normalize_line_height=true)
      }
  }
  self.traverse(item)
}

///|
/// The term font of a description list (`theme_font
/// :description_list_term`), whose font style its text inherits as markup,
/// and its line height.
fn dlist_term_style() -> (Style, Double) {
  let (style, line_height) = theme_font(
    base_style(),
    base_line_height(),
    "description_list_term",
  )
  (
    {
      ..style,
      bold: style.bold || style.doc_bold,
      italic: style.italic || style.doc_italic,
    },
    line_height,
  )
}

///|
fn Converter::convert_dlist(self : Converter, node : @core.Node) -> Unit {
  self.add_dest(node)
  let flow = self.flow
  if node.has_title() {
    self.ink_caption(node.title().unwrap_or(""), category="description_list")
  }
  if node.style == Some("horizontal") {
    self.convert_horizontal_dlist(node)
    return
  }
  let (term_style, term_lh) = dlist_term_style()
  let term_spacing = description_list_term_spacing()
  // `height_of_typeset_text 'A'` in the term font and in the prose font
  let one_line = fn(style : Style, lh : Double) {
    flow.height_of(
      [{ text: "A", style, anchor: None, }],
      line_metrics(lh, flow.font(style), style.size),
      style,
    )
  }
  let term_height = one_line(term_style, term_lh)
  let prose_height = one_line(base_style(), base_line_height())
  for entry in node.dlist_items {
    // keep the terms (and the first line of the description) together
    let desc_text = match entry.desc {
      Some(desc) => desc.text().map(t => !t.is_empty()).unwrap_or(false)
      None => false
    }
    let nlines = entry.terms.length() + (if desc_text { 1 } else { 0 })
    let blocks_only = match entry.desc {
      Some(desc) => !desc_text && desc.has_blocks()
      None => false
    }
    let needed = nlines.to_double() * term_height +
      (nlines - 1).to_double() * term_spacing +
      (if blocks_only { term_spacing + prose_height } else { 0.0 })
    if !flow.at_page_top() && flow.cursor() < needed {
      flow.advance_page()
    }
    for index, term in entry.terms {
      if index > 0 {
        flow.margin(term_spacing)
      }
      self.ink_prose(
        term.text().unwrap_or(""),
        style=term_style,
        align=Left,
        margin_bottom=0.0,
        line_height=term_lh,
        normalize_line_height=true,
      )
    }
    match entry.desc {
      Some(desc) =>
        flow.indent(description_list_description_indent(), 0.0, fn() {
          flow.margin(term_spacing)
          let margin_bottom = if next_enclosed_block(desc, descend=true)
            is Some(_) {
            prose_margin_bottom()
          } else {
            0.0
          }
          match desc.text() {
            Some(text) if !text.is_empty() =>
              self.ink_prose(text, margin_bottom~, normalize_line_height=true)
            _ => ()
          }
          self.traverse(desc)
        })
      None => ()
    }
  }
  if !list_nested(node) && next_enclosed_block(node) is Some(_) {
    flow.margin(prose_margin_bottom())
  }
}

///|
fn Converter::convert_horizontal_dlist(
  self : Converter,
  node : @core.Node,
) -> Unit {
  let flow = self.flow
  let (term_style, term_lh) = dlist_term_style()
  let term_spacing = description_list_term_spacing()
  let mut term_width = 0.0
  for entry in node.dlist_items {
    for term in entry.terms {
      let lines = typeset_lines(
        parse_formatted(term.text().unwrap_or(""), term_style),
        flow.catalog,
        1.0e6,
        Left,
      )
      for line in lines {
        if line.fit_width > term_width {
          term_width = line.fit_width
        }
      }
    }
  }
  let column = @cmp.minimum(term_width + 20.0, flow.width() * 0.5 - 20.0)
  // `height_of_typeset_text 'A'` in the term font and in the prose font
  let one_line = fn(style : Style, lh : Double) {
    flow.height_of(
      [{ text: "A", style, anchor: None, }],
      line_metrics(lh, flow.font(style), style.size),
      style,
    )
  }
  let term_height = one_line(term_style, term_lh)
  let prose_height = one_line(base_style(), base_line_height())
  for entry in node.dlist_items {
    // the terms (and a line of the description) must fit, else the entry
    // starts on the next page
    let terms = entry.terms.length().to_double()
    let needed = @cmp.maximum(
      (term_spacing + term_height) * terms - term_spacing,
      if entry.desc is Some(_) {
        prose_height
      } else {
        0.0
      },
    )
    if !flow.at_page_top() && flow.cursor() < needed {
      flow.advance_page()
    }
    let start_page = flow.page
    let start_y = flow.y
    flow.indent(10.0, flow.width() - column, fn() {
      for index, term in entry.terms {
        if index > 0 {
          flow.margin(term_spacing)
        }
        self.ink_prose(
          term.text().unwrap_or(""),
          style=term_style,
          align=Left,
          margin_bottom=0.0,
          line_height=term_lh,
          normalize_line_height=true,
        )
      }
    })
    let (term_page, term_y) = (flow.page, flow.y)
    match entry.desc {
      Some(desc) => {
        flow.page = start_page
        flow.y = start_y
        // traverse_list_item: the description's text takes the prose
        // margin below when something follows it in the entry
        let margin_bottom = if next_enclosed_block(desc, descend=true)
          is Some(_) {
          prose_margin_bottom()
        } else {
          0.0
        }
        flow.indent(column + 10.0, 10.0, fn() {
          match desc.text() {
            Some(text) if !text.is_empty() =>
              self.ink_prose(text, margin_bottom~, normalize_line_height=true)
            _ =>
              if !desc.has_blocks() {
                self.ink_prose("", margin_bottom~, normalize_line_height=true)
              }
          }
          self.traverse(desc)
        })
        // the cursor ends below the last term
        if flow.page < term_page || (flow.page == term_page && flow.y < term_y) {
          flow.page = term_page
          flow.y = term_y
        }
      }
      None => ()
    }
  }
  if !list_nested(node) && next_enclosed_block(node) is Some(_) {
    flow.margin(prose_margin_bottom())
  }
}
