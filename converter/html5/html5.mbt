///|
/// The HTML 5 converter (Ruby `Converter::Html5Converter`).
pub struct Html5Converter {
  priv xml_mode : Bool
  priv void_element_slash : String
  priv mut refs : Map[String, @core.Node]?
  priv mut resolving_xref : Bool
}

///|
pub fn Html5Converter::new(htmlsyntax? : String) -> Html5Converter {
  let xml = htmlsyntax == Some("xml")
  {
    xml_mode: xml,
    void_element_slash: if xml {
      "/"
    } else {
      ""
    },
    refs: None,
    resolving_xref: false,
  }
}

///|
fn init {
  @core.register_converter(["html5"], fn(_backend, htmlsyntax, _doc) {
    Html5Converter::new(htmlsyntax?)
  })
}

///|
/// Ensures the converter is registered (the package initializer does this;
/// calling this function forces the package to be linked).
pub fn register() -> Unit {
  @core.register_converter(["html5"], fn(_backend, htmlsyntax, _doc) {
    Html5Converter::new(htmlsyntax?)
  })
}

///|
pub impl @core.Converter for Html5Converter with fn backend_traits(self) {
  {
    basebackend: "html",
    filetype: "html",
    htmlsyntax: Some(if self.xml_mode { "xml" } else { "html" }),
    outfilesuffix: ".html",
    supports_templates: true,
  }
}

///|
pub impl @core.Converter for Html5Converter with fn convert(
  self,
  node,
  transform,
) {
  match transform {
    "inline_quoted" => self.convert_inline_quoted(node)
    "paragraph" => self.convert_paragraph(node)
    "inline_anchor" => self.convert_inline_anchor(node)
    "section" => self.convert_section(node)
    "listing" => self.convert_listing(node)
    "literal" => self.convert_literal(node)
    "ulist" => self.convert_ulist(node)
    "olist" => self.convert_olist(node)
    "dlist" => self.convert_dlist(node)
    "admonition" => self.convert_admonition(node)
    "colist" => self.convert_colist(node)
    "embedded" => self.convert_embedded(node)
    "example" => self.convert_example(node)
    "floating_title" => self.convert_floating_title(node)
    "image" => self.convert_image(node)
    "inline_break" => self.convert_inline_break(node)
    "inline_button" => self.convert_inline_button(node)
    "inline_callout" => self.convert_inline_callout(node)
    "inline_footnote" => self.convert_inline_footnote(node)
    "inline_image" => self.convert_inline_image(node)
    "inline_indexterm" => self.convert_inline_indexterm(node)
    "inline_kbd" => self.convert_inline_kbd(node)
    "inline_menu" => self.convert_inline_menu(node)
    "open" => self.convert_open(node)
    "page_break" => "<div class=\"page-break\"></div>"
    "preamble" => self.convert_preamble(node)
    "quote" => self.convert_quote(node)
    "sidebar" => self.convert_sidebar(node)
    "stem" => self.convert_stem(node)
    "table" => self.convert_table(node)
    "thematic_break" => self.convert_thematic_break(node)
    "verse" => self.convert_verse(node)
    "video" => self.convert_video(node)
    "document" => self.convert_document(node)
    "toc" => self.convert_toc(node)
    "pass" => node.content()
    "audio" => self.convert_audio(node)
    "outline" => self.convert_outline(node).unwrap_or("")
    _ => {
      @core.logger().add({
        severity: Warn,
        text: "no converter handler for transform: \{transform}",
        source_location: None,
        include_location: None,
      })
      ""
    }
  }
}

// ---------------------------------------------------------------------------
// helpers

///|
fn id_attr(node : @core.Node) -> String {
  match node.id {
    Some(id) => " id=\"\{id}\""
    None => ""
  }
}

///|
fn role_suffix(node : @core.Node) -> String {
  match node.role() {
    Some(r) => " \{r}"
    None => ""
  }
}

///|
fn title_div(node : @core.Node) -> String {
  if node.has_title() {
    "<div class=\"title\">\{node.title().unwrap_or("")}</div>\n"
  } else {
    ""
  }
}

///|
fn a(node : @core.Node, name : String) -> String {
  node.attr(name).unwrap_or("")
}

///|
fn compact_join(items : Array[String?], sep : String) -> String {
  items.filter_map(x => x).join(sep)
}

///|
fn Html5Converter::append_boolean_attribute(
  _self : Html5Converter,
  name : String,
  xml : Bool,
) -> String {
  if xml {
    " \{name}=\"\{name}\""
  } else {
    " \{name}"
  }
}

///|
fn append_link_constraint_attrs(
  node : @core.Node,
  attrs : Array[String],
) -> Array[String] {
  let rel = if node.has_option("nofollow") { Some("nofollow") } else { None }
  match node.attributes.str("window") {
    Some(window) => {
      attrs.push(" target=\"\{window}\"")
      if window == "_blank" || node.has_option("noopener") {
        attrs.push(
          match rel {
            Some(r) => " rel=\"\{r} noopener\""
            None => " rel=\"noopener\""
          },
        )
      }
    }
    None =>
      match rel {
        Some(r) => attrs.push(" rel=\"\{r}\"")
        None => ()
      }
  }
  attrs
}

///|
fn encode_attribute_value(val : String) -> String {
  if val.contains("\"") {
    val.replace_all(old="\"", new="&quot;")
  } else {
    val
  }
}

///|
let drop_anchor_rx : @regex.Regex = @regex.re("<(?:a\\b[^>]*|/a)>")

///|
let leading_anchors_rx : @regex.Regex = @regex.re("^(?:<a id=\"[^\"]+\"></a>)+")

///|
let stem_break_rx : @regex.Regex = @regex.re(" *\\\\\\n(?:\\\\?\\n)*|\\n\\n+")

///|
let svg_preamble_rx : @regex.Regex = @regex.re(
  "\\A.*?(?=<svg[\\s>])",
  flags="m",
)

///|
let svg_start_tag_rx : @regex.Regex = @regex.re("\\A<svg(?:\\s[^>]*)?>")

///|
let dimension_attribute_rx : @regex.Regex = @regex.re(
  "\\s(?:width|height|style)=([\"']).*?\\1",
)

///|
let xml_sanitize_rx : @regex.Regex = @regex.re("<[^>]+>")

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
fn Html5Converter::generate_manname_section(
  self : Html5Converter,
  node : @core.Node,
) -> String {
  ignore(self)
  let mut manname_title = node
    .attr("manname-title", default="Name")
    .unwrap_or("Name")
  match node.sections().get(0) {
    Some(next_section) => {
      let t = next_section.title().unwrap_or("")
      if t == @rb.upcase(t) {
        manname_title = @rb.upcase(manname_title)
      }
    }
    None => ()
  }
  let manname_id_attr = match node.attr("manname-id") {
    Some(i) => " id=\"\{i}\""
    None => ""
  }
  let mannames = match node.attributes.get("mannames") {
    Some(List(l)) => l.join(", ")
    Some(v) => v.to_s()
    None => ""
  }
  "<h2\{manname_id_attr}>\{manname_title}</h2>\n<div class=\"sectionbody\">\n<p>\{mannames} - \{a(node, "manpurpose")}</p>\n</div>"
}

///|
fn Html5Converter::read_svg_contents(
  self : Html5Converter,
  node : @core.Node,
  target : String,
) -> String? {
  ignore(self)
  match
    node.read_contents(
      target,
      start?=node.document().attr("imagesdir"),
      normalize=true,
      label="SVG",
      warn_if_empty=true,
    ) {
    Some(svg0) => {
      if svg0 == "" {
        return None
      }
      let mut svg = svg0
      if !svg.has_prefix("<svg") {
        svg = svg_preamble_rx.sub(svg, "")
      }
      let mut old_start_tag : String? = None
      let mut new_start_tag : String? = None
      let mut start_tag_searched = false
      let mut start_tag_match : String? = None
      for dim in ["width", "height"] {
        if !node.has_attr(dim) {
          continue
        }
        if new_start_tag is None {
          if !start_tag_searched {
            start_tag_searched = true
            start_tag_match = svg_start_tag_rx.find(svg).map(m => m.matched())
          }
          match start_tag_match {
            Some(tag) => {
              old_start_tag = Some(tag)
              new_start_tag = Some(dimension_attribute_rx.gsub(tag, ""))
            }
            None => continue
          }
        }
        new_start_tag = Some(
          "\{@rb.chop(new_start_tag.unwrap())} \{dim}=\"\{a(node, dim)}\">",
        )
      }
      match (new_start_tag, old_start_tag) {
        (Some(n), Some(o)) => svg = n + @rb.from(svg, o.length())
        _ => ()
      }
      Some(svg)
    }
    None => None
  }
}
