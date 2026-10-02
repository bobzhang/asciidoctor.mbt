///|
// PDF files as images, after asciidoctor-pdf's `convert_image` for a PDF
// target and its `import_page` (prawn-templates): a block image imports
// pages of the PDF, each on a page of its own the size of the imported
// page, with no running content or page background; the flow then goes on
// on a new page the size of the page before. A PDF also serves as a front
// or back cover and as a page background. pagelayout draws the imported
// page as a Form XObject (an `application/pdf` image item).

///|
/// prawn-templates' `PDF::Core::Errors::TemplateError`: a PDF imported as a
/// block image or a cover cannot be read, which fails the conversion (see
/// `template_failure`). The message is Ruby's.
pub(all) suberror TemplateError {
  TemplateError(String)
}

///|
/// prawn-templates' message for a PDF it cannot read, with what went wrong.
fn template_error_message(detail : String) -> String {
  "Error reading template file. If you are sure it's a valid PDF, it may be a bug.\n\{detail}"
}

///|
/// Fail the conversion with `error` once it is done (prawn-templates raises
/// from the middle of it); the first failure is the one reported.
fn template_failure(error : TemplateError) -> Unit {
  let TemplateError(message) = error
  let state = session()
  if state.template_error is None {
    state.template_error = Some(message)
  }
}

///|
/// The pages of a PDF: how many it has, and the size each is shown at.
priv struct PdfPages {
  data : Bytes
  source : @pdflite.PdfPageSource
  count : Int
}

///|
/// Read `data` as a PDF to import pages of, or raise `TemplateError` when it
/// is not a readable PDF or its page tree cannot be read.
fn read_pdf_pages(data : Bytes) -> PdfPages raise TemplateError {
  let document = @pdflite.pdf_read_document_from_bytes(data) catch {
    _ => raise TemplateError(template_error_message("PDF malformed"))
  }
  let source = @pdflite.PdfPageSource::new(document) catch {
    HardError(_) =>
      raise TemplateError("Template file contains unsupported PDF features")
    _ =>
      raise TemplateError(
        template_error_message("PDF malformed: invalid page tree"),
      )
  }
  { data, source, count: source.page_count(), }
}

///|
/// The size of page `number` (1-based), as prawn-templates looks pages up
/// (`page_references[number - 1]`, so 0 and negative numbers count from
/// the end), with the page's number from the start; None when the PDF has
/// no such page, and `TemplateError` when the page's boxes cannot be read.
fn PdfPages::page(
  self : PdfPages,
  number : Int,
) -> (Int, Double, Double)? raise TemplateError {
  let index = if number >= 1 { number } else { self.count + number }
  guard index >= 1 && index <= self.count else { return None }
  let (w, h) = self.source.page_display_size(index) catch {
    _ =>
      raise TemplateError(
        template_error_message("PDF malformed: invalid page boxes"),
      )
  }
  Some((index, w, h))
}

///|
/// The image item that draws page `index` of `data` over a page `w` by `h`.
fn pdf_page_item(
  data : Bytes,
  index : Int,
  w : Double,
  h : Double,
) -> @pagelayout.PageItem {
  Image({
    x_pt: 0.0,
    y_pt: 0.0,
    w_pt: w,
    h_pt: h,
    data,
    mime: "application/pdf; page=\{index}",
  })
}

///|
/// Ruby's `String#to_i`: the leading integer, after leading whitespace and
/// an optional sign, single underscores between digits allowed (`1_0` is
/// 10), or 0.
fn ruby_to_i(value : String) -> Int {
  let chars = value.trim_start(chars=" \t\n\r\u{0B}\u{0C}").to_array()
  let digit = (i : Int) => {
    i < chars.length() && chars[i] >= '0' && chars[i] <= '9'
  }
  let mut i = 0
  let negative = chars.get(0) == Some('-')
  if chars.get(0) is Some('-' | '+') {
    i = 1
  }
  let mut n = 0
  while digit(i) {
    if n < 100000000 {
      n = n * 10 + (chars[i].to_int() - '0'.to_int())
    }
    // an underscore joins digits
    i += if chars.get(i + 1) == Some('_') && digit(i + 2) { 2 } else { 1 }
  }
  if negative {
    -n
  } else {
    n
  }
}

///|
/// asciidoctor-pdf's `resolve_pagenums`: the `pages` attribute's entries,
/// split on commas (else semicolons), each a page number or a `from..to`
/// range (both at least 1). As Ruby's `String#split`, trailing empty
/// entries are dropped (`1,` is page 1, an empty list no page) while
/// others count as 0, which prawn-templates takes for the last page.
fn resolve_pagenums(value : String) -> Array[Int] {
  let separator = if value.contains(",") { "," } else { ";" }
  let entries = value.split(separator).map(e => e.to_owned()).to_array()
  while entries.last() == Some("") {
    ignore(entries.pop())
  }
  let pages : Array[Int] = []
  for entry in entries {
    match entry.find("..") {
      Some(i) => {
        let from = @cmp.maximum(ruby_to_i(entry[:i].to_owned()), 1)
        let to = @cmp.maximum(ruby_to_i(entry[i + 2:].to_owned()), 1)
        for n in from..<=to {
          pages.push(n)
        }
      }
      None => pages.push(ruby_to_i(entry))
    }
  }
  pages
}

///|
/// Start a page `w` by `h` after the last one (Prawn's `start_new_page`
/// with a `size`).
fn start_sized_page(flow : Flow, w : Double, h : Double) -> Unit {
  flow.start_new_page(size=(w, h))
}

///|
/// asciidoctor-pdf's `import_page`: page `number` of `pdf` on a page of its
/// own, the current page deleted first when `replace` (and empty; its
/// destinations move to the imported page), then, with `advance`, a new
/// page the size of the current one, where a column box starts over in its
/// first column. `dests` are named at the imported page's top. When the PDF
/// has no such page, nothing is imported, and with `advance_if_missing` the
/// flow goes on on a new page all the same. Returns whether the page was
/// imported.
fn Converter::import_pdf_page(
  self : Converter,
  pdf : PdfPages,
  number : Int,
  replace? : Bool = false,
  advance? : Bool = true,
  advance_if_missing? : Bool = true,
  dests? : Array[String] = [],
) -> Bool {
  let flow = self.flow
  // prawn-templates reads the page before anything changes; a page it
  // cannot read fails the conversion
  let page = pdf.page(number) catch {
    error => {
      template_failure(error)
      return false
    }
  }
  let (prev_w, prev_h) = match flow.model.pages.get(flow.page) {
    Some(p) => (p.width_pt, p.height_pt)
    None => (page_width(), page_height())
  }
  // `delete_current_page`: only the last page, and only when empty
  let carried : Array[@pagelayout.PageItem] = []
  if replace &&
    flow.page >= 0 &&
    flow.page == flow.model.pages.length() - 1 &&
    flow.model.pages[flow.page].items.iter().all(i => i is Anchor(_)) {
    carried.append(flow.model.pages[flow.page].items)
    ignore(flow.model.pages.pop())
    flow.page -= 1
  }
  // `advance_page` with the previous page's size, and a column box (Prawn's
  // ColumnBox `reset_top`) back in its first column
  let move_on = () => {
    match flow.columns {
      Some(columns) => {
        let back = columns.stride * columns.current.to_double()
        flow.left -= back
        flow.right -= back
        columns.current = 0
      }
      None => ()
    }
    start_sized_page(flow, prev_w, prev_h)
  }
  match page {
    Some((index, w, h)) => {
      start_sized_page(flow, w, h)
      if !flow.scratch {
        self.imported_pages[flow.page] = ()
      }
      // `dest_top` of the imported page: the destinations of the page it
      // replaced (the parent section's, the document's top) go to its
      // top-left corner
      for item in carried {
        match item {
          Anchor(anchor) =>
            flow.model.pages[flow.page].items.push(
              Anchor({ ..anchor, x_pt: 0.0, y_pt: 0.0, }),
            )
          other => flow.model.pages[flow.page].items.push(other)
        }
      }
      for dest in dests {
        flow.add_anchor(dest, 0.0, 0.0)
      }
      flow.push(pdf_page_item(pdf.data, index, w, h))
      if advance {
        move_on()
      }
      true
    }
    None => {
      if advance_if_missing {
        move_on()
        flow.model.pages[flow.page].items.append(carried)
      } else if !carried.is_empty() {
        // the deleted page's destinations stay on the page before
        match flow.model.pages.get(flow.page) {
          Some(page) => page.items.append(carried)
          None => ()
        }
      }
      false
    }
  }
}

///|
/// A block image of a PDF (asciidoctor-pdf's `convert_image` with a PDF
/// target): the page the `page` attribute names (the first by default), or
/// each page the `pages` attribute lists, imported in turn; the first
/// replaces the current page when it is empty. The block's id names the
/// top of the first imported page.
fn Converter::convert_pdf_image(
  self : Converter,
  node : @core.Node,
  data : Bytes,
) -> Unit {
  let flow = self.flow
  // the pages to import come first: a `pages` list that selects none
  // imports nothing, and prawn-templates never reads the file
  let numbers = match node.attr("pages") {
    Some(pages) => resolve_pagenums(pages)
    None => [@cmp.maximum(ruby_to_i(node.attr("page").unwrap_or("")), 1)]
  }
  if numbers.is_empty() {
    return
  }
  // prawn-templates raises a TemplateError, which fails the conversion
  let pdf = read_pdf_pages(data) catch {
    error => {
      template_failure(error)
      return
    }
  }
  let replace = flow.page == flow.model.pages.length() - 1 &&
    flow.model.pages[flow.page].items.iter().all(i => i is Anchor(_))
  let dests = match node.id {
    Some(id) => [id]
    None => []
  }
  for i, number in numbers {
    if i == 0 {
      ignore(self.import_pdf_page(pdf, number, replace~, dests~))
    } else {
      ignore(self.import_pdf_page(pdf, number, replace=true))
    }
  }
}

///|
/// The warning for a PDF block image that cannot be read
/// (`resolve_image_path`, then `convert_image`).
fn warn_missing_pdf(
  node : @core.Node,
  target : ImageTarget,
  path : String,
) -> Unit {
  match target {
    Path(uri) if uri.has_prefix("http://") || uri.has_prefix("https://") =>
      if node.document().has_attr("allow-uri-read") {
        warning("could not retrieve remote image: \{uri}", node)
      } else {
        warning(
          "cannot embed remote image: \{uri} (allow-uri-read attribute not enabled)",
          node,
        )
      }
    _ => warning("pdf to insert not found or not readable: \{path}", node)
  }
}
