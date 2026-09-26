///|
let copyright_rx : @regex.Regex = @regex.re("^(.+?)(?: ((?:\\d{4}-)?\\d{4}))?$")

///|
let image_macro_rx : @regex.Regex = @regex.re(
  "^image::?(\\S|\\S.*?\\S)\\[(.+)?\\]$",
)

///|
/// Converts the blocks of a document, omitting blocks whose handler is
/// `skip` (Ruby returns nil for those and the result is compacted).
fn convert_top_blocks(node : @core.Node) -> String {
  node.blocks
  .filter(b => !(b.context is (Audio | Video | Toc)))
  .map(b => b.convert())
  .join("\n")
}

///|
fn DocBook5Converter::convert_document(
  self : DocBook5Converter,
  node : @core.Node,
) -> String {
  let result = ["<?xml version=\"1.0\" encoding=\"UTF-8\"?>"]
  if node.has_attr("toc") {
    result.push(
      if node.has_attr("toclevels") {
        "<?asciidoc-toc maxdepth=\"\{a(node, "toclevels")}\"?>"
      } else {
        "<?asciidoc-toc?>"
      },
    )
  }
  if node.has_attr("sectnums") {
    result.push(
      if node.has_attr("sectnumlevels") {
        "<?asciidoc-numbered maxdepth=\"\{a(node, "sectnumlevels")}\"?>"
      } else {
        "<?asciidoc-numbered?>"
      },
    )
  }
  let lang_attribute = if node.has_attr("nolang") {
    ""
  } else {
    " xml:lang=\"\{node.attr("lang", default="en").unwrap_or("en")}\""
  }
  let mut root_tag_name = node.doctype()
  let manpage = root_tag_name == "manpage"
  if manpage {
    root_tag_name = "article"
  }
  let root_tag_idx = result.length()
  let id = node.id
  let abstract_block = find_root_abstract(node)
  if !node.noheader() {
    result.push(self.document_info_tag(node, abstract_block))
  }
  if manpage {
    result.push("<refentry>")
    result.push("<refmeta>")
    if node.has_attr("mantitle") {
      result.push(
        "<refentrytitle>\{node.apply_reftext_subs(a(node, "mantitle"))}</refentrytitle>",
      )
    }
    if node.has_attr("manvolnum") {
      result.push("<manvolnum>\{a(node, "manvolnum")}</manvolnum>")
    }
    result.push(
      "<refmiscinfo class=\"source\">\{node.attr("mansource", default="&#160;").unwrap_or("&#160;")}</refmiscinfo>",
    )
    result.push(
      "<refmiscinfo class=\"manual\">\{node.attr("manmanual", default="&#160;").unwrap_or("&#160;")}</refmiscinfo>",
    )
    result.push("</refmeta>")
    result.push("<refnamediv>")
    if node.has_attr("mannames") {
      for n in list_attr(node, "mannames") {
        result.push("<refname>\{n}</refname>")
      }
    }
    if node.has_attr("manpurpose") {
      result.push("<refpurpose>\{a(node, "manpurpose")}</refpurpose>")
    }
    result.push("</refnamediv>")
  }
  let docinfo_header = node.docinfo(location="header")
  if docinfo_header != "" {
    result.push(docinfo_header)
  }
  let extracted = match abstract_block {
    Some(abs) => extract_abstract(node, abs)
    None => None
  }
  if node.has_blocks() {
    result.push(convert_top_blocks(node))
  }
  match extracted {
    Some(e) => restore_abstract(e)
    None => ()
  }
  let docinfo_footer = node.docinfo(location="footer")
  if docinfo_footer != "" {
    result.push(docinfo_footer)
  }
  if manpage {
    result.push("</refentry>")
  }
  // defer adding root tag in case document ID is auto-generated on demand
  let id = match id {
    Some(_) => id
    None => {
      let generated = node.id
      node.set_id(None)
      generated
    }
  }
  result.insert(
    root_tag_idx,
    "<\{root_tag_name} xmlns=\"http://docbook.org/ns/docbook\" xmlns:xl=\"http://www.w3.org/1999/xlink\" version=\"5.0\"\{lang_attribute}\{common_attributes(id)}>",
  )
  result.push("</\{root_tag_name}>")
  result.join("\n")
}

///|
fn DocBook5Converter::convert_embedded(
  self : DocBook5Converter,
  node : @core.Node,
) -> String {
  // NOTE in DocBook 5, the root abstract must be in the info tag and is thus not part of the body
  let extracted = if self.backend == "docbook5" {
    match find_root_abstract(node) {
      Some(abs) => extract_abstract(node, abs)
      None => None
    }
  } else {
    None
  }
  let result = convert_top_blocks(node)
  match extracted {
    Some(e) => restore_abstract(e)
    None => ()
  }
  result
}

///|
fn convert_section(node : @core.Node) -> String {
  let sectname = node.sectname.unwrap_or("section")
  let tag_name = if node.document().doctype() == "manpage" {
    match sectname {
      "section" => "refsection"
      "synopsis" => "refsynopsisdiv"
      s => s
    }
  } else {
    sectname
  }
  let title_el = if node.special &&
    (node.has_option("notitle") || node.has_option("untitled")) {
    ""
  } else {
    "<title>\{title_of(node)}</title>\n"
  }
  "<\{tag_name}\{block_attrs(node)}>\n\{title_el}\{node.content()}\n</\{tag_name}>"
}

///|
fn convert_preamble(node : @core.Node) -> String {
  if node.document().doctype() == "book" {
    "<preface\{block_attrs(node)}>\n\{title_tag(node, optional=false)}\{node.content()}\n</preface>"
  } else {
    node.content()
  }
}

///|
fn author_tag(doc : @core.Node, author : @core.Author) -> String {
  let result = []
  result.push("<author>")
  result.push("<personname>")
  match author.firstname {
    Some(v) => result.push("<firstname>\{doc.sub_replacements(v)}</firstname>")
    None => ()
  }
  match author.middlename {
    Some(v) => result.push("<othername>\{doc.sub_replacements(v)}</othername>")
    None => ()
  }
  match author.lastname {
    Some(v) => result.push("<surname>\{doc.sub_replacements(v)}</surname>")
    None => ()
  }
  result.push("</personname>")
  match author.email {
    Some(v) => result.push("<email>\{v}</email>")
    None => ()
  }
  result.push("</author>")
  result.join("\n")
}

///|
fn DocBook5Converter::document_info_tag(
  self : DocBook5Converter,
  doc : @core.Node,
  abstract_block : @core.Node?,
) -> String {
  let result = ["<info>"]
  if !doc.notitle() {
    match doc.doctitle_partitioned(use_fallback=true) {
      Some(title) =>
        match title.subtitle {
          Some(subtitle) =>
            result.push(
              "<title>\{title.main}</title>\n<subtitle>\{subtitle}</subtitle>",
            )
          None => result.push("<title>\{title.combined}</title>")
        }
      None => result.push("<title></title>")
    }
  }
  let date = if doc.has_attr("revdate") {
    doc.attr("revdate")
  } else if doc.has_attr("reproducible") {
    None
  } else {
    doc.attr("docdate")
  }
  match date {
    Some(d) => result.push("<date>\{d}</date>")
    None => ()
  }
  if doc.has_attr("copyright") {
    let m = copyright_rx.find(a(doc, "copyright"))
    result.push("<copyright>")
    result.push(
      "<holder>\{m.map(m => m.group(1).unwrap_or("")).unwrap_or("")}</holder>",
    )
    match m.map(m => m.group(2)) {
      Some(Some(year)) => result.push("<year>\{year}</year>")
      _ => ()
    }
    result.push("</copyright>")
  }
  if doc.has_header() {
    let authors = doc.authors()
    if !authors.is_empty() {
      if authors.length() > 1 {
        result.push("<authorgroup>")
        for author in authors {
          result.push(author_tag(doc, author))
        }
        result.push("</authorgroup>")
      } else {
        let author = authors[0]
        result.push(author_tag(doc, author))
        match author.initials {
          Some(i) => result.push("<authorinitials>\{i}</authorinitials>")
          None => ()
        }
      }
    }
    if doc.has_attr("revdate") &&
      (doc.has_attr("revnumber") || doc.has_attr("revremark")) {
      result.push("<revhistory>\n<revision>")
      if doc.has_attr("revnumber") {
        result.push("<revnumber>\{a(doc, "revnumber")}</revnumber>")
      }
      if doc.has_attr("revdate") {
        result.push("<date>\{a(doc, "revdate")}</date>")
      }
      if doc.has_attr("authorinitials") {
        result.push(
          "<authorinitials>\{a(doc, "authorinitials")}</authorinitials>",
        )
      }
      if doc.has_attr("revremark") {
        result.push("<revremark>\{a(doc, "revremark")}</revremark>")
      }
      result.push("</revision>\n</revhistory>")
    }
    if doc.has_attr("front-cover-image") || doc.has_attr("back-cover-image") {
      match cover_tag(doc, "back") {
        Some(back_cover_tag) => {
          match cover_tag(doc, "front", use_placeholder=true) {
            Some(t) => result.push(t)
            None => ()
          }
          result.push(back_cover_tag)
        }
        None =>
          match cover_tag(doc, "front") {
            Some(t) => result.push(t)
            None => ()
          }
      }
    }
    if doc.has_attr("orgname") {
      result.push("<orgname>\{a(doc, "orgname")}</orgname>")
    }
    let docinfo_content = doc.docinfo()
    if docinfo_content != "" {
      result.push(docinfo_content)
    }
  }
  match abstract_block {
    Some(abs) => {
      abs.set_option("root") |> ignore
      result.push(self.dispatch(abs, abs.node_name))
      abs.remove_attr("root-option") |> ignore
    }
    None => ()
  }
  result.push("</info>")
  result.join("\n")
}

///|
fn find_root_abstract(doc : @core.Node) -> @core.Node? {
  guard doc.has_blocks() else { return None }
  let mut first_block = doc.blocks[0]
  if first_block.context == Preamble {
    match first_block.blocks.get(0) {
      Some(b) => first_block = b
      None => return None
    }
  } else if first_block.context == Section {
    if first_block.sectname == Some("abstract") {
      return Some(first_block)
    }
    guard first_block.sectname == Some("preface") &&
      first_block.blocks.get(0) is Some(b) else {
      return None
    }
    first_block = b
  }
  if first_block.style == Some("abstract") && first_block.context == Open {
    Some(first_block)
  } else {
    None
  }
}

///|
/// Removes the block that holds the abstract from the tree; returns the
/// removed block so it can be restored.
fn extract_abstract(
  document : @core.Node,
  abstract_block : @core.Node,
) -> @core.Node? {
  guard abstract_block.parent() is Some(p) else { return None }
  let mut parent = p
  while !physical_equal(parent, document) && parent.blocks.length() == 1 {
    match parent.parent() {
      Some(pp) => parent = pp
      None => break
    }
  }
  if parent.blocks.is_empty() {
    None
  } else {
    Some(parent.blocks.remove(0))
  }
}

///|
fn restore_abstract(abstract_block : @core.Node) -> Unit {
  match abstract_block.parent() {
    Some(p) => p.blocks.insert(0, abstract_block)
    None => ()
  }
}

///|
fn cover_tag(
  doc : @core.Node,
  face : String,
  use_placeholder? : Bool = false,
) -> String? {
  match doc.attr("\{face}-cover-image") {
    Some(cover_image0) => {
      let mut cover_image = cover_image0
      let mut size_attrs = ""
      if cover_image.contains(":") {
        match image_macro_rx.find(cover_image) {
          Some(m) => {
            let target = m.group(1).unwrap_or("")
            cover_image = doc.image_uri(target)
            // NOTE scalefit="1" is the default for a cover image
            match m.group(2) {
              Some(attrlist) =>
                size_attrs = image_size_attributes(
                  doc.parse_attributes(attrlist, [
                    Some("alt"),
                    Some("width"),
                    Some("height"),
                  ]),
                )
              None => ()
            }
          }
          None => ()
        }
      }
      Some(
        "<cover role=\"\{face}\">\n<mediaobject>\n<imageobject>\n<imagedata fileref=\"\{cover_image}\"\{size_attrs}/>\n</imageobject>\n</mediaobject>\n</cover>",
      )
    }
    None =>
      if use_placeholder {
        Some("<cover role=\"\{face}\"/>")
      } else {
        None
      }
  }
}
