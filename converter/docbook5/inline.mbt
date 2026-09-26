///|
fn convert_inline_anchor(node : @core.Node) -> String {
  match node.inline_type {
    Some("ref") => {
      let id = node.id
      let reftext = match node.reftext() {
        Some(r) => r
        None => "[\{id.unwrap_or("")}]"
      }
      "<anchor\{common_attributes(id, reftext=Some(reftext))}/>"
    }
    Some("xref") =>
      match node.attributes.str("path") {
        Some(path) =>
          "<link xl:href=\"\{node.target.unwrap_or("")}\">\{node.text().unwrap_or(path)}</link>"
        None => {
          let linkend = match node.attributes.str("refid") {
            Some(refid) if refid != "" => refid
            _ => {
              let root_doc = get_root_document(node)
              match root_doc.id {
                Some(id) => id
                None => {
                  let id = generate_document_id(root_doc)
                  root_doc.set_id(Some(id))
                  id
                }
              }
            }
          }
          // NOTE the xref tag in DocBook does not support explicit link text, so the link tag must be used instead
          match node.text() {
            Some(text) => "<link linkend=\"\{linkend}\">\{text}</link>"
            None => "<xref linkend=\"\{linkend}\"/>"
          }
        }
      }
    Some("link") =>
      "<link xl:href=\"\{node.target.unwrap_or("")}\">\{node.text().unwrap_or("")}</link>"
    Some("bibref") => {
      let text = "[\{match node.reftext() { Some(r) => r; None => node.id.unwrap_or("") }}]"
      "<anchor\{common_attributes(node.id, reftext=Some(text))}/>\{text}"
    }
    t => {
      warn("unknown anchor type: \{t.map(x => ":" + x).unwrap_or("nil")}")
      ""
    }
  }
}

///|
fn convert_inline_footnote(node : @core.Node) -> String {
  if node.inline_type == Some("xref") {
    "<footnoteref linkend=\"\{node.target.unwrap_or("")}\"/>"
  } else {
    "<footnote\{common_attributes(node.id)}><simpara>\{node.text().unwrap_or("")}</simpara></footnote>"
  }
}

///|
fn convert_inline_image(node : @core.Node) -> String {
  let target = node.target.unwrap_or("")
  let (src, fileref) = if node.inline_type == Some("icon") {
    (node.icon_uri(target), None)
  } else {
    let f = node.image_uri(target)
    (f, Some(f))
  }
  let img = "<inlinemediaobject\{common_attributes(node.id, role=node.role())}>\n<imageobject>\n<imagedata fileref=\"\{src}\"\{image_size_attributes(node.attributes)}/>\n</imageobject>\n<textobject><phrase>\{node.alt()}</phrase></textobject>\n</inlinemediaobject>"
  match (fileref, node.attr("link")) {
    (Some(fileref), Some(link_href)) =>
      "<link xl:href=\"\{if link_href == "self" { fileref } else { link_href }}\">\{img}</link>"
    _ => img
  }
}

///|
fn convert_inline_indexterm(node : @core.Node) -> String {
  let rel = match node.attr("see") {
    Some(see) => "\n<see>\{see}</see>"
    None =>
      match node.attributes.get("see-also") {
        Some(List(l)) =>
          l.map(see_also => "\n<seealso>\{see_also}</seealso>").join("")
        Some(Nil) | Some(Bool(false)) | None => ""
        Some(v) => "\n<seealso>\{v.to_s()}</seealso>"
      }
  }
  if node.inline_type == Some("visible") {
    let text = node.text().unwrap_or("")
    return "<indexterm>\n<primary>\{text}</primary>\{rel}\n</indexterm>\{text}"
  }
  let terms = list_attr(node, "terms")
  let numterms = terms.length()
  let promote = node.document().has_option("indexterm-promotion")
  let term = fn(i : Int) { terms.get(i).unwrap_or("") }
  if numterms > 2 {
    let promoted = if promote {
      "\n<indexterm>\n<primary>\{term(1)}</primary><secondary>\{term(2)}</secondary>\n</indexterm>\n<indexterm>\n<primary>\{term(2)}</primary>\n</indexterm>"
    } else {
      ""
    }
    "<indexterm>\n<primary>\{term(0)}</primary><secondary>\{term(1)}</secondary><tertiary>\{term(2)}</tertiary>\{rel}\n</indexterm>\{promoted}"
  } else if numterms > 1 {
    let promoted = if promote {
      "\n<indexterm>\n<primary>\{term(1)}</primary>\n</indexterm>"
    } else {
      ""
    }
    "<indexterm>\n<primary>\{term(0)}</primary><secondary>\{term(1)}</secondary>\{rel}\n</indexterm>\{promoted}"
  } else {
    "<indexterm>\n<primary>\{term(0)}</primary>\{rel}\n</indexterm>"
  }
}

///|
fn convert_inline_kbd(node : @core.Node) -> String {
  let keys = list_attr(node, "keys")
  if keys.length() == 1 {
    "<keycap>\{keys[0]}</keycap>"
  } else {
    "<keycombo><keycap>\{keys.join("</keycap><keycap>")}</keycap></keycombo>"
  }
}

///|
fn convert_inline_menu(node : @core.Node) -> String {
  let menu = a(node, "menu")
  let submenus = list_attr(node, "submenus")
  if submenus.is_empty() {
    match node.attr("menuitem") {
      Some(menuitem) =>
        "<menuchoice><guimenu>\{menu}</guimenu> <guimenuitem>\{menuitem}</guimenuitem></menuchoice>"
      None => "<guimenu>\{menu}</guimenu>"
    }
  } else {
    "<menuchoice><guimenu>\{menu}</guimenu> <guisubmenu>\{submenus.join("</guisubmenu> <guisubmenu>")}</guisubmenu> <guimenuitem>\{a(node, "menuitem")}</guimenuitem></menuchoice>"
  }
}

///|
fn quote_tags(type_ : String) -> (String, String, Bool) {
  match type_ {
    "monospaced" => ("<literal>", "</literal>", false)
    "emphasis" => ("<emphasis>", "</emphasis>", true)
    "strong" => ("<emphasis role=\"strong\">", "</emphasis>", true)
    "double" => ("<quote role=\"double\">", "</quote>", true)
    "single" => ("<quote role=\"single\">", "</quote>", true)
    "mark" => ("<emphasis role=\"marked\">", "</emphasis>", false)
    "superscript" => ("<superscript>", "</superscript>", false)
    "subscript" => ("<subscript>", "</subscript>", false)
    _ => ("", "", true)
  }
}

///|
fn DocBook5Converter::convert_inline_quoted(
  self : DocBook5Converter,
  node : @core.Node,
) -> String {
  let type_ = node.inline_type.unwrap_or("")
  let text = node.text().unwrap_or("")
  match type_ {
    "asciimath" => {
      // NOTE fop requires jeuclid to process mathml markup
      ignore(self.asciimath_available())
      "<inlineequation><mathphrase><![CDATA[\{text}]]></mathphrase></inlineequation>"
    }
    "latexmath" =>
      // unhandled math; pass source to alt and required mathphrase element; dblatex will process alt as LaTeX math
      "<inlineequation><alt><![CDATA[\{text}]]></alt><mathphrase><![CDATA[\{text}]]></mathphrase></inlineequation>"
    _ => {
      let (open, close, supports_phrase) = quote_tags(type_)
      let quoted_text = match node.role() {
        Some(role) =>
          if supports_phrase {
            "\{open}<phrase role=\"\{role}\">\{text}</phrase>\{close}"
          } else {
            "\{@rb.chop(open)} role=\"\{role}\">\{text}\{close}"
          }
        None => "\{open}\{text}\{close}"
      }
      match node.id {
        Some(id) => "<anchor\{common_attributes(Some(id))}/>\{quoted_text}"
        None => quoted_text
      }
    }
  }
}
