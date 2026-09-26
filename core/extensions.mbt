///|
/// Configuration shared by block, block macro and inline macro processors
/// (Ruby extension `config` Hash).
pub(all) struct ExtensionConfig {
  mut content_model : ContentModel?
  mut positional_attrs : Array[String]
  mut default_attrs : Array[(String, String)]
  mut contexts : Array[Context]
  mut format : String? // inline macro: "short" or "long"
  mut regexp : @regex.Regex?
}

///|
pub fn ExtensionConfig::new(
  content_model? : ContentModel,
  positional_attrs? : Array[String] = [],
  default_attrs? : Array[(String, String)] = [],
  contexts? : Array[Context] = [],
  format? : String,
  regexp? : @regex.Regex,
) -> ExtensionConfig {
  { content_model, positional_attrs, default_attrs, contexts, format, regexp, }
}

///|
pub(all) struct Preprocessor {
  process : (Node, Reader) -> Reader?
}

///|
pub(all) struct TreeProcessor {
  process : (Node) -> Node?
}

///|
pub(all) struct Postprocessor {
  process : (Node, String) -> String
}

///|
pub(all) struct DocinfoProcessor {
  location : String
  process : (Node) -> String?
}

///|
pub(all) struct IncludeProcessor {
  handles : (Node, String) -> Bool
  process : (Node, Reader, String, Attributes) -> Unit
}

///|
pub(all) struct BlockProcessor {
  name : String
  config : ExtensionConfig
  process : (Node, Reader, Attributes) -> Node?
}

///|
pub(all) struct BlockMacroProcessor {
  name : String
  config : ExtensionConfig
  process : (Node, String, Attributes) -> Node?
}

///|
/// Result of an inline macro: a node to convert, or literal text.
pub(all) enum InlineResult {
  InlineNode(Node)
  InlineText(String)
}

///|
pub(all) struct InlineMacroProcessor {
  name : String
  config : ExtensionConfig
  process : (Node, String, Attributes) -> InlineResult?
}

///|
/// An extension registry (Ruby `Extensions::Registry`).
pub struct Extensions {
  preprocessors : Array[Preprocessor]
  tree_processors : Array[TreeProcessor]
  postprocessors : Array[Postprocessor]
  docinfo_processors : Array[DocinfoProcessor]
  include_processors : Array[IncludeProcessor]
  block_processors : Array[BlockProcessor]
  block_macros : Array[BlockMacroProcessor]
  inline_macros : Array[InlineMacroProcessor]
  /// Called with the document when the registry is activated.
  groups : Array[(Extensions) -> Unit]
  mut document : Node?
}

///|
pub fn Extensions::new() -> Extensions {
  {
    preprocessors: [],
    tree_processors: [],
    postprocessors: [],
    docinfo_processors: [],
    include_processors: [],
    block_processors: [],
    block_macros: [],
    inline_macros: [],
    groups: [],
    document: None,
  }
}

///|
/// Activates the registry for a document; returns a fresh activated copy.
pub fn Extensions::activate(self : Extensions, doc : Node) -> Extensions {
  let e = {
    preprocessors: self.preprocessors.copy(),
    tree_processors: self.tree_processors.copy(),
    postprocessors: self.postprocessors.copy(),
    docinfo_processors: self.docinfo_processors.copy(),
    include_processors: self.include_processors.copy(),
    block_processors: self.block_processors.copy(),
    block_macros: self.block_macros.copy(),
    inline_macros: self.inline_macros.copy(),
    groups: [],
    document: Some(doc),
  }
  for g in self.groups {
    g(e)
  }
  e
}

///|
fn Extensions::docinfo_processors_for(
  self : Extensions,
  location : String,
) -> Array[DocinfoProcessor] {
  self.docinfo_processors.filter(p => p.location == location)
}

///|
fn Extensions::registered_for_block(
  self : Extensions,
  name : String,
  context : Context,
) -> BlockProcessor? {
  for p in self.block_processors {
    if p.name == name &&
      (p.config.contexts.is_empty() || p.config.contexts.contains(context)) {
      return Some(p)
    }
  }
  None
}

///|
fn Extensions::registered_for_block_macro(
  self : Extensions,
  name : String,
) -> BlockMacroProcessor? {
  for p in self.block_macros {
    if p.name == name {
      return Some(p)
    }
  }
  None
}

///|
let global_extensions_ref : Ref[Extensions?] = { val: None, }

///|
/// Registers a global extension group (Ruby `Asciidoctor::Extensions.register`).
pub fn register_global_extensions(group : (Extensions) -> Unit) -> Unit {
  let e = match global_extensions_ref.val {
    Some(e) => e
    None => {
      let e = Extensions::new()
      global_extensions_ref.val = Some(e)
      e
    }
  }
  e.groups.push(group)
}

///|
/// Removes all global extension groups.
pub fn unregister_all_global_extensions() -> Unit {
  global_extensions_ref.val = None
}

///|
fn global_extensions() -> Extensions? {
  global_extensions_ref.val
}
