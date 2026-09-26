// Syntax highlighter adapters (Ruby syntax_highlighter.rb and the client-side
// adapters highlightjs.rb, prettify.rb, html_pipeline.rb).

///|
/// Callout marks extracted from the source of a source block, indexed by
/// 1-based line number: the (guard, numeral) pairs of the callouts on that
/// line, in order (Ruby `extract_callouts`). The guard is `Nil`, the line
/// comment prefix (`Str`) or `List(["<!--", "-->"])` for XML callouts.
pub type CalloutMarks = Map[Int, Array[(AttrVal, String)]]

///|
/// Options passed to `SyntaxHighlighter::highlight` (Ruby's opts Hash).
pub(all) struct HighlightOptions {
  /// Callouts extracted from the source (`None` when there are none or
  /// callouts are not processed). An adapter may remove the entries it
  /// handles itself; the remaining ones are restored after highlighting.
  callouts : CalloutMarks?
  /// The CSS mode (`<name>-css` attribute, default `"class"`).
  css_mode : String
  /// 1-based line numbers to highlight (`highlight` attribute).
  highlight_lines : Array[Int]?
  /// `"table"` or `"inline"` (`<name>-linenums-mode`) when lines are numbered.
  number_lines : String?
  /// The first line number (when lines are numbered).
  start_line_number : Int?
  /// The style (theme) name (`<name>-style` attribute).
  style : String?
}

///|
/// Creates highlight options (defaults as Ruby's opts Hash with no entries,
/// except `css_mode`, which Asciidoctor always sets).
pub fn HighlightOptions::new(
  callouts? : CalloutMarks,
  css_mode? : String = "class",
  highlight_lines? : Array[Int],
  number_lines? : String,
  start_line_number? : Int,
  style? : String,
) -> HighlightOptions {
  {
    callouts,
    css_mode,
    highlight_lines,
    number_lines,
    start_line_number,
    style,
  }
}

///|
/// Options passed to `SyntaxHighlighter::format`.
pub(all) struct FormatOptions {
  /// Whether wrapping is disabled (the `nowrap` option or no `prewrap`).
  nowrap : Bool
  /// The CSS mode (only set when the adapter highlights on the server).
  css_mode : String?
  /// The style name (only set when the adapter highlights on the server).
  style : String?
}

///|
pub fn FormatOptions::new(
  nowrap? : Bool = false,
  css_mode? : String,
  style? : String,
) -> FormatOptions {
  { nowrap, css_mode, style, }
}

///|
/// Options passed to `SyntaxHighlighter::docinfo`.
pub(all) struct DocinfoOptions {
  /// Whether stylesheets should be linked instead of embedded.
  linkcss : Bool
  /// The base URL for assets loaded from the CDN.
  cdn_base_url : String
  /// `"/"` if the converter emits self-closing tags, otherwise `""`.
  self_closing_tag_slash : String
}

///|
pub fn DocinfoOptions::new(
  linkcss? : Bool = false,
  cdn_base_url? : String = "https://cdnjs.cloudflare.com/ajax/libs",
  self_closing_tag_slash? : String = "",
) -> DocinfoOptions {
  { linkcss, cdn_base_url, self_closing_tag_slash, }
}

///|
/// A syntax highlighter adapter (Ruby `SyntaxHighlighter`).
///
/// A server-side adapter returns `true` from `handles_highlighting` (Ruby
/// `highlight?`); `highlight` then handles the `specialcharacters`
/// substitution of source blocks. A client-side adapter only formats the
/// block and inserts docinfo markup. Every method but `name` has a default
/// (Ruby `SyntaxHighlighter::Base`).
pub(open) trait SyntaxHighlighter {
  /// The name used in messages and attribute names (e.g. `pygments-style`).
  fn name(Self) -> String
  /// Whether the adapter highlights the source (Ruby `highlight?`).
  fn handles_highlighting(Self) -> Bool = _
  /// Highlights the raw source of a source block (node, source, language,
  /// options) and returns the highlighted source together with an optional
  /// offset: when the highlighted source contains markup before the first
  /// source line (e.g. a line number column), the offset of the first line.
  /// Callouts are restored to the lines after the offset.
  fn highlight(Self, Node, String, String?, HighlightOptions) -> (String, Int?) = _
  /// Wraps the converted source block in `<pre>`/`<code>` (Ruby `format`).
  fn format(Self, Node, String?, FormatOptions) -> String = _
  /// Whether docinfo is emitted at the location (`head` or `footer`).
  fn has_docinfo(Self, String) -> Bool = _
  /// Docinfo markup for the location (location, document, options).
  fn docinfo(Self, String, Node, DocinfoOptions) -> String = _
  /// Whether the adapter wants a stylesheet written next to the output when
  /// `linkcss` and `copycss` are set (Ruby `write_stylesheet?`).
  fn writes_stylesheet(Self, Node) -> Bool = _
  /// The stylesheet files to write (Ruby `write_stylesheet`), as (file name
  /// relative to the stylesheet output directory, contents). The core is
  /// pure, so the file-system driver (`@io`) writes them.
  fn write_stylesheet(Self, Node) -> Array[(String, String)] = _
}

///|
impl SyntaxHighlighter with fn handles_highlighting(_self) {
  false
}

///|
impl SyntaxHighlighter with fn highlight(_self, node, source, _lang, opts) {
  (node.sub_source(source, opts.callouts is Some(_)), None)
}

///|
impl SyntaxHighlighter with fn format(self, node, lang, opts) {
  format_source(self.name(), node, lang, opts.nowrap)
}

///|
impl SyntaxHighlighter with fn has_docinfo(_self, _location) {
  false
}

///|
impl SyntaxHighlighter with fn docinfo(_self, _location, _doc, _opts) {
  ""
}

///|
impl SyntaxHighlighter with fn writes_stylesheet(_self, _doc) {
  false
}

///|
impl SyntaxHighlighter with fn write_stylesheet(_self, _doc) {
  []
}

///|
/// Ruby `SyntaxHighlighter::Base#format`: wraps the converted content of
/// `node` in `<pre class="<pre_class> highlight"><code data-lang="<lang>">`.
/// `pre_style` adds a `style` attribute to the `<pre>` element (the Ruby
/// `:transform` hook used by the Pygments and Rouge adapters).
pub fn format_source(
  pre_class : String,
  node : Node,
  lang : String?,
  nowrap : Bool,
  pre_style? : String,
) -> String {
  let class_attr_val = if nowrap {
    "\{pre_class} highlight nowrap"
  } else {
    "\{pre_class} highlight"
  }
  let style_attr = match pre_style {
    Some(s) => " style=\"\{s}\""
    None => ""
  }
  let data_lang = match lang {
    Some(l) => " data-lang=\"\{l}\""
    None => ""
  }
  "<pre class=\"\{class_attr_val}\"\{style_attr}><code\{data_lang}>\{node.content()}</code></pre>"
}

///|
pub type SyntaxHighlighterFactory = (String, String, Node) -> &SyntaxHighlighter?

///|
let syntax_highlighter_registry : Map[String, SyntaxHighlighterFactory] = {
  "highlightjs": (_, _, _) => Some(ClientHighlighter::new(HighlightJs)),
  "highlight.js": (_, _, _) => Some(ClientHighlighter::new(HighlightJs)),
  "prettify": (_, _, _) => Some(ClientHighlighter::new(Prettify)),
  "html-pipeline": (_, _, _) => Some(ClientHighlighter::new(HtmlPipeline)),
  // server-side highlighters behave as in Ruby when their gem is missing;
  // an optional package (e.g. highlighter/pygments) replaces the entry
  "rouge": (_, _, _) => Some(ClientHighlighter::new(Unavailable("rouge"))),
  "coderay": (_, _, _) => Some(ClientHighlighter::new(Unavailable("coderay"))),
  "pygments": (_, _, _) => Some(ClientHighlighter::new(Unavailable("pygments"))),
}

///|
fn warn_unavailable(name : String) -> Unit {
  if !once_per_process("unavailable:\{name}") {
    return
  }
  let msg = match name {
    "pygments" =>
      "optional gem 'pygments.rb' is not available (reason: cannot load 'pygments'). Functionality disabled."
    _ => "optional gem '\{name}' is not available. Functionality disabled."
  }
  log_warn(msg)
}

///|
priv enum ClientKind {
  HighlightJs
  Prettify
  HtmlPipeline
  Unavailable(String) // rouge, coderay, pygments without their Ruby gems
}

///|
/// Client-side syntax highlighter adapters (highlight.js, prettify, html-pipeline).
priv struct ClientHighlighter {
  kind : ClientKind
}

///|
fn ClientHighlighter::new(kind : ClientKind) -> &SyntaxHighlighter {
  ({ kind, } : ClientHighlighter)
}

///|
impl SyntaxHighlighter for ClientHighlighter with fn name(self) {
  match self.kind {
    HighlightJs => "highlightjs"
    Prettify => "prettify"
    HtmlPipeline => "html-pipeline"
    Unavailable(n) => n
  }
}

///|
impl SyntaxHighlighter for ClientHighlighter with fn has_docinfo(
  self,
  _location,
) {
  match self.kind {
    HtmlPipeline | Unavailable(_) => false
    _ => true
  }
}

///|
impl SyntaxHighlighter for ClientHighlighter with fn format(
  self,
  node,
  lang,
  opts,
) {
  let nowrap = opts.nowrap
  let data_lang = match lang {
    Some(l) => " data-lang=\"\{l}\""
    None => ""
  }
  match self.kind {
    Unavailable(n) => {
      warn_unavailable(n)
      format_source(
        if n == "coderay" {
          "CodeRay"
        } else {
          n
        },
        node,
        lang,
        nowrap,
      )
    }
    HtmlPipeline => {
      let lang_attr = match lang {
        Some(l) => " lang=\"\{l}\""
        None => ""
      }
      "<pre\{lang_attr}><code>\{node.content()}</code></pre>"
    }
    HighlightJs => {
      let mut pre_class = if nowrap {
        "highlightjs highlight nowrap"
      } else {
        "highlightjs highlight"
      }
      if node.has_attr("nohighlight-option") {
        pre_class = pre_class.replace(old=" highlight", new="")
      }
      let code_class = "language-\{lang.unwrap_or("none")} hljs"
      "<pre class=\"\{pre_class}\"><code class=\"\{code_class}\"\{data_lang}>\{node.content()}</code></pre>"
    }
    Prettify => {
      let mut pre_class = if nowrap {
        "prettyprint highlight nowrap"
      } else {
        "prettyprint highlight"
      }
      if node.has_option("linenums") {
        pre_class = pre_class +
          (match node.attr("start") {
            Some(start) => " linenums:\{start}"
            None => " linenums"
          })
      }
      "<pre class=\"\{pre_class}\"><code\{data_lang}>\{node.content()}</code></pre>"
    }
  }
}

///|
impl SyntaxHighlighter for ClientHighlighter with fn docinfo(
  self,
  location,
  doc,
  opts,
) {
  let cdn_base_url = opts.cdn_base_url
  let slash = opts.self_closing_tag_slash
  match self.kind {
    HighlightJs => {
      let base_url = doc
        .attr("highlightjsdir", default="\{cdn_base_url}/highlight.js/9.18.3")
        .unwrap_or("")
      if location == "head" {
        let theme = doc
          .attr("highlightjs-theme", default="github")
          .unwrap_or("github")
        "<link rel=\"stylesheet\" href=\"\{base_url}/styles/\{theme}.min.css\"\{slash}>"
      } else {
        let langs = if doc.has_attr("highlightjs-languages") {
          @rb.split(doc.attr("highlightjs-languages").unwrap_or(""), ",")
          .map(l => {
            "<script src=\"\{base_url}/languages/\{@rb.lstrip(l)}.min.js\"></script>\n"
          })
          .join("")
        } else {
          ""
        }
        "<script src=\"\{base_url}/highlight.min.js\"></script>\n\{langs}<script>\nif (!hljs.initHighlighting.called) {\n  hljs.initHighlighting.called = true\n  ;[].slice.call(document.querySelectorAll('pre.highlight > code[data-lang]')).forEach(function (el) { hljs.highlightBlock(el) })\n}\n</script>"
      }
    }
    Prettify => {
      let base_url = doc
        .attr("prettifydir", default="\{cdn_base_url}/prettify/r298")
        .unwrap_or("")
      if location == "head" {
        let theme = doc
          .attr("prettify-theme", default="prettify")
          .unwrap_or("prettify")
        let theme_url = if theme.has_prefix("http://") ||
          theme.has_prefix("https://") {
          theme
        } else {
          "\{base_url}/\{theme}.min.css"
        }
        "<link rel=\"stylesheet\" href=\"\{theme_url}\"\{slash}>"
      } else {
        "<script src=\"\{base_url}/run_prettify.min.js\"></script>"
      }
    }
    HtmlPipeline | Unavailable(_) => ""
  }
}

///|
/// Registers a syntax highlighter factory under the given names (Ruby
/// `SyntaxHighlighter.register`); replaces an existing registration, such as
/// the "library not available" fallbacks of `rouge`, `coderay` and
/// `pygments`.
pub fn register_syntax_highlighter(
  names : Array[String],
  factory : SyntaxHighlighterFactory,
) -> Unit {
  for n in names {
    syntax_highlighter_registry[n] = factory
  }
}

///|
/// Creates the registered syntax highlighter for `name`, if any (Ruby
/// `SyntaxHighlighter.create`).
pub fn create_syntax_highlighter(
  name : String,
  backend : String,
  doc : Node,
) -> &SyntaxHighlighter? {
  match syntax_highlighter_registry.get(name) {
    Some(f) => f(name, backend, doc)
    None => None
  }
}
