///|
// Tables, after asciidoctor-pdf's `convert_table` over prawn-table: column
// widths from the column specs, cells placed on a grid that row and column
// spans occupy (Table#make_cells), row heights from the cells' natural
// heights (a spanning cell shares its height evenly among its rows), rows
// that move to the next page when they do not fit, with the header rows
// repeated there, and every cell stroking its own edges.
//
// A text cell is a Prawn text box (Cell::Text, as asciidoctor-pdf patches
// it); an AsciiDoc cell (`a|`) lays out its nested document in the cell
// (ext/prawn-table/cell/asciidoc.rb): measured with a dry run in the
// cell's width, then drawn; content taller than a page is cut off with a
// warning, as Ruby does.

///|
priv enum VAlign {
  VTop
  VCenter
  VBottom
}

///|
priv enum CellContent {
  /// placed lines, their line metrics and base style
  TextContent(Array[Line], LineMetrics, Style)
  /// the nested document of an AsciiDoc cell, and the alignment its
  /// paragraphs take (when all its blocks are paragraphs)
  AsciiDocContent(@core.Node, Alignment?)
}

///|
priv struct TableCell {
  node : @core.Node
  row : Int
  column : Int
  rowspan : Int
  colspan : Int
  /// left edge and width of the whole span
  x : Double
  width : Double
  content : CellContent
  /// top, right, bottom, left (text cells include the line metrics'
  /// padding above and below)
  padding : (Double, Double, Double, Double)
  valign : VAlign
  /// the height of the content alone (prawn-table's
  /// `natural_content_height`)
  natural : Double
  background : Color?
}

///|
fn cell_align(cell : @core.Node) -> Alignment {
  match cell.attr("halign") {
    Some("center") => Center
    Some("right") => Right
    _ => Left
  }
}

///|
fn cell_valign(cell : @core.Node) -> VAlign {
  match cell.attr("valign") {
    Some("middle") => VCenter
    Some("bottom") => VBottom
    _ => VTop
  }
}

///|
/// Prawn's text box height for placed lines: the first line hangs by its
/// ascender, each next one drops by its height and the leading; the last
/// line's descender ends it.
fn text_box_height(
  lines : Array[Line],
  face : Face,
  base : Style,
  metrics : LineMetrics,
) -> Double {
  let mut baseline = 0.0
  let mut depth = 0.0
  for index, line in lines {
    let (a, d, h) = if line.height == 0.0 {
      (
        face.ascender_pt(base.size),
        face.descender_pt(base.size),
        face.height_pt(base.size),
      )
    } else {
      (line.ascender, line.descender, line.height)
    }
    baseline = if index == 0 { a } else { baseline + h + metrics.leading }
    depth = d
  }
  baseline + depth
}

///|
/// Collapse runs of spaces, tabs and newlines to one space (Ruby's
/// `tr_s " \t\n", ' '`).
fn squeeze_whitespace(text : String) -> String {
  let sb = StringBuilder()
  let mut in_space = false
  for c in text {
    if c == ' ' || c == '\t' || c == '\n' {
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

///|
/// The formatted text of a body cell, as `convert_table` hands it to
/// prawn-table: separate paragraphs become lines apart (hard breaks, the
/// whitespace in each squeezed), else one normalized paragraph.
fn body_cell_fragments(text : String, base : Style) -> Array[Fragment] {
  let text = text.trim().to_owned()
  if text.contains("\n\n") {
    let paragraphs = []
    let mut rest = text
    while rest.find("\n\n") is Some(i) {
      paragraphs.push(squeeze_whitespace(rest[:i].to_owned()))
      let mut j = i
      while j < rest.length() && rest[j] == '\n' {
        j += 1
      }
      rest = rest[j:].to_owned()
    }
    paragraphs.push(squeeze_whitespace(rest))
    parse_formatted(paragraphs.join("\n\n"), base, normalize=false)
  } else {
    parse_formatted(text, base)
  }
}

///|
/// A text cell: its lines, line metrics and natural height after the
/// cell's style (`convert_table`'s `case cell.style`).
fn Converter::text_cell_content(
  self : Converter,
  cell : @core.Node,
  head : Bool,
  width : Double,
) -> (CellContent, Double) {
  let flow = self.flow
  let (base, fragments, line_height) = if head {
    let base = Style::new(doc_bold=true)
    (
      base,
      parse_formatted(cell.text().unwrap_or("").trim().to_owned(), base),
      base_line_height,
    )
  } else {
    match cell.style {
      Some("literal") => {
        // the raw text, without inline formatting, in the code font
        let base = Style::new(family=mono_font_family, size=code_font_size)
        let text = guard_indentation(cell.cell_data().text)
        (base, [{ text, style: base, anchor: None, }], code_line_height)
      }
      style => {
        let base = match style {
          Some("strong") | Some("header") => Style::new(doc_bold=true)
          Some("emphasis") => Style::new(doc_italic=true)
          Some("monospaced") =>
            Style::new(family=mono_font_family, color=codespan_font_color)
          _ => Style::new()
        }
        (
          base,
          body_cell_fragments(cell.text().unwrap_or(""), base),
          base_line_height,
        )
      }
    }
  }
  let face = flow.font(base)
  let metrics = line_metrics(line_height, face, base.size)
  // prawn-table lays text out one point wider than the content box
  // (`FPTolerance`)
  let inner = width - 2.0 * table_cell_padding + 1.0
  let lines = typeset_lines(fragments, flow.catalog, inner, cell_align(cell))
  // Cell::Text#natural_content_height: the box's height and the line gap
  let natural = text_box_height(lines, face, base, metrics) +
    face.line_gap_pt(base.size)
  (TextContent(lines, metrics, base), natural)
}

///|
/// The height the nested document of an AsciiDoc cell takes in the cell's
/// content width (Cell::AsciiDoc#dry_run): laid out from the top of a page
/// after moving down by the vertical padding; when it does not fit on
/// that page, the page's height.
fn Converter::asciidoc_cell_height(
  self : Converter,
  inner : @core.Node,
  align : Alignment?,
  left : Double,
  right : Double,
  padding_y : Double,
) -> Double {
  let scratch = self.dry_run(left, right, fn(scratch) {
    scratch.flow.move_down(padding_y)
    scratch.with_text_align(align, () => scratch.traverse(inner))
  })
  let flow = self.flow
  if scratch.model.pages.length() > 1 {
    flow.bottom - flow.page_top - padding_y
  } else {
    scratch.y - flow.page_top - padding_y
  }
}

///|
/// Rule widths of a table, after its `frame` and `grid` attributes.
priv struct Rules {
  frame_ends : Double
  frame_sides : Double
  grid_rows : Double
  grid_cols : Double
  /// under the last header row (the default theme's
  /// `table_head_border_bottom_width`)
  head : Double
}

///|
fn table_rules(node : @core.Node) -> Rules {
  let w = table_border_width
  let (frame_ends, frame_sides) = match
    node.attr("frame", default="all", fallback_name="table-frame") {
    Some("topbot") | Some("ends") => (w, 0.0)
    Some("sides") => (0.0, w)
    Some("none") => (0.0, 0.0)
    _ => (w, w)
  }
  let (grid_rows, grid_cols) = match
    node.attr("grid", default="all", fallback_name="table-grid") {
    Some("rows") => (w, 0.0)
    Some("cols") => (0.0, w)
    Some("none") => (0.0, 0.0)
    _ => (w, w)
  }
  {
    frame_ends,
    frame_sides,
    grid_rows,
    grid_cols,
    head: table_head_border_bottom_width,
  }
}

///|
/// A laid-out table: its cells in row-major order, the row heights, and
/// how many header rows, rows and columns it has.
priv struct TableLayout {
  cells : Array[TableCell]
  row_heights : Array[Double]
  head_rows : Int
  num_rows : Int
  num_cols : Int
  rules : Rules
  /// prawn-table's `row_colors` for the body rows (None: the page's white)
  row_colors : Array[Color?]
}

///|
/// Place the cells on the grid (prawn-table's `make_cells`: a cell takes
/// the first column its row has free after the spans from above) and size
/// them.
fn Converter::layout_table(
  self : Converter,
  node : @core.Node,
  columns : Array[Double],
  left : Double,
) -> TableLayout {
  let rows = node.rows()
  let all_rows : Array[(Array[@core.Node], Bool, Bool)] = []
  for row in rows.head {
    all_rows.push((row, true, false))
  }
  for row in rows.body {
    all_rows.push((row, false, false))
  }
  for row in rows.foot {
    all_rows.push((row, false, true))
  }
  let num_cols = columns.length()
  let occupied : Map[(Int, Int), Bool] = Map([])
  let cells : Array[TableCell] = []
  for r, entry in all_rows {
    let (row, head, foot) = entry
    let mut column = 0
    for cell in row {
      while occupied.contains((r, column)) {
        column += 1
      }
      let colspan = @cmp.maximum(cell.colspan().unwrap_or(1), 1)
      // header rows take no row span
      let rowspan = if head {
        1
      } else {
        @cmp.maximum(cell.rowspan().unwrap_or(1), 1)
      }
      for i in 0..<rowspan {
        for j in 0..<colspan {
          occupied[(r + i, column + j)] = true
        }
      }
      let mut x = left
      for i in 0..<@cmp.minimum(column, num_cols) {
        x += columns[i]
      }
      let mut width = 0.0
      for i in column..<@cmp.minimum(column + colspan, num_cols) {
        width += columns[i]
      }
      let pad = table_cell_padding
      let (content, padding, natural) = if !head &&
        cell.style == Some("asciidoc") &&
        cell.inner_document() is Some(inner) {
        // a centred or right-aligned cell aligns its paragraphs, when it
        // has nothing else (`apply_font_properties`)
        let align = match cell_align(cell) {
          Left => None
          other =>
            if inner.blocks.iter().all(b => b.context == Paragraph) {
              Some(other)
            } else {
              None
            }
        }
        let natural = self.asciidoc_cell_height(
          inner,
          align,
          x + pad,
          x + width - pad,
          2.0 * pad,
        )
        (AsciiDocContent(inner, align), (pad, pad, pad, pad), natural)
      } else {
        let (content, natural) = self.text_cell_content(cell, head, width)
        let (top, bottom) = match content {
          TextContent(_, metrics, _) =>
            (metrics.padding_top, metrics.padding_bottom)
          _ => (0.0, 0.0)
        }
        (content, (pad + top, pad, pad + bottom, pad), natural)
      }
      cells.push({
        node: cell,
        row: r,
        column,
        rowspan,
        colspan,
        x,
        width,
        content,
        padding,
        valign: cell_valign(cell),
        natural,
        background: if foot {
          Some(table_foot_background_color)
        } else {
          None
        },
      })
      column += colspan
    }
  }
  let mut num_rows = all_rows.length()
  for cell in cells {
    num_rows = @cmp.maximum(num_rows, cell.row + cell.rowspan)
  }
  // prawn-table's `row_heights`: a cell's height shared evenly among the
  // rows it spans
  let row_heights = Array::make(num_rows, 0.0)
  for cell in cells {
    let height = cell.natural + cell.padding.0 + cell.padding.2
    let share = height / cell.rowspan.to_double()
    for i in 0..<cell.rowspan {
      if share > row_heights[cell.row + i] {
        row_heights[cell.row + i] = share
      }
    }
  }
  {
    cells,
    row_heights,
    head_rows: rows.head.length(),
    num_rows,
    num_cols,
    rules: table_rules(node),
    row_colors: match node.attr("stripes", fallback_name="table-stripes") {
      Some("all") => [Some(table_body_stripe_background_color)]
      Some("even") => [None, Some(table_body_stripe_background_color)]
      Some("odd") => [Some(table_body_stripe_background_color), None]
      _ => [None]
    },
  }
}

///|
/// The height of a cell's whole span.
fn TableLayout::span_height(self : TableLayout, cell : TableCell) -> Double {
  let mut h = 0.0
  for i in cell.row..<(cell.row + cell.rowspan) {
    h += self.row_heights[i]
  }
  h
}

///|
/// The room a row needs to start on a page: its tallest cell with its span
/// (prawn-table's `height_with_span`).
fn TableLayout::row_height_with_span(self : TableLayout, row : Int) -> Double {
  let mut h = self.row_heights[row]
  for cell in self.cells {
    if cell.row == row {
      h = @cmp.maximum(h, self.span_height(cell))
    }
  }
  h
}

///|
/// Stroke a cell's edges: the frame on the table's outside, the grid
/// inside, the heavier rule between header and body. Left and right edges
/// run on by half the top and bottom widths, so corners are square
/// (asciidoctor-pdf's `draw_borders`).
fn Converter::draw_cell_borders(
  self : Converter,
  layout : TableLayout,
  cell : TableCell,
  top : Double,
  height : Double,
) -> Unit {
  let flow = self.flow
  let rules = layout.rules
  let last_row = cell.row + cell.rowspan - 1
  let top_width = if cell.row == 0 {
    rules.frame_ends
  } else if layout.head_rows > 0 && cell.row == layout.head_rows {
    rules.head
  } else {
    rules.grid_rows
  }
  let bottom_width = if last_row == layout.num_rows - 1 {
    rules.frame_ends
  } else if layout.head_rows > 0 && last_row == layout.head_rows - 1 {
    rules.head
  } else {
    rules.grid_rows
  }
  let left_width = if cell.column == 0 {
    rules.frame_sides
  } else {
    rules.grid_cols
  }
  let right_width = if cell.column + cell.colspan >= layout.num_cols {
    rules.frame_sides
  } else {
    rules.grid_cols
  }
  let right = cell.x + cell.width
  let bottom = top + height
  if top_width > 0.0 {
    flow.push(hrule(cell.x, right, top, top_width, table_border_color))
  }
  if bottom_width > 0.0 {
    flow.push(hrule(cell.x, right, bottom, bottom_width, table_border_color))
  }
  let (y1, y2) = (top - top_width / 2.0, bottom + bottom_width / 2.0)
  if left_width > 0.0 {
    flow.push(vrule(cell.x, y1, y2, left_width, table_border_color))
  }
  if right_width > 0.0 {
    flow.push(vrule(right, y1, y2, right_width, table_border_color))
  }
}

///|
/// Draw a cell's content in its content box, whose top is `top`.
fn Converter::draw_cell_content(
  self : Converter,
  cell : TableCell,
  top : Double,
  spanned_content_height : Double,
) -> Unit {
  let flow = self.flow
  let (_, pad_right, _, pad_left) = cell.padding
  match cell.content {
    TextContent(lines, metrics, base) => {
      let face = flow.font(base)
      // the text box is one point taller than the content (FPTolerance);
      // asciidoctor-pdf centres the text on its own height
      let box_height = spanned_content_height + 1.0
      let text_height = text_box_height(lines, face, base, metrics)
      let offset = match cell.valign {
        VTop => 0.0
        VCenter => (box_height - text_height) * 0.5
        VBottom => box_height - text_height
      }
      let mut baseline = top + offset
      for index, line in lines {
        let (a, h) = if line.height == 0.0 {
          (face.ascender_pt(base.size), face.height_pt(base.size))
        } else {
          (line.ascender, line.height)
        }
        baseline = if index == 0 {
          baseline + a
        } else {
          baseline + h + metrics.leading
        }
        flow.ink_line(line, cell.x + pad_left, baseline)
      }
    }
    AsciiDocContent(inner, align) => {
      let excess = spanned_content_height - cell.natural
      let offset = if excess > 0.0 {
        match cell.valign {
          VTop => 0.0
          VCenter => excess / 2.0
          VBottom => excess
        }
      } else {
        0.0
      }
      let (page, y, left, right) = (flow.page, flow.y, flow.left, flow.right)
      let pages = flow.model.pages.length()
      flow.left = cell.x + pad_left
      flow.right = cell.x + cell.width - pad_right
      flow.y = top + offset
      self.with_text_align(align, () => self.traverse(inner))
      if flow.model.pages.length() > pages {
        // Ruby deletes the pages the cell ran onto
        warning(
          "the table cell on page \{page + 1} has been truncated; Asciidoctor PDF does not support table cell content that exceeds the height of a single page",
          cell.node,
        )
        while flow.model.pages.length() > pages {
          ignore(flow.model.pages.pop())
        }
      }
      flow.page = page
      flow.y = y
      flow.left = left
      flow.right = right
    }
  }
}

///|
/// Draw `rows` with the top of the first at the cursor, as prawn-table
/// draws the cells of one page: every background, then each cell's borders
/// and content.
fn Converter::draw_table_rows(
  self : Converter,
  layout : TableLayout,
  rows : Array[Int],
  start_row : Int,
) -> Unit {
  let flow = self.flow
  let tops : Map[Int, Double] = Map([])
  let mut y = flow.y
  for r in rows {
    tops[r] = y
    y += layout.row_heights[r]
  }
  let on_page = layout.cells.filter(c => tops.contains(c.row))
  for cell in on_page {
    // body rows take the row colours, restarting on every page
    // (`set_background_color`)
    let background = match cell.background {
      Some(color) => Some(color)
      None if cell.row >= layout.head_rows => {
        let index = cell.row - @cmp.maximum(start_row, layout.head_rows)
        let n = layout.row_colors.length()
        layout.row_colors[(index % n + n) % n]
      }
      None => None
    }
    match background {
      Some(color) =>
        flow.push(
          rect_item(
            cell.x,
            tops.get(cell.row).unwrap(),
            cell.width,
            layout.span_height(cell),
            fill=color,
          ),
        )
      None => ()
    }
  }
  for cell in on_page {
    let top = tops.get(cell.row).unwrap()
    let height = layout.span_height(cell)
    self.draw_cell_borders(layout, cell, top, height)
    let (pad_top, _, pad_bottom, _) = cell.padding
    self.draw_cell_content(cell, top + pad_top, height - pad_top - pad_bottom)
  }
}

///|
/// Whether `height` fits below the cursor (prawn-table's `fits_on_page?`).
fn Flow::fits(self : Flow, height : Double, y? : Double = self.y) -> Bool {
  height < self.bottom - y + 1.0e-9
}

///|
fn Converter::convert_table(self : Converter, node : @core.Node) -> Unit {
  let flow = self.flow
  self.add_dest(node)
  let pct = node.attributes
    .get("tablepcwidth")
    .map(v => v.to_f())
    .unwrap_or(100.0)
  let table_width = flow.width() * pct / 100.0
  let columns_spec = node.columns()
  let columns : Array[Double] = []
  if node.has_option("autowidth") {
    // prawn-table would size columns to their content; share evenly
    let n = columns_spec.length()
    for _ in 0..<n {
      columns.push(table_width / n.to_double())
    }
  } else {
    for col in columns_spec {
      let colpc = col.attributes
        .get("colpcwidth")
        .map(v => v.to_f())
        .unwrap_or(0.0)
      columns.push(colpc * table_width / 100.0)
    }
  }
  // the table's `align` attribute, else its last alignment role, else the
  // theme's (left)
  let alignment = match node.attr("align") {
    Some("center") => Center
    Some("right") => Right
    Some("left") => Left
    _ => {
      let mut a = Left
      for role in node.roles() {
        match role {
          "left" => a = Left
          "center" => a = Center
          "right" => a = Right
          _ => ()
        }
      }
      a
    }
  }
  let left = match alignment {
    Center => flow.left + (flow.width() - table_width) * 0.5
    Right => flow.left + flow.width() - table_width
    _ => flow.left
  }
  let layout = self.layout_table(node, columns, left)
  if node.has_title() {
    self.ink_caption(node.captioned_title())
  }
  if layout.num_rows == 0 {
    self.block_margin_bottom(node)
    return
  }
  // initial_row_on_initial_page (as asciidoctor-pdf patches it): unless at
  // the top, the header rows and the first body row, with their spans, must
  // fit, else the table starts on the next page

  if !flow.at_page_top() {
    let mut needed = 0.0
    for r in 0..<@cmp.minimum(layout.head_rows + 1, layout.num_rows) {
      needed += layout.row_height_with_span(r)
    }
    if !flow.fits(needed) {
      flow.advance_page()
    }
  }
  // the rows of each page, drawn once the page is full
  let mut page_top = flow.y
  let mut rows_here : Array[Int] = []
  let mut used = 0.0
  let mut start_row = 0
  for r in 0..<layout.num_rows {
    if r > 0 && !flow.fits(layout.row_height_with_span(r), y=page_top + used) {
      // a page holding only the repeated header draws nothing
      if rows_here.length() > layout.head_rows {
        flow.y = page_top
        self.draw_table_rows(layout, rows_here, start_row)
      }
      flow.advance_page()
      start_row = r
      page_top = flow.y
      rows_here = []
      used = 0.0
      if r >= layout.head_rows {
        for h in 0..<layout.head_rows {
          rows_here.push(h)
          used += layout.row_heights[h]
        }
      }
    }
    rows_here.push(r)
    used += layout.row_heights[r]
  }
  flow.y = page_top
  self.draw_table_rows(layout, rows_here, start_row)
  flow.y = page_top + used
  self.block_margin_bottom(node)
}
