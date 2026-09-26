///|
fn Html5Converter::convert_admonition(
  self : Html5Converter,
  node : @core.Node,
) -> String {
  let name = a(node, "name")
  let doc = node.document()
  let label = if doc.has_attr("icons") {
    if doc.has_attr("icons", expected="font") && !node.has_attr("icon") {
      "<i class=\"fa icon-\{name}\" title=\"\{a(node, "textlabel")}\"></i>"
    } else {
      "<img src=\"\{node.icon_uri(name)}\" alt=\"\{a(node, "textlabel")}\"\{self.void_element_slash}>"
    }
  } else {
    "<div class=\"title\">\{a(node, "textlabel")}</div>"
  }
  "<div\{id_attr(node)} class=\"admonitionblock \{name}\{role_suffix(node)}\">\n<table>\n<tr>\n<td class=\"icon\">\n\{label}\n</td>\n<td class=\"content\">\n\{title_div(node)}\{node.content()}\n</td>\n</tr>\n</table>\n</div>"
}

///|
fn Html5Converter::convert_audio(
  self : Html5Converter,
  node : @core.Node,
) -> String {
  let xml = self.xml_mode
  let classes = compact_join([Some("audioblock"), node.role()], " ")
  let start_t = node.attr("start")
  let end_t = node.attr("end")
  let time_anchor = if start_t is Some(_) || end_t is Some(_) {
    "#t=\{start_t.unwrap_or("")}\{match end_t { Some(e) => ",\{e}"; None => "" }}"
  } else {
    ""
  }
  let autoplay = if node.has_option("autoplay") {
    self.append_boolean_attribute("autoplay", xml)
  } else {
    ""
  }
  let controls = if node.has_option("nocontrols") {
    ""
  } else {
    self.append_boolean_attribute("controls", xml)
  }
  let loop_ = if node.has_option("loop") {
    self.append_boolean_attribute("loop", xml)
  } else {
    ""
  }
  "<div\{id_attr(node)} class=\"\{classes}\">\n\{title_div(node)}<div class=\"content\">\n<audio src=\"\{node.media_uri(a(node, "target"))}\{time_anchor}\"\{autoplay}\{controls}\{loop_}>\nYour browser does not support the audio tag.\n</audio>\n</div>\n</div>"
}

///|
fn Html5Converter::convert_colist(
  self : Html5Converter,
  node : @core.Node,
) -> String {
  let result = []
  let classes = compact_join([Some("colist"), node.style, node.role()], " ")
  result.push("<div\{id_attr(node)} class=\"\{classes}\">")
  if node.has_title() {
    result.push("<div class=\"title\">\{node.title().unwrap_or("")}</div>")
  }
  let doc = node.document()
  if doc.has_attr("icons") {
    result.push("<table>")
    let font_icons = doc.has_attr("icons", expected="font")
    let mut num = 0
    for item in node.items() {
      num += 1
      let num_label = if font_icons {
        "<i class=\"conum\" data-value=\"\{num}\"></i><b>\{num}</b>"
      } else {
        "<img src=\"\{node.icon_uri("callouts/\{num}")}\" alt=\"\{num}\"\{self.void_element_slash}>"
      }
      let extra = if item.has_blocks() { "\n" + item.content() } else { "" }
      result.push(
        "<tr>\n<td>\{num_label}</td>\n<td>\{item.text().unwrap_or("")}\{extra}</td>\n</tr>",
      )
    }
    result.push("</table>")
  } else {
    result.push("<ol>")
    for item in node.items() {
      let extra = if item.has_blocks() { "\n" + item.content() } else { "" }
      result.push("<li>\n<p>\{item.text().unwrap_or("")}</p>\{extra}\n</li>")
    }
    result.push("</ol>")
  }
  result.push("</div>")
  result.join("\n")
}

///|
fn Html5Converter::convert_dlist(
  self : Html5Converter,
  node : @core.Node,
) -> String {
  let result = []
  let classes = match node.style {
    Some("qanda") => [Some("qlist"), Some("qanda"), node.role()]
    Some("horizontal") => [Some("hdlist"), node.role()]
    _ => [Some("dlist"), node.style, node.role()]
  }
  result.push("<div\{id_attr(node)} class=\"\{compact_join(classes, " ")}\">")
  if node.has_title() {
    result.push("<div class=\"title\">\{node.title().unwrap_or("")}</div>")
  }
  match node.style {
    Some("qanda") => {
      result.push("<ol>")
      for item in node.dlist_items {
        result.push("<li>")
        for dt in item.terms {
          result.push("<p><em>\{dt.text().unwrap_or("")}</em></p>")
        }
        match item.desc {
          Some(dd) => {
            if dd.has_text() {
              result.push("<p>\{dd.text().unwrap_or("")}</p>")
            }
            if dd.has_blocks() {
              result.push(dd.content())
            }
          }
          None => ()
        }
        result.push("</li>")
      }
      result.push("</ol>")
    }
    Some("horizontal") => {
      let slash = self.void_element_slash
      result.push("<table>")
      if node.has_attr("labelwidth") || node.has_attr("itemwidth") {
        result.push("<colgroup>")
        let lw = if node.has_attr("labelwidth") {
          " width=\"\{@rb.chomp_suffix(a(node, "labelwidth"), "%")}%\""
        } else {
          ""
        }
        result.push("<col\{lw}\{slash}>")
        let iw = if node.has_attr("itemwidth") {
          " width=\"\{@rb.chomp_suffix(a(node, "itemwidth"), "%")}%\""
        } else {
          ""
        }
        result.push("<col\{iw}\{slash}>")
        result.push("</colgroup>")
      }
      for item in node.dlist_items {
        result.push("<tr>")
        result.push(
          "<td class=\"hdlist1\{if node.has_option("strong") { " strong" } else { "" }}\">",
        )
        let mut first_term = true
        for dt in item.terms {
          if !first_term {
            result.push("<br\{slash}>")
          }
          result.push(dt.text().unwrap_or(""))
          first_term = false
        }
        result.push("</td>")
        result.push("<td class=\"hdlist2\">")
        match item.desc {
          Some(dd) => {
            if dd.has_text() {
              result.push("<p>\{dd.text().unwrap_or("")}</p>")
            }
            if dd.has_blocks() {
              result.push(dd.content())
            }
          }
          None => ()
        }
        result.push("</td>")
        result.push("</tr>")
      }
      result.push("</table>")
    }
    _ => {
      result.push("<dl>")
      let dt_style_attribute = if node.style is Some(_) {
        ""
      } else {
        " class=\"hdlist1\""
      }
      for item in node.dlist_items {
        for dt in item.terms {
          result.push(
            "<dt\{dt_style_attribute}>\{dt.text().unwrap_or("")}</dt>",
          )
        }
        match item.desc {
          Some(dd) => {
            result.push("<dd>")
            if dd.has_text() {
              result.push("<p>\{dd.text().unwrap_or("")}</p>")
            }
            if dd.has_blocks() {
              result.push(dd.content())
            }
            result.push("</dd>")
          }
          None => ()
        }
      }
      result.push("</dl>")
    }
  }
  result.push("</div>")
  result.join("\n")
}

///|
fn Html5Converter::convert_example(
  self : Html5Converter,
  node : @core.Node,
) -> String {
  ignore(self)
  if node.has_option("collapsible") {
    let class_attribute = match node.role() {
      Some(r) => " class=\"\{r}\""
      None => ""
    }
    let summary_element = if node.has_title() {
      "<summary class=\"title\">\{node.title().unwrap_or("")}</summary>"
    } else {
      "<summary class=\"title\">Details</summary>"
    }
    "<details\{id_attr(node)}\{class_attribute}\{if node.has_option("open") { " open" } else { "" }}>\n\{summary_element}\n<div class=\"content\">\n\{node.content()}\n</div>\n</details>"
  } else {
    let title_element = if node.has_title() {
      "<div class=\"title\">\{node.captioned_title()}</div>\n"
    } else {
      ""
    }
    "<div\{id_attr(node)} class=\"exampleblock\{role_suffix(node)}\">\n\{title_element}<div class=\"content\">\n\{node.content()}\n</div>\n</div>"
  }
}

///|
fn Html5Converter::convert_floating_title(
  self : Html5Converter,
  node : @core.Node,
) -> String {
  ignore(self)
  let tag_name = "h\{node.level + 1}"
  let classes = compact_join([node.style, node.role()], " ")
  "<\{tag_name}\{id_attr(node)} class=\"\{classes}\">\{node.title().unwrap_or("")}</\{tag_name}>"
}

///|
fn Html5Converter::convert_image(
  self : Html5Converter,
  node : @core.Node,
) -> String {
  let target = a(node, "target")
  let width_attr = if node.has_attr("width") {
    " width=\"\{a(node, "width")}\""
  } else {
    ""
  }
  let height_attr = if node.has_attr("height") {
    " height=\"\{a(node, "height")}\""
  } else {
    ""
  }
  let slash = self.void_element_slash
  let mut src : String? = None
  let img = if (
      node.has_attr("format", expected="svg") || target.contains(".svg")
    ) &&
    node.document().safe() < @core.SAFE_SECURE {
    if node.has_option("inline") {
      match self.read_svg_contents(node, target) {
        Some(svg) => svg
        None => "<span class=\"alt\">\{node.alt()}</span>"
      }
    } else if node.has_option("interactive") {
      let fallback = if node.has_attr("fallback") {
        "<img src=\"\{node.image_uri(a(node, "fallback"))}\" alt=\"\{encode_attribute_value(node.alt())}\"\{width_attr}\{height_attr}\{slash}>"
      } else {
        "<span class=\"alt\">\{node.alt()}</span>"
      }
      let s = node.image_uri(target)
      src = Some(s)
      "<object type=\"image/svg+xml\" data=\"\{s}\"\{width_attr}\{height_attr}>\{fallback}</object>"
    } else {
      let s = node.image_uri(target)
      src = Some(s)
      "<img src=\"\{s}\" alt=\"\{encode_attribute_value(node.alt())}\"\{width_attr}\{height_attr}\{slash}>"
    }
  } else {
    let s = node.image_uri(target)
    src = Some(s)
    "<img src=\"\{s}\" alt=\"\{encode_attribute_value(node.alt())}\"\{width_attr}\{height_attr}\{slash}>"
  }
  let img = wrap_image_link(node, img, src)
  let classes = ["imageblock"]
  if node.has_attr("float") {
    classes.push(a(node, "float"))
  }
  if node.has_attr("align") {
    classes.push("text-\{a(node, "align")}")
  }
  match node.role() {
    Some(r) => classes.push(r)
    None => ()
  }
  let title_el = if node.has_title() {
    "\n<div class=\"title\">\{node.captioned_title()}</div>"
  } else {
    ""
  }
  "<div\{id_attr(node)} class=\"\{classes.join(" ")}\">\n<div class=\"content\">\n\{img}\n</div>\{title_el}\n</div>"
}

///|
fn wrap_image_link(node : @core.Node, img : String, src : String?) -> String {
  if node.has_attr("link") {
    let link = a(node, "link")
    let href = if link != "self" { Some(link) } else { src }
    match href {
      Some(h) =>
        "<a class=\"image\" href=\"\{h}\"\{append_link_constraint_attrs(node, []).join("")}>\{img}</a>"
      None => img
    }
  } else {
    img
  }
}

///|
fn Html5Converter::convert_listing(
  self : Html5Converter,
  node : @core.Node,
) -> String {
  ignore(self)
  let doc = node.document()
  let nowrap = node.has_option("nowrap") || !doc.has_attr("prewrap")
  let mut pre_open = ""
  let mut pre_close = ""
  let mut syntax_hl : &@core.SyntaxHighlighter? = None
  let mut lang : String? = None
  if node.style == Some("source") {
    lang = node.attr("language")
    match doc.syntax_highlighter() {
      Some(hl) => syntax_hl = Some(hl)
      None => {
        let lang_attrs = match lang {
          Some(l) => " class=\"language-\{l}\" data-lang=\"\{l}\""
          None => ""
        }
        pre_open = "<pre class=\"highlight\{if nowrap { " nowrap" } else { "" }}\"><code\{lang_attrs}>"
        pre_close = "</code></pre>"
      }
    }
  } else {
    pre_open = "<pre\{if nowrap { " class=\"nowrap\"" } else { "" }}>"
    pre_close = "</pre>"
  }
  let title_element = if node.has_title() {
    "<div class=\"title\">\{node.captioned_title()}</div>\n"
  } else {
    ""
  }
  let body = match syntax_hl {
    Some(hl) => {
      let opts = if hl.handles_highlighting() {
        let doc_attrs = doc.attributes
        @core.FormatOptions::new(
          nowrap~,
          css_mode=doc_attrs.str("\{hl.name()}-css").unwrap_or("class"),
          style?=doc_attrs.str("\{hl.name()}-style"),
        )
      } else {
        @core.FormatOptions::new(nowrap~)
      }
      hl.format(node, lang, opts)
    }
    None => pre_open + node.content() + pre_close
  }
  "<div\{id_attr(node)} class=\"listingblock\{role_suffix(node)}\">\n\{title_element}<div class=\"content\">\n\{body}\n</div>\n</div>"
}

///|
fn Html5Converter::convert_literal(
  self : Html5Converter,
  node : @core.Node,
) -> String {
  ignore(self)
  let nowrap = !node.document().has_attr("prewrap") || node.has_option("nowrap")
  "<div\{id_attr(node)} class=\"literalblock\{role_suffix(node)}\">\n\{title_div(node)}<div class=\"content\">\n<pre\{if nowrap { " class=\"nowrap\"" } else { "" }}>\{node.content()}</pre>\n</div>\n</div>"
}

///|
fn Html5Converter::convert_stem(
  self : Html5Converter,
  node : @core.Node,
) -> String {
  let style = node.style.unwrap_or("asciimath")
  let (open, close) = if style == "latexmath" {
    ("\\[", "\\]")
  } else {
    ("\\$", "\\$")
  }
  let mut equation = node.content()
  if style == "asciimath" && equation.contains("\n") {
    let br = "\n<br\{self.void_element_slash}>"
    equation = stem_break_rx.replace(equation, m => {
      let count = @rb.count(m.matched(), "\n")
      "\{close}\{@rb.repeat(br, count - 1)}\n\{open}"
    })
  }
  if !(equation.has_prefix(open) && equation.has_suffix(close)) {
    equation = "\{open}\{equation}\{close}"
  }
  "<div\{id_attr(node)} class=\"stemblock\{role_suffix(node)}\">\n\{title_div(node)}<div class=\"content\">\n\{equation}\n</div>\n</div>"
}

///|
fn Html5Converter::convert_olist(
  self : Html5Converter,
  node : @core.Node,
) -> String {
  let result = []
  let classes = compact_join([Some("olist"), node.style, node.role()], " ")
  result.push("<div\{id_attr(node)} class=\"\{classes}\">")
  if node.has_title() {
    result.push("<div class=\"title\">\{node.title().unwrap_or("")}</div>")
  }
  let type_attribute = match node.list_marker_keyword() {
    Some(k) => " type=\"\{k}\""
    None => ""
  }
  let start_attribute = if node.has_attr("start") {
    " start=\"\{a(node, "start")}\""
  } else {
    ""
  }
  let reversed_attribute = if node.has_option("reversed") {
    self.append_boolean_attribute("reversed", self.xml_mode)
  } else {
    ""
  }
  result.push(
    "<ol class=\"\{node.style.unwrap_or("")}\"\{type_attribute}\{start_attribute}\{reversed_attribute}>",
  )
  for item in node.items() {
    result.push(li_open(item))
    result.push("<p>\{item.text().unwrap_or("")}</p>")
    if item.has_blocks() {
      result.push(item.content())
    }
    result.push("</li>")
  }
  result.push("</ol>")
  result.push("</div>")
  result.join("\n")
}

///|
fn li_open(item : @core.Node) -> String {
  match item.id {
    Some(id) =>
      "<li id=\"\{id}\"\{match item.role() { Some(r) => " class=\"\{r}\""; None => "" }}>"
    None =>
      match item.role() {
        Some(r) => "<li class=\"\{r}\">"
        None => "<li>"
      }
  }
}

///|
fn Html5Converter::convert_open(
  self : Html5Converter,
  node : @core.Node,
) -> String {
  ignore(self)
  let style = node.style
  let doc = node.document()
  if style == Some("abstract") {
    let parent_is_doc = match node.parent() {
      Some(p) => physical_equal(p, doc)
      None => false
    }
    if parent_is_doc && doc.doctype() == "book" {
      @core.logger().add({
        severity: Warn,
        text: "abstract block cannot be used in a document without a doctitle when doctype is book. Excluding block content.",
        source_location: None,
        include_location: None,
      })
      ""
    } else {
      "<div\{id_attr(node)} class=\"quoteblock abstract\{role_suffix(node)}\">\n\{title_div(node)}<blockquote>\n\{node.content()}\n</blockquote>\n</div>"
    }
  } else if style == Some("partintro") &&
    (
      node.level > 0 ||
      (match node.parent() {
        Some(p) => p.context != Section
        None => true
      }) ||
      doc.doctype() != "book"
    ) {
    @core.logger().add({
      severity: Error,
      text: "partintro block can only be used when doctype is book and must be a child of a book part. Excluding block content.",
      source_location: None,
      include_location: None,
    })
    ""
  } else {
    let style_class = match style {
      Some(s) if s != "open" => " \{s}"
      _ => ""
    }
    "<div\{id_attr(node)} class=\"openblock\{style_class}\{role_suffix(node)}\">\n\{title_div(node)}<div class=\"content\">\n\{node.content()}\n</div>\n</div>"
  }
}

///|
fn Html5Converter::convert_paragraph(
  self : Html5Converter,
  node : @core.Node,
) -> String {
  ignore(self)
  let attributes = match node.role() {
    Some(r) => "\{id_attr(node)} class=\"paragraph \{r}\""
    None =>
      match node.id {
        Some(id) => " id=\"\{id}\" class=\"paragraph\""
        None => " class=\"paragraph\""
      }
  }
  if node.has_title() {
    "<div\{attributes}>\n<div class=\"title\">\{node.title().unwrap_or("")}</div>\n<p>\{node.content()}</p>\n</div>"
  } else {
    "<div\{attributes}>\n<p>\{node.content()}</p>\n</div>"
  }
}

///|
fn Html5Converter::attribution_element(
  self : Html5Converter,
  node : @core.Node,
) -> String {
  let attribution = if node.has_attr("attribution") {
    node.attr("attribution")
  } else {
    None
  }
  let citetitle = if node.has_attr("citetitle") {
    node.attr("citetitle")
  } else {
    None
  }
  if attribution is Some(_) || citetitle is Some(_) {
    let cite_element = match citetitle {
      Some(c) => "<cite>\{c}</cite>"
      None => ""
    }
    let attribution_text = match attribution {
      Some(at) =>
        "&#8212; \{at}\{if citetitle is Some(_) { "<br\{self.void_element_slash}>\n" } else { "" }}"
      None => ""
    }
    "\n<div class=\"attribution\">\n\{attribution_text}\{cite_element}\n</div>"
  } else {
    ""
  }
}

///|
fn Html5Converter::convert_quote(
  self : Html5Converter,
  node : @core.Node,
) -> String {
  let classes = compact_join([Some("quoteblock"), node.role()], " ")
  let title_element = if node.has_title() {
    "\n<div class=\"title\">\{node.title().unwrap_or("")}</div>"
  } else {
    ""
  }
  "<div\{id_attr(node)} class=\"\{classes}\">\{title_element}\n<blockquote>\n\{node.content()}\n</blockquote>\{self.attribution_element(node)}\n</div>"
}

///|
fn Html5Converter::convert_verse(
  self : Html5Converter,
  node : @core.Node,
) -> String {
  let classes = compact_join([Some("verseblock"), node.role()], " ")
  let title_element = if node.has_title() {
    "\n<div class=\"title\">\{node.title().unwrap_or("")}</div>"
  } else {
    ""
  }
  "<div\{id_attr(node)} class=\"\{classes}\">\{title_element}\n<pre class=\"content\">\{node.content()}</pre>\{self.attribution_element(node)}\n</div>"
}

///|
fn Html5Converter::convert_thematic_break(
  self : Html5Converter,
  node : @core.Node,
) -> String {
  let class_attribute = match node.role() {
    Some(r) => " class=\"\{r}\""
    None => ""
  }
  "<hr\{class_attribute}\{self.void_element_slash}>"
}

///|
fn Html5Converter::convert_sidebar(
  self : Html5Converter,
  node : @core.Node,
) -> String {
  ignore(self)
  "<div\{id_attr(node)} class=\"sidebarblock\{role_suffix(node)}\">\n<div class=\"content\">\n\{title_div(node)}\{node.content()}\n</div>\n</div>"
}

///|
fn Html5Converter::convert_table(
  self : Html5Converter,
  node : @core.Node,
) -> String {
  let result = []
  let mut frame = node
    .attr("frame", default="all", fallback_name="table-frame")
    .unwrap_or("all")
  if frame == "topbot" {
    frame = "ends"
  }
  let classes = [
    "tableblock",
    "frame-\{frame}",
    "grid-\{node.attr("grid", default="all", fallback_name="table-grid").unwrap_or("all")}",
  ]
  match node.attr("stripes", fallback_name="table-stripes") {
    Some(stripes) => classes.push("stripes-\{stripes}")
    None => ()
  }
  let mut width_attribute = ""
  let autowidth = node.has_option("autowidth")
  if autowidth && !node.has_attr("width") {
    classes.push("fit-content")
  } else {
    let tablewidth = node.attributes.get("tablepcwidth")
    if tablewidth == Some(Int(100)) {
      classes.push("stretch")
    } else {
      width_attribute = " width=\"\{tablewidth.map(v => v.to_s()).unwrap_or("")}%\""
    }
  }
  if node.has_attr("float") {
    classes.push(a(node, "float"))
  }
  match node.role() {
    Some(r) => classes.push(r)
    None => ()
  }
  result.push(
    "<table\{id_attr(node)} class=\"\{classes.join(" ")}\"\{width_attribute}>",
  )
  if node.has_title() {
    result.push("<caption class=\"title\">\{node.captioned_title()}</caption>")
  }
  let rowcount = node.attributes.get("rowcount").map(v => v.to_i()).unwrap_or(0)
  if rowcount > 0 {
    let slash = self.void_element_slash
    result.push("<colgroup>")
    if autowidth {
      for _ in node.columns() {
        result.push("<col\{slash}>")
      }
    } else {
      for col in node.columns() {
        result.push(
          if col.has_option("autowidth") {
            "<col\{slash}>"
          } else {
            "<col width=\"\{a(col, "colpcwidth")}%\"\{slash}>"
          },
        )
      }
    }
    result.push("</colgroup>")
    let rows = node.rows()
    let doc = node.document()
    for tsec in [("head", rows.head), ("body", rows.body), ("foot", rows.foot)] {
      let (tsec_name, section_rows) = tsec
      if section_rows.is_empty() {
        continue
      }
      result.push("<t\{tsec_name}>")
      for row in section_rows {
        result.push("<tr>")
        for cell in row {
          let cell_content = if tsec_name == "head" {
            cell.text().unwrap_or("")
          } else {
            match cell.style {
              Some("asciidoc") =>
                "<div class=\"content\">\{cell.inner_document().map(d => d.convert()).unwrap_or("")}</div>"
              Some("literal") =>
                "<div class=\"literal\"><pre>\{cell.text().unwrap_or("")}</pre></div>"
              _ => {
                let paras = cell.cell_paragraphs()
                if paras.is_empty() {
                  ""
                } else {
                  "<p class=\"tableblock\">\{paras.join("</p>\n<p class=\"tableblock\">")}</p>"
                }
              }
            }
          }
          let cell_tag_name = if tsec_name == "head" ||
            cell.style == Some("header") {
            "th"
          } else {
            "td"
          }
          let cell_class_attribute = " class=\"tableblock halign-\{a(cell, "halign")} valign-\{a(cell, "valign")}\""
          let cell_colspan_attribute = match cell.colspan() {
            Some(c) => " colspan=\"\{c}\""
            None => ""
          }
          let cell_rowspan_attribute = match cell.rowspan() {
            Some(r) => " rowspan=\"\{r}\""
            None => ""
          }
          let cell_style_attribute = if doc.has_attr("cellbgcolor") {
            " style=\"background-color: \{a(doc, "cellbgcolor")};\""
          } else {
            ""
          }
          result.push(
            "<\{cell_tag_name}\{cell_class_attribute}\{cell_colspan_attribute}\{cell_rowspan_attribute}\{cell_style_attribute}>\{cell_content}</\{cell_tag_name}>",
          )
        }
        result.push("</tr>")
      }
      result.push("</t\{tsec_name}>")
    }
  }
  result.push("</table>")
  result.join("\n")
}

///|
fn Html5Converter::convert_ulist(
  self : Html5Converter,
  node : @core.Node,
) -> String {
  let result = []
  let div_classes = [Some("ulist"), node.style, node.role()].filter_map(x => x)
  let mut marker_checked = ""
  let mut marker_unchecked = ""
  let checklist = node.has_option("checklist")
  let ul_class_attribute = if checklist {
    div_classes.insert(1, "checklist")
    if node.has_option("interactive") {
      if self.xml_mode {
        marker_checked = "<input type=\"checkbox\" data-item-complete=\"1\" checked=\"checked\"/> "
        marker_unchecked = "<input type=\"checkbox\" data-item-complete=\"0\"/> "
      } else {
        marker_checked = "<input type=\"checkbox\" data-item-complete=\"1\" checked> "
        marker_unchecked = "<input type=\"checkbox\" data-item-complete=\"0\"> "
      }
    } else if node.document().has_attr("icons", expected="font") {
      marker_checked = "<i class=\"fa fa-check-square-o\"></i> "
      marker_unchecked = "<i class=\"fa fa-square-o\"></i> "
    } else {
      marker_checked = "&#10003; "
      marker_unchecked = "&#10063; "
    }
    " class=\"checklist\""
  } else {
    match node.style {
      Some(s) => " class=\"\{s}\""
      None => ""
    }
  }
  result.push("<div\{id_attr(node)} class=\"\{div_classes.join(" ")}\">")
  if node.has_title() {
    result.push("<div class=\"title\">\{node.title().unwrap_or("")}</div>")
  }
  result.push("<ul\{ul_class_attribute}>")
  for item in node.items() {
    result.push(li_open(item))
    if checklist && item.has_attr("checkbox") {
      let marker = if item.has_attr("checked") {
        marker_checked
      } else {
        marker_unchecked
      }
      result.push("<p>\{marker}\{item.text().unwrap_or("")}</p>")
    } else {
      result.push("<p>\{item.text().unwrap_or("")}</p>")
    }
    if item.has_blocks() {
      result.push(item.content())
    }
    result.push("</li>")
  }
  result.push("</ul>")
  result.push("</div>")
  result.join("\n")
}

///|
fn Html5Converter::convert_video(
  self : Html5Converter,
  node : @core.Node,
) -> String {
  let xml = self.xml_mode
  let classes = ["videoblock"]
  if node.has_attr("float") {
    classes.push(a(node, "float"))
  }
  if node.has_attr("align") {
    classes.push("text-\{a(node, "align")}")
  }
  match node.role() {
    Some(r) => classes.push(r)
    None => ()
  }
  let class_attribute = " class=\"\{classes.join(" ")}\""
  let title_element = if node.has_title() {
    "\n<div class=\"title\">\{node.title().unwrap_or("")}</div>"
  } else {
    ""
  }
  let width_attribute = if node.has_attr("width") {
    " width=\"\{a(node, "width")}\""
  } else {
    ""
  }
  let height_attribute = if node.has_attr("height") {
    " height=\"\{a(node, "height")}\""
  } else {
    ""
  }
  let asset_scheme = fn() {
    let s = node
      .document()
      .attr("asset-uri-scheme", default="https")
      .unwrap_or("https")
    if s == "" {
      s
    } else {
      "\{s}:"
    }
  }
  let bool_attr = fn(opt : String, name : String) {
    if node.has_option(opt) {
      self.append_boolean_attribute(name, xml)
    } else {
      ""
    }
  }
  let fullscreen = if node.has_option("nofullscreen") {
    ""
  } else {
    self.append_boolean_attribute("allowfullscreen", xml)
  }
  let head = "<div\{id_attr(node)}\{class_attribute}>\{title_element}\n<div class=\"content\">\n"
  match node.attr("poster") {
    Some("vimeo") => {
      let scheme = asset_scheme()
      let start_anchor = if node.has_attr("start") {
        "#at=\{a(node, "start")}"
      } else {
        ""
      }
      let delimiter = ["?"]
      let next_delim = fn() { delimiter.pop().unwrap_or("&amp;") }
      let parts = @rb.split(a(node, "target"), "/", limit=2)
      let target = parts.get(0).unwrap_or("")
      let hash = match parts.get(1) {
        Some(h) => Some(h)
        None => node.attr("hash")
      }
      let hash_param = match hash {
        Some(h) => "\{next_delim()}h=\{h}"
        None => ""
      }
      let autoplay_param = if node.has_option("autoplay") {
        "\{next_delim()}autoplay=1"
      } else {
        ""
      }
      let loop_param = if node.has_option("loop") {
        "\{next_delim()}loop=1"
      } else {
        ""
      }
      let muted_param = if node.has_option("muted") {
        "\{next_delim()}muted=1"
      } else {
        ""
      }
      "\{head}<iframe\{width_attribute}\{height_attribute} src=\"\{scheme}//player.vimeo.com/video/\{target}\{hash_param}\{autoplay_param}\{loop_param}\{muted_param}\{start_anchor}\" frameborder=\"0\"\{fullscreen}></iframe>\n</div>\n</div>"
    }
    Some("youtube") => {
      let scheme = asset_scheme()
      let rel_param_val = if node.has_option("related") { 1 } else { 0 }
      let start_param = if node.has_attr("start") {
        "&amp;start=\{a(node, "start")}"
      } else {
        ""
      }
      let end_param = if node.has_attr("end") {
        "&amp;end=\{a(node, "end")}"
      } else {
        ""
      }
      let autoplay_param = if node.has_option("autoplay") {
        "&amp;autoplay=1"
      } else {
        ""
      }
      let has_loop_param = node.has_option("loop")
      let loop_param = if has_loop_param { "&amp;loop=1" } else { "" }
      let mute_param = if node.has_option("muted") { "&amp;mute=1" } else { "" }
      let controls_param = if node.has_option("nocontrols") {
        "&amp;controls=0"
      } else {
        ""
      }
      let (fs_param, fs_attribute) = if node.has_option("nofullscreen") {
        ("&amp;fs=0", "")
      } else {
        ("", self.append_boolean_attribute("allowfullscreen", xml))
      }
      let modest_param = if node.has_option("modest") {
        "&amp;modestbranding=1"
      } else {
        ""
      }
      let theme_param = if node.has_attr("theme") {
        "&amp;theme=\{a(node, "theme")}"
      } else {
        ""
      }
      let hl_param = if node.has_attr("lang") {
        "&amp;hl=\{a(node, "lang")}"
      } else {
        ""
      }
      let parts = @rb.split(a(node, "target"), "/", limit=2)
      let mut target = parts.get(0).unwrap_or("")
      let list = match parts.get(1) {
        Some(l) => Some(l)
        None => node.attr("list")
      }
      let list_param = match list {
        Some(l) => "&amp;list=\{l}"
        None => {
          let parts2 = @rb.split(target, ",", limit=2)
          target = parts2.get(0).unwrap_or("")
          let playlist = match parts2.get(1) {
            Some(p) => Some(p)
            None => node.attr("playlist")
          }
          match playlist {
            Some(p) => "&amp;playlist=\{target},\{p}"
            None => if has_loop_param { "&amp;playlist=\{target}" } else { "" }
          }
        }
      }
      "\{head}<iframe\{width_attribute}\{height_attribute} src=\"\{scheme}//www.youtube.com/embed/\{target}?rel=\{rel_param_val}\{start_param}\{end_param}\{autoplay_param}\{loop_param}\{mute_param}\{controls_param}\{list_param}\{fs_param}\{modest_param}\{theme_param}\{hl_param}\" frameborder=\"0\"\{fs_attribute}></iframe>\n</div>\n</div>"
    }
    Some("wistia") => {
      let scheme = asset_scheme()
      let delimiter = ["?"]
      let next_delim = fn() { delimiter.pop().unwrap_or("&amp;") }
      let start_anchor = if node.has_attr("start") {
        "\{next_delim()}time=\{a(node, "start")}"
      } else {
        ""
      }
      let end_video_behavior_param = if node.has_option("loop") {
        "\{next_delim()}endVideoBehavior=loop"
      } else if node.has_option("reset") {
        "\{next_delim()}endVideoBehavior=reset"
      } else {
        ""
      }
      let target = a(node, "target")
      let autoplay_param = if node.has_option("autoplay") {
        "\{next_delim()}autoPlay=true"
      } else {
        ""
      }
      let muted_param = if node.has_option("muted") {
        "\{next_delim()}muted=true"
      } else {
        ""
      }
      "\{head}<iframe\{width_attribute}\{height_attribute} src=\"\{scheme}//fast.wistia.com/embed/iframe/\{target}\{start_anchor}\{autoplay_param}\{end_video_behavior_param}\{muted_param}\" frameborder=\"0\"\{fullscreen} class=\"wistia_embed\" name=\"wistia_embed\"></iframe>\n</div>\n</div>"
    }
    _ => {
      let poster_attribute = match node.attr("poster") {
        Some(v) if v != "" => " poster=\"\{node.media_uri(v)}\""
        _ => ""
      }
      let preload_attribute = match node.attr("preload") {
        Some(v) if v != "" => " preload=\"\{v}\""
        _ => ""
      }
      let start_t = node.attr("start")
      let end_t = node.attr("end")
      let time_anchor = if start_t is Some(_) || end_t is Some(_) {
        "#t=\{start_t.unwrap_or("")}\{match end_t { Some(e) => ",\{e}"; None => "" }}"
      } else {
        ""
      }
      let controls = if node.has_option("nocontrols") {
        ""
      } else {
        self.append_boolean_attribute("controls", xml)
      }
      "\{head}<video src=\"\{node.media_uri(a(node, "target"))}\{time_anchor}\"\{width_attribute}\{height_attribute}\{poster_attribute}\{bool_attr("autoplay", "autoplay")}\{bool_attr("muted", "muted")}\{controls}\{bool_attr("loop", "loop")}\{preload_attribute}>\nYour browser does not support the video tag.\n</video>\n</div>\n</div>"
    }
  }
}
