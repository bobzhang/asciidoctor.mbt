///|
/// Rows of a table grouped by section.
pub struct TableRows {
  mut head : Array[Array[Node]]
  mut body : Array[Array[Node]]
  mut foot : Array[Array[Node]]
}

///|
/// Implicit/explicit header state (Ruby `has_header_option`: true, :implicit, nil/false).
pub(all) enum HeaderOption {
  NoHeader
  ExplicitHeader
  ImplicitHeader
  UnsetHeader // Ruby nil
} derive(Eq, Debug)

///|
/// Table-specific data.
pub struct TableData {
  rows : TableRows
  mut columns : Array[Node]
  mut has_header_option : HeaderOption
}

///|
/// Table cell data.
pub struct CellData {
  mut text : String
  mut colspan : Int?
  mut rowspan : Int?
  mut inner_document : Node?
  priv mut cursor : Cursor?
  priv mut reinitialize_args : (Node?, String, Attributes?, Cursor?)?
}

///|
pub fn Node::table_data(self : Node) -> TableData {
  match self.table_ {
    Some(t) => t
    None => abort("not a table")
  }
}

///|
pub fn Node::cell_data(self : Node) -> CellData {
  match self.cell_ {
    Some(c) => c
    None => abort("not a table cell")
  }
}

///|
pub fn Node::rows(self : Node) -> TableRows {
  self.table_data().rows
}

///|
pub fn Node::columns(self : Node) -> Array[Node] {
  self.table_data().columns
}

///|
pub fn Node::colspan(self : Node) -> Int? {
  self.cell_data().colspan
}

///|
pub fn Node::rowspan(self : Node) -> Int? {
  self.cell_data().rowspan
}

///|
pub fn Node::inner_document(self : Node) -> Node? {
  self.cell_data().inner_document
}

///|
/// The column of a table cell, or the table of a column.
pub fn Node::column(self : Node) -> Node? {
  self.parent_
}

///|
fn attr_number(x : Double) -> AttrVal {
  if @rb.is_integral(x) {
    Int(x.to_int())
  } else {
    Float(x)
  }
}

///|
/// Creates a table (Ruby `Table.new parent, attributes`).
pub fn Node::new_table(parent : Node, attributes : Attributes) -> Node {
  let t = Node::alloc(Some(parent), Table)
  t.table_ = Some({
    rows: { head: [], body: [], foot: [], },
    columns: [],
    has_header_option: NoHeader,
  })
  let pcwidth_intval = match attributes.str("width") {
    Some(pcwidth) => {
      let mut v = @rb.to_i(pcwidth)
      if v > 100 || v < 1 {
        if !(v == 0 && (pcwidth == "0" || pcwidth == "0%")) {
          v = 100
        }
      }
      v
    }
    None => 100
  }
  t.attributes.set("tablepcwidth", Int(pcwidth_intval))
  match t.document().attributes.get("pagewidth") {
    Some(pw) if pw.truthy() => {
      let abswidth = @rb.float_truncate(
        pcwidth_intval.to_double() / 100.0 * pw.to_f(),
        4,
      )
      t.attributes.set("tableabswidth", attr_number(abswidth))
    }
    _ => ()
  }
  if attributes.truthy("rotate-option") {
    t.attributes.set_str("orientation", "landscape")
  }
  t
}

///|
/// Ruby `Table#header_row?`.
fn Node::header_row(self : Node) -> HeaderOption {
  let td = self.table_data()
  match td.has_header_option {
    ExplicitHeader | ImplicitHeader if td.rows.body.is_empty() =>
      td.has_header_option
    _ => NoHeader
  }
}

///|
/// A column spec (Ruby Hash with width, halign, valign, style).
pub(all) struct ColSpec {
  mut width : Int
  mut halign : String?
  mut valign : String?
  mut style : String?
} derive(Debug)

///|
/// Creates the columns from colspecs (Ruby `create_columns`).
fn Node::create_columns(self : Node, colspecs : Array[ColSpec]) -> Unit {
  let cols = []
  let autowidth_cols = []
  let mut width_base = 0
  for colspec in colspecs {
    let a = Attributes::new()
    a.set("width", Int(colspec.width))
    match colspec.halign {
      Some(h) => a.set_str("halign", h)
      None => ()
    }
    match colspec.valign {
      Some(v) => a.set_str("valign", v)
      None => ()
    }
    match colspec.style {
      Some(s) => a.set_str("style", s)
      None => ()
    }
    let col = Node::new_table_column(self, cols.length(), a)
    cols.push(col)
    if colspec.width < 0 {
      autowidth_cols.push(col)
    } else {
      width_base += colspec.width
    }
  }
  self.table_data().columns = cols
  let num_cols = cols.length()
  if num_cols > 0 {
    self.attributes.set("colcount", Int(num_cols))
    let wb = if width_base > 0 || !autowidth_cols.is_empty() {
      Some(width_base)
    } else {
      None
    }
    self.assign_column_widths(
      width_base?=wb,
      autowidth_cols?=if autowidth_cols.is_empty() {
        None
      } else {
        Some(autowidth_cols)
      },
    )
  }
}

///|
/// Ruby numeric addition preserving Integer/Float distinction.
fn num_add(a : AttrVal, b : AttrVal) -> AttrVal {
  match (a, b) {
    (Int(x), Int(y)) => Int(x + y)
    _ => Float(a.to_f() + b.to_f())
  }
}

///|
fn num_sub(a : AttrVal, b : AttrVal) -> AttrVal {
  match (a, b) {
    (Int(x), Int(y)) => Int(x - y)
    _ => Float(a.to_f() - b.to_f())
  }
}

///|
/// Ruby `Table#assign_column_widths`.
fn Node::assign_column_widths(
  self : Node,
  width_base? : Int,
  autowidth_cols? : Array[Node],
) -> Unit {
  let precision = 4
  let columns = self.table_data().columns
  let mut total_width : AttrVal = Int(0)
  let mut col_pcwidth : AttrVal = Int(0)
  match width_base {
    Some(wb0) => {
      let mut wb = wb0
      match autowidth_cols {
        Some(acols) => {
          let autowidth = if wb > 100 {
            log_warn(
              "total column width must not exceed 100% when using autowidth columns; got \{wb}%",
            )
            Int(0)
          } else {
            let aw = @rb.float_truncate(
              (100.0 - wb.to_double()) / acols.length().to_double(),
              precision,
            )
            wb = 100
            attr_number(aw)
          }
          for col in acols {
            col.attributes.set("width", autowidth)
            col.attributes.set_str("autowidth-option", "")
          }
        }
        None => ()
      }
      for col in columns {
        col_pcwidth = col.assign_width(Int(0), Some(wb), precision)
        total_width = num_add(total_width, col_pcwidth)
      }
    }
    None => {
      col_pcwidth = attr_number(
        @rb.float_truncate(100.0 / columns.length().to_double(), precision),
      )
      for col in columns {
        total_width = num_add(
          total_width,
          col.assign_width(col_pcwidth, None, precision),
        )
      }
    }
  }
  if total_width.to_f() != 100.0 {
    let last = columns[columns.length() - 1]
    let v = num_add(num_sub(Int(100), total_width), col_pcwidth)
    let rounded = match v {
      Int(_) => v
      _ => Float(@rb.float_round(v.to_f(), precision))
    }
    last.assign_width(rounded, None, precision) |> ignore
  }
}

///|
/// Ruby `Table::Column#assign_width`; returns the percentage width.
fn Node::assign_width(
  self : Node,
  col_pcwidth : AttrVal,
  width_base : Int?,
  precision : Int,
) -> AttrVal {
  let pc = match width_base {
    Some(wb) =>
      attr_number(
        @rb.float_truncate(
          self.attributes.get("width").unwrap_or(Int(1)).to_f() *
          100.0 /
          wb.to_double(),
          precision,
        ),
      )
    None => col_pcwidth
  }
  match self.parent_ {
    Some(table) =>
      match table.attributes.get("tableabswidth") {
        Some(abs) if abs.truthy() => {
          let colabs = @rb.float_truncate(
            pc.to_f() / 100.0 * abs.to_f(),
            precision,
          )
          self.attributes.set("colabswidth", attr_number(colabs))
        }
        _ => ()
      }
    None => ()
  }
  self.attributes.set("colpcwidth", pc)
  pc
}

///|
/// Partitions header and footer rows (Ruby `partition_header_footer`).
fn Node::partition_header_footer(self : Node, attrs : Attributes) -> Unit {
  let td = self.table_data()
  let body = td.rows.body
  let mut num_body_rows = body.length()
  self.attributes.set("rowcount", Int(num_body_rows))
  if num_body_rows > 0 {
    if td.has_header_option == ExplicitHeader ||
      td.has_header_option == ImplicitHeader {
      let first = body.remove(0)
      td.rows.head = [first.map(cell => cell.reinitialize(true))]
      num_body_rows -= 1
    } else if td.has_header_option == UnsetHeader {
      td.has_header_option = NoHeader
      let first = body.remove(0)
      body.insert(0, first.map(cell => cell.reinitialize(false)))
    }
  }
  if num_body_rows > 0 && attrs.truthy("footer-option") {
    td.rows.foot = [body.pop().unwrap()]
  }
}

///|
/// Creates a table column (Ruby `Table::Column.new table, index, attributes`).
fn Node::new_table_column(
  table : Node,
  index : Int,
  attributes : Attributes,
) -> Node {
  let col = Node::alloc(Some(table), TableColumn)
  col.level = 0
  col.style = attributes.str("style")
  attributes.set("colnumber", Int(index + 1))
  if !attributes.truthy("width") {
    attributes.set("width", Int(1))
  }
  attributes.set_default("halign", Str("left"))
  attributes.set_default("valign", Str("top"))
  col.attributes.update(attributes)
  col
}

///|
/// The table of a column.
pub fn Node::table(self : Node) -> Node? {
  self.parent_
}

///|
/// Creates a table cell (Ruby `Table::Cell.new column, text, attributes, opts`).
fn Node::new_table_cell(
  column : Node?,
  cell_text : String,
  attributes : Attributes?,
  cursor : Cursor?,
) -> Node {
  let parent = column
  let c = match parent {
    Some(col) => Node::alloc(Some(col), TableCell)
    None => abort("cell without column")
  }
  let cd : CellData = {
    text: "",
    colspan: None,
    rowspan: None,
    inner_document: None,
    cursor: None,
    reinitialize_args: None,
  }
  c.cell_ = Some(cd)
  if c.document().sourcemap() {
    c.source_location = cursor.map(cu => cu.dup())
  }
  let mut cell_style : String? = None
  let mut in_header_row = NoHeader
  let mut cell_text = cell_text
  match column {
    Some(col) => {
      in_header_row = match col.parent_ {
        Some(table) => table.header_row()
        None => NoHeader
      }
      if in_header_row != NoHeader {
        if in_header_row == ImplicitHeader {
          let s = match col.style {
            Some(s) => Some(s)
            None =>
              match attributes {
                Some(a) => a.str("style")
                None => None
              }
          }
          match s {
            Some(st) => {
              if st == "asciidoc" || st == "literal" {
                cd.reinitialize_args = Some(
                  (column, cell_text, attributes.map(a => a.copy()), cursor),
                )
              }
              cell_style = None
            }
            None => ()
          }
        }
      } else {
        cell_style = col.style
      }
      c.attributes.update(col.attributes)
    }
    None => ()
  }
  let mut asciidoc = false
  let mut literal = false
  let mut normal_psv = false
  let mut inner_cursor : Cursor? = None
  match attributes {
    Some(attrs) => {
      if !attrs.is_empty() {
        cd.colspan = attrs.remove("colspan").map(v => v.to_i())
        cd.rowspan = attrs.remove("rowspan").map(v => v.to_i())
        if in_header_row == NoHeader {
          match attrs.str("style") {
            Some(s) => cell_style = Some(s)
            None => ()
          }
        }
        c.attributes.update(attrs)
      }
      match cell_style {
        Some("asciidoc") => {
          asciidoc = true
          inner_cursor = cursor
          cell_text = @rb.rstrip(cell_text)
          if cell_text.has_prefix("\n") {
            let mut lines_advanced = 1
            cell_text = @rb.from(cell_text, 1)
            while cell_text.has_prefix("\n") {
              lines_advanced += 1
              cell_text = @rb.from(cell_text, 1)
            }
            match inner_cursor {
              Some(ic) => ic.advance(lines_advanced)
              None => ()
            }
          } else {
            cell_text = @rb.lstrip(cell_text)
          }
        }
        Some("literal") => {
          literal = true
          cell_text = @rb.rstrip(cell_text)
          while cell_text.has_prefix("\n") {
            cell_text = @rb.from(cell_text, 1)
          }
        }
        _ => {
          normal_psv = true
          cell_text = @rb.strip(cell_text)
        }
      }
    }
    None =>
      if cell_style == Some("asciidoc") {
        asciidoc = true
        inner_cursor = cursor
      }
  }
  if asciidoc {
    let doc = c.document()
    let parent_doctitle = doc.attributes.remove("doctitle")
    let inner_lines = @rb.split(cell_text, "\n", limit=-1)
    if !inner_lines.is_empty() && inner_lines[0].contains("::") {
      let unprocessed_line1 = inner_lines[0]
      let pre = Reader::new_preprocessor(
        doc,
        [unprocessed_line1],
        cursor?=inner_cursor,
      )
      let preprocessed = pre.read_lines()
      if !(unprocessed_line1 == preprocessed.get(0).unwrap_or("\u{0}") &&
        preprocessed.length() < 2) {
        inner_lines.remove(0) |> ignore
        for i, l in preprocessed {
          inner_lines.insert(i, l)
        }
      }
    }
    let opts = Options::new(standalone=false)
    opts.parent = Some(doc)
    opts.cursor = inner_cursor
    cd.inner_document = Some(new_document(Some(inner_lines), opts))
    match parent_doctitle {
      Some(v) => doc.attributes.set("doctitle", v)
      None => ()
    }
    c.subs = []
  } else if literal {
    c.content_model = Verbatim
    c.subs = basic_subs.copy()
  } else {
    if normal_psv {
      if in_header_row != NoHeader {
        cd.cursor = cursor
      } else {
        c.catalog_cell_inline_anchor(cell_text, cursor)
      }
    }
    c.content_model = Simple
    c.subs = normal_subs.copy()
  }
  cd.text = cell_text
  c.style = cell_style
  c
}

///|
/// Ruby `Table::Cell#reinitialize`.
fn Node::reinitialize(self : Node, has_header : Bool) -> Node {
  let cd = self.cell_data()
  if has_header {
    cd.reinitialize_args = None
  } else {
    match cd.reinitialize_args {
      Some((col, text, attrs, cursor)) =>
        return Node::new_table_cell(col, text, attrs, cursor)
      None => self.style = self.attributes.str("style")
    }
  }
  if cd.cursor is Some(_) {
    self.catalog_cell_inline_anchor(cd.text, None)
  }
  self
}

///|
fn Node::catalog_cell_inline_anchor(
  self : Node,
  cell_text : String,
  cursor : Cursor?,
) -> Unit {
  let cd = self.cell_data()
  let cursor = match cursor {
    Some(c) => Some(c)
    None => {
      let c = cd.cursor
      cd.cursor = None
      c
    }
  }
  if !cell_text.has_prefix("[[") {
    return
  }
  match leading_inline_anchor_rx.find(cell_text) {
    Some(m) =>
      catalog_inline_anchor(m.at(1), m.group(2), self, cursor, self.document())
    None => ()
  }
}

///|
/// Content of a table cell: paragraphs of converted text (Ruby `Cell#content`).
fn Node::cell_content(self : Node) -> Array[String] {
  let cd = self.cell_data()
  let cell_style = self.style
  if cell_style == Some("asciidoc") {
    return [cd.inner_document.unwrap().convert()]
  }
  let parent = self.parent_.unwrap()
  if cd.text.contains("\n\n") {
    blank_line_rx
    .split(self.text().unwrap_or(""))
    .map(para => {
      match cell_style {
        Some(st) if st != "header" =>
          Node::new_inline(parent, Quoted, text=para, type_=st).convert()
        _ => para
      }
    })
  } else {
    let subbed = self.text().unwrap_or("")
    if subbed == "" {
      []
    } else {
      match cell_style {
        Some(st) if st != "header" =>
          [Node::new_inline(parent, Quoted, text=subbed, type_=st).convert()]
        _ => [subbed]
      }
    }
  }
}

///|
/// Content of a table cell as an array of paragraphs.
pub fn Node::cell_paragraphs(self : Node) -> Array[String] {
  self.cell_content()
}

///|
/// Lines of a table cell text.
pub fn Node::cell_lines(self : Node) -> Array[String] {
  @rb.split(self.cell_data().text, "\n")
}

// ---------------------------------------------------------------------------
// Table parser context (Ruby `Table::ParserContext`)

///|
priv struct TableParserContext {
  reader : Reader
  table : Node
  format : String
  mut colcount : Int
  mut buffer : String
  delimiter : String
  delimiter_rx : @regex.Regex
  cellspecs : Array[Attributes?]
  mut cell_open : Bool
  active_rowspans : Array[Int]
  mut column_visits : Int
  mut current_row : Array[Node]
  mut linenum : Int
  start_cursor : Cursor
}

///|
fn TableParserContext::new(
  reader : Reader,
  table : Node,
  attributes : Attributes,
) -> TableParserContext {
  let start_cursor = reader.mark()
  let nested = table.document().is_nested()
  let mut format = "psv"
  let mut xsv = if nested { "!sv" } else { "psv" }
  match attributes.get("format") {
    Some(v) => {
      let f = v.to_s()
      if f == "psv" || f == "csv" || f == "dsv" || f == "tsv" {
        if f == "tsv" {
          format = "csv"
          xsv = "tsv"
        } else {
          format = f
          xsv = if f == "psv" && nested { "!sv" } else { f }
        }
      } else {
        log_error(
          "illegal table format: \{f}",
          source_location=reader.cursor_at_prev_line(),
        )
      }
    }
    None => ()
  }
  let default_delim = fn(x : String) -> String {
    match x {
      "psv" => "|"
      "csv" => ","
      "dsv" => ":"
      "tsv" => "\t"
      _ => "!"
    }
  }
  let delimiter = match attributes.get("separator") {
    Some(v) => {
      let sep = if v.truthy() { v.to_s() } else { "" }
      if sep == "" {
        default_delim(xsv)
      } else if sep == "\\t" {
        "\t"
      } else {
        sep
      }
    }
    None => default_delim(xsv)
  }
  let delimiter_rx = @regex.re(regex_escape(delimiter))
  let columns = table.table_data().columns
  {
    reader,
    table,
    format,
    colcount: if columns.is_empty() {
      -1
    } else {
      columns.length()
    },
    buffer: "",
    delimiter,
    delimiter_rx,
    cellspecs: [],
    cell_open: false,
    active_rowspans: [0],
    column_visits: 0,
    current_row: [],
    linenum: -1,
    start_cursor,
  }
}

///|
/// Escapes regex metacharacters (Ruby `Regexp.escape`).
pub fn regex_escape(s : String) -> String {
  let sb = StringBuilder()
  for c in s {
    match c {
      '.'
      | '*'
      | '?'
      | '+'
      | '^'
      | '$'
      | '|'
      | '('
      | ')'
      | '['
      | ']'
      | '{'
      | '}'
      | '\\'
      | '/'
      | '-' => {
        sb.write_char('\\')
        sb.write_char(c)
      }
      '\n' => sb.write_string("\\n")
      '\t' => sb.write_string("\\t")
      ' ' => sb.write_string("\\ ")
      _ => sb.write_char(c)
    }
  }
  sb.to_string()
}

///|
fn TableParserContext::skip_past_delimiter(
  self : TableParserContext,
  pre : String,
) -> Unit {
  self.buffer = "\{self.buffer}\{pre}\{self.delimiter}"
}

///|
fn TableParserContext::skip_past_escaped_delimiter(
  self : TableParserContext,
  pre : String,
) -> Unit {
  self.buffer = "\{self.buffer}\{@rb.chop(pre)}\{self.delimiter}"
}

///|
fn TableParserContext::buffer_has_unclosed_quotes(
  self : TableParserContext,
  append? : String,
) -> Bool {
  let q = "\""
  let record = match append {
    Some(a) => @rb.strip(self.buffer + a)
    None => @rb.strip(self.buffer)
  }
  if record == q {
    true
  } else if record.has_prefix(q) {
    let qq = q + q
    let trailing_quote = record.has_suffix(q)
    if (trailing_quote && record.has_suffix(qq)) || record.has_prefix(qq) {
      let r = record.replace_all(old=qq, new="")
      r.has_prefix(q) && !r.has_suffix(q)
    } else {
      !trailing_quote
    }
  } else {
    false
  }
}

///|
fn TableParserContext::push_cellspec(
  self : TableParserContext,
  spec : Attributes?,
) -> Unit {
  self.cellspecs.push(Some(spec.unwrap_or(Attributes::new())))
}

///|
fn TableParserContext::close_open_cell(
  self : TableParserContext,
  next_cellspec? : Attributes,
) -> Unit {
  self.push_cellspec(next_cellspec)
  if self.cell_open {
    self.close_cell(eol=true)
  }
  self.linenum += 1
}

///|
fn TableParserContext::close_cell(
  self : TableParserContext,
  eol? : Bool = false,
) -> Unit {
  let mut cell_text = ""
  let mut cellspec : Attributes? = None
  let mut repeat = 1
  if self.format == "psv" {
    cell_text = self.buffer
    self.buffer = ""
    if self.cellspecs.is_empty() {
      log_error(
        "table missing leading separator; recovering automatically",
        source_location=self.start_cursor.dup(),
      )
      cellspec = Some(Attributes::new())
    } else {
      let spec = self.cellspecs.remove(0).unwrap_or(Attributes::new())
      repeat = match spec.remove("repeatcol") {
        Some(v) => v.to_i()
        None => 1
      }
      cellspec = Some(spec)
    }
  } else {
    cell_text = @rb.strip(self.buffer)
    self.buffer = ""
    if self.format == "csv" && cell_text != "" && cell_text.contains("\"") {
      if cell_text.has_prefix("\"") && cell_text.has_suffix("\"") {
        if cell_text.length() >= 2 {
          cell_text = @rb.squeeze(
            @rb.strip(@rb.slice(cell_text, 1, cell_text.length() - 1)),
            chars="\"",
          )
        } else {
          log_error(
            "unclosed quote in CSV data; setting cell to empty",
            source_location=self.reader.cursor_at_prev_line(),
          )
          cell_text = ""
        }
      } else {
        cell_text = @rb.squeeze(cell_text, chars="\"")
      }
    }
  }
  let table = self.table
  let td = table.table_data()
  for i in 1..<=repeat {
    let column = if self.colcount == -1 {
      let col = Node::new_table_column(
        table,
        td.columns.length() + i - 1,
        Attributes::new(),
      )
      td.columns.push(col)
      match cellspec {
        Some(spec) =>
          match spec.get("colspan") {
            Some(cs) => {
              let extra = cs.to_i() - 1
              if extra > 0 {
                let offset = td.columns.length()
                for j in 0..<extra {
                  td.columns.push(
                    Node::new_table_column(table, offset + j, Attributes::new()),
                  )
                }
              }
            }
            None => ()
          }
        None => ()
      }
      Some(col)
    } else {
      td.columns.get(self.current_row.length())
    }
    let cursor_before_mark = self.reader.cursor_before_mark()
    let cell = Node::new_table_cell(
      column,
      cell_text,
      cellspec,
      Some(cursor_before_mark),
    )
    self.reader.mark() |> ignore
    let cd = cell.cell_data()
    match cd.rowspan {
      Some(rs) if rs != 1 => self.activate_rowspan(rs, cd.colspan.unwrap_or(1))
      _ => ()
    }
    self.column_visits += cd.colspan.unwrap_or(1)
    self.current_row.push(cell)
    let row_status = self.end_of_row()
    if row_status > -1 &&
      (self.colcount != -1 || self.linenum > 0 || (eol && i == repeat)) {
      if row_status > 0 {
        log_error(
          "dropping cell because it exceeds specified number of columns",
          source_location=cursor_before_mark,
        )
        self.close_row(drop=true)
      } else {
        self.close_row()
      }
    }
  }
  self.cell_open = false
}

///|
fn TableParserContext::close_table(self : TableParserContext) -> Unit {
  if self.column_visits == 0 {
    return
  }
  log_error(
    "dropping cells from incomplete row detected end of table",
    source_location=self.reader.cursor_before_mark(),
  )
}

///|
fn TableParserContext::close_row(
  self : TableParserContext,
  drop? : Bool = false,
) -> Unit {
  if !drop {
    self.table.table_data().rows.body.push(self.current_row)
  }
  if self.colcount == -1 {
    self.colcount = self.column_visits
  }
  self.column_visits = 0
  self.current_row = []
  self.active_rowspans.remove(0) |> ignore
  if self.active_rowspans.is_empty() {
    self.active_rowspans.push(0)
  }
}

///|
fn TableParserContext::activate_rowspan(
  self : TableParserContext,
  rowspan : Int,
  colspan : Int,
) -> Unit {
  for i in 1..<rowspan {
    while self.active_rowspans.length() <= i {
      self.active_rowspans.push(0)
    }
    self.active_rowspans[i] = self.active_rowspans[i] + colspan
  }
}

///|
fn TableParserContext::end_of_row(self : TableParserContext) -> Int {
  if self.colcount == -1 {
    0
  } else {
    let v = self.column_visits + self.active_rowspans[0]
    if v < self.colcount {
      -1
    } else if v == self.colcount {
      0
    } else {
      1
    }
  }
}
