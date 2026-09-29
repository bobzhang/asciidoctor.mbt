///|
// The `pdf` backend as the core sees it: a converter that turns inline
// nodes into asciidoctor-pdf's formatted-text markup (the `convert_inline_*`
// methods of lib/asciidoctor/pdf/converter.rb). Block nodes are walked by
// `convert_document`, not converted to strings, so they yield nothing here.

///|
priv struct InlineConverter {
  mut resolving_xref : Bool
}

///|
/// State shared by the inline conversions of one document and its block
/// conversion. Inline content is converted whenever the core asks (section
/// titles already while parsing), so this lives with the converter the
/// core creates for the document, as asciidoctor-pdf's converter instance
/// does.
priv struct Session {
  /// how deep in dry runs (asciidoctor-pdf's scratch document): inline
  /// conversions there must leave no trace (index terms are not stored)
  mut scratch : Int
  /// the index terms met so far
  mut index : IndexCatalog
  /// how many footnotes are inked (`@rendered_footnotes`): a book inks
  /// them after each chapter, and labels count from there
  mut rendered_footnotes : Int
  /// the labels footnotes were inked with, by index
  footnote_labels : Map[Int, String]
}

///|
let session : Session = {
  scratch: 0,
  index: IndexCatalog::new(),
  rendered_footnotes: 0,
  footnote_labels: Map([]),
}

///|
/// Registers the `pdf` backend with the core so that `backend=pdf` loads
/// resolve inline content to formatted text.
pub fn register() -> Unit {
  @core.register_converter(["pdf"], fn(_backend, _htmlsyntax, _doc) {
    // a new document: a new index (nested documents share their parent's
    // converter)
    session.index = IndexCatalog::new()
    session.scratch = 0
    session.rendered_footnotes = 0
    session.footnote_labels.clear()
    ({ resolving_xref: false, } : InlineConverter)
  })
}

///|
impl @core.Converter for InlineConverter with fn backend_traits(_self) {
  {
    basebackend: "html",
    filetype: "pdf",
    htmlsyntax: Some("html"),
    outfilesuffix: ".pdf",
    supports_templates: false,
  }
}

///|
impl @core.Converter for InlineConverter with fn convert(self, node, transform) {
  match transform {
    "inline_quoted" => convert_inline_quoted(node)
    "inline_anchor" => self.convert_inline_anchor(node)
    "inline_break" => "\{node.text().unwrap_or("")}<br>"
    "inline_button" => "<button>[ \{node.text().unwrap_or("")} ]</button>"
    "inline_callout" =>
      "<font color=\"#B12146\"><font name=\"M+ 1mn\">\{conum_glyph(node.text().unwrap_or("1"))}</font></font>"
    "inline_footnote" => convert_inline_footnote(node)
    "inline_kbd" => convert_inline_kbd(node)
    "inline_menu" => convert_inline_menu(node)
    "inline_image" => {
      // drawn as its alt text; asciidoctor-pdf places the image in the line
      unsupported("inline", "image", node)
      "[\{node.attr("alt").unwrap_or("")}]"
    }
    "inline_indexterm" => convert_inline_indexterm(node)
    // block content reached through `content()` (e.g. a pass block)
    "pass" => node.content()
    // the nested document of an AsciiDoc table cell (`a|`), which the
    // spike's tables leave empty
    "embedded" => {
      unsupported("block", "AsciiDoc table cell", node)
      ""
    }
    other => {
      unsupported("inline", other, node)
      ""
    }
  }
}

///|
/// A string list attribute (`terms`, `see-also`).
fn list_attr(node : @core.Node, name : String) -> Array[String] {
  match node.attributes.get(name) {
    Some(List(items)) => items
    Some(Str(item)) => [item]
    _ => []
  }
}

///|
/// asciidoctor-pdf's `convert_inline_indexterm`: an anchor named
/// `__indexterm-N` where the term occurs (whose page the index lists),
/// followed by the term when it is visible. A dry run (scratch) keeps only
/// the visible text and stores nothing.
fn convert_inline_indexterm(node : @core.Node) -> String {
  let visible = node.inline_type == Some("visible")
  if session.scratch > 0 {
    return if visible { node.text().unwrap_or("") } else { "" }
  }
  let index = session.index
  let anchor_name = index.next_anchor_name()
  let dest : IndexDest = { anchor: anchor_name, page: None, page_sortable: 0, }
  let anchor = if visible {
    "<a id=\"\{anchor_name}\" type=\"indexterm\" visible=\"true\"></a>"
  } else {
    "<a id=\"\{anchor_name}\" type=\"indexterm\"></a>"
  }
  let see = node.attr("see")
  let see_also = list_attr(node, "see-also")
  if visible {
    let term = node.text().unwrap_or("")
    index.store_term([term], dest, see~, see_also~)
    anchor + term
  } else {
    index.store_term(list_attr(node, "terms"), dest, see~, see_also~)
    anchor
  }
}

///|
fn conum_glyph(text : String) -> String {
  let n = @string.parse_int(text) catch { _ => 1 }
  if n >= 1 && n <= 20 {
    code_to_string(0x2460 + n - 1)
  } else {
    "(\{text})"
  }
}

///|
fn convert_inline_quoted(node : @core.Node) -> String {
  let (open, close, is_tag) = match node.inline_type {
    Some("emphasis") => ("<em>", "</em>", true)
    Some("strong") => ("<strong>", "</strong>", true)
    Some("monospaced") | Some("asciimath") | Some("latexmath") =>
      ("<code>", "</code>", true)
    Some("superscript") => ("<sup>", "</sup>", true)
    Some("subscript") => ("<sub>", "</sub>", true)
    Some("double") => ("&#8220;", "&#8221;", false)
    Some("single") => ("&#8216;", "&#8217;", false)
    Some("mark") => ("<mark>", "</mark>", true)
    _ => ("", "", false)
  }
  let text = node.text().unwrap_or("")
  let quoted = match node.role() {
    Some(roles) =>
      if is_tag {
        "\{open[:open.length() - 1]} class=\"\{roles}\">\{text}\{close}"
      } else {
        "<span class=\"\{roles}\">\{open}\{text}\{close}</span>"
      }
    None => "\{open}\{text}\{close}"
  }
  match node.id {
    Some(id) => "<a id=\"\{id}\"></a>\{quoted}"
    None => quoted
  }
}

///|
fn InlineConverter::convert_inline_anchor(
  self : InlineConverter,
  node : @core.Node,
) -> String {
  let target = node.target.unwrap_or("")
  match node.inline_type {
    Some("link") => {
      let anchor = match node.id {
        Some(id) => "<a id=\"\{id}\"></a>"
        None => ""
      }
      let class = match node.role() {
        Some(role) => " class=\"\{role}\""
        None => ""
      }
      "\{anchor}<a href=\"\{target}\"\{class}>\{node.text().unwrap_or("")}</a>"
    }
    Some("xref") =>
      match node.attributes.str("path") {
        Some(path) => "<a href=\"\{target}\">\{node.text().unwrap_or(path)}</a>"
        None => {
          let refid = node.attributes.str("refid")
          let text = match node.text() {
            Some(text) => text
            None => {
              let refs = node.document().catalog().refs
              match refid.bind(id => refs.get(id)) {
                Some(ref_) if !self.resolving_xref => {
                  self.resolving_xref = true
                  let text = ref_.xreftext(
                    xrefstyle?=node.attr("xrefstyle", inherited=true),
                  )
                  self.resolving_xref = false
                  match text {
                    Some(t) => drop_anchors(t)
                    None => "[\{refid.unwrap_or("")}]"
                  }
                }
                _ => "[\{refid.unwrap_or("")}]"
              }
            }
          }
          match refid {
            Some(id) => "<a anchor=\"\{id}\">\{text}</a>"
            None => "<a anchor=\"\{top_anchor(node.document())}\">\{text}</a>"
          }
        }
      }
    Some("ref") => "<a id=\"\{node.id.unwrap_or("")}\"></a>"
    Some("bibref") => {
      let id = node.id.unwrap_or("")
      let reftext = match node.reftext() {
        Some(r) => r
        None => id
      }
      "<a id=\"\{id}\"></a>[\{reftext}]"
    }
    other => {
      unsupported("inline", "anchor type \{other.unwrap_or("none")}", node)
      ""
    }
  }
}

///|
/// Remove `<a ...>` and `</a>` tags (asciidoctor-pdf's `DropAnchorRx`).
fn drop_anchors(text : String) -> String {
  if !text.contains("<a") {
    return text
  }
  let sb = StringBuilder()
  let mut i = 0
  let n = text.length()
  while i < n {
    if text[i] == '<' &&
      i + 1 < n &&
      (
        (
          text[i + 1] == 'a' &&
          i + 2 < n &&
          (text[i + 2] == ' ' || text[i + 2] == '>')
        ) ||
        (text[i + 1] == '/' && i + 2 < n && text[i + 2] == 'a')
      ) {
      while i < n && text[i] != '>' {
        i += 1
      }
      i += 1
      continue
    }
    sb.write_char(text[i].to_int().unsafe_to_char())
    i += 1
  }
  sb.to_string()
}

///|
fn convert_inline_footnote(node : @core.Node) -> String {
  match node.attr("index") {
    Some(index) => {
      let anchor = if node.inline_type == Some("xref") {
        ""
      } else {
        "<a id=\"_footnoteref_\{index}\"></a>"
      }
      // counted from the footnotes inked so far (a book's chapter), or the
      // label it was inked with
      let number = @string.parse_int(index) catch { _ => 0 }
      let label = match session.footnote_labels.get(number) {
        Some(label) => label
        None => (number - session.rendered_footnotes).to_string()
      }
      "<sup>\{anchor}[<a anchor=\"_footnotedef_\{index}\">\{label}</a>]</sup>"
    }
    None => "<sup>[\{node.text().unwrap_or("")}]</sup>"
  }
}

///|
fn convert_inline_kbd(node : @core.Node) -> String {
  match node.attributes.get("keys") {
    Some(List(keys)) => keys.map(key => "<kbd>\{key}</kbd>").join(" + ​")
    _ => "<kbd>\{node.text().unwrap_or("")}</kbd>"
  }
}

///|
fn convert_inline_menu(node : @core.Node) -> String {
  let caret = " <font size=\"1.15em\" color=\"#B12146\">›</font> "
  let menu = node.attr("menu").unwrap_or("")
  let parts = [menu]
  match node.attributes.get("submenus") {
    Some(List(submenus)) => parts.append(submenus)
    _ => ()
  }
  match node.attr("menuitem") {
    Some(item) => parts.push(item)
    None => ()
  }
  "<strong>\{parts.join(caret)}</strong>"
}
