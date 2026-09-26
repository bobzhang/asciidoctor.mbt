///|
fn Html5Converter::convert_inline_anchor(
  self : Html5Converter,
  node : @core.Node,
) -> String {
  match node.inline_type {
    Some("xref") => {
      let target = node.target.unwrap_or("")
      match node.attributes.str("path") {
        Some(path) => {
          let base : Array[String] = match node.role() {
            Some(r) => [" class=\"\{r}\""]
            None => []
          }
          let attrs = append_link_constraint_attrs(node, base).join("")
          let text = match node.text() {
            Some(t) => t
            None => path
          }
          "<a href=\"\{target}\"\{attrs}>\{text}</a>"
        }
        None => {
          let attrs = match node.role() {
            Some(r) => " class=\"\{r}\""
            None => ""
          }
          let text = match node.text() {
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
              match ref_ {
                Some(r) =>
                  if !self.resolving_xref {
                    self.resolving_xref = true
                    let t = match
                      r.xreftext(
                        xrefstyle?=node.attr("xrefstyle", inherit=true),
                      ) {
                      Some(t) =>
                        if t.contains("<a") {
                          drop_anchor_rx.gsub(t, "")
                        } else {
                          t
                        }
                      None => if top { "[^top]" } else { "[\{refid_s}]" }
                    }
                    self.resolving_xref = false
                    t
                  } else if top {
                    "[^top]"
                  } else {
                    "[\{refid_s}]"
                  }
                None => "[\{refid_s}]"
              }
            }
          }
          "<a href=\"\{target}\"\{attrs}>\{text}</a>"
        }
      }
    }
    Some("ref") => "<a id=\"\{node.id.unwrap_or("")}\"></a>"
    Some("link") => {
      let attrs : Array[String] = match node.id {
        Some(id) => [" id=\"\{id}\""]
        None => []
      }
      match node.role() {
        Some(r) => attrs.push(" class=\"\{r}\"")
        None => ()
      }
      if node.has_attr("title") {
        attrs.push(" title=\"\{a(node, "title")}\"")
      }
      "<a href=\"\{node.target.unwrap_or("")}\"\{append_link_constraint_attrs(node, attrs).join("")}>\{node.text().unwrap_or("")}</a>"
    }
    Some("bibref") =>
      "<a id=\"\{node.id.unwrap_or("")}\"></a>[\{match node.reftext() { Some(r) => r; None => node.id.unwrap_or("") }}]"
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
fn Html5Converter::convert_inline_break(
  self : Html5Converter,
  node : @core.Node,
) -> String {
  "\{node.text().unwrap_or("")}<br\{self.void_element_slash}>"
}

///|
fn Html5Converter::convert_inline_button(
  self : Html5Converter,
  node : @core.Node,
) -> String {
  ignore(self)
  "<b class=\"button\">\{node.text().unwrap_or("")}</b>"
}

///|
fn Html5Converter::convert_inline_callout(
  self : Html5Converter,
  node : @core.Node,
) -> String {
  let doc = node.document()
  let text = node.text().unwrap_or("")
  if doc.has_attr("icons", expected="font") {
    "<i class=\"conum\" data-value=\"\{text}\"></i><b>(\{text})</b>"
  } else if doc.has_attr("icons") {
    let src = node.icon_uri("callouts/\{text}")
    "<img src=\"\{src}\" alt=\"\{text}\"\{self.void_element_slash}>"
  } else {
    match node.attributes.get("guard") {
      Some(List(_)) => "&lt;!--<b class=\"conum\">(\{text})</b>--&gt;"
      Some(g) => "\{g.to_s()}<b class=\"conum\">(\{text})</b>"
      None => "<b class=\"conum\">(\{text})</b>"
    }
  }
}

///|
fn Html5Converter::convert_inline_footnote(
  self : Html5Converter,
  node : @core.Node,
) -> String {
  ignore(self)
  match node.attr("index") {
    Some(index) =>
      if node.inline_type == Some("xref") {
        "<sup class=\"footnoteref\">[<a class=\"footnote\" href=\"#_footnotedef_\{index}\" title=\"View footnote.\">\{index}</a>]</sup>"
      } else {
        let id_attr_s = match node.id {
          Some(id) => " id=\"_footnote_\{id}\""
          None => ""
        }
        "<sup class=\"footnote\"\{id_attr_s}>[<a id=\"_footnoteref_\{index}\" class=\"footnote\" href=\"#_footnotedef_\{index}\" title=\"View footnote.\">\{index}</a>]</sup>"
      }
    None =>
      if node.inline_type == Some("xref") {
        "<sup class=\"footnoteref red\" title=\"Unresolved footnote reference.\">[\{node.text().unwrap_or("")}]</sup>"
      } else {
        ""
      }
  }
}

///|
fn Html5Converter::convert_inline_image(
  self : Html5Converter,
  node : @core.Node,
) -> String {
  let target = node.target.unwrap_or("")
  let type_ = node.inline_type.unwrap_or("image")
  let slash = self.void_element_slash
  let mut src : String? = None
  let img = if type_ == "icon" {
    let icons = node.document().attr("icons")
    if icons == Some("font") {
      let mut i_class = "fa fa-\{target}"
      if node.has_attr("size") {
        i_class = "\{i_class} fa-\{a(node, "size")}"
      }
      if node.has_attr("flip") {
        i_class = "\{i_class} fa-flip-\{a(node, "flip")}"
      } else if node.has_attr("rotate") {
        i_class = "\{i_class} fa-rotate-\{a(node, "rotate")}"
      }
      let attrs = if node.has_attr("title") {
        " title=\"\{a(node, "title")}\""
      } else {
        ""
      }
      "<i class=\"\{i_class}\"\{attrs}></i>"
    } else if icons is Some(_) {
      let mut attrs = if node.has_attr("width") {
        " width=\"\{a(node, "width")}\""
      } else {
        ""
      }
      if node.has_attr("height") {
        attrs = "\{attrs} height=\"\{a(node, "height")}\""
      }
      if node.has_attr("title") {
        attrs = "\{attrs} title=\"\{a(node, "title")}\""
      }
      let s = node.icon_uri(target)
      src = Some(s)
      "<img src=\"\{s}\" alt=\"\{encode_attribute_value(node.alt())}\"\{attrs}\{slash}>"
    } else {
      "[\{node.alt()}&#93;"
    }
  } else {
    let mut attrs = if node.has_attr("width") {
      " width=\"\{a(node, "width")}\""
    } else {
      ""
    }
    if node.has_attr("height") {
      attrs = "\{attrs} height=\"\{a(node, "height")}\""
    }
    if node.has_attr("title") {
      attrs = "\{attrs} title=\"\{a(node, "title")}\""
    }
    if (node.has_attr("format", expected="svg") || target.contains(".svg")) &&
      node.document().safe() < @core.SAFE_SECURE {
      if node.has_option("inline") {
        match self.read_svg_contents(node, target) {
          Some(svg) => svg
          None => "<span class=\"alt\">\{node.alt()}</span>"
        }
      } else if node.has_option("interactive") {
        let fallback = if node.has_attr("fallback") {
          "<img src=\"\{node.image_uri(a(node, "fallback"))}\" alt=\"\{encode_attribute_value(node.alt())}\"\{attrs}\{slash}>"
        } else {
          "<span class=\"alt\">\{node.alt()}</span>"
        }
        let s = node.image_uri(target)
        src = Some(s)
        "<object type=\"image/svg+xml\" data=\"\{s}\"\{attrs}>\{fallback}</object>"
      } else {
        let s = node.image_uri(target)
        src = Some(s)
        "<img src=\"\{s}\" alt=\"\{encode_attribute_value(node.alt())}\"\{attrs}\{slash}>"
      }
    } else {
      let s = node.image_uri(target)
      src = Some(s)
      "<img src=\"\{s}\" alt=\"\{encode_attribute_value(node.alt())}\"\{attrs}\{slash}>"
    }
  }
  let img = wrap_image_link(node, img, src)
  let class_attr_val = match node.role() {
    Some(r) =>
      if node.has_attr("float") {
        "\{type_} \{a(node, "float")} \{r}"
      } else {
        "\{type_} \{r}"
      }
    None =>
      if node.has_attr("float") {
        "\{type_} \{a(node, "float")}"
      } else {
        type_
      }
  }
  "<span\{id_attr(node)} class=\"\{class_attr_val}\">\{img}</span>"
}

///|
fn Html5Converter::convert_inline_indexterm(
  self : Html5Converter,
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
fn Html5Converter::convert_inline_kbd(
  self : Html5Converter,
  node : @core.Node,
) -> String {
  ignore(self)
  let keys = match node.attributes.get("keys") {
    Some(List(l)) => l
    Some(v) => [v.to_s()]
    None => []
  }
  if keys.length() == 1 {
    "<kbd>\{keys[0]}</kbd>"
  } else {
    "<span class=\"keyseq\"><kbd>\{keys.join("</kbd>+<kbd>")}</kbd></span>"
  }
}

///|
fn Html5Converter::convert_inline_menu(
  self : Html5Converter,
  node : @core.Node,
) -> String {
  ignore(self)
  let caret = if node.document().has_attr("icons", expected="font") {
    "&#160;<i class=\"fa fa-angle-right caret\"></i> "
  } else {
    "&#160;<b class=\"caret\">&#8250;</b> "
  }
  let submenu_joiner = "</b>\{caret}<b class=\"submenu\">"
  let menu = a(node, "menu")
  let submenus = match node.attributes.get("submenus") {
    Some(List(l)) => l
    _ => []
  }
  if submenus.is_empty() {
    match node.attr("menuitem") {
      Some(menuitem) =>
        "<span class=\"menuseq\"><b class=\"menu\">\{menu}</b>\{caret}<b class=\"menuitem\">\{menuitem}</b></span>"
      None => "<b class=\"menuref\">\{menu}</b>"
    }
  } else {
    "<span class=\"menuseq\"><b class=\"menu\">\{menu}</b>\{caret}<b class=\"submenu\">\{submenus.join(submenu_joiner)}</b>\{caret}<b class=\"menuitem\">\{a(node, "menuitem")}</b></span>"
  }
}

///|
fn quote_tags(type_ : String) -> (String, String, Bool) {
  match type_ {
    "monospaced" => ("<code>", "</code>", true)
    "emphasis" => ("<em>", "</em>", true)
    "strong" => ("<strong>", "</strong>", true)
    "double" => ("&#8220;", "&#8221;", false)
    "single" => ("&#8216;", "&#8217;", false)
    "mark" => ("<mark>", "</mark>", true)
    "superscript" => ("<sup>", "</sup>", true)
    "subscript" => ("<sub>", "</sub>", true)
    "asciimath" => ("\\$", "\\$", false)
    "latexmath" => ("\\(", "\\)", false)
    _ => ("", "", false)
  }
}

///|
fn Html5Converter::convert_inline_quoted(
  self : Html5Converter,
  node : @core.Node,
) -> String {
  ignore(self)
  let (open, close, tag) = quote_tags(node.inline_type.unwrap_or(""))
  let text = node.text().unwrap_or("")
  match node.id {
    Some(id) => {
      let class_attr = match node.role() {
        Some(r) => " class=\"\{r}\""
        None => ""
      }
      if tag {
        "\{@rb.chop(open)} id=\"\{id}\"\{class_attr}>\{text}\{close}"
      } else {
        "<span id=\"\{id}\"\{class_attr}>\{open}\{text}\{close}</span>"
      }
    }
    None =>
      match node.role() {
        Some(r) =>
          if tag {
            "\{@rb.chop(open)} class=\"\{r}\">\{text}\{close}"
          } else {
            "<span class=\"\{r}\">\{open}\{text}\{close}</span>"
          }
        None => "\{open}\{text}\{close}"
      }
  }
}
