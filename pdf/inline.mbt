///|
// The `pdf` backend as the core sees it: a converter that turns inline
// nodes into asciidoctor-pdf's formatted-text markup (the `convert_inline_*`
// methods of lib/asciidoctor/pdf/converter.rb). Block nodes are walked by
// `convert_document`, not converted to strings, so they yield nothing here.

///|
priv struct InlineConverter {
  mut resolving_xref : Bool
  /// the document's state
  session : Session
}

///|
/// State shared by the inline conversions of one document and its block
/// conversion. Inline content is converted whenever the core asks (section
/// titles already while parsing), so this lives with the converter the
/// core creates for the document, as asciidoctor-pdf's converter instance
/// does: two documents loaded one after the other, then converted in any
/// order, each keep their own. The converter makes its session the active
/// one (`session()`) whenever it converts, and `convert_document` makes
/// the document's active (see `activate_session`).
priv struct Session {
  /// how deep in dry runs (asciidoctor-pdf's scratch document): inline
  /// conversions there must leave no trace (index terms are not stored)
  mut scratch : Int
  /// the index terms met so far
  index : IndexCatalog
  /// how many footnotes are inked (`@rendered_footnotes`): a book inks
  /// them after each chapter, and labels count from there
  mut rendered_footnotes : Int
  /// the labels footnotes were inked with, by index
  footnote_labels : Map[Int, String]
  /// the font catalog: the theme's fonts, and the icon fonts, whose glyphs
  /// font icons (`icon:name[]`) take; loaded once per document, unless
  /// `register` was given one
  mut catalog : FontCatalog?
  /// the document's theme, once loaded (see `document_theme`)
  mut theme : @theme.Theme?
  /// the bibliography entries referenced so far (`@bibref_refs`)
  bibref_refs : Map[String, Bool]
  /// the `subtitle` role's `normal` style was applied once (see
  /// `apply_roles`)
  normal_spent : Map[String, Bool]
  /// the inline images met so far (`<img src="N">` is the Nth)
  inline_images : Array[InlineImage]
  /// the transformation stacks of the Prawn documents SVG images are drawn
  /// into: the document's and the scratch document's (see
  /// `Flow::svg_stack`)
  svg_stacks : Array[@svg.TransformationStack]
  /// the diagnostics reported outside `convert_document` (while the
  /// document was loaded, or by `convert` before it), which each of its
  /// conversions reports first (see `report`)
  pending_diagnostics : Array[String]
  /// `convert_document` is converting the document
  mut converting : Bool
  /// the first PDF a block image or a cover could not import (see
  /// `template_failure`): the conversion fails with it
  mut template_error : String?
  /// the fonts (`family (style)`) reported as unknown
  unknown_fonts : Map[String, Bool]
  /// the Rouge formatter of the document's source blocks, made for the
  /// first (asciidoctor-pdf's `@rouge_formatter`)
  mut rouge_formatter : RougeFormatter?
  /// an error Prawn raises while the document is laid out (a line that
  /// cannot fit), which fails its conversion
  mut failure : String?
  /// what `register` was given when the document's converter was created:
  /// a later `register` leaves the documents loaded before it as they were
  registration : Registration
  /// the page size and margins (resolved when the conversion starts)
  mut page_setup : PageSetup
  /// the font blocks are set in while a category's `theme_font` is in force
  /// (the admonition, example, sidebar or quote content), with its base
  /// line height; None outside them
  mut font_scope : (Style, Double)?
}

///|
fn Session::new() -> Session {
  let registration = registration.val
  {
    scratch: 0,
    index: IndexCatalog::new(),
    rendered_footnotes: 0,
    footnote_labels: Map([]),
    catalog: registration.catalog,
    theme: None,
    bibref_refs: Map([]),
    normal_spent: Map([]),
    inline_images: [],
    svg_stacks: [
      @svg.TransformationStack::new(),
      @svg.TransformationStack::new(),
    ],
    pending_diagnostics: [],
    converting: false,
    template_error: None,
    unknown_fonts: Map([]),
    rouge_formatter: None,
    failure: None,
    registration,
    page_setup: default_page_setup(),
    font_scope: None,
  }
}

///|
/// What `register` was given, which the documents whose converters are
/// created from then on use (each session keeps its own): the catalog
/// every document is set in, where the fonts the theme loader's virtual
/// `GEM_FONTS_DIR` (`@theme.fonts_dir`) stands for really are, and
/// prawn-icon's icon fonts (`icons=font`).
priv struct Registration {
  /// the catalog every document is set in, if any
  catalog : FontCatalog?
  /// the bundled fonts, searched in order (unless `fonts_dir`)
  bundles : Array[@bundled.Bundle]
  /// the bundled icon fonts (unless `icon_fonts_dir`)
  icon_bundle : @bundled.Bundle?
  fonts_dir : String?
  icon_fonts_dir : String?
  /// the `pdf_theme` API option (see `register`)
  pdf_theme : ((@theme.Files) -> @theme.Theme raise)?
}

///|
/// The current registration (the defaults until `register` is called).
let registration : Ref[Registration] = {
  val: {
    catalog: None,
    bundles: [@bundled.default_fonts()],
    icon_bundle: None,
    fonts_dir: None,
    icon_fonts_dir: None,
    pdf_theme: None,
  },
}

///|
/// The session of the document being converted (a placeholder until a
/// document is).
let active_session : Ref[Session] = { val: Session::new(), }

///|
/// The session of the document being converted.
fn session() -> Session {
  active_session.val
}

///|
/// Make `state` the active session, and its theme, once loaded, the theme
/// of the conversion.
fn activate(state : Session) -> Unit {
  active_session.val = state
  match state.theme {
    Some(theme) => current_theme.val = theme
    None => ()
  }
}

///|
/// The transform that makes a document's converter activate its session.
let activate_transform : String = "__pdf_activate_session__"

///|
/// Make the session of `doc`'s converter the active one (see `Session`).
fn activate_session(doc : @core.Node) -> Unit {
  ignore(doc.converter().convert(doc, activate_transform))
}

///|
/// Registers the `pdf` backend with the core so that `backend=pdf` loads
/// resolve inline content to formatted text.
///
/// The fonts a theme names in asciidoctor-pdf's own font directory (its
/// `GEM_FONTS_DIR`) come from the bundles in `fonts` (by default the
/// default theme's: `@fonts.default_fonts()`; add `@sans.fonts()` and
/// `@fallback.fonts()` from `bobzhang/asciidoctor-pdf/fonts/sans` and
/// `/fonts/fallback` for the `default-sans` and
/// `default-with-font-fallbacks` themes), or, given `fonts_dir`, from that
/// directory (a copy of the gem's `data/fonts`). prawn-icon's icon fonts
/// (`icons=font`) come from `icon_fonts` (`@icons.fonts()` of
/// `bobzhang/asciidoctor-pdf/fonts/icons`), or, given `icon_fonts_dir`,
/// from that directory (prawn-icon's `data/fonts`). Any other font is read
/// through the document's VFS. With `catalog`, every document is set in
/// that catalog's fonts instead.
///
/// `pdf_theme` is asciidoctor-pdf's `pdf_theme` API option: the theme
/// every document is converted with instead of the one its `pdf-theme`
/// attribute (or `media`) selects, built from the theme files of the
/// document's VFS (see `load_document_theme`).
pub fn register(
  catalog? : FontCatalog,
  fonts? : Array[@bundled.Bundle] = [@bundled.default_fonts()],
  icon_fonts? : @bundled.Bundle,
  fonts_dir? : String,
  icon_fonts_dir? : String,
  pdf_theme? : (@theme.Files) -> @theme.Theme raise,
) -> Unit {
  registration.val = {
    catalog,
    bundles: fonts.copy(),
    icon_bundle: icon_fonts,
    fonts_dir,
    icon_fonts_dir,
    pdf_theme,
  }
  @core.register_converter(["pdf"], fn(_backend, _htmlsyntax, _doc) {
    // a new document: its own session (nested documents share their
    // parent's converter, and so its session)
    let state = Session::new()
    activate(state)
    ({ resolving_xref: false, session: state, } : InlineConverter)
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
  activate(self.session)
  match transform {
    "__pdf_activate_session__" => ""
    "inline_quoted" => convert_inline_quoted(node)
    "inline_anchor" => self.convert_inline_anchor(node)
    "inline_break" => "\{node.text().unwrap_or("")}<br>"
    "inline_button" => convert_inline_button(node)
    "inline_callout" => convert_inline_callout(node)
    "inline_footnote" => convert_inline_footnote(node)
    "inline_kbd" => convert_inline_kbd(node)
    "inline_menu" => convert_inline_menu(node)
    "inline_image" if node.inline_type == Some("icon") =>
      convert_inline_icon(node)
    "inline_image" => convert_inline_image(node)
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
  if session().scratch > 0 {
    return if visible { node.text().unwrap_or("") } else { "" }
  }
  let index = session().index
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
/// The theme's typographic quote `index` (`quotes`: open and close
/// double, open and close single).
fn theme_quote(node : @core.Node, index : Int) -> String {
  match document_theme(node)["quotes"] {
    Array(items) => items.get(index).bind(value_str).unwrap_or("")
    _ => ""
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
    Some("double") => (theme_quote(node, 0), theme_quote(node, 1), false)
    Some("single") => (theme_quote(node, 2), theme_quote(node, 3), false)
    Some("mark") => ("<mark>", "</mark>", true)
    _ => ("", "", false)
  }
  let text = node.text().unwrap_or("")
  // quoted text ending in `...` ends in an ellipsis
  let text = if (
      node.inline_type == Some("double") || node.inline_type == Some("single")
    ) &&
    text.length() > 3 &&
    text.has_suffix("...") &&
    !text[:text.length() - 3].has_suffix("\\") {
    text[:text.length() - 3].to_owned() + "&#8230;"
  } else {
    text
  }
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
      let doc = node.document()
      // for print, a mailto link shows its address (`media`)
      let screen = doc.attr("media").unwrap_or("screen") == "screen"
      let (text, bare_target) = if !screen && target.has_prefix("mailto:") {
        let address = target[7:].to_owned()
        let text = node.text().unwrap_or("")
        if address == text {
          ignore(node.add_role("bare"))
        }
        (text, if doc.has_attr("hide-uri-scheme") { address } else { target })
      } else {
        (node.text().unwrap_or(""), target)
      }
      let show_uri = doc.has_attr("show-link-uri") ||
        (!screen && attr_unspecified(doc, "show-link-uri"))
      if node.has_role("bare") {
        "\{anchor}<a href=\"\{target}\"\{class}>\{breakable_uri(text)}</a>"
      } else if show_uri {
        let bare = if doc.has_attr("hide-uri-scheme") {
          match bare_target.find("://") {
            Some(i) => bare_target[i + 3:].to_owned()
            None => bare_target
          }
        } else {
          bare_target
        }
        "\{anchor}<a href=\"\{target}\"\{class}>\{text}</a> [<font size=\"0.85em\">\{breakable_uri(bare)}</font>&#93;"
      } else {
        "\{anchor}<a href=\"\{target}\"\{class}>\{text}</a>"
      }
    }
    Some("xref") =>
      match node.attributes.str("path") {
        Some(path) => "<a href=\"\{target}\">\{node.text().unwrap_or(path)}</a>"
        None => {
          guard node.attributes.str("refid") is Some(refid) else {
            // no target: the top of the document
            let text = node.text().unwrap_or("[^top&#93;")
            return "<a anchor=\"\{top_anchor(node.document())}\">\{text}</a>"
          }
          // the first reference to a bibliography entry is where the entry
          // links back to (`_bibref_ref_<id>`)
          let mut anchor = ""
          let text = match node.text() {
            Some(text) => text
            None => {
              let refs = node.document().catalog().refs
              match refs.get(refid) {
                Some(ref_) if !self.resolving_xref => {
                  self.resolving_xref = true
                  let text = ref_.xreftext(
                    xrefstyle?=node.attr("xrefstyle", inherited=true),
                  )
                  if ref_.inline_type == Some("bibref") &&
                    session().scratch == 0 &&
                    !session().bibref_refs.contains(refid) {
                    session().bibref_refs[refid] = true
                    anchor = "<a id=\"_bibref_ref_\{refid}\"></a>"
                  }
                  self.resolving_xref = false
                  match text {
                    Some(t) => drop_anchors(t)
                    None => "[\{refid}]"
                  }
                }
                _ => "[\{refid}]"
              }
            }
          }
          "\{anchor}<a anchor=\"\{refid}\">\{text}</a>"
        }
      }
    Some("ref") => "<a id=\"\{node.id.unwrap_or("")}\"></a>"
    Some("bibref") => {
      let id = node.id.unwrap_or("")
      let reftext = match node.reftext() {
        Some(r) => "[\{r}]"
        None => "[\{id}]"
      }
      let reftext = if session().bibref_refs.contains(id) {
        "<a anchor=\"_bibref_ref_\{id}\">\{reftext}</a>"
      } else {
        reftext
      }
      "<a id=\"\{id}\"></a>\{reftext}"
    }
    other => {
      unsupported("inline", "anchor type \{other.unwrap_or("none")}", node)
      ""
    }
  }
}

///|
/// The Font Awesome icon sets, in the order a `fa` icon name is looked up
/// (`FontAwesomeIconSets`), and all icon sets (`IconSets`).
let font_awesome_icon_sets : Array[String] = ["fab", "far", "fas"]

///|
let icon_set_names : Array[String] = ["fab", "far", "fas", "fi", "pf"]

///|
/// asciidoctor-pdf's `convert_inline_icon`: with `icons=font`, the icon's
/// glyph in its icon set's font (`name@set`, the `set` attribute, else
/// `icon-set`, default `fa`: a Font Awesome 4 name through the legacy
/// mapping, else the first Font Awesome set that has it; a `fas-` style
/// prefix names the set too), sized by the `size` attribute; otherwise, or
/// when the icon is unknown, the alt text in brackets.
fn convert_inline_icon(node : @core.Node) -> String {
  let doc = node.document()
  let alt = "[\{node.attr("alt").unwrap_or("")}&#93;"
  let icons = doc.attr("icons")
  let catalog : FontCatalog? = if icons == Some("font") {
    Some(document_catalog(doc)) catch {
      _ => None
    }
  } else {
    None
  }
  guard catalog is Some(catalog) && catalog.has_icons() else {
    if icons is Some(_) && icons != Some("font") {
      unsupported("inline", "image icon", node)
      return "[\{node.target.unwrap_or("")}&#93;"
    }
    if icons == Some("font") {
      unsupported("inline", "font icon (no icon fonts)", node)
    }
    return alt
  }
  let target = node.target.unwrap_or("")
  let (name0, set0, explicit) = match target.find("@") {
    Some(i) => (target[:i].to_owned(), target[i + 1:].to_owned(), true)
    None =>
      match node.attr("set") {
        Some(set) => (target, set, true)
        None => (target, doc.attr("icon-set").unwrap_or("fa"), false)
      }
  }
  let mut name = name0
  let mut set = set0
  let mut glyph : String? = None
  if set == "fa" || !icon_set_names.contains(set) {
    set = "fa"
    match catalog.legacy_icons.get("fa-\{name}") {
      Some(mapped) =>
        match mapped.find("-") {
          Some(i) => {
            set = mapped[:i].to_owned()
            name = mapped[i + 1:].to_owned()
            glyph = catalog.icon_glyph(set, name)
          }
          None => ()
        }
      None =>
        for candidate in font_awesome_icon_sets {
          match catalog.icon_glyph(candidate, name) {
            Some(g) => {
              set = candidate
              glyph = Some(g)
              break
            }
            None => ()
          }
        }
    }
  } else {
    glyph = catalog.icon_glyph(set, name)
  }
  if glyph is None &&
    !explicit &&
    icon_set_names.iter().any(s => name.has_prefix(s + "-")) {
    match name.find("-") {
      Some(i) => {
        set = name[:i].to_owned()
        name = name[i + 1:].to_owned()
        glyph = catalog.icon_glyph(set, name)
      }
      None => ()
    }
  }
  guard glyph is Some(glyph) else { return alt }
  let size_attr = match node.attr("size") {
    Some("lg") => " size=\"1.333em\""
    // `fw` sets a width Prawn's formatted text does not know
    Some("fw") => " width=\"1em\""
    Some(size) => " size=\"\{size.replace(old="x", new="em")}\""
    None => ""
  }
  let class_attr = match node.role() {
    Some(role) => " class=\"\{role}\""
    None => ""
  }
  "<font name=\"\{set}\"\{size_attr}\{class_attr}>\{glyph}</font>"
}

///|
/// asciidoctor-pdf's `breakable_uri`: a zero-width space after each `/`,
/// `?`, `&amp;` and `#` of the address (after the scheme's `://`) that is
/// not its last character, so a long URL can wrap there; but not one that
/// would leave a single character on the next line.
fn breakable_uri(uri : String) -> String {
  let (scheme, address) = match uri.find("://") {
    Some(i) => (uri[:i + 3].to_owned(), uri[i + 3:].to_owned())
    None => ("", uri)
  }
  if address.is_empty() {
    return uri
  }
  let sb = StringBuilder()
  let n = address.length()
  let mut i = 0
  while i < n {
    let matched = if address[i:].has_prefix("&amp;") {
      5
    } else if address[i] == '/' || address[i] == '?' || address[i] == '#' {
      1
    } else {
      0
    }
    if matched == 0 {
      sb.write_char(address[i].to_int().unsafe_to_char())
      i += 1
      continue
    }
    for k in 0..<matched {
      sb.write_char(address[i + k].to_int().unsafe_to_char())
    }
    i += matched
    if i < n {
      sb.write_char('\u{200b}')
    }
  }
  let broken = sb.to_string()
  let len = broken.length()
  let result = if len >= 2 && broken[len - 2] == 0x200B {
    broken[:len - 2].to_owned() + broken[len - 1:].to_owned()
  } else {
    broken
  }
  scheme + result
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
      let label = match session().footnote_labels.get(number) {
        Some(label) => label
        None => (number - session().rendered_footnotes).to_string()
      }
      "<sup class=\"wj\">\{anchor}[<a anchor=\"_footnotedef_\{index}\">\{label}</a>]</sup>"
    }
    None => {
      let color = document_theme(node)["role_unresolved_font_color"].to_ruby_s()
      "<sup class=\"wj\"><font color=\"\{color}\">[\{node.text().unwrap_or("")}]</font></sup>"
    }
  }
}

///|
/// asciidoctor-pdf's `convert_inline_button`: the text in the theme's
/// `button_content` (`%s` stands for the text).
fn convert_inline_button(node : @core.Node) -> String {
  let theme = document_theme(node)
  let content = value_str(theme["button_content"]).unwrap_or("%s")
  let text = node.text().unwrap_or("")
  let content = match content.find("%s") {
    Some(i) => content[:i].to_owned() + text + content[i + 2:].to_owned()
    None => content
  }
  "<button>\{content}</button>"
}

///|
/// asciidoctor-pdf's `convert_inline_callout`: the callout number's glyph
/// in the conum font and colour (the font is named, as callouts in code
/// are set in the code font).
fn convert_inline_callout(node : @core.Node) -> String {
  let theme = document_theme(node)
  let glyph = conum_glyph(node.text().unwrap_or("1"))
  let family = value_str(theme["conum_font_family"]).unwrap_or("")
  let result = "<font name=\"\{family}\">\{glyph}</font>"
  match theme["conum_font_color"] {
    Null | Bool(false) => result
    color => "<font color=\"\{color.to_ruby_s()}\">\{result}</font>"
  }
}

///|
/// asciidoctor-pdf's `convert_inline_kbd`: the keys joined by the theme's
/// `kbd_separator`.
fn convert_inline_kbd(node : @core.Node) -> String {
  let separator = value_str(document_theme(node)["kbd_separator"]).unwrap_or(
    "+",
  )
  match node.attributes.get("keys") {
    Some(List([key])) => "<kbd>\{key}</kbd>"
    Some(List(keys)) => keys.map(key => "<kbd>\{key}</kbd>").join(separator)
    _ => "<kbd>\{node.text().unwrap_or("")}</kbd>"
  }
}

///|
/// asciidoctor-pdf's `convert_inline_menu`: the menu, submenus and item
/// joined by the theme's `menu_caret_content`.
fn convert_inline_menu(node : @core.Node) -> String {
  let caret = value_str(document_theme(node)["menu_caret_content"]).unwrap_or(
    " \u{203a} ",
  )
  let menu = node.attr("menu").unwrap_or("")
  let submenus = match node.attributes.get("submenus") {
    Some(List(submenus)) => submenus
    _ => []
  }
  if !submenus.is_empty() {
    let parts = [menu, ..submenus, node.attr("menuitem").unwrap_or("")]
    "<menu>\{parts.join(caret)}</menu>"
  } else {
    match node.attr("menuitem") {
      Some(item) => "<menu>\{menu}\{caret}\{item}</menu>"
      None => "<menu>\{menu}</menu>"
    }
  }
}

///|
/// Run `body` with `state` the active session (and its theme), then make
/// the session that was active before active again: the hooks a document
/// gives its flows report, look up images and draw SVG in that document's
/// session whichever is active when they are called.
fn[T] with_session(state : Session, body : () -> T) -> T {
  let before = active_session.val
  let theme = current_theme.val
  activate(state)
  let result = body()
  active_session.val = before
  current_theme.val = theme
  result
}
