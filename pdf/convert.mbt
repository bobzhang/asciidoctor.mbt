///|
// The block-level converter: a walk over the document tree that inks each
// block into the page flow, following asciidoctor-pdf's `convert_*`
// methods and its default theme.

///|
priv struct Converter {
  doc : @core.Node
  flow : Flow
  outline : Array[@pdf.OutlineEntry]
  /// asciidoctor-pdf's `@bottom_gutters`: the block whose last line must
  /// keep clear of an enclosing padding, and by how much
  gutters : Array[(@core.Node, Double)?]
  /// asciidoctor-pdf's `@base_text_align`: how prose aligns by default
  mut text_align : Alignment
  /// the pages reserved for the TOC (`@toc_extent`), once allocated
  mut toc_extent : TocExtent?
  /// the `toc::[]` block the TOC was placed at, and its destination
  mut toc_node : (@core.Node, String)?
  /// `toclevels` as the conversion starts (`toc_num_levels`), before the
  /// body's attribute entries: the TOC's depth and the outline's default
  mut toc_levels : Int
  /// asciidoctor-pdf's `@disable_running_content`: the (1-based) pages
  /// whose header or footer is left out (the TOC's, when the `toc::[]`
  /// macro has the `noheader` or `nofooter` option)
  disable_running_content : Map[String, Array[Int]]
  /// asciidoctor-pdf's `@float_box`: the space beside a floated image
  /// that the next paragraphs wrap into (see `init_float_box`)
  mut float_box : FloatBox?
  /// the first page is a front cover (see `ink_cover_page`)
  mut has_front_cover : Bool
  /// asciidoctor-pdf's `pinned` option of `convert_image` (the title page
  /// logo): the image stays on the page, with no margin or float after it
  mut pinned : Bool
}

///|
fn Converter::new(doc : @core.Node, flow : Flow) -> Converter {
  {
    doc,
    flow,
    outline: [],
    gutters: [],
    text_align: Justify,
    toc_extent: None,
    toc_node: None,
    toc_levels: resolve_toclevels(doc),
    disable_running_content: Map([("header", []), ("footer", [])]),
    float_box: None,
    has_front_cover: false,
    pinned: false,
  }
}

///|
/// Lay out `body` in a scratch document (asciidoctor-pdf's `dry_run`) on a
/// new page, with bounds `left`..`right` and the cursor at `start_y` (by
/// default the page's top); returns the scratch flow, whose pages and
/// cursor tell how far the content went. The run stores no index terms
/// and leaves no footnotes registered (`push_scratch`/`pop_scratch`).
fn Converter::dry_run(
  self : Converter,
  left : Double,
  right : Double,
  start_y? : Double,
  bottom? : Double,
  body : (Converter) -> Unit,
) -> Flow {
  let flow = Flow::new(self.flow.catalog, scratch=true)
  flow.start_new_page()
  flow.left = left
  flow.right = right
  match bottom {
    Some(b) => flow.bottom = b
    None => ()
  }
  match start_y {
    Some(y) => flow.y = y
    None => ()
  }
  let scratch = Converter::new(self.doc, flow)
  scratch.gutters.append(self.gutters)
  scratch.text_align = self.text_align
  // the outermost dry run restores the document's attributes, and so its
  // counters (a footnote's number), when it ends (`push_scratch`)
  let saved_attributes = if session.scratch == 0 {
    Some(self.doc.attributes.copy())
  } else {
    None
  }
  session.scratch += 1
  let footnotes = self.doc.catalog().footnotes
  let registered = footnotes.length()
  body(scratch)
  while footnotes.length() > registered {
    ignore(footnotes.pop())
  }
  session.scratch -= 1
  match saved_attributes {
    Some(saved) => self.doc.attributes.replace(saved)
    None => ()
  }
  flow
}

///|
/// asciidoctor-pdf's `arrange_block` for a block that may break across
/// pages: `body` inks the block; a dry run of it from the cursor tells
/// whether it would ink nothing on this page but tared content (its
/// caption, its background: `Flow::tared`) before moving to the next page
/// (`dry_run` with `stop_if_first_page_empty`), in which case the block
/// starts on the next page.
///
/// With `keep_together` (the `unbreakable` option), a first dry run from
/// the top of a page tells whether the block fits on one page; when it
/// does but not in the room left here, it starts on the next page
/// (`ScratchExtent#position_onto`); when it does not, it is arranged as
/// above.
fn Converter::arrange_block(
  self : Converter,
  keep_together? : Bool = false,
  node? : @core.Node,
  body : (Converter) -> Unit,
) -> Unit {
  // `pdf-at-top`: the block starts at the top of a page, or is the first
  // child of one that does (read by block images)
  match node {
    Some(n) => {
      if self.flow.at_page_top() || first_child_at_top(n) {
        ignore(n.set_attr("pdf-at-top", value=Str("")))
      }
      // a dry run from the top of a page sets it too, for good
      let body_for_scratch = fn(c : Converter) {
        if c.flow.scratch && c.flow.at_page_top() {
          ignore(n.set_attr("pdf-at-top", value=Str("")))
        }
        body(c)
      }
      self.arrange_block_at(
        keep_together~,
        moved=() => ignore(n.set_attr("pdf-at-top", value=Str(""))),
        body_for_scratch,
      )
      ignore(n.remove_attr("pdf-at-top"))
    }
    None => self.arrange_block_at(keep_together~, body)
  }
}

///|
/// Whether `node` is its parent's first block and the parent is arranged
/// at the top of a page (asciidoctor-pdf's `node.first_child? &&
/// node.parent.attr?('pdf-at-top')`).
fn first_child_at_top(node : @core.Node) -> Bool {
  match node.parent() {
    Some(parent) =>
      parent.blocks.get(0) is Some(first) &&
      physical_equal(first, node) &&
      parent.has_attr("pdf-at-top")
    None => false
  }
}

///|
fn Converter::arrange_block_at(
  self : Converter,
  keep_together? : Bool = false,
  moved? : () -> Unit = () => (),
  body : (Converter) -> Unit,
) -> Unit {
  let flow = self.flow
  if !flow.at_page_top() && keep_together {
    let scratch = self.dry_run(flow.left, flow.right, bottom=flow.bottom, body)
    if scratch.model.pages.length() == 1 {
      if scratch.y - scratch.page_top > flow.cursor() {
        flow.advance_page()
      }
      body(self)
      return
    }
  }
  if !flow.at_page_top() {
    let scratch = self.dry_run(
      flow.left,
      flow.right,
      start_y=flow.y,
      bottom=flow.bottom,
      body,
    )
    if scratch.first_break_empty == Some(true) {
      flow.advance_page()
      // asciidoctor-pdf's dry run goes on from the top of the next page,
      // where the block is at the top (see `arrange_block`)
      moved()
    }
  }
  body(self)
}

///|
/// Run `body` with prose aligned to `align` by default, when given
/// (asciidoctor-pdf swaps `@base_text_align`).
fn Converter::with_text_align(
  self : Converter,
  align : Alignment?,
  body : () -> Unit,
) -> Unit {
  match align {
    Some(a) => {
      let saved = self.text_align
      self.text_align = a
      body()
      self.text_align = saved
    }
    None => body()
  }
}

///|
/// What the last `convert_document` could not render, one line each:
/// `UNSUPPORTED <kind> <what> at <file>:<line>`. Content the spike does not
/// implement is left out of the PDF (or approximated), and this is where it
/// says so; the CLI prints these lines on stderr. Problems Ruby
/// asciidoctor-pdf reports too (content it cuts off, such as a table cell
/// taller than a page) are `WARNING <message> at <file>:<line>`.
let diagnostics : Array[String] = []

///|
/// The unsupported content and the warnings the last `convert_document`
/// met (see `diagnostics`), in document order.
pub fn conversion_warnings() -> Array[String] {
  diagnostics.copy()
}

///|
/// Where one block of the last `convert_document` went: its nesting depth,
/// what it is, its source line, and the flow position (page from 1, cursor
/// in points from the page top) where its conversion started and ended.
priv struct TraceEntry {
  depth : Int
  what : String
  line : Int
  start_page : Int
  start_y : Double
  mut end_page : Int
  mut end_y : Double
}

///|
let trace : Array[TraceEntry] = []

///|
let trace_depth : Ref[Int] = { val: 0, }

///|
/// Where the blocks of the last `convert_document` went, one line each in
/// the order they started: `depth what line start_page start_y end_page
/// end_y`, tab-separated (pages from 1, y in points from the page top).
/// Comparison tools map a position in the PDF to the innermost block
/// containing it.
pub fn conversion_trace() -> Array[String] {
  trace.map(e => {
    "\{e.depth}\t\{e.what}\t\{e.line}\t\{e.start_page}\t\{e.start_y}\t\{e.end_page}\t\{e.end_y}"
  })
}

///|
/// Run `body`, the conversion of `node`, recording where it went (see
/// `conversion_trace`); dry runs leave no trace.
fn Converter::traced(
  self : Converter,
  node : @core.Node,
  what : String,
  body : () -> Unit,
) -> Unit {
  if self.flow.scratch {
    body()
    return
  }
  let entry : TraceEntry = {
    depth: trace_depth.val,
    what,
    line: node.lineno().unwrap_or(0),
    start_page: self.flow.page + 1,
    start_y: self.flow.y,
    end_page: 0,
    end_y: 0.0,
  }
  trace.push(entry)
  trace_depth.val += 1
  body()
  trace_depth.val -= 1
  entry.end_page = self.flow.page + 1
  entry.end_y = self.flow.y
}

///|
/// `file:line` of a node, or of its nearest ancestor that has one (inline
/// nodes carry no location of their own). Locations exist only when the
/// document was loaded with `sourcemap`.
fn source_location(node : @core.Node) -> String {
  let mut current : @core.Node? = Some(node)
  while current is Some(n) {
    match n.lineno() {
      Some(line) => return "\{n.file().unwrap_or("<stdin>")}:\{line}"
      None => current = n.parent()
    }
  }
  "<unknown>"
}

///|
/// Record content the spike leaves out or approximates.
fn unsupported(kind : String, what : String, node : @core.Node) -> Unit {
  diagnostics.push("UNSUPPORTED \{kind} \{what} at \{source_location(node)}")
}

///|
/// Record a problem Ruby asciidoctor-pdf also reports (as a warning or
/// error on its log), e.g. content cut off: `WARNING <message> at
/// <file>:<line>`.
fn warning(message : String, node : @core.Node) -> Unit {
  diagnostics.push("WARNING \{message} at \{source_location(node)}")
}

///|
/// The name of the destination at the top of the document
/// (asciidoctor-pdf's `pdf-anchor` of the document): its id, else
/// `__anchor-top`.
fn top_anchor(doc : @core.Node) -> String {
  match doc.id {
    Some(id) => pdf_anchor_name(id)
    None => "__anchor-top"
  }
}

///|
/// The PDF destination name for an id (asciidoctor-pdf's
/// `derive_anchor_from_id`): the id itself when it is ASCII, else `0x` and
/// the hex of its UTF-8 bytes.
fn pdf_anchor_name(id : String) -> String {
  if id.iter().all(c => c.to_int() < 0x80) {
    return id
  }
  let sb = StringBuilder()
  sb.write_string("0x")
  for byte in @utf8.encode(id) {
    let v = byte.to_int()
    sb.write_char("0123456789abcdef"[v >> 4].unsafe_to_char())
    sb.write_char("0123456789abcdef"[v & 15].unsafe_to_char())
  }
  sb.to_string()
}

///|
/// The document title as asciidoctor-pdf resolves it for the outline and
/// the information dictionary (`resolve_doctitle`): the header's title, or
/// `untitled-label` for a document without a header.
fn resolve_doctitle(doc : @core.Node) -> String? {
  if doc.has_header() {
    doc.doctitle()
  } else {
    doc.attr("untitled-label")
  }
}

///|
/// A date attribute as Asciidoctor writes it (`2026-09-29 15:12:28 +0800`,
/// or `... UTC`) in PDF date form, `D:20260929151228+08'00'`, as Prawn
/// writes the Ruby `Time` it parses to. None when it does not parse, or
/// when the result is not a valid PDF date (month 13, 30 February, hour
/// 24): the date is then left out, where `render_pdf` would refuse the
/// whole document.
fn pdf_date_of_attribute(value : String) -> String? {
  let digits = StringBuilder()
  let mut count = 0
  let mut i = 0
  // the fourteen digits of the date and time, skipping their separators
  while i < value.length() && count < 14 {
    let c = value[i]
    if c >= '0' && c <= '9' {
      digits.write_char(c.to_int().unsafe_to_char())
      count += 1
    } else if c != '-' && c != ':' && c != ' ' {
      return None
    }
    i += 1
  }
  if count != 14 {
    return None
  }
  let zone = value[i:].trim().to_owned()
  let offset = if zone == "" || zone == "UTC" || zone == "Z" {
    "+00'00'"
  } else if zone.length() == 5 &&
    (zone[0] == '+' || zone[0] == '-') &&
    zone[1:].iter().all(c => c >= '0' && c <= '9') {
    "\{zone[0:3]}'\{zone[3:5]}'"
  } else {
    return None
  }
  let date = "D:\{digits.to_string()}\{offset}"
  if @pdf.is_pdf_date(date) {
    Some(date)
  } else {
    None
  }
}

///|
/// The document information entries asciidoctor-pdf writes
/// (`build_pdf_info`).
fn pdf_info(doc : @core.Node) -> @pdf.DocumentInfo {
  let author = if doc.attribute_locked("author") &&
    !doc.attribute_locked("authors") {
    doc.attr("author")
  } else {
    match doc.attr("authors") {
      Some(authors) => Some(authors)
      None => doc.attr("author")
    }
  }
  let creator = match doc.attr("publisher") {
    Some(publisher) => sanitize(publisher)
    None => author.map(sanitize).unwrap_or("")
  }
  // the modification date is the input's, the creation date the
  // conversion's
  let (mod_date, creation_date) = if doc.has_attr("reproducible") {
    (None, None)
  } else {
    (
      doc.attr("docdatetime").bind(pdf_date_of_attribute),
      doc.attr("localdatetime").bind(pdf_date_of_attribute),
    )
  }
  @pdf.DocumentInfo::new(
    title?=resolve_doctitle(doc).map(sanitize),
    author?=author.map(sanitize),
    subject?=doc.attr("subject").map(sanitize),
    keywords?=doc.attr("keywords").map(sanitize),
    creator~,
    producer=doc
      .attr("producer")
      .map(sanitize)
      .unwrap_or("asciidoctor.mbt (spike)"),
    creation_date?,
    mod_date?,
  )
}

///|
/// asciidoctor-pdf's outline depth and how many levels start expanded:
/// `outlinelevels` (default `toclevels` as the conversion starts, see
/// `Converter::toc_levels`), where `N:M` expands only the first M levels.
fn outline_levels(doc : @core.Node, toclevels : Int) -> (Int, Int) {
  match doc.attr("outlinelevels") {
    Some(spec) =>
      match spec.find(":") {
        Some(i) => {
          let levels = spec[:i].to_owned()
          let num = if levels == "" {
            toclevels
          } else {
            @string.parse_int(levels) catch {
              _ => toclevels
            }
          }
          let expand = @string.parse_int(spec[i + 1:].to_owned()) catch {
            _ => 0
          }
          (num, expand)
        }
        None => {
          let num = @string.parse_int(spec) catch { _ => toclevels }
          (num, num)
        }
      }
    None => (toclevels, toclevels)
  }
}

///|
/// Report document-level features the spike does not implement.
fn report_document_features(doc : @core.Node, catalog : FontCatalog) -> Unit {
  if doc.attr("icons") == Some("font") && !catalog.has_icons() {
    unsupported("attribute", "icons=font (no icon fonts)", doc)
  }
  if doc.has_attr("source-highlighter") {
    unsupported("attribute", "source-highlighter", doc)
  }
}

///|
/// A name given to several destinations (an index term and a subterm of
/// the same name, a repeated id) goes to the last one: Prawn's name tree
/// inserts a new entry before an equal one, so a reader finds the latest
/// (pdf-core's `NameTree::Node#insertion_point`). Pagelayout keeps the
/// first, so the earlier ones are dropped.
fn keep_last_anchors(model : @pagelayout.PageModel) -> Unit {
  let seen : Map[String, Bool] = Map([])
  for p = model.pages.length() - 1; p >= 0; p = p - 1 {
    let items = model.pages[p].items
    let kept : Array[@pagelayout.PageItem] = []
    for i = items.length() - 1; i >= 0; i = i - 1 {
      match items[i] {
        Anchor(anchor) if seen.contains(anchor.name) => ()
        Anchor(anchor) => {
          seen[anchor.name] = true
          kept.push(items[i])
        }
        item => kept.push(item)
      }
    }
    if kept.length() != items.length() {
      kept.rev_in_place()
      items.clear()
      items.append(kept)
    }
  }
}

///|
/// The document outline (asciidoctor-pdf's `add_outline`): the document
/// title (`outline-title`, which defaults to the resolved title), going to
/// the top of the first page, then the sections, with the TOC among them
/// when there is one (`insert_toc_section`).
fn Converter::document_outline(self : Converter) -> Array[@pdf.OutlineEntry] {
  let doc = self.doc
  let outline : Array[@pdf.OutlineEntry] = []
  // `add_outline`: only when the `outline` attribute is set; the title
  // entry is `outline-title`'s (the document title when empty)
  if !doc.has_attr("outline") {
    return outline
  }
  let outline_title = match doc.attr("outline-title") {
    Some("") => resolve_doctitle(doc)
    title => title
  }
  // the title goes to the first page after the front cover, if any
  let initial_page = if self.has_front_cover { 1 } else { 0 }
  match outline_title {
    Some(title) if self.flow.model.pages.length() > initial_page =>
      outline.push({
        title: sanitize(title),
        level: 0,
        dest: Position(page=initial_page, x=0.0, y=0.0),
        open: false,
      })
    _ => ()
  }
  let sections = self.outline
  let toc_title = doc.attr("toc-title").unwrap_or("")
  let toc_entry = match self.toc_extent {
    Some(extent) if toc_title != "" && !doc.sections().is_empty() =>
      match self.toc_node {
        // the macro: after the section it is in (at that section's level),
        // going to its destination
        Some((node, anchor)) => {
          let entry : @pdf.OutlineEntry = {
            title: sanitize(toc_title),
            level: 0,
            dest: Named(anchor),
            open: false,
          }
          match node.parent() {
            Some(parent) if parent.context == Section => {
              let parent_anchor = pdf_anchor_name(
                parent.attr("pdf-anchor").unwrap_or(""),
              )
              let mut at = -1
              let mut level = 0
              for i, e in sections {
                if at < 0 && e.dest == Named(parent_anchor) {
                  at = i + 1
                  level = e.level
                } else if at == i && e.level > level {
                  at = i + 1
                }
              }
              if at < 0 {
                None
              } else {
                Some((at, { ..entry, level, }))
              }
            }
            _ => Some((0, entry))
          }
        }
        // at the top: first, going to the top of the TOC's first page
        None =>
          Some(
            (
              0,
              {
                title: sanitize(toc_title),
                level: 0,
                dest: Position(page=extent.from_page, x=0.0, y=0.0),
                open: false,
              },
            ),
          )
      }
    _ => None
  }
  for i, entry in sections {
    match toc_entry {
      Some((at, toc)) if at == i => outline.push(toc)
      _ => ()
    }
    outline.push(entry)
  }
  match toc_entry {
    Some((at, toc)) if at == sections.length() => outline.push(toc)
    _ => ()
  }
  outline
}

///|
/// Strip markup and decode references: the plain text of formatted text.
fn sanitize(text : String) -> String {
  let sb = StringBuilder()
  let mut in_tag = false
  let mut after_tag = false
  for c in text {
    if c == '<' {
      in_tag = true
    } else if c == '>' && in_tag {
      in_tag = false
      after_tag = true
      continue
    } else if !in_tag && !(after_tag && c == '\u{0}') {
      sb.write_char(c)
    }
    after_tag = false
  }
  // `compact`: stripped, runs of spaces squeezed
  let decoded = decode_entities(sb.to_string())
  let out = StringBuilder()
  let mut space = false
  for c in decoded.trim(chars=" \t\n") {
    if c == ' ' {
      if !space {
        out.write_char(c)
      }
      space = true
    } else {
      out.write_char(c)
      space = false
    }
  }
  out.to_string()
}

///|
fn Converter::traverse(self : Converter, node : @core.Node) -> Unit {
  if node.has_blocks() {
    for block in node.blocks {
      self.convert_block(block)
    }
  } else if node.content_model != Compound {
    // a simple block (e.g. `NOTE: text`) carries its text itself
    let text = node.content()
    if !text.is_empty() {
      self.ink_prose(
        text,
        align=role_align(node.roles(), self.text_align),
        margin_bottom=0.0,
        bottom_gutter=self.gutter(node),
      )
    }
  }
}

///|
fn Converter::convert_block(self : Converter, node : @core.Node) -> Unit {
  // the attribute entries in the body take effect as the block before
  // which they stand is converted (AbstractBlock#convert); after parsing,
  // the document's attributes are those of its header
  node.document().playback_attributes(node.attributes)
  let what = match node.style {
    Some(style) => "\{node.context.name()}/\{style}"
    None => node.context.name()
  }
  self.traced(node, what, () => self.convert_block_body(node))
}

///|
fn Converter::convert_block_body(self : Converter, node : @core.Node) -> Unit {
  match node.context {
    Section => self.convert_section(node)
    Preamble => self.convert_preamble(node)
    Paragraph => self.convert_paragraph(node)
    Listing | Literal => self.convert_code(node)
    Stem => self.convert_code(node, plain=true)
    Pass => self.convert_pass(node)
    Video => self.convert_media(node, "video")
    Audio => self.convert_media(node, "audio")
    Ulist => self.convert_ulist(node)
    Olist => self.convert_olist(node)
    Colist => self.convert_colist(node)
    Dlist => self.convert_dlist(node)
    Table => self.convert_table(node)
    Admonition => self.convert_admonition(node)
    Image => self.convert_image(node)
    Example => self.convert_example(node)
    Sidebar => self.convert_sidebar(node)
    Quote | Verse => self.convert_quote(node)
    Open => self.convert_open(node)
    ThematicBreak => self.convert_thematic_break(node)
    PageBreak => if !self.flow.at_page_top() { self.flow.advance_page() }
    Toc => self.convert_toc(node, "macro")
    FloatingTitle => self.convert_floating_title(node)
    other => unsupported("block", other.name(), node)
  }
}

///|
/// A named destination for the block at the cursor (asciidoctor-pdf's
/// `add_dest_for_block`).
fn Flow::dest_x(self : Flow) -> Double {
  // `add_dest_for_block`: `bounds.absolute_left.truncate 4`, 0 when at the
  // margin
  let left = (self.left * 10000.0).floor() / 10000.0
  if left <= page_setup.val.margin_left {
    0.0
  } else {
    left
  }
}

///|
fn Converter::add_dest(self : Converter, node : @core.Node) -> Unit {
  match node.id {
    Some(id) =>
      // `bounds.absolute_left.truncate 4`, 0 when at the margin; the y is
      // the cursor even at the top of a page (only sections jump to the
      // page's top edge)
      self.flow.add_anchor(id, self.flow.dest_x(), self.flow.y)
    None => ()
  }
}

///|
/// The next block after `block` in reading order, crossing out of the
/// containers that do not end a vertical rhythm unit
/// (asciidoctor-pdf's `next_enclosed_block`). Decides whether a block gets
/// its bottom margin.
fn next_enclosed_block(
  block : @core.Node,
  descend? : Bool = false,
) -> @core.Node? {
  if block.context == Document {
    return None
  }
  guard block.parent() is Some(parent) else { return None }
  let is_list_item = block.context == ListItem
  if is_list_item && descend && block.has_blocks() {
    return Some(block.blocks[0])
  }
  let siblings : Array[@core.Node] = if parent.context == Dlist {
    let flat = []
    for item in parent.dlist_items {
      flat.append(item.terms)
      match item.desc {
        Some(desc) => flat.push(desc)
        None => ()
      }
    }
    flat
  } else if is_list_item {
    parent.items()
  } else {
    parent.blocks
  }
  let mut index = -1
  for i, sibling in siblings {
    if physical_equal(sibling, block) {
      index = i
      break
    }
  }
  if index >= 0 && index < siblings.length() - 1 {
    return Some(siblings[index + 1])
  }
  match parent.context {
    ListItem | Section => next_enclosed_block(parent)
    Open if parent.style != Some("abstract") => next_enclosed_block(parent)
    _ =>
      if is_list_item {
        match parent.parent() {
          Some(grandparent) if grandparent.context == ListItem =>
            next_enclosed_block(grandparent)
          _ => None
        }
      } else {
        None
      }
  }
}

///|
/// `theme_margin :block, :bottom, next_enclosed_block(node)`.
fn Converter::block_margin_bottom(self : Converter, node : @core.Node) -> Unit {
  if next_enclosed_block(node) is Some(_) {
    self.flow.margin(block_margin_bottom())
  }
}

///|
/// Ink formatted text as prose (asciidoctor-pdf's `ink_prose`).
fn Converter::ink_prose(
  self : Converter,
  text : String,
  style? : Style = base_style(),
  align? : Alignment,
  margin_bottom? : Double = prose_margin_bottom(),
  line_height? : Double = base_line_height(),
  normalize? : Bool = true,
  bottom_gutter? : Double = 0.0,
  normalize_line_height? : Bool = false,
  first_line_style? : Style,
  text_indent? : Double = 0.0,
) -> Unit {
  let face = self.flow.font(style)
  let metrics = line_metrics(line_height, face, style.size)
  self.flow.typeset(
    parse_formatted(text, style, normalize~),
    metrics,
    style,
    align=align.unwrap_or(self.text_align),
    bottom_gutter~,
    normalize_line_height~,
    first_line_style?,
    text_indent~,
  )
  self.flow.margin(margin_bottom)
}

///|
/// Enter a padded box whose bottom padding is `bottom` (asciidoctor-pdf's
/// `pad_box`): the block that will ink its last line gets a gutter.
fn Converter::push_gutter(
  self : Converter,
  node : @core.Node,
  bottom : Double,
) -> Unit {
  if node.content_model != Compound {
    self.gutters.push(Some((node, bottom)))
  } else if node.blocks.last() is Some(last) && last.context == Paragraph {
    self.gutters.push(Some((last, bottom)))
  } else {
    self.gutters.push(None)
  }
}

///|
fn Converter::pop_gutter(self : Converter) -> Unit {
  ignore(self.gutters.pop())
}

///|
/// The bottom gutter of `node`, when it is the last block of the
/// innermost padded box.
fn Converter::gutter(self : Converter, node : @core.Node) -> Double {
  match self.gutters.last() {
    Some(Some((last, bottom))) if physical_equal(last, node) => bottom
    _ => 0.0
  }
}

///|
/// A discrete heading (asciidoctor-pdf's `convert_floating_title`): kept
/// with the next block unless it is the last of its parent.
fn Converter::convert_floating_title(
  self : Converter,
  node : @core.Node,
) -> Unit {
  let title = node.title().unwrap_or("")
  let hlevel = node.level + 1
  let last_child = match node.parent() {
    Some(parent) =>
      parent.blocks.last().map(b => physical_equal(b, node)).unwrap_or(false)
    None => true
  }
  if !self.flow.at_page_top() && !last_child {
    self.arrange_heading(title, hlevel, true)
  }
  self.add_dest(node)
  self.ink_heading(
    title,
    hlevel,
    align?=text_align_from_roles(node.roles()),
    outdent=node.parent() is Some(p) && p.context == Section,
  )
}

///|
/// asciidoctor-pdf's `convert_section`: parts and chapters (a book's
/// level-1 sections) start a new page; other headings keep with the
/// content after them (`arrange_heading`). The section records the page it
/// starts on and its destination (`pdf-page-start`, `pdf-anchor`), which
/// the TOC reads; chapters end with their footnotes. The index section
/// lists the index, and is left out while there are no index terms.
fn Converter::convert_section(self : Converter, section : @core.Node) -> Unit {
  let flow = self.flow
  let is_index = section.sectname == Some("index")
  if is_index && session.index.is_empty() {
    return
  }
  let title = numbered_title(section, formal=true)
  // a title separator (`separator`, `title-separator`) splits off a subtitle,
  // set on its own line
  let separator = match section.attr("separator") {
    Some(s) => s
    None => section.document().attr("title-separator").unwrap_or("")
  }
  let heading = match title.rev_find(separator + " ") {
    Some(i) if separator != "" => {
      let main = title[:i].to_owned()
      let subtitle = title[i + separator.length() + 1:].to_owned()
      "\{main}\n<em class=\"subtitle\">\{subtitle}</em>"
    }
    _ => title
  }
  let hlevel = section.level + 1
  let is_book = self.doc.doctype() == "book"
  let part = section.sectname == Some("part")
  let chapterlike = !part &&
    (section.sectname == Some("chapter") || (is_book && section.level == 1))
  let hidden = section.has_option("notitle")
  // parts and chapters start a new page (`heading_part_break_before`,
  // `heading_chapter_break_before`, `heading_part_break_after`)
  let first_of_part = match section.parent() {
    Some(parent) if parent.sectname == Some("part") =>
      parent
      .sections()
      .get(0)
      .map(s => physical_equal(s, section))
      .unwrap_or(false)
    _ => false
  }
  let started_new = if part {
    t_str("heading_part_break_before") == Some("always")
  } else if chapterlike {
    let part_break_after = t_str("heading_part_break_after")
    (
      t_str("heading_chapter_break_before") == Some("always") &&
      !(part_break_after == Some("avoid") && first_of_part)
    ) ||
    (part_break_after == Some("always") && first_of_part)
  } else {
    false
  }
  if started_new && !flow.at_page_top() {
    flow.advance_page()
  }
  if !hidden && !started_new && !flow.at_page_top() {
    self.arrange_heading(heading, hlevel, section.has_blocks())
  }
  let start_page = flow.page + 1
  section.set_attr("pdf-page-start", value=Int(start_page)) |> ignore
  // a section without an id is named after where it starts
  let anchor = match section.id {
    Some(id) => pdf_anchor_name(id)
    None => "__anchor-\{start_page}-\{(page_height() - flow.y).ceil().to_int()}"
  }
  section.set_attr("pdf-anchor", value=Str(anchor)) |> ignore
  flow.add_anchor(
    anchor,
    flow.dest_x(),
    if flow.at_page_top() {
      0.0
    } else {
      flow.y
    },
  )
  let (num_levels, expand_levels) = outline_levels(self.doc, self.toc_levels)
  // `add_outline_level` leaves out an empty, untitled last section
  let untitled_last = hidden &&
    !section.has_blocks() &&
    self.doc.blocks.last() is Some(last) &&
    physical_equal(last, section)
  if section.level <= num_levels && sanitize(title) != "" && !untitled_last {
    // the depth in the section tree, not the section level: a document
    // without a header may start at `===`, and its first sections are
    // still top-level entries
    let mut depth = 0
    let mut parent = section.parent()
    while parent is Some(p) && p.context == Section {
      depth += 1
      parent = p.parent()
    }
    self.outline.push({
      title: sanitize(title),
      level: depth,
      dest: Named(anchor),
      // `closed: expand_levels < 1`, counted down one per level
      open: depth < expand_levels,
    })
  }
  if !hidden {
    self.ink_heading(heading, hlevel, outdent=true)
  }
  if is_index {
    self.outdent_section(() => self.convert_index_section())
  } else {
    self.traverse(section)
  }
  if chapterlike {
    self.outdent_section(() => self.ink_footnotes(section))
  }
}

///|
fn Converter::convert_preamble(self : Converter, node : @core.Node) -> Unit {
  // the first paragraph of a preamble leads when the document has sections
  if node.blocks.length() > 0 &&
    node.blocks[0].context == Paragraph &&
    self.doc.has_sections() &&
    node.blocks[0].role() is None {
    node.blocks[0].set_role("lead")
  }
  self.traverse(node)
  self.block_margin_bottom(node)
  self.convert_toc(node, "preamble")
}

///|
/// The prose style of a block's roles (`theme_font_cascade` of their
/// `role_<name>` categories), with their text decoration.
fn role_style(roles : Array[String], base : Style) -> Style {
  let mut style = base
  for role in roles {
    let (s, _) = theme_font(style, base_line_height(), "role_" + role)
    style = s
    match t_str("role_\{role}_text_decoration") {
      Some("underline") => style = { ..style, underline: true, }
      Some("line-through") => style = { ..style, strike: true, }
      _ => ()
    }
  }
  style
}

///|
/// The line height of a block's roles (`role_<name>_line_height`), else
/// `default`.
fn role_line_height(roles : Array[String], default : Double) -> Double {
  let mut line_height = default
  for role in roles {
    match t_num("role_\{role}_line_height") {
      Some(lh) => line_height = lh
      None => ()
    }
  }
  line_height
}

///|
/// The alignment of a block from its `text-*` roles, else `default`.
fn role_align(roles : Array[String], default : Alignment) -> Alignment {
  text_align_from_roles(roles).unwrap_or(default)
}

///|
/// asciidoctor-pdf's `convert_paragraph`: aligned by its roles (a
/// `text-*` role, else a role's `role_<name>_text_align`), in its roles'
/// fonts; then the prose margin (`prose_margin_inner` between paragraphs,
/// when the theme sets it).
fn paragraph_text_indent(node : @core.Node, align : Alignment) -> Double {
  // asciidoctor-pdf's `convert_paragraph`: the first line's indent,
  // prose_text_indent, else prose_text_indent_inner after a paragraph
  // (justified and left-aligned text only)
  if align is (Justify | Left) {
    let indent = t_num_or("prose_text_indent", 0.0)
    let inner = t_num_or("prose_text_indent_inner", 0.0)
    if indent > 0.0 {
      indent
    } else if inner > 0.0 &&
      previous_sibling(node) is Some(prev) &&
      prev.context == Paragraph {
      inner
    } else {
      0.0
    }
  } else {
    0.0
  }
}

///|
fn Converter::convert_paragraph(self : Converter, node : @core.Node) -> Unit {
  self.add_dest(node)
  let roles = node.roles()
  let align = text_align_from_roles(roles, query_theme=true).unwrap_or(
    self.text_align,
  )
  let text_indent = paragraph_text_indent(node, align)
  // a float box takes the paragraph, unless a float group ended before it
  match self.float_box {
    Some(float_box) =>
      if previous_sibling(node) is Some(prev) &&
        prev.context == Open &&
        prev.has_role("float-group") {
        self.flow.y = float_box.bottom
        self.float_box = None
      } else {
        self.ink_paragraph_in_float_box(
          node,
          float_box,
          role_style(roles, base_style()),
          align,
          role_line_height(roles, base_line_height()),
          text_indent,
        )
        return
      }
    None => ()
  }
  if node.has_title() {
    self.ink_caption(node.title().unwrap_or(""))
  }
  self.ink_prose(
    node.content(),
    style=role_style(roles, base_style()),
    align~,
    margin_bottom=0.0,
    line_height=role_line_height(roles, base_line_height()),
    bottom_gutter=self.gutter(node),
    text_indent~,
  )
  match next_enclosed_block(node) {
    Some(next) =>
      match t_num("prose_margin_inner") {
        Some(inner) if next.context == Paragraph => self.flow.margin(inner)
        _ => self.flow.margin(prose_margin_bottom())
      }
    None => ()
  }
}

///|

///|
/// A block title (asciidoctor-pdf's `ink_caption`, top end): italic,
/// slightly smaller, with the inside margin below.
fn Converter::ink_caption(
  self : Converter,
  text : String,
  bottom? : Bool = false,
  category? : String,
  block_align? : Alignment,
  block_width? : Double,
  max_width? : String,
) -> Unit {
  // the category's caption keys (`table_caption_*`) before the generic ones
  let key = match category {
    Some(c) => c + "_caption"
    None => "caption"
  }
  let setting = (name : String) => {
    match tv("\{key}_\{name}") {
      Null => tv("caption_\{name}")
      v => v
    }
  }
  let outside = value_num(setting("margin_outside")).unwrap_or(0.0)
  let inside = value_num(setting("margin_inside")).unwrap_or(0.0)
  let align = match value_str(setting("align")) {
    Some("inherit") => block_align.unwrap_or(self.text_align)
    Some(a) => alignment_of(a)
    None => self.text_align
  }
  let text_align = match value_str(setting("text_align")) {
    Some("inherit") => align
    Some(a) => alignment_of(a)
    None => align
  }
  let (style, line_height) = theme_font(
    base_style(),
    base_line_height(),
    "caption",
  )
  let (style, line_height) = if key != "caption" {
    theme_font(style, line_height, key)
  } else {
    (style, line_height)
  }
  if value_color(setting("background_color")) is Some(_) {
    unsupported("theme", "caption background", self.doc)
  }
  let (top_margin, bottom_margin) = if bottom {
    (inside, outside)
  } else {
    (outside, inside)
  }
  let (indent_left, indent_right) = caption_indents(
    self.flow.width(),
    align,
    block_align,
    block_width,
    max_width,
  )
  self.flow.margin(top_margin)
  self.flow.indent(indent_left, indent_right, () => {
    self.ink_prose(
      text,
      style~,
      align=text_align,
      margin_bottom=bottom_margin,
      line_height~,
      normalize=false,
      normalize_line_height=true,
    )
  })
}

///|
/// How far `ink_caption` indents a caption from each side for its
/// `max_width`: `fit-content` (the block's width), `fit-content(N%)` (N% of
/// it, placed by the caption's alignment), `N%` of the container or a
/// length (placed by the caption's alignment); the caption then sits where
/// the block does (`block_align`).
fn caption_indents(
  container_width : Double,
  align : Alignment,
  block_align : Alignment?,
  block_width : Double?,
  max_width : String?,
) -> (Double, Double) {
  guard max_width is Some(max_width) && max_width != "none" else {
    return (0.0, 0.0)
  }
  let mut left = 0.0
  let mut right = 0.0
  let mut block_align = block_align
  let share = (amount : Double, by : Alignment?) => {
    match by {
      Some(Right) => left += amount
      Some(Center) => {
        left += amount * 0.5
        right += amount * 0.5
      }
      _ => right += amount
    }
  }
  let max = if max_width.has_prefix("fit-content") {
    let block_width = block_width.unwrap_or(container_width)
    if !(max_width.has_suffix("t") || max_width.has_suffix("()")) {
      let percent = @theme.ruby_string_to_f(
        max_width[12:max_width.length() - 1].to_owned(),
      )
      let delta = block_width - block_width * percent / 100.0
      if delta > 0.0 {
        share(delta, Some(align))
      }
    }
    block_width
  } else if max_width.has_suffix("%") {
    block_align = Some(align)
    @cmp.minimum(
      @theme.ruby_string_to_f(max_width) / 100.0 * container_width,
      container_width,
    )
  } else {
    block_align = Some(align)
    @cmp.minimum(@theme.ruby_string_to_f(max_width), container_width)
  }
  let remainder = container_width - max
  if remainder > 0.0 {
    share(remainder, block_align)
  }
  (left, right)
}

///|
/// asciidoctor-pdf's `guard_indentation`: tabs expand to 4-column stops,
/// then the first space of each line becomes a no-break space so that the
/// line keeps its leading spaces.
fn guard_indentation(text : String) -> String {
  let sb = StringBuilder()
  let mut column = 0
  let mut at_line_start = true
  for c in text {
    if c == '\t' {
      let spaces = 4 - column % 4
      for k in 0..<spaces {
        sb.write_char(if at_line_start && k == 0 { '\u{a0}' } else { ' ' })
      }
      at_line_start = false
      column += spaces
      continue
    }
    if at_line_start && c == ' ' {
      sb.write_char('\u{a0}')
    } else {
      sb.write_char(c)
    }
    at_line_start = c == '\n'
    column = if c == '\n' { 0 } else { column + 1 }
  }
  sb.to_string()
}

///|
/// asciidoctor-pdf's `generate_manname_section`: the Name section of a man
/// page (`manname-title`, upper case when the first section's title is),
/// holding `manname - manpurpose`.
fn generate_manname_section(doc : @core.Node) -> @core.Node {
  let title = doc.attr("manname-title").unwrap_or("Name")
  let title = match doc.sections().get(0).bind(s => s.title()) {
    Some(first) if first.to_upper() == first => title.to_upper()
    _ => title
  }
  let section = @core.Node::new_section(Some(doc), level=1)
  section.sectname = Some("section")
  section.set_id(doc.attr("manname-id"))
  section.set_title(Some(title))
  let text = "\{doc.attr("manname").unwrap_or("")} - \{doc.attr("manpurpose").unwrap_or("")}"
  section.append(
    @core.Node::new_block(
      section,
      Paragraph,
      subs=SubsSpec("normal"),
      source_text=text,
    ),
  )
  section
}
