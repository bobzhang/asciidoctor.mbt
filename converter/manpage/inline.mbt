///|
fn ManPageConverter::convert_inline_anchor(
  self : ManPageConverter,
  node : @core.Node,
) -> String {
  let target = node.target.unwrap_or("")
  match node.inline_type {
    Some("link") => {
      let (macro_, target) = if target.has_prefix("mailto:") {
        ("MTO", @rb.from(target, 7))
      } else {
        ("URL", target)
      }
      let text = node.text().unwrap_or("")
      let text = if text == target {
        ""
      } else {
        text.replace_all(old="\"", new="\{ESC_BS}(dq")
      }
      let target = if macro_ == "MTO" {
        target.replace(old="@", new="\{ESC_BS}(at")
      } else {
        target
      }
      "\{ESC_BS}c\n\{ESC_FS}\{macro_} \"\{target}\" \"\{text}\" "
    }
    Some("xref") =>
      match node.text() {
        Some(t) => t
        None => {
          let refs = match self.refs {
            Some(r) => r
            None => {
              let r = node.document().catalog().refs
              self.refs = Some(r)
              r
            }
          }
          let refid = node.attributes.str("refid")
          let mut top = false
          let ref_ = match refid {
            Some(rid) =>
              match refs.get(rid) {
                Some(r) => Some(r)
                None =>
                  if rid == "" {
                    top = true
                    Some(get_root_document(node))
                  } else {
                    None
                  }
              }
            None => {
              top = true
              Some(get_root_document(node))
            }
          }
          let refid_s = refid.unwrap_or("")
          let fallback = if top { "[^top]" } else { "[\{refid_s}]" }
          match ref_ {
            Some(r) =>
              if !self.resolving_xref {
                self.resolving_xref = true
                let t = match
                  r.xreftext(xrefstyle?=node.attr("xrefstyle", inherit=true)) {
                  Some(t) =>
                    if r.context == Section &&
                      r.level < 2 &&
                      Some(t) == r.title() {
                      uppercase_pcdata(t)
                    } else {
                      t
                    }
                  None => fallback
                }
                self.resolving_xref = false
                t
              } else {
                fallback
              }
            None => "[\{refid_s}]"
          }
        }
      }
    // These are anchor points, which shouldn't be visible
    Some("ref") | Some("bibref") => ""
    t => {
      @core.logger().add({
        severity: Warn,
        text: "unknown anchor type: \{t.map(x => ":" + x).unwrap_or("nil")}",
        source_location: None,
        include_location: None,
      })
      ""
    }
  }
}

///|
fn ManPageConverter::convert_inline_break(
  self : ManPageConverter,
  node : @core.Node,
) -> String {
  ignore(self)
  "\{node.text().unwrap_or("")}\n\{ESC_FS}br"
}

///|
fn ManPageConverter::convert_inline_button(
  self : ManPageConverter,
  node : @core.Node,
) -> String {
  ignore(self)
  "<\{ESC_BS}fB>[\{ESC_BS}0\{node.text().unwrap_or("")}\{ESC_BS}0]</\{ESC_BS}fP>"
}

///|
fn ManPageConverter::convert_inline_callout(
  self : ManPageConverter,
  node : @core.Node,
) -> String {
  ignore(self)
  "<\{ESC_BS}fB>(\{node.text().unwrap_or("")})<\{ESC_BS}fP>"
}

///|
fn ManPageConverter::convert_inline_footnote(
  self : ManPageConverter,
  node : @core.Node,
) -> String {
  ignore(self)
  match node.attr("index") {
    Some(index) => "[\{index}]"
    None =>
      if node.inline_type == Some("xref") {
        "[\{node.text().unwrap_or("")}]"
      } else {
        ""
      }
  }
}

///|
fn ManPageConverter::convert_inline_image(
  self : ManPageConverter,
  node : @core.Node,
) -> String {
  ignore(self)
  if node.has_attr("link") {
    "[\{node.alt()}] <\{a(node, "link")}>"
  } else {
    "[\{node.alt()}]"
  }
}

///|
fn ManPageConverter::convert_inline_indexterm(
  self : ManPageConverter,
  node : @core.Node,
) -> String {
  ignore(self)
  if node.inline_type == Some("visible") {
    node.text().unwrap_or("")
  } else {
    ""
  }
}

///|
fn list_attr(node : @core.Node, name : String) -> Array[String] {
  match node.attributes.get(name) {
    Some(List(l)) => l
    Some(Nil) | None => []
    Some(v) => [v.to_s()]
  }
}

///|
fn ManPageConverter::convert_inline_kbd(
  self : ManPageConverter,
  node : @core.Node,
) -> String {
  ignore(self)
  let keys = list_attr(node, "keys")
  let body = if keys.length() == 1 {
    keys[0]
  } else {
    keys.join("\{ESC_BS}0+\{ESC_BS}0")
  }
  "<\{ESC_BS}f(CR>\{body}</\{ESC_BS}fP>"
}

///|
fn ManPageConverter::convert_inline_menu(
  self : ManPageConverter,
  node : @core.Node,
) -> String {
  ignore(self)
  let caret = "\{ESC_BS}0\{ESC_BS}(fc\{ESC_BS}0"
  let menu = a(node, "menu")
  let submenus = list_attr(node, "submenus")
  if !submenus.is_empty() {
    let submenu_path = submenus
      .map(item => "<\{ESC_BS}fI>\{item}</\{ESC_BS}fP>")
      .join(caret)
    "<\{ESC_BS}fI>\{menu}</\{ESC_BS}fP>\{caret}\{submenu_path}\{caret}<\{ESC_BS}fI>\{a(node, "menuitem")}</\{ESC_BS}fP>"
  } else {
    match node.attr("menuitem") {
      Some(menuitem) => "<\{ESC_BS}fI>\{menu}\{caret}\{menuitem}</\{ESC_BS}fP>"
      None => "<\{ESC_BS}fI>\{menu}</\{ESC_BS}fP>"
    }
  }
}

///|
/// NOTE use fake XML elements to prevent creating artificial word boundaries
fn ManPageConverter::convert_inline_quoted(
  self : ManPageConverter,
  node : @core.Node,
) -> String {
  ignore(self)
  let text = node.text().unwrap_or("")
  match node.inline_type {
    Some("emphasis") => "<\{ESC_BS}fI>\{text}</\{ESC_BS}fP>"
    Some("strong") => "<\{ESC_BS}fB>\{text}</\{ESC_BS}fP>"
    Some("monospaced") => "<\{ESC_BS}f(CR>\{text}</\{ESC_BS}fP>"
    Some("single") => "<\{ESC_BS}(oq>\{text}</\{ESC_BS}(cq>"
    Some("double") => "<\{ESC_BS}(lq>\{text}</\{ESC_BS}(rq>"
    _ => text
  }
}
