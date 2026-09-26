///|
/// A growable array whose slots may be unset (Ruby arrays with nil holes).
priv struct Slots[T] {
  items : Array[T?]
}

///|
fn[T] Slots::new() -> Slots[T] {
  { items: [], }
}

///|
fn[T] Slots::get(self : Slots[T], i : Int) -> T? {
  match self.items.get(i) {
    Some(v) => v
    None => None
  }
}

///|
fn[T] Slots::set(self : Slots[T], i : Int, v : T) -> Unit {
  while self.items.length() <= i {
    self.items.push(None)
  }
  self.items[i] = Some(v)
}

///|
/// Ruby `slots[i] ||= init()`.
fn[T] Slots::ensure(self : Slots[T], i : Int, init : () -> T) -> T {
  match self.get(i) {
    Some(v) => v
    None => {
      let v = init()
      self.set(i, v)
      v
    }
  }
}

///|
fn[T] Slots::is_empty(self : Slots[T]) -> Bool {
  self.items.is_empty()
}

///|
fn slot_is_empty(cell : Array[String]?) -> Bool {
  match cell {
    Some(c) => c.is_empty()
    None => true
  }
}

///|
/// NOTE This handler inserts empty cells to account for colspans and rowspans.
/// In order to support colspans and rowspans properly, that information must
/// be computed up front and consulted when rendering the cell as this
/// information is not available on the cell itself.
fn ManPageConverter::convert_table(
  self : ManPageConverter,
  node : @core.Node,
) -> String {
  ignore(self)
  let result = []
  if node.has_title() {
    result.push(
      ".sp\n.it 1 an-trap\n.nr an-no-space-flag 1\n.nr an-break-flag 1\n.br\n.B \{manify(node.captioned_title())}\n",
    )
  }
  result.push(".TS\nallbox tab(:);")
  let row_header : Slots[Slots[Array[String]]] = Slots::new()
  let row_text : Slots[Array[String]] = Slots::new()
  let mut row_index = 0
  let rows = node.rows()
  for tsec in [("head", rows.head), ("body", rows.body), ("foot", rows.foot)] {
    let (tsec_name, section_rows) = tsec
    for row in section_rows {
      let header = row_header.ensure(row_index, Slots::new)
      let text = row_text.ensure(row_index, () => [])
      let mut remaining_cells = row.length()
      for cell_index, cell in row {
        remaining_cells -= 1
        let this_header = header.ensure(cell_index, () => [])
        // add an empty cell as a placeholder if this is a rowspan cell
        if this_header.length() == 1 && this_header[0] == "^t" {
          text.push("T{\nT}:")
        }
        text.push("T{\n")
        let cell_halign = @rb.take(
          cell.attr("halign", default="left").unwrap_or("left"),
          1,
        )
        let spec = if tsec_name == "body" {
          "\{cell_halign}t"
        } else {
          "\{cell_halign}tB"
        }
        if header.is_empty() || slot_is_empty(header.get(cell_index)) {
          this_header.push(spec)
        } else {
          header.ensure(cell_index + 1, () => []).push(spec)
        }
        if tsec_name == "body" {
          let cell_content = match cell.style {
            Some("asciidoc") => cell.cell_paragraphs().join("\n")
            Some("literal") =>
              ".nf\n\{manify(cell.text().unwrap_or(""), whitespace=Preserve)}\n.fi"
            _ =>
              cell
              .cell_paragraphs()
              .map(p => manify(p, whitespace=Normalize))
              .join("\n.sp\n")
          }
          text.push("\{cell_content}\n")
        } else {
          text.push(
            "\{manify(cell.text().unwrap_or(""), whitespace=Normalize)}\n",
          )
        }
        match cell.colspan() {
          Some(colspan) if colspan > 1 =>
            for i in 0..<(colspan - 1) {
              if header.is_empty() || slot_is_empty(header.get(cell_index)) {
                header.ensure(cell_index + i, () => []).push("st")
              } else {
                header.ensure(cell_index + 1 + i, () => []).push("st")
              }
            }
          _ => ()
        }
        match cell.rowspan() {
          Some(rowspan) if rowspan > 1 =>
            for i in 0..<(rowspan - 1) {
              let next = row_header.ensure(row_index + 1 + i, Slots::new)
              if next.is_empty() || slot_is_empty(next.get(cell_index)) {
                next.ensure(cell_index, () => []).push("^t")
              } else {
                next.ensure(cell_index + 1, () => []).push("^t")
              }
            }
          _ => ()
        }
        if remaining_cells >= 1 {
          text.push("T}:")
        } else {
          text.push("T}\n")
        }
      }
      row_index += 1
    }
  }
  let header_row = row_header.get(0).unwrap_or(Slots::new())
  let mut texts = row_text.items.map(r => r.unwrap_or([]))
  if node.table_data().has_header_option is (ExplicitHeader | ImplicitHeader) &&
    row_text.get(0) is Some(header_row_text) {
    let spec = header_row.items
      .map(c => {
        match c {
          Some(c) => c.join(" ")
          None => ""
        }
      })
      .join(" ")
    result.push("\n\{spec}.")
    result.push("\n\{header_row_text.join("")}")
    result.push(".T&")
    texts = texts[1:].to_owned()
  }
  result.push("\n\{header_row.items.map(_ => "lt").join(" ")}.\n")
  for row in texts {
    result.push(row.join(""))
  }
  result.push(".TE\n.sp")
  result.join("")
}
