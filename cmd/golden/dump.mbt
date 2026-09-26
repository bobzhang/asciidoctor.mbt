///|
/// Converts an attribute value to JSON as Ruby's harvester does.
fn attr_json(v : @core.AttrVal) -> Json {
  match v {
    Str(s) => Json::string(s)
    Int(i) => Json::number(i.to_double())
    Float(f) => Json::number(f)
    Bool(b) => Json::boolean(b)
    List(l) => Json::array(l.map(Json::string))
    Nil => Json::null()
  }
}

///|
fn key_json(k : @core.AttrKey) -> Json {
  match k {
    Name(n) => Json::string(n)
    Pos(i) => Json::number(i.to_double())
  }
}

///|
fn attrs_json(attrs : @core.Attributes) -> Json {
  let out = []
  for k, v in attrs.iter() {
    out.push(Json::array([key_json(k), attr_json(v)]))
  }
  Json::array(out)
}

///|
fn is_date_attr(k : String) -> Bool {
  (k.has_prefix("local") || k.has_prefix("doc")) &&
  (
    k.has_suffix("date") ||
    k.has_suffix("time") ||
    k.has_suffix("year") ||
    k.has_suffix("datetime")
  )
}

///|
/// Canonical AST dump matching scripts/harvest/harvest.rb.
fn dump_node(node : @core.Node) -> Json {
  let d : Map[String, Json] = Map([])
  let ctx = node.context.name()
  d["context"] = Json::string(ctx)
  if node.node_name != ctx {
    d["node_name"] = Json::string(node.node_name)
  }
  match node.id {
    Some(id) => d["id"] = Json::string(id)
    None => ()
  }
  match node.style {
    Some(s) => d["style"] = Json::string(s)
    None => ()
  }
  d["level"] = Json::number(node.level.to_double())
  match node.raw_title() {
    Some(t) => d["title"] = Json::string(t)
    None => ()
  }
  match node.numeral {
    Some(n) => d["numeral"] = Json::string(n)
    None => ()
  }
  if node.content_model != Compound {
    d["content_model"] = Json::string(node.content_model.name())
  }
  if !node.subs.is_empty() {
    d["subs"] = Json::array(node.subs.map(s => Json::string(s.name())))
  }
  match node.context {
    Document => {
      let header = match node.header() {
        Some(h) =>
          match h.raw_title() {
            Some(t) => Json::string(t)
            None => Json::null()
          }
        None => Json::null()
      }
      d["header"] = Json::object({ "doctitle": header })
      let pairs = []
      for k, v in node.attributes.iter() {
        match k {
          Name(n) => if !is_date_attr(n) { pairs.push((n, v)) }
          _ => ()
        }
      }
      pairs.sort_by((x, y) => @rb.lex_compare(x.0, y.0))
      d["attributes"] = Json::array(
        pairs.map(p => Json::array([Json::string(p.0), attr_json(p.1)])),
      )
    }
    _ =>
      if !node.attributes.is_empty() &&
        !(node.attributes.length() == 0 && node.attributes.entries is Some(_)) {
        d["attributes"] = attrs_json(node.attributes)
      }
  }
  match node.context {
    Section => {
      d["sectname"] = match node.sectname {
        Some(s) => Json::string(s)
        None => Json::null()
      }
      if node.special {
        d["special"] = Json::boolean(true)
      }
      if node.numbered != NotNumbered {
        d["numbered"] = Json::boolean(true)
      }
    }
    ListItem => {
      d["text"] = match node.raw_text() {
        Some(t) => Json::string(t)
        None => Json::null()
      }
      match node.marker {
        Some(m) => d["marker"] = Json::string(m)
        None => ()
      }
    }
    Table => {
      let rows = node.rows()
      d["rows"] = Json::array(
        [rows.head, rows.body, rows.foot].map(section => {
          Json::array(section.map(row => Json::array(row.map(dump_cell))))
        }),
      )
      d["columns"] = Json::array(
        node.columns().map(c => attrs_json(c.attributes)),
      )
    }
    _ =>
      if node.is_block() && !node.is_list() && !node.lines.is_empty() {
        d["lines"] = Json::array(node.lines.map(Json::string))
      }
  }
  if node.context == Dlist {
    d["items"] = Json::array(
      node.dlist_items.map(item => {
        Json::object({
          "terms": Json::array(item.terms.map(dump_node)),
          "desc": match item.desc {
            Some(dd) => dump_node(dd)
            None => Json::null()
          },
        })
      }),
    )
  } else if !node.blocks.is_empty() {
    d["blocks"] = Json::array(node.blocks.map(dump_node))
  }
  Json::object(d)
}

///|
fn dump_cell(cell : @core.Node) -> Json {
  let c : Map[String, Json] = {
    "text": Json::string(cell.raw_text().unwrap_or("")),
    "style": match cell.style {
      Some(s) => Json::string(s)
      None => Json::null()
    },
  }
  match cell.colspan() {
    Some(v) => c["colspan"] = Json::number(v.to_double())
    None => ()
  }
  match cell.rowspan() {
    Some(v) => c["rowspan"] = Json::number(v.to_double())
    None => ()
  }
  match cell.inner_document() {
    Some(d) => c["inner"] = dump_node(d)
    None => ()
  }
  Json::object(c)
}

///|
/// Normalizes a JSON value: drops `attribute_entries` pairs and formats numbers
/// so integral doubles compare equal regardless of representation.
fn canon(j : Json) -> String {
  let sb = StringBuilder()
  canon_into(j, sb)
  sb.to_string()
}

///|
fn canon_into(j : Json, sb : StringBuilder) -> Unit {
  match j {
    Null => sb.write_string("null")
    True => sb.write_string("true")
    False => sb.write_string("false")
    Number(n, ..) =>
      if n == n.floor() && n.abs() < 1.0e15 {
        sb.write_string(n.to_int64().to_string())
      } else {
        sb.write_string(n.to_string())
      }
    String(s) => sb.write_string(s.escape())
    Array(a) => {
      sb.write_char('[')
      let mut first = true
      for x in a {
        // skip ["attribute_entries", ...] pairs
        if x is Array([String("attribute_entries"), ..]) {
          continue
        }
        if !first {
          sb.write_char(',')
        }
        first = false
        canon_into(x, sb)
      }
      sb.write_char(']')
    }
    Object(m) => {
      let keys = m.keys().collect()
      keys.sort()
      sb.write_char('{')
      let mut first = true
      for k in keys {
        let v = m[k]
        // an attributes list containing only attribute_entries is treated as absent
        if k == "attributes" &&
          v is Array(items) &&
          items.iter().all(x => x is Array([String("attribute_entries"), ..])) {
          continue
        }
        if !first {
          sb.write_char(',')
        }
        first = false
        sb.write_string(k.escape())
        sb.write_char(':')
        canon_into(v, sb)
      }
      sb.write_char('}')
    }
  }
}
