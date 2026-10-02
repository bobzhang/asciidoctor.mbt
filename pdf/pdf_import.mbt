///|
// PDF files as images, after asciidoctor-pdf's `convert_image` for a PDF
// target and its `import_page` (prawn-templates): a block image imports
// pages of the PDF, each on a page of its own the size of the imported
// page, with no running content or page background; the flow then goes on
// on a new page the size of the page before. A PDF also serves as a front
// or back cover and as a page background. pagelayout draws the imported
// page as a Form XObject (an `application/pdf` image item).

///|
/// The pages of a PDF: how many it has, and the size each is shown at;
/// None when the bytes are not a readable PDF.
priv struct PdfPages {
  data : Bytes
  document : @pdflite.PdfDocument
  count : Int
}

///|
fn read_pdf_pages(data : Bytes) -> PdfPages? {
  let document = @pdflite.pdf_read_document_from_bytes(data) catch {
    _ => return None
  }
  let count = document.endpage() catch { _ => 0 }
  Some({ data, document, count, })
}

///|
/// The size of page `number` (1-based), as prawn-templates looks pages up
/// (`page_references[number - 1]`, so 0 and negative numbers count from
/// the end), with the page's number from the start; None when there is no
/// such page or its boxes cannot be read.
fn PdfPages::page(self : PdfPages, number : Int) -> (Int, Double, Double)? {
  let index = if number >= 1 { number } else { self.count + number }
  guard index >= 1 && index <= self.count else { return None }
  let (w, h) = self.document.page_display_size(index) catch { _ => return None }
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
/// Ruby's `String#to_i`: the leading integer, after leading whitespace, or
/// 0.
fn ruby_to_i(value : String) -> Int {
  let text = value.trim_start(chars=" \t\n\r\u{0B}\u{0C}")
  let mut negative = false
  let mut n = 0
  for i, c in text {
    if i == 0 && (c == '-' || c == '+') {
      negative = c == '-'
      continue
    }
    guard c >= '0' && c <= '9' && n < 100000000 else { break }
    n = n * 10 + (c.to_int() - '0'.to_int())
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
/// range (both at least 1).
fn resolve_pagenums(value : String) -> Array[Int] {
  let separator = if value.contains(",") { "," } else { ";" }
  let pages : Array[Int] = []
  for entry in value.split(separator) {
    let entry = entry.to_owned()
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
  flow.start_new_page()
  let page = flow.model.pages[flow.page]
  if page.width_pt != w || page.height_pt != h {
    flow.model.pages[flow.page] = { ..page, width_pt: w, height_pt: h, }
    flow.fit_page_size()
    flow.apply_page_margins(flow.page)
  }
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
  match pdf.page(number) {
    Some((index, w, h)) => {
      start_sized_page(flow, w, h)
      if !flow.scratch {
        self.imported_pages[flow.page] = ()
      }
      flow.model.pages[flow.page].items.append(carried)
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
  path : String,
) -> Unit {
  let flow = self.flow
  let pdf = match read_pdf_pages(data) {
    Some(pdf) => pdf
    None => {
      // prawn-templates raises a TemplateError
      if !flow.scratch {
        warning("could not embed image: \{path}; not a readable PDF", node)
      }
      return
    }
  }
  let replace = flow.page == flow.model.pages.length() - 1 &&
    flow.model.pages[flow.page].items.iter().all(i => i is Anchor(_))
  let dests = match node.id {
    Some(id) => [id]
    None => []
  }
  match node.attr("pages") {
    Some(pages) =>
      for i, number in resolve_pagenums(pages) {
        if i == 0 {
          ignore(self.import_pdf_page(pdf, number, replace~, dests~))
        } else {
          ignore(self.import_pdf_page(pdf, number, replace=true))
        }
      }
    None => {
      let number = @cmp.maximum(ruby_to_i(node.attr("page").unwrap_or("")), 1)
      ignore(self.import_pdf_page(pdf, number, replace~, dests~))
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
