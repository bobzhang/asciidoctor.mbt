///|
// `source-highlighter: pygments`, as asciidoctor-pdf drives pygments.rb:
// the HTML Pygments writes for a block (inline styles, no wrapper),
// parsed as formatted text, and the block's colours from the style's CSS
// (Pygments::Ext::BlockStyles). Pygments itself is optional: the package
// bobzhang/asciidoctor-pdf/pygments registers it (`register_pygments`).

///|
/// What source highlighting needs from Pygments.
pub(all) struct PygmentsBackend {
  /// pygments.rb's `Lexer.find_by_alias`: the name and first alias of the
  /// lexer with this alias, if any
  find_lexer : (String) -> (String, String)?
  /// the lexer for a MIME type (`Lexer.find_by_mimetype`), as above
  find_lexer_by_mimetype : (String) -> (String, String)?
  /// `Pygments.highlight(code, lexer:, options:)` with the lexer of this
  /// alias: the source as HTML with
  /// the HTML formatter (options go to the lexer and the formatter alike),
  /// right-stripped; None when Pygments fails
  highlight : (String, String, Map[String, String]) -> String?
  /// `Pygments.css(selector, style:)`: the style's CSS for `selector`
  css : (String, String) -> String
  /// `Pygments.styles`: the names of the styles
  styles : () -> Array[String]
}

///|
let pygments_backend : Ref[PygmentsBackend?] = { val: None, }

///|
/// Make Pygments available to `source-highlighter: pygments` (the package
/// bobzhang/asciidoctor-pdf/pygments does this with bobzhang/pygments).
pub fn register_pygments(backend : PygmentsBackend) -> Unit {
  pygments_backend.val = Some(backend)
}

///|
/// The colours of a block in a Pygments style (`BlockStyles.for`):
/// background and text from the style's `.highlight` rule, and the
/// background of highlighted lines (`.hll`); six-digit colours only.
priv struct PygmentsBlockStyle {
  background : Color?
  font_color : Color?
  highlight : Color?
}

///|
let pygments_block_styles : Map[String, PygmentsBlockStyle] = Map([])

///|
let block_selector_rx : @regex.Regex = @regex.re(
  "^\\.highlight *\\{([^}]+?)\\}",
)

///|
let highlight_background_rx : @regex.Regex = @regex.re(
  "^\\.highlight +\\.hll +\\{ *background(?:-color)?: *#(\\h{6})",
)

///|
let color_properties_rx : @regex.Regex = @regex.re(
  "(?:^|;) *(background(?:-color)?|color): *#?(\\h{6}) *(?=$|;)",
)

///|
fn pygments_block_style(
  backend : PygmentsBackend,
  style : String,
) -> PygmentsBlockStyle {
  match pygments_block_styles.get(style) {
    Some(s) => return s
    None => ()
  }
  let css = (backend.css)(".highlight", style)
  let mut background = None
  let mut font_color = None
  match block_selector_rx.find(css) {
    Some(m) =>
      for p in color_properties_rx.find_all(m.group(1).unwrap_or("")) {
        let value = parse_color(p.group(2).unwrap_or(""))
        if p.group(1) == Some("color") {
          font_color = value
        } else {
          background = value
        }
      }
    None => ()
  }
  let highlight = highlight_background_rx
    .find(css)
    .bind(m => parse_color(m.group(1).unwrap_or("")))
  let s = { background, font_color, highlight, }
  pygments_block_styles[style] = s
  s
}

///|
/// The fragments of a source block highlighted by Pygments (the `pygments`
/// branch of asciidoctor-pdf's `convert_code`), the block's background and
/// text colour, and whether the line numbers need SourceWrap.
fn pygments_chunks(
  backend : PygmentsBackend,
  node : @core.Node,
  source : String,
  callouts : Bool,
  conums : Conums?,
  base : Style,
) -> (Array[Fragment], Color?, Color?, Bool) {
  let doc = node.document()
  let style = match doc.attr("pygments-style") {
    Some(s) if (backend.styles)().contains(s) => s
    _ => "pastie"
  }
  let block = pygments_block_style(backend, style)
  let base = match block.font_color {
    Some(c) => { ..base, color: c, }
    None => base
  }
  if source == "" {
    return ([], block.background, block.font_color, false)
  }
  let language = node.attr("language").unwrap_or("text")
  let lexer = match (backend.find_lexer)(language) {
    Some(l) => Some(l)
    None => (backend.find_lexer_by_mimetype)("text/plain")
  }
  let options : Map[String, String] = {
    "nowrap": "True",
    "noclasses": "True",
    "stripnl": "False",
    "style": style,
  }
  if lexer is Some(("PHP", _)) {
    options["startinline"] = if node.has_option("mixed") {
      "False"
    } else {
      "True"
    }
  }
  let (source, conums) = if callouts {
    extract_conums(source)
  } else {
    (source, conums)
  }
  // a lexer that fails leaves the source as it is (escaped)
  let html = match lexer {
    Some((_, alias_)) =>
      match (backend.highlight)(source, alias_, options) {
        Some(h) => h
        None => node.apply_subs(source, [SpecialCharacters])
      }
    None => node.apply_subs(source, [SpecialCharacters])
  }
  let highlight_lines = match node.attr("highlight") {
    Some(spec) => {
      let lines = @core.resolve_lines_to_highlight(source, spec)
      if lines.is_empty() {
        None
      } else {
        let m : Map[Int, Color] = Map([])
        for l in lines {
          m[l] = block.highlight.unwrap_or(rgb_hex(0xFFFFCC))
        }
        Some(m)
      }
    }
    None => None
  }
  let linenums = if node.has_option("linenums") || node.has_attr("linenums") {
    Some(ruby_to_i(node.attr("start").unwrap_or("1")))
  } else {
    None
  }
  let fragments = parse_formatted(html, base, normalize=false)
  let fragments = if linenums is Some(_) ||
    conums is Some(_) ||
    highlight_lines is Some(_) {
    restore_conums(
      fragments,
      conums,
      base,
      linenums?,
      highlight?=highlight_lines,
    )
  } else {
    fragments
  }
  (
    guard_indentation_in_fragments(fragments),
    block.background,
    block.font_color,
    linenums is Some(_),
  )
}
