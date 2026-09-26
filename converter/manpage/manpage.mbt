///|
/// The man page (groff/troff) converter (Ruby `Converter::ManPageConverter`).
pub struct ManPageConverter {
  priv mut refs : Map[String, @core.Node]?
  priv mut resolving_xref : Bool
}

///|
pub fn ManPageConverter::new() -> ManPageConverter {
  { refs: None, resolving_xref: false, }
}

///|
fn init {
  register()
}

///|
/// Ensures the converter is registered (the package initializer does this;
/// calling this function forces the package to be linked).
pub fn register() -> Unit {
  @core.register_converter(["manpage"], fn(_backend, _htmlsyntax, _doc) {
    ManPageConverter::new()
  })
}

///|
pub impl @core.Converter for ManPageConverter with fn backend_traits(_self) {
  {
    basebackend: "manpage",
    filetype: "man",
    htmlsyntax: None,
    outfilesuffix: ".man",
    supports_templates: true,
  }
}

///|
pub impl @core.Converter for ManPageConverter with fn convert(
  self,
  node,
  transform,
) {
  match transform {
    "document" => self.convert_document(node)
    "embedded" => self.convert_embedded(node)
    "section" => self.convert_section(node)
    "admonition" => self.convert_admonition(node)
    "colist" => self.convert_colist(node)
    "dlist" => self.convert_dlist(node)
    "example" => self.convert_example(node)
    "floating_title" => self.convert_floating_title(node)
    "image" => self.convert_image(node)
    "listing" => self.convert_listing(node)
    "literal" => self.convert_literal(node)
    "sidebar" => self.convert_sidebar(node)
    "olist" => self.convert_olist(node)
    "open" => self.convert_open(node)
    "page_break" => ".bp"
    "paragraph" => self.convert_paragraph(node)
    "pass" | "preamble" => node.content()
    "quote" => self.convert_quote(node)
    "stem" => self.convert_stem(node)
    "table" => self.convert_table(node)
    "thematic_break" => ".sp\n.ce\n\\l'\\n(.lu*25u/100u\\(ap'"
    "toc" => ""
    "ulist" => self.convert_ulist(node)
    "verse" => self.convert_verse(node)
    "video" => self.convert_video(node)
    "inline_anchor" => self.convert_inline_anchor(node)
    "inline_break" => self.convert_inline_break(node)
    "inline_button" => self.convert_inline_button(node)
    "inline_callout" => self.convert_inline_callout(node)
    "inline_footnote" => self.convert_inline_footnote(node)
    "inline_image" => self.convert_inline_image(node)
    "inline_indexterm" => self.convert_inline_indexterm(node)
    "inline_kbd" => self.convert_inline_kbd(node)
    "inline_menu" => self.convert_inline_menu(node)
    "inline_quoted" => self.convert_inline_quoted(node)
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
// constants and regular expressions

///|
/// troff leader marker
const ESC : String = "\u{1b}"

///|
/// escaped backslash (indicates troff formatting sequence)
const ESC_BS : String = "\u{1b}\\"

///|
/// escaped full stop (indicates troff macro)
const ESC_FS : String = "\u{1b}."

///|
const ET : String = "        "

///|
let literal_backslash_rx : @regex.Regex = @regex.re(
  "\\A\\\\|(" + ESC + ")?\\\\",
)

///|
let leading_period_rx : @regex.Regex = @regex.re("^\\.")

///|
let escaped_macro_rx : @regex.Regex = @regex.re(
  "^(?:" +
  ESC +
  "\\\\c\\n)?" +
  ESC +
  "\\.((?:URL|MTO) \".*?\" \".*?\" )( |[^\\s]*)(.*?)(?: *" +
  ESC +
  "\\\\c)?$",
)

///|
let malformed_escaped_macro_rx : @regex.Regex = @regex.re(
  "(" + ESC + "\\\\c) (" + ESC + "\\.(?:URL|MTO) )",
)

///|
let mock_macro_rx : @regex.Regex = @regex.re("</?(" + ESC + "\\\\[^>]+)>")

///|
let em_dash_char_ref_rx : @regex.Regex = @regex.re("&#8212;(?:&#8203;)?")

///|
let ellipsis_char_ref_rx : @regex.Regex = @regex.re("&#8230;(?:&#8203;)?")

///|
let wrapped_indent_rx : @regex.Regex = @regex.re("[ \\t]*\\n[ \\t]*")

///|
let xml_markup_rx : @regex.Regex = @regex.re("&#?[a-z\\d]+;|<")

///|
let pcdata_filter_rx : @regex.Regex = @regex.re(
  "(&#?[a-z\\d]+;|<" +
  ESC +
  "\\\\f\\(CR.*?</" +
  ESC +
  "\\\\fP>|<[^>]+>)|([^&<]+)",
)

///|
let repeated_spaces_rx : @regex.Regex = @regex.re("(^)?  +")

///|
let invalid_section_id_chars_rx : @regex.Regex = @regex.re(
  "<[^>]+>|&(?:[a-z][a-z]+\\d{0,2}|#\\d\\d\\d{0,4}|#x[\\da-f][\\da-f][\\da-f]{0,3});|[^ \\p{Word}\\-.]+?",
)

// ---------------------------------------------------------------------------
// helpers

///|
/// How `manify` handles whitespace.
priv enum Whitespace {
  Preserve
  Normalize
  Collapse
}

///|
/// Converts HTML entity references back to their original form, escapes
/// special man characters and strips trailing whitespace.
///
/// It's crucial that text only ever pass through manify once.
fn manify(str : String, whitespace? : Whitespace = Collapse) -> String {
  let mut s = match whitespace {
    Preserve =>
      repeated_spaces_rx.replace(str.replace_all(old="\t", new=ET), m => {
        if m.group(1) is Some(_) {
          m.matched()
        } else {
          "\{ESC_BS}&\{m.matched()}"
        }
      })
    Normalize => wrapped_indent_rx.replace(str, _ => "\n")
    Collapse => @rb.tr_s(str, "\n\t ", ' ')
  }
  // literal backslash (not a troff escape sequence)
  s = literal_backslash_rx.replace(s, m => {
    if m.group(1) is Some(_) {
      m.matched()
    } else {
      "\\(rs"
    }
  })
  // horizontal ellipsis (emulate appearance)
  s = ellipsis_char_ref_rx.replace(s, _ => ".\\|.\\|.")
  // leading . is used in troff for macro call or other formatting; replace with \&.
  s = leading_period_rx.replace(s, _ => "\\&.")
  // drop orphaned \c escape lines, unescape troff macro, quote adjacent
  // character, isolate macro line
  s = escaped_macro_rx.replace(s, m => {
    let g1 = m.group(1).unwrap_or("")
    let g2 = m.group(2).unwrap_or("")
    let rest = @rb.lstrip(m.group(3).unwrap_or(""))
    if rest == "" {
      ".\{g1}\"\{g2}\""
    } else {
      ".\{g1}\"\{@rb.rstrip(g2)}\"\n\{rest}"
    }
  })
  s = s
    .replace_all(old="-", new="\\-")
    .replace_all(old="&lt;", new="<")
    .replace_all(old="&gt;", new=">")
    .replace_all(old="&#43;", new="+") // plus sign
    .replace_all(old="&#160;", new="\\~") // non-breaking space
    .replace_all(old="&#169;", new="\\(co") // copyright sign
    .replace_all(old="&#174;", new="\\(rg") // registered sign
    .replace_all(old="&#8482;", new="\\(tm") // trademark sign
    .replace_all(old="&#176;", new="\\(de") // degree sign
    .replace_all(old="&#8201;", new=" ") // thin space
    .replace_all(old="&#8211;", new="\\(en") // en dash
  s = em_dash_char_ref_rx.replace(s, _ => "\\(em") // em dash
  s = s
    .replace_all(old="&#8216;", new="\\(oq") // left single quotation mark
    .replace_all(old="&#8217;", new="\\(cq") // right single quotation mark
    .replace_all(old="&#8220;", new="\\(lq") // left double quotation mark
    .replace_all(old="&#8221;", new="\\(rq") // right double quotation mark
    .replace_all(old="&#8592;", new="\\(<-") // leftwards arrow
    .replace_all(old="&#8594;", new="\\(->") // rightwards arrow
    .replace_all(old="&#8656;", new="\\(lA") // leftwards double arrow
    .replace_all(old="&#8658;", new="\\(rA") // rightwards double arrow
    .replace_all(old="&#8203;", new="\\:") // zero width space
    .replace_all(old="&amp;", new="&") // literal ampersand
    .replace_all(old="'", new="\\*(Aq") // apostrophe / neutral single quote
  s = mock_macro_rx.replace(s, m => m.group(1).unwrap_or("")) // mock boundary
  s = s
    .replace_all(old=ESC_BS, new="\\") // unescape troff backslash
    .replace_all(old=ESC_FS, new=".") // unescape full stop in troff commands
  @rb.rstrip(s)
}

///|
fn uppercase_pcdata(string : String) -> String {
  if xml_markup_rx.matches(string) {
    pcdata_filter_rx.replace(string, m => {
      match m.group(2) {
        Some(t) => @rb.upcase(t)
        None => m.group(1).unwrap_or("")
      }
    })
  } else {
    @rb.upcase(string)
  }
}

///|
fn enclose_content(node : @core.Node) -> String {
  if node.content_model == Compound {
    node.content()
  } else {
    ".sp\n\{manify(node.content(), whitespace=Normalize)}"
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
fn a(node : @core.Node, name : String) -> String {
  node.attr(name).unwrap_or("")
}

///|
fn title_s(node : @core.Node) -> String {
  node.title().unwrap_or("")
}

///|
/// The `.sp` / `.B title` / `.br` preamble used by many blocks.
fn bold_title(title : String) -> String {
  ".sp\n.B \{manify(title)}\n.br"
}
