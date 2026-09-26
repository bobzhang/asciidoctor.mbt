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
  process : (Node, Reader) -> Reader? raise
}

///|
pub(all) struct TreeProcessor {
  process : (Node) -> Node? raise
}

///|
pub(all) struct Postprocessor {
  process : (Node, String) -> String raise
}

///|
pub(all) struct DocinfoProcessor {
  location : String
  process : (Node) -> String? raise
}

///|
pub(all) struct IncludeProcessor {
  handles : (Node, String) -> Bool
  process : (Node, Reader, String, Attributes) -> Unit raise
}

///|
pub(all) struct BlockProcessor {
  name : String
  config : ExtensionConfig
  process : (Node, Reader, Attributes) -> Node? raise
}

///|
pub(all) struct BlockMacroProcessor {
  name : String
  config : ExtensionConfig
  process : (Node, String, Attributes) -> Node? raise
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
  process : (Node, String, Attributes) -> InlineResult? raise
}

///|
/// An extension registry (Ruby `Extensions::Registry`). Register processors
/// directly or through groups (run on activation); pass the registry with
/// `Options::new(extensions=...)` or register groups globally with
/// `register_global_extensions`.
pub struct Extensions {
  priv preprocessor_list : Array[Preprocessor]
  priv tree_processor_list : Array[TreeProcessor]
  priv postprocessor_list : Array[Postprocessor]
  priv docinfo_processor_list : Array[DocinfoProcessor]
  priv include_processor_list : Array[IncludeProcessor]
  priv block_map : Map[String, BlockProcessor]
  priv block_macro_map : Map[String, BlockMacroProcessor]
  priv inline_macro_map : Map[String, InlineMacroProcessor]
  priv groups : Array[(Extensions) -> Unit]
  mut document : Node?
}

///|
/// Creates an empty registry, optionally with a group to run on activation.
pub fn Extensions::new(group? : (Extensions) -> Unit) -> Extensions {
  {
    preprocessor_list: [],
    tree_processor_list: [],
    postprocessor_list: [],
    docinfo_processor_list: [],
    include_processor_list: [],
    block_map: {},
    block_macro_map: {},
    inline_macro_map: {},
    groups: match group {
      Some(g) => [g]
      None => []
    },
    document: None,
  }
}

///|
/// Adds a group (a function that registers processors on activation).
pub fn Extensions::add_group(
  self : Extensions,
  group : (Extensions) -> Unit,
) -> Unit {
  self.groups.push(group)
}

///|
/// Activates the registry for a document: returns a fresh registry containing
/// the direct registrations plus those made by the global and own groups.
pub fn Extensions::activate(self : Extensions, doc : Node) -> Extensions {
  let e : Extensions = {
    preprocessor_list: self.preprocessor_list.copy(),
    tree_processor_list: self.tree_processor_list.copy(),
    postprocessor_list: self.postprocessor_list.copy(),
    docinfo_processor_list: self.docinfo_processor_list.copy(),
    include_processor_list: self.include_processor_list.copy(),
    block_map: self.block_map.copy(),
    block_macro_map: self.block_macro_map.copy(),
    inline_macro_map: self.inline_macro_map.copy(),
    groups: [],
    document: Some(doc),
  }
  match global_extensions_ref.val {
    Some(g) if !physical_equal(g, self) =>
      for grp in g.groups {
        grp(e)
      }
    _ => ()
  }
  for grp in self.groups {
    grp(e)
  }
  e
}

///|
/// Registers a preprocessor. With `prefer`, it runs before the others.
pub fn Extensions::preprocessor(
  self : Extensions,
  process : (Node, Reader) -> Reader? raise,
  prefer? : Bool = false,
) -> Unit {
  let p : Preprocessor = { process, }
  if prefer {
    self.preprocessor_list.insert(0, p)
  } else {
    self.preprocessor_list.push(p)
  }
}

///|
/// Registers a tree processor; returning a document replaces the document.
pub fn Extensions::tree_processor(
  self : Extensions,
  process : (Node) -> Node? raise,
  prefer? : Bool = false,
) -> Unit {
  let p : TreeProcessor = { process, }
  if prefer {
    self.tree_processor_list.insert(0, p)
  } else {
    self.tree_processor_list.push(p)
  }
}

///|
/// Registers a postprocessor (transforms the converted output).
pub fn Extensions::postprocessor(
  self : Extensions,
  process : (Node, String) -> String raise,
  prefer? : Bool = false,
) -> Unit {
  let p : Postprocessor = { process, }
  if prefer {
    self.postprocessor_list.insert(0, p)
  } else {
    self.postprocessor_list.push(p)
  }
}

///|
/// Registers an include processor.
pub fn Extensions::include_processor(
  self : Extensions,
  process : (Node, Reader, String, Attributes) -> Unit raise,
  handles? : (Node, String) -> Bool = (_, _) => true,
  prefer? : Bool = false,
) -> Unit {
  let p = { handles, process, }
  if prefer {
    self.include_processor_list.insert(0, p)
  } else {
    self.include_processor_list.push(p)
  }
}

///|
/// Registers a docinfo processor for `location` (`head` or `footer`).
pub fn Extensions::docinfo_processor(
  self : Extensions,
  process : (Node) -> String? raise,
  location? : String = "head",
  prefer? : Bool = false,
) -> Unit {
  let p = { location, process, }
  if prefer {
    self.docinfo_processor_list.insert(0, p)
  } else {
    self.docinfo_processor_list.push(p)
  }
}

///|
/// Registers a block processor for a style `name` on `contexts`
/// (default: open and paragraph).
pub fn Extensions::block(
  self : Extensions,
  name : String,
  process : (Node, Reader, Attributes) -> Node? raise,
  contexts? : Array[Context] = [Open, Paragraph],
  content_model? : ContentModel = Compound,
  positional_attrs? : Array[String] = [],
  default_attrs? : Array[(String, String)] = [],
) -> Unit {
  self.block_map[name] = {
    name,
    config: ExtensionConfig::new(
      content_model~,
      positional_attrs~,
      default_attrs~,
      contexts~,
    ),
    process,
  }
}

///|
/// Registers a block macro processor (`name::target[attrs]`).
pub fn Extensions::block_macro(
  self : Extensions,
  name : String,
  process : (Node, String, Attributes) -> Node? raise,
  content_model? : ContentModel = Attributes,
  positional_attrs? : Array[String] = [],
  default_attrs? : Array[(String, String)] = [],
) -> Unit raise ArgumentError {
  if !macro_name_rx.matches(name) {
    raise ArgumentError("invalid name for block macro: \{name}")
  }
  self.block_macro_map[name] = {
    name,
    config: ExtensionConfig::new(
      content_model~,
      positional_attrs~,
      default_attrs~,
    ),
    process,
  }
}

///|
/// Registers an inline macro processor (`name:target[attrs]`, or `name:[attrs]`
/// with `format="short"`, or a custom `regexp`).
pub fn Extensions::inline_macro(
  self : Extensions,
  name : String,
  process : (Node, String, Attributes) -> InlineResult? raise,
  format? : String,
  regexp? : @regex.Regex,
  content_model? : ContentModel = Attributes,
  positional_attrs? : Array[String] = [],
  default_attrs? : Array[(String, String)] = [],
) -> Unit raise ArgumentError {
  if regexp is None && !macro_name_rx.matches(name) {
    raise ArgumentError("invalid name for inline macro: \{name}")
  }
  self.inline_macro_map[name] = {
    name,
    config: ExtensionConfig::new(
      content_model~,
      positional_attrs~,
      default_attrs~,
      format?,
      regexp?,
    ),
    process,
  }
}

///|
fn Extensions::preprocessors(self : Extensions) -> Array[Preprocessor] {
  self.preprocessor_list
}

///|
fn Extensions::tree_processors(self : Extensions) -> Array[TreeProcessor] {
  self.tree_processor_list
}

///|
fn Extensions::postprocessors(self : Extensions) -> Array[Postprocessor] {
  self.postprocessor_list
}

///|
fn Extensions::include_processors(self : Extensions) -> Array[IncludeProcessor] {
  self.include_processor_list
}

///|
fn Extensions::has_blocks(self : Extensions) -> Bool {
  !self.block_map.is_empty()
}

///|
fn Extensions::has_block_macros(self : Extensions) -> Bool {
  !self.block_macro_map.is_empty()
}

///|
fn Extensions::inline_macros(self : Extensions) -> Array[InlineMacroProcessor] {
  self.inline_macro_map.values().collect()
}

///|
fn Extensions::docinfo_processors_for(
  self : Extensions,
  location : String,
) -> Array[DocinfoProcessor] {
  self.docinfo_processor_list.filter(p => p.location == location)
}

///|
fn Extensions::registered_for_block(
  self : Extensions,
  name : String,
  context : Context,
) -> BlockProcessor? {
  match self.block_map.get(name) {
    Some(p) if p.config.contexts.contains(context) => Some(p)
    _ => None
  }
}

///|
fn Extensions::registered_for_block_macro(
  self : Extensions,
  name : String,
) -> BlockMacroProcessor? {
  self.block_macro_map.get(name)
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

// ---------------------------------------------------------------------------
// Processor helpers (Ruby `Extensions::Processor#create_*`, `parse_content`)

///|
/// Creates a block (Ruby `create_block parent, context, source, attrs, opts`).
pub fn create_block(
  parent : Node,
  context : Context,
  source : Array[String]?,
  attrs : Attributes,
  content_model? : ContentModel,
  subs? : BlockSubs,
) -> Node {
  Node::new_block(
    parent,
    context,
    content_model?,
    subs?,
    source?,
    attributes=attrs,
  )
}

///|
/// Creates a paragraph block from lines.
pub fn create_paragraph(
  parent : Node,
  source : Array[String],
  attrs : Attributes,
) -> Node {
  create_block(parent, Paragraph, Some(source), attrs)
}

///|
/// Creates an open block (children parsed with `parse_content`).
pub fn create_open_block(
  parent : Node,
  source : Array[String]?,
  attrs : Attributes,
) -> Node {
  create_block(parent, Open, source, attrs)
}

///|
pub fn create_example_block(
  parent : Node,
  source : Array[String]?,
  attrs : Attributes,
) -> Node {
  create_block(parent, Example, source, attrs)
}

///|
pub fn create_pass_block(
  parent : Node,
  source : Array[String],
  attrs : Attributes,
) -> Node {
  create_block(parent, Pass, Some(source), attrs)
}

///|
pub fn create_listing_block(
  parent : Node,
  source : Array[String],
  attrs : Attributes,
) -> Node {
  create_block(parent, Listing, Some(source), attrs)
}

///|
pub fn create_literal_block(
  parent : Node,
  source : Array[String],
  attrs : Attributes,
) -> Node {
  create_block(parent, Literal, Some(source), attrs)
}

///|
/// Creates a list (ulist, olist, dlist or colist).
pub fn create_list(
  parent : Node,
  context : Context,
  attrs? : Attributes,
) -> Node {
  let list = Node::new_list(parent, context)
  match attrs {
    Some(a) => list.update_attributes(a)
    None => ()
  }
  list
}

///|
pub fn create_list_item(parent : Node, text? : String) -> Node {
  Node::new_list_item(parent, text?)
}

///|
/// Creates an image block; `attrs` must contain `target`.
pub fn create_image_block(
  parent : Node,
  attrs : Attributes,
) -> Node raise ArgumentError {
  guard attrs.str("target") is Some(target) else {
    raise ArgumentError(
      "Unable to create an image block, target attribute is required",
    )
  }
  if !attrs.truthy("alt") {
    let default_alt = basename(target, drop_ext=true)
      .replace_all(old="_", new=" ")
      .replace_all(old="-", new=" ")
    attrs.set_str("default-alt", default_alt)
    attrs.set_str("alt", default_alt)
  }
  let title = if attrs.contains("title") {
    attrs.remove_str("title")
  } else {
    None
  }
  let block = create_block(parent, Image, None, attrs)
  match title {
    Some(t) => {
      block.set_title(Some(t))
      block.assign_caption(
        attrs.remove_str("caption"),
        caption_context="figure",
      )
    }
    None => ()
  }
  block
}

///|
/// Creates an inline node (quoted nodes default to type `unquoted`).
pub fn create_inline(
  parent : Node,
  context : Context,
  text : String?,
  type_? : String,
  target? : String,
  id? : String,
  attributes? : Attributes,
) -> Node {
  let type_ = match type_ {
    Some(t) => Some(t)
    None => if context == Quoted { Some("unquoted") } else { None }
  }
  Node::new_inline(parent, context, text?, type_?, target?, id?, attributes?)
}

///|
/// Creates an anchor (link or xref) inline node.
pub fn create_anchor(
  parent : Node,
  text : String?,
  type_ : String,
  target? : String,
  id? : String,
  attributes? : Attributes,
) -> Node {
  create_inline(parent, Anchor, text, type_~, target?, id?, attributes?)
}

///|
/// Creates a section (Ruby `create_section parent, title, attrs, opts`).
pub fn create_section(
  parent : Node,
  title : String,
  attrs : Attributes,
  level? : Int,
  numbered? : Bool,
) -> Node {
  let doc = parent.document()
  let doctype = doc.doctype()
  let book = doctype == "book"
  let mut level = level.unwrap_or(parent.level + 1)
  let mut sectname = "section"
  let mut special = false
  let style = attrs.remove_str("style")
  match style {
    Some(s) =>
      if book && s == "abstract" {
        sectname = "chapter"
        level = 1
      } else {
        sectname = s
        special = true
        if level == 0 {
          level = 1
        }
      }
    None =>
      if book {
        sectname = if level == 0 {
          "part"
        } else if level > 1 {
          "section"
        } else {
          "chapter"
        }
      } else if doctype == "manpage" && @rb.downcase_ascii(title) == "synopsis" {
        sectname = "synopsis"
        special = true
      }
  }
  let sect = Node::new_section(Some(parent), level~)
  sect.set_title(Some(title))
  sect.sectname = Some(sectname)
  if special {
    sect.special = true
    if numbered.unwrap_or(style == Some("appendix")) {
      sect.numbered = Numbered
    } else if numbered is None && doc.has_attr("sectnums", expected="all") {
      sect.numbered = if book && level == 1 {
        NumberedChapter
      } else {
        Numbered
      }
    }
  } else if level > 0 {
    if numbered.unwrap_or(doc.has_attr("sectnums")) {
      sect.numbered = if sect.special {
        if parent.numbered != NotNumbered {
          Numbered
        } else {
          NotNumbered
        }
      } else {
        Numbered
      }
    }
  } else if numbered.unwrap_or(book && doc.has_attr("partnums")) {
    sect.numbered = Numbered
  }
  match attrs.get("id") {
    Some(Bool(false)) => attrs.remove("id") |> ignore
    v => {
      let id = match v {
        Some(Str(i)) => Some(i)
        _ =>
          if doc.has_attr("sectids") {
            Some(generate_section_id(sect.title().unwrap_or(""), doc))
          } else {
            None
          }
      }
      sect.id = id
      match id {
        Some(i) => attrs.set_str("id", i)
        None => attrs.set("id", Nil)
      }
    }
  }
  sect.update_attributes(attrs)
  sect
}

///|
/// Parses AsciiDoc lines as child blocks of `parent` (Ruby `parse_content`).
pub fn parse_content(
  parent : Node,
  content : Array[String],
  attributes? : Attributes,
) -> Node {
  parse_blocks(Reader::new(content), parent, attributes)
  parent
}

///|
/// Parses the remaining lines of `reader` as child blocks of `parent`.
pub fn parse_content_from_reader(
  parent : Node,
  reader : Reader,
  attributes? : Attributes,
) -> Node {
  parse_blocks(reader, parent, attributes)
  parent
}

///|
/// Parses an attribute list for an extension (Ruby `Processor#parse_attributes`).
pub fn parse_extension_attributes(
  block : Node,
  attrlist : String,
  positional_attributes? : Array[String] = [],
  sub_attributes? : Bool = false,
) -> Attributes {
  if attrlist == "" {
    return Attributes::new()
  }
  let attrlist = if sub_attributes && attrlist.contains("{") {
    block.sub_attributes(attrlist)
  } else {
    attrlist
  }
  parse_attribute_list(
    attrlist,
    positional_attrs=positional_attributes.map(x => Some(x)),
  )
}
