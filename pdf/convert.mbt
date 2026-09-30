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
/// Convert a document loaded with `backend=pdf` (see `register`) to PDF.
/// Load it with `sourcemap` for `conversion_warnings` to say where the
/// unsupported content is.
pub fn convert_document(doc : @core.Node, catalog : FontCatalog) -> Bytes raise {
  diagnostics.clear()
  trace.clear()
  trace_depth.val = 0
  report_document_features(doc, catalog)
  let flow = Flow::new(catalog)
  let c = Converter::new(doc, flow)
  flow.start_new_page()
  // an article's abstract section becomes an abstract block, out of the
  // TOC and the outline (the "demote abstract section" hack)
  match doc.sections().get(0) {
    Some(first) if doc.doctype() == "article" &&
      first.sectname == Some("abstract") => {
      first.set_context(Open)
      first.style = Some("abstract")
    }
    _ => ()
  }
  let is_book = doc.doctype() == "book"
  // a book (or `title-page`) has a title page instead of a title heading
  let title_as_page = is_book || doc.has_attr("title-page")
  let has_title_page = title_as_page && doc.has_header() && !doc.notitle()
  if has_title_page {
    c.ink_title_page()
    flow.start_new_page()
  }
  if !title_as_page && doc.has_header() && !doc.notitle() {
    match doc.doctitle() {
      Some(title) => c.ink_heading(title, 1, align=Center)
      None => ()
    }
  }
  let levels = resolve_toclevels(doc)
  c.toc_levels = levels
  // the TOC at the top, unless the macro or the preamble places it
  let placement = doc.attr("toc-placement").unwrap_or("auto")
  if has_toc(doc) && placement != "macro" && placement != "preamble" {
    flow.add_anchor("toc", 0.0, if flow.at_page_top() { 0.0 } else { flow.y })
    c.toc_extent = Some(c.allocate_toc(levels, title_as_page))
  }
  // pages before the body are front matter: numbered in roman, without
  // running content (the default theme starts both at the body)
  let body_start = flow.page
  let front_matter = if title_as_page { body_start } else { 0 }
  session.index.start_page_number = front_matter + 1
  // the top of the document, for `<<_top>>`-style references: the top of
  // the page the body starts on (`add_dest_for_top`)
  let top = top_anchor(doc)
  flow.add_anchor(top, 0.0, 0.0)
  // a man page starts with its name and purpose, as a section the outline
  // (built from the document's sections) does not list
  if doc.doctype() == "manpage" && doc.has_attr("manpurpose") {
    let listed = c.outline.length()
    c.convert_section(generate_manname_section(doc))
    while c.outline.length() > listed {
      ignore(c.outline.pop())
    }
  }
  c.traverse(doc)
  c.ink_footnotes(doc)
  match c.toc_extent {
    Some(extent) => {
      let last = flow.page
      ignore(c.ink_toc(levels, extent.from_page, extent.from_y, front_matter))
      flow.page = last
    }
    None => ()
  }
  // a page started but never written to is dropped
  let pages = flow.model.pages
  if pages.length() > 1 &&
    pages[pages.length() - 1].items.iter().all(fn(i) { i is Anchor(_) }) {
    ignore(pages.pop())
  }
  c.ink_footers(front_matter)
  keep_last_anchors(flow.model)
  for entry in @pdf.unembeddable_images(flow.model) {
    diagnostics.push("UNSUPPORTED image \{entry.0} (\{entry.1}x) at <document>")
  }
  @pdf.render_pdf(
    flow.model,
    options=@pdf.RenderOptions::new(
      // the faces the flow measured with, drawn and embedded as they are
      fonts=catalog.registry,
      outline=c.document_outline(),
      info=pdf_info(doc),
      // the default theme's `page_initial_zoom: FitH` and `page_mode: outline`
      initial_zoom=FitH,
      page_mode=UseOutlines,
      display_doc_title=true,
      page_boxes=true,
      truncate_widths=true,
      // Prawn draws a character the font lacks as its .notdef glyph and
      // keeps it in the text layer
      notdef_text=true,
      // ttfunk reads the descriptor's ascent, descent and cap height from
      // the OS/2 typographic metrics
      typo_metrics=true,
      page_labels=Array::makei(flow.model.pages.length(), i => {
        page_label(i + 1, front_matter)
      }),
    ),
  )
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
  let outline_title = match doc.attr("outline-title") {
    Some(t) if t != "" => Some(t)
    _ => resolve_doctitle(doc)
  }
  match outline_title {
    Some(title) =>
      outline.push({
        title: sanitize(title),
        level: 0,
        dest: Position(page=0, x=0.0, y=0.0),
        open: false,
      })
    None => ()
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
/// The title page of a book (asciidoctor-pdf's `ink_title_page` with the
/// default theme): the title from 55% down the page, in #999999, then the
/// subtitle, authors and revision, all right-aligned.
fn Converter::ink_title_page(self : Converter) -> Unit {
  let doc = self.doc
  let flow = self.flow
  flow.y = flow.page_top + (flow.bottom - flow.page_top) * 0.55
  let (main, subtitle) = match doc.doctitle_partitioned() {
    Some(t) => (t.main, t.subtitle)
    None => (doc.doctitle().unwrap_or(""), None)
  }
  self.ink_prose(
    main,
    style=Style::new(size=heading_font_size(1), color=rgb_hex(0x999999)),
    align=Right,
    margin_bottom=0.0,
    line_height=0.9,
  )
  match subtitle {
    Some(sub) =>
      self.ink_prose(
        sub,
        style=Style::new(
          size=heading_font_size(3),
          doc_bold=true,
          doc_italic=true,
        ),
        align=Right,
        margin_bottom=0.0,
        line_height=1.0,
      )
    None => ()
  }
  let authors = doc.authors()
  if !authors.is_empty() {
    flow.move_down(base_font_size * 1.25)
    self.ink_prose(
      authors.map(a => a.name.unwrap_or("")).join(", "),
      style=Style::new(
        size=(base_font_size * 1.25).round(),
        color=rgb_hex(0x181818),
      ),
      align=Right,
      margin_bottom=0.0,
    )
  }
  let revision = []
  match doc.attr("revnumber") {
    Some(n) =>
      revision.push("\{doc.attr("version-label").unwrap_or("Version")} \{n}")
    None => ()
  }
  match doc.attr("revdate") {
    Some(d) => revision.push(d)
    None => ()
  }
  if !revision.is_empty() {
    flow.move_down(base_font_size * 1.25)
    let text = match doc.attr("revremark") {
      Some(remark) => "\{revision.join(", ")}: \{remark}"
      None => revision.join(", ")
    }
    self.ink_prose(text, align=Right, margin_bottom=0.0, normalize=false)
  }
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
fn Converter::add_dest(self : Converter, node : @core.Node) -> Unit {
  match node.id {
    Some(id) => {
      // `bounds.absolute_left.truncate 4`, 0 when at the margin; the y is
      // the cursor even at the top of a page (only sections jump to the
      // page's top edge)
      let left = (self.flow.left * 10000.0).floor() / 10000.0
      let x = if left <= margin_side { 0.0 } else { left }
      self.flow.add_anchor(id, x, self.flow.y)
    }
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
    self.flow.margin(block_margin_bottom)
  }
}

///|
fn base_style() -> Style {
  Style::new()
}

///|
/// Ink formatted text as prose (asciidoctor-pdf's `ink_prose`).
fn Converter::ink_prose(
  self : Converter,
  text : String,
  style? : Style = base_style(),
  align? : Alignment,
  margin_bottom? : Double = prose_margin_bottom,
  line_height? : Double = base_line_height,
  normalize? : Bool = true,
  bottom_gutter? : Double = 0.0,
  normalize_line_height? : Bool = false,
  first_line_style? : Style,
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
/// A heading at `level` (1 is the document title), asciidoctor-pdf's
/// `ink_heading` with the heading theme font.
fn Converter::ink_heading(
  self : Converter,
  title : String,
  level : Int,
  align? : Alignment = Left,
) -> Unit {
  let style = Style::new(size=heading_font_size(level), bold=true)
  let flow = self.flow
  if !flow.at_page_top() {
    flow.margin(heading_margin_top)
  }
  let face = flow.font(style)
  flow.typeset(
    parse_formatted(title, style, normalize=false),
    line_metrics(1.0, face, style.size),
    style,
    align~,
  )
  flow.margin(heading_margin_bottom)
}

///|
/// asciidoctor-pdf's `arrange_heading` with a numeric
/// `heading_min_height_after`: keep a heading with the content after it,
/// when there is some, by starting a new page unless the heading, its top
/// margin and that much room below it fit here.
fn Converter::arrange_heading(
  self : Converter,
  title : String,
  hlevel : Int,
  content_after : Bool,
) -> Unit {
  let flow = self.flow
  let size = heading_font_size(hlevel)
  if size > flow.cursor() {
    flow.advance_page()
    return
  }
  let style = Style::new(size~, bold=true)
  let face = flow.font(style)
  let space_below = if content_after {
    heading_min_height_after + heading_margin_bottom
  } else {
    0.0
  }
  let height = flow.height_of(
    parse_formatted(title, style, normalize=false),
    line_metrics(1.0, face, size),
    style,
  )
  if flow.cursor() < height + heading_margin_top + space_below {
    flow.advance_page()
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
  self.ink_heading(title, hlevel)
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
  // the default theme breaks before parts and chapters
  // (`start_new_chapter`)
  let started_new = part || chapterlike
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
    None => "__anchor-\{start_page}-\{(page_height - flow.y).ceil().to_int()}"
  }
  section.set_attr("pdf-anchor", value=Str(anchor)) |> ignore
  flow.add_anchor(anchor, 0.0, if flow.at_page_top() { 0.0 } else { flow.y })
  let (num_levels, expand_levels) = outline_levels(self.doc, self.toc_levels)
  if section.level <= num_levels && sanitize(title) != "" {
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
    self.ink_heading(heading, hlevel)
  }
  if is_index {
    self.convert_index_section()
  } else {
    self.traverse(section)
  }
  if chapterlike {
    self.ink_footnotes(section)
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
/// The prose style of a paragraph's roles.
fn role_style(roles : Array[String], base : Style) -> Style {
  let mut style = base
  for role in roles {
    match role {
      "lead" => style = { ..style, size: (base_font_size * 1.25).round(), }
      "big" => style = { ..style, size: style.size * 1.2, }
      "small" => style = { ..style, size: style.size * 0.8, }
      "underline" => style = { ..style, underline: true, }
      "line-through" => style = { ..style, strike: true, }
      // `font_style: normal_italic`: the document font upright italic
      "subtitle" =>
        style = {
          ..style,
          size: style.size * 0.8,
          color: rgb_hex(0x999999),
          doc_bold: false,
          doc_italic: true,
        }
      _ => ()
    }
  }
  style
}

///|
fn role_align(roles : Array[String], default : Alignment) -> Alignment {
  for role in roles {
    match role {
      "text-left" => return Left
      "text-right" => return Right
      "text-center" => return Center
      "text-justify" => return Justify
      _ => ()
    }
  }
  default
}

///|
fn Converter::convert_paragraph(self : Converter, node : @core.Node) -> Unit {
  self.add_dest(node)
  let roles = node.roles()
  if node.has_title() {
    self.ink_caption(node.title().unwrap_or(""))
  }
  self.ink_prose(
    node.content(),
    style=role_style(roles, base_style()),
    align=role_align(roles, self.text_align),
    margin_bottom=0.0,
    bottom_gutter=self.gutter(node),
  )
  if next_enclosed_block(node) is Some(_) {
    self.flow.margin(prose_margin_bottom)
  }
}

///|
/// A block title (asciidoctor-pdf's `ink_caption`, top end): italic,
/// slightly smaller, with the inside margin below.
fn Converter::ink_caption(
  self : Converter,
  text : String,
  bottom? : Bool = false,
) -> Unit {
  let style = Style::new(size=caption_font_size, doc_italic=true)
  if bottom {
    self.flow.margin(caption_margin_inside)
  }
  self.ink_prose(
    text,
    style~,
    align=Left,
    margin_bottom=if bottom { 0.0 } else { caption_margin_inside },
    normalize=false,
    normalize_line_height=true,
  )
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
fn Converter::convert_code(
  self : Converter,
  node : @core.Node,
  plain? : Bool = false,
) -> Unit {
  let flow = self.flow
  let style = Style::new(family=mono_font_family, size=code_font_size)
  let face = flow.font(style)
  let metrics = line_metrics(code_line_height, face, code_font_size)
  // a stem block's text is shown as it is, without inline formatting
  let fragments = if plain {
    [{ text: guard_indentation(node.content()), style, anchor: None, }]
  } else {
    parse_formatted(guard_indentation(node.content()), style, normalize=false)
  }
  // arrange_block: the caption and the background are tared, so the block
  // starts on the next page when not even its first line (with the room
  // its bottom padding needs, when it is the last) fits here
  self.arrange_block(keep_together=node.has_option("unbreakable"), node~, fn(
    c,
  ) {
    let flow = c.flow
    c.add_dest(node)
    if node.has_title() {
      flow.tared(() => c.ink_caption(node.captioned_title()))
    }
    let start = flow.mark()
    let (left, right) = (flow.left, flow.right)
    flow.move_down(code_padding)
    flow.indent(code_padding, code_padding, fn() {
      flow.typeset(fragments, metrics, style, bottom_gutter=code_padding)
    })
    flow.pad_bottom(code_padding)
    flow.underlay(start, fn(top, bottom, first, last) {
      let items = [
        rect_item(
          left,
          top,
          right - left,
          bottom - top,
          fill=code_background_color,
          stroke=code_border_color,
          stroke_width=code_border_width,
        ),
      ]
      // where the block breaks across pages, a dashed line in the
      // background colour cuts into the border
      // (theme_fill_and_stroke_block)
      let inset = 4.0 + code_border_width
      let width = code_border_width * 1.2
      if !first {
        items.append(
          dashed_hrule(
            left + inset,
            right - inset,
            top,
            width,
            code_background_color,
          ),
        )
      }
      if !last {
        items.append(
          dashed_hrule(
            left + inset,
            right - inset,
            bottom,
            width,
            code_background_color,
          ),
        )
      }
      items
    })
  })
  self.block_margin_bottom(node)
}

///|
/// asciidoctor-pdf's bullet for an unordered list (`convert_ulist`): its
/// style's (`bibliography` is a square, an unknown style a disc), else the
/// one for its depth; None for `unstyled` and `no-bullet`, which have no
/// marker and a narrower indent.
fn ulist_marker(node : @core.Node, depth : Int) -> String? {
  match node.style {
    Some("circle") => Some("◦")
    Some("square") | Some("bibliography") => Some("▪")
    Some("none") => Some("")
    Some("unstyled") | Some("no-bullet") => None
    Some(_) => Some("•")
    None =>
      match depth {
        1 => Some("•")
        2 => Some("◦")
        _ => Some("▪")
      }
  }
}

///|
/// Nesting level among unordered and ordered lists (asciidoctor-pdf's
/// `list_level`).
fn list_level(node : @core.Node) -> Int {
  let mut level = 1
  let mut ancestor = node.parent()
  while ancestor is Some(a) {
    if a.context == Ulist || a.context == Olist {
      level += 1
    }
    ancestor = a.parent()
  }
  level
}

///|
fn Converter::convert_ulist(self : Converter, node : @core.Node) -> Unit {
  self.add_dest(node)
  if node.has_option("checklist") {
    // a checkbox for an item that has one, nothing for the others
    self.convert_list(node, fn(_index, item) {
      if !item.has_attr("checkbox") {
        ""
      } else if item.has_attr("checked") {
        "☑"
      } else {
        "☐"
      }
    })
    return
  }
  match ulist_marker(node, list_level(node)) {
    Some(marker) => self.convert_list(node, fn(_index, _item) { marker })
    None => self.convert_list(node, fn(_index, _item) { "" }, unmarked=true)
  }
}

///|
fn roman(n : Int, upper : Bool) -> String {
  let values = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1]
  let symbols = [
    "m", "cm", "d", "cd", "c", "xc", "l", "xl", "x", "ix", "v", "iv", "i",
  ]
  let sb = StringBuilder()
  let mut rest = n
  for i, value in values {
    while rest >= value {
      sb.write_string(symbols[i])
      rest -= value
    }
  }
  if upper {
    sb.to_string().to_upper()
  } else {
    sb.to_string()
  }
}

///|
fn alpha(n : Int, upper : Bool) -> String {
  let base = if upper { 'A'.to_int() } else { 'a'.to_int() }
  let sb = StringBuilder()
  let mut rest = n
  let digits = []
  while rest > 0 {
    rest -= 1
    digits.push(base + rest % 26)
    rest = rest / 26
  }
  for i = digits.length() - 1; i >= 0; i = i - 1 {
    sb.write_char(digits[i].unsafe_to_char())
  }
  sb.to_string()
}

///|
/// The block before `node` among its parent's blocks.
fn previous_sibling(node : @core.Node) -> @core.Node? {
  guard node.parent() is Some(parent) else { return None }
  let mut previous : @core.Node? = None
  for block in parent.blocks {
    if physical_equal(block, node) {
      return previous
    }
    previous = Some(block)
  }
  None
}

///|
/// asciidoctor-pdf's `convert_colist`: after a code block it moves up
/// (`callout_list_margin_top_after_code`); each item's number, in the conum
/// font, is centred in a column as wide as the number and an `x`, and the
/// item's text is indented by that column (`convert_colist_item`).
fn Converter::convert_colist(self : Converter, node : @core.Node) -> Unit {
  let flow = self.flow
  if !flow.at_page_top() &&
    previous_sibling(node) is Some(prev) &&
    (prev.context == Listing || prev.context == Literal) {
    flow.margin(-block_margin_bottom / 2.0)
  }
  self.add_dest(node)
  let conum = conum_style()
  let conum_face = flow.font(conum)
  // allocate_space_for_list_item with the conum font's line metrics (in
  // `theme_font :conum`, the base line height is `conum_line_height`)
  let metrics = line_metrics(conum_line_height, conum_face, conum.size)
  let items = node.items()
  for index, item in items {
    if !flow.at_page_top() &&
      flow.cursor() <
      conum_line_height * conum.size + metrics.leading + metrics.padding_top {
      flow.advance_page()
    }
    self.traced(item, "list_item", () => {
      let marker = conum_glyph((index + 1).to_string())
      let marker_width = typeset_lines(
          [{ text: marker + "x", style: conum, anchor: None, }],
          flow.catalog,
          1.0e6,
          Left,
        )[0].fit_width
      let (page, y) = (flow.page, flow.y)
      flow.indent(0.0, flow.width() - marker_width, () => {
        self.ink_prose(
          marker,
          style=conum,
          align=Center,
          margin_bottom=0.0,
          normalize=false,
          line_height=conum_line_height,
        )
      })
      flow.page = page
      flow.y = y
      let margin_bottom = if index == items.length() - 1 {
        0.0
      } else {
        list_item_spacing
      }
      flow.indent(marker_width, 0.0, () => {
        match item.text() {
          Some(text) if !text.is_empty() =>
            self.ink_prose(text, margin_bottom~, normalize_line_height=true)
          _ =>
            if !item.has_blocks() {
              self.ink_prose("", margin_bottom~, normalize_line_height=true)
            }
        }
        self.traverse(item)
      })
    })
  }
  self.block_margin_bottom(node)
}

///|
/// The conum font (`conum_font_*`): the codespan font and colour at the
/// base size.
fn conum_style() -> Style {
  {
    ..Style::new(
      family=mono_font_family,
      size=base_font_size,
      color=codespan_font_color,
    ),
    font_set: true,
  }
}

///|
fn Converter::convert_olist(self : Converter, node : @core.Node) -> Unit {
  self.add_dest(node)
  let start = match node.attr("start") {
    Some(s) => @string.parse_int(s) catch { _ => 1 }
    None => 1
  }
  // a style the marker implies (`a.`) is a Symbol in Asciidoctor, which
  // asciidoctor-pdf's `case node.style when 'loweralpha'` never matches:
  // (the core marks such a style: it has no list marker keyword)
  let style = match node.style {
    Some("loweralpha" | "upperalpha" | "lowerroman" | "upperroman") if node.list_marker_keyword()
      is None => "arabic"
    Some(style) => style
    None => "arabic"
  }
  // `unstyled`, `unnumbered` and `no-bullet` have no numbers and a narrower
  // indent; `none` has empty ones
  let unmarked = style == "unstyled" ||
    style == "unnumbered" ||
    style == "no-bullet"
  self.convert_list(
    node,
    fn(index, _item) {
      let n = start + index
      match style {
        "loweralpha" => "\{alpha(n, false)}."
        "upperalpha" => "\{alpha(n, true)}."
        "lowerroman" => "\{roman(n, false)}."
        "upperroman" => "\{roman(n, true)}."
        // LowercaseGreekA, counted on by `String#next` one code point a step
        // (a start below 1 does not count back from a letter)
        "lowergreek" =>
          "\{Int::unsafe_to_char(0x3B1 + @cmp.maximum(start - 1, 0) + index)}."
        "none" | "unstyled" | "unnumbered" | "no-bullet" => ""
        "decimal" => if n < 10 { "0\{n}." } else { "\{n}." }
        _ => "\{n}."
      }
    },
    unmarked~,
  )
}

///|
fn Converter::convert_list(
  self : Converter,
  node : @core.Node,
  marker_of : (Int, @core.Node) -> String,
  unmarked? : Bool = false,
) -> Unit {
  let flow = self.flow
  if node.has_title() {
    self.ink_caption(node.title().unwrap_or(""))
  }
  let base = base_style()
  let face = flow.font(base)
  let metrics = line_metrics(base_line_height, face, base.size)
  // a list without markers is indented less: not at all when unstyled,
  // else by the room a marker and an `x` would take less
  let indent = if !unmarked {
    list_indent
  } else if node.style == Some("unstyled") {
    0.0
  } else {
    let sample = if node.context == Ulist { "•x" } else { "1.x" }
    @cmp.maximum(list_indent - flow.width_of(sample, base), 0.0)
  }
  // the items' text (not their blocks) aligns by the list's role, and a
  // bibliography's to the left
  let align = match node.roles().iter().find_first(r => r.has_prefix("text-")) {
    Some(_) => Some(role_align(node.roles(), self.text_align))
    None => if node.style == Some("bibliography") { Some(Left) } else { None }
  }
  flow.indent(indent, 0.0, fn() {
    for index, item in node.items() {
      // allocate_space_for_list_item
      if !flow.at_page_top() &&
        flow.cursor() <
        base_line_height * base.size + metrics.leading + metrics.padding_top {
        flow.advance_page()
      }
      let marker = marker_of(index, item)
      self.traced(item, "list_item", () => {
        self.convert_list_item(item, marker, metrics, align?)
      })
    }
  })
  if !list_nested(node) && next_enclosed_block(node) is Some(_) {
    self.flow.margin(prose_margin_bottom)
  }
}

///|
/// asciidoctor-pdf's `List#nested?`: the list sits in a list item.
fn list_nested(node : @core.Node) -> Bool {
  node.parent() is Some(parent) && parent.context == ListItem
}

///|
/// Ruby's `ListItem#compound?`: blocks other than a single nested list.
fn is_compound_item(item : @core.Node) -> Bool {
  match item.blocks {
    [] => false
    [only] => !(only.context == Ulist || only.context == Olist)
    _ => true
  }
}

///|
fn Converter::convert_list_item(
  self : Converter,
  item : @core.Node,
  marker : String,
  metrics : LineMetrics,
  align? : Alignment,
) -> Unit {
  let flow = self.flow
  let base = base_style()
  if !marker.is_empty() {
    // the marker hangs in the indent, right-aligned one `x` before the
    // text, in a float that does not move the cursor
    let face = flow.font(base)
    let gap = face.prawn_width('x'.to_int()) * base.size / 1000.0
    let lines = typeset_lines(
      [{ text: marker, style: base, anchor: None, }],
      flow.catalog,
      1000.0,
      Left,
    )
    let width = if lines.length() > 0 { lines[0].fit_width } else { 0.0 }
    let y = flow.y
    let page = flow.page
    // the marker's text box stretches to the bottom margin: when its line
    // does not fit above it, the marker goes to the top of the next page,
    // where the item's text will follow it (`flow_bounding_box`)
    let a = face.ascender_pt(base.size)
    if !flow.at_page_top() &&
      metrics.padding_top + a + face.descender_pt(base.size) >
      flow.cursor() + 0.0001 {
      flow.advance_page()
    }
    let baseline = flow.y + metrics.padding_top + a
    if lines.length() > 0 {
      // set with `character_spacing: -0.5`, which Prawn does not count
      // after the last glyph: right-aligned in a box as wide as the marker
      // without it, the text starts 0.5pt in per glyph after the first,
      // plus the 0.5pt asciidoctor-pdf adds back
      // (`character_spacing_correction`)
      let mut glyphs = 0
      for run in lines[0].runs {
        for i in 0..<run.advances.length() {
          run.advances[i] -= 0.5
          glyphs += 1
        }
      }
      let shift = 0.5 * glyphs.to_double()
      flow.ink_line(lines[0], flow.left - width - gap + shift, baseline)
    }
    flow.page = page
    flow.y = y
  }
  let margin_bottom = if is_compound_item(item) {
    prose_margin_bottom
  } else if next_enclosed_block(item, descend=true) is Some(_) {
    list_item_spacing
  } else {
    0.0
  }
  match item.text() {
    Some(text) if !text.is_empty() =>
      self.ink_prose(text, align?, margin_bottom~, normalize_line_height=true)
    // an item without text or blocks still takes a line (`DummyText`)
    _ =>
      if !item.has_blocks() {
        self.ink_prose("", margin_bottom~, normalize_line_height=true)
      }
  }
  self.traverse(item)
}

///|
fn Converter::convert_dlist(self : Converter, node : @core.Node) -> Unit {
  self.add_dest(node)
  let flow = self.flow
  if node.has_title() {
    self.ink_caption(node.title().unwrap_or(""))
  }
  if node.style == Some("horizontal") {
    self.convert_horizontal_dlist(node)
    return
  }
  let term_style = Style::new(bold=true)
  // `height_of_typeset_text 'A'` in the term font and in the prose font
  let one_line = fn(style : Style) {
    flow.height_of(
      [{ text: "A", style, anchor: None, }],
      line_metrics(base_line_height, flow.font(style), style.size),
      style,
    )
  }
  let term_height = one_line(term_style)
  let prose_height = one_line(base_style())
  for entry in node.dlist_items {
    // keep the terms (and the first line of the description) together
    let desc_text = match entry.desc {
      Some(desc) => desc.text().map(t => !t.is_empty()).unwrap_or(false)
      None => false
    }
    let nlines = entry.terms.length() + (if desc_text { 1 } else { 0 })
    let blocks_only = match entry.desc {
      Some(desc) => !desc_text && desc.has_blocks()
      None => false
    }
    let needed = nlines.to_double() * term_height +
      (nlines - 1).to_double() * description_list_term_spacing +
      (if blocks_only {
        description_list_term_spacing + prose_height
      } else {
        0.0
      })
    if !flow.at_page_top() && flow.cursor() < needed {
      flow.advance_page()
    }
    for index, term in entry.terms {
      if index > 0 {
        flow.margin(description_list_term_spacing)
      }
      self.ink_prose(
        term.text().unwrap_or(""),
        style=term_style,
        align=Left,
        margin_bottom=0.0,
        normalize_line_height=true,
      )
    }
    match entry.desc {
      Some(desc) =>
        flow.indent(description_list_description_indent, 0.0, fn() {
          flow.margin(description_list_term_spacing)
          let margin_bottom = if next_enclosed_block(desc, descend=true)
            is Some(_) {
            prose_margin_bottom
          } else {
            0.0
          }
          match desc.text() {
            Some(text) if !text.is_empty() =>
              self.ink_prose(text, margin_bottom~, normalize_line_height=true)
            _ => ()
          }
          self.traverse(desc)
        })
      None => ()
    }
  }
  if !list_nested(node) && next_enclosed_block(node) is Some(_) {
    flow.margin(prose_margin_bottom)
  }
}

///|
fn Converter::convert_horizontal_dlist(
  self : Converter,
  node : @core.Node,
) -> Unit {
  let flow = self.flow
  let term_style = Style::new(bold=true)
  let mut term_width = 0.0
  for entry in node.dlist_items {
    for term in entry.terms {
      let lines = typeset_lines(
        parse_formatted(term.text().unwrap_or(""), term_style),
        flow.catalog,
        1.0e6,
        Left,
      )
      for line in lines {
        if line.fit_width > term_width {
          term_width = line.fit_width
        }
      }
    }
  }
  let column = @cmp.minimum(term_width + 20.0, flow.width() * 0.5 - 20.0)
  // `height_of_typeset_text 'A'` in the term font and in the prose font
  let one_line = fn(style : Style) {
    flow.height_of(
      [{ text: "A", style, anchor: None, }],
      line_metrics(base_line_height, flow.font(style), style.size),
      style,
    )
  }
  let term_height = one_line(term_style)
  let prose_height = one_line(base_style())
  for entry in node.dlist_items {
    // the terms (and a line of the description) must fit, else the entry
    // starts on the next page
    let terms = entry.terms.length().to_double()
    let needed = @cmp.maximum(
      (description_list_term_spacing + term_height) * terms -
      description_list_term_spacing,
      if entry.desc is Some(_) {
        prose_height
      } else {
        0.0
      },
    )
    if !flow.at_page_top() && flow.cursor() < needed {
      flow.advance_page()
    }
    let start_page = flow.page
    let start_y = flow.y
    flow.indent(10.0, flow.width() - column, fn() {
      for index, term in entry.terms {
        if index > 0 {
          flow.margin(description_list_term_spacing)
        }
        self.ink_prose(
          term.text().unwrap_or(""),
          style=term_style,
          align=Left,
          margin_bottom=0.0,
          normalize_line_height=true,
        )
      }
    })
    let (term_page, term_y) = (flow.page, flow.y)
    match entry.desc {
      Some(desc) => {
        flow.page = start_page
        flow.y = start_y
        // traverse_list_item: the description's text takes the prose
        // margin below when something follows it in the entry
        let margin_bottom = if next_enclosed_block(desc, descend=true)
          is Some(_) {
          prose_margin_bottom
        } else {
          0.0
        }
        flow.indent(column + 10.0, 10.0, fn() {
          match desc.text() {
            Some(text) if !text.is_empty() =>
              self.ink_prose(text, margin_bottom~, normalize_line_height=true)
            _ =>
              if !desc.has_blocks() {
                self.ink_prose("", margin_bottom~, normalize_line_height=true)
              }
          }
          self.traverse(desc)
        })
        // the cursor ends below the last term
        if flow.page < term_page || (flow.page == term_page && flow.y < term_y) {
          flow.page = term_page
          flow.y = term_y
        }
      }
      None => ()
    }
  }
  if !list_nested(node) && next_enclosed_block(node) is Some(_) {
    flow.margin(prose_margin_bottom)
  }
}

///|
fn Converter::convert_admonition(self : Converter, node : @core.Node) -> Unit {
  let flow = self.flow
  let name = node.attr("name").unwrap_or("")
  // `icons=font`: the admonition's icon, 24pt, in a column one and a half
  // times as wide (`admonition_icon_data`); other icons (images) are left
  // out, and the label is text
  let icon = match self.doc.attr("icons") {
    Some("font") if !node.has_attr("icon") =>
      match admonition_icon(name) {
        Some((set, icon_name, color)) =>
          match flow.catalog.icon_glyph(set, icon_name) {
            Some(glyph) => Some((set, glyph, color))
            None => None
          }
        None => None
      }
    Some(_) => {
      unsupported("block", "admonition icon image", node)
      None
    }
    None => None
  }
  let label_style = Style::new(bold=true)
  let label = sanitize(node.caption().unwrap_or(name)).to_upper()
  let label_lines = if icon is Some(_) {
    []
  } else {
    typeset_lines(
      [{ text: label, style: label_style, anchor: None, }],
      flow.catalog,
      1.0e6,
      Left,
    )
  }
  let label_width = if icon is Some(_) {
    admonition_icon_size * 1.5
  } else if label_lines.length() > 0 {
    label_lines[0].fit_width
  } else {
    0.0
  }
  let (pad_top, pad_right, pad_bottom, pad_left) = admonition_padding
  let label_face = flow.font(label_style)
  // arrange_block: the label and the rule are drawn once the extent is
  // known, so they take no part in keeping the block on this page; the
  // title is content
  self.arrange_block(keep_together=node.has_option("unbreakable"), node~, fn(
    c,
  ) {
    let flow = c.flow
    c.add_dest(node)
    let start = flow.mark()
    let box_left = flow.left + pad_left
    let rule_x = box_left + label_width + pad_right
    flow.indent(pad_left, pad_right, fn() {
      flow.move_down(pad_top)
      flow.indent(label_width + pad_right + pad_left, 0.0, fn() {
        if node.has_title() {
          c.ink_caption(node.title().unwrap_or(""))
        }
        c.push_gutter(node, pad_bottom)
        c.traverse(node)
        c.pop_gutter()
      })
      flow.pad_bottom(pad_bottom)
    })
    flow.underlay(start, fn(top, bottom, first, _last) {
      let items = [
        vrule(
          rule_x, top, bottom, admonition_column_rule_width, admonition_column_rule_color,
        ),
      ]
      match icon {
        Some((set, glyph, color)) if first => {
          // the icon, no taller than the label box, centred in it: moved
          // down by half the room it leaves, then set as Prawn's `text`
          // (the first baseline an ascender below the top), centred
          // across the column (`fit_icon_to_bounds`, `icon`)
          let height = bottom - top
          let size = @cmp.minimum(height, admonition_icon_size)
          let offset = @cmp.maximum((height - size) * 0.5, 0.0)
          let style = {
            ..Style::new(family=set, size~, color~),
            font_set: true,
          }
          let lines = typeset_lines(
            [{ text: glyph, style, anchor: None, }],
            flow.catalog,
            label_width,
            Center,
          )
          let face = flow.font(style)
          if lines.length() > 0 {
            items.append(
              flow.line_items(
                lines[0],
                box_left,
                top + offset + face.ascender_pt(size),
              ),
            )
          }
        }
        _ =>
          if first && label_lines.length() > 0 {
            // the label is centred vertically on the part of the block on
            // its first page
            let a = label_face.ascender_pt(label_style.size)
            let d = label_face.descender_pt(label_style.size)
            let offset = @cmp.maximum((bottom - top - (a + d)) / 2.0, 0.0)
            items.append(
              flow.line_items(label_lines[0], box_left, top + offset + a),
            )
          }
      }
      items
    })
  })
  self.block_margin_bottom(node)
}

///|
/// The size of an admonition's font icon (`admonition_icon_<type>_size`).
let admonition_icon_size = 24.0

///|
/// asciidoctor-pdf's `AdmonitionIcons`: the icon set, icon name and colour
/// of each admonition type (a type it does not know takes the note's
/// icon, in the text colour).
fn admonition_icon(name : String) -> (String, String, Color)? {
  match name {
    "caution" => Some(("fas", "fire", rgb_hex(0xBF3400)))
    "important" => Some(("fas", "exclamation-circle", rgb_hex(0xBF0000)))
    "note" => Some(("fas", "info-circle", rgb_hex(0x19407C)))
    "tip" => Some(("far", "lightbulb", rgb_hex(0x111111)))
    "warning" => Some(("fas", "exclamation-triangle", rgb_hex(0xBF6900)))
    _ => Some(("fas", "info-circle", base_font_color))
  }
}

///|
fn Converter::convert_example(self : Converter, node : @core.Node) -> Unit {
  if node.has_option("collapsible") {
    self.convert_collapsible(node)
    return
  }
  self.bordered_block(
    node,
    padding=vertical_rhythm,
    side_padding=horizontal_rhythm,
    fill=None,
    stroke=example_border_color,
    stroke_width=example_border_width,
    caption=true,
  )
}

///|
fn Converter::convert_sidebar(self : Converter, node : @core.Node) -> Unit {
  self.bordered_block(
    node,
    padding=vertical_rhythm,
    side_padding=vertical_rhythm * 1.25,
    fill=Some(sidebar_background_color),
    stroke=sidebar_border_color,
    stroke_width=0.5,
    caption=false,
  )
}

///|
/// asciidoctor-pdf's `convert_pass`: the content as it is, in the code font
/// and the base colour, with no box around it.
fn Converter::convert_pass(self : Converter, node : @core.Node) -> Unit {
  let flow = self.flow
  let style = Style::new(family=mono_font_family, size=code_font_size)
  let face = flow.font(style)
  flow.typeset(
    [{ text: guard_indentation(node.content()), style, anchor: None, }],
    line_metrics(code_line_height, face, code_font_size),
    style,
  )
  self.block_margin_bottom(node)
}

///|
/// asciidoctor-pdf's `convert_video` and `convert_audio` without a poster
/// image: a play symbol (the `fas-play` icon with `icons=font`), the link
/// to the media and its kind, then the caption below.
fn Converter::convert_media(
  self : Converter,
  node : @core.Node,
  kind : String,
) -> Unit {
  let target = node.attr("target").unwrap_or("")
  let (path, what) = match node.attr("poster") {
    Some("youtube") if kind == "video" =>
      ("https://www.youtube.com/watch?v=\{target}", "YouTube video")
    Some("vimeo") if kind == "video" =>
      ("https://vimeo.com/\{target}", "Vimeo video")
    Some(poster) if kind == "video" && poster != "" => {
      unsupported("block", "video poster image", node)
      (node.media_uri(target), kind)
    }
    _ => (node.media_uri(target), kind)
  }
  self.add_dest(node)
  let play = match
    (self.doc.attr("icons"), self.flow.catalog.icon_glyph("fas", "play")) {
    (Some("font"), Some(glyph)) => "<font name=\"fas\">\{glyph}</font>"
    _ => "\u{25ba}"
  }
  self.ink_prose(
    "\{play}\u{a0}<a href=\"\{path}\">\{path}</a> <em>(\{what})</em>",
    normalize=false,
    margin_bottom=0.0,
  )
  if node.has_title() {
    self.ink_caption(node.title().unwrap_or(""), bottom=true)
  }
  self.block_margin_bottom(node)
}

///|
/// asciidoctor-pdf's `convert_abstract` with the default theme: its title
/// centred in the h4 heading font, then its paragraphs in the abstract font
/// (#5C6266, 13pt, italic, line height 1.4), the first line of the first
/// one in bold italic (`abstract_first_line_font_style`); other blocks as
/// usual.
fn Converter::convert_abstract(self : Converter, node : @core.Node) -> Unit {
  let flow = self.flow
  self.add_dest(node)
  if node.has_title() {
    flow.margin(heading_margin_top)
    self.ink_prose(
      node.title().unwrap_or(""),
      style=Style::new(size=heading_font_size(4), doc_bold=true),
      align=Center,
      margin_bottom=heading_margin_bottom,
      line_height=1.0,
    )
  }
  let style = Style::new(
    size=abstract_font_size,
    color=abstract_font_color,
    doc_italic=true,
  )
  let first = { ..style, doc_bold: true, }
  let mut first_line = true
  if node.has_blocks() {
    for child in node.blocks {
      if child.context != Paragraph {
        self.convert_block(child)
        continue
      }
      child.document().playback_attributes(child.attributes)
      self.add_dest(child)
      if child.has_title() {
        self.ink_caption(child.title().unwrap_or(""))
      }
      self.ink_prose(
        child.content(),
        style~,
        align=role_align(child.roles(), self.text_align),
        margin_bottom=0.0,
        line_height=abstract_line_height,
        bottom_gutter=self.gutter(child),
        first_line_style?=if first_line { Some(first) } else { None },
      )
      first_line = false
      if next_enclosed_block(child) is Some(_) {
        flow.margin(prose_margin_bottom)
      }
    }
  } else {
    let text = node.content()
    if !text.is_empty() {
      self.ink_prose(
        text,
        style~,
        align=role_align(node.roles(), self.text_align),
        margin_bottom=0.0,
        line_height=abstract_line_height,
        first_line_style=first,
      )
    }
  }
  self.block_margin_bottom(node)
}

///|
/// asciidoctor-pdf's `convert_collapsible`: an example block with the
/// `collapsible` option is its title (default `Details`) after a
/// down-pointing triangle, as a caption, then its content indented by the
/// triangle's width; arranged when it has an id.
fn Converter::convert_collapsible(self : Converter, node : @core.Node) -> Unit {
  let marker = "\u{25bc} "
  let title = marker + node.title().unwrap_or("Details")
  let caption_style = Style::new(size=caption_font_size, doc_italic=true)
  let indent_by = self.flow.width_of(marker, caption_style)
  let body = fn(c : Converter) {
    c.add_dest(node)
    c.flow.tared(() => c.ink_caption(title))
    c.flow.indent(indent_by, 0.0, () => c.traverse(node))
  }
  if !self.flow.at_page_top() &&
    (node.id is Some(_) || node.has_option("unbreakable")) {
    self.arrange_block(
      keep_together=node.has_option("unbreakable"),
      node~,
      body,
    )
  } else {
    body(self)
  }
  self.block_margin_bottom(node)
}

///|
/// A padded block with a background and border (example, sidebar), in
/// `arrange_block`: its destination, then its caption (example) or title
/// (sidebar), both tared, then its content; where it breaks across pages,
/// a dashed line in the gap colour cuts into the border
/// (`theme_fill_and_stroke_block`).
fn Converter::bordered_block(
  self : Converter,
  node : @core.Node,
  padding~ : Double,
  side_padding~ : Double,
  fill~ : Color?,
  stroke~ : Color,
  stroke_width~ : Double,
  caption~ : Bool,
) -> Unit {
  self.arrange_block(keep_together=node.has_option("unbreakable"), node~, fn(
    c,
  ) {
    let flow = c.flow
    c.add_dest(node)
    if caption && node.has_title() {
      flow.tared(() => c.ink_caption(node.captioned_title()))
    }
    let start = flow.mark()
    let (left, right) = (flow.left, flow.right)
    flow.move_down(padding)
    flow.indent(side_padding, side_padding, fn() {
      if !caption && node.has_title() {
        // sidebar title: centred, bold, heading h4 size
        flow.tared(() => {
          c.ink_prose(
            node.title().unwrap_or(""),
            style=Style::new(size=heading_font_size(4), doc_bold=true),
            align=Center,
            margin_bottom=heading_margin_bottom,
            // the heading line height, 1
            line_height=1.0,
          )
        })
      }
      c.push_gutter(node, padding)
      c.traverse(node)
      c.pop_gutter()
    })
    flow.pad_bottom(padding)
    // the page's white when the block has no background of its own
    let gap = fill.unwrap_or(rgb_hex(0xFFFFFF))
    flow.underlay(start, fn(top, bottom, first, last) {
      let items = [
        rect_item(
          left,
          top,
          right - left,
          bottom - top,
          fill?,
          stroke~,
          stroke_width~,
        ),
      ]
      let inset = 4.0 + stroke_width
      let width = stroke_width * 1.2
      if !first {
        items.append(dashed_hrule(left + inset, right - inset, top, width, gap))
      }
      if !last {
        items.append(
          dashed_hrule(left + inset, right - inset, bottom, width, gap),
        )
      }
      items
    })
  })
  self.block_margin_bottom(node)
}

///|
fn Converter::convert_quote(self : Converter, node : @core.Node) -> Unit {
  let border = horizontal_rhythm / 3.0
  let pad = vertical_rhythm / 4.0
  let attribution = node.attr("attribution")
  // arrange_block: the destination, the caption (tared), then the content
  // in the quote padding, whose bottom the last line keeps clear of
  // unless an attribution follows
  self.arrange_block(keep_together=node.has_option("unbreakable"), node~, fn(
    c,
  ) {
    let flow = c.flow
    c.add_dest(node)
    if node.has_title() {
      flow.tared(() => c.ink_caption(node.title().unwrap_or("")))
    }
    let start = flow.mark()
    let left = flow.left
    let style = Style::new(size=quote_font_size)
    flow.move_down(pad)
    flow.indent(horizontal_rhythm + border / 2.0, horizontal_rhythm, fn() {
      if attribution is None {
        c.push_gutter(node, pad)
      } else {
        c.gutters.push(None)
      }
      if node.context == Verse {
        c.ink_prose(
          guard_indentation(node.content()),
          style~,
          align=role_align(node.roles(), Left),
          margin_bottom=0.0,
          normalize=false,
          bottom_gutter=c.gutter(node),
        )
      } else if !node.has_blocks() {
        // a quoted paragraph (`[quote]` on a paragraph) carries its text
        // itself (`traverse`)
        let text = node.content()
        if !text.is_empty() {
          c.ink_prose(
            text,
            style~,
            align=role_align(node.roles(), c.text_align),
            margin_bottom=0.0,
            bottom_gutter=c.gutter(node),
          )
        }
      } else {
        // quote paragraphs take the quote font size
        for block in node.blocks {
          if block.context == Paragraph {
            c.ink_prose(
              block.content(),
              style~,
              margin_bottom=if next_enclosed_block(block) is Some(_) {
                prose_margin_bottom
              } else {
                0.0
              },
              bottom_gutter=c.gutter(block),
            )
          } else {
            c.convert_block(block)
          }
        }
      }
      c.pop_gutter()
      match attribution {
        Some(attribution) => {
          flow.margin(block_margin_bottom)
          let cite = match node.attr("citetitle") {
            Some(title) => "\{attribution}, \{title}"
            None => attribution
          }
          c.ink_prose(
            "— \{cite}",
            style=Style::new(
              size=(base_font_size * 0.85).round(),
              color=rgb_hex(0x999999),
            ),
            align=Left,
            margin_bottom=0.0,
            normalize=false,
          )
        }
        None => ()
      }
    })
    flow.pad_bottom(pad)
    flow.underlay(start, fn(top, bottom, _first, _last) {
      [vrule(left + border / 2.0, top, bottom, border, quote_border_color)]
    })
  })
  self.block_margin_bottom(node)
}

///|
fn Converter::convert_open(self : Converter, node : @core.Node) -> Unit {
  if node.style == Some("abstract") {
    self.convert_abstract(node)
    return
  }
  // a titled open block, or one with an id, is arranged: its caption is
  // tared, so it moves on with the content after it
  if !self.flow.at_page_top() &&
    (node.has_title() || node.id is Some(_) || node.has_option("unbreakable")) {
    self.arrange_block(keep_together=node.has_option("unbreakable"), node~, fn(
      c,
    ) {
      c.add_dest(node)
      if node.has_title() {
        c.flow.tared(() => c.ink_caption(node.title().unwrap_or("")))
      }
      c.traverse(node)
    })
  } else {
    self.add_dest(node)
    if node.has_title() {
      self.ink_caption(node.title().unwrap_or(""))
    }
    self.traverse(node)
  }
}

///|
fn Converter::convert_thematic_break(
  self : Converter,
  node : @core.Node,
) -> Unit {
  let flow = self.flow
  flow.move_down(vertical_rhythm * 0.5)
  flow.push(hrule(flow.left, flow.right, flow.y, 0.5, thematic_break_color))
  flow.move_down(vertical_rhythm * 0.5)
  self.block_margin_bottom(node)
}

///|
/// Footnotes not yet inked, at the bottom of the page (asciidoctor-pdf's
/// `ink_footnotes` with `footnotes_margin_top: auto`): after the document,
/// and in a book after each chapter. Labels count from the first footnote
/// inked here.
fn Converter::ink_footnotes(self : Converter, node : @core.Node) -> Unit {
  let footnotes = self.doc.footnotes()
  if footnotes.length() <= session.rendered_footnotes {
    return
  }
  let pending = footnotes[session.rendered_footnotes:].to_owned()
  let flow = self.flow
  let is_last = match self.doc.blocks.last() {
    Some(last) => physical_equal(last, node)
    None => false
  }
  if node.context == Document || is_last {
    flow.margin(block_margin_bottom)
  }
  let style = Style::new(size=(base_font_size * 0.75).round())
  let face = flow.font(style)
  let metrics = line_metrics(base_line_height, face, style.size)
  let offset = session.rendered_footnotes
  let texts = pending.map(fn(fn_) {
    "<a id=\"_footnotedef_\{fn_.index}\"></a>[<a anchor=\"_footnoteref_\{fn_.index}\">\{fn_.index - offset}</a>] \{fn_.text}"
  })
  let mut height = 0.0
  for text in texts {
    height += flow.height_of(parse_formatted(text, style), metrics, style) + 3.0
  }
  if height < flow.cursor() {
    flow.move_down(flow.cursor() - height - 0.0001)
  }
  for text in texts {
    self.ink_prose(text, style~, margin_bottom=3.0)
  }
  if !flow.scratch {
    // a later reference to one of these (an xref footnote) shows its label,
    // with the chapter it is in
    if node.context == Section {
      let xreftext = node
        .xreftext(xrefstyle?=self.doc.attr("xrefstyle"))
        .unwrap_or("")
      for fn_ in pending {
        session.footnote_labels[fn_.index] = "\{fn_.index - offset} - \{xreftext}"
      }
    }
    session.rendered_footnotes = footnotes.length()
  }
}

///|
/// Running footer: a rule and the page number, right on recto pages and
/// left on verso ones (the default theme's `footer_*` keys), from the body
/// on: the first `front_matter` pages have none, and pages are numbered
/// from the body's first (`ink_running_content`).
fn Converter::ink_footers(self : Converter, front_matter : Int) -> Unit {
  let flow = self.flow
  let style = Style::new(size=footer_font_size)
  let face = flow.font(style)
  let top = page_height - footer_height
  let left = margin_side
  let right = page_width - margin_side
  for index, page in flow.model.pages {
    if index < front_matter {
      continue
    }
    let number = index + 1 - front_matter
    page.items.push(
      hrule(left, right, top, footer_border_width, footer_border_color),
    )
    let lines = typeset_lines(
      [{ text: number.to_string(), style, anchor: None, }],
      flow.catalog,
      right - left - 2.0,
      // the side follows the page number (`folio_placement` virtual)
      if number % 2 == 1 {
        Right
      } else {
        Left
      },
    )
    let baseline = top +
      base_line_height_length / 2.0 +
      face.ascender_pt(style.size)
    page.items.append(flow.line_items(lines[0], left + 1.0, baseline))
  }
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
