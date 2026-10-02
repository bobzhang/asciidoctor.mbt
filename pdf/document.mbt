///|
// The conversion of a document (asciidoctor-pdf's `convert_document`): the
// theme and page setup, the title page or title, the TOC, the body, the
// running content and the PDF's outline, labels and viewer settings.

///|
/// Convert a document loaded with `backend=pdf` (see `register`) to PDF,
/// in its theme's fonts (read through its VFS: run it inside
/// `@io.run_with_files`), or the catalog `register` was given. Load it with
/// `sourcemap` for `conversion_warnings` to say where the unsupported
/// content is.
pub fn convert(doc : @core.Node) -> Bytes raise {
  activate_session(doc)
  convert_document(doc, document_catalog(doc))
}

///|
/// asciidoctor-pdf's `Document#attr_unspecified?`: the attribute is not
/// locked, the document did not set or unset it, and the API's attributes
/// do not name it (soft `name@`, `!name` and `name!` forms included).
fn attr_unspecified(doc : @core.Node, name : String) -> Bool {
  if doc.attribute_locked(name) || doc.attribute_modified(name) {
    return false
  }
  for entry in doc.options().attributes {
    let (key, value) = entry
    let named = if key == name {
      true
    } else if value is Str("@") {
      key == "!\{name}" || key == "\{name}!"
    } else if key.has_suffix("@") {
      let k = key[:key.length() - 1].to_owned()
      k == name || k == "!\{name}" || k == "\{name}!"
    } else {
      false
    }
    if named {
      return false
    }
  }
  true
}

///|
/// The front matter of the document: how many pages have no running
/// content, and how many are not numbered from the body on
/// (`running_content_start_at`, `page_numbering_start_at`).
fn front_matter(
  title_as_page : Bool,
  has_title_page : Bool,
  toc_at_top : Bool,
  body_start : Int,
  has_front_cover? : Bool = false,
) -> (Int, Int) {
  // pages (0-based) before the body
  let body_offset = body_start
  if !title_as_page {
    let running = match tv("running_content_start_at") {
      Int(n) => body_offset + @cmp.maximum(n.to_int() - 1, 0)
      _ => body_offset
    }
    let numbering = match tv("page_numbering_start_at") {
      Int(n) => body_offset + @cmp.maximum(n.to_int() - 1, 0)
      Str("cover") if has_front_cover => 0
      _ => body_offset
    }
    return (running, numbering)
  }
  let zero = if has_front_cover { 1 } else { 0 }
  let first = if has_title_page { zero + 1 } else { zero }
  let resolve = (key : String) => {
    match tv(key) {
      Int(n) => ("body", body_offset + @cmp.maximum(n.to_int() - 1, 0))
      v => {
        let at = value_str(v).unwrap_or("body")
        let numbering = key == "page_numbering_start_at"
        match at {
          "cover" if numbering && has_front_cover => ("cover", 0)
          "cover" if numbering => ("title", body_offset)
          "title" => (if has_title_page { "title" } else { "toc" }, body_offset)
          "toc" => (if toc_at_top { "toc" } else { "body" }, body_offset)
          "after-toc" => ("body", body_offset)
          other => (other, body_offset)
        }
      }
    }
  }
  let (running_at, running_body) = resolve("running_content_start_at")
  let (numbering_at, numbering_body) = resolve("page_numbering_start_at")
  let offset = (at : String, body : Int) => {
    match at {
      "title" => zero
      "toc" => first
      _ => body
    }
  }
  (offset(running_at, running_body), offset(numbering_at, numbering_body))
}

///|
/// Convert a document loaded with `backend=pdf` (see `register`) to PDF,
/// set in the fonts of `catalog`.
pub fn convert_document(doc : @core.Node, catalog : FontCatalog) -> Bytes raise {
  // the document's own state (its theme, index, footnotes, images), which
  // another document loaded or converted since must not have touched
  activate_session(doc)
  let state = session()
  diagnostics.clear()
  diagnostics.append(state.pending_diagnostics)
  state.converting = true
  defer {
    state.converting = false
  }
  trace.clear()
  trace_depth.val = 0
  let theme = document_theme(doc)
  current_theme.val = theme
  session().font_scope = None
  session().page_setup = resolve_page_setup(doc)
  report_document_features(doc, catalog)
  // `outline`, `outline-title` and `pagenums` are on unless specified
  for name in ["outline", "outline-title", "pagenums"] {
    if attr_unspecified(doc, name) {
      ignore(doc.set_attr(name, value=Str("")))
    }
  }
  let flow = new_flow(catalog)
  let c = Converter::new(doc, flow)
  c.text_align = match doc.attr("text-align") {
    Some("left" | "right" | "center" | "justify" as align) =>
      alignment_of(align)
    _ => t_align("base_text_align", Left)
  }
  let is_book = doc.doctype() == "book"
  // a book (or `title-page`) has a title page instead of a title heading
  let title_as_page = is_book || doc.has_attr("title-page")
  let has_title_page = title_as_page &&
    doc.has_header() &&
    !doc.notitle() &&
    !(tv("title_page") is Bool(false))
  // `media=prepress` (`init_pdf`): recto pages take the inner margin on
  // the left and the outer on the right, verso pages the reverse; the first
  // page keeps the theme's margins (an article without a title page takes
  // the recto margins); a book's chapters start on recto pages
  if doc.attr("media") == Some("prepress") {
    c.ppbook = is_book
    let setup = session().page_setup
    let outer = t_num("page_margin_outer")
    let inner = t_num("page_margin_inner")
    let recto = (
      inner.unwrap_or(setup.margin_left),
      outer.unwrap_or(setup.margin_right),
    )
    let verso = (
      outer.unwrap_or(setup.margin_left),
      inner.unwrap_or(setup.margin_right),
    )
    let cover = if has_title_page ||
      doc.has_attr("front-cover-image") ||
      t_set("cover_front_image") {
      (setup.margin_left, setup.margin_right)
    } else {
      recto
    }
    side_margins.val = Some((recto, verso))
    flow.page_margins = Some(index => {
      if index == 0 {
        cover
      } else if index % 2 == 0 {
        recto
      } else {
        verso
      }
    })
  } else {
    side_margins.val = None
  }
  flow.start_new_page()
  // the front cover, on a page of its own (`ink_cover_page`)
  let has_front_cover = c.ink_cover_page("front")
  c.has_front_cover = has_front_cover
  // a book's title page goes on a recto page after a front cover
  // (`start_title_page`)
  if c.ppbook && has_front_cover && has_title_page {
    flow.start_new_page()
  }
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
  let title_page_index = flow.page
  if has_title_page {
    c.ink_title_page()
    flow.start_new_page()
  }
  if !title_as_page && doc.has_header() && !doc.notitle() {
    match doc.doctitle() {
      Some(title) =>
        c.ink_heading(
          title,
          1,
          align=t_str("heading_h1_text_align")
            .map(alignment_of)
            .unwrap_or(Center),
        )
      None => ()
    }
  }
  // an article's body starts where its title is, before the TOC
  let article_body_start = flow.page
  let levels = resolve_toclevels(doc)
  c.toc_levels = levels
  // the TOC at the top, unless the macro or the preamble places it
  let placement = doc.attr("toc-placement").unwrap_or("auto")
  let toc_at_top = has_toc(doc) &&
    placement != "macro" &&
    placement != "preamble"
  // the body, the TOC included, is inside the section indent
  // (`indent_section`)
  let (indent_left, indent_right) = section_indent().unwrap_or((0.0, 0.0))
  flow.left += indent_left
  flow.right -= indent_right
  if toc_at_top {
    // a prepress book's TOC starts on a recto page
    if c.ppbook && flow.on_verso() {
      flow.start_new_page()
    }
    flow.add_anchor(
      "toc",
      flow.dest_x(),
      if flow.at_page_top() {
        0.0
      } else {
        flow.y
      },
    )
    c.toc_extent = Some(
      c.allocate_toc(
        levels,
        title_as_page && t_str("toc_break_after") != Some("auto"),
      ),
    )
  }
  // a prepress book's body starts on a recto page, unless its first block
  // is `nonfacing`
  let first_block = match doc.blocks.get(0) {
    Some(b) if b.context == Preamble => b.blocks.get(0)
    other => other
  }
  if c.ppbook &&
    flow.on_verso() &&
    !(first_block is Some(b) && b.has_option("nonfacing")) {
    flow.start_new_page()
  }
  // pages before the body are front matter: numbered in roman, and without
  // running content (by default)
  let body_start = if title_as_page { flow.page } else { article_body_start }
  let (skip_running, skip_numbering) = front_matter(
    title_as_page,
    has_title_page,
    toc_at_top,
    body_start,
    has_front_cover~,
  )
  session().index.start_page_number = skip_numbering + 1
  // the top of the document, for `<<_top>>`-style references: the top of
  // the page the body starts on (`add_dest_for_top`)
  let top = top_anchor(doc)
  flow.add_anchor(top, 0.0, 0.0)
  let body = () => {
    // a man page starts with its name and purpose, as a section the
    // outline (built from the document's sections) does not list
    if doc.doctype() == "manpage" && doc.has_attr("manpurpose") {
      let listed = c.outline.length()
      c.convert_section(generate_manname_section(doc))
      while c.outline.length() > listed {
        ignore(c.outline.pop())
      }
    }
    c.traverse(doc)
    c.outdent_section(() => c.ink_footnotes(doc))
  }
  // an article's body in `page_columns` columns `page_column_gap` apart
  // (the font size by default, Prawn's column box spacer)
  let page_columns = t_num_or("page_columns", 1.0).to_int()
  if !is_book && page_columns >= 2 {
    flow.column_box(
      page_columns,
      t_num_or("page_column_gap", base_font_size()),
      body,
    )
  } else {
    body()
  }
  // a TOC the macro placed in the body of a book starts the running content
  // or the page numbering when they start at `toc` or `after-toc`
  let (skip_running, skip_numbering) = match c.toc_extent {
    Some(extent) if title_as_page && !toc_at_top => {
      let at = (key : String) => {
        match tv(key) {
          Str("toc") => Some(extent.from_page)
          Str("after-toc") => {
            // in a prepress book, the recto page after the TOC
            let after = extent.to_page + 1
            Some(if c.ppbook && after % 2 == 1 { after + 1 } else { after })
          }
          _ => None
        }
      }
      (
        at("running_content_start_at").unwrap_or(skip_running),
        at("page_numbering_start_at").unwrap_or(skip_numbering),
      )
    }
    _ => (skip_running, skip_numbering)
  }
  match c.toc_extent {
    Some(extent) => {
      let last = flow.page
      ignore(c.ink_toc(levels, extent.from_page, extent.from_y, skip_numbering))
      flow.go_to_page(last)
    }
    None => ()
  }
  flow.left -= indent_left
  flow.right += indent_right
  // a page started but never written to is dropped
  let pages = flow.model.pages
  if pages.length() > 1 &&
    pages[pages.length() - 1].items.iter().all(fn(i) { i is Anchor(_) }) {
    ignore(pages.pop())
  }
  // the page backgrounds (`init_page`), under everything
  c.ink_page_backgrounds(
    if has_title_page {
      Some(title_page_index)
    } else {
      None
    },
    front_cover=has_front_cover,
  )
  if flow.model.pages.length() > body_start {
    if !doc.has_attr("noheader") && t_num_or("header_height", 0.0) != 0.0 {
      c.ink_running_content(
        "header",
        skip_running,
        skip_numbering,
        body_start + 1,
      )
    }
    if !doc.has_attr("nofooter") && t_num_or("footer_height", 0.0) != 0.0 {
      c.ink_running_content(
        "footer",
        skip_running,
        skip_numbering,
        body_start + 1,
      )
    }
  }
  // the back cover, on a page after the last; it is not labeled itself
  // (the labels are added before it), so it takes the last page's label
  let labeled_pages = flow.model.pages.length()
  c.end_page_h = flow.model.pages[labeled_pages - 1].height_pt
  ignore(c.ink_cover_page("back"))
  keep_last_anchors(flow.model)
  for entry in @pdf.unembeddable_images(flow.model) {
    report("UNSUPPORTED image \{entry.0} (\{entry.1}x) at <document>")
  }
  let initial_zoom : @pdf.InitialZoom? = match t_str("page_initial_zoom") {
    Some("Fit") => Some(Fit)
    Some("FitV") => Some(FitV)
    // `dest_fit_horizontally page_height, state.pages[0]`: the window's top
    // at the height of the page current when the open action is set (the
    // last content page, before the back cover), measured from the first
    // page's bottom edge
    Some("FitH") =>
      Some(FitHAt(top=flow.model.pages[0].height_pt - c.end_page_h))
    _ => None
  }
  let page_mode : @pdf.PageMode = match
    doc.attr("pdf-page-mode").or_some(t_str("page_mode")) {
    Some("none") => UseNone
    Some("thumbs") => UseThumbs
    Some(
      "fullscreen"
      | "fullscreen none"
      | "fullscreen outline"
      | "fullscreen thumbs"
    ) => FullScreen
    _ => UseOutlines
  }
  @pdf.render_pdf(
    flow.model,
    options=@pdf.RenderOptions::new(
      // the faces the flow measured with, drawn and embedded as they are
      fonts=catalog.registry,
      outline=c.document_outline(),
      info=pdf_info(doc),
      initial_zoom?,
      page_mode~,
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
        page_label(@cmp.minimum(i, labeled_pages - 1) + 1, skip_numbering)
      }),
    ),
  )
}
