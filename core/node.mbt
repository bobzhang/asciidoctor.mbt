///|
/// An entry of a description list: one or more terms and an optional description.
pub(all) struct DlistItem {
  terms : Array[Node]
  mut desc : Node?
}

///|
/// A node of the document tree. Ruby's class hierarchy (AbstractNode,
/// AbstractBlock, Document, Section, Block, List, ListItem, Table,
/// Table::Column, Table::Cell, Inline) is flattened into this one struct; the
/// `context` tells which fields are meaningful.
pub(all) struct Node {
  mut context : Context
  mut node_name : String
  priv mut parent_ : Node?
  priv mut document_ : Node? // None for the document itself
  attributes : Attributes
  mut id : String?
  priv passthroughs : Array[Passthrough]
  priv mut passthroughs_locked : Bool
  // AbstractBlock
  blocks : Array[Node]
  mut content_model : ContentModel
  mut level : Int
  mut numeral : String?
  mut source_location : Cursor?
  mut style : String?
  mut subs : Array[Sub]
  priv mut default_subs : Array[Sub]?
  priv mut title_ : String?
  priv mut converted_title : String?
  priv mut caption_ : String?
  priv mut next_section_index : Int
  priv mut next_section_ordinal : Int
  // Block
  mut lines : Array[String]
  // Section
  mut index : Int
  mut sectname : String?
  mut special : Bool
  mut numbered : Numbered
  // ListItem / Inline / Cell
  priv mut text_ : String?
  mut marker : String?
  // Ruby stores an implicit ordered list style as a Symbol, which does not
  // match ORDERED_LIST_KEYWORDS; track that quirk.
  priv mut symbolic_style : Bool
  // Description list items (context == Dlist)
  dlist_items : Array[DlistItem]
  // Inline
  mut inline_type : String?
  mut target : String?
  // Table, column and cell data
  priv mut table_ : TableData?
  priv mut cell_ : CellData?
  // Document data (context == Document)
  priv mut doc_ : DocData?
}

///|
fn Node::alloc(
  parent : Node?,
  context : Context,
  attributes? : Attributes,
  document? : Node,
) -> Node {
  let doc = match document {
    Some(d) => Some(d)
    None =>
      match parent {
        Some(p) => Some(p.document())
        None => None
      }
  }
  let level = match parent {
    Some(p) => p.level
    None => 0
  }
  {
    context,
    node_name: context.name(),
    parent_: parent,
    document_: doc,
    attributes: match attributes {
      Some(a) => a.copy()
      None => Attributes::new()
    },
    id: None,
    passthroughs: [],
    passthroughs_locked: false,
    blocks: [],
    content_model: Compound,
    level,
    numeral: None,
    source_location: None,
    style: None,
    subs: [],
    default_subs: None,
    title_: None,
    converted_title: None,
    caption_: None,
    next_section_index: 0,
    next_section_ordinal: 1,
    lines: [],
    index: 0,
    sectname: None,
    special: false,
    numbered: NotNumbered,
    text_: None,
    marker: None,
    symbolic_style: false,
    dlist_items: [],
    inline_type: None,
    target: None,
    table_: None,
    cell_: None,
    doc_: None,
  }
}

// ---------------------------------------------------------------------------
// AbstractNode

///|
/// The parent node (None for a document).
pub fn Node::parent(self : Node) -> Node? {
  self.parent_
}

///|
/// Sets the parent (and the document) of this node.
pub fn Node::set_parent(self : Node, parent : Node) -> Unit {
  self.parent_ = Some(parent)
  self.document_ = Some(parent.document())
}

///|
/// The document this node belongs to.
pub fn Node::document(self : Node) -> Node {
  match self.document_ {
    Some(d) => d
    None => self
  }
}

///|
fn Node::doc(self : Node) -> DocData {
  match self.document().doc_ {
    Some(d) => d
    None => abort("node is not attached to a document")
  }
}

///|
pub fn Node::is_block(self : Node) -> Bool {
  !self.is_inline() && self.context != TableColumn
}

///|
pub fn Node::is_inline(self : Node) -> Bool {
  self.node_name.has_prefix("inline_")
}

///|
/// Ruby `attr(name, default, fallback)`: the attribute value as a string if
/// truthy; otherwise, if `fallback` is set and the node has a parent, the
/// document attribute; otherwise `default`.
pub fn Node::attr(
  self : Node,
  name : String,
  default? : String,
  inherited? : Bool = false,
  fallback_name? : String,
) -> String? {
  match self.attributes.str(name) {
    Some(v) => Some(v)
    None =>
      if (inherited || fallback_name is Some(_)) && self.parent_ is Some(_) {
        match self.document().attributes.str(fallback_name.unwrap_or(name)) {
          Some(v) => Some(v)
          None => default
        }
      } else {
        default
      }
  }
}

///|
/// Ruby `attr?(name, expected, fallback)`.
pub fn Node::has_attr(
  self : Node,
  name : String,
  expected? : String,
  inherited? : Bool = false,
) -> Bool {
  match expected {
    Some(e) => {
      let v = match self.attributes.str(name) {
        Some(v) => Some(v)
        None =>
          if inherited && self.parent_ is Some(_) {
            self.document().attributes.str(name)
          } else {
            None
          }
      }
      v == Some(e)
    }
    None =>
      self.attributes.contains(name) ||
      (
        inherited &&
        self.parent_ is Some(_) &&
        self.document().attributes.contains(name)
      )
  }
}

///|
/// Ruby `set_attr(name, value, overwrite)`.
pub fn Node::set_attr(
  self : Node,
  name : String,
  value? : AttrVal = Str(""),
  overwrite? : Bool = true,
) -> Bool {
  if !overwrite && self.attributes.contains(name) {
    false
  } else {
    self.attributes.set(name, value)
    true
  }
}

///|
pub fn Node::remove_attr(self : Node, name : String) -> AttrVal? {
  self.attributes.remove(name)
}

///|
/// Ruby `option?(name)`.
pub fn Node::has_option(self : Node, name : String) -> Bool {
  self.attributes.truthy("\{name}-option")
}

///|
pub fn Node::set_option(self : Node, name : String) -> Unit {
  self.attributes.set_str("\{name}-option", "")
}

///|
/// Ruby `enabled_options`.
pub fn Node::enabled_options(self : Node) -> Array[String] {
  let out = []
  for k, _ in self.attributes.iter() {
    if k is Name(n) && n.has_suffix("-option") {
      out.push(n.unsafe_substring(start=0, end=n.length() - 7))
    }
  }
  out
}

///|
pub fn Node::update_attributes(
  self : Node,
  new_attributes : Attributes,
) -> Unit {
  self.attributes.update(new_attributes)
}

///|
pub fn Node::role(self : Node) -> String? {
  self.attributes.str("role")
}

///|
pub fn Node::roles(self : Node) -> Array[String] {
  match self.attributes.str("role") {
    Some(v) => @rb.split_ws(v)
    None => []
  }
}

///|
pub fn Node::has_role(self : Node, name : String) -> Bool {
  match self.attributes.str("role") {
    Some(v) => " \{v} ".contains(" \{name} ")
    None => false
  }
}

///|
/// Ruby `role?(expected)`.
pub fn Node::role_is(self : Node, expected? : String) -> Bool {
  match expected {
    Some(e) => self.attributes.str("role") == Some(e)
    None => self.attributes.contains("role")
  }
}

///|
/// Sets (or clears) the id of this node (Ruby `node.id = value`).
pub fn Node::set_id(self : Node, id : String?) -> Unit {
  self.id = id
}

///|
pub fn Node::set_role(self : Node, names : String) -> Unit {
  self.attributes.set_str("role", names)
}

///|
pub fn Node::add_role(self : Node, name : String) -> Bool {
  match self.attributes.str("role") {
    Some(v) =>
      if " \{v} ".contains(" \{name} ") {
        false
      } else {
        self.attributes.set_str("role", "\{v} \{name}")
        true
      }
    None => {
      self.attributes.set_str("role", name)
      true
    }
  }
}

///|
pub fn Node::remove_role(self : Node, name : String) -> Bool {
  match self.attributes.str("role") {
    Some(v) => {
      let parts = @rb.split_ws(v)
      match parts.search(name) {
        Some(i) => {
          parts.remove(i) |> ignore
          if parts.is_empty() {
            self.attributes.remove("role") |> ignore
          } else {
            self.attributes.set_str("role", parts.join(" "))
          }
          true
        }
        None => false
      }
    }
    None => false
  }
}

///|
/// Ruby `reftext`: the reftext attribute with reftext substitutions applied.
pub fn Node::reftext(self : Node) -> String? {
  match self.context {
    Anchor if self.is_inline() =>
      match self.text_ {
        Some(t) => Some(self.apply_reftext_subs(t))
        None => None
      }
    _ =>
      match self.attributes.str("reftext") {
        Some(v) => Some(self.apply_reftext_subs(v))
        None => None
      }
  }
}

///|
pub fn Node::has_reftext(self : Node) -> Bool {
  if self.is_inline() {
    self.text_ is Some(_) &&
    (self.inline_type == Some("ref") || self.inline_type == Some("bibref"))
  } else {
    self.attributes.contains("reftext")
  }
}

// ---------------------------------------------------------------------------
// AbstractBlock

///|
pub fn Node::file(self : Node) -> String? {
  match self.source_location {
    Some(c) => c.file
    None => None
  }
}

///|
pub fn Node::lineno(self : Node) -> Int? {
  match self.source_location {
    Some(c) => Some(c.lineno)
    None => None
  }
}

///|
/// Sets the context (and node name) of this node.
pub fn Node::set_context(self : Node, context : Context) -> Unit {
  self.context = context
  self.node_name = context.name()
}

///|
/// Appends a child block (Ruby `<<`), assigning section numbers as needed.
pub fn Node::append(self : Node, block : Node) -> Unit {
  if (self.context == Section || self.context == Document) &&
    block.context == Section {
    self.assign_numeral(block)
  }
  match block.parent_ {
    Some(p) if physical_equal(p, self) => ()
    _ => block.set_parent(self)
  }
  self.blocks.push(block)
}

///|
pub fn Node::has_blocks(self : Node) -> Bool {
  !self.blocks.is_empty()
}

///|
/// Whether this node has child sections.
pub fn Node::has_sections(self : Node) -> Bool {
  match self.context {
    Section | Document => self.next_section_index > 0
    _ => false
  }
}

///|
/// Ruby `number`: the numeral as an integer when possible.
pub fn Node::number(self : Node) -> AttrVal {
  match self.numeral {
    Some(n) =>
      match @rb.parse_int(n) {
        Some(i) => Int(i)
        None => Str(n)
      }
    None => Nil
  }
}

///|
/// The child sections.
pub fn Node::sections(self : Node) -> Array[Node] {
  self.blocks.filter(b => b.context == Section)
}

///|
/// The raw (unsubstituted) title.
pub fn Node::raw_title(self : Node) -> String? {
  self.title_
}

///|
/// The converted title (title substitutions applied), memoized.
pub fn Node::title(self : Node) -> String? {
  if self.context == Document {
    return self.doctitle()
  }
  match self.converted_title {
    Some(t) => Some(t)
    None =>
      match self.title_ {
        Some(t) => {
          let c = self.apply_title_subs(t)
          self.converted_title = Some(c)
          Some(c)
        }
        None => None
      }
  }
}

///|
pub fn Node::has_title(self : Node) -> Bool {
  if self.context == Document {
    return self.doc().header is Some(_) || self.attributes.contains("title")
  }
  self.title_ is Some(_)
}

///|
pub fn Node::set_title(self : Node, val : String?) -> Unit {
  if self.context == Document {
    let sect = match self.doc().header {
      Some(h) => h
      None => {
        let h = Node::new_section(Some(self), level=0)
        h.sectname = Some("header")
        self.doc().header = Some(h)
        h
      }
    }
    sect.set_title(val)
    return
  }
  self.converted_title = None
  self.title_ = val
}

///|
/// The caption (for admonitions, the textlabel attribute).
pub fn Node::caption(self : Node) -> String? {
  if self.context == Admonition {
    self.attributes.str("textlabel")
  } else {
    self.caption_
  }
}

///|
pub fn Node::set_caption(self : Node, caption : String?) -> Unit {
  self.caption_ = caption
}

///|
/// The caption followed by the title.
pub fn Node::captioned_title(self : Node) -> String {
  "\{self.caption_.unwrap_or("")}\{self.title().unwrap_or("")}"
}

///|
pub fn Node::list_marker_keyword(self : Node, list_type? : String) -> String? {
  let lt = match list_type {
    Some(x) => Some(x)
    None => if self.symbolic_style { None } else { self.style }
  }
  match lt {
    Some("loweralpha") => Some("a")
    Some("lowerroman") => Some("i")
    Some("upperalpha") => Some("A")
    Some("upperroman") => Some("I")
    _ => None
  }
}

///|
pub fn Node::has_sub(self : Node, name : Sub) -> Bool {
  self.subs.contains(name)
}

///|
pub fn Node::remove_sub(self : Node, sub : Sub) -> Unit {
  match self.subs.search(sub) {
    Some(i) => self.subs.remove(i) |> ignore
    None => ()
  }
}

///|
/// The alt text of an image block, with special characters escaped.
pub fn Node::alt(self : Node) -> String {
  if self.is_inline() {
    return self.attributes.str("alt").unwrap_or("")
  }
  match self.attributes.str("alt") {
    Some(text) =>
      if Some(text) == self.attributes.str("default-alt") {
        sub_specialchars(text)
      } else {
        let text = sub_specialchars(text)
        if replaceable_text_rx.matches(text) {
          self.sub_replacements(text)
        } else {
          text
        }
      }
    None => ""
  }
}

///|
fn caption_attribute_name(ctx : String) -> String? {
  match ctx {
    "example" => Some("example-caption")
    "figure" => Some("figure-caption")
    "listing" => Some("listing-caption")
    "table" => Some("table-caption")
    _ => None
  }
}

///|
/// Ruby `xreftext(xrefstyle)`.
pub fn Node::xreftext(self : Node, xrefstyle? : String) -> String? {
  match self.context {
    Section => return self.section_xreftext(xrefstyle?)
    Document =>
      return match self.reftext() {
        Some(v) if v != "" => Some(v)
        _ => self.title()
      }
    _ => ()
  }
  if self.is_inline() {
    return self.reftext()
  }
  match self.reftext() {
    Some(v) if v != "" => return Some(v)
    _ => ()
  }
  match (xrefstyle, self.title_, self.caption_) {
    (Some(style), Some(_), Some(caption)) if caption != "" => {
      let doc = self.document()
      let prefix = match
        (self.numeral, caption_attribute_name(self.context.name())) {
        (Some(_), Some(attr_name)) => doc.attributes.str(attr_name)
        _ => None
      }
      match style {
        "full" => {
          let quoted_title = sub_placeholder(
            self.sub_quotes(
              if doc.doc().compat_mode {
                "``%s''"
              } else {
                "\"`%s`\""
              },
            ),
            self.title().unwrap_or(""),
          )
          match prefix {
            Some(p) =>
              Some("\{p} \{self.numeral.unwrap_or("")}, \{quoted_title}")
            None => Some("\{@rb.chomp_suffix(caption, ". ")}, \{quoted_title}")
          }
        }
        "short" =>
          match prefix {
            Some(p) => Some("\{p} \{self.numeral.unwrap_or("")}")
            None => Some(@rb.chomp_suffix(caption, ". "))
          }
        _ => self.title()
      }
    }
    _ => self.title()
  }
}

///|
/// Ruby `assign_caption(value, caption_context)`.
pub fn Node::assign_caption(
  self : Node,
  value : String?,
  caption_context? : String,
) -> Unit {
  if self.caption_ is Some(_) || self.title_ is None {
    return
  }
  let doc = self.document()
  let v0 = match value {
    Some(x) => Some(x)
    None => doc.attributes.str("caption")
  }
  match v0 {
    Some(v) => self.caption_ = Some(v)
    None => {
      let ctx = caption_context.unwrap_or(self.context.name())
      match caption_attribute_name(ctx) {
        Some(attr_name) =>
          match doc.attributes.str(attr_name) {
            Some(prefix) => {
              let num = doc.increment_and_store_counter("\{ctx}-number", self)
              self.numeral = Some(num)
              self.caption_ = Some("\{prefix} \{num}. ")
            }
            None => ()
          }
        None => ()
      }
    }
  }
}

///|
/// Assigns the next index and numeral to the child `section`.
pub fn Node::assign_numeral(self : Node, section : Node) -> Unit {
  section.index = self.next_section_index
  self.next_section_index = section.index + 1
  if section.numbered != NotNumbered {
    let doc = self.document()
    let sectname = section.sectname.unwrap_or("")
    if sectname == "appendix" {
      let n = doc.counter("appendix-number", seed="A")
      section.numeral = Some(n)
      section.caption_ = match doc.attributes.str("appendix-caption") {
        Some(caption) => Some("\{caption} \{n}: ")
        None => Some("\{n}. ")
      }
    } else if sectname == "chapter" || section.numbered == NumberedChapter {
      section.numeral = Some(doc.counter("chapter-number", seed="1"))
    } else {
      section.numeral = Some(
        if sectname == "part" {
          @rb.int_to_roman(self.next_section_ordinal)
        } else {
          self.next_section_ordinal.to_string()
        },
      )
      self.next_section_ordinal += 1
    }
  }
}

///|
/// Recomputes section indexes and numerals.
pub fn Node::reindex_sections(self : Node) -> Unit {
  self.next_section_index = 0
  self.next_section_ordinal = 1
  for block in self.blocks {
    if block.context == Section {
      self.assign_numeral(block)
      block.reindex_sections()
    }
  }
}

///|
/// Content of this block: converted children (compound), substituted text
/// (simple), or substituted lines (verbatim/raw).
pub fn Node::content(self : Node) -> String {
  match self.context {
    Document => {
      self.attributes.remove("title") |> ignore
      return self.blocks.map(b => b.convert()).join("\n")
    }
    TableCell => return self.cell_content().join("\n")
    _ => ()
  }
  if self.context == ListItem || self.is_list() {
    return self.blocks.map(b => b.convert()).join("\n")
  }
  match self.content_model {
    Compound => self.blocks.map(b => b.convert()).join("\n")
    Simple => self.apply_subs(self.lines.join("\n"), self.subs)
    Verbatim | Raw => {
      let result = self.apply_subs_lines(self.lines, self.subs)
      if result.length() < 2 {
        result.get(0).unwrap_or("")
      } else {
        let mut start = 0
        let mut end = result.length()
        while start < end && @rb.rstrip(result[start]) == "" {
          start += 1
        }
        while end > start && @rb.rstrip(result[end - 1]) == "" {
          end -= 1
        }
        result[start:end].join("\n")
      }
    }
    _ => {
      if self.content_model != Empty {
        log_warn(
          "unknown content model '\{self.content_model.name()}' for block: \{self.context.name()}",
        )
      }
      ""
    }
  }
}

///|
/// The source (lines joined by LF).
pub fn Node::source(self : Node) -> String {
  match self.cell_ {
    Some(c) => c.text
    None => self.lines.join("\n")
  }
}

///|
/// Converts this node using the document's converter.
pub fn Node::convert(self : Node) -> String {
  if self.context == Document {
    return self.convert_document()
  }
  if !self.is_inline() {
    self.document().playback_attributes(self.attributes)
  }
  let result = self.document().converter().convert(self, self.node_name)
  if self.context == Colist {
    self.doc().catalog.callouts.next_list()
  }
  result
}

///|
/// Whether this is a list (ulist, olist, dlist or colist).
pub fn Node::is_list(self : Node) -> Bool {
  self.context is (Ulist | Olist | Dlist | Colist)
}

///|
/// Whether this list is an outline (ulist or olist).
pub fn Node::is_outline(self : Node) -> Bool {
  self.context is (Ulist | Olist)
}

///|
/// The next block after this one, walking up the tree (Ruby `next_adjacent_block`).
pub fn Node::next_adjacent_block(self : Node) -> Node? {
  if self.context == Document {
    return None
  }
  guard self.parent_ is Some(p) else { return None }
  if p.context == Dlist && self.context == ListItem {
    let items = p.dlist_items
    let mut idx = -1
    for i, item in items {
      if item.terms.iter().any(t => physical_equal(t, self)) ||
        (item.desc is Some(d) && physical_equal(d, self)) {
        idx = i
        break
      }
    }
    if idx >= 0 && idx + 1 < items.length() {
      let sib = items[idx + 1]
      // Ruby returns the [terms, desc] pair; callers use its first term
      return Some(sib.terms[0])
    }
    return p.next_adjacent_block()
  }
  let mut idx = -1
  for i, b in p.blocks {
    if physical_equal(b, self) {
      idx = i
      break
    }
  }
  if idx >= 0 && idx + 1 < p.blocks.length() {
    Some(p.blocks[idx + 1])
  } else {
    p.next_adjacent_block()
  }
}

///|
/// Selector for `find_by`.
pub(all) enum FindVerdict {
  Accept
  Reject
  Prune
  Stop
  Skip // falsy: not accepted, keep walking
}

///|
priv suberror StopIteration

///|
/// Ruby `find_by(selector) {|node| ... }`: walks the tree and collects matching nodes.
pub fn Node::find_by(
  self : Node,
  context? : Context,
  style? : String,
  role? : String,
  id? : String,
  traverse_documents? : Bool = false,
  filter? : (Node) -> FindVerdict,
) -> Array[Node] {
  let result = []
  self.find_by_internal(
    context~,
    style~,
    role~,
    id~,
    traverse_documents~,
    filter~,
    result,
  ) catch {
    StopIteration => ()
  }
  result
}

///|
fn Node::find_by_internal(
  self : Node,
  context~ : Context?,
  style~ : String?,
  role~ : String?,
  id~ : String?,
  traverse_documents~ : Bool,
  filter~ : ((Node) -> FindVerdict)?,
  result : Array[Node],
) -> Unit raise StopIteration {
  let any_context = context is None
  let matches = (any_context || context == Some(self.context)) &&
    (style is None || style == self.style) &&
    (role is None || self.has_role(role.unwrap())) &&
    (id is None || id == self.id)
  if matches {
    match filter {
      Some(f) =>
        match f(self) {
          Prune => {
            result.push(self)
            if id is Some(_) {
              raise StopIteration
            }
            return
          }
          Reject => {
            if id is Some(_) {
              raise StopIteration
            }
            return
          }
          Stop => raise StopIteration
          Accept => {
            result.push(self)
            if id is Some(_) {
              raise StopIteration
            }
          }
          Skip => if id is Some(_) { raise StopIteration }
        }
      None => {
        result.push(self)
        if id is Some(_) {
          raise StopIteration
        }
      }
    }
  }
  let recurse = fn(b : Node, ctx : Context?) raise StopIteration {
    b.find_by_internal(
      context=ctx,
      style~,
      role~,
      id~,
      traverse_documents~,
      filter~,
      result,
    )
  }
  match self.context {
    Document =>
      if context != Some(Document) {
        match self.doc().header {
          Some(h) if any_context || context == Some(Section) =>
            recurse(h, context)
          _ => ()
        }
        for b in self.blocks {
          if context == Some(Section) && b.context != Section {
            continue
          }
          recurse(b, context)
        }
      }
    Dlist =>
      if any_context || context != Some(Section) {
        for item in self.dlist_items {
          for t in item.terms {
            recurse(t, context)
          }
          if item.desc is Some(d) {
            recurse(d, context)
          }
        }
      }
    Table => {
      let rows = self.table_data().rows
      if traverse_documents {
        for r in rows.head {
          for c in r {
            recurse(c, context)
          }
        }
        let ctx2 = if context == Some(Custom("inner_document")) {
          Some(Document)
        } else {
          context
        }
        for section in [rows.body, rows.foot] {
          for r in section {
            for c in r {
              recurse(c, ctx2)
              if c.style == Some("asciidoc") {
                match c.cell_data().inner_document {
                  Some(d) => recurse(d, ctx2)
                  None => ()
                }
              }
            }
          }
        }
      } else {
        for section in [rows.head, rows.body, rows.foot] {
          for r in section {
            for c in r {
              recurse(c, context)
            }
          }
        }
      }
    }
    _ =>
      for b in self.blocks {
        if context == Some(Section) && b.context != Section {
          continue
        }
        recurse(b, context)
      }
  }
}

// ---------------------------------------------------------------------------
// Constructors

///|
/// Creates a block (Ruby `Block.new parent, context, opts`).
pub fn Node::new_block(
  parent : Node,
  context : Context,
  content_model? : ContentModel,
  subs? : BlockSubs,
  source? : Array[String],
  source_text? : String,
  attributes? : Attributes,
) -> Node {
  let b = Node::alloc(Some(parent), context, attributes?)
  b.content_model = match content_model {
    Some(cm) => cm
    None => default_content_model(context)
  }
  match subs {
    None => ()
    Some(DefaultSubs(ds)) => {
      b.default_subs = ds
      b.commit_subs()
    }
    Some(ExplicitSubs(list)) => {
      b.default_subs = Some(list.copy())
      b.attributes.remove("subs") |> ignore
      b.commit_subs()
    }
    Some(SubsSpec(spec)) => {
      b.default_subs = None
      b.attributes.set_str("subs", spec)
      b.commit_subs()
    }
    Some(NoSubs) => {
      b.default_subs = Some([])
      b.attributes.remove("subs") |> ignore
    }
  }
  match source {
    Some(lines) => b.lines = lines.copy()
    None =>
      match source_text {
        Some(t) if t != "" => b.lines = prepare_source_string(t)
        _ => ()
      }
  }
  b
}

///|
/// How the subs of a new block are specified (Ruby `opts[:subs]`).
pub(all) enum BlockSubs {
  DefaultSubs(Array[Sub]?) // :default with optional default_subs
  ExplicitSubs(Array[Sub]) // an Array of subs
  SubsSpec(String) // a subs attribute value
  NoSubs // nil / false
}

///|
fn default_content_model(context : Context) -> ContentModel {
  match context {
    Audio | Image | PageBreak | ThematicBreak | Video => Empty
    Listing | Literal => Verbatim
    Stem | Pass => Raw
    Open => Compound
    _ => Simple
  }
}

///|
/// Creates a section (Ruby `Section.new parent, level, numbered`).
pub fn Node::new_section(
  parent : Node?,
  level? : Int,
  numbered? : Bool = false,
  attributes? : Attributes,
) -> Node {
  let s = Node::alloc(parent, Section, attributes?)
  match parent {
    Some(p) if p.context == Section => {
      s.level = level.unwrap_or(p.level + 1)
      s.special = p.special
    }
    _ => s.level = level.unwrap_or(1)
  }
  s.numbered = if numbered { Numbered } else { NotNumbered }
  s
}

///|
/// Creates a list (Ruby `List.new parent, context`).
pub fn Node::new_list(
  parent : Node,
  context : Context,
  attributes? : Attributes,
) -> Node {
  Node::alloc(Some(parent), context, attributes?)
}

///|
/// Creates a list item (Ruby `ListItem.new list, text`).
pub fn Node::new_list_item(parent : Node, text? : String) -> Node {
  let li = Node::alloc(Some(parent), ListItem)
  li.text_ = text
  li.level = parent.level
  li.subs = normal_subs.copy()
  li
}

///|
/// Creates an inline node (Ruby `Inline.new parent, context, text, opts`).
pub fn Node::new_inline(
  parent : Node,
  context : Context,
  text? : String,
  id? : String,
  type_? : String,
  target? : String,
  attributes? : Attributes,
) -> Node {
  let n = Node::alloc(Some(parent), context, attributes?)
  n.node_name = "inline_\{context.name()}"
  n.text_ = text
  n.id = id
  n.inline_type = type_
  n.target = target
  n.level = 0
  n
}

// ---------------------------------------------------------------------------
// ListItem / Inline text

///|
/// The raw text of a list item, inline node or table cell.
pub fn Node::raw_text(self : Node) -> String? {
  match self.cell_ {
    Some(c) => Some(c.text)
    None => self.text_
  }
}

///|
pub fn Node::set_text(self : Node, text : String?) -> Unit {
  match self.cell_ {
    Some(c) => c.text = text.unwrap_or("")
    None => self.text_ = text
  }
}

///|
/// Converted text: for list items and cells the text with subs applied; for
/// inline nodes the raw text.
pub fn Node::text(self : Node) -> String? {
  if self.is_inline() {
    return self.text_
  }
  match self.cell_ {
    Some(c) => Some(self.apply_subs(c.text, self.subs))
    None =>
      match self.text_ {
        Some(t) => Some(self.apply_subs(t, self.subs))
        None => None
      }
  }
}

///|
pub fn Node::has_text(self : Node) -> Bool {
  match self.text_ {
    Some(t) => t != ""
    None => false
  }
}

///|
/// Whether a list item is simple (no blocks, or only a nested outline list).
pub fn Node::is_simple(self : Node) -> Bool {
  self.blocks.is_empty() ||
  (self.blocks.length() == 1 && self.blocks[0].is_outline())
}

///|
pub fn Node::is_compound(self : Node) -> Bool {
  !self.is_simple()
}

///|
/// Folds the first block into the text of a list item.
pub fn Node::fold_first(self : Node) -> Unit {
  let first = self.blocks.remove(0)
  self.text_ = match self.text_ {
    Some(t) if t != "" => Some("\{t}\n\{first.source()}")
    _ => Some(first.source())
  }
}

///|
/// The items of a list (for dlists, use `dlist_items`).
pub fn Node::items(self : Node) -> Array[Node] {
  self.blocks
}
