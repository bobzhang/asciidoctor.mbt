///|
fn footnotes_html(
  node : @core.Node,
  max_width_attr : String,
  slash : String,
) -> Array[String] {
  let result = []
  result.push("<div id=\"footnotes\"\{max_width_attr}>\n<hr\{slash}>")
  for footnote in node.footnotes() {
    result.push(
      "<div class=\"footnote\" id=\"_footnotedef_\{footnote.index}\">\n<a href=\"#_footnoteref_\{footnote.index}\">\{footnote.index}</a>. \{footnote.text}\n</div>",
    )
  }
  result.push("</div>")
  result
}

///|
fn Html5Converter::convert_document(
  self : Html5Converter,
  node : @core.Node,
) -> String {
  let slash = self.void_element_slash
  let br = "<br\{slash}>"
  let mut asset_uri_scheme = node
    .attr("asset-uri-scheme", default="https")
    .unwrap_or("https")
  if asset_uri_scheme != "" {
    asset_uri_scheme = "\{asset_uri_scheme}:"
  }
  let cdn_base_url = "\{asset_uri_scheme}//cdnjs.cloudflare.com/ajax/libs"
  let linkcss = node.has_attr("linkcss")
  let max_width_attr = if node.has_attr("max-width") {
    " style=\"max-width: \{a(node, "max-width")};\""
  } else {
    ""
  }
  let result : Array[String] = ["<!DOCTYPE html>"]
  let lang_attribute = if node.has_attr("nolang") {
    ""
  } else {
    " lang=\"\{node.attr("lang", default="en").unwrap_or("en")}\""
  }
  result.push(
    "<html\{if self.xml_mode { " xmlns=\"http://www.w3.org/1999/xhtml\"" } else { "" }}\{lang_attribute}>",
  )
  result.push(
    "<head>\n<meta charset=\"\{node.attr("encoding", default="UTF-8").unwrap_or("UTF-8")}\"\{slash}>\n<meta http-equiv=\"X-UA-Compatible\" content=\"IE=edge\"\{slash}>\n<meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\"\{slash}>",
  )
  let reproducible = node.has_attr("reproducible")
  if !reproducible {
    result.push(
      "<meta name=\"generator\" content=\"Asciidoctor \{a(node, "asciidoctor-version")}\"\{slash}>",
    )
  }
  if node.has_attr("app-name") {
    result.push(
      "<meta name=\"application-name\" content=\"\{a(node, "app-name")}\"\{slash}>",
    )
  }
  if node.has_attr("description") {
    result.push(
      "<meta name=\"description\" content=\"\{a(node, "description")}\"\{slash}>",
    )
  }
  if node.has_attr("keywords") {
    result.push(
      "<meta name=\"keywords\" content=\"\{a(node, "keywords")}\"\{slash}>",
    )
  }
  if node.has_attr("authors") {
    let authors = node.sub_replacements(a(node, "authors"))
    let authors = if authors.contains("<") {
      xml_sanitize_rx.gsub(authors, "")
    } else {
      authors
    }
    result.push("<meta name=\"author\" content=\"\{authors}\"\{slash}>")
  }
  if node.has_attr("copyright") {
    result.push(
      "<meta name=\"copyright\" content=\"\{a(node, "copyright")}\"\{slash}>",
    )
  }
  if node.has_attr("favicon") {
    let mut icon_href = a(node, "favicon")
    let mut icon_type = "image/x-icon"
    if icon_href == "" {
      icon_href = "favicon.ico"
    } else {
      let ext = @core.extname(icon_href, fallback="")
      if ext != "" {
        icon_type = if ext == ".ico" {
          "image/x-icon"
        } else {
          "image/\{@rb.from(ext, 1)}"
        }
      }
    }
    result.push(
      "<link rel=\"icon\" type=\"\{icon_type}\" href=\"\{icon_href}\"\{slash}>",
    )
  }
  result.push(
    "<title>\{node.doctitle(sanitize=true, use_fallback=true).unwrap_or("")}</title>",
  )
  let stylesheet = node.attr("stylesheet")
  if stylesheet == Some("") || stylesheet == Some("DEFAULT") {
    match node.attr("webfonts") {
      Some(webfonts) =>
        result.push(
          "<link rel=\"stylesheet\" href=\"\{asset_uri_scheme}//fonts.googleapis.com/css?family=\{if webfonts == "" { "Open+Sans:300,300italic,400,400italic,600,600italic%7CNoto+Serif:400,400italic,700,700italic%7CNoto+Sans+Mono:400,700" } else { webfonts }}\"\{slash}>",
        )
      None => ()
    }
    if linkcss {
      result.push(
        "<link rel=\"stylesheet\" href=\"\{node.normalize_web_path("asciidoctor.css", start?=node.attr("stylesdir"), preserve_uri_target=false)}\"\{slash}>",
      )
    } else {
      result.push("<style>\n\{@core.primary_stylesheet_data}\n</style>")
    }
  } else if node.has_attr("stylesheet") {
    if linkcss {
      result.push(
        "<link rel=\"stylesheet\" href=\"\{node.normalize_web_path(a(node, "stylesheet"), start?=node.attr("stylesdir"))}\"\{slash}>",
      )
    } else {
      let data = node
        .read_contents(
          a(node, "stylesheet"),
          start?=node.attr("stylesdir"),
          warn_on_failure=true,
          label="stylesheet",
        )
        .unwrap_or("")
      result.push("<style>\n\{data}\n</style>")
    }
  }
  if node.has_attr("icons", expected="font") {
    if node.has_attr("iconfont-remote") {
      result.push(
        "<link rel=\"stylesheet\" href=\"\{node.attr("iconfont-cdn", default="\{cdn_base_url}/font-awesome/4.7.0/css/font-awesome.min.css").unwrap_or("")}\"\{slash}>",
      )
    } else {
      let iconfont_stylesheet = "\{node.attr("iconfont-name", default="font-awesome").unwrap_or("font-awesome")}.css"
      result.push(
        "<link rel=\"stylesheet\" href=\"\{node.normalize_web_path(iconfont_stylesheet, start?=node.attr("stylesdir"), preserve_uri_target=false)}\"\{slash}>",
      )
    }
  }
  let syntax_hl = node.syntax_highlighter()
  let mut syntax_hl_docinfo_head_idx = -1
  if syntax_hl is Some(_) {
    syntax_hl_docinfo_head_idx = result.length()
    result.push("")
  }
  let docinfo_head = node.docinfo()
  if docinfo_head != "" {
    result.push(docinfo_head)
  }
  result.push("</head>")
  let id_attr_s = id_attr(node)
  let sectioned = node.has_sections()
  let classes = if sectioned &&
    node.has_attr("toc-class") &&
    node.has_attr("toc") &&
    node.has_attr("toc-placement", expected="auto") {
    [
      node.doctype(),
      a(node, "toc-class"),
      "toc-\{node.attr("toc-position", default="header").unwrap_or("header")}",
    ]
  } else {
    [node.doctype()]
  }
  match node.role() {
    Some(r) if node.role_is() => classes.push(r)
    _ => ()
  }
  result.push("<body\{id_attr_s} class=\"\{classes.join(" ")}\">")
  let docinfo_header = node.docinfo(location="header")
  if docinfo_header != "" {
    result.push(docinfo_header)
  }
  if !node.noheader() {
    result.push("<div id=\"header\"\{max_width_attr}>")
    if node.doctype() == "manpage" {
      result.push("<h1>\{node.doctitle().unwrap_or("")} Manual Page</h1>")
      if sectioned &&
        node.has_attr("toc") &&
        node.has_attr("toc-placement", expected="auto") {
        result.push(
          "<div id=\"toc\" class=\"\{node.attr("toc-class", default="toc").unwrap_or("toc")}\">\n<div id=\"toctitle\">\{a(node, "toc-title")}</div>\n\{self.convert_outline(node).unwrap_or("")}\n</div>",
        )
      }
      if node.has_attr("manpurpose") {
        result.push(self.generate_manname_section(node))
      }
    } else {
      match node.header() {
        Some(header) => {
          if !node.notitle() {
            result.push("<h1>\{header.title().unwrap_or("")}</h1>")
          }
          let details = []
          let mut idx = 1
          for author in node.authors() {
            let suffix = if idx > 1 { idx.to_string() } else { "" }
            details.push(
              "<span id=\"author\{suffix}\" class=\"author\">\{node.sub_replacements(author.name.unwrap_or(""))}</span>\{br}",
            )
            match author.email {
              Some(email) =>
                details.push(
                  "<span id=\"email\{suffix}\" class=\"email\">\{node.sub_macros(email)}</span>\{br}",
                )
              None => ()
            }
            idx += 1
          }
          if node.has_attr("revnumber") {
            details.push(
              "<span id=\"revnumber\">\{@rb.downcase(node.attr("version-label").unwrap_or(""))} \{a(node, "revnumber")}\{if node.has_attr("revdate") { "," } else { "" }}</span>",
            )
          }
          if node.has_attr("revdate") {
            details.push("<span id=\"revdate\">\{a(node, "revdate")}</span>")
          }
          if node.has_attr("revremark") {
            details.push(
              "\{br}<span id=\"revremark\">\{a(node, "revremark")}</span>",
            )
          }
          if !details.is_empty() {
            result.push("<div class=\"details\">")
            for d in details {
              result.push(d)
            }
            result.push("</div>")
          }
        }
        None => ()
      }
      if sectioned &&
        node.has_attr("toc") &&
        node.has_attr("toc-placement", expected="auto") {
        result.push(
          "<div id=\"toc\" class=\"\{node.attr("toc-class", default="toc").unwrap_or("toc")}\">\n<div id=\"toctitle\">\{a(node, "toc-title")}</div>\n\{self.convert_outline(node).unwrap_or("")}\n</div>",
        )
      }
    }
    result.push("</div>")
  }
  result.push(
    "<div id=\"content\"\{max_width_attr}>\n\{node.content()}\n</div>",
  )
  if node.has_footnotes() && !node.has_attr("nofootnotes") {
    for l in footnotes_html(node, max_width_attr, slash) {
      result.push(l)
    }
  }
  if !node.nofooter() {
    result.push("<div id=\"footer\"\{max_width_attr}>")
    result.push("<div id=\"footer-text\">")
    if node.has_attr("revnumber") {
      result.push("\{a(node, "version-label")} \{a(node, "revnumber")}\{br}")
    }
    if node.has_attr("last-update-label") && !reproducible {
      result.push("\{a(node, "last-update-label")} \{a(node, "docdatetime")}")
    }
    result.push("</div>")
    result.push("</div>")
  }
  match syntax_hl {
    Some(hl) => {
      let opts = @core.DocinfoOptions::new(
        linkcss~,
        cdn_base_url~,
        self_closing_tag_slash=slash,
      )
      if hl.has_docinfo("head") {
        result[syntax_hl_docinfo_head_idx] = hl.docinfo("head", node, opts)
      } else {
        result.remove(syntax_hl_docinfo_head_idx) |> ignore
      }
      if hl.has_docinfo("footer") {
        result.push(hl.docinfo("footer", node, opts))
      }
    }
    None => ()
  }
  if node.has_attr("stem") {
    let mut eqnums_val = node.attr("eqnums", default="none").unwrap_or("none")
    if eqnums_val == "" {
      eqnums_val = "AMS"
    }
    let eqnums_opt = " equationNumbers: { autoNumber: \"\{eqnums_val}\" } "
    let latexmath_inline = "[\"\\\\(\", \"\\\\)\"]"
    let latexmath_block = "[\"\\\\[\", \"\\\\]\"]"
    let asciimath_block = "[\"\\\\$\", \"\\\\$\"]"
    result.push(
      (
        $|<script type="text/x-mathjax-config">
        $|MathJax.Hub.Config({
        $|  messageStyle: "none",
        $|  tex2jax: {
        $|    inlineMath: [\{latexmath_inline}],
        $|    displayMath: [\{latexmath_block}],
        $|    ignoreClass: "nostem|nolatexmath"
        $|  },
        $|  asciimath2jax: {
        $|    delimiters: [\{asciimath_block}],
        $|    ignoreClass: "nostem|noasciimath"
        $|  },
        $|  TeX: {\{eqnums_opt}}
        $|})
        $|MathJax.Hub.Register.StartupHook("AsciiMath Jax Ready", function () {
        $|  MathJax.InputJax.AsciiMath.postfilterHooks.Add(function (data, node) {
        $|    if ((node = data.script.parentNode) && (node = node.parentNode) && node.classList.contains("stemblock")) {
        $|      data.math.root.display = "block"
        $|    }
        $|    return data
        $|  })
        $|})
        $|</script>
        $|<script src="\{cdn_base_url}/mathjax/2.7.9/MathJax.js?config=TeX-MML-AM_CHTML"></script>
      ),
    )
  }
  let docinfo_footer = node.docinfo(location="footer")
  if docinfo_footer != "" {
    result.push(docinfo_footer)
  }
  result.push("</body>")
  result.push("</html>")
  result.join("\n")
}

///|
fn Html5Converter::convert_embedded(
  self : Html5Converter,
  node : @core.Node,
) -> String {
  let result = []
  if node.doctype() == "manpage" {
    if !node.notitle() {
      result.push(
        "<h1\{id_attr(node)}>\{node.doctitle().unwrap_or("")} Manual Page</h1>",
      )
    }
    if node.has_attr("manpurpose") {
      result.push(self.generate_manname_section(node))
    }
  } else {
    match node.header() {
      Some(header) if !node.notitle() =>
        result.push("<h1\{id_attr(node)}>\{header.title().unwrap_or("")}</h1>")
      _ => ()
    }
  }
  if node.has_sections() && node.has_attr("toc") {
    let toc_p = node.attr("toc-placement")
    if toc_p != Some("macro") && toc_p != Some("preamble") {
      result.push(
        "<div id=\"toc\" class=\"toc\">\n<div id=\"toctitle\">\{a(node, "toc-title")}</div>\n\{self.convert_outline(node).unwrap_or("")}\n</div>",
      )
    }
  }
  result.push(node.content())
  if node.has_footnotes() && !node.has_attr("nofootnotes") {
    for l in footnotes_html(node, "", self.void_element_slash) {
      result.push(l)
    }
  }
  result.join("\n")
}

///|
fn section_title_text(node : @core.Node, section : @core.Node) -> String {
  let doc = node.document()
  let level = section.level
  let sectnumlevels = doc.attributes
    .get("sectnumlevels")
    .map(v => v.to_i())
    .unwrap_or(3)
  if section.caption() is Some(_) {
    section.captioned_title()
  } else if section.numbered != NotNumbered && level <= sectnumlevels {
    let title = section.title().unwrap_or("")
    if level < 2 && doc.doctype() == "book" {
      match section.sectname {
        Some("chapter") => {
          let sig = match doc.attributes.str("chapter-signifier") {
            Some(s) => "\{s} "
            None => ""
          }
          "\{sig}\{section.sectnum()} \{title}"
        }
        Some("part") => {
          let sig = match doc.attributes.str("part-signifier") {
            Some(s) => "\{s} "
            None => ""
          }
          "\{sig}\{section.sectnum(append=Some(":"))} \{title}"
        }
        _ => "\{section.sectnum()} \{title}"
      }
    } else {
      "\{section.sectnum()} \{title}"
    }
  } else {
    section.title().unwrap_or("")
  }
}

///|
fn Html5Converter::convert_outline(
  self : Html5Converter,
  node : @core.Node,
  toclevels? : Int,
  sectnumlevels? : Int,
) -> String? {
  if !node.has_sections() {
    return None
  }
  let sections = node.sections()
  let parts = node.context == Document && node.is_multipart()
  let sectlevel = if parts { 0 } else { sections[0].level }
  let doc = node.document()
  let sectnumlevels = match sectnumlevels {
    Some(s) => s
    None => doc.attributes.get("sectnumlevels").map(v => v.to_i()).unwrap_or(3)
  }
  let toclevels = match toclevels {
    Some(t) => t
    None =>
      match doc.attributes.get("toclevels") {
        Some(v) => {
          let t = v.to_i()
          if t < 1 && !parts {
            1
          } else {
            t
          }
        }
        None => 2
      }
  }
  let result = ["<ul class=\"sectlevel\{sectlevel}\">"]
  for section in sections {
    let slevel = section.level
    let stoclevels = if section.has_attr("toclevels") {
      @rb.to_i(a(section, "toclevels"))
    } else {
      toclevels
    }
    if slevel > stoclevels {
      continue
    }
    let mut stitle = if section.caption() is Some(_) {
      section.captioned_title()
    } else if section.numbered != NotNumbered && slevel <= sectnumlevels {
      section_title_text(node, section)
    } else {
      section.title().unwrap_or("")
    }
    if stitle.contains("<a") {
      stitle = drop_anchor_rx.gsub(stitle, "")
    }
    let otag = if slevel == sectlevel {
      "<li>"
    } else {
      "<li class=\"sectlevel\{slevel}\">"
    }
    let sid = section.id.unwrap_or("")
    let child = if slevel < stoclevels {
      self.convert_outline(section, toclevels=stoclevels, sectnumlevels~)
    } else {
      None
    }
    match child {
      Some(child_toc) => {
        result.push("\{otag}<a href=\"#\{sid}\">\{stitle}</a>")
        result.push(child_toc)
        result.push("</li>")
      }
      None => result.push("\{otag}<a href=\"#\{sid}\">\{stitle}</a></li>")
    }
  }
  result.push("</ul>")
  Some(result.join("\n"))
}

///|
fn Html5Converter::convert_section(
  self : Html5Converter,
  node : @core.Node,
) -> String {
  ignore(self)
  let doc_attrs = node.document().attributes
  let level = node.level
  let mut title = section_title_text(node, node)
  let id_attr_s = match node.id {
    Some(id) => {
      if doc_attrs.truthy("sectlinks") {
        match
          (if title.has_prefix("<a ") {
            leading_anchors_rx.find(title)
          } else {
            None
          }) {
          Some(m) =>
            title = "\{m.matched()}<a class=\"link\" href=\"#\{id}\">\{@rb.from(title, m.matched().length())}</a>"
          None => title = "<a class=\"link\" href=\"#\{id}\">\{title}</a>"
        }
      }
      if doc_attrs.truthy("sectanchors") {
        if doc_attrs.str("sectanchors") == Some("after") {
          title = "\{title}<a class=\"anchor\" href=\"#\{id}\"></a>"
        } else {
          title = "<a class=\"anchor\" href=\"#\{id}\"></a>\{title}"
        }
      }
      " id=\"\{id}\""
    }
    None => ""
  }
  if level == 0 {
    "<h1\{id_attr_s} class=\"sect0\{role_suffix(node)}\">\{title}</h1>\n\{node.content()}"
  } else {
    let body = if level == 1 {
      "<div class=\"sectionbody\">\n\{node.content()}\n</div>"
    } else {
      node.content()
    }
    "<div class=\"sect\{level}\{role_suffix(node)}\">\n<h\{level + 1}\{id_attr_s}>\{title}</h\{level + 1}>\n\{body}\n</div>"
  }
}

///|
fn Html5Converter::convert_preamble(
  self : Html5Converter,
  node : @core.Node,
) -> String {
  let doc = node.document()
  let toc = if doc.has_attr("toc-placement", expected="preamble") &&
    doc.has_sections() &&
    doc.has_attr("toc") {
    "\n<div id=\"toc\" class=\"\{doc.attr("toc-class", default="toc").unwrap_or("toc")}\">\n<div id=\"toctitle\">\{a(doc, "toc-title")}</div>\n\{self.convert_outline(doc).unwrap_or("")}\n</div>"
  } else {
    ""
  }
  "<div id=\"preamble\">\n<div class=\"sectionbody\">\n\{node.content()}\n</div>\{toc}\n</div>"
}

///|
fn Html5Converter::convert_toc(
  self : Html5Converter,
  node : @core.Node,
) -> String {
  let doc = node.document()
  if !(doc.has_attr("toc-placement", expected="macro") &&
    doc.has_sections() &&
    doc.has_attr("toc")) {
    return "<!-- toc disabled -->"
  }
  let (id_attr_s, title_id_attr) = match node.id {
    Some(id) => (" id=\"\{id}\"", " id=\"\{id}title\"")
    None => (" id=\"toc\"", " id=\"toctitle\"")
  }
  let title = if node.has_title() {
    node.title().unwrap_or("")
  } else {
    a(doc, "toc-title")
  }
  let levels = if node.has_attr("levels") {
    Some(@rb.to_i(a(node, "levels")))
  } else {
    None
  }
  let role = if node.role_is() {
    node.role().unwrap_or("")
  } else {
    doc.attr("toc-class", default="toc").unwrap_or("toc")
  }
  "<div\{id_attr_s} class=\"\{role}\">\n<div\{title_id_attr} class=\"title\">\{title}</div>\n\{self.convert_outline(doc, toclevels?=levels).unwrap_or("")}\n</div>"
}
