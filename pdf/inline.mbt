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
/// Registers the `pdf` backend with the core so that `backend=pdf` loads
/// resolve inline content to formatted text.
pub fn register() -> Unit {
  @core.register_converter(["pdf"], fn(_backend, _htmlsyntax, _doc) {
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
    "inline_indexterm" => {
      // asciidoctor-pdf anchors every term (`__indexterm-N`) and collects
      // it for the index section; the spike keeps only the visible text
      unsupported("inline", "indexterm", node)
      if node.inline_type == Some("visible") {
        node.text().unwrap_or("")
      } else {
        ""
      }
    }
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
      "<sup>\{anchor}[<a anchor=\"_footnotedef_\{index}\">\{index}</a>]</sup>"
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
