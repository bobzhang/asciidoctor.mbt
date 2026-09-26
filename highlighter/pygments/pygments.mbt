// Server-side syntax highlighting with Pygments: a port of Ruby Asciidoctor's
// lib/asciidoctor/syntax_highlighter/pygments.rb on top of bobzhang/pygments
// (the MoonBit port of Python Pygments), in place of pygments.rb, which runs
// Python Pygments in a subprocess.
//
// The adapter is optional: `register()` installs it for the `pygments` name
// in the core highlighter registry, replacing the "pygments.rb is not
// available" fallback.

///|
let default_style : String = "default"

///|
let base_selector : String = "pre.pygments"

///|
let token_class_prefix : String = "tok-"

///|
let base_style_rx : @regex.Regex = @regex.re("^pre\\.pygments +\\{([^}]+?)\\}")

///|
let code_cell_start_tag_cs : String = "<td class=\"code\">"

///|
let legacy_lineno_span_start_tag_cs : String = "<span class=\"lineno\">"

///|
let legacy_lineno_span_tag_rx : @regex.Regex = @regex.re(
  "<span class=\"lineno\">( *\\d+) ?</span>",
)

///|
let lineno_column_start_tags_cs : String = "<td class=\"linenos\"><div class=\"linenodiv\"><pre>"

///|
let lineno_span_tag_cs : String = "<span class=\"linenos\">\\1</span>"

///|
let pre_tag_cs : String = "<pre>\\1</pre>"

///|
let styled_lineno_column_start_tags_rx : @regex.Regex = @regex.re(
  "<td><div class=\"linenodiv\" style=\"[^\"]+?\"><pre style=\"[^\"]+?\">",
)

///|
let styled_lineno_span_tag_rx : @regex.Regex = @regex.re(
  "(?<=^|<span></span>)<span style=\"[^\"]+\">( *\\d+) ?</span>",
)

///|
/// Doesn't appear in the output; Pygments appends "table" to this value to
/// make the class of the nested table.
let wrapper_class : String = "lineno"

///|
/// NOTE `<pre>` has a style attribute when pygments-css=style; `<div>` has a
/// trailing newline when pygments-linenums-mode=table; the initial
/// `<span></span>` preserves leading blank lines.
let wrapper_tag_rx : @regex.Regex = @regex.re(
  "<div class=\"\{wrapper_class}\"><pre\\b[^>]*?>(.*)</pre></div>\\n*",
  flags="m",
)

///|
/// The Pygments syntax highlighter adapter (Ruby `PygmentsAdapter`). One
/// instance is created per document.
priv struct PygmentsAdapter {
  name : String
  mut requires_stylesheet : Bool
  mut style : String?
}

///|
/// Creates a Pygments adapter registered under `name` (the `<pre>` class and
/// the prefix of the `<name>-css`, `<name>-style` and `<name>-linenums-mode`
/// attributes).
pub fn adapter(name? : String = "pygments") -> &@core.SyntaxHighlighter {
  ({ name, requires_stylesheet: false, style: None, } : PygmentsAdapter)
}

///|
/// Registers the adapter for the `pygments` source highlighter (Ruby
/// `register_for 'pygments'`), replacing the core's "library not available"
/// fallback.
pub fn register() -> Unit {
  @core.register_syntax_highlighter(["pygments"], (name, _backend, _doc) => {
    Some(adapter(name~))
  })
}

///|
impl @core.SyntaxHighlighter for PygmentsAdapter with fn name(self) {
  self.name
}

///|
impl @core.SyntaxHighlighter for PygmentsAdapter with fn handles_highlighting(
  _self,
) {
  true
}

///|
impl @core.SyntaxHighlighter for PygmentsAdapter with fn highlight(
  self,
  node,
  source,
  lang,
  opts,
) {
  let (lexer_name, lexer_alias) = match lang.bind(find_lexer_by_alias) {
    Some(l) => l
    None => find_lexer_by_mimetype("text/plain")
  }
  let noclasses = opts.css_mode != "class"
  if !noclasses {
    self.requires_stylesheet = true
  }
  let style = match self.style {
    Some(s) => s
    None => {
      let s = available_style(opts.style)
      self.style = Some(s)
      s
    }
  }
  let highlight_opts : Map[String, String] = {
    "classprefix": token_class_prefix,
    "cssclass": wrapper_class,
    "nobackground": "True",
    "noclasses": py_bool(noclasses),
    "startinline": py_bool(lexer_name == "PHP" && !node.has_option("mixed")),
    "stripnl": "False",
    "style": style,
  }
  match opts.highlight_lines {
    Some(lines) =>
      highlight_opts["hl_lines"] = lines.map(l => l.to_string()).join(" ")
    None => ()
  }
  let linenos = opts.number_lines
  match (linenos, opts.start_line_number) {
    (Some(mode), Some(start)) => {
      highlight_opts["linenostart"] = start.to_string()
      highlight_opts["linenos"] = mode
    }
    _ => ()
  }
  if highlight_opts.get("linenos") == Some("table") {
    guard pygments_highlight(source, lexer_alias, highlight_opts)
      is Some(highlighted) else {
      // handles a failure of Pygments like a nil response from pygments.rb
      return (node.sub_source(source, false), None)
    }
    let highlighted = if noclasses {
      styled_lineno_column_start_tags_rx.sub(
        highlighted, lineno_column_start_tags_cs,
      )
    } else {
      highlighted
    }
    let highlighted = wrapper_tag_rx.sub(highlighted, pre_tag_cs)
    if opts.callouts is Some(_) {
      (
        highlighted,
        highlighted
        .find(code_cell_start_tag_cs)
        .map(idx => idx + code_cell_start_tag_cs.length()),
      )
    } else {
      (highlighted, None)
    }
  } else {
    guard pygments_highlight(source, lexer_alias, highlight_opts)
      is Some(highlighted) else {
      return (node.sub_source(source, false), None)
    }
    let highlighted = if linenos is Some(_) {
      if noclasses {
        styled_lineno_span_tag_rx.gsub(highlighted, lineno_span_tag_cs)
      } else if highlighted.contains(legacy_lineno_span_start_tag_cs) {
        legacy_lineno_span_tag_rx.gsub(highlighted, lineno_span_tag_cs)
      } else {
        highlighted
      }
    } else {
      highlighted
    }
    (wrapper_tag_rx.sub(highlighted, "\\1"), None)
  }
}

///|
impl @core.SyntaxHighlighter for PygmentsAdapter with fn format(
  self,
  node,
  lang,
  opts,
) {
  let pre_style = if opts.css_mode != Some("class") {
    let style = available_style(opts.style)
    self.style = Some(style)
    base_style(style)
  } else {
    None
  }
  @core.format_source(self.name, node, lang, opts.nowrap, pre_style?)
}

///|
impl @core.SyntaxHighlighter for PygmentsAdapter with fn has_docinfo(
  self,
  location,
) {
  self.requires_stylesheet && location == "head"
}

///|
impl @core.SyntaxHighlighter for PygmentsAdapter with fn docinfo(
  self,
  _location,
  doc,
  opts,
) {
  if opts.linkcss {
    let href = doc.normalize_web_path(
      stylesheet_basename(self.style),
      start?=doc.attr("stylesdir"),
      preserve_uri_target=false,
    )
    "<link rel=\"stylesheet\" href=\"\{href}\"\{opts.self_closing_tag_slash}>"
  } else {
    "<style>\n\{read_stylesheet(self.style)}\n</style>"
  }
}

///|
impl @core.SyntaxHighlighter for PygmentsAdapter with fn writes_stylesheet(
  self,
  _doc,
) {
  self.requires_stylesheet
}

///|
impl @core.SyntaxHighlighter for PygmentsAdapter with fn write_stylesheet(
  self,
  _doc,
) {
  [(stylesheet_basename(self.style), read_stylesheet(self.style))]
}

///|
fn py_bool(b : Bool) -> String {
  if b {
    "True"
  } else {
    "False"
  }
}

///|
/// Highlights `source` with the HTML formatter like pygments.rb's
/// `Pygments.highlight` (options go to both the lexer and the formatter; the
/// result is right-stripped; empty source is returned as is). `None` when
/// Pygments fails.
fn pygments_highlight(
  source : String,
  lexer_alias : String,
  options : Map[String, String],
) -> String? {
  if source == "" {
    return Some(source)
  }
  let options = options.copy()
  options["outencoding"] = "utf-8"
  let html = @py.highlight(
    source,
    @py.get_lexer_by_name(lexer_alias, options~),
    @py.get_formatter_by_name("html", options~),
  ) catch {
    _ => return None
  }
  Some(@rb.rstrip(html))
}

// ---------------------------------------------------------------------------
// Lexer lookup (pygments.rb `Pygments::Lexer`)

///|
/// Lexers by alias (pygments.rb `Lexer.find_by_alias`: exact, case-sensitive
/// match; a later lexer wins), as (name, first alias).
let alias_index : Map[String, (String, String)] = Map([])

///|
fn build_alias_index() -> Unit {
  if !alias_index.is_empty() {
    return
  }
  for entry in @py_lexers.all_lexers {
    let info = entry.0
    if info.aliases.is_empty() {
      continue
    }
    for a in info.aliases {
      alias_index[a] = (info.name, info.aliases[0])
    }
  }
}

///|
fn find_lexer_by_alias(lang : String) -> (String, String)? {
  build_alias_index()
  alias_index.get(lang)
}

///|
/// pygments.rb `Lexer.find_by_mimetype` (a later lexer wins).
fn find_lexer_by_mimetype(mimetype : String) -> (String, String) {
  let mut found = ("Text only", "text")
  for entry in @py_lexers.all_lexers {
    let info = entry.0
    if info.mimetypes.contains(mimetype) && !info.aliases.is_empty() {
      found = (info.name, info.aliases[0])
    }
  }
  found
}

// ---------------------------------------------------------------------------
// Styles (Ruby `PygmentsAdapter::Styles`)

///|
let stylesheet_cache : Map[String, String?] = Map([])

///|
let base_style_cache : Map[String, String] = Map([])

///|
/// The style name if Pygments provides it (Ruby `style_available?`),
/// otherwise the default style.
fn available_style(style : String?) -> String {
  match style {
    Some(s) if @py_styles.get_all_styles().contains(s) => s
    _ => default_style
  }
}

///|
/// The stylesheet for the tokens of the Pygments style (default: "default"),
/// scoped to `pre.pygments` with the `tok-` class prefix (Ruby
/// `PygmentsAdapter.read_stylesheet`).
pub fn read_stylesheet(style : String?) -> String {
  stylesheet(style.unwrap_or(default_style)).unwrap_or(
    "/* Failed to load Pygments CSS. */",
  )
}

///|
/// The file name of the stylesheet for the style (Ruby
/// `PygmentsAdapter.stylesheet_basename`): `pygments-<style>.css`.
pub fn stylesheet_basename(style : String?) -> String {
  "pygments-\{style.unwrap_or(default_style)}.css"
}

///|
/// pygments.rb `Pygments.css('pre.pygments', classprefix: 'tok-', style:)`,
/// starting at the first `pre.pygments` rule.
fn stylesheet(style : String) -> String? {
  match stylesheet_cache.get(style) {
    Some(Some(s)) => return Some(s)
    _ => ()
  }
  let css = @py.get_formatter_by_name("html", options={
    "classprefix": token_class_prefix,
    "style": style,
  }).get_style_defs(arg=base_selector) catch {
    _ => return None
  }
  let css = @rb.rstrip(css)
  let css = if css.has_prefix(base_selector) {
    css
  } else {
    match css.find(base_selector) {
      Some(i) => @rb.from(css, i)
      None => css
    }
  }
  stylesheet_cache[style] = Some(css)
  Some(css)
}

///|
/// The declarations of the `pre.pygments` rule of the style (Ruby
/// `base_style`), used as the style attribute of `<pre>` in inline CSS mode.
fn base_style(style : String) -> String? {
  match base_style_cache.get(style) {
    Some(s) => return Some(s)
    None => ()
  }
  guard stylesheet(style) is Some(css) else { return None }
  guard base_style_rx.find(css) is Some(m) else { return None }
  let s = @rb.strip(m.at(1))
  base_style_cache[style] = s
  Some(s)
}
