///|
// The block-level converter: a walk over the document tree that inks each
// block into the page flow, following asciidoctor-pdf's `convert_*`
// methods and its default theme.

///|
priv struct Converter {
  doc : @core.Node
  flow : Flow
  outline : Array[@pdf.OutlineEntry]
  /// asciidoctor-pdf's `@bottom_gutters`: the block whose last line must
  /// keep clear of an enclosing padding, and by how much
  gutters : Array[(@core.Node, Double)?]
}

///|
/// Convert a document loaded with `backend=pdf` (see `register`) to PDF.
pub fn convert_document(doc : @core.Node, catalog : FontCatalog) -> Bytes raise {
  let flow = Flow::new(catalog)
  let c : Converter = { doc, flow, outline: [], gutters: [], }
  flow.start_new_page()
  // the top of the document, for `<<_top>>`-style references and the
  // outline's title entry
  flow.add_anchor("__top", 0.0, 0.0)
  let doctitle = doc.doctitle()
  if doc.has_header() && !doc.notitle() {
    match doctitle {
      Some(title) => c.ink_heading(title, 1, align=Center)
      None => ()
    }
  }
  match doctitle {
    Some(title) =>
      c.outline.push({ title: sanitize(title), level: 0, anchor: "__top", })
    None => ()
  }
  c.traverse(doc)
  c.ink_footnotes()
  // a page started but never written to is dropped
  let pages = flow.model.pages
  if pages.length() > 1 &&
    pages[pages.length() - 1].items.iter().all(fn(i) { i is Anchor(_) }) {
    ignore(pages.pop())
  }
  c.ink_footers()
  let info = [("Producer", "asciidoctor.mbt (spike)")]
  match doctitle {
    Some(title) => info.push(("Title", sanitize(title)))
    None => ()
  }
  match doc.attr("author") {
    Some(author) => info.push(("Author", author))
    None => ()
  }
  @pdf.render_pdf(flow.model, outline=c.outline, info~)
}

///|
/// Strip markup and decode references: the plain text of formatted text.
fn sanitize(text : String) -> String {
  let sb = StringBuilder()
  let mut in_tag = false
  for c in text {
    if c == '<' {
      in_tag = true
    } else if c == '>' && in_tag {
      in_tag = false
    } else if !in_tag {
      sb.write_char(c)
    }
  }
  decode_entities(sb.to_string())
}

///|
fn Converter::traverse(self : Converter, node : @core.Node) -> Unit {
  if node.has_blocks() {
    for block in node.blocks {
      self.convert_block(block)
    }
  } else if node.content_model != Compound {
    // a simple block (e.g. `NOTE: text`) carries its text itself
    let text = node.content()
    if !text.is_empty() {
      self.ink_prose(
        text,
        align=role_align(node.roles(), Justify),
        margin_bottom=0.0,
        bottom_gutter=self.gutter(node),
      )
    }
  }
}

///|
fn Converter::convert_block(self : Converter, node : @core.Node) -> Unit {
  match node.context {
    Section => self.convert_section(node)
    Preamble => self.convert_preamble(node)
    Paragraph => self.convert_paragraph(node)
    Listing | Literal => self.convert_code(node)
    Ulist => self.convert_ulist(node)
    Olist | Colist => self.convert_olist(node)
    Dlist => self.convert_dlist(node)
    Table => self.convert_table(node)
    Admonition => self.convert_admonition(node)
    Image => self.convert_image(node)
    Example => self.convert_example(node)
    Sidebar => self.convert_sidebar(node)
    Quote | Verse => self.convert_quote(node)
    Open => self.convert_open(node)
    ThematicBreak => self.convert_thematic_break(node)
    PageBreak => if !self.flow.at_page_top() { self.flow.advance_page() }
    FloatingTitle => {
      self.add_dest(node)
      self.ink_heading(node.title().unwrap_or(""), node.level + 1)
    }
    _ => ()
  }
}

///|
/// A named destination for the block at the cursor (asciidoctor-pdf's
/// `add_dest_for_block`).
fn Converter::add_dest(self : Converter, node : @core.Node) -> Unit {
  match node.id {
    Some(id) => {
      let x = if self.flow.left <= margin_side { 0.0 } else { self.flow.left }
      let y = if self.flow.at_page_top() { 0.0 } else { self.flow.y }
      self.flow.add_anchor(id, x, y)
    }
    None => ()
  }
}

///|
/// The next block after `block` in reading order, crossing out of the
/// containers that do not end a vertical rhythm unit
/// (asciidoctor-pdf's `next_enclosed_block`). Decides whether a block gets
/// its bottom margin.
fn next_enclosed_block(
  block : @core.Node,
  descend? : Bool = false,
) -> @core.Node? {
  if block.context == Document {
    return None
  }
  guard block.parent() is Some(parent) else { return None }
  let is_list_item = block.context == ListItem
  if is_list_item && descend && block.has_blocks() {
    return Some(block.blocks[0])
  }
  let siblings : Array[@core.Node] = if parent.context == Dlist {
    let flat = []
    for item in parent.dlist_items {
      flat.append(item.terms)
      match item.desc {
        Some(desc) => flat.push(desc)
        None => ()
      }
    }
    flat
  } else if is_list_item {
    parent.items()
  } else {
    parent.blocks
  }
  let mut index = -1
  for i, sibling in siblings {
    if physical_equal(sibling, block) {
      index = i
      break
    }
  }
  if index >= 0 && index < siblings.length() - 1 {
    return Some(siblings[index + 1])
  }
  match parent.context {
    ListItem | Section => next_enclosed_block(parent)
    Open if parent.style != Some("abstract") => next_enclosed_block(parent)
    _ =>
      if is_list_item {
        match parent.parent() {
          Some(grandparent) if grandparent.context == ListItem =>
            next_enclosed_block(grandparent)
          _ => None
        }
      } else {
        None
      }
  }
}

///|
/// `theme_margin :block, :bottom, next_enclosed_block(node)`.
fn Converter::block_margin_bottom(self : Converter, node : @core.Node) -> Unit {
  if next_enclosed_block(node) is Some(_) {
    self.flow.margin(block_margin_bottom)
  }
}

///|
fn base_style() -> Style {
  Style::new()
}

///|
/// Ink formatted text as prose (asciidoctor-pdf's `ink_prose`).
fn Converter::ink_prose(
  self : Converter,
  text : String,
  style? : Style = base_style(),
  align? : Alignment = Justify,
  margin_bottom? : Double = prose_margin_bottom,
  line_height? : Double = base_line_height,
  normalize? : Bool = true,
  bottom_gutter? : Double = 0.0,
) -> Unit {
  let face = self.flow.font(style)
  let metrics = line_metrics(line_height, face, style.size)
  self.flow.typeset(
    parse_formatted(text, style, normalize~),
    metrics,
    style,
    align~,
    bottom_gutter~,
  )
  self.flow.margin(margin_bottom)
}

///|
/// Enter a padded box whose bottom padding is `bottom` (asciidoctor-pdf's
/// `pad_box`): the block that will ink its last line gets a gutter.
fn Converter::push_gutter(
  self : Converter,
  node : @core.Node,
  bottom : Double,
) -> Unit {
  if node.content_model != Compound {
    self.gutters.push(Some((node, bottom)))
  } else if node.blocks.last() is Some(last) && last.context == Paragraph {
    self.gutters.push(Some((last, bottom)))
  } else {
    self.gutters.push(None)
  }
}

///|
fn Converter::pop_gutter(self : Converter) -> Unit {
  ignore(self.gutters.pop())
}

///|
/// The bottom gutter of `node`, when it is the last block of the
/// innermost padded box.
fn Converter::gutter(self : Converter, node : @core.Node) -> Double {
  match self.gutters.last() {
    Some(Some((last, bottom))) if physical_equal(last, node) => bottom
    _ => 0.0
  }
}

///|
/// A heading at `level` (1 is the document title), asciidoctor-pdf's
/// `ink_heading` with the heading theme font.
fn Converter::ink_heading(
  self : Converter,
  title : String,
  level : Int,
  align? : Alignment = Left,
) -> Unit {
  let style = Style::new(size=heading_font_size(level), bold=true)
  let flow = self.flow
  if !flow.at_page_top() {
    flow.margin(heading_margin_top)
  }
  let face = flow.font(style)
  flow.typeset(
    parse_formatted(title, style),
    line_metrics(1.0, face, style.size),
    style,
    align~,
  )
  flow.margin(heading_margin_bottom)
}

///|
fn Converter::section_title(self : Converter, section : @core.Node) -> String {
  let doc = self.doc
  let sectnumlevels = doc.attributes
    .get("sectnumlevels")
    .map(v => v.to_i())
    .unwrap_or(3)
  let title = section.title().unwrap_or("")
  if section.caption() is Some(_) {
    section.captioned_title()
  } else if section.numbered != NotNumbered && section.level <= sectnumlevels {
    "\{section.sectnum()} \{title}"
  } else {
    title
  }
}

///|
fn Converter::convert_section(self : Converter, section : @core.Node) -> Unit {
  let flow = self.flow
  let title = self.section_title(section)
  let hlevel = section.level + 1
  let hidden = section.has_option("notitle")
  if !hidden && !flow.at_page_top() {
    // asciidoctor-pdf's `arrange_heading`: keep the heading with the
    // content after it
    let size = heading_font_size(hlevel)
    if size > flow.cursor() {
      flow.advance_page()
    } else {
      let style = Style::new(size~, bold=true)
      let face = flow.font(style)
      let space_below = if section.has_blocks() {
        heading_min_height_after + heading_margin_bottom
      } else {
        0.0
      }
      let height = flow.height_of(
        parse_formatted(title, style),
        line_metrics(1.0, face, size),
        style,
      )
      if flow.cursor() < height + heading_margin_top + space_below {
        flow.advance_page()
      }
    }
  }
  match section.id {
    Some(id) => {
      let y = if flow.at_page_top() { 0.0 } else { flow.y }
      flow.add_anchor(id, 0.0, y)
      if section.level <= 2 {
        self.outline.push({
          title: sanitize(title),
          level: section.level - 1,
          anchor: id,
        })
      }
    }
    None => ()
  }
  if !hidden {
    self.ink_heading(title, hlevel)
  }
  self.traverse(section)
}

///|
fn Converter::convert_preamble(self : Converter, node : @core.Node) -> Unit {
  // the first paragraph of a preamble leads when the document has sections
  if node.blocks.length() > 0 &&
    node.blocks[0].context == Paragraph &&
    self.doc.has_sections() &&
    node.blocks[0].role() is None {
    node.blocks[0].set_role("lead")
  }
  self.traverse(node)
  self.block_margin_bottom(node)
}

///|
/// The prose style of a paragraph's roles.
fn role_style(roles : Array[String], base : Style) -> Style {
  let mut style = base
  for role in roles {
    match role {
      "lead" => style = { ..style, size: (base_font_size * 1.25).round(), }
      "big" => style = { ..style, size: style.size * 1.2, }
      "small" => style = { ..style, size: style.size * 0.8, }
      "underline" => style = { ..style, underline: true, }
      "line-through" => style = { ..style, strike: true, }
      "subtitle" =>
        style = { ..style, size: style.size * 0.8, color: rgb_hex(0x999999), }
      _ => ()
    }
  }
  style
}

///|
fn role_align(roles : Array[String], default : Alignment) -> Alignment {
  for role in roles {
    match role {
      "text-left" => return Left
      "text-right" => return Right
      "text-center" => return Center
      "text-justify" => return Justify
      _ => ()
    }
  }
  default
}

///|
fn Converter::convert_paragraph(self : Converter, node : @core.Node) -> Unit {
  self.add_dest(node)
  let roles = node.roles()
  if node.has_title() {
    self.ink_caption(node.title().unwrap_or(""))
  }
  self.ink_prose(
    node.content(),
    style=role_style(roles, base_style()),
    align=role_align(roles, Justify),
    margin_bottom=0.0,
    bottom_gutter=self.gutter(node),
  )
  if next_enclosed_block(node) is Some(_) {
    self.flow.margin(prose_margin_bottom)
  }
}

///|
/// A block title (asciidoctor-pdf's `ink_caption`, top end): italic,
/// slightly smaller, with the inside margin below.
fn Converter::ink_caption(
  self : Converter,
  text : String,
  bottom? : Bool = false,
) -> Unit {
  let style = Style::new(size=caption_font_size, italic=true)
  if bottom {
    self.flow.margin(caption_margin_inside)
  }
  self.ink_prose(
    text,
    style~,
    align=Left,
    margin_bottom=if bottom { 0.0 } else { caption_margin_inside },
    normalize=false,
  )
}

///|
/// asciidoctor-pdf's `guard_indentation`: tabs expand to 4-column stops,
/// then the first space of each line becomes a no-break space so that the
/// line keeps its leading spaces.
fn guard_indentation(text : String) -> String {
  let sb = StringBuilder()
  let mut column = 0
  let mut at_line_start = true
  for c in text {
    if c == '\t' {
      let spaces = 4 - column % 4
      for k in 0..<spaces {
        sb.write_char(if at_line_start && k == 0 { '\u{a0}' } else { ' ' })
      }
      at_line_start = false
      column += spaces
      continue
    }
    if at_line_start && c == ' ' {
      sb.write_char('\u{a0}')
    } else {
      sb.write_char(c)
    }
    at_line_start = c == '\n'
    column = if c == '\n' { 0 } else { column + 1 }
  }
  sb.to_string()
}

///|
fn Converter::convert_code(self : Converter, node : @core.Node) -> Unit {
  let flow = self.flow
  let style = Style::new(family=mono_font_family, size=code_font_size)
  let face = flow.font(style)
  let metrics = line_metrics(code_line_height, face, code_font_size)
  let fragments = parse_formatted(
    guard_indentation(node.content()),
    style,
    normalize=false,
  )
  // arrange_block's dry run: when not even the first line (with the
  // caption above it) fits here, the block starts on the next page; a
  // single line must also leave room for the bottom padding (its gutter)
  let single = typeset_lines(
      fragments,
      flow.catalog,
      flow.width() - 2.0 * code_padding,
      Left,
    ).length() <=
    1
  let caption_height = if node.has_title() {
    let caption_style = Style::new(size=caption_font_size, italic=true)
    flow.height_of(
      parse_formatted(node.captioned_title(), caption_style, normalize=false),
      line_metrics(
        base_line_height,
        flow.font(caption_style),
        caption_font_size,
      ),
      caption_style,
    ) +
    caption_margin_inside
  } else {
    0.0
  }
  let first_line = caption_height +
    code_padding +
    metrics.padding_top +
    face.ascender_pt(code_font_size) +
    face.descender_pt(code_font_size) +
    (if single { code_padding } else { 0.0 })
  if !flow.at_page_top() && flow.cursor() < first_line {
    flow.advance_page()
  }
  if node.has_title() {
    self.ink_caption(node.captioned_title())
  }
  self.add_dest(node)
  let start = flow.mark()
  let (left, right) = (flow.left, flow.right)
  flow.move_down(code_padding)
  flow.indent(code_padding, code_padding, fn() {
    flow.typeset(fragments, metrics, style, bottom_gutter=code_padding)
  })
  flow.pad_bottom(code_padding)
  flow.underlay(start, fn(top, bottom, first, last) {
    let items = [
      rect_item(
        left,
        top,
        right - left,
        bottom - top,
        fill=code_background_color,
        stroke=code_border_color,
        stroke_width=code_border_width,
      ),
    ]
    // where the block breaks across pages, a dashed line in the background
    // colour cuts into the border (theme_fill_and_stroke_block)
    let inset = 4.0 + code_border_width
    let width = code_border_width * 1.2
    if !first {
      items.append(
        dashed_hrule(left + inset, right - inset, top, width, code_background_color),
      )
    }
    if !last {
      items.append(
        dashed_hrule(
          left + inset,
          right - inset,
          bottom,
          width,
          code_background_color,
        ),
      )
    }
    items
  })
  self.block_margin_bottom(node)
}

///|
fn ulist_marker(node : @core.Node, depth : Int) -> String {
  if node.has_option("checklist") {
    return "•"
  }
  match node.style {
    Some("circle") => "◦"
    Some("square") | Some("bibliography") => "▪"
    Some("none") | Some("unstyled") | Some("no-bullet") => ""
    Some("disc") => "•"
    _ =>
      match depth {
        1 => "•"
        2 => "◦"
        _ => "▪"
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
fn Converter::convert_ulist(self : Converter, node : @core.Node) -> Unit {
  self.add_dest(node)
  let marker = ulist_marker(node, list_level(node))
  self.convert_list(node, fn(_index, item) {
    if node.has_option("checklist") && item.has_attr("checkbox") {
      if item.has_attr("checked") {
        "☑"
      } else {
        "☐"
      }
    } else {
      marker
    }
  })
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
fn Converter::convert_olist(self : Converter, node : @core.Node) -> Unit {
  self.add_dest(node)
  let start = match node.attr("start") {
    Some(s) => @string.parse_int(s) catch { _ => 1 }
    None => 1
  }
  let style = node.style.unwrap_or("arabic")
  let colist = node.context == Colist
  if colist && !self.flow.at_page_top() {
    // callout lists hug the code block above (callout_list_margin_top_after_code)
    self.flow.move_down(-block_margin_bottom / 2.0)
  }
  self.convert_list(node, fn(index, _item) {
    let n = start + index
    if colist {
      conum_glyph(n.to_string())
    } else {
      match style {
        "loweralpha" => "\{alpha(n, false)}."
        "upperalpha" => "\{alpha(n, true)}."
        "lowerroman" => "\{roman(n, false)}."
        "upperroman" => "\{roman(n, true)}."
        "none" | "unstyled" | "unnumbered" | "no-bullet" => ""
        "decimal" => if n < 10 { "0\{n}." } else { "\{n}." }
        _ => "\{n}."
      }
    }
  })
}

///|
fn Converter::convert_list(
  self : Converter,
  node : @core.Node,
  marker_of : (Int, @core.Node) -> String,
) -> Unit {
  let flow = self.flow
  if node.has_title() {
    self.ink_caption(node.title().unwrap_or(""))
  }
  let base = base_style()
  let face = flow.font(base)
  let metrics = line_metrics(base_line_height, face, base.size)
  flow.indent(list_indent, 0.0, fn() {
    for index, item in node.items() {
      // allocate_space_for_list_item
      if !flow.at_page_top() &&
        flow.cursor() <
        base_line_height * base.size + metrics.leading + metrics.padding_top {
        flow.advance_page()
      }
      self.convert_list_item(item, marker_of(index, item), metrics)
    }
  })
  if !list_nested(node) && next_enclosed_block(node) is Some(_) {
    self.flow.margin(prose_margin_bottom)
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
fn Converter::convert_list_item(
  self : Converter,
  item : @core.Node,
  marker : String,
  metrics : LineMetrics,
) -> Unit {
  let flow = self.flow
  let base = base_style()
  if !marker.is_empty() {
    // the marker hangs in the indent, right-aligned one `x` before the
    // text, in a float that does not move the cursor
    let face = flow.font(base)
    let gap = face.prawn_width('x'.to_int()) * base.size / 1000.0
    let lines = typeset_lines(
      [{ text: marker, style: base, anchor: None, }],
      flow.catalog,
      1000.0,
      Left,
    )
    let width = if lines.length() > 0 { lines[0].fit_width } else { 0.0 }
    let y = flow.y
    let page = flow.page
    let baseline = y + metrics.padding_top + face.ascender_pt(base.size)
    if lines.length() > 0 {
      flow.ink_line(lines[0], flow.left - width - gap + 0.5, baseline)
    }
    flow.page = page
    flow.y = y
  }
  let margin_bottom = if is_compound_item(item) {
    prose_margin_bottom
  } else if next_enclosed_block(item, descend=true) is Some(_) {
    list_item_spacing
  } else {
    0.0
  }
  match item.text() {
    Some(text) if !text.is_empty() => self.ink_prose(text, margin_bottom~)
    _ => ()
  }
  self.traverse(item)
}

///|
fn Converter::convert_dlist(self : Converter, node : @core.Node) -> Unit {
  self.add_dest(node)
  let flow = self.flow
  if node.has_title() {
    self.ink_caption(node.title().unwrap_or(""))
  }
  if node.style == Some("horizontal") {
    self.convert_horizontal_dlist(node)
    return
  }
  let term_style = Style::new(bold=true)
  for entry in node.dlist_items {
    for index, term in entry.terms {
      if index > 0 {
        flow.margin(description_list_term_spacing)
      }
      self.ink_prose(
        term.text().unwrap_or(""),
        style=term_style,
        align=Left,
        margin_bottom=0.0,
      )
    }
    match entry.desc {
      Some(desc) =>
        flow.indent(description_list_description_indent, 0.0, fn() {
          flow.margin(description_list_term_spacing)
          let margin_bottom = if next_enclosed_block(desc, descend=true)
            is Some(_) {
            prose_margin_bottom
          } else {
            0.0
          }
          match desc.text() {
            Some(text) if !text.is_empty() =>
              self.ink_prose(text, margin_bottom~)
            _ => ()
          }
          self.traverse(desc)
        })
      None => ()
    }
  }
  if !list_nested(node) && next_enclosed_block(node) is Some(_) {
    flow.margin(prose_margin_bottom)
  }
}

///|
fn Converter::convert_horizontal_dlist(
  self : Converter,
  node : @core.Node,
) -> Unit {
  let flow = self.flow
  let term_style = Style::new(bold=true)
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
  for entry in node.dlist_items {
    let start_page = flow.page
    let start_y = flow.y
    flow.indent(10.0, flow.width() - column, fn() {
      for term in entry.terms {
        self.ink_prose(
          term.text().unwrap_or(""),
          style=term_style,
          align=Left,
          margin_bottom=0.0,
        )
      }
    })
    let (term_page, term_y) = (flow.page, flow.y)
    flow.page = start_page
    flow.y = start_y
    match entry.desc {
      Some(desc) =>
        flow.indent(column + 10.0, 10.0, fn() {
          match desc.text() {
            Some(text) if !text.is_empty() =>
              self.ink_prose(text, margin_bottom=0.0)
            _ => ()
          }
          self.traverse(desc)
        })
      None => ()
    }
    if flow.page < term_page || (flow.page == term_page && flow.y < term_y) {
      flow.page = term_page
      flow.y = term_y
    }
  }
  if next_enclosed_block(node) is Some(_) {
    flow.margin(prose_margin_bottom)
  }
}

///|
fn Converter::convert_admonition(self : Converter, node : @core.Node) -> Unit {
  let flow = self.flow
  let label_style = Style::new(bold=true)
  let label = sanitize(
    node.caption().unwrap_or(node.attr("name").unwrap_or("")),
  ).to_upper()
  let label_lines = typeset_lines(
    [{ text: label, style: label_style, anchor: None, }],
    flow.catalog,
    1.0e6,
    Left,
  )
  let label_width = if label_lines.length() > 0 {
    label_lines[0].fit_width
  } else {
    0.0
  }
  let (pad_top, pad_right, pad_bottom, pad_left) = admonition_padding
  if !flow.at_page_top() &&
    flow.cursor() < pad_top + base_line_height_length + pad_bottom {
    flow.advance_page()
  }
  self.add_dest(node)
  let start = flow.mark()
  let box_left = flow.left + pad_left
  let rule_x = box_left + label_width + pad_right
  flow.indent(pad_left, pad_right, fn() {
    flow.move_down(pad_top)
    flow.indent(label_width + pad_right + pad_left, 0.0, fn() {
      if node.has_title() {
        self.ink_caption(node.title().unwrap_or(""))
      }
      self.push_gutter(node, pad_bottom)
      self.traverse(node)
      self.pop_gutter()
    })
    flow.pad_bottom(pad_bottom)
  })
  let label_face = flow.font(label_style)
  flow.underlay(start, fn(top, bottom, first, _last) {
    let items = [
      vrule(
        rule_x, top, bottom, admonition_column_rule_width, admonition_column_rule_color,
      ),
    ]
    if first && label_lines.length() > 0 {
      // the label is centred vertically on the part of the block on its
      // first page
      let a = label_face.ascender_pt(label_style.size)
      let d = label_face.descender_pt(label_style.size)
      let offset = @cmp.maximum((bottom - top - (a + d)) / 2.0, 0.0)
      items.append(flow.line_items(label_lines[0], box_left, top + offset + a))
    }
    items
  })
  self.block_margin_bottom(node)
}

///|
fn Converter::convert_example(self : Converter, node : @core.Node) -> Unit {
  self.bordered_block(
    node,
    padding=vertical_rhythm,
    side_padding=horizontal_rhythm,
    fill=None,
    stroke=example_border_color,
    stroke_width=example_border_width,
    caption=true,
  )
}

///|
fn Converter::convert_sidebar(self : Converter, node : @core.Node) -> Unit {
  self.bordered_block(
    node,
    padding=vertical_rhythm,
    side_padding=vertical_rhythm * 1.25,
    fill=Some(sidebar_background_color),
    stroke=sidebar_border_color,
    stroke_width=0.5,
    caption=false,
  )
}

///|
/// A padded block with a background and border (example, sidebar).
fn Converter::bordered_block(
  self : Converter,
  node : @core.Node,
  padding~ : Double,
  side_padding~ : Double,
  fill~ : Color?,
  stroke~ : Color,
  stroke_width~ : Double,
  caption~ : Bool,
) -> Unit {
  let flow = self.flow
  if caption && node.has_title() {
    self.ink_caption(node.captioned_title())
  }
  if !flow.at_page_top() &&
    flow.cursor() < padding * 2.0 + base_line_height_length {
    flow.advance_page()
  }
  self.add_dest(node)
  let start = flow.mark()
  let (left, right) = (flow.left, flow.right)
  flow.move_down(padding)
  flow.indent(side_padding, side_padding, fn() {
    if !caption && node.has_title() {
      // sidebar title: centred, bold, heading h4 size
      self.ink_prose(
        node.title().unwrap_or(""),
        style=Style::new(size=heading_font_size(4), bold=true),
        align=Center,
        margin_bottom=heading_margin_bottom,
        // the heading line height, 1
        line_height=1.0,
      )
    }
    self.push_gutter(node, padding)
    self.traverse(node)
    self.pop_gutter()
  })
  flow.pad_bottom(padding)
  flow.underlay(start, fn(top, bottom, _first, _last) {
    [
      rect_item(
        left,
        top,
        right - left,
        bottom - top,
        fill?,
        stroke~,
        stroke_width~,
      ),
    ]
  })
  self.block_margin_bottom(node)
}

///|
fn Converter::convert_quote(self : Converter, node : @core.Node) -> Unit {
  let flow = self.flow
  if node.has_title() {
    self.ink_caption(node.title().unwrap_or(""))
  }
  self.add_dest(node)
  let border = horizontal_rhythm / 3.0
  let start = flow.mark()
  let left = flow.left
  let style = Style::new(size=quote_font_size)
  flow.move_down(vertical_rhythm / 4.0)
  flow.indent(horizontal_rhythm + border / 2.0, horizontal_rhythm, fn() {
    if node.context == Verse {
      self.ink_prose(
        guard_indentation(node.content()),
        style~,
        align=Left,
        margin_bottom=0.0,
        normalize=false,
      )
    } else {
      // quote paragraphs take the quote font size
      for block in node.blocks {
        if block.context == Paragraph {
          self.ink_prose(
            block.content(),
            style~,
            margin_bottom=if next_enclosed_block(block) is Some(_) {
              prose_margin_bottom
            } else {
              0.0
            },
          )
        } else {
          self.convert_block(block)
        }
      }
    }
    match node.attr("attribution") {
      Some(attribution) => {
        flow.margin(block_margin_bottom)
        let cite = match node.attr("citetitle") {
          Some(title) => "\{attribution}, \{title}"
          None => attribution
        }
        self.ink_prose(
          "— \{cite}",
          style=Style::new(
            size=(base_font_size * 0.85).round(),
            color=rgb_hex(0x999999),
          ),
          align=Left,
          margin_bottom=0.0,
        )
      }
      None => ()
    }
  })
  flow.move_down(vertical_rhythm / 4.0)
  flow.underlay(start, fn(top, bottom, _first, _last) {
    [vrule(left + border / 2.0, top, bottom, border, quote_border_color)]
  })
  self.block_margin_bottom(node)
}

///|
fn Converter::convert_open(self : Converter, node : @core.Node) -> Unit {
  self.add_dest(node)
  if node.has_title() {
    self.ink_caption(node.title().unwrap_or(""))
  }
  self.traverse(node)
}

///|
fn Converter::convert_thematic_break(
  self : Converter,
  node : @core.Node,
) -> Unit {
  let flow = self.flow
  flow.move_down(vertical_rhythm * 0.5)
  flow.push(hrule(flow.left, flow.right, flow.y, 0.5, thematic_break_color))
  flow.move_down(vertical_rhythm * 0.5)
  self.block_margin_bottom(node)
}

///|
/// Footnotes of the document, at the bottom of the last page
/// (asciidoctor-pdf's `ink_footnotes` with `footnotes_margin_top: auto`).
fn Converter::ink_footnotes(self : Converter) -> Unit {
  let footnotes = self.doc.footnotes()
  if footnotes.is_empty() {
    return
  }
  let flow = self.flow
  flow.margin(block_margin_bottom)
  let style = Style::new(size=(base_font_size * 0.75).round())
  let face = flow.font(style)
  let metrics = line_metrics(base_line_height, face, style.size)
  let texts = footnotes.map(fn(fn_) {
    "<a id=\"_footnotedef_\{fn_.index}\"></a>[<a anchor=\"_footnoteref_\{fn_.index}\">\{fn_.index}</a>] \{fn_.text}"
  })
  let mut height = 0.0
  for text in texts {
    height += flow.height_of(parse_formatted(text, style), metrics, style) + 3.0
  }
  if height < flow.cursor() {
    flow.move_down(flow.cursor() - height - 0.0001)
  }
  for text in texts {
    self.ink_prose(text, style~, margin_bottom=3.0)
  }
}

///|
/// Running footer: a rule and the page number, right on odd pages and left
/// on even ones (the default theme's `footer_*` keys).
fn Converter::ink_footers(self : Converter) -> Unit {
  let flow = self.flow
  let style = Style::new(size=footer_font_size)
  let face = flow.font(style)
  let top = page_height - footer_height
  let left = margin_side
  let right = page_width - margin_side
  for index, page in flow.model.pages {
    let number = (index + 1).to_string()
    page.items.push(
      hrule(left, right, top, footer_border_width, footer_border_color),
    )
    let lines = typeset_lines(
      [{ text: number, style, anchor: None, }],
      flow.catalog,
      right - left - 2.0,
      if index % 2 == 0 {
        Right
      } else {
        Left
      },
    )
    let baseline = top +
      base_line_height_length / 2.0 +
      face.ascender_pt(style.size)
    page.items.append(flow.line_items(lines[0], left + 1.0, baseline))
  }
}
