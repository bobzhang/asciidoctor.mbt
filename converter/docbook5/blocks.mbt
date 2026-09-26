///|
fn convert_admonition(node : @core.Node) -> String {
  let tag_name = a(node, "name")
  "<\{tag_name}\{block_attrs(node)}>\n\{title_tag(node)}\{enclose_content(node)}\n</\{tag_name}>"
}

///|
fn convert_colist(node : @core.Node) -> String {
  let result = []
  result.push("<calloutlist\{block_attrs(node)}>")
  if node.has_title() {
    result.push("<title>\{title_of(node)}</title>")
  }
  for item in node.items() {
    result.push("<callout arearefs=\"\{a(item, "coids")}\">")
    result.push("<para>\{item.text().unwrap_or("")}</para>")
    if item.has_blocks() {
      result.push(item.content())
    }
    result.push("</callout>")
  }
  result.push("</calloutlist>")
  result.join("\n")
}

///|
priv struct DlistTags {
  list : String?
  entry : String
  label : String?
  term : String
  item : String
}

///|
fn dlist_tags(style : String?) -> DlistTags {
  match style {
    Some("qanda") =>
      {
        list: Some("qandaset"),
        entry: "qandaentry",
        label: Some("question"),
        term: "simpara",
        item: "answer",
      }
    Some("glossary") =>
      {
        list: None,
        entry: "glossentry",
        label: None,
        term: "glossterm",
        item: "glossdef",
      }
    _ =>
      {
        list: Some("variablelist"),
        entry: "varlistentry",
        label: None,
        term: "term",
        item: "listitem",
      }
  }
}

///|
fn convert_dlist(node : @core.Node) -> String {
  let result = []
  if node.style == Some("horizontal") {
    let tag_name = if node.has_title() { "table" } else { "informaltable" }
    result.push(
      "<\{tag_name}\{block_attrs(node)} tabstyle=\"horizontal\" frame=\"none\" colsep=\"0\" rowsep=\"0\">\n\{title_tag(node)}<tgroup cols=\"2\">\n<colspec colwidth=\"\{node.attr("labelwidth", default="15").unwrap_or("15")}*\"/>\n<colspec colwidth=\"\{node.attr("itemwidth", default="85").unwrap_or("85")}*\"/>\n<tbody valign=\"top\">",
    )
    for item in node.dlist_items {
      result.push("<row>\n<entry>")
      for dt in item.terms {
        result.push("<simpara>\{dt.text().unwrap_or("")}</simpara>")
      }
      result.push("</entry>\n<entry>")
      match item.desc {
        Some(dd) => {
          if dd.has_text() {
            result.push("<simpara>\{dd.text().unwrap_or("")}</simpara>")
          }
          if dd.has_blocks() {
            result.push(dd.content())
          }
        }
        None => ()
      }
      result.push("</entry>\n</row>")
    }
    result.push("</tbody>\n</tgroup>\n</\{tag_name}>")
  } else {
    let tags = dlist_tags(node.style)
    match tags.list {
      Some(list_tag) => {
        result.push("<\{list_tag}\{block_attrs(node)}>")
        if node.has_title() {
          result.push("<title>\{title_of(node)}</title>")
        }
      }
      None => ()
    }
    for item in node.dlist_items {
      result.push("<\{tags.entry}>")
      match tags.label {
        Some(l) => result.push("<\{l}>")
        None => ()
      }
      for dt in item.terms {
        result.push("<\{tags.term}>\{dt.text().unwrap_or("")}</\{tags.term}>")
      }
      match tags.label {
        Some(l) => result.push("</\{l}>")
        None => ()
      }
      result.push("<\{tags.item}>")
      match item.desc {
        Some(dd) => {
          if dd.has_text() {
            result.push("<simpara>\{dd.text().unwrap_or("")}</simpara>")
          }
          if dd.has_blocks() {
            result.push(dd.content())
          }
        }
        None => ()
      }
      result.push("</\{tags.item}>")
      result.push("</\{tags.entry}>")
    }
    match tags.list {
      Some(list_tag) => result.push("</\{list_tag}>")
      None => ()
    }
  }
  result.join("\n")
}

///|
fn convert_example(node : @core.Node) -> String {
  if node.has_title() {
    "<example\{block_attrs(node)}>\n<title>\{title_of(node)}</title>\n\{enclose_content(node)}\n</example>"
  } else {
    "<informalexample\{block_attrs(node)}>\n\{enclose_content(node)}\n</informalexample>"
  }
}

///|
fn convert_floating_title(node : @core.Node) -> String {
  "<bridgehead\{block_attrs(node)} renderas=\"sect\{node.level}\">\{title_of(node)}</bridgehead>"
}

///|
fn convert_image(node : @core.Node) -> String {
  let align_attribute = if node.has_attr("align") {
    " align=\"\{a(node, "align")}\""
  } else {
    ""
  }
  let mediaobject = "<mediaobject>\n<imageobject>\n<imagedata fileref=\"\{node.image_uri(a(node, "target"))}\"\{image_size_attributes(node.attributes)}\{align_attribute}/>\n</imageobject>\n<textobject><phrase>\{node.alt()}</phrase></textobject>\n</mediaobject>"
  if node.has_title() {
    "<figure\{block_attrs(node)}>\n<title>\{title_of(node)}</title>\n\{mediaobject}\n</figure>"
  } else {
    "<informalfigure\{block_attrs(node)}>\n\{mediaobject}\n</informalfigure>"
  }
}

///|
fn convert_listing(node : @core.Node) -> String {
  let informal = !node.has_title()
  let common_attrs = block_attrs(node)
  let informal_attrs = if informal { common_attrs } else { "" }
  let wrapped_content = if node.style == Some("source") {
    let attrs = node.attributes
    let numbering_attrs = if node.has_option("linenums") {
      match attrs.get("start") {
        Some(start) =>
          " linenumbering=\"numbered\" startinglinenumber=\"\{attr_to_i(start)}\""
        None => " linenumbering=\"numbered\""
      }
    } else {
      " linenumbering=\"unnumbered\""
    }
    match attrs.get("language") {
      Some(lang) =>
        "<programlisting\{informal_attrs} language=\"\{lang.to_s()}\"\{numbering_attrs}>\{node.content()}</programlisting>"
      None =>
        "<screen\{informal_attrs}\{numbering_attrs}>\{node.content()}</screen>"
    }
  } else {
    "<screen\{informal_attrs}>\{node.content()}</screen>"
  }
  if informal {
    wrapped_content
  } else {
    "<formalpara\{common_attrs}>\n<title>\{title_of(node)}</title>\n<para>\n\{wrapped_content}\n</para>\n</formalpara>"
  }
}

///|
/// Ruby `to_i` of an attribute value.
fn attr_to_i(v : @core.AttrVal) -> Int {
  match v {
    Str(s) => @rb.to_i(s)
    Nil => 0
    v => v.to_i()
  }
}

///|
fn convert_literal(node : @core.Node) -> String {
  if node.has_title() {
    "<formalpara\{block_attrs(node)}>\n<title>\{title_of(node)}</title>\n<para>\n<literallayout class=\"monospaced\">\{node.content()}</literallayout>\n</para>\n</formalpara>"
  } else {
    "<literallayout\{block_attrs(node)} class=\"monospaced\">\{node.content()}</literallayout>"
  }
}

///|
fn DocBook5Converter::convert_stem(
  self : DocBook5Converter,
  node : @core.Node,
) -> String {
  let equation = match node.subs.search(SpecialCharacters) {
    Some(idx) => {
      node.subs.remove(idx) |> ignore
      let equation = node.content()
      node.subs.insert(idx, SpecialCharacters)
      equation
    }
    None => node.content()
  }
  let equation_data = if node.style == Some("asciimath") {
    // NOTE fop requires jeuclid to process mathml markup
    // (AsciiMath to MathML conversion is unavailable; see asciimath_available)
    ignore(self.asciimath_available())
    "<mathphrase><![CDATA[\{equation}]]></mathphrase>"
  } else {
    // unhandled math; pass source to alt and required mathphrase element; dblatex will process alt as LaTeX math
    "<alt><![CDATA[\{equation}]]></alt>\n<mathphrase><![CDATA[\{equation}]]></mathphrase>"
  }
  if node.has_title() {
    "<equation\{block_attrs(node)}>\n<title>\{title_of(node)}</title>\n\{equation_data}\n</equation>"
  } else {
    // WARNING dblatex displays the <informalequation> element inline instead of block as documented (except w/ mathml)
    "<informalequation\{block_attrs(node)}>\n\{equation_data}\n</informalequation>"
  }
}

///|
fn convert_olist(node : @core.Node) -> String {
  let result = []
  let num_attribute = match node.style {
    Some(s) => " numeration=\"\{s}\""
    None => ""
  }
  let start_attribute = if node.has_attr("start") {
    " startingnumber=\"\{a(node, "start")}\""
  } else {
    ""
  }
  result.push(
    "<orderedlist\{block_attrs(node)}\{num_attribute}\{start_attribute}>",
  )
  if node.has_title() {
    result.push("<title>\{title_of(node)}</title>")
  }
  for item in node.items() {
    result.push("<listitem\{common_attributes(item.id, role=item.role())}>")
    result.push("<simpara>\{item.text().unwrap_or("")}</simpara>")
    if item.has_blocks() {
      result.push(item.content())
    }
    result.push("</listitem>")
  }
  result.push("</orderedlist>")
  result.join("\n")
}

///|
fn DocBook5Converter::convert_open(
  self : DocBook5Converter,
  node : @core.Node,
) -> String {
  let doc = node.document()
  match node.style {
    Some("abstract") => {
      let parent = node.parent()
      let parent_is_doc = match parent {
        Some(p) => physical_equal(p, doc)
        None => false
      }
      if parent_is_doc && doc.doctype() == "book" {
        warn(
          "abstract block cannot be used in a document without a doctitle when doctype is book. Excluding block content.",
        )
        ""
      } else {
        let result = "<abstract>\n\{title_tag(node)}\{enclose_content(node)}\n</abstract>"
        match parent {
          Some(p) if self.backend == "docbook5" &&
            !node.has_option("root") &&
            (if p.context == Open {
              p.style == Some("partintro")
            } else {
              p.context == Section && p.sectname == Some("partintro")
            }) &&
            (match p.blocks.get(0) {
              Some(b) => physical_equal(b, node)
              None => false
            }) => "<info>\n\{result}\n</info>"
          _ => result
        }
      }
    }
    Some("partintro") =>
      if node.level == 0 &&
        (match node.parent() {
          Some(p) => p.context == Section
          None => false
        }) &&
        doc.doctype() == "book" {
        "<partintro\{block_attrs(node)}>\n\{title_tag(node)}\{enclose_content(node)}\n</partintro>"
      } else {
        error(
          "partintro block can only be used when doctype is book and must be a child of a book part. Excluding block content.",
        )
        ""
      }
    _ => {
      let id = node.id
      let reftext = match id {
        Some(_) => node.reftext()
        None => None
      }
      let role = node.role()
      if node.has_title() {
        let content_spacer = if node.content_model == Compound {
          "\n"
        } else {
          ""
        }
        "<formalpara\{common_attributes(id, role~, reftext~)}>\n<title>\{title_of(node)}</title>\n<para>\{content_spacer}\{node.content()}\{content_spacer}</para>\n</formalpara>"
      } else if id is Some(_) || role is Some(_) {
        if node.content_model == Compound {
          "<para\{common_attributes(id, role~, reftext~)}>\n\{node.content()}\n</para>"
        } else {
          "<simpara\{common_attributes(id, role~, reftext~)}>\{node.content()}</simpara>"
        }
      } else {
        enclose_content(node)
      }
    }
  }
}

///|
fn convert_paragraph(node : @core.Node) -> String {
  if node.has_title() {
    "<formalpara\{block_attrs(node)}>\n<title>\{title_of(node)}</title>\n<para>\{node.content()}</para>\n</formalpara>"
  } else {
    "<simpara\{block_attrs(node)}>\{node.content()}</simpara>"
  }
}

///|
fn convert_quote(node : @core.Node) -> String {
  blockquote_tag(
    node,
    if node.has_role("epigraph") {
      Some("epigraph")
    } else {
      None
    },
    () => enclose_content(node),
  )
}

///|
fn convert_verse(node : @core.Node) -> String {
  blockquote_tag(
    node,
    if node.has_role("epigraph") {
      Some("epigraph")
    } else {
      None
    },
    () => "<literallayout>\{node.content()}</literallayout>",
  )
}

///|
fn blockquote_tag(
  node : @core.Node,
  tag_name : String?,
  body : () -> String,
) -> String {
  let (start_tag, end_tag) = match tag_name {
    Some(t) => ("<\{t}", "</\{t}>")
    None => ("<blockquote", "</blockquote>")
  }
  let result = ["\{start_tag}\{block_attrs(node)}>"]
  if node.has_title() {
    result.push("<title>\{title_of(node)}</title>")
  }
  if node.has_attr("attribution") || node.has_attr("citetitle") {
    result.push("<attribution>")
    if node.has_attr("attribution") {
      result.push(a(node, "attribution"))
    }
    if node.has_attr("citetitle") {
      result.push("<citetitle>\{a(node, "citetitle")}</citetitle>")
    }
    result.push("</attribution>")
  }
  result.push(body())
  result.push(end_tag)
  result.join("\n")
}

///|
fn convert_sidebar(node : @core.Node) -> String {
  "<sidebar\{block_attrs(node)}>\n\{title_tag(node)}\{enclose_content(node)}\n</sidebar>"
}

///|
fn convert_table(node : @core.Node) -> String {
  let mut has_body = false
  let result = []
  let pgwide_attribute = if node.has_option("pgwide") {
    " pgwide=\"1\""
  } else {
    ""
  }
  let mut frame = node
    .attr("frame", default="all", fallback_name="table-frame")
    .unwrap_or("all")
  if frame == "ends" {
    frame = "topbot"
  }
  let grid = node.attr("grid", fallback_name="table-grid")
  let rowsep = if grid == Some("none") || grid == Some("cols") { 0 } else { 1 }
  let colsep = if grid == Some("none") || grid == Some("rows") { 0 } else { 1 }
  let orient = if node.attr("orientation", fallback_name="table-orientation") ==
    Some("landscape") {
    " orient=\"land\""
  } else {
    ""
  }
  let tag_name = if node.has_title() { "table" } else { "informaltable" }
  result.push(
    "<\{tag_name}\{block_attrs(node)}\{pgwide_attribute} frame=\"\{frame}\" rowsep=\"\{rowsep}\" colsep=\"\{colsep}\"\{orient}>",
  )
  if node.has_option("unbreakable") {
    result.push("<?dbfo keep-together=\"always\"?>")
  } else if node.has_option("breakable") {
    result.push("<?dbfo keep-together=\"auto\"?>")
  }
  if tag_name == "table" {
    result.push("<title>\{title_of(node)}</title>")
  }
  let col_width_key = if node.has_attr("width") {
    let width = a(node, "width")
    for pi_name in ["dbhtml", "dbfo", "dblatex"] {
      result.push("<?\{pi_name} table-width=\"\{width}\"?>")
    }
    "colabswidth"
  } else {
    "colpcwidth"
  }
  result.push("<tgroup cols=\"\{a(node, "colcount")}\">")
  for col in node.columns() {
    result.push(
      "<colspec colname=\"col_\{a(col, "colnumber")}\" colwidth=\"\{a(col, col_width_key)}*\"/>",
    )
  }
  let rows = node.rows()
  let doc = node.document()
  for tsec in [("head", rows.head), ("body", rows.body), ("foot", rows.foot)] {
    let (tsec_name, section_rows) = tsec
    if section_rows.is_empty() {
      continue
    }
    if tsec_name == "body" {
      has_body = true
    }
    result.push("<t\{tsec_name}>")
    for row in section_rows {
      result.push("<row>")
      for cell in row {
        let colspan_attribute = match cell.colspan() {
          Some(colspan) => {
            let colnum = match cell.column() {
              Some(col) =>
                col.attributes.get("colnumber").map(v => v.to_i()).unwrap_or(0)
              None => 0
            }
            " namest=\"col_\{colnum}\" nameend=\"col_\{colnum + colspan - 1}\""
          }
          None => ""
        }
        let rowspan_attribute = match cell.rowspan() {
          Some(rowspan) => " morerows=\"\{rowspan - 1}\""
          None => ""
        }
        // NOTE <entry> may not have whitespace (e.g., line breaks) as a direct descendant according to DocBook rules
        let entry_start = "<entry align=\"\{a(cell, "halign")}\" valign=\"\{a(cell, "valign")}\"\{colspan_attribute}\{rowspan_attribute}>"
        let cell_content = if tsec_name == "head" {
          cell.text().unwrap_or("")
        } else {
          match cell.style {
            Some("asciidoc") =>
              cell.inner_document().map(d => d.convert()).unwrap_or("")
            Some("literal") =>
              "<literallayout class=\"monospaced\">\{cell.text().unwrap_or("")}</literallayout>"
            Some("header") => {
              let paras = cell.cell_paragraphs()
              if paras.is_empty() {
                ""
              } else {
                "<simpara><emphasis role=\"strong\">\{paras.join("</emphasis></simpara><simpara><emphasis role=\"strong\">")}</emphasis></simpara>"
              }
            }
            _ => {
              let paras = cell.cell_paragraphs()
              if paras.is_empty() {
                ""
              } else {
                "<simpara>\{paras.join("</simpara><simpara>")}</simpara>"
              }
            }
          }
        }
        let entry_end = if doc.has_attr("cellbgcolor") {
          "<?dbfo bgcolor=\"\{a(doc, "cellbgcolor")}\"?></entry>"
        } else {
          "</entry>"
        }
        result.push("\{entry_start}\{cell_content}\{entry_end}")
      }
      result.push("</row>")
    }
    result.push("</t\{tsec_name}>")
  }
  result.push("</tgroup>")
  result.push("</\{tag_name}>")
  if !has_body {
    warn("tables must have at least one body row")
  }
  result.join("\n")
}

///|
fn convert_ulist(node : @core.Node) -> String {
  let result = []
  if node.style == Some("bibliography") {
    result.push("<bibliodiv\{block_attrs(node)}>")
    if node.has_title() {
      result.push("<title>\{title_of(node)}</title>")
    }
    for item in node.items() {
      result.push("<bibliomixed>")
      result.push("<bibliomisc>\{item.text().unwrap_or("")}</bibliomisc>")
      if item.has_blocks() {
        result.push(item.content())
      }
      result.push("</bibliomixed>")
    }
    result.push("</bibliodiv>")
  } else {
    let checklist = node.has_option("checklist")
    let mark_type = if checklist { Some("none") } else { node.style }
    let mark_attribute = match mark_type {
      Some(m) => " mark=\"\{m}\""
      None => ""
    }
    result.push("<itemizedlist\{block_attrs(node)}\{mark_attribute}>")
    if node.has_title() {
      result.push("<title>\{title_of(node)}</title>")
    }
    for item in node.items() {
      let text_marker = if checklist && item.has_attr("checkbox") {
        if item.has_attr("checked") {
          "&#10003; "
        } else {
          "&#10063; "
        }
      } else {
        ""
      }
      result.push("<listitem\{common_attributes(item.id, role=item.role())}>")
      result.push(
        "<simpara>\{text_marker}\{item.text().unwrap_or("")}</simpara>",
      )
      if item.has_blocks() {
        result.push(item.content())
      }
      result.push("</listitem>")
    }
    result.push("</itemizedlist>")
  }
  result.join("\n")
}
