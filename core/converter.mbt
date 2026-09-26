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
