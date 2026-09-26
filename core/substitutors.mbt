///|
/// A passthrough extracted before substitutions and restored afterwards.
priv struct Passthrough {
  text : String
  subs : Array[Sub]?
  type_ : String?
  attributes : Attributes?
}

///|
pub let basic_subs : Array[Sub] = [SpecialCharacters]

///|
pub let header_subs : Array[Sub] = [SpecialCharacters, Attributes]

///|
pub let no_subs : Array[Sub] = []

///|
pub let normal_subs : Array[Sub] = [
  SpecialCharacters,
  Quotes,
  Attributes,
  Replacements,
  Macros,
  PostReplacements,
]

///|
pub let reftext_subs : Array[Sub] = [SpecialCharacters, Quotes, Replacements]

///|
pub let verbatim_subs : Array[Sub] = [SpecialCharacters, Callouts]

///|
let pass_start : String = "\u{96}"

///|
let pass_end : String = "\u{97}"

///|
let can_char : String = "\u{18}"

///|
let del_char : String = "\u{7f}"

///|
/// Escapes `<`, `>` and `&` (Ruby `sub_specialchars`).
pub fn sub_specialchars(text : String) -> String {
  if !(text.contains(">") || text.contains("&") || text.contains("<")) {
    return text
  }
  let sb = StringBuilder(size_hint=text.length() + 16)
  for c in text {
    match c {
      '<' => sb.write_string("&lt;")
      '>' => sb.write_string("&gt;")
      '&' => sb.write_string("&amp;")
      _ => sb.write_char(c)
    }
  }
  sb.to_string()
}

///|
/// Ruby `sprintf(format, arg)` for a format with one `%s`.
pub fn sub_placeholder(format : String, arg : String) -> String {
  match format.find("%s") {
    Some(i) => @rb.slice(format, 0, i) + arg + @rb.from(format, i + 2)
    None => format
  }
}

///|
/// Applies substitutions to text (Ruby `apply_subs`).
pub fn Node::apply_subs(
  self : Node,
  text : String,
  subs : Array[Sub],
) -> String {
  if text == "" || subs.is_empty() {
    return text
  }
  let mut text = text
  let mut passthrus = false
  let mut clear_passthrus = false
  if subs.contains(Macros) {
    text = self.extract_passthroughs(text)
    if !self.passthroughs.is_empty() {
      passthrus = true
      if !self.passthroughs_locked {
        self.passthroughs_locked = true
        clear_passthrus = true
      }
    }
  }
  for type_ in subs {
    match type_ {
      SpecialCharacters => text = sub_specialchars(text)
      Quotes => text = self.sub_quotes(text)
      Attributes => if text.contains("{") { text = self.sub_attributes(text) }
      Replacements => text = self.sub_replacements(text)
      Macros => text = self.sub_macros(text)
      Highlight => text = self.highlight_source(text, subs.contains(Callouts))
      Callouts =>
        if !subs.contains(Highlight) {
          text = self.sub_callouts(text)
        }
      PostReplacements => text = self.sub_post_replacements(text)
    }
  }
  if passthrus {
    text = self.restore_passthroughs(text)
    if clear_passthrus {
      self.passthroughs.clear()
      self.passthroughs_locked = false
    }
  }
  text
}

///|
/// Applies substitutions to lines (Ruby `apply_subs` with an Array).
pub fn Node::apply_subs_lines(
  self : Node,
  lines : Array[String],
  subs : Array[Sub],
) -> Array[String] {
  if lines.is_empty() || subs.is_empty() {
    return lines.copy()
  }
  let text = if lines.length() > 1 { lines.join("\n") } else { lines[0] }
  if text == "" {
    return [text]
  }
  @rb.split(self.apply_subs(text, subs), "\n", limit=-1)
}

///|
pub fn Node::apply_normal_subs(self : Node, text : String) -> String {
  self.apply_subs(text, normal_subs)
}

///|
pub fn Node::apply_header_subs(self : Node, text : String) -> String {
  self.apply_subs(text, header_subs)
}

///|
pub fn Node::apply_title_subs(self : Node, text : String) -> String {
  self.apply_subs(text, normal_subs)
}

///|
pub fn Node::apply_reftext_subs(self : Node, text : String) -> String {
  self.apply_subs(text, reftext_subs)
}

///|
/// Applies inline quote substitutions.
pub fn Node::sub_quotes(self : Node, text : String) -> String {
  let compat = self.document().compat_mode()
  let sniff = quoted_text_sniff_rx
    .get(if compat { "true" } else { "false" })
    .unwrap()
  if !sniff.matches(text) {
    return text
  }
  let mut text = text
  for q in (if compat { quote_subs_compat } else { quote_subs_normal }) {
    let (type_, scope, pattern) = q
    text = pattern.replace(text, m => self.convert_quoted_text(m, type_, scope))
  }
  text
}

///|
/// Replaces attribute references (Ruby `sub_attributes`).
pub fn Node::sub_attributes(
  self : Node,
  text : String,
  attribute_missing? : String,
  drop_line_ignore? : Bool = false,
) -> String {
  let doc = self.document()
  let doc_attrs = doc.attributes
  let mut drop = false
  let mut drop_line = false
  let mut drop_empty_line = false
  let mut attribute_undefined : String? = None
  let mut attribute_missing_val : String? = attribute_missing
  let text = attribute_reference_rx.replace(text, m => {
    if m.group(1) == Some("\\") || m.group(4) == Some("\\") {
      return "{\{m.at(2)}}"
    }
    if m.has(3) {
      let args = @rb.split(m.at(2), ":", limit=3)
      let directive = args.remove(0)
      match directive {
        "set" => {
          let (_, value) = store_attribute(
            args.get(0).unwrap_or(""),
            Some(args.get(1).unwrap_or("")),
            doc=Some(doc),
            attrs=None,
          )
          let undefined = match attribute_undefined {
            Some(u) => u
            None => {
              let u = doc_attrs
                .str("attribute-undefined")
                .unwrap_or(compliance.attribute_undefined)
              attribute_undefined = Some(u)
              u
            }
          }
          if value is Some(_) || undefined != "drop-line" {
            drop = true
            drop_empty_line = true
            return del_char
          } else {
            drop = true
            drop_line = true
            return can_char
          }
        }
        "counter2" => {
          doc.counter(args.get(0).unwrap_or(""), seed?=args.get(1)) |> ignore
          drop = true
          drop_empty_line = true
          return del_char
        }
        _ => return doc.counter(args.get(0).unwrap_or(""), seed?=args.get(1))
      }
    }
    let key = @rb.downcase(m.at(2))
    if doc_attrs.contains(key) {
      return doc_attrs.get(key).unwrap().to_s()
    }
    match intrinsic_attribute(key) {
      Some(v) => return v
      None => ()
    }
    let missing = match attribute_missing_val {
      Some(v) => v
      None => {
        let v = doc_attrs.str("attribute-missing").unwrap_or(compliance.attribute_missing)
        attribute_missing_val = Some(v)
        v
      }
    }
    match missing {
      "drop" => {
        drop = true
        drop_empty_line = true
        del_char
      }
      "drop-line" => {
        if !drop_line_ignore {
          log_info(
            "dropping line containing reference to missing attribute: \{key}",
          )
        }
        drop = true
        drop_line = true
        can_char
      }
      "warn" => {
        log_warn("skipping reference to missing attribute: \{key}")
        m.matched()
      }
      _ => m.matched()
    }
  })
  if !drop {
    return text
  }
  if drop_empty_line {
    let lines = @rb.split(@rb.squeeze(text, chars=del_char), "\n", limit=-1)
    let kept = if drop_line {
      lines.filter(line => !(line == del_char || line.contains(can_char)))
    } else {
      lines.filter(line => line != del_char)
    }
    @rb.delete_chars(kept.join("\n"), del_char)
  } else if text.contains("\n") {
    @rb.split(text, "\n", limit=-1)
    .filter(line => !line.contains(can_char))
    .join("\n")
  } else {
    ""
  }
}

///|
fn intrinsic_attribute(key : String) -> String? {
  match key {
    "startsb" => Some("[")
    "endsb" => Some("]")
    "vbar" => Some("|")
    "caret" => Some("^")
    "asterisk" => Some("*")
    "tilde" => Some("~")
    "plus" => Some("&#43;")
    "backslash" => Some("\\")
    "backtick" => Some("`")
    "blank" => Some("")
    "empty" => Some("")
    "sp" => Some(" ")
    "two-colons" => Some("::")
    "two-semicolons" => Some(";;")
    "nbsp" => Some("&#160;")
    "deg" => Some("&#176;")
    "zwsp" => Some("&#8203;")
    "quot" => Some("&#34;")
    "apos" => Some("&#39;")
    "lsquo" => Some("&#8216;")
    "rsquo" => Some("&#8217;")
    "ldquo" => Some("&#8220;")
    "rdquo" => Some("&#8221;")
    "wj" => Some("&#8288;")
    "brvbar" => Some("&#166;")
    "pp" => Some("&#43;&#43;")
    "cpp" => Some("C&#43;&#43;")
    "cxx" => Some("C&#43;&#43;")
    "amp" => Some("&")
    "lt" => Some("<")
    "gt" => Some(">")
    _ => None
  }
}

///|
/// Applies textual replacements (Ruby `sub_replacements`).
pub fn Node::sub_replacements(_self : Node, text : String) -> String {
  if !replaceable_text_rx.matches(text) {
    return text
  }
  let mut text = text
  for r in replacements {
    let (pattern, replacement, restore) = r
    text = pattern.replace(text, m => do_replacement(m, replacement, restore))
  }
  text
}

///|
fn do_replacement(
  m : @regex.MatchData,
  replacement : String,
  restore : String,
) -> String {
  let captured = m.matched()
  if captured.contains("\\") {
    captured.replace(old="\\", new="")
  } else {
    match restore {
      "none" => replacement
      "bounding" => m.at(1) + replacement + m.at(2)
      _ => m.at(1) + replacement
    }
  }
}

///|
fn Node::convert_quoted_text(
  self : Node,
  m : @regex.MatchData,
  type_ : String,
  scope : String,
) -> String {
  let mut unescaped_attrs : String? = None
  if m.matched().has_prefix("\\") {
    if scope == "constrained" && m.has(2) {
      unescaped_attrs = Some("[\{m.at(2)}]")
    } else {
      return @rb.from(m.matched(), 1)
    }
  }
  if scope == "constrained" {
    match unescaped_attrs {
      Some(ua) =>
        "\{ua}\{Node::new_inline(self, Quoted, text=m.at(3), type_~).convert()}"
      None => {
        let mut type_ = type_
        let mut id : String? = None
        let mut attributes : Attributes? = None
        match m.group(2) {
          Some(attrlist) => {
            let a = self.parse_quoted_text_attributes(attrlist)
            id = a.str("id")
            attributes = Some(a)
            if type_ == "mark" {
              type_ = "unquoted"
            }
          }
          None => ()
        }
        "\{m.at(1)}\{Node::new_inline(self, Quoted, text=m.at(3), type_~, id?=id, attributes?=attributes).convert()}"
      }
    }
  } else {
    let mut type_ = type_
    let mut id : String? = None
    let mut attributes : Attributes? = None
    match m.group(1) {
      Some(attrlist) => {
        let a = self.parse_quoted_text_attributes(attrlist)
        id = a.str("id")
        attributes = Some(a)
        if type_ == "mark" {
          type_ = "unquoted"
        }
      }
      None => ()
    }
    Node::new_inline(self, Quoted, text=m.at(2), type_~, id?, attributes?).convert()
  }
}

///|
fn Node::parse_quoted_text_attributes(self : Node, str : String) -> Attributes {
  let mut str = str
  if str.contains("{") {
    str = self.sub_attributes(str)
  }
  match str.find(",") {
    Some(i) => str = @rb.slice(str, 0, i)
    None => ()
  }
  str = @rb.strip(str)
  let attrs = Attributes::new()
  if str == "" {
    attrs
  } else if (str.has_prefix(".") || str.has_prefix("#")) &&
    compliance.shorthand_property_syntax {
    let (before, _, after) = @rb.partition(str, "#")
    if after == "" {
      if before.length() > 1 {
        attrs.set_str("role", @rb.lstrip(before.replace_all(old=".", new=" ")))
      }
    } else {
      let (id, _, roles) = @rb.partition(after, ".")
      if id != "" {
        attrs.set_str("id", id)
      }
      if roles == "" {
        if before.length() > 1 {
          attrs.set_str(
            "role",
            @rb.lstrip(before.replace_all(old=".", new=" ")),
          )
        }
      } else if before.length() > 1 {
        attrs.set_str(
          "role",
          @rb.lstrip((before + "." + roles).replace_all(old=".", new=" ")),
        )
      } else {
        attrs.set_str("role", roles.replace_all(old=".", new=" "))
      }
    }
    attrs
  } else {
    attrs.set_str("role", str)
    attrs
  }
}

///|
/// Ruby `normalize_text`.
fn normalize_text(
  text : String,
  normalize_whitespace? : Bool = false,
  unescape_closing_square_brackets? : Bool = false,
) -> String {
  if text == "" {
    return text
  }
  let mut text = text
  if normalize_whitespace {
    text = @rb.strip(text).replace_all(old="\n", new=" ")
  }
  if unescape_closing_square_brackets && text.contains("]") {
    text = text.replace_all(old="\\]", new="]")
  }
  text
}

///|
fn split_simple_csv(str : String) -> Array[String] {
  if str == "" {
    []
  } else if str.contains("\"") {
    let values = []
    let accum = StringBuilder()
    let mut quote_open = false
    for c in str {
      match c {
        ',' =>
          if quote_open {
            accum.write_char(c)
          } else {
            values.push(@rb.strip(accum.to_string()))
            accum.reset()
          }
        '"' => quote_open = !quote_open
        _ => accum.write_char(c)
      }
    }
    values.push(@rb.strip(accum.to_string()))
    values
  } else {
    @rb.split(str, ",").map(@rb.strip)
  }
}

///|
fn Node::extract_attributes_from_text(
  self : Node,
  text : String,
  default_text? : String?,
) -> (String?, Attributes) {
  let attrlist = if text.contains("\n") {
    text.replace_all(old="\n", new=" ")
  } else {
    text
  }
  let attrs = parse_attribute_list(attrlist, block=self)
  match attrs.pos_str(1) {
    Some(resolved) =>
      if resolved == attrlist {
        attrs.clear()
        (Some(text), attrs)
      } else {
        (Some(resolved), attrs)
      }
    None => (default_text.unwrap_or(None), attrs)
  }
}

///|
/// Parses an attribute list (Ruby `parse_attributes`).
pub fn Node::parse_attributes(
  self : Node,
  attrlist : String,
  posattrs : Array[String?],
  unescape_input? : Bool = false,
  sub_input? : Bool = false,
  sub_result? : Bool = false,
  into? : Attributes,
) -> Attributes {
  if attrlist == "" {
    return match into {
      Some(a) => a
      None => Attributes::new()
    }
  }
  let mut attrlist = attrlist
  if unescape_input {
    attrlist = normalize_text(
      attrlist,
      normalize_whitespace=true,
      unescape_closing_square_brackets=true,
    )
  }
  if sub_input && attrlist.contains("{") {
    attrlist = self.document().sub_attributes(attrlist)
  }
  let block = if sub_result { Some(self) } else { None }
  let parsed = parse_attribute_list(attrlist, positional_attrs=posattrs, block?)
  match into {
    Some(a) => {
      a.update(parsed)
      a
    }
    None => parsed
  }
}

///|
/// Applies post replacements (hard line breaks).
pub fn Node::sub_post_replacements(self : Node, text : String) -> String {
  if self.attributes.truthy("hardbreaks-option") ||
    self.document().attributes.truthy("hardbreaks-option") {
    let lines = @rb.split(text, "\n", limit=-1)
    if lines.length() < 2 {
      return text
    }
    let last = lines.pop().unwrap()
    let out = lines.map(line => {
      Node::new_inline(
        self,
        Break,
        text=if line.has_suffix(" +") {
          @rb.slice(line, 0, line.length() - 2)
        } else {
          line
        },
        type_="line",
      ).convert()
    })
    out.push(last)
    out.join("\n")
  } else if text.contains("+") && text.contains(" +") {
    hard_line_break_rx.replace(text, m => {
      Node::new_inline(self, Break, text=m.at(1), type_="line").convert()
    })
  } else {
    text
  }
}

///|
/// Escapes special characters and optionally processes callouts.
pub fn Node::sub_source(
  self : Node,
  source : String,
  process_callouts : Bool,
) -> String {
  if process_callouts {
    self.sub_callouts(sub_specialchars(source))
  } else {
    sub_specialchars(source)
  }
}

///|
let callout_rx_cache : Map[String, @regex.Regex] = {}

///|
fn callout_rx_for(line_comment : String, source : Bool) -> @regex.Regex {
  let key = (if source { "s:" } else { "e:" }) + line_comment
  match callout_rx_cache.get(key) {
    Some(r) => r
    None => {
      let prefix = if line_comment == "" {
        ""
      } else {
        "\{regex_escape(line_comment)} ?"
      }
      let rxt = if source {
        "(\\\\)?&lt;()(\\d+|\\.)&gt;(?=(?: ?\\\\?&lt;(?:\\d+|\\.)&gt;)*$)"
      } else {
        "(\\\\)?<()(\\d+|\\.)>(?=(?: ?\\\\?<(?:\\d+|\\.)>)*$)"
      }
      let r = @regex.re("(\{prefix})?\{rxt}")
      callout_rx_cache[key] = r
      r
    }
  }
}

///|
/// Replaces callout markers with callout nodes.
pub fn Node::sub_callouts(self : Node, text : String) -> String {
  let callout_rx = if self.has_attr("line-comment") {
    callout_rx_for(self.attr("line-comment").unwrap_or(""), true)
  } else {
    callout_source_rx
  }
  let mut autonum = 0
  callout_rx.replace(text, m => {
    if m.has(2) {
      m.matched().replace(old="\\", new="")
    } else {
      let num = if m.at(4) == "." {
        autonum += 1
        autonum.to_string()
      } else {
        m.at(4)
      }
      let guard_ : AttrVal = match m.group(1) {
        Some(g) => Str(g)
        None => if m.at(3) == "--" { List(["<!--", "-->"]) } else { Nil }
      }
      let attrs = Attributes::new()
      attrs.set("guard", guard_)
      Node::new_inline(
        self,
        Callout,
        text=num,
        id?=self.document().callouts().read_next_id(),
        attributes=attrs,
      ).convert()
    }
  })
}

///|
/// Highlights source using the document's syntax highlighter (server-side only).
fn Node::highlight_source(
  self : Node,
  source : String,
  process_callouts : Bool,
) -> String {
  match self.document().syntax_highlighter() {
    Some(hl) if hl.handles_highlighting() => {
      let opts : Map[String, String] = {}
      let highlighted = hl.highlight(
        self,
        source,
        self.attr("language").unwrap_or(""),
        opts,
      )
      if process_callouts {
        self.sub_callouts(highlighted)
      } else {
        highlighted
      }
    }
    _ => self.sub_source(source, process_callouts)
  }
}

///|
/// Line numbers to highlight (Ruby `resolve_lines_to_highlight`).
pub fn resolve_lines_to_highlight(
  source : String,
  spec : String,
  start? : Int,
) -> Array[Int] {
  let mut lines : Array[Int] = []
  let spec = if spec.contains(" ") { @rb.delete_chars(spec, " ") } else { spec }
  let entries = if spec.contains(",") {
    @rb.split(spec, ",")
  } else {
    @rb.split(spec, ";")
  }
  for entry0 in entries {
    let mut entry = entry0
    let mut negate = false
    if entry.has_prefix("!") {
      entry = @rb.from(entry, 1)
      negate = true
    }
    let delim = if entry.contains("..") {
      Some("..")
    } else if entry.contains("-") {
      Some("-")
    } else {
      None
    }
    match delim {
      Some(d) => {
        let (from, _, to) = @rb.partition(entry, d)
        let to_i = if to == "" || @rb.to_i(to) < 0 {
          @rb.count(source, "\n") + 1
        } else {
          @rb.to_i(to)
        }
        let range = []
        for i in @rb.to_i(from)..<=to_i {
          range.push(i)
        }
        if negate {
          lines = lines.filter(l => !range.contains(l))
        } else {
          for r in range {
            if !lines.contains(r) {
              lines.push(r)
            }
          }
        }
      }
      None =>
        if negate {
          let v = @rb.to_i(entry)
          lines = lines.filter(l => l != v)
        } else {
          let line = @rb.to_i(entry)
          if !lines.contains(line) {
            lines.push(line)
          }
        }
    }
  }
  let shift = match start {
    Some(s) => s - 1
    None => 0
  }
  if shift != 0 {
    lines = lines.map(l => l - shift)
  }
  lines.sort()
  lines
}

///|
fn Node::add_passthrough(self : Node, p : Passthrough) -> String {
  let key = self.passthroughs.length()
  self.passthroughs.push(p)
  "\{pass_start}\{key}\{pass_end}"
}

///|
/// Extracts passthroughs (Ruby `extract_passthroughs`).
fn Node::extract_passthroughs(self : Node, text : String) -> String {
  let compat_mode = self.document().compat_mode()
  let mut text = text
  if text.contains("++") || text.contains("$$") || text.contains("ss:") {
    text = inline_pass_macro_rx.replace(text, m => {
      let mut preceding : String? = None
      match m.group(4) {
        Some(boundary) => {
          if compat_mode && boundary == "++" {
            let head = match m.group(2) {
              Some(a) => "\{m.at(1)}[\{a}]\{m.at(3)}"
              None => "\{m.at(1)}\{m.at(3)}"
            }
            return "\{head}++\{self.extract_passthroughs(m.at(5))}++"
          }
          let mut attributes : Attributes? = None
          let mut old_behavior = false
          match m.group(2) {
            Some(attrlist) => {
              let escape_count = m.at(3).length()
              if escape_count > 0 {
                return "\{m.at(1)}[\{attrlist}]\{@rb.repeat("\\", escape_count - 1)}\{boundary}\{m.at(5)}\{boundary}"
              } else if m.at(1) == "\\" {
                preceding = Some("[\{attrlist}]")
              } else if boundary == "++" {
                if attrlist == "x-" {
                  old_behavior = true
                  attributes = Some(Attributes::new())
                } else if attrlist.has_suffix(" x-") {
                  old_behavior = true
                  attributes = Some(
                    self.parse_quoted_text_attributes(
                      @rb.slice(attrlist, 0, attrlist.length() - 3),
                    ),
                  )
                } else {
                  attributes = Some(self.parse_quoted_text_attributes(attrlist))
                }
              } else {
                attributes = Some(self.parse_quoted_text_attributes(attrlist))
              }
            }
            None => {
              let escape_count = m.at(3).length()
              if escape_count > 0 {
                return "\{@rb.repeat("\\", escape_count - 1)}\{boundary}\{m.at(5)}\{boundary}"
              }
            }
          }
          let subs = if boundary == "+++" { [] } else { basic_subs }
          let key = match attributes {
            Some(a) =>
              if old_behavior {
                self.add_passthrough({
                  text: m.at(5),
                  subs: Some(normal_subs),
                  type_: Some("monospaced"),
                  attributes: Some(a),
                })
              } else {
                self.add_passthrough({
                  text: m.at(5),
                  subs: Some(subs),
                  type_: Some("unquoted"),
                  attributes: Some(a),
                })
              }
            None =>
              self.add_passthrough({
                text: m.at(5),
                subs: Some(subs),
                type_: None,
                attributes: None,
              })
          }
          "\{preceding.unwrap_or("")}\{key}"
        }
        None => {
          if m.group(6) == Some("\\") {
            return @rb.from(m.matched(), 1)
          }
          let t = normalize_text(m.at(8), unescape_closing_square_brackets=true)
          match m.group(7) {
            Some(subs) =>
              self.add_passthrough({
                text: t,
                subs: Some(self.resolve_pass_subs(subs)),
                type_: None,
                attributes: None,
              })
            None =>
              self.add_passthrough({
                text: t,
                subs: None,
                type_: None,
                attributes: None,
              })
          }
        }
      }
    })
  }
  let (pass_char1, pass_char2, pass_rx) = if compat_mode {
    inline_pass_rx_true
  } else {
    inline_pass_rx_false
  }
  if text.contains(pass_char1) ||
    (match pass_char2 {
      Some(c) => text.contains(c)
      None => false
    }) {
    text = pass_rx.replace(text, m => {
      let mut preceding = m.at(1)
      let attrlist = match m.group(4) {
        Some(a) => Some(a)
        None => m.group(3)
      }
      let escaped = m.has(5)
      let quoted_text = m.at(6)
      let format_mark = m.at(7)
      let content = m.at(8)
      let mut old_behavior = false
      let mut old_behavior_forced = false
      if compat_mode {
        old_behavior = true
      } else {
        match attrlist {
          Some(a) if a == "x-" || a.has_suffix(" x-") => {
            old_behavior = true
            old_behavior_forced = true
          }
          _ => ()
        }
      }
      let mut attributes : Attributes? = None
      match attrlist {
        Some(a) =>
          if escaped {
            return "\{preceding}[\{a}]\{@rb.from(quoted_text, 1)}"
          } else if preceding == "\\" {
            if old_behavior_forced && format_mark == "`" {
              return "\{preceding}[\{a}]\{quoted_text}"
            }
            preceding = "[\{a}]"
          } else if old_behavior_forced {
            attributes = Some(
              if a == "x-" {
                Attributes::new()
              } else {
                self.parse_quoted_text_attributes(
                  @rb.slice(a, 0, a.length() - 3),
                )
              },
            )
          } else {
            attributes = Some(self.parse_quoted_text_attributes(a))
          }
        None =>
          if escaped {
            return "\{preceding}\{@rb.from(quoted_text, 1)}"
          } else if compat_mode && preceding == "\\" {
            return quoted_text
          }
      }
      let key = if compat_mode {
        self.add_passthrough({
          text: content,
          subs: Some(basic_subs),
          type_: Some("monospaced"),
          attributes,
        })
      } else {
        match attributes {
          Some(_) =>
            if old_behavior {
              self.add_passthrough({
                text: content,
                subs: Some(
                  if format_mark == "`" {
                    basic_subs
                  } else {
                    normal_subs
                  },
                ),
                type_: Some("monospaced"),
                attributes,
              })
            } else {
              self.add_passthrough({
                text: content,
                subs: Some(basic_subs),
                type_: Some("unquoted"),
                attributes,
              })
            }
          None =>
            self.add_passthrough({
              text: content,
              subs: Some(basic_subs),
              type_: None,
              attributes: None,
            })
        }
      }
      "\{preceding}\{key}"
    })
  }
  if text.contains(":") && (text.contains("stem:") || text.contains("math:")) {
    text = inline_stem_macro_rx.replace(text, m => {
      if m.matched().has_prefix("\\") {
        return @rb.from(m.matched(), 1)
      }
      let mut type_ = m.at(1)
      if type_ == "stem" {
        type_ = stem_type_alias(self.document().attributes.str("stem"))
      }
      let mut content = normalize_text(
        m.at(3),
        unescape_closing_square_brackets=true,
      )
      if type_ == "latexmath" &&
        content.has_prefix("$") &&
        content.has_suffix("$") {
        content = @rb.slice(content, 1, content.length() - 1)
      }
      let subs = match m.group(2) {
        Some(s) => Some(self.resolve_pass_subs(s, subject="stem macro"))
        None =>
          if self.document().is_basebackend("html") {
            Some(basic_subs)
          } else {
            None
          }
      }
      self.add_passthrough({
        text: content,
        subs,
        type_: Some(type_),
        attributes: None,
      })
    })
  }
  text
}

///|
/// Ruby `STEM_TYPE_ALIASES[value]`.
fn stem_type_alias(v : String?) -> String {
  match v {
    Some("latexmath") | Some("latex") | Some("tex") => "latexmath"
    _ => "asciimath"
  }
}

///|
/// Restores passthroughs (Ruby `restore_passthroughs`).
fn Node::restore_passthroughs(self : Node, text : String) -> String {
  pass_slot_rx.replace(text, m => {
    let idx = @rb.to_i(m.at(1))
    match self.passthroughs.get(idx) {
      Some(pass) => {
        let mut subbed = match pass.subs {
          Some(s) => self.apply_subs(pass.text, s)
          None => pass.text
        }
        match pass.type_ {
          Some(t) => {
            let id = match pass.attributes {
              Some(a) => a.str("id")
              None => None
            }
            subbed = Node::new_inline(
              self,
              Quoted,
              text=subbed,
              type_=t,
              id?,
              attributes?=pass.attributes,
            ).convert()
          }
          None => ()
        }
        if subbed.contains(pass_start) {
          self.restore_passthroughs(subbed)
        } else {
          subbed
        }
      }
      None => {
        log_error("unresolved passthrough detected: \{text}")
        "??pass??"
      }
    }
  })
}

///|
fn sub_group(key : String) -> Array[Sub]? {
  match key {
    "none" => Some(no_subs)
    "normal" => Some(normal_subs)
    "verbatim" => Some(verbatim_subs)
    "specialchars" => Some(basic_subs)
    _ => None
  }
}

///|
fn sub_hint(key : String) -> String? {
  match key {
    "a" => Some("attributes")
    "m" => Some("macros")
    "n" => Some("normal")
    "p" => Some("post_replacements")
    "q" => Some("quotes")
    "r" => Some("replacements")
    "c" => Some("specialcharacters")
    "v" => Some("verbatim")
    _ => None
  }
}

///|
fn sub_from_name(name : String) -> Sub? {
  match name {
    "specialcharacters" => Some(SpecialCharacters)
    "quotes" => Some(Quotes)
    "attributes" => Some(Attributes)
    "replacements" => Some(Replacements)
    "macros" => Some(Macros)
    "post_replacements" => Some(PostReplacements)
    "callouts" => Some(Callouts)
    _ => None
  }
}

///|
/// Resolves a subs attribute value (Ruby `resolve_subs`). Returns an empty
/// array when `subs` is empty.
pub fn Node::resolve_subs(
  _self : Node,
  subs : String,
  type_? : String = "block",
  defaults? : Array[Sub],
  subject? : String,
) -> Array[Sub] {
  if subs == "" {
    return []
  }
  let mut candidates : Array[String]? = None
  let subs = if subs.contains(" ") { @rb.delete_chars(subs, " ") } else { subs }
  let modifiers_present = sub_modifier_sniff_rx.matches(subs)
  for key0 in @rb.split(subs, ",") {
    let mut key = key0
    let mut op : Int = 0 // 1 append, 2 remove, 3 prepend
    if modifiers_present {
      if key.has_prefix("+") {
        op = 1
        key = @rb.from(key, 1)
      } else if key.has_prefix("-") {
        op = 2
        key = @rb.from(key, 1)
      } else if key.has_suffix("+") {
        op = 3
        key = @rb.chop(key)
      }
    }
    let resolved_keys : Array[String] = if type_ == "inline" &&
      (key == "verbatim" || key == "v") {
      ["specialcharacters"]
    } else {
      match sub_group(key) {
        Some(g) => g.map(s => s.name())
        None =>
          if type_ == "inline" && key.length() == 1 && sub_hint(key) is Some(rk) {
            match sub_group(rk) {
              Some(g) => g.map(s => s.name())
              None => [rk]
            }
          } else {
            [key]
          }
      }
    }
    if op != 0 {
      let c = match candidates {
        Some(c) => c
        None =>
          match defaults {
            Some(d) => d.map(s => s.name())
            None => []
          }
      }
      candidates = Some(
        match op {
          1 => c + resolved_keys
          3 => resolved_keys + c
          _ => c.filter(k => !resolved_keys.contains(k))
        },
      )
    } else {
      candidates = Some(candidates.unwrap_or([]) + resolved_keys)
    }
  }
  guard candidates is Some(candidates) else { return [] }
  // Ruby `candidates & SUB_OPTIONS[type]` (keeps order, removes duplicates)
  let valid = fn(k : String) {
    match k {
      "none" | "normal" | "verbatim" | "specialchars" => true
      "callouts" => type_ == "block"
      _ => sub_from_name(k) is Some(_)
    }
  }
  let resolved : Array[Sub] = []
  let seen : Array[String] = []
  let invalid : Array[String] = []
  for k in candidates {
    if valid(k) {
      if !seen.contains(k) {
        seen.push(k)
        match sub_from_name(k) {
          Some(s) => resolved.push(s)
          None => ()
        }
      }
    } else {
      invalid.push(k)
    }
  }
  if !invalid.is_empty() {
    let subj = match subject {
      Some(s) => " for \{s}"
      None => ""
    }
    log_warn(
      "invalid substitution type\{if invalid.length() > 1 { "s" } else { "" }}\{subj}: \{invalid.join(", ")}",
    )
  }
  resolved
}

///|
pub fn Node::resolve_block_subs(
  self : Node,
  subs : String,
  defaults : Array[Sub]?,
  subject : String,
) -> Array[Sub] {
  self.resolve_subs(subs, type_="block", defaults?, subject~)
}

///|
pub fn Node::resolve_pass_subs(
  self : Node,
  subs : String,
  subject? : String = "passthrough macro",
) -> Array[Sub] {
  self.resolve_subs(subs, type_="inline", subject~)
}

///|
/// Expands a subs spec (Ruby `expand_subs`); None means no subs.
pub fn Node::expand_subs(
  self : Node,
  subs : String,
  subject? : String,
) -> Array[Sub]? {
  let r = self.resolve_subs(subs, type_="inline", subject?)
  if r.is_empty() {
    None
  } else {
    Some(r)
  }
}

///|
/// Resolves and stores the subs of this block (Ruby `commit_subs`).
pub fn Node::commit_subs(self : Node) -> Unit {
  let default_subs = match self.default_subs {
    Some(d) => d
    None =>
      match self.content_model {
        Simple => normal_subs
        Verbatim =>
          if self.context == Verse {
            normal_subs
          } else {
            verbatim_subs
          }
        Raw => if self.context == Stem { basic_subs } else { no_subs }
        _ => return
      }
  }
  match self.attributes.str("subs") {
    Some(custom) =>
      self.subs = self.resolve_block_subs(
        custom,
        Some(default_subs),
        self.context.name(),
      )
    None => self.subs = default_subs.copy()
  }
  if self.context == Listing && self.style == Some("source") {
    match self.document().syntax_highlighter() {
      Some(hl) if hl.handles_highlighting() =>
        match self.subs.search(SpecialCharacters) {
          Some(idx) => self.subs[idx] = Highlight
          None => ()
        }
      _ => ()
    }
  }
}

///|
/// Extracts callouts from source (Ruby `extract_callouts`).
fn Node::extract_callouts(
  self : Node,
  source : String,
) -> (String, Map[Int, Array[(AttrVal, String)]]?) {
  let marks : Map[Int, Array[(AttrVal, String)]] = {}
  let mut autonum = 0
  let mut lineno = 0
  let mut last_lineno : Int? = None
  let callout_rx = if self.has_attr("line-comment") {
    callout_rx_for(self.attr("line-comment").unwrap_or(""), false)
  } else {
    callout_extract_rx
  }
  let lines = @rb.split(source, "\n", limit=-1).map(line => {
    lineno += 1
    callout_rx.replace(line, m => {
      if m.has(2) {
        m.matched().replace(old="\\", new="")
      } else {
        let guard_ : AttrVal = match m.group(1) {
          Some(g) => Str(g)
          None => if m.at(3) == "--" { List(["<!--", "-->"]) } else { Nil }
        }
        let num = if m.at(4) == "." {
          autonum += 1
          autonum.to_string()
        } else {
          m.at(4)
        }
        match marks.get(lineno) {
          Some(a) => a.push((guard_, num))
          None => marks[lineno] = [(guard_, num)]
        }
        last_lineno = Some(lineno)
        ""
      }
    })
  })
  let mut source = lines.join("\n")
  match last_lineno {
    Some(l) => {
      if l == lineno {
        source = source + "\n"
      }
      (source, Some(marks))
    }
    None => (source, None)
  }
}

///|
/// Restores callouts after highlighting (Ruby `restore_callouts`).
fn Node::restore_callouts(
  self : Node,
  source : String,
  callout_marks : Map[Int, Array[(AttrVal, String)]],
  source_offset? : Int,
) -> String {
  let (preamble, source) = match source_offset {
    Some(off) => (@rb.slice(source, 0, off), @rb.from(source, off))
    None => ("", source)
  }
  let mut lineno = 0
  let callout_node = fn(g : AttrVal, numeral : String) {
    let attrs = Attributes::new()
    attrs.set("guard", g)
    Node::new_inline(
      self,
      Callout,
      text=numeral,
      id?=self.document().callouts().read_next_id(),
      attributes=attrs,
    ).convert()
  }
  preamble +
  @rb.split(source, "\n", limit=-1)
  .map(line => {
    lineno += 1
    match callout_marks.get(lineno) {
      Some(conums) => {
        callout_marks.remove(lineno)
        if conums.length() == 1 {
          line + callout_node(conums[0].0, conums[0].1)
        } else {
          line + conums.map(c => callout_node(c.0, c.1)).join(" ")
        }
      }
      None => line
    }
  })
  .join("\n")
}
