///|
/// A footnote registered in the document catalog.
pub(all) struct Footnote {
  index : Int
  id : String?
  text : String
} derive(Debug)

///|
/// An image reference registered in the catalog (when `catalog_assets` is set).
pub(all) struct ImageReference {
  target : String
  imagesdir : String?
} derive(Debug)

///|
/// Document catalog (Ruby `Document#catalog`).
pub struct Catalog {
  refs : Map[String, Node]
  footnotes : Array[Footnote]
  links : Array[String]
  images : Array[ImageReference]
  callouts : Callouts
  includes : Map[String, Bool] // value false == nil in Ruby (partial include)
}

///|
fn Catalog::new() -> Catalog {
  {
    refs: {},
    footnotes: [],
    links: [],
    images: [],
    callouts: Callouts::new(),
    includes: {},
  }
}

///|
/// Options for loading/converting a document (Ruby options Hash).
pub(all) struct Options {
  /// Attribute overrides in order; `Nil` unsets, `Bool(false)` soft-unsets,
  /// a trailing `@` on a string value or name makes it soft.
  mut attributes : Array[(String, AttrVal)]
  mut safe : Int?
  mut backend : String?
  mut doctype : String?
  mut standalone : Bool?
  mut base_dir : String?
  mut to_file : String?
  mut to_dir : String?
  mut mkdirs : Bool
  mut sourcemap : Bool
  mut parse_header_only : Bool
  mut catalog_assets : Bool
  mut parse : Bool
  /// Modification time of the input file (seconds since epoch), for docdate/doctime.
  mut input_mtime : Int64?
  mut converter : &Converter?
  mut extensions : Extensions?
  mut vfs : &Vfs?
  /// Records the time spent in each phase (Ruby `:timings` option).
  mut timings : Timings?
  mut syntax_highlighter_factory : ((String, String, Node) -> &SyntaxHighlighter?)?
  // nested document support
  mut parent : Node?
  mut cursor : Cursor?
}

///|
pub fn Options::new(
  attributes? : Array[(String, AttrVal)] = [],
  safe? : Int,
  backend? : String,
  doctype? : String,
  standalone? : Bool,
  base_dir? : String,
  to_file? : String,
  to_dir? : String,
  mkdirs? : Bool = false,
  sourcemap? : Bool = false,
  parse_header_only? : Bool = false,
  catalog_assets? : Bool = false,
  parse? : Bool = true,
  converter? : &Converter,
  extensions? : Extensions,
  vfs? : &Vfs,
  timings? : Timings,
) -> Options {
  {
    attributes,
    safe,
    backend,
    doctype,
    standalone,
    base_dir,
    to_file,
    to_dir,
    mkdirs,
    sourcemap,
    parse_header_only,
    catalog_assets,
    parse,
    input_mtime: None,
    converter,
    extensions,
    vfs,
    timings,
    syntax_highlighter_factory: None,
    parent: None,
    cursor: None,
  }
}

///|
fn Options::copy(self : Options) -> Options {
  { ..self, attributes: self.attributes.copy(), }
}

///|
/// Data specific to a document node (Ruby `Document` instance variables).
struct DocData {
  mut safe : Int
  mut compat_mode : Bool
  mut backend : String?
  mut doctype : String?
  mut sourcemap : Bool
  catalog : Catalog
  counters : Map[String, AttrVal]
  mut header : Node?
  mut base_dir : String
  options : Options
  mut outfilesuffix : String?
  mut parent_document : Node?
  mut reader : Reader?
  path_resolver : PathResolver
  mut converter : &Converter?
  mut syntax_highlighter : &SyntaxHighlighter?
  mut extensions : Extensions?
  attribute_overrides : Map[String, AttrVal]
  mut header_attributes : Attributes?
  mut max_attribute_value_size : Int?
  attributes_modified : Map[String, Bool]
  mut parsed : Bool
  mut reftexts : Map[String, String]?
  vfs : &Vfs
  docinfo_processor_extensions : Map[String, Bool]
  /// the error that aborted processing (see `Node::abort_processing`)
  mut error : Error?
}

///|
let default_attributes : Array[(String, String)] = [
  ("appendix-caption", "Appendix"),
  ("appendix-refsig", "Appendix"),
  ("caution-caption", "Caution"),
  ("chapter-refsig", "Chapter"),
  ("example-caption", "Example"),
  ("figure-caption", "Figure"),
  ("important-caption", "Important"),
  ("last-update-label", "Last updated"),
  ("note-caption", "Note"),
  ("part-refsig", "Part"),
  ("prewrap", ""),
  ("sectids", ""),
  ("section-refsig", "Section"),
  ("table-caption", "Table"),
  ("tip-caption", "Tip"),
  ("toc-placement", "auto"),
  ("toc-title", "Table of Contents"),
  ("untitled-label", "Untitled"),
  ("version-label", "Version"),
  ("warning-caption", "Warning"),
]

///|
/// Version of Asciidoctor this port tracks.
pub const VERSION : String = "2.1.0.alpha.0"

///|
pub const DEFAULT_BACKEND : String = "html5"

///|
pub const DEFAULT_DOCTYPE : String = "article"

///|
/// Creates a document (Ruby `Document.new data, options`). The document is
/// not parsed yet unless it is nested (has a parent).
pub fn new_document(data : Array[String]?, options : Options) -> Node {
  let options = options.copy()
  let vfs : &Vfs = match options.parent {
    Some(pd) => pd.doc().vfs
    None =>
      match options.vfs {
        Some(v) => v
        None => NullVfs::new()
      }
  }
  let doc = Node::alloc(None, Document)
  doc.level = 0
  let parent_doc = options.parent
  options.parent = None
  let attr_overrides : Map[String, AttrVal] = Map([])
  let attrs = doc.attributes
  let mut parent_doctype : String? = None
  let dd : DocData = match parent_doc {
    Some(pd) => {
      let pdd = pd.doc()
      if options.base_dir is None {
        options.base_dir = Some(pdd.base_dir)
      }
      if pdd.options.catalog_assets {
        options.catalog_assets = true
      }
      if pdd.options.to_dir is Some(d) {
        options.to_dir = Some(d)
      }
      for k, v in pdd.attribute_overrides {
        attr_overrides[k] = v
      }
      for k, v in pd.attributes.iter() {
        if k is Name(n) {
          attr_overrides[n] = v
        }
      }
      attr_overrides.remove("compat-mode")
      parent_doctype = match attr_overrides.get("doctype") {
        Some(v) if v.truthy() => Some(v.to_s())
        _ => None
      }
      attr_overrides.remove("doctype")
      attr_overrides.remove("notitle")
      attr_overrides.remove("showtitle")
      attr_overrides.remove("toc")
      attrs.set_str(
        "toc-placement",
        match attr_overrides.get("toc-placement") {
          Some(v) if v.truthy() => v.to_s()
          _ => "auto"
        },
      )
      attr_overrides.remove("toc-placement")
      attr_overrides.remove("toc-position")
      if pdd.compat_mode {
        attrs.set_str("compat-mode", "")
      }
      let catalog : Catalog = { ..pdd.catalog, footnotes: [], }
      {
        safe: pdd.safe,
        compat_mode: pdd.compat_mode,
        backend: None,
        doctype: None,
        sourcemap: pdd.sourcemap,
        catalog,
        counters: {},
        header: None,
        base_dir: "",
        options,
        outfilesuffix: pdd.outfilesuffix,
        parent_document: Some(pd),
        reader: None,
        path_resolver: pdd.path_resolver,
        converter: pdd.converter,
        syntax_highlighter: pdd.syntax_highlighter,
        extensions: pdd.extensions,
        attribute_overrides: attr_overrides,
        header_attributes: None,
        max_attribute_value_size: None,
        attributes_modified: {},
        parsed: false,
        reftexts: None,
        vfs: pdd.vfs,
        docinfo_processor_extensions: {},
        error: None,
      }
    }
    None => {
      for entry in options.attributes {
        let (key0, val0) = entry
        let mut key = key0
        let mut val = val0
        if key.has_suffix("@") {
          if key.has_prefix("!") {
            key = @rb.slice(key, 1, key.length() - 1)
            val = Bool(false)
          } else if key.has_suffix("!@") {
            key = @rb.slice(key, 0, key.length() - 2)
            val = Bool(false)
          } else {
            key = @rb.chop(key)
            val = Str("\{val.to_s()}@")
          }
        } else if key.has_prefix("!") {
          key = @rb.from(key, 1)
          val = if val.is_str("@") { Bool(false) } else { Nil }
        } else if key.has_suffix("!") {
          key = @rb.chop(key)
          val = if val.is_str("@") { Bool(false) } else { Nil }
        }
        attr_overrides[@rb.downcase(key)] = val
      }
      match options.to_file {
        Some(to_file) =>
          attr_overrides["outfilesuffix"] = Str(extname(to_file, fallback=""))
        None => ()
      }
      let safe = match options.safe {
        None => SAFE_SECURE
        Some(s) => s
      }
      {
        safe,
        compat_mode: attr_overrides.contains("compat-mode"),
        backend: None,
        doctype: None,
        sourcemap: options.sourcemap,
        catalog: Catalog::new(),
        counters: {},
        header: None,
        base_dir: "",
        options,
        outfilesuffix: None,
        parent_document: None,
        reader: None,
        path_resolver: PathResolver::new(working_dir=vfs.cwd()),
        converter: None,
        syntax_highlighter: None,
        extensions: None,
        attribute_overrides: attr_overrides,
        header_attributes: None,
        max_attribute_value_size: None,
        attributes_modified: {},
        parsed: false,
        reftexts: None,
        vfs,
        docinfo_processor_extensions: {},
        error: None,
      }
    }
  }
  doc.doc_ = Some(dd)
  let standalone = options.standalone.unwrap_or(false)
  if parent_doc is None {
    attrs.set_str("attribute-undefined", compliance.attribute_undefined)
    attrs.set_str("attribute-missing", compliance.attribute_missing)
    for p in default_attributes {
      attrs.set_str(p.0, p.1)
    }
  }
  if standalone {
    attr_overrides["embedded"] = Nil
    attrs.set_str("copycss", "")
    attrs.set_str("iconfont-remote", "")
    attrs.set_str("stylesheet", "")
    attrs.set_str("webfonts", "")
  } else {
    attr_overrides["embedded"] = Str("")
    let showtitle_last = {
      let mut last : String? = None
      for k, _ in attr_overrides {
        if k == "notitle" || k == "showtitle" {
          last = Some(k)
        }
      }
      last == Some("showtitle")
    }
    let flip = fn(v : AttrVal) -> AttrVal {
      match v {
        Nil => Str("")
        Bool(false) => Str("@")
        Str("@") => Bool(false)
        _ => Nil
      }
    }
    if attr_overrides.contains("showtitle") && showtitle_last {
      attr_overrides["notitle"] = flip(attr_overrides["showtitle"])
    } else if attr_overrides.contains("notitle") {
      attr_overrides["showtitle"] = flip(attr_overrides["notitle"])
    } else {
      attrs.set_str("notitle", "")
    }
  }
  attr_overrides["asciidoctor"] = Str("")
  attr_overrides["asciidoctor-version"] = Str(VERSION)
  // an unrecognized level has no name (Ruby: nil, which unsets the attribute)
  let safe_mode_name = safe_mode_name_for_value(dd.safe)
  attr_overrides["safe-mode-name"] = match safe_mode_name {
    Some(n) => Str(n)
    None => Nil
  }
  attr_overrides["safe-mode-\{safe_mode_name.unwrap_or("")}"] = Str("")
  attr_overrides["safe-mode-level"] = Int(dd.safe)
  or_set(attr_overrides, "max-include-depth", Int(64))
  or_set(attr_overrides, "allow-uri-read", Nil)
  if attr_overrides.contains("numbered") {
    attr_overrides["sectnums"] = attr_overrides["numbered"]
    attr_overrides.remove("numbered")
  }
  if attr_overrides.contains("hardbreaks") {
    attr_overrides["hardbreaks-option"] = attr_overrides["hardbreaks"]
    attr_overrides.remove("hardbreaks")
  }
  match options.base_dir {
    Some(b) => {
      let d = expand_path_from(vfs.cwd(), b)
      dd.base_dir = d
      attr_overrides["docdir"] = Str(d)
    }
    None =>
      match attr_overrides.get("docdir") {
        Some(v) if v.truthy() => dd.base_dir = v.to_s()
        _ => {
          let d = vfs.cwd()
          dd.base_dir = d
          attr_overrides["docdir"] = Str(d)
        }
      }
  }
  match options.backend {
    Some(b) => attr_overrides["backend"] = Str(b)
    None => ()
  }
  match options.doctype {
    Some(d) => attr_overrides["doctype"] = Str(d)
    None => ()
  }
  if dd.safe >= SAFE_SERVER {
    or_set(attr_overrides, "copycss", Nil)
    or_set(attr_overrides, "source-highlighter", Nil)
    or_set(attr_overrides, "backend", Str(DEFAULT_BACKEND))
    if parent_doc is None && attr_overrides.contains("docfile") {
      let docfile = attr_overrides["docfile"].to_s()
      let docdir = attr_overrides.get("docdir").map(v => v.to_s()).unwrap_or("")
      attr_overrides["docfile"] = Str(@rb.from(docfile, docdir.length() + 1))
    }
    attr_overrides["docdir"] = Str("")
    or_set(attr_overrides, "user-home", Str("."))
    if dd.safe >= SAFE_SECURE {
      if !attr_overrides.contains("max-attribute-value-size") {
        attr_overrides["max-attribute-value-size"] = Int(4096)
      }
      if !attr_overrides.contains("linkcss") {
        attr_overrides["linkcss"] = Str("")
      }
      or_set(attr_overrides, "icons", Nil)
    }
  } else {
    or_set(attr_overrides, "user-home", Str(vfs.home()))
  }
  or_set(attr_overrides, "max-attribute-value-size", Nil)
  dd.max_attribute_value_size = match
    attr_overrides.get("max-attribute-value-size") {
    Some(v) if v.truthy() => Some(v.to_i().abs())
    _ => None
  }
  // apply overrides, removing soft ones from the override (lock) map
  let soft = []
  for key, val in attr_overrides {
    if val.truthy() {
      match val {
        Str(s) if s.has_suffix("@") => {
          attrs.set_str(key, @rb.chop(s))
          soft.push(key)
        }
        _ => attrs.set(key, val)
      }
    } else {
      attrs.remove(key) |> ignore
      if val == Bool(false) {
        soft.push(key)
      }
    }
  }
  for k in soft {
    attr_overrides.remove(k)
  }
  match parent_doc {
    Some(_) => {
      dd.backend = attrs.str("backend")
      dd.doctype = parent_doctype
      match parent_doctype {
        Some(pdt) => attrs.set_str("doctype", pdt)
        None => attrs.remove("doctype") |> ignore
      }
      if parent_doctype != Some(DEFAULT_DOCTYPE) {
        doc.update_doctype_attributes(DEFAULT_DOCTYPE)
      }
      dd.doctype = attrs.str("doctype")
      let reader = Reader::new(data.unwrap_or([]), cursor?=options.cursor)
      dd.reader = Some(reader)
      if dd.sourcemap {
        doc.source_location = Some(reader.cursor())
      }
      parse_document(reader, doc, header_only=false)
      doc.restore_attributes()
      dd.parsed = true
    }
    None => {
      let initial_backend = attrs.str("backend").unwrap_or(DEFAULT_BACKEND)
      if initial_backend == "manpage" {
        attrs.set_str("doctype", "manpage")
        attr_overrides["doctype"] = Str("manpage")
        dd.doctype = Some("manpage")
      } else {
        attrs.set_default("doctype", Str(DEFAULT_DOCTYPE))
        dd.doctype = attrs.str("doctype")
      }
      doc.update_backend_attributes(initial_backend, init=true) |> ignore
      attrs.set_default("stylesdir", Str("."))
      attrs.set_default(
        "iconsdir",
        Str("\{attrs.str("imagesdir").unwrap_or("./images")}/icons"),
      )
      fill_datetime_attributes(attrs, options.input_mtime)
      dd.extensions = match options.extensions {
        Some(e) => Some(e.activate(doc))
        None =>
          match global_extensions() {
            Some(e) => Some(e.activate(doc))
            None => None
          }
      }
      let reader = Reader::new_preprocessor(
        doc,
        data.unwrap_or([]),
        cursor=Cursor::new(file?=attrs.str("docfile"), dir=dd.base_dir),
        normalize=true,
      )
      dd.reader = Some(reader)
      if dd.sourcemap {
        doc.source_location = Some(reader.cursor())
      }
    }
  }
  doc
}

///|
fn or_set(m : Map[String, AttrVal], key : String, v : AttrVal) -> Unit {
  match m.get(key) {
    Some(existing) if existing.truthy() => ()
    _ => m[key] = v
  }
}

///|
/// Parses the document (Ruby `Document#parse`).
pub fn Node::parse(self : Node, data? : Array[String]) -> Node {
  let dd = self.doc()
  if dd.parsed {
    return self
  }
  if self.processing_error() is Some(_) {
    // Ruby raises before parsing (e.g. missing converter)
    dd.parsed = true
    return self
  }
  let mut doc = self
  match data {
    Some(d) => {
      let reader = Reader::new_preprocessor(
        self,
        d,
        cursor=Cursor::new(
          file?=self.attributes.str("docfile"),
          dir=dd.base_dir,
        ),
        normalize=true,
      )
      dd.reader = Some(reader)
      if dd.sourcemap {
        self.source_location = Some(reader.cursor())
      }
    }
    None => ()
  }
  let exts = if dd.parent_document is None { dd.extensions } else { None }
  match exts {
    Some(e) =>
      for p in e.preprocessors() {
        match
          ((p.process)(self, dd.reader.unwrap()) catch {
            e => {
              self.abort_processing(e)
              None
            }
          }) {
          Some(r) => dd.reader = Some(r)
          None => ()
        }
      }
    None => ()
  }
  parse_document(
    dd.reader.unwrap(),
    self,
    header_only=dd.options.parse_header_only,
  )
  self.restore_attributes()
  match exts {
    Some(e) =>
      for t in e.tree_processors() {
        match
          ((t.process)(doc) catch {
            e => {
              doc.abort_processing(e)
              None
            }
          }) {
          Some(result) if result.context == Document &&
            !physical_equal(result, doc) => doc = result
          _ => ()
        }
      }
    None => ()
  }
  dd.parsed = true
  doc
}

///|
pub fn Node::is_parsed(self : Node) -> Bool {
  self.doc().parsed
}

///|
pub fn Node::safe(self : Node) -> Int {
  self.doc().safe
}

///|
pub fn Node::compat_mode(self : Node) -> Bool {
  self.doc().compat_mode
}

///|
pub fn Node::backend(self : Node) -> String {
  self.doc().backend.unwrap_or("")
}

///|
pub fn Node::doctype(self : Node) -> String {
  self.doc().doctype.unwrap_or("")
}

///|
pub fn Node::sourcemap(self : Node) -> Bool {
  self.doc().sourcemap
}

///|
/// Ruby `Document#sourcemap=`: enables source mapping before parsing.
pub fn Node::set_sourcemap(self : Node, value : Bool) -> Unit {
  self.doc().sourcemap = value
}

///|
pub fn Node::catalog(self : Node) -> Catalog {
  self.doc().catalog
}

///|
pub fn Node::base_dir(self : Node) -> String {
  self.doc().base_dir
}

///|
pub fn Node::options(self : Node) -> Options {
  self.doc().options
}

///|
pub fn Node::outfilesuffix(self : Node) -> String {
  self.doc().outfilesuffix.unwrap_or("")
}

///|
pub fn Node::parent_document(self : Node) -> Node? {
  self.doc().parent_document
}

///|
pub fn Node::path_resolver(self : Node) -> PathResolver {
  self.doc().path_resolver
}

///|
pub fn Node::syntax_highlighter(self : Node) -> &SyntaxHighlighter? {
  self.doc().syntax_highlighter
}

///|
pub fn Node::extensions(self : Node) -> Extensions? {
  self.doc().extensions
}

///|
pub fn Node::vfs(self : Node) -> &Vfs {
  self.doc().vfs
}

///|
/// The document header section, if any.
pub fn Node::header(self : Node) -> Node? {
  self.doc().header
}

///|
pub fn Node::has_header(self : Node) -> Bool {
  self.doc().header is Some(_)
}

///|
/// The converter of the document.
pub fn Node::converter(self : Node) -> &Converter {
  match self.doc().converter {
    Some(c) => c
    None => abort("no converter")
  }
}

///|
/// Ruby `Document#counter(name, seed)`.
pub fn Node::counter(self : Node, name : String, seed? : String) -> String {
  let dd = self.doc()
  match dd.parent_document {
    Some(p) => return p.counter(name, seed?)
    None => ()
  }
  let locked = self.attribute_locked(name)
  let curr_val = if locked {
    dd.counters.get(name)
  } else {
    match self.attributes.get(name) {
      Some(v) if v.truthy() && v.to_s() != "" => Some(v)
      _ => None
    }
  }
  let curr_val = match curr_val {
    Some(v) => Some(v)
    None =>
      if !locked {
        None
      } else {
        match self.attributes.get(name) {
          Some(v) if v.truthy() && v.to_s() != "" => Some(v)
          _ => None
        }
      }
  }
  let next_val : AttrVal = match curr_val {
    Some(v) => nextval(v)
    None =>
      match seed {
        Some(s) =>
          match @rb.parse_int(s) {
            Some(i) if i.to_string() == s => Int(i)
            _ => Str(s)
          }
        None => Int(1)
      }
  }
  dd.counters[name] = next_val
  if !locked {
    self.attributes.set(name, next_val)
  }
  next_val.to_s()
}

///|
/// Ruby `Helpers.nextval`.
fn nextval(current : AttrVal) -> AttrVal {
  match current {
    Int(i) => Int(i + 1)
    _ => {
      let s = current.to_s()
      let i = @rb.to_i(s)
      if i.to_string() == s {
        Int(i + 1)
      } else {
        Str(@rb.succ(s))
      }
    }
  }
}

///|
/// Increments a counter and records an attribute entry on `block`.
pub fn Node::increment_and_store_counter(
  self : Node,
  counter_name : String,
  block : Node,
) -> String {
  let v = self.counter(counter_name)
  block.attributes.save_entry(AttributeEntry::new(counter_name, Some(v)))
  v
}

///|
/// Registers a reference; returns false if the id is already taken.
pub fn Node::register_ref(self : Node, id : String, node : Node) -> Bool {
  let refs = self.doc().catalog.refs
  if refs.contains(id) {
    false
  } else {
    refs[id] = node
    true
  }
}

///|
pub fn Node::register_footnote(self : Node, fn_ : Footnote) -> Unit {
  self.doc().catalog.footnotes.push(fn_)
}

///|
pub fn Node::register_link(self : Node, target : String) -> Unit {
  if self.doc().options.catalog_assets {
    self.doc().catalog.links.push(target)
  }
}

///|
pub fn Node::register_image(self : Node, target : String) -> Unit {
  if self.doc().options.catalog_assets {
    self.doc().catalog.images.push({
      target,
      imagesdir: self.attributes.str("imagesdir"),
    })
  }
}

///|
/// Resolves an id from reference text (Ruby `resolve_id`).
pub fn Node::resolve_id(self : Node, text : String) -> String? {
  let dd = self.doc()
  match dd.reftexts {
    Some(m) => m.get(text)
    None =>
      if dd.parsed {
        let accum : Map[String, String] = Map([])
        dd.reftexts = Some(accum)
        for id, ref_ in dd.catalog.refs {
          match ref_.xreftext() {
            Some(x) => if !accum.contains(x) { accum[x] = id }
            None => ()
          }
        }
        accum.get(text)
      } else {
        // publish a partial map so recursive lookups terminate (Ruby semantics)
        let accum : Map[String, String] = Map([])
        dd.reftexts = Some(accum)
        let mut resolved = None
        for id, ref_ in dd.catalog.refs {
          let xreftext = ref_.xreftext()
          if xreftext == Some(text) {
            resolved = Some(id)
            break
          }
          match xreftext {
            Some(x) => if !accum.contains(x) { accum[x] = id }
            None => ()
          }
        }
        dd.reftexts = None
        resolved
      }
  }
}

///|
/// Whether a book document has parts.
pub fn Node::is_multipart(self : Node) -> Bool {
  if self.doctype() != "book" {
    return false
  }
  for b in self.blocks {
    if b.context != Section {
      continue
    }
    if b.level == 0 {
      return true
    } else if !b.special {
      return false
    }
  }
  false
}

///|
pub fn Node::footnotes(self : Node) -> Array[Footnote] {
  self.doc().catalog.footnotes
}

///|
pub fn Node::has_footnotes(self : Node) -> Bool {
  !self.doc().catalog.footnotes.is_empty()
}

///|
pub fn Node::callouts(self : Node) -> Callouts {
  self.doc().catalog.callouts
}

///|
pub fn Node::is_nested(self : Node) -> Bool {
  self.doc().parent_document is Some(_)
}

///|
pub fn Node::is_embedded(self : Node) -> Bool {
  self.attributes.contains("embedded")
}

///|
pub fn Node::has_extensions(self : Node) -> Bool {
  self.doc().extensions is Some(_)
}

///|
/// The reader of the document (Ruby `Document#reader`); None before the
/// document has a source.
pub fn Node::reader(self : Node) -> Reader? {
  self.doc().reader
}

///|
/// The normalized source of the document.
pub fn Node::doc_source(self : Node) -> String? {
  self.doc().reader.map(r => r.source())
}

///|
pub fn Node::source_lines(self : Node) -> Array[String]? {
  self.doc().reader.map(r => r.source_lines)
}

///|
pub fn Node::is_basebackend(self : Node, base : String) -> Bool {
  self.attributes.str("basebackend") == Some(base)
}

///|
/// A parsed document title (Ruby `Document::Title`).
pub(all) struct DocTitle {
  main : String
  subtitle : String?
  combined : String
  sanitized : Bool
} derive(Debug)

///|
pub fn DocTitle::new(
  val : String,
  sanitize? : Bool = false,
  separator? : String,
) -> DocTitle {
  let mut val = val
  if sanitize && val.contains("<") {
    val = @rb.strip(@rb.squeeze(xml_sanitize_rx.gsub(val, ""), chars=" "))
  }
  let sep = separator.unwrap_or(":")
  let sep2 = "\{sep} "
  if sep == "" || !val.contains(sep2) {
    { main: val, subtitle: None, combined: val, sanitized: sanitize, }
  } else {
    let (main, _, sub) = @rb.rpartition(val, sep2)
    { main, subtitle: Some(sub), combined: val, sanitized: sanitize, }
  }
}

///|
pub fn DocTitle::has_subtitle(self : DocTitle) -> Bool {
  self.subtitle is Some(_)
}

///|
/// Ruby `Document#doctitle(opts)` without partitioning.
pub fn Node::doctitle(
  self : Node,
  use_fallback? : Bool = false,
  sanitize? : Bool = false,
) -> String? {
  let doc = self.document()
  let val = match doc.attributes.str("title") {
    Some(v) => v
    None =>
      match doc.first_section() {
        Some(sect) => sect.title().unwrap_or("")
        None =>
          if use_fallback {
            match doc.attributes.str("untitled-label") {
              Some(v) => v
              None => return None
            }
          } else {
            return None
          }
      }
  }
  if sanitize && val.contains("<") {
    Some(@rb.strip(@rb.squeeze(xml_sanitize_rx.gsub(val, ""), chars=" ")))
  } else {
    Some(val)
  }
}

///|
/// Ruby `Document#doctitle(partition: ...)`.
pub fn Node::doctitle_partitioned(
  self : Node,
  use_fallback? : Bool = false,
  sanitize? : Bool = false,
  separator? : String,
) -> DocTitle? {
  let doc = self.document()
  let val = match doc.attributes.str("title") {
    Some(v) => v
    None =>
      match doc.first_section() {
        Some(sect) => sect.title().unwrap_or("")
        None =>
          if use_fallback {
            match doc.attributes.str("untitled-label") {
              Some(v) => v
              None => return None
            }
          } else {
            return None
          }
      }
  }
  let sep = match separator {
    Some(s) => Some(s)
    None => doc.attributes.str("title-separator")
  }
  Some(DocTitle::new(val, sanitize~, separator?=sep))
}

///|
/// A document author (Ruby `Document::Author`).
pub(all) struct Author {
  name : String?
  firstname : String?
  middlename : String?
  lastname : String?
  initials : String?
  email : String?
} derive(Debug)

///|
pub fn Node::author(self : Node) -> String? {
  self.attributes.str("author")
}

///|
pub fn Node::authors(self : Node) -> Array[Author] {
  let attrs = self.attributes
  if !attrs.contains("author") {
    return []
  }
  let authors = [
    {
      name: attrs.str("author"),
      firstname: attrs.str("firstname"),
      middlename: attrs.str("middlename"),
      lastname: attrs.str("lastname"),
      initials: attrs.str("authorinitials"),
      email: attrs.str("email"),
    },
  ]
  let num = match attrs.get("authorcount") {
    Some(v) => v.to_i()
    None => 0
  }
  for idx in 2..<=num {
    authors.push({
      name: attrs.str("author_\{idx}"),
      firstname: attrs.str("firstname_\{idx}"),
      middlename: attrs.str("middlename_\{idx}"),
      lastname: attrs.str("lastname_\{idx}"),
      initials: attrs.str("authorinitials_\{idx}"),
      email: attrs.str("email_\{idx}"),
    })
  }
  authors
}

///|
pub fn Node::revdate(self : Node) -> String? {
  self.attributes.str("revdate")
}

///|
pub fn Node::notitle(self : Node) -> Bool {
  self.attributes.contains("notitle")
}

///|
pub fn Node::noheader(self : Node) -> Bool {
  self.attributes.contains("noheader")
}

///|
pub fn Node::nofooter(self : Node) -> Bool {
  self.attributes.contains("nofooter")
}

///|
/// The header, or the first section.
pub fn Node::first_section(self : Node) -> Node? {
  match self.doc().header {
    Some(h) => Some(h)
    None => {
      for b in self.blocks {
        if b.context == Section {
          return Some(b)
        }
      }
      None
    }
  }
}

///|
fn Node::finalize_header(
  self : Node,
  unrooted_attributes : Attributes,
  header_valid? : Bool = true,
) -> Attributes {
  unrooted_attributes.clear_entries()
  self.save_attributes()
  if !header_valid {
    unrooted_attributes.set("invalid-header", Bool(true))
  }
  unrooted_attributes
}

///|
/// Replays attribute entries recorded on a block (Ruby `playback_attributes`).
pub fn Node::playback_attributes(
  self : Node,
  block_attributes : Attributes,
) -> Unit {
  guard block_attributes.entries is Some(entries) else { return }
  let dd = self.doc()
  for entry in entries {
    let name = entry.name
    if entry.negate {
      self.attributes.remove(name) |> ignore
      if name == "compat-mode" {
        dd.compat_mode = false
      }
    } else {
      self.attributes.set(name, Str(entry.value.unwrap_or("")))
      if name == "compat-mode" {
        dd.compat_mode = true
      }
    }
  }
}

///|
/// Restores the attributes to the snapshot taken at the end of the header
/// (Ruby `Document#restore_attributes`).
pub fn Node::restore_attributes(self : Node) -> Unit {
  let dd = self.doc()
  if dd.parent_document is None {
    dd.catalog.callouts.rewind()
  }
  match dd.header_attributes {
    Some(h) => self.attributes.replace(h)
    None => ()
  }
}

///|
/// Sets a document attribute unless locked; returns the resolved value.
pub fn Node::set_attribute(
  self : Node,
  name : String,
  value? : String = "",
) -> String? {
  if self.attribute_locked(name) {
    return None
  }
  let dd = self.doc()
  let value = if value != "" {
    self.apply_attribute_value_subs(value)
  } else {
    value
  }
  if dd.header_attributes is Some(_) {
    self.attributes.set_str(name, value)
  } else {
    match name {
      "backend" => {
        let was_modified = dd.attributes_modified.contains("htmlsyntax")
        dd.attributes_modified.remove("htmlsyntax")
        self.update_backend_attributes(
          value,
          init=was_modified && Some(value) == dd.backend,
        )
        |> ignore
      }
      "doctype" => self.update_doctype_attributes(value)
      _ => self.attributes.set_str(name, value)
    }
    dd.attributes_modified[name] = true
  }
  Some(value)
}

///|
/// Deletes a document attribute unless locked.
pub fn Node::delete_attribute(self : Node, name : String) -> Bool {
  if self.attribute_locked(name) {
    false
  } else {
    self.attributes.remove(name) |> ignore
    self.doc().attributes_modified[name] = true
    true
  }
}

///|
/// Whether the attribute is locked by an API/CLI override.
pub fn Node::attribute_locked(self : Node, name : String) -> Bool {
  self.doc().attribute_overrides.contains(name)
}

///|
/// Ruby's `@attributes_modified.include? name`: whether an attribute entry
/// changed the attribute, as Ruby records it — an entry in the header that
/// sets or unsets it, or one in the body that unsets it (a body entry that
/// sets an attribute is not recorded). Entries for a locked attribute (one
/// set by the API, or by the safe mode, such as `icons` when secure) are
/// ignored and not recorded.
pub fn Node::attribute_modified(self : Node, name : String) -> Bool {
  self.doc().attributes_modified.contains(name)
}

///|
/// Sets an attribute in the header attribute snapshot.
pub fn Node::set_header_attribute(
  self : Node,
  name : String,
  value? : String = "",
  overwrite? : Bool = true,
) -> Bool {
  let attrs = match self.doc().header_attributes {
    Some(h) => h
    None => self.attributes
  }
  if !overwrite && attrs.contains(name) {
    false
  } else {
    attrs.set_str(name, value)
    true
  }
}

///|
fn Node::apply_attribute_value_subs(self : Node, value : String) -> String {
  let v = match attribute_entry_pass_macro_rx.find(value) {
    Some(m) => {
      let v2 = m.at(2)
      match m.group(1) {
        Some(spec) => self.apply_subs(v2, self.resolve_pass_subs(spec))
        None => v2
      }
    }
    None => self.apply_header_subs(value)
  }
  match self.doc().max_attribute_value_size {
    Some(max) => @rb.limit_bytesize(v, max)
    None => v
  }
}

///|
fn Node::save_attributes(self : Node) -> Unit {
  let dd = self.doc()
  let attrs = self.attributes
  if !attrs.contains("doctitle") {
    match self.doctitle() {
      Some(v) => attrs.set_str("doctitle", v)
      None => ()
    }
  }
  if self.id is None {
    self.id = attrs.str("css-signature")
  }
  let toc_val = if attrs.remove("toc2") is Some(_) {
    Some("left")
  } else {
    attrs.str("toc")
  }
  match toc_val {
    Some(toc_val) => {
      let toc_placement_val = match attrs.get("toc-placement") {
        Some(v) => if v.truthy() { Some(v.to_s()) } else { None }
        None => Some("macro")
      }
      let toc_position_val = match toc_placement_val {
        Some(p) if p != "auto" => Some(p)
        _ => attrs.str("toc-position")
      }
      let pos_empty = match toc_position_val {
        Some(p) => p == ""
        None => true
      }
      if !(toc_val == "" && pos_empty) {
        let mut default_toc_class : String? = Some("toc2")
        let position = if pos_empty {
          if toc_val == "" {
            "left"
          } else {
            toc_val
          }
        } else {
          toc_position_val.unwrap()
        }
        attrs.set_str("toc", "")
        attrs.set_str("toc-placement", "auto")
        match position {
          "left" | "<" | "&lt;" => attrs.set_str("toc-position", "left")
          "right" | ">" | "&gt;" => attrs.set_str("toc-position", "right")
          "top" | "^" => attrs.set_str("toc-position", "top")
          "bottom" | "v" => attrs.set_str("toc-position", "bottom")
          "preamble" | "macro" => {
            attrs.set_str("toc-position", "content")
            attrs.set_str("toc-placement", position)
            default_toc_class = None
          }
          _ => {
            attrs.remove("toc-position") |> ignore
            default_toc_class = None
          }
        }
        match default_toc_class {
          Some(c) => attrs.set_default("toc-class", Str(c))
          None => ()
        }
      }
    }
    None => ()
  }
  match attrs.str("icons") {
    Some(icons_val) if !attrs.contains("icontype") =>
      if icons_val != "" && icons_val != "font" {
        attrs.set_str("icons", "")
        if icons_val != "image" {
          attrs.set_str("icontype", icons_val)
        }
      }
    _ => ()
  }
  dd.compat_mode = attrs.contains("compat-mode")
  if dd.compat_mode && attrs.contains("language") {
    attrs.set("source-language", attrs.get("language").unwrap())
  }
  if dd.parent_document is None {
    let basebackend = attrs.str("basebackend")
    if basebackend == Some("html") {
      match attrs.str("source-highlighter") {
        Some(name) if !attrs.truthy("\{name}-unavailable") =>
          dd.syntax_highlighter = match dd.options.syntax_highlighter_factory {
            Some(f) => f(name, dd.backend.unwrap_or(""), self)
            None =>
              create_syntax_highlighter(name, dd.backend.unwrap_or(""), self)
          }
        _ => ()
      }
    } else if basebackend == Some("docbook") {
      if !self.attribute_locked("toc") &&
        !dd.attributes_modified.contains("toc") {
        attrs.set_str("toc", "")
      }
      if !self.attribute_locked("sectnums") &&
        !dd.attributes_modified.contains("sectnums") {
        attrs.set_str("sectnums", "")
      }
    }
    dd.outfilesuffix = attrs.str("outfilesuffix")
    for name in ["sectnums"] {
      match dd.attribute_overrides.get(name) {
        Some(v) if v.truthy() => dd.attribute_overrides.remove(name)
        _ => ()
      }
    }
  }
  dd.header_attributes = Some(attrs.copy())
}

///|
/// Assigns localdate, localtime, docdate, ... (Ruby `fill_datetime_attributes`).
/// The current time comes from the `SOURCE_DATE_EPOCH`-like hook `now_epoch`.
fn fill_datetime_attributes(attrs : Attributes, input_mtime : Int64?) -> Unit {
  let sde = source_date_epoch_ref.val
  let now = match sde {
    Some(e) => e
    None => now_epoch()
  }
  let (date, year, time) = format_epoch(now, in_local_zone=sde is None)
  let localdate = match attrs.str("localdate") {
    Some(d) => {
      if !attrs.truthy("localyear") {
        match d.find("-") {
          Some(4) => attrs.set_str("localyear", @rb.slice(d, 0, 4))
          _ => attrs.set("localyear", Nil)
        }
      }
      d
    }
    None => {
      attrs.set_str("localdate", date)
      attrs.set_default("localyear", Str(year))
      date
    }
  }
  attrs.set_default("localtime", Str(time))
  let localtime = attrs.str("localtime").unwrap_or("")
  attrs.set_default("localdatetime", Str("\{localdate} \{localtime}"))
  let doc_epoch = match sde {
    Some(e) => e
    None =>
      match input_mtime {
        Some(m) => m
        None => now
      }
  }
  let (ddate, dyear, dtime) = format_epoch(doc_epoch, in_local_zone=sde is None)
  let docdate = match attrs.str("docdate") {
    Some(d) => {
      if !attrs.truthy("docyear") {
        match d.find("-") {
          Some(4) => attrs.set_str("docyear", @rb.slice(d, 0, 4))
          _ => attrs.set("docyear", Nil)
        }
      }
      d
    }
    None => {
      attrs.set_str("docdate", ddate)
      attrs.set_default("docyear", Str(dyear))
      ddate
    }
  }
  attrs.set_default("doctime", Str(dtime))
  let doctime = attrs.str("doctime").unwrap_or("")
  attrs.set_default("docdatetime", Str("\{docdate} \{doctime}"))
}

///|
/// Hook returning the current time in seconds since the epoch (UTC).
let now_epoch_ref : Ref[() -> Int64] = {
  val: () => (@env.now() / 1000UL).reinterpret_as_int64(),
}

///|
/// SOURCE_DATE_EPOCH: when set, pins both local and document dates.
let source_date_epoch_ref : Ref[Int64?] = { val: None, }

///|
fn now_epoch() -> Int64 {
  (now_epoch_ref.val)()
}

///|
/// Sets the clock used for date attributes.
pub fn set_now_epoch(f : () -> Int64) -> Unit {
  now_epoch_ref.val = f
}

///|
/// Hook returning the local time zone's offset from UTC (seconds) at a given
/// epoch second; the default is UTC.
let utc_offset_ref : Ref[(Int64) -> Int] = { val: _ => 0, }

///|
/// Sets the local time zone used for `localtime`, `doctime` and friends (the
/// core defaults to UTC; `@io` and the CLI install the system time zone).
/// `offset(epoch)` returns the offset from UTC in seconds at `epoch`.
pub fn set_utc_offset(offset : (Int64) -> Int) -> Unit {
  utc_offset_ref.val = offset
}

///|
/// Sets (or clears) SOURCE_DATE_EPOCH (reproducible builds).
pub fn set_source_date_epoch(epoch : Int64?) -> Unit {
  source_date_epoch_ref.val = epoch
}

///|
/// Formats `secs` as Ruby's `%F`, `%Y` and `%T %z` (or `%T UTC` when the
/// offset is zero); `in_local_zone` applies the local time zone, otherwise UTC.
fn format_epoch(
  secs : Int64,
  in_local_zone~ : Bool,
) -> (String, String, String) {
  let offset = if in_local_zone { (utc_offset_ref.val)(secs) } else { 0 }
  let secs = secs + offset.to_int64()
  let days = (secs / 86400L).to_int()
  let rem = (secs % 86400L).to_int()
  // civil from days (Howard Hinnant)
  let z = days + 719468
  let era = (if z >= 0 { z } else { z - 146096 }) / 146097
  let doe = z - era * 146097
  let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
  let y = yoe + era * 400
  let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
  let mp = (5 * doy + 2) / 153
  let d = doy - (153 * mp + 2) / 5 + 1
  let m = if mp < 10 { mp + 3 } else { mp - 9 }
  let y = if m <= 2 { y + 1 } else { y }
  let pad = fn(n : Int) { if n < 10 { "0\{n}" } else { n.to_string() } }
  let date = "\{y}-\{pad(m)}-\{pad(d)}"
  let zone = if offset == 0 {
    "UTC"
  } else {
    let a = offset.abs() / 60
    "\{if offset < 0 { "-" } else { "+" }}\{pad(a / 60)}\{pad(a % 60)}"
  }
  let time = "\{pad(rem / 3600)}:\{pad(rem % 3600 / 60)}:\{pad(rem % 60)} \{zone}"
  (date, y.to_string(), time)
}

///|
let backend_aliases : Map[String, String] = {
  "html": "html5",
  "docbook": "docbook5",
}

///|
/// Updates the backend attributes (Ruby `update_backend_attributes`).
fn Node::update_backend_attributes(
  self : Node,
  new_backend : String,
  init? : Bool = false,
) -> String? {
  let dd = self.doc()
  if !init && Some(new_backend) == dd.backend {
    return None
  }
  let attrs = self.attributes
  let current_backend = dd.backend
  let current_basebackend = attrs.str("basebackend")
  let current_doctype = dd.doctype
  let mut new_backend = new_backend
  let mut actual_backend : String? = None
  if new_backend.contains(":") {
    let (a, _, b) = @rb.partition(new_backend, ":")
    actual_backend = Some(a)
    new_backend = b
  }
  if new_backend.has_prefix("xhtml") {
    attrs.set_str("htmlsyntax", "xml")
    new_backend = @rb.from(new_backend, 1)
  } else if new_backend.has_prefix("html") {
    attrs.set_default("htmlsyntax", Str("html"))
  }
  new_backend = backend_aliases.get(new_backend).unwrap_or(new_backend)
  let mut delegate_backend : String? = None
  match actual_backend {
    Some(a) => {
      delegate_backend = Some(new_backend)
      new_backend = a
    }
    None => ()
  }
  match current_doctype {
    Some(cd) => {
      match current_backend {
        Some(cb) => {
          attrs.remove("backend-\{cb}") |> ignore
          attrs.remove("backend-\{cb}-doctype-\{cd}") |> ignore
        }
        None => ()
      }
      attrs.set_str("backend-\{new_backend}-doctype-\{cd}", "")
      attrs.set_str("doctype-\{cd}", "")
    }
    None =>
      match current_backend {
        Some(cb) => attrs.remove("backend-\{cb}") |> ignore
        None => ()
      }
  }
  attrs.set_str("backend-\{new_backend}", "")
  dd.backend = Some(new_backend)
  attrs.set_str("backend", new_backend)
  let converter = self.create_converter(new_backend, delegate_backend)
  let traits = match converter {
    Some(c) => c.backend_traits()
    None => {
      // no converter registered: Ruby raises NotImplementedError here; record
      // the error (processing stops) and derive traits from the backend name
      self.abort_processing(MissingConverter(new_backend))
      derive_backend_traits(new_backend)
    }
  }
  match traits.htmlsyntax {
    Some(h) => attrs.set_str("htmlsyntax", h)
    None => ()
  }
  if init {
    attrs.set_default("outfilesuffix", Str(traits.outfilesuffix))
  } else if !self.attribute_locked("outfilesuffix") {
    attrs.set_str("outfilesuffix", traits.outfilesuffix)
  }
  dd.converter = match converter {
    Some(c) => Some(c)
    None => Some(({ traits, } : NullConverter))
  }
  match attrs.str("filetype") {
    Some(ft) => attrs.remove("filetype-\{ft}") |> ignore
    None => ()
  }
  attrs.set_str("filetype", traits.filetype)
  attrs.set_str("filetype-\{traits.filetype}", "")
  let new_basebackend = traits.basebackend
  if new_basebackend == "docbook" {
    attrs.set("pagewidth", Int(425))
  } else {
    attrs.remove("pagewidth") |> ignore
  }
  if Some(new_basebackend) != current_basebackend {
    match current_doctype {
      Some(cd) => {
        match current_basebackend {
          Some(cbb) => {
            attrs.remove("basebackend-\{cbb}") |> ignore
            attrs.remove("basebackend-\{cbb}-doctype-\{cd}") |> ignore
          }
          None => ()
        }
        attrs.set_str("basebackend-\{new_basebackend}-doctype-\{cd}", "")
      }
      None =>
        match current_basebackend {
          Some(cbb) => attrs.remove("basebackend-\{cbb}") |> ignore
          None => ()
        }
    }
    attrs.set_str("basebackend-\{new_basebackend}", "")
    attrs.set_str("basebackend", new_basebackend)
  }
  Some(new_backend)
}

///|
fn Node::update_doctype_attributes(self : Node, new_doctype : String) -> Unit {
  let dd = self.doc()
  if Some(new_doctype) == dd.doctype {
    return
  }
  let attrs = self.attributes
  let current_backend = dd.backend
  let current_basebackend = attrs.str("basebackend")
  match dd.doctype {
    Some(cd) => {
      attrs.remove("doctype-\{cd}") |> ignore
      match current_backend {
        Some(cb) => {
          attrs.remove("backend-\{cb}-doctype-\{cd}") |> ignore
          attrs.set_str("backend-\{cb}-doctype-\{new_doctype}", "")
        }
        None => ()
      }
      match current_basebackend {
        Some(cbb) => {
          attrs.remove("basebackend-\{cbb}-doctype-\{cd}") |> ignore
          attrs.set_str("basebackend-\{cbb}-doctype-\{new_doctype}", "")
        }
        None => ()
      }
    }
    None => {
      match current_backend {
        Some(cb) => attrs.set_str("backend-\{cb}-doctype-\{new_doctype}", "")
        None => ()
      }
      match current_basebackend {
        Some(cbb) =>
          attrs.set_str("basebackend-\{cbb}-doctype-\{new_doctype}", "")
        None => ()
      }
    }
  }
  attrs.set_str("doctype-\{new_doctype}", "")
  dd.doctype = Some(new_doctype)
  attrs.set_str("doctype", new_doctype)
}

///|
fn Node::create_converter(
  self : Node,
  backend : String,
  delegate_backend : String?,
) -> &Converter? {
  let dd = self.doc()
  match dd.options.converter {
    Some(c) => Some(c)
    None =>
      match lookup_converter(backend) {
        Some(factory) =>
          Some(factory(backend, self.attributes.str("htmlsyntax"), self))
        None =>
          match delegate_backend {
            Some(db) =>
              match lookup_converter(db) {
                Some(factory) =>
                  Some(factory(db, self.attributes.str("htmlsyntax"), self))
                None => None
              }
            None => None
          }
      }
  }
}

///|
/// Converts the document (Ruby `Document#convert`).
fn Node::convert_document(self : Node) -> String {
  self.convert_with()
}

///|
/// Converts the document. `standalone` overrides the load option;
/// `outfile`/`outdir` set the corresponding attributes.
pub fn Node::convert_with(
  self : Node,
  standalone? : Bool,
  outfile? : String,
  outdir? : String,
) -> String {
  let dd = self.doc()
  let timings = if dd.parent_document is None {
    dd.options.timings
  } else {
    None
  }
  if timings is Some(t) {
    t.start("convert")
  }
  if !dd.parsed {
    self.parse() |> ignore
  }
  if self.processing_error() is Some(_) {
    return ""
  }
  if dd.safe < SAFE_SERVER && (outfile is Some(_) || outdir is Some(_)) {
    match outfile {
      Some(f) => self.attributes.set_str("outfile", f)
      None => self.attributes.remove("outfile") |> ignore
    }
    match outdir {
      Some(d) => self.attributes.set_str("outdir", d)
      None => self.attributes.remove("outdir") |> ignore
    }
  }
  let mut output = ""
  if self.doctype() == "inline" {
    let block = match self.blocks.get(0) {
      Some(b) => Some(b)
      None => dd.header
    }
    match block {
      Some(b) =>
        if b.content_model == Compound || b.content_model == Empty {
          log_warn(
            "no inline candidate; use the inline doctype to convert a single paragragh, verbatim, or raw block",
          )
        } else {
          output = b.content()
        }
      None => ()
    }
  } else {
    let transform = if standalone.unwrap_or(
        dd.options.standalone.unwrap_or(false),
      ) {
      "document"
    } else {
      "embedded"
    }
    output = self.converter().convert(self, transform)
  }
  if dd.parent_document is None {
    match dd.extensions {
      Some(e) =>
        for p in e.postprocessors() {
          output = (p.process)(self, output) catch {
            e => {
              self.abort_processing(e)
              output
            }
          }
        }
      None => ()
    }
  }
  if timings is Some(t) {
    t.record("convert")
  }
  output
}

///|
/// Docinfo content for `location` (`head`, `header`, `footer`).
pub fn Node::docinfo(
  self : Node,
  location? : String = "head",
  suffix? : String,
) -> String {
  let dd = self.doc()
  let content = []
  let mut has_content = false
  if dd.safe < SAFE_SECURE {
    let qualifier = if location == "head" { "" } else { "-\{location}" }
    let suffix = suffix.unwrap_or(dd.outfilesuffix.unwrap_or(""))
    let docinfo = match self.attributes.str("docinfo") {
      Some(v) if v != "" =>
        Some(v.split(",").map(k => @rb.strip(k.to_owned())).collect())
      v =>
        if self.attributes.contains("docinfo2") {
          Some(["private", "shared"])
        } else if self.attributes.contains("docinfo1") {
          Some(["shared"])
        } else if v is Some(_) {
          Some(["private"])
        } else {
          None
        }
    }
    match docinfo {
      Some(docinfo) => {
        has_content = true
        let docinfo_file = "docinfo\{qualifier}\{suffix}"
        let docinfo_dir = self.attributes.str("docinfodir")
        let docinfo_subs = self.resolve_docinfo_subs()
        if docinfo.contains("shared") || docinfo.contains("shared-\{location}") {
          let path = self.normalize_system_path(
            docinfo_file,
            start?=docinfo_dir,
          )
          match self.read_asset(path, normalize=true) {
            Some(s) => content.push(self.apply_subs(s, docinfo_subs))
            None => ()
          }
        }
        match self.attributes.str("docname") {
          Some(docname) if docname != "" &&
            (
              docinfo.contains("private") ||
              docinfo.contains("private-\{location}")
            ) => {
            let path = self.normalize_system_path(
              "\{docname}-\{docinfo_file}",
              start?=docinfo_dir,
            )
            match self.read_asset(path, normalize=true) {
              Some(s) => content.push(self.apply_subs(s, docinfo_subs))
              None => ()
            }
          }
          _ => ()
        }
      }
      None => ()
    }
  }
  match dd.extensions {
    Some(e) => {
      let procs = e.docinfo_processors_for(location)
      if !procs.is_empty() {
        for p in procs {
          match
            ((p.process)(self) catch {
              e => {
                self.abort_processing(e)
                None
              }
            }) {
            Some(s) => content.push(s)
            None => ()
          }
        }
        return content.join("\n")
      }
    }
    None => ()
  }
  if has_content {
    content.join("\n")
  } else {
    ""
  }
}

///|
pub fn Node::has_docinfo_processors(
  self : Node,
  location? : String = "head",
) -> Bool {
  match self.doc().extensions {
    Some(e) => !e.docinfo_processors_for(location).is_empty()
    None => false
  }
}

///|
fn Node::resolve_docinfo_subs(self : Node) -> Array[Sub] {
  match self.attributes.str("docinfosubs") {
    Some(s) => self.resolve_subs(s, subject="docinfo")
    None =>
      if self.attributes.contains("docinfosubs") {
        []
      } else {
        [Attributes]
      }
  }
}
