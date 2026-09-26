///|
/// Parses an attribute list string (Ruby `AttributeList`).
priv struct AttributeListParser {
  src : String
  mut pos : Int
  block : Node?
  delimiter : String
  attributes : Attributes
}

///|
fn AttributeListParser::eos(self : AttributeListParser) -> Bool {
  self.pos >= self.src.length()
}

///|
fn AttributeListParser::peek(self : AttributeListParser) -> String {
  if self.pos < self.src.length() {
    self.src.unsafe_substring(start=self.pos, end=self.pos + 1)
  } else {
    ""
  }
}

///|
/// Reads one character (a whole code point).
fn AttributeListParser::get_char(self : AttributeListParser) -> String? {
  if self.pos >= self.src.length() {
    return None
  }
  let c = self.src[self.pos]
  let w = if c >= 0xD800 && c <= 0xDBFF && self.pos + 1 < self.src.length() {
    2
  } else {
    1
  }
  let s = self.src.unsafe_substring(start=self.pos, end=self.pos + w)
  self.pos += w
  Some(s)
}

///|
fn AttributeListParser::scan(
  self : AttributeListParser,
  rx : @regex.Regex,
) -> String? {
  match rx.match_at(self.src, self.pos) {
    Some(m) => {
      self.pos = m.end()
      Some(m.matched())
    }
    None => None
  }
}

///|
fn AttributeListParser::skip(
  self : AttributeListParser,
  rx : @regex.Regex,
) -> Int? {
  match rx.match_at(self.src, self.pos) {
    Some(m) => {
      let len = m.end() - m.begin()
      self.pos = m.end()
      Some(len)
    }
    None => None
  }
}

///|
let attribute_list_quot_boundary_rx : @regex.Regex = @regex.re(
  ".*?[^\\\\](?=\")",
)

///|
let attribute_list_apos_boundary_rx : @regex.Regex = @regex.re(
  ".*?[^\\\\](?=')",
)

///|
let attribute_list_comma_boundary_rx : @regex.Regex = @regex.re(
  ".*?(?=[ \\t]*(,|$))",
)

///|
let attribute_list_comma_skip_rx : @regex.Regex = @regex.re("[ \\t]*(,|$)")

///|
fn AttributeListParser::scan_to_delimiter(self : AttributeListParser) -> String {
  let rx = if self.delimiter == "," {
    attribute_list_comma_boundary_rx
  } else {
    @regex.re(".*?(?=[ \\t]*(\{regex_escape(self.delimiter)}|$))")
  }
  self.scan(rx).unwrap_or("")
}

///|
fn AttributeListParser::skip_delimiter(self : AttributeListParser) -> Unit {
  let rx = if self.delimiter == "," {
    attribute_list_comma_skip_rx
  } else {
    @regex.re("[ \\t]*(\{regex_escape(self.delimiter)}|$)")
  }
  self.skip(rx) |> ignore
}

///|
fn AttributeListParser::parse_attribute_value(
  self : AttributeListParser,
  quote : String,
) -> String {
  if self.peek() == quote {
    self.pos += 1
    return ""
  }
  let rx = if quote == "\"" {
    attribute_list_quot_boundary_rx
  } else {
    attribute_list_apos_boundary_rx
  }
  match self.scan(rx) {
    Some(value) => {
      self.pos += 1
      if value.contains("\\") {
        value.replace_all(old="\\" + quote, new=quote)
      } else {
        value
      }
    }
    None => "\{quote}\{self.scan_to_delimiter()}"
  }
}

///|
fn AttributeListParser::parse_attribute(
  self : AttributeListParser,
  index : Int,
  positional_attrs : Array[String?],
) -> Bool {
  let mut continue_ = true
  self.skip(attribute_list_blank_rx) |> ignore
  let mut name : String? = None
  let mut value : String? = None
  let mut single_quoted = false
  let first = self.peek()
  if first == "\"" {
    self.pos += 1
    name = Some(self.parse_attribute_value("\""))
  } else if first == "'" {
    self.pos += 1
    let n = self.parse_attribute_value("'")
    name = Some(n)
    if !n.has_prefix("'") {
      single_quoted = true
    }
  } else {
    name = self.scan(attribute_list_name_rx)
    let skipped = match name {
      Some(_) => self.skip(attribute_list_blank_rx).unwrap_or(0)
      None => 0
    }
    if self.eos() {
      if !(name is Some(_) || @rb.rstrip(self.src).has_suffix(self.delimiter)) {
        return false
      }
      continue_ = false
    } else {
      let c = self.get_char().unwrap()
      if c == self.delimiter {
        self.pos -= c.length()
      } else {
        match name {
          Some(n) =>
            if c == "=" {
              self.skip(attribute_list_blank_rx) |> ignore
              match self.get_char() {
                Some("\"") => value = Some(self.parse_attribute_value("\""))
                Some("'") => {
                  let v = self.parse_attribute_value("'")
                  value = Some(v)
                  if !v.has_prefix("'") {
                    single_quoted = true
                  }
                }
                Some(c2) if c2 == self.delimiter => {
                  value = Some("")
                  self.pos -= c2.length()
                }
                None => value = Some("")
                Some(c2) => {
                  let v = "\{c2}\{self.scan_to_delimiter()}"
                  if v == "None" {
                    return true
                  }
                  value = Some(v)
                }
              }
            } else {
              name = Some(
                "\{n}\{@rb.repeat(" ", skipped)}\{c}\{self.scan_to_delimiter()}",
              )
            }
          None => name = Some("\{c}\{self.scan_to_delimiter()}")
        }
      }
    }
  }
  match value {
    Some(v) => {
      let n = name.unwrap_or("")
      if n == "options" || n == "opts" {
        if v.contains(",") {
          let v2 = if v.contains(" ") { @rb.delete_chars(v, " ") } else { v }
          for opt in @rb.split(v2, ",") {
            if opt != "" {
              self.attributes.set_str("\{opt}-option", "")
            }
          }
        } else if v != "" {
          self.attributes.set_str("\{v}-option", "")
        }
      } else if single_quoted && self.block is Some(block) {
        if n == "title" || n == "reftext" {
          self.attributes.set_str(n, v)
        } else {
          self.attributes.set_str(n, block.apply_subs(v, normal_subs))
        }
      } else {
        self.attributes.set_str(n, v)
      }
    }
    None => {
      let name = match (name, self.block) {
        (Some(n), Some(block)) if single_quoted =>
          Some(block.apply_subs(n, normal_subs))
        _ => name
      }
      match (positional_attrs.get(index), name) {
        (Some(Some(pname)), Some(n)) => self.attributes.set_str(pname, n)
        _ => ()
      }
      self.attributes.set_pos(
        index + 1,
        match name {
          Some(n) => Str(n)
          None => Nil
        },
      )
    }
  }
  continue_
}

///|
/// Parses an attribute list into a new Attributes map.
pub fn parse_attribute_list(
  source : String,
  positional_attrs? : Array[String?] = [],
  block? : Node,
  delimiter? : String = ",",
) -> Attributes {
  let p : AttributeListParser = {
    src: source,
    pos: 0,
    block,
    delimiter,
    attributes: Attributes::new(),
  }
  let mut index = 0
  while p.parse_attribute(index, positional_attrs) {
    if p.eos() {
      break
    }
    p.skip_delimiter()
    index += 1
  }
  p.attributes
}

///|
/// Copies positional attributes to named keys (Ruby `AttributeList.rekey`).
pub fn rekey_attributes(
  attributes : Attributes,
  positional_attrs : Array[String?],
) -> Attributes {
  for index, key in positional_attrs {
    match key {
      Some(k) =>
        match attributes.get_pos(index + 1) {
          Some(v) if v.truthy() => attributes.set(k, v)
          _ => ()
        }
      None => ()
    }
  }
  attributes
}
