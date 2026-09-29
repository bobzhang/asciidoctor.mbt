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
  let (base, fragments, line_height) = cell_fragments(cell, head)
  let face = flow.font(base)
  let metrics = line_metrics(line_height, face, base.size)
  // prawn-table lays text out one point wider than the content box
  // (`FPTolerance`)
  let inner = width - 2.0 * table_cell_padding + 1.0
  let lines = typeset_lines(fragments, flow.catalog, inner, cell_align(cell))
  // Cell::Text#natural_content_height: the box's height and its line gap,
  // the last line's height less its ascender and descender (Box#line_gap:
  // a line all in the code font has that font's gap)
  let last_gap = match lines.last() {
    Some(line) if line.height != 0.0 =>
      line.height - (line.ascender + line.descender)
    _ => face.line_gap_pt(base.size)
  }
  let natural = text_box_height(lines, face, base, metrics) + last_gap
  (TextContent(lines, metrics, base), natural)
}

///|
/// The base style, formatted text and line height of a text cell, after
/// the cell's style (`convert_table`'s `case cell.style`).
fn cell_fragments(
  cell : @core.Node,
  head : Bool,
) -> (Style, Array[Fragment], Double) {
  if head {
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
          // the codespan font and colour (`theme_font :codespan` sets the
          // colour the cell takes)
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
}

///|
/// A cell of prawn-table's width calculation: a master cell, or a dummy
/// standing for a place its span covers (Cell::SpanDummy), in the order
/// `make_cells` creates them.
priv struct WidthCell {
  row : Int
  column : Int
  colspan : Int
  /// the master cell this dummy stands for (its index), or -1
  master : Int
  /// width_ignoring_span, min_width_ignoring_span
  width : Double
  min : Double
}

///|
/// `Cells#aggregate_cell_values(:column, :avg_spanned_min_width, :max)`
/// over `cells` (the table's or one column's): each column's largest
/// minimum width, a span's shared evenly among its columns, summed.
fn aggregate_min_widths(
  all : Array[WidthCell],
  cells : Array[WidthCell],
) -> Double {
  let avg = fn(c : WidthCell) {
    if c.master >= 0 {
      let m = all[c.master]
      m.min / m.colspan.to_double()
    } else {
      c.min / c.colspan.to_double()
    }
  }
  let values : Map[Int, Double] = Map([])
  let put_max = fn(i : Int, v : Double) {
    match values.get(i) {
      Some(old) => values[i] = @cmp.maximum(old, v)
      None => values[i] = v
    }
  }
  for c in cells {
    if c.colspan == 1 && c.master < 0 {
      put_max(c.column, c.min)
    }
  }
  let rows_with_dummy : Map[Int, Bool] = Map([])
  for c in cells {
    if c.master >= 0 {
      rows_with_dummy[c.row] = true
    }
  }
  let mut needs_fixing = true
  for c in cells {
    let index = c.column
    if c.colspan > 1 {
      // fill_values_if_needed: some but not all of the span's columns have
      // a value, in a row with a dummy
      let mut missing = 0
      for i in 0..<c.colspan {
        if !values.contains(index + i) {
          missing += 1
        }
      }
      if missing > 0 && missing < c.colspan && rows_with_dummy.contains(c.row) {
        let mut sum = avg(c) * c.colspan.to_double()
        for i in 0..<c.colspan {
          match values.get(index + i) {
            Some(v) => sum -= v
            None => ()
          }
        }
        let share = sum / missing.to_double()
        for i in 0..<c.colspan {
          if !values.contains(index + i) {
            values[index + i] = share
          }
        }
      }
      let mut old_sum = 0.0
      for i in 0..<c.colspan {
        old_sum += values.get(index + i).unwrap_or(0.0)
      }
      let new_sum = avg(c) * c.colspan.to_double()
      needs_fixing = new_sum - old_sum > 1.0e-9
      if needs_fixing {
        put_max(index, avg(c))
        let mut all_exist = true
        for i in 0..<c.colspan {
          if !values.contains(index + i) {
            all_exist = false
          }
        }
        if all_exist {
          for i in 0..<c.colspan {
            values[index + i] = avg(c)
          }
        }
      }
    } else if needs_fixing && c.master >= 0 {
      put_max(index, avg(c))
    }
  }
  let mut total = 0.0
  for _, v in values {
    total += v
  }
  total
}

///|
/// The column widths of an `autowidth` table, as prawn-table sizes a table
/// given no column widths: each cell's natural width (its text on one
/// line, or the widest of its hard-broken lines, at most the bounds'
/// width; an AsciiDoc cell takes the bounds' width), the widest per column
/// (`ColumnWidthCalculator#natural_widths`), then shrunk towards the
/// columns' minimum widths when wider than `width` (the table's width, by
/// default the natural width capped by the bounds), or grown when
/// narrower.
fn Converter::autowidth_columns(
  self : Converter,
  node : @core.Node,
  bounds_width : Double,
  table_width : Double?,
) -> Array[Double] {
  let flow = self.flow
  let rows = node.rows()
  let all_rows : Array[(Array[@core.Node], Bool)] = []
  for row in rows.head {
    all_rows.push((row, true))
  }
  for row in rows.body {
    all_rows.push((row, false))
  }
  for row in rows.foot {
    all_rows.push((row, false))
  }
  let pad = 2.0 * table_cell_padding
  let occupied : Map[(Int, Int), Bool] = Map([])
  let cells : Array[WidthCell] = []
  let mut num_cols = node.columns().length()
  for r, entry in all_rows {
    let (row, head) = entry
    let mut column = 0
    for cell in row {
      while occupied.contains((r, column)) {
        column += 1
      }
      let colspan = @cmp.maximum(cell.colspan().unwrap_or(1), 1)
      let rowspan = if head {
        1
      } else {
        @cmp.maximum(cell.rowspan().unwrap_or(1), 1)
      }
      let (natural, min_content) = if !head &&
        cell.style == Some("asciidoc") &&
        cell.inner_document() is Some(_) {
        (bounds_width - pad, 0.0)
      } else {
        let (base, fragments, _) = cell_fragments(cell, head)
        let lines = typeset_lines(fragments, flow.catalog, 1.0e9, Left)
        let mut widest = 0.0
        for line in lines {
          widest = @cmp.maximum(widest, line.fit_width)
        }
        let natural = @cmp.minimum(widest, bounds_width)
        (natural, @cmp.minimum(natural, flow.width_of("M", base)))
      }
      let master = cells.length()
      cells.push({
        row: r,
        column,
        colspan,
        master: -1,
        width: natural + pad,
        min: pad + min_content,
      })
      for i in 0..<rowspan {
        for j in 0..<colspan {
          occupied[(r + i, column + j)] = true
          if i > 0 || j > 0 {
            cells.push({
              row: r + i,
              column: column + j,
              colspan: 1,
              master,
              width: 0.0,
              min: 0.0,
            })
          }
        }
      }
      column += colspan
      num_cols = @cmp.maximum(num_cols, column)
    }
  }
  // ColumnWidthCalculator#natural_widths
  let rows_with_dummy : Map[Int, Bool] = Map([])
  for c in cells {
    if c.master >= 0 {
      rows_with_dummy[c.row] = true
    }
  }
  let natural = Array::make(num_cols, 0.0)
  for c in cells {
    if !rows_with_dummy.contains(c.row) && c.master < 0 {
      natural[c.column] = @cmp.maximum(natural[c.column], c.width)
    }
  }
  for c in cells {
    if !rows_with_dummy.contains(c.row) || c.master >= 0 {
      continue
    }
    if c.colspan == 1 {
      natural[c.column] = @cmp.maximum(natural[c.column], c.width)
    } else {
      let mut current = 0.0
      for i in c.column..<@cmp.minimum(c.column + c.colspan, num_cols) {
        current += natural[i]
      }
      if c.width - current > 1.0e-9 {
        for i in c.column..<@cmp.minimum(c.column + c.colspan, num_cols) {
          natural[i] = c.width / c.colspan.to_double()
        }
      }
    }
  }
  let natural_width = natural.fold(init=0.0, (a, b) => a + b)
  let width = table_width.unwrap_or(@cmp.minimum(natural_width, bounds_width))
  if width - natural_width < -1.0e-9 {
    // shrink towards each column's minimum width
    let min_width = aggregate_min_widths(cells, cells)
    let f = (width - min_width) / (natural_width - min_width)
    Array::makei(num_cols, c => {
      let min = aggregate_min_widths(
        cells,
        cells.filter(cell => cell.column == c),
      )
      f * (natural[c] - min) + min
    })
  } else if width - natural_width > 1.0e-9 {
    // grow towards each column's maximum width (the bounds' width)
    let f = (width - natural_width) /
      (bounds_width * num_cols.to_double() - natural_width)
    natural.map(nat => f * (bounds_width - nat) + nat)
  } else {
    natural
  }
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
      let (page, y, left, right, bottom) = (
        flow.page,
        flow.y,
        flow.left,
        flow.right,
        flow.bottom,
      )
      let pages = flow.model.pages.length()
      flow.left = cell.x + pad_left
      flow.right = cell.x + cell.width - pad_right
      // the content may take a page's height from the cell's top (less the
      // padding), even past the bottom margin (`draw_content`)
      flow.bottom = top +
        (bottom - flow.page_top) -
        cell.padding.0 -
        cell.padding.2
      flow.y = top + offset
      self.with_text_align(align, () => self.traverse(inner))
      flow.bottom = bottom
      let extra = flow.model.pages.length() - pages
      if extra > 0 {
        // Ruby deletes the pages the cell ran onto, and says so unless it
        // only started an empty one
        let empty = flow.model.pages[flow.model.pages.length() - 1].items
          .iter()
          .all(i => i is Anchor(_))
        if !(extra == 1 && empty) {
          warning(
            "the table cell on page \{page + 1} has been truncated; Asciidoctor PDF does not support table cell content that exceeds the height of a single page",
            cell.node,
          )
        }
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
  let unbreakable = node.has_option("unbreakable")
  if !self.flow.at_page_top() &&
    (
      unbreakable ||
      (node.has_option("breakable") && (node.has_title() || node.id is Some(_)))
    ) {
    // asciidoctor-pdf puts the table in an open block holding its id and
    // its caption (as a tared caption, full width), and arranges that; the
    // margin below is the table's (`next_enclosed_block` of a table
    // container)
    self.arrange_block(keep_together=unbreakable, fn(c) {
      c.add_dest(node)
      if node.has_title() {
        c.flow.tared(() => c.ink_caption(node.captioned_title()))
      }
      c.convert_table_body(node, contained=true)
    })
    return
  }
  self.convert_table_body(node)
}

///|
/// A table as prawn-table draws it; `contained` when inside the open block
/// asciidoctor-pdf wraps a titled breakable or an unbreakable table in:
/// the block has the destination and the caption.
fn Converter::convert_table_body(
  self : Converter,
  node : @core.Node,
  contained? : Bool = false,
) -> Unit {
  let flow = self.flow
  if !contained {
    self.add_dest(node)
  }
  let pct = node.attributes
    .get("tablepcwidth")
    .map(v => v.to_f())
    .unwrap_or(100.0)
  let columns_spec = node.columns()
  let columns : Array[Double] = []
  let table_width = if node.has_option("autowidth") {
    // prawn-table sizes the columns to their content, within the width
    // given by a `width` attribute or the `stretch` role
    let requested = if node.has_attr("width") {
      Some(flow.width() * pct / 100.0)
    } else if node.has_role("stretch") {
      Some(flow.width())
    } else {
      None
    }
    columns.append(self.autowidth_columns(node, flow.width(), requested))
    columns.fold(init=0.0, (a, b) => a + b)
  } else {
    flow.width() * pct / 100.0
  }
  if !node.has_option("autowidth") {
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
  if !contained && node.has_title() {
    // the default `table_caption_max_width: fit-content`: the caption is
    // no wider than the table, and aligned with it
    let remainder = flow.width() - table_width
    let (l, r) = if remainder > 0.0 {
      match alignment {
        Center => (remainder * 0.5, remainder * 0.5)
        Right => (remainder, 0.0)
        _ => (0.0, remainder)
      }
    } else {
      (0.0, 0.0)
    }
    flow.indent(l, r, () => self.ink_caption(node.captioned_title()))
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
