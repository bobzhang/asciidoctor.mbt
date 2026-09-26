///|
fn ManPageConverter::convert_section(
  self : ManPageConverter,
  node : @core.Node,
) -> String {
  ignore(self)
  let (macro_, stitle) = if node.level > 1 {
    // QUESTION why captioned title? why not when level == 1?
    ("SS", node.captioned_title())
  } else {
    ("SH", uppercase_pcdata(title_s(node)))
  }
  ".\{macro_} \"\{manify(stitle)}\"\n\{node.content()}"
}

///|
fn ManPageConverter::convert_admonition(
  self : ManPageConverter,
  node : @core.Node,
) -> String {
  ignore(self)
  let title = if node.has_title() {
    "\\fP: \{manify(title_s(node))}"
  } else {
    ""
  }
  ".if n .sp\n.RS 4\n.it 1 an-trap\n.nr an-no-space-flag 1\n.nr an-break-flag 1\n.br\n.ps +1\n.B \{a(node, "textlabel")}\{title}\n.ps -1\n.br\n\{enclose_content(node)}\n.sp .5v\n.RE"
}

///|
fn ManPageConverter::convert_colist(
  self : ManPageConverter,
  node : @core.Node,
) -> String {
  ignore(self)
  let result = []
  if node.has_title() {
    result.push(bold_title(title_s(node)))
  }
  result.push(".TS\ntab(:);\nr lw(\\n(.lu*75u/100u).")
  let mut num = 0
  for item in node.items() {
    num += 1
    result.push("\\fB(\{num})\\fP\\h'-2n':T{")
    result.push(manify(item.text().unwrap_or(""), whitespace=Normalize))
    if item.has_blocks() {
      result.push(item.content())
    }
    result.push("T}")
  }
  result.push(".TE")
  result.join("\n")
}

///|
fn ManPageConverter::convert_dlist(
  self : ManPageConverter,
  node : @core.Node,
) -> String {
  ignore(self)
  let result = []
  if node.has_title() {
    result.push(bold_title(title_s(node)))
  }
  let mut counter = 0
  for item in node.dlist_items {
    counter += 1
    let terms = item.terms.map(dt => dt.text().unwrap_or(""))
    if node.style == Some("qanda") {
      result.push(".sp\n\{counter}. \{manify(terms.join(" "))}\n.RS 4")
    } else {
      result.push(
        ".sp\n\{manify(terms.join(", "), whitespace=Normalize)}\n.RS 4",
      )
    }
    match item.desc {
      Some(dd) => {
        let has_text = dd.has_text()
        if has_text {
          result.push(manify(dd.text().unwrap_or(""), whitespace=Normalize))
        }
        if dd.has_blocks() {
          let mut dd_content = dd.content()
          if !has_text && dd_content.has_prefix(".sp\n") {
            dd_content = @rb.from(dd_content, 4)
          }
          result.push(dd_content)
        }
      }
      None => ()
    }
    result.push(".RE")
  }
  result.join("\n")
}

///|
fn ManPageConverter::convert_example(
  self : ManPageConverter,
  node : @core.Node,
) -> String {
  ignore(self)
  let head = if node.has_title() {
    bold_title(node.captioned_title())
  } else {
    ".sp"
  }
  "\{head}\n.RS 4\n\{enclose_content(node)}\n.RE"
}

///|
fn ManPageConverter::convert_floating_title(
  self : ManPageConverter,
  node : @core.Node,
) -> String {
  ignore(self)
  ".SS \"\{manify(title_s(node))}\""
}

///|
fn ManPageConverter::convert_image(
  self : ManPageConverter,
  node : @core.Node,
) -> String {
  ignore(self)
  let head = if node.has_title() {
    bold_title(node.captioned_title())
  } else {
    ".sp"
  }
  "\{head}\n[\{manify(node.alt())}]"
}

///|
fn verbatim_body(node : @core.Node) -> String {
  ".sp\n.if n .RS 4\n.nf\n.fam C\n\{manify(node.content(), whitespace=Preserve)}\n.fam\n.fi\n.if n .RE"
}

///|
fn ManPageConverter::convert_listing(
  self : ManPageConverter,
  node : @core.Node,
) -> String {
  ignore(self)
  let result = []
  if node.has_title() {
    result.push(bold_title(node.captioned_title()))
  }
  result.push(verbatim_body(node))
  result.join("\n")
}

///|
fn ManPageConverter::convert_literal(
  self : ManPageConverter,
  node : @core.Node,
) -> String {
  ignore(self)
  let result = []
  if node.has_title() {
    result.push(bold_title(title_s(node)))
  }
  result.push(verbatim_body(node))
  result.join("\n")
}

///|
fn ManPageConverter::convert_sidebar(
  self : ManPageConverter,
  node : @core.Node,
) -> String {
  ignore(self)
  let head = if node.has_title() { bold_title(title_s(node)) } else { ".sp" }
  "\{head}\n.RS 4\n\{enclose_content(node)}\n.RE"
}

///|
/// Appends the content of a list item, dropping the leading `.sp` when the
/// item has no principal text.
fn push_item_content(
  result : Array[String],
  item : @core.Node,
  list_text : String,
) -> Unit {
  if item.has_blocks() {
    let mut item_content = item.content()
    if list_text == "" && item_content.has_prefix(".sp\n") {
      item_content = @rb.from(item_content, 4)
    }
    result.push(item_content)
  }
}

///|
fn ManPageConverter::convert_olist(
  self : ManPageConverter,
  node : @core.Node,
) -> String {
  ignore(self)
  let result = []
  if node.has_title() {
    result.push(bold_title(title_s(node)))
  }
  let start = @rb.to_i(node.attr("start", default="1").unwrap_or("1"))
  for idx, item in node.items() {
    let numeral = idx + start
    let list_text = manify(item.text().unwrap_or(""), whitespace=Normalize)
    let text_s = if list_text == "" { "" } else { "\n" + list_text }
    result.push(
      ".sp\n.RS 4\n.ie n \\{\\\n\\h'-04' \{numeral}.\\h'+01'\\c\n.\\}\n.el \\{\\\n.  sp -1\n.  IP \" \{numeral}.\" 4.2\n.\\}\{text_s}",
    )
    push_item_content(result, item, list_text)
    result.push(".RE")
  }
  result.join("\n")
}

///|
fn ManPageConverter::convert_open(
  self : ManPageConverter,
  node : @core.Node,
) -> String {
  ignore(self)
  match node.style {
    Some("abstract") | Some("partintro") => enclose_content(node)
    _ => node.content()
  }
}

///|
fn ManPageConverter::convert_paragraph(
  self : ManPageConverter,
  node : @core.Node,
) -> String {
  ignore(self)
  if node.has_title() {
    ".sp\n.B \{manify(title_s(node))}\n.br\n\{manify(node.content(), whitespace=Normalize)}"
  } else {
    ".sp\n\{manify(node.content(), whitespace=Normalize)}"
  }
}

///|
fn attribution_line(node : @core.Node) -> String? {
  let citetitle = if node.has_attr("citetitle") {
    "\{a(node, "citetitle")} "
  } else {
    ""
  }
  if node.has_attr("attribution") {
    Some("\{citetitle}\\(em \{a(node, "attribution")}")
  } else {
    None
  }
}

///|
fn ManPageConverter::convert_quote(
  self : ManPageConverter,
  node : @core.Node,
) -> String {
  ignore(self)
  let result = []
  if node.has_title() {
    result.push(".sp\n.RS 3\n.B \{manify(title_s(node))}\n.br\n.RE")
  }
  let attribution = attribution_line(node)
  result.push(".RS 3\n.ll -.6i\n\{enclose_content(node)}\n.br\n.RE\n.ll")
  match attribution {
    Some(line) => result.push(".RS 5\n.ll -.10i\n\{line}\n.RE\n.ll")
    None => ()
  }
  result.join("\n")
}

///|
fn ManPageConverter::convert_stem(
  self : ManPageConverter,
  node : @core.Node,
) -> String {
  ignore(self)
  let result = []
  result.push(if node.has_title() { bold_title(title_s(node)) } else { ".sp" })
  let style = node.style.unwrap_or("")
  let (open, close) = if style == "latexmath" {
    ("\\[", "\\]")
  } else {
    ("\\$", "\\$")
  }
  let mut equation = node.content()
  if equation.has_prefix(open) && equation.has_suffix(close) {
    equation = @rb.slice(
      equation,
      open.length(),
      equation.length() - close.length(),
    )
  }
  result.push("\{manify(equation, whitespace=Preserve)} (\{style})")
  result.join("\n")
}

///|
fn ManPageConverter::convert_ulist(
  self : ManPageConverter,
  node : @core.Node,
) -> String {
  ignore(self)
  let result = []
  if node.has_title() {
    result.push(bold_title(title_s(node)))
  }
  for item in node.items() {
    let list_text = manify(item.text().unwrap_or(""), whitespace=Normalize)
    let text_s = if list_text == "" { "" } else { "\n" + list_text }
    result.push(
      ".sp\n.RS 4\n.ie n \\{\\\n\\h'-04'\\(bu\\h'+03'\\c\n.\\}\n.el \\{\\\n.  sp -1\n.  IP \\(bu 2.3\n.\\}\{text_s}",
    )
    push_item_content(result, item, list_text)
    result.push(".RE")
  }
  result.join("\n")
}

///|
fn ManPageConverter::convert_verse(
  self : ManPageConverter,
  node : @core.Node,
) -> String {
  ignore(self)
  let result = []
  if node.has_title() {
    result.push(bold_title(title_s(node)))
  }
  let attribution = attribution_line(node)
  result.push(
    ".sp\n.nf\n\{manify(node.content(), whitespace=Preserve)}\n.fi\n.br",
  )
  match attribution {
    Some(line) => result.push(".in +.5i\n.ll -.5i\n\{line}\n.in\n.ll")
    None => ()
  }
  result.join("\n")
}

///|
fn ManPageConverter::convert_video(
  self : ManPageConverter,
  node : @core.Node,
) -> String {
  ignore(self)
  let start_param = if node.has_attr("start") {
    "&start=\{a(node, "start")}"
  } else {
    ""
  }
  let end_param = if node.has_attr("end") {
    "&end=\{a(node, "end")}"
  } else {
    ""
  }
  let head = if node.has_title() { bold_title(title_s(node)) } else { ".sp" }
  "\{head}\n<\{node.media_uri(a(node, "target"))}\{start_param}\{end_param}> (video)"
}
