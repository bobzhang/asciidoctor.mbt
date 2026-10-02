///|
/// A three-page PDF to import: 300 x 200, 400 x 100 and 612 x 792.
fn pdf_import_source() -> Bytes raise {
  let model = @pagelayout.PageModel::new()
  for size in [(300.0, 200.0), (400.0, 100.0), (612.0, 792.0)] {
    model.pages.push({ width_pt: size.0, height_pt: size.1, items: [], })
  }
  @pdf.render_pdf(model)
}

///|
/// A PDF without pages.
fn pdf_import_empty_source() -> Bytes raise {
  let document = @pdflite.pdf_document_empty()
  let root = document.add_pagetree([])
  ignore(document.add_root(root, []))
  @pdflite.pdf_write_document(document)
}

///|
/// Convert `text` with `src.pdf` and `empty.pdf` beside it: the pages'
/// sizes and whether each draws an imported page.
fn pdf_import_convert(text : String) -> Array[(Double, Double, Bool)] raise {
  register()
  let vfs = @core.MemoryVfs::new(cwd="/doc")
  vfs.add_bytes("/doc/src.pdf", pdf_import_source())
  vfs.add_bytes("/doc/empty.pdf", pdf_import_empty_source())
  let doc = @asciidoctor.load(
    text,
    options=@core.Options::new(
      backend="pdf",
      standalone=true,
      base_dir="/doc",
      attributes=[("nofooter", Str(""))],
      vfs~,
    ),
  )
  let bytes = convert_document(doc, test_catalog())
  let document = @pdflite.pdf_read_document_from_bytes(bytes)
  let xobject_key = @pdfcore.pdf_name_of_bytes(b"/XObject")
  document
  .pages_of_pagetree()
  .map(page => {
    let box = document.parse_rectangle(page.mediabox)
    let imported = document.lookup_direct(xobject_key, page.resources)
      is Some(PdfDictionary(entries)) &&
      entries
      .iter()
      .any(entry => {
        document.lookup_direct(
          @pdfcore.pdf_name_of_bytes(b"/Subtype"),
          document.direct(entry.1),
        )
        is Some(PdfNameObject(subtype)) &&
        subtype == @pdfcore.pdf_name_of_bytes(b"/Form")
      })
    (box.max_x - box.min_x, box.max_y - box.min_y, imported)
  })
}

///|
test "a PDF block image imports its page on a page of its own" {
  let pages = pdf_import_convert("before\n\nimage::src.pdf[page=2]\n\nafter\n")
  debug_inspect(
    pages,
    content=(
      #|[(595.28, 841.89, false), (400, 100, true), (595.28, 841.89, false)]
    ),
  )
}

///|
test "an empty page is replaced, missing pages are skipped" {
  // the first page is empty, so the import takes its place; page 9 does
  // not exist, and the page after it starts the flow over
  let pages = pdf_import_convert("image::src.pdf[pages=\"1,9,3\"]\n\nafter\n")
  debug_inspect(
    pages,
    content=(
      #|[(300, 200, true), (612, 792, true), (595.28, 841.89, false)]
    ),
  )
}

///|
test "a PDF without pages imports nothing" {
  let pages = pdf_import_convert(
    "== Before\n\nimage::empty.pdf[]\n\n== After\n",
  )
  debug_inspect(
    pages,
    content=(
      #|[(595.28, 841.89, false), (595.28, 841.89, false)]
    ),
  )
}

///|
test "a missing PDF is its alt text, with a warning" {
  let pages = pdf_import_convert("image::missing.pdf[PDF insert]\n")
  debug_inspect(
    pages,
    content=(
      #|[(595.28, 841.89, false)]
    ),
  )
  assert_true(
    conversion_warnings()
    .iter()
    .any(w => {
      w.contains("pdf to insert not found or not readable: /doc/missing.pdf")
    }),
  )
}

///|
test "a PDF front cover takes the place of the first page" {
  let pages = pdf_import_convert(
    ":front-cover-image: image:src.pdf[page=2]\n:back-cover-image: image:src.pdf[page=7]\n\ncontent\n",
  )
  debug_inspect(
    pages,
    content=(
      #|[(400, 100, true), (595.28, 841.89, false)]
    ),
  )
}

///|
test "resolve_pagenums reads lists and ranges as asciidoctor-pdf does" {
  debug_inspect(
    resolve_pagenums("3,1..2"),
    content=(
      #|[3, 1, 2]
    ),
  )
  debug_inspect(
    resolve_pagenums("3;0..2; 5x"),
    content=(
      #|[3, 1, 2, 5]
    ),
  )
  debug_inspect(
    resolve_pagenums("two"),
    content=(
      #|[0]
    ),
  )
}
