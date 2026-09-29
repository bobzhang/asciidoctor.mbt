///|
// Tables, after asciidoctor-pdf's `convert_table` over prawn-table: fixed
// column widths from the column specs, cell padding plus the line metrics'
// padding, a grid of thin rules with a heavier rule under the header, and
// the header rows repeated on every page the table continues onto.

///|
priv struct CellLayout {
  lines : Array[Line]
  x : Double
  width : Double
  metrics : LineMetrics
  base : Style
}

///|
priv struct RowLayout {
  cells : Array[CellLayout]
  height : Double
  foot : Bool
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
fn Converter::layout_row(
  self : Converter,
  row : Array[@core.Node],
  columns : Array[Double],
  left : Double,
  head : Bool,
  foot : Bool,
) -> RowLayout {
  let flow = self.flow
  let cells : Array[CellLayout] = []
  let mut column = 0
  let mut height = 0.0
  for cell in row {
    let span = cell.colspan().unwrap_or(1)
    let mut x = left
    for i in 0..<column {
      x += columns[i]
    }
    let mut width = 0.0
    for i in column..<@cmp.minimum(column + span, columns.length()) {
      width += columns[i]
    }
    column += span
    let (base, text, normalize) = if head {
      (Style::new(bold=true), cell.text().unwrap_or("").trim().to_owned(), true)
    } else {
      match cell.style {
        Some("strong") =>
          (
            Style::new(bold=true),
            cell.text().unwrap_or("").trim().to_owned(),
            true,
          )
        Some("emphasis") =>
          (
            Style::new(italic=true),
            cell.text().unwrap_or("").trim().to_owned(),
            true,
          )
        Some("header") =>
          (
            Style::new(bold=true),
            cell.text().unwrap_or("").trim().to_owned(),
            true,
          )
        Some("monospaced") =>
          (
            Style::new(family=mono_font_family),
            cell.text().unwrap_or("").trim().to_owned(),
            true,
          )
        Some("literal") =>
          (
            Style::new(family=mono_font_family, size=code_font_size),
            guard_indentation(cell.text().unwrap_or("")),
            false,
          )
        Some("asciidoc") =>
          // nested AsciiDoc is flattened to its paragraphs for now
          (Style::new(), cell.cell_paragraphs().join("<br>"), true)
        _ => (Style::new(), cell.cell_paragraphs().join("<br><br>"), true)
      }
    }
    let face = flow.font(base)
    let metrics = line_metrics(base_line_height, face, base.size)
    // prawn-table lays text out one point wider than the content box
    // (`FPTolerance`)
    let inner = width - 2.0 * table_cell_padding + 1.0
    let lines = typeset_lines(
      parse_formatted(text, base, normalize~),
      flow.catalog,
      inner,
      cell_align(cell),
    )
    // prawn-table: padding (with the line metrics' top and bottom), the
    // text box height, and the font's line gap
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
    let content = baseline + depth + face.line_gap_pt(base.size)
    let cell_height = 2.0 * table_cell_padding +
      metrics.padding_top +
      metrics.padding_bottom +
      content
    if cell_height > height {
      height = cell_height
    }
    cells.push({ lines, x, width, metrics, base, })
  }
  { cells, height, foot, }
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
/// Ink one row with its top at the cursor. Every cell strokes its own
/// edges, as prawn-table does: the frame on the table's outside, the grid
/// inside, the heavier rule between header and body.
fn Converter::ink_row(
  self : Converter,
  row : RowLayout,
  rules : Rules,
  first : Bool,
  last : Bool,
  head_last : Bool,
  body_first : Bool,
  table_left : Double,
  table_right : Double,
) -> Unit {
  let flow = self.flow
  let top = flow.y
  let bottom = top + row.height
  if row.foot {
    flow.push(
      rect_item(
        table_left,
        top,
        table_right - table_left,
        row.height,
        fill=table_foot_background_color,
      ),
    )
  }
  for cell in row.cells {
    let face = flow.font(cell.base)
    let mut baseline = top + table_cell_padding + cell.metrics.padding_top
    for index, line in cell.lines {
      let (a, h) = if line.height == 0.0 {
        (face.ascender_pt(cell.base.size), face.height_pt(cell.base.size))
      } else {
        (line.ascender, line.height)
      }
      baseline = if index == 0 {
        baseline + a
      } else {
        baseline + h + cell.metrics.leading
      }
      flow.ink_line(line, cell.x + table_cell_padding, baseline)
    }
    let right = cell.x + cell.width
    let top_width = if first {
      rules.frame_ends
    } else if body_first {
      rules.head
    } else {
      rules.grid_rows
    }
    let bottom_width = if last {
      rules.frame_ends
    } else if head_last {
      rules.head
    } else {
      rules.grid_rows
    }
    let left_width = if cell.x <= table_left + 0.01 {
      rules.frame_sides
    } else {
      rules.grid_cols
    }
    let right_width = if right >= table_right - 0.01 {
      rules.frame_sides
    } else {
      rules.grid_cols
    }
    if top_width > 0.0 {
      flow.push(hrule(cell.x, right, top, top_width, table_border_color))
    }
    if bottom_width > 0.0 {
      flow.push(hrule(cell.x, right, bottom, bottom_width, table_border_color))
    }
    if left_width > 0.0 {
      flow.push(vrule(cell.x, top, bottom, left_width, table_border_color))
    }
    if right_width > 0.0 {
      flow.push(vrule(right, top, bottom, right_width, table_border_color))
    }
  }
  flow.y = bottom
}

///|
fn Converter::convert_table(self : Converter, node : @core.Node) -> Unit {
  let flow = self.flow
  self.add_dest(node)
  if node.has_title() {
    self.ink_caption(node.captioned_title())
  }
  let columns_spec = node.columns()
  let pct = node.attributes
    .get("tablepcwidth")
    .map(v => v.to_f())
    .unwrap_or(100.0)
  let table_width = flow.width() * pct / 100.0
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
  let left = flow.left
  let right = left + table_width
  let rules = table_rules(node)
  let rows = node.rows()
  let head = rows.head.map(r => self.layout_row(r, columns, left, true, false))
  let body = rows.body.map(r => self.layout_row(r, columns, left, false, false))
  let foot = rows.foot.map(r => self.layout_row(r, columns, left, false, true))
  let all : Array[RowLayout] = []
  all.append(head)
  all.append(body)
  all.append(foot)
  let head_count = head.length()
  for index, row in all {
    let is_head = index < head_count
    if !flow.at_page_top() && flow.cursor() < row.height {
      flow.advance_page()
      // prawn-table repeats the header on each new page
      if !is_head {
        for h, head_row in head {
          self.ink_row(
            head_row,
            rules,
            h == 0,
            false,
            h == head_count - 1,
            false,
            left,
            right,
          )
        }
      }
    }
    self.ink_row(
      row,
      rules,
      index == 0,
      index == all.length() - 1,
      is_head && index == head_count - 1,
      head_count > 0 && index == head_count,
      left,
      right,
    )
  }
  self.block_margin_bottom(node)
}
