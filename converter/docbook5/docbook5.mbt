///|
/// The DocBook 5 converter (Ruby `Converter::DocBook5Converter`).
pub struct DocBook5Converter {
  priv backend : String
  priv mut asciimath_checked : Bool
}

///|
pub fn DocBook5Converter::new(
  backend? : String = "docbook5",
) -> DocBook5Converter {
  { backend, asciimath_checked: false, }
}

///|
/// Ruby `asciimath_available?`. The AsciiMath library is not part of this
/// port, so this behaves as if the optional gem were not installed (warning
/// once per converter) and math is passed through as `mathphrase`.
fn DocBook5Converter::asciimath_available(self : DocBook5Converter) -> Bool {
  if !self.asciimath_checked {
    self.asciimath_checked = true
    warn("optional gem 'asciimath' is not available. Functionality disabled.")
  }
  false
}

///|
fn factory(
  backend : String,
  _htmlsyntax : String?,
  _doc : @core.Node,
) -> &@core.Converter {
  DocBook5Converter::new(backend~)
}

///|
fn init {
  @core.register_converter(["docbook5"], factory)
}

///|
/// Ensures the converter is registered (the package initializer does this;
/// calling this function forces the package to be linked).
pub fn register() -> Unit {
  @core.register_converter(["docbook5"], factory)
}

///|
pub impl @core.Converter for DocBook5Converter with fn backend_traits(_self) {
  {
    basebackend: "docbook",
    filetype: "xml",
    htmlsyntax: None,
    outfilesuffix: ".xml",
    supports_templates: true,
  }
}

///|
pub impl @core.Converter for DocBook5Converter with fn convert(
  self,
  node,
  transform,
) {
  self.dispatch(node, transform)
}

///|
fn DocBook5Converter::dispatch(
  self : DocBook5Converter,
  node : @core.Node,
  transform : String,
) -> String {
  match transform {
    "document" => self.convert_document(node)
    "embedded" => self.convert_embedded(node)
    "section" => convert_section(node)
    "admonition" => convert_admonition(node)
    "audio" | "video" | "toc" => ""
    "colist" => convert_colist(node)
    "dlist" => convert_dlist(node)
    "example" => convert_example(node)
    "floating_title" => convert_floating_title(node)
    "image" => convert_image(node)
    "listing" => convert_listing(node)
    "literal" => convert_literal(node)
    "pass" => node.content()
    "stem" => self.convert_stem(node)
    "olist" => convert_olist(node)
    "open" => self.convert_open(node)
    "page_break" => "<simpara><?asciidoc-pagebreak?></simpara>"
    "paragraph" => convert_paragraph(node)
    "preamble" => convert_preamble(node)
    "quote" => convert_quote(node)
    "thematic_break" => "<simpara><?asciidoc-hr?></simpara>"
    "sidebar" => convert_sidebar(node)
    "table" => convert_table(node)
    "ulist" => convert_ulist(node)
    "verse" => convert_verse(node)
    "inline_anchor" => convert_inline_anchor(node)
    "inline_break" => "\{node.text().unwrap_or("")}<?asciidoc-br?>"
    "inline_button" => "<guibutton>\{node.text().unwrap_or("")}</guibutton>"
    "inline_callout" => "<co\{common_attributes(node.id)}/>"
    "inline_footnote" => convert_inline_footnote(node)
    "inline_image" => convert_inline_image(node)
    "inline_indexterm" => convert_inline_indexterm(node)
    "inline_kbd" => convert_inline_kbd(node)
    "inline_menu" => convert_inline_menu(node)
    "inline_quoted" => self.convert_inline_quoted(node)
    _ => {
      warn(
        "missing convert handler for \{node.node_name} node in docbook5 backend (Asciidoctor::Converter::DocBook5Converter)",
      )
      ""
    }
  }
}

// ---------------------------------------------------------------------------
// helpers

///|
fn warn(text : String) -> Unit {
  @core.logger().add({
    severity: Warn,
    text,
    source_location: None,
    include_location: None,
  })
}

///|
fn error(text : String) -> Unit {
  @core.logger().add({
    severity: Error,
    text,
    source_location: None,
    include_location: None,
  })
}

///|
fn a(node : @core.Node, name : String) -> String {
  node.attr(name).unwrap_or("")
}

///|
fn title_of(node : @core.Node) -> String {
  node.title().unwrap_or("")
}

///|
let xml_sanitize_rx : @regex.Regex = @regex.re("<[^>]+>")

///|
/// Ruby `common_attributes id, role, reftext`.
fn common_attributes(
  id : String?,
  role? : String?,
  reftext? : String?,
) -> String {
  let attrs = match id {
    Some(id) =>
      match role {
        Some(Some(r)) => " xml:id=\"\{id}\" role=\"\{r}\""
        _ => " xml:id=\"\{id}\""
      }
    None =>
      match role {
        Some(Some(r)) => " role=\"\{r}\""
        _ => ""
      }
  }
  match reftext {
    Some(Some(reftext)) => {
      let mut reftext = reftext
      if reftext.contains("<") {
        reftext = xml_sanitize_rx.gsub(reftext, "")
        if reftext.contains(" ") {
          reftext = @rb.strip(@rb.squeeze(reftext, chars=" "))
        }
      }
      if reftext.contains("\"") {
        reftext = reftext.replace_all(old="\"", new="&quot;")
      }
      "\{attrs} xreflabel=\"\{reftext}\""
    }
    _ => attrs
  }
}

///|
/// `common_attributes node.id, node.role, node.reftext`
fn block_attrs(node : @core.Node) -> String {
  common_attributes(node.id, role=node.role(), reftext=node.reftext())
}

///|
fn image_size_attributes(attributes : @core.Attributes) -> String {
  let s = fn(name : String) {
    attributes.get(name).map(v => v.to_s()).unwrap_or("")
  }
  if attributes.contains("scaledwidth") {
    " width=\"\{s("scaledwidth")}\""
  } else if attributes.contains("scale") {
    " scale=\"\{s("scale")}\""
  } else {
    let width_attribute = if attributes.contains("width") {
      " contentwidth=\"\{s("width")}\""
    } else {
      ""
    }
    let depth_attribute = if attributes.contains("height") {
      " contentdepth=\"\{s("height")}\""
    } else {
      ""
    }
    "\{width_attribute}\{depth_attribute}"
  }
}

///|
/// FIXME this should be handled through a template mechanism
fn enclose_content(node : @core.Node) -> String {
  if node.content_model == Compound {
    node.content()
  } else {
    "<simpara>\{node.content()}</simpara>"
  }
}

///|
fn title_tag(node : @core.Node, optional? : Bool = true) -> String {
  if !optional || node.has_title() {
    "<title>\{title_of(node)}</title>\n"
  } else {
    ""
  }
}

///|
fn get_root_document(node : @core.Node) -> @core.Node {
  let mut doc = node.document()
  while doc.is_nested() {
    match doc.parent_document() {
      Some(p) => doc = p.document()
      None => break
    }
  }
  doc
}

///|
fn generate_document_id(doc : @core.Node) -> String {
  "__\{doc.doctype()}-root__"
}

///|
fn list_attr(node : @core.Node, name : String) -> Array[String] {
  match node.attributes.get(name) {
    Some(List(l)) => l
    Some(Nil) | None => []
    Some(v) => [v.to_s()]
  }
}
