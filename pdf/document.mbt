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
  diagnostics.clear()
  convert_document(doc, document_catalog(doc))
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
      _ => body_offset
    }
    return (running, numbering)
  }
  let zero = 0
  let first = if has_title_page { 1 } else { 0 }
  let resolve = (key : String) => {
    match tv(key) {
      Int(n) => ("body", body_offset + @cmp.maximum(n.to_int() - 1, 0))
      v => {
        let at = value_str(v).unwrap_or("body")
        let at = match at {
          "title" => if has_title_page { "title" } else { "toc" }
          "toc" => if toc_at_top { "toc" } else { "body" }
          "after-toc" => "body"
          "cover" => if key == "page_numbering_start_at" { "title" } else { at }
          other => other
        }
        let at = if at == "toc" && !toc_at_top { "body" } else { at }
        (at, body_offset)
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
  diagnostics.clear()
  trace.clear()
  trace_depth.val = 0
  let theme = document_theme(doc)
  current_theme.val = theme
  font_scope.val = None
  page_setup.val = resolve_page_setup(doc)
  report_document_features(doc, catalog)
  // `pagenums` is on unless the document turns it off
  ignore(doc.set_attr("pagenums", value=Str(""), overwrite=false))
  let flow = Flow::new(catalog)
  let c = Converter::new(doc, flow)
  c.text_align = match doc.attr("text-align") {
    Some("left" | "right" | "center" | "justify" as align) =>
      alignment_of(align)
    _ => t_align("base_text_align", Left)
  }
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
  let has_title_page = title_as_page &&
    doc.has_header() &&
    !doc.notitle() &&
    !(tv("title_page") is Bool(false))
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
  // pages before the body are front matter: numbered in roman, and without
  // running content (by default)
  let body_start = if title_as_page { flow.page } else { article_body_start }
  let (skip_running, skip_numbering) = front_matter(
    title_as_page, has_title_page, toc_at_top, body_start,
  )
  session.index.start_page_number = skip_numbering + 1
  // the top of the document, for `<<_top>>`-style references: the top of
  // the page the body starts on (`add_dest_for_top`)
  let top = top_anchor(doc)
  flow.add_anchor(top, 0.0, 0.0)
  if !is_book && t_num_or("page_columns", 1.0) >= 2.0 {
    unsupported("theme", "page_columns", doc)
  }
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
  c.outdent_section(() => c.ink_footnotes(doc))
  match c.toc_extent {
    Some(extent) => {
      let last = flow.page
      ignore(c.ink_toc(levels, extent.from_page, extent.from_y, skip_numbering))
      flow.page = last
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
  // the page background (`page_background_color`), under everything
  let background = page_background_color()
  if background != rgb_hex(0xFFFFFF) {
    for page in flow.model.pages {
      page.items.insert(
        0,
        rect_item(0.0, 0.0, page_width(), page_height(), fill=background),
      )
    }
  }
  if t_set("page_background_image") || doc.has_attr("page-background-image") {
    unsupported("theme", "page background image", doc)
  }
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
  keep_last_anchors(flow.model)
  for entry in @pdf.unembeddable_images(flow.model) {
    diagnostics.push("UNSUPPORTED image \{entry.0} (\{entry.1}x) at <document>")
  }
  let initial_zoom : @pdf.InitialZoom? = match t_str("page_initial_zoom") {
    Some("Fit") => Some(Fit)
    Some("FitV") => Some(FitV)
    Some("FitH") => Some(FitH)
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
        page_label(i + 1, skip_numbering)
      }),
    ),
  )
}
