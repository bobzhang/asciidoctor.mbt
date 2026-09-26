///|
fn table_cell_halign(s : String) -> String? {
  match s {
    "<" => Some("left")
    ">" => Some("right")
    "^" => Some("center")
    _ => None
  }
}

///|
fn table_cell_valign(s : String) -> String? {
  match s {
    "<" => Some("top")
    ">" => Some("bottom")
    "^" => Some("middle")
    _ => None
  }
}

///|
fn table_cell_style(s : String) -> String? {
  match s {
    "d" => Some("none")
    "s" => Some("strong")
    "e" => Some("emphasis")
    "m" => Some("monospaced")
    "h" => Some("header")
    "l" => Some("literal")
    "a" => Some("asciidoc")
    _ => None
  }
}

///|
/// Parses a table (Ruby `Parser.parse_table`).
fn parse_table(
  table_reader : Reader,
  parent : Node,
  attributes : Attributes,
) -> Node {
  let table = Node::new_table(parent, attributes)
  let td = table.table_data()
  let mut explicit_colspecs = false
  match attributes.str("cols") {
    Some(cols) if attributes.contains("cols") => {
      let colspecs = parse_colspecs(cols)
      if !colspecs.is_empty() {
        table.create_columns(colspecs)
        explicit_colspecs = true
      }
    }
    _ => ()
  }
  let skipped = table_reader.skip_blank_lines().unwrap_or(0)
  let mut implicit_header = false
  if attributes.truthy("header-option") {
    td.has_header_option = ExplicitHeader
  } else if skipped == 0 && !attributes.truthy("noheader-option") {
    td.has_header_option = ImplicitHeader
    implicit_header = true
  }
  let parser_ctx = TableParserContext::new(table_reader, table, attributes)
  let format = parser_ctx.format
  let mut loop_idx = -1
  let mut implicit_header_boundary : Int? = None
  while table_reader.read_line() is Some(line0) {
    let mut line : String? = Some(line0)
    loop_idx += 1
    let beyond_first = loop_idx > 0
    if beyond_first && line0 == "" {
      line = None
      match implicit_header_boundary {
        Some(b) => implicit_header_boundary = Some(b + 1)
        None => ()
      }
    } else if format == "psv" {
      let l = line0
      if l.has_prefix(parser_ctx.delimiter) {
        line = Some(@rb.from(l, parser_ctx.delimiter.length()))
        parser_ctx.close_open_cell()
        if implicit_header_boundary is Some(_) {
          implicit_header_boundary = None
        }
      } else {
        let (next_cellspec, rest) = parse_cellspec(
          l,
          start=true,
          delimiter=parser_ctx.delimiter,
        )
        line = Some(rest)
        match next_cellspec {
          Some(spec) => {
            parser_ctx.close_open_cell(next_cellspec=spec)
            if implicit_header_boundary is Some(_) {
              implicit_header_boundary = None
            }
          }
          None =>
            if implicit_header_boundary == Some(loop_idx) {
              td.has_header_option = UnsetHeader
              implicit_header = false
              implicit_header_boundary = None
            }
        }
      }
    }
    if !beyond_first {
      table_reader.mark() |> ignore
      if implicit_header {
        if table_reader.has_more_lines() && table_reader.peek_line() == Some("") {
          implicit_header_boundary = Some(1)
        } else {
          td.has_header_option = UnsetHeader
          implicit_header = false
        }
      }
    }
    while true {
      let m = match line {
        Some(l) => parser_ctx.delimiter_rx.find(l)
        None => None
      }
      match m {
        Some(m) => {
          let pre_match = m.pre_match()
          let post_match = m.post_match()
          match format {
            "csv" => {
              if parser_ctx.buffer_has_unclosed_quotes(append=pre_match) {
                parser_ctx.skip_past_delimiter(pre_match)
                if post_match == "" {
                  break
                }
                line = Some(post_match)
                continue
              }
              parser_ctx.buffer = parser_ctx.buffer + pre_match
            }
            "dsv" => {
              if pre_match.has_suffix("\\") {
                parser_ctx.skip_past_escaped_delimiter(pre_match)
                if post_match == "" {
                  parser_ctx.buffer = parser_ctx.buffer + "\n"
                  parser_ctx.cell_open = true
                  break
                }
                line = Some(post_match)
                continue
              }
              parser_ctx.buffer = parser_ctx.buffer + pre_match
            }
            _ => {
              if pre_match.has_suffix("\\") {
                parser_ctx.skip_past_escaped_delimiter(pre_match)
                if post_match == "" {
                  parser_ctx.buffer = parser_ctx.buffer + "\n"
                  parser_ctx.cell_open = true
                  break
                }
                line = Some(post_match)
                continue
              }
              let (next_cellspec, cell_text) = parse_cellspec(pre_match)
              parser_ctx.push_cellspec(next_cellspec)
              parser_ctx.buffer = parser_ctx.buffer + cell_text
            }
          }
          line = if post_match == "" { None } else { Some(post_match) }
          parser_ctx.close_cell()
        }
        None => {
          parser_ctx.buffer = "\{parser_ctx.buffer}\{line.unwrap_or("")}\n"
          match format {
            "csv" =>
              if parser_ctx.buffer_has_unclosed_quotes() {
                if implicit_header_boundary is Some(_) && loop_idx == 0 {
                  td.has_header_option = UnsetHeader
                  implicit_header = false
                  implicit_header_boundary = None
                }
                parser_ctx.cell_open = true
              } else {
                parser_ctx.close_cell(eol=true)
              }
            "dsv" => parser_ctx.close_cell(eol=true)
            _ => parser_ctx.cell_open = true
          }
          break
        }
      }
    }
    if parser_ctx.cell_open {
      if !table_reader.has_more_lines() {
        parser_ctx.close_cell(eol=true)
      }
    } else if table_reader.skip_blank_lines() is None {
      break
    }
  }
  parser_ctx.close_table()
  let colcount = match table.attributes.get("colcount") {
    Some(v) if v.truthy() => v.to_i()
    _ => {
      table.attributes.set("colcount", Int(td.columns.length()))
      td.columns.length()
    }
  }
  if !(colcount == 0 || explicit_colspecs) {
    table.assign_column_widths()
  }
  if implicit_header {
    td.has_header_option = ExplicitHeader
  }
  table.partition_header_footer(attributes)
  table
}

///|
/// Parses the cols attribute (Ruby `parse_colspecs`).
fn parse_colspecs(records0 : String) -> Array[ColSpec] {
  let records = if records0.contains(" ") {
    @rb.delete_chars(records0, " ")
  } else {
    records0
  }
  if records == @rb.to_i(records).to_string() {
    let n = @rb.to_i(records)
    return Array::makei(n, _ => {
      width: 1,
      halign: None,
      valign: None,
      style: None,
    })
  }
  let specs = []
  let parts = if records.contains(",") {
    @rb.split(records, ",", limit=-1)
  } else {
    @rb.split(records, ";", limit=-1)
  }
  for record in parts {
    if record == "" {
      specs.push({ width: 1, halign: None, valign: None, style: None, })
    } else {
      match column_spec_rx.find(record) {
        Some(m) => {
          let spec : ColSpec = {
            width: 1,
            halign: None,
            valign: None,
            style: None,
          }
          match m.group(2) {
            Some(g2) => {
              let parts2 = @rb.split(g2, ".")
              match parts2.get(0) {
                Some(colspec) if colspec != "" =>
                  spec.halign = table_cell_halign(colspec)
                _ => ()
              }
              match parts2.get(1) {
                Some(rowspec) if rowspec != "" =>
                  spec.valign = table_cell_valign(rowspec)
                _ => ()
              }
            }
            None => ()
          }
          match m.group(3) {
            Some(width) =>
              spec.width = if width == "~" { -1 } else { @rb.to_i(width) }
            None => spec.width = 1
          }
          match m.group(4) {
            Some(s) => spec.style = table_cell_style(s)
            None => ()
          }
          match m.group(1) {
            Some(repeat) =>
              for _ in 0..<@rb.to_i(repeat) {
                specs.push({ ..spec, })
              }
            None => specs.push(spec)
          }
        }
        None => ()
      }
    }
  }
  specs
}

///|
/// Parses a cell spec (Ruby `parse_cellspec`): returns (spec or None, rest).
fn parse_cellspec(
  line : String,
  start? : Bool = false,
  delimiter? : String = "",
) -> (Attributes?, String) {
  let mut m : @regex.MatchData? = None
  let mut rest = ""
  if start {
    if !line.contains(delimiter) {
      return (None, line)
    }
    let (spec_part, _, r) = @rb.partition(line, delimiter)
    rest = r
    match cell_spec_start_rx.find(spec_part) {
      Some(mm) => {
        if mm.matched() == "" {
          return (Some(Attributes::new()), rest)
        }
        m = Some(mm)
      }
      None => return (None, line)
    }
  } else {
    match cell_spec_end_rx.find(line) {
      Some(mm) => {
        if @rb.lstrip(mm.matched()) == "" {
          return (Some(Attributes::new()), @rb.rstrip(line))
        }
        rest = mm.pre_match()
        m = Some(mm)
      }
      None => return (Some(Attributes::new()), line)
    }
  }
  let m = m.unwrap()
  let spec = Attributes::new()
  match m.group(1) {
    Some(g1) => {
      let parts = @rb.split(g1, ".")
      let colspec = match parts.get(0) {
        Some(c) if c != "" => @rb.to_i(c)
        _ => 1
      }
      let rowspec = match parts.get(1) {
        Some(r) if r != "" => @rb.to_i(r)
        _ => 1
      }
      match m.group(2) {
        Some("+") => {
          if colspec != 1 {
            spec.set("colspan", Int(colspec))
          }
          if rowspec != 1 {
            spec.set("rowspan", Int(rowspec))
          }
        }
        Some("*") => if colspec != 1 { spec.set("repeatcol", Int(colspec)) }
        _ => ()
      }
    }
    None => ()
  }
  match m.group(3) {
    Some(g3) => {
      let parts = @rb.split(g3, ".")
      match parts.get(0) {
        Some(c) if c != "" =>
          match table_cell_halign(c) {
            Some(h) => spec.set_str("halign", h)
            None => ()
          }
        _ => ()
      }
      match parts.get(1) {
        Some(r) if r != "" =>
          match table_cell_valign(r) {
            Some(v) => spec.set_str("valign", v)
            None => ()
          }
        _ => ()
      }
    }
    None => ()
  }
  match m.group(4) {
    Some(g4) =>
      match table_cell_style(g4) {
        Some(s) => spec.set_str("style", s)
        None => ()
      }
    None => ()
  }
  (Some(spec), rest)
}
