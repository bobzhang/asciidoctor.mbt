///|
// Source highlighting in asciidoctor-pdf's `convert_code`: which
// highlighter a block gets, the source it is given (the block's
// substitutions set aside, callouts taken out), and the fragments that
// come back (Rouge: highlight_rouge.mbt, Pygments: highlight_pygments.mbt).

///|
/// The fragments a code block is typeset from, the background and text
/// colour the highlighter gives the block (over the theme's), and whether
/// its line numbers wrap as asciidoctor-pdf's SourceWrap does; `highlighted`
/// when a highlighter made the fragments (none at all is then no line).
priv struct CodeChunks {
  fragments : Array[Fragment]
  background : Color?
  font_color : Color?
  source_wrap : Bool
  highlighted : Bool
}

///|
/// The server-side highlighter of a source block (`syntax_highlighter.name`
/// when it highlights): rouge, pygments or coderay.
fn source_highlighter(node : @core.Node) -> String? {
  guard node.style == Some("source") else { return None }
  match node.document().syntax_highlighter() {
    Some(hl) =>
      match hl.name() {
        "rouge" | "pygments" | "coderay" as name => Some(name)
        _ => None
      }
    None => None
  }
}

///|
/// The fragments of a code block, as `convert_code` makes them: with a
/// highlighter, the source without the block's specialcharacters (or
/// highlight) and callouts substitutions is highlighted and the callouts
/// restored; otherwise the content with its indentation guarded, parsed as
/// formatted text unless `plain`.
fn Converter::code_chunks(
  self : Converter,
  node : @core.Node,
  base : Style,
  plain? : Bool = false,
) -> CodeChunks {
  let none = fn(text : String) -> CodeChunks {
    let fragments = if plain {
      [({ text, style: base, anchor: None, } : Fragment)]
    } else {
      parse_formatted(text, base, normalize=false)
    }
    {
      fragments,
      background: None,
      font_color: None,
      source_wrap: false,
      highlighted: false,
    }
  }
  guard source_highlighter(node) is Some(highlighter) else {
    return none(guard_indentation(node.content()))
  }
  let highlighter = match highlighter {
    "pygments" if pygments_backend.val is None => {
      unsupported(
        "attribute", "source-highlighter=pygments (Pygments not registered)", node,
      )
      None
    }
    "coderay" => {
      unsupported("attribute", "source-highlighter=coderay", node)
      None
    }
    h => Some(h)
  }
  let saved_subs = node.subs.copy()
  let mut callouts = node.subs.contains(Callouts)
  // the substitution the highlighter replaces: highlight, which the core
  // puts in place of specialcharacters when the document's highlighter
  // highlights, else specialcharacters itself
  let highlight_idx = match node.subs.search(Highlight) {
    Some(i) => Some(i)
    None => node.subs.search(SpecialCharacters)
  }
  guard highlighter is Some(highlighter) &&
    !self.flow.scratch &&
    highlight_idx is Some(highlight_idx) else {
    if highlight_idx is Some(i) {
      node.subs[i] = SpecialCharacters
    }
    let chunks = none(guard_indentation(node.content()))
    node.subs = saved_subs
    return chunks
  }
  let mut conums : Conums? = None
  let only_highlighting = node.subs
    .mapi((i, s) => i == highlight_idx || s == Callouts)
    .iter()
    .all(x => x)
  let source = if only_highlighting {
    node.subs = []
    expand_tabs(node.content())
  } else {
    // other substitutions apply: the callouts are taken out of the raw
    // source first, then the content (with specialcharacters) is turned
    // back into plain text
    let saved_lines = if callouts {
      let saved_lines = node.lines.copy()
      node.subs = node.subs.filter(s => s != Callouts)
      let previous = node.subs.copy()
      node.subs = []
      let (text, mapping) = extract_conums(node.content())
      conums = mapping
      node.lines = text.split("\n").map(l => l.to_owned()).collect()
      node.subs = previous
      callouts = false
      Some(saved_lines)
    } else {
      None
    }
    if highlight_idx < node.subs.length() {
      node.subs[highlight_idx] = SpecialCharacters
    }
    let text = node.content()
    let text = if text == "" {
      text
    } else {
      expand_tabs(unescape_xml(strip_markup(text)))
    }
    match saved_lines {
      Some(lines) => node.lines = lines
      None => ()
    }
    text
  }
  node.subs = saved_subs
  match highlighter {
    "rouge" => self.rouge_chunks(node, source, callouts, conums, base)
    _ =>
      match pygments_backend.val {
        Some(backend) => {
          let (fragments, background, font_color, source_wrap) = pygments_chunks(
            backend, node, source, callouts, conums, base,
          )
          { fragments, background, font_color, source_wrap, highlighted: true, }
        }
        None => none(guard_indentation(source))
      }
  }
}

///|
/// asciidoctor-pdf's `SanitizeXMLRx`: a tag, with a NUL that follows it.
let sanitize_xml_rx : @regex.Regex = @regex.re("<[^>]+>\\u0000?")

///|
/// asciidoctor-pdf's `CharRefRx`.
let char_ref_rx : @regex.Regex = @regex.re(
  "&(?:amp;)?(?:([a-z][a-z]+\\d{0,2})|#(?:(\\d\\d\\d{0,4})|x(\\h\\h\\h{0,3})));",
)

///|
/// The text of formatted text without its tags (asciidoctor-pdf's
/// `sanitize` with `compact: false`): every complete tag removed, with a
/// NUL that follows it (a `<` that opens no tag stays), then the
/// character references decoded (an unknown name becomes `?`).
fn strip_markup(text : String) -> String {
  let text = if text.contains("<") {
    sanitize_xml_rx.replace(text, _ => "")
  } else {
    text
  }
  if !text.contains("&") {
    return text
  }
  char_ref_rx.replace(text, m => {
    match m.group(1) {
      Some(name) =>
        match name {
          "amp" => "&"
          "apos" => "'"
          "gt" => ">"
          "lt" => "<"
          "nbsp" => " "
          "quot" => "\""
          _ => "?"
        }
      None => {
        let code = match m.group(2) {
          Some(dec) => @string.parse_int(dec) catch { _ => 0x3F }
          None =>
            @string.parse_int(m.group(3).unwrap_or("3f"), base=16) catch {
              _ => 0x3F
            }
        }
        code_to_string(code)
      }
    }
  })
}

///|
/// asciidoctor-pdf's `unescape_xml`: `&lt;`, `&gt;` and `&amp;` decoded.
fn unescape_xml(text : String) -> String {
  if !text.contains("&") {
    return text
  }
  text
  .replace_all(old="&lt;", new="<")
  .replace_all(old="&gt;", new=">")
  .replace_all(old="&amp;", new="&")
}

///|
/// The lexer asciidoctor-pdf picks for a source block's `language`: a
/// language with cgi-style options (`php?start_inline=1`) through
/// `find_fancy`, else by name; PHP starts inline unless the block has the
/// `mixed` option (or the options say); plain text when unknown.
fn rouge_lexer(node : @core.Node) -> @rouge.Lexer {
  let mixed = node.has_option("mixed")
  let lexer = match node.attr("language") {
    Some(lang) if lang.contains("?") =>
      match @rouge.find_fancy(lang) {
        Some(l) if l.tag == "php" &&
          !mixed &&
          !l.options.contains("start_inline") => {
          let options = l.options.copy()
          options["start_inline"] = ""
          @rouge.find("php").map(f => f(options))
        }
        l => l
      }
    Some(lang) =>
      match @rouge.find(lang) {
        Some(f) => {
          let l = f(Map([]))
          if l.tag == "php" && !mixed {
            Some(f({ "start_inline": "" }))
          } else {
            Some(l)
          }
        }
        None => None
      }
    None => None
  }
  match lexer {
    Some(l) => l
    None => @rouge.plain_text(Map([]))
  }
}

///|
/// The `rouge` branch of `convert_code`.
fn Converter::rouge_chunks(
  _self : Converter,
  node : @core.Node,
  source : String,
  callouts : Bool,
  conums : Conums?,
  base : Style,
) -> CodeChunks {
  let session = session()
  let formatter = match session.rouge_formatter {
    Some(f) => f
    None => {
      let f = RougeFormatter::new(node.document().attr("rouge-style"))
      session.rouge_formatter = Some(f)
      f
    }
  }
  let background = formatter.block_background()
  if source == "" {
    return {
      fragments: [],
      background,
      font_color: None,
      source_wrap: false,
      highlighted: true,
    }
  }
  let line_numbers = node.has_option("linenums") || node.has_attr("linenums")
  let start_line = if line_numbers {
    ruby_to_i(node.attr("start").unwrap_or("1"))
  } else {
    1
  }
  let lexer = rouge_lexer(node)
  let (source, conums) = if callouts {
    extract_conums(source)
  } else {
    (source, conums)
  }
  let highlight_lines = match node.attr("highlight") {
    Some(spec) => {
      let lines = @core.resolve_lines_to_highlight(source, spec)
      if lines.is_empty() {
        None
      } else {
        let m : Map[Int, Bool] = Map([])
        for l in lines {
          m[l] = true
        }
        Some(m)
      }
    }
    None => None
  }
  let fragments = formatter.format(
    base,
    lexer.tokens(source),
    line_numbers~,
    start_line~,
    highlight_lines?,
  )
  let fragments = match conums {
    Some(_) => restore_conums(fragments, conums, base)
    None => fragments
  }
  {
    fragments,
    background,
    font_color: None,
    source_wrap: line_numbers,
    highlighted: true,
  }
}
