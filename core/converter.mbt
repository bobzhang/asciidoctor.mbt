///|
/// Traits describing a backend (Ruby `Converter::BackendTraits`).
pub(all) struct BackendTraits {
  basebackend : String
  filetype : String
  htmlsyntax : String?
  outfilesuffix : String
  supports_templates : Bool
} derive(Debug)

///|
/// Derives backend traits from a backend name (Ruby `Converter.derive_backend_traits`).
pub fn derive_backend_traits(
  backend : String,
  basebackend? : String,
) -> BackendTraits {
  let base = match basebackend {
    Some(b) => b
    None => trailing_digits_rx.gsub(backend, "")
  }
  let (outfilesuffix, filetype) = match base {
    "html" => (".html", "html")
    "docbook" => (".xml", "xml")
    "pdf" => (".pdf", "pdf")
    "epub" => (".epub", "epub")
    "manpage" => (".man", "man")
    "asciidoc" => (".adoc", "adoc")
    _ => (".\{base}", base)
  }
  {
    basebackend: base,
    filetype,
    htmlsyntax: if filetype == "html" {
      Some("html")
    } else {
      None
    },
    outfilesuffix,
    supports_templates: false,
  }
}

///|
/// A converter turns nodes into output. `transform` is the node name
/// (`paragraph`, `inline_quoted`, ...) or `document`/`embedded`/`outline`.
pub(open) trait Converter {
  fn convert(Self, Node, String) -> String
  fn backend_traits(Self) -> BackendTraits
}

///|
/// Creates a converter for a backend: (backend, htmlsyntax, document) -> converter.
pub type ConverterFactory = (String, String?, Node) -> &Converter

///|
let converter_registry : Map[String, ConverterFactory] = Map([])

///|
/// Registers a converter factory for the given backend names.
pub fn register_converter(
  backends : Array[String],
  factory : ConverterFactory,
) -> Unit {
  for b in backends {
    converter_registry[b] = factory
  }
}

///|
/// Looks up the converter factory registered for a backend.
pub fn lookup_converter(backend : String) -> ConverterFactory? {
  converter_registry.get(backend)
}

///|
/// Names of the registered backends.
pub fn registered_backends() -> Array[String] {
  converter_registry.keys().collect()
}

///|
/// A converter that renders nothing (used when no converter is registered).
priv struct NullConverter {
  traits : BackendTraits
}

///|
impl Converter for NullConverter with fn convert(_self, _node, _transform) {
  ""
}

///|
impl Converter for NullConverter with fn backend_traits(self) {
  self.traits
}

///|
/// A converter that dispatches individual transforms to handler functions and
/// falls back to a delegate (Ruby `CompositeConverter` / converter subclassing).
pub struct CompositeConverter {
  handlers : Map[String, (Node) -> String]
  delegate : &Converter
}

///|
pub fn CompositeConverter::new(
  delegate : &Converter,
  handlers? : Map[String, (Node) -> String] = {},
) -> CompositeConverter {
  { handlers, delegate, }
}

///|
pub impl Converter for CompositeConverter with fn convert(self, node, transform) {
  match self.handlers.get(transform) {
    Some(h) => h(node)
    None => self.delegate.convert(node, transform)
  }
}

///|
pub impl Converter for CompositeConverter with fn backend_traits(self) {
  self.delegate.backend_traits()
}

// ---------------------------------------------------------------------------
// Syntax highlighting

///|
/// A syntax highlighter adapter (Ruby `SyntaxHighlighter`). Only client-side
/// highlighters (highlight.js, prettify, ...) are provided by this port.
pub(open) trait SyntaxHighlighter {
  fn name(Self) -> String
  /// Whether the highlighter handles the listing itself (server-side).
  fn handles_highlighting(Self) -> Bool
  /// Formats the (already converted) source block.
  fn format(Self, Node, String?, Map[String, String]) -> String
  /// Whether docinfo is emitted at the location (`head` or `footer`).
  fn has_docinfo(Self, String) -> Bool
  /// Docinfo markup for the location; opts: linkcss, cdn_base_url, self_closing_tag_slash.
  fn docinfo(Self, String, Node, Map[String, String]) -> String
  /// Highlights source (server-side highlighters only): (node, source, lang, opts) -> (html, lineno offsets?)
  fn highlight(Self, Node, String, String, Map[String, String]) -> String
}

///|
pub type SyntaxHighlighterFactory = (String, String, Node) -> &SyntaxHighlighter?

///|
let syntax_highlighter_registry : Map[String, SyntaxHighlighterFactory] = {
  "highlightjs": (_, _, _) => Some(ClientHighlighter::new(HighlightJs)),
  "highlight.js": (_, _, _) => Some(ClientHighlighter::new(HighlightJs)),
  "prettify": (_, _, _) => Some(ClientHighlighter::new(Prettify)),
  "html-pipeline": (_, _, _) => Some(ClientHighlighter::new(HtmlPipeline)),
  // server-side highlighters behave as in Ruby when their gem is missing
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
impl SyntaxHighlighter for ClientHighlighter with fn handles_highlighting(_self) {
  false
}

///|
impl SyntaxHighlighter for ClientHighlighter with fn highlight(
  _self,
  _node,
  source,
  _lang,
  _opts,
) {
  source
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
  let nowrap = opts.contains("nowrap")
  let data_lang = match lang {
    Some(l) => " data-lang=\"\{l}\""
    None => ""
  }
  match self.kind {
    Unavailable(n) => {
      warn_unavailable(n)
      let pre_class = if n == "coderay" { "CodeRay" } else { n }
      let pre_class = if nowrap {
        "\{pre_class} highlight nowrap"
      } else {
        "\{pre_class} highlight"
      }
      "<pre class=\"\{pre_class}\"><code\{data_lang}>\{node.content()}</code></pre>"
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
  let cdn_base_url = opts.get("cdn_base_url").unwrap_or("")
  let slash = opts.get("self_closing_tag_slash").unwrap_or("")
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
/// Registers a syntax highlighter factory under the given names.
pub fn register_syntax_highlighter(
  names : Array[String],
  factory : SyntaxHighlighterFactory,
) -> Unit {
  for n in names {
    syntax_highlighter_registry[n] = factory
  }
}

///|
fn create_syntax_highlighter(
  name : String,
  backend : String,
  doc : Node,
) -> &SyntaxHighlighter? {
  match syntax_highlighter_registry.get(name) {
    Some(f) => f(name, backend, doc)
    None => None
  }
}
