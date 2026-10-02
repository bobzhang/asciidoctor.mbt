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
/// Load `text` with `src.pdf`, `empty.pdf`, `bad.pdf` (not a PDF),
/// `other.pdf` (one 500 x 50 page), `mixed.pdf` (page 1 without a
/// usable media box, page 2 300 x 200) and `indent-theme.yml` (sections
/// indented 36pt) beside it.
fn pdf_import_load(text : String) -> @core.Node raise {
  register()
  let vfs = @core.MemoryVfs::new(cwd="/doc")
  vfs.add_bytes("/doc/src.pdf", pdf_import_source())
  vfs.add_bytes("/doc/empty.pdf", pdf_import_empty_source())
  vfs.add_bytes("/doc/bad.pdf", b"%PDF-1.4\nnot really a PDF\n")
  let other = @pagelayout.PageModel::new()
  other.pages.push({ width_pt: 500, height_pt: 50, items: [], })
  vfs.add_bytes("/doc/other.pdf", @pdf.render_pdf(other))
  vfs.add_bytes("/doc/mixed.pdf", pdf_import_mixed_source())
  vfs.add_text(
    "/doc/indent-theme.yml", "extends: default\nsection:\n  indent: 36\n",
  )
  @asciidoctor.load(
    text,
    options=@core.Options::new(
      backend="pdf",
      standalone=true,
      base_dir="/doc",
      attributes=[("nofooter", Str(""))],
      vfs~,
    ),
  )
}

///|
/// The pages' sizes of `bytes`, and whether each draws an imported page.
fn pdf_import_pages(bytes : Bytes) -> Array[(Double, Double, Bool)] raise {
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
/// Convert `text` (see `pdf_import_load`): its pages (see
/// `pdf_import_pages`).
fn pdf_import_convert(text : String) -> Array[(Double, Double, Bool)] raise {
  pdf_import_pages(convert_document(pdf_import_load(text), test_catalog()))
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

///|
/// The conversion of `text`, or the message of the `TemplateError` it
/// fails with.
fn pdf_import_failure(text : String) -> String? raise {
  let doc = pdf_import_load(text)
  try ignore(convert_document(doc, test_catalog())) catch {
    TemplateError(message) => Some(message)
    other => raise other
  } noraise {
    _ => None
  }
}

///|
/// The x and y of the named destination `name` in `bytes`.
fn pdf_import_dest(bytes : Bytes, name : String) -> (Double, Double)? raise {
  let document = @pdflite.pdf_read_document_from_bytes(bytes)
  let key = (text : String) => @pdfcore.pdf_name_of_bytes(@utf8.encode(text))
  let root = document
    .lookup_direct(key("/Root"), document.trailer_dict())
    .unwrap()
  let names = document.lookup_direct(key("/Names"), root).unwrap()
  let dests = document.lookup_direct(key("/Dests"), names).unwrap()
  guard document.lookup_direct(key("/Names"), dests) is Some(PdfArray(entries)) else {
    return None
  }
  for i = 0; i + 1 < entries.length(); i = i + 2 {
    if entries[i] is PdfString(bytes) && bytes == @utf8.encode(name) {
      guard document.direct(entries[i + 1]) is PdfArray(dest) else {
        return None
      }
      return Some((document.get_number(dest[2]), document.get_number(dest[3])))
    }
  }
  None
}

///|
test "page lists drop trailing empty entries, as Ruby's split does" {
  // `1,` is page 1 alone; an empty list imports nothing
  debug_inspect(
    pdf_import_convert("image::src.pdf[pages=\"1,\"]\n\nafter\n"),
    content=(
      #|[(300, 200, true), (595.28, 841.89, false)]
    ),
  )
  debug_inspect(
    pdf_import_convert("image::src.pdf[pages=\"\"]\n\nafter\n"),
    content=(
      #|[(595.28, 841.89, false)]
    ),
  )
  // an empty entry inside the list is 0, the last page
  debug_inspect(resolve_pagenums("1,,2"), content="[1, 0, 2]")
  debug_inspect(resolve_pagenums(",1,,"), content="[0, 1]")
  debug_inspect(resolve_pagenums(""), content="[]")
  debug_inspect(resolve_pagenums(";"), content="[]")
}

///|
test "ruby_to_i reads Ruby's integers" {
  debug_inspect(
    ["1_0", "1__0", "_1", "1_", " -2x", "+3", "1_000_000", "", "x"].map(
      ruby_to_i,
    ),
    content="[10, 1, 0, 1, -2, 3, 1000000, 0, 0]",
  )
}

///|
test "a block image of a PDF that cannot be read fails the conversion" {
  let failure = pdf_import_failure("before\n\nimage::bad.pdf[]\n\nafter\n")
  assert_true(
    failure is Some(message) &&
    message.has_prefix(
      "Error reading template file. If you are sure it's a valid PDF, it may be a bug.\n",
    ),
  )
  // a readable PDF without the page is not an error
  assert_true(pdf_import_failure("image::src.pdf[page=9]\n") is None)
}

///|
test "a cover PDF that cannot be read fails the conversion" {
  for face in ["front", "back"] {
    assert_true(
      pdf_import_failure(":\{face}-cover-image: image:bad.pdf[]\n\ncontent\n")
      is Some(_),
    )
    // a readable PDF without the page is no cover
    assert_true(
      pdf_import_failure(
        ":\{face}-cover-image: image:src.pdf[page=9]\n\ncontent\n",
      )
      is None,
    )
  }
}

///|
test "a page background PDF that cannot be read is a warning, once" {
  let pages = pdf_import_convert(
    ":page-background-image: image:bad.pdf[]\n\none\n\n<<<\n\ntwo\n\n<<<\n\nthree\n",
  )
  assert_eq(pages.length(), 3)
  assert_true(pages.iter().all(p => !p.2))
  let warnings = conversion_warnings().filter(w => {
    w.contains(
      "could not embed page background image: /doc/bad.pdf; Error reading template file.",
    )
  })
  // recto and verso take the same image: dropped for both at the first
  // failure
  assert_eq(warnings.length(), 1)
}

///|
test "an inline PDF image suggests prawn-gmagick, as Ruby does" {
  ignore(pdf_import_convert("text image:src.pdf[] text\n"))
  assert_true(
    conversion_warnings()
    .iter()
    .any(w => {
      w.contains(
        "could not embed image: /doc/src.pdf; image file is an unrecognised format; install prawn-gmagick gem to add support for PDF image format",
      )
    }),
  )
}

///|
test "a hidden section's destination moves to the top of the page imported over it" {
  let doc = pdf_import_load(
    "= Title\n:doctype: book\n:notitle:\n:pdf-theme: /doc/indent-theme.yml\n\ngo to <<blue>>\n\n[#blue%notitle]\n== Blue Page\n\nimage::src.pdf[page=2]\n",
  )
  let bytes = convert_document(doc, test_catalog())
  // `dest_top` of the imported page (100pt high): x 0, its top
  assert_eq(pdf_import_dest(bytes, "blue"), Some((0.0, 100.0)))
}

///|
test "documents with different PDF images convert independently" {
  let first = pdf_import_load("image::src.pdf[page=2]\n")
  let second = pdf_import_load("image::other.pdf[]\n")
  let broken = pdf_import_load("image::bad.pdf[]\n")
  for _ in 0..<2 {
    debug_inspect(
      pdf_import_pages(convert_document(first, test_catalog())),
      content="[(400, 100, true)]",
    )
    // the failure of one document is not another's
    try ignore(convert_document(broken, test_catalog())) catch {
      TemplateError(_) => ()
      other => raise other
    } noraise {
      _ => fail("expected a TemplateError")
    }
    debug_inspect(
      pdf_import_pages(convert_document(second, test_catalog())),
      content="[(500, 50, true)]",
    )
  }
}

///|
/// A readable PDF whose page 1 has an empty media box and page 2 is
/// 300 x 200.
fn pdf_import_mixed_source() -> Bytes raise {
  let document = @pdflite.pdf_document_empty()
  let key = (text : String) => @pdfcore.pdf_name_of_bytes(@utf8.encode(text))
  let root = document.add_object(PdfNull)
  let page = (w : Int, h : Int) => {
    document.add_object(
      PdfDictionary([
        (key("/Type"), PdfNameObject(key("/Page"))),
        (key("/Parent"), PdfIndirect(root)),
        (
          key("/MediaBox"),
          PdfArray([PdfInteger(0), PdfInteger(0), PdfInteger(w), PdfInteger(h)]),
        ),
      ]),
    )
  }
  let first = page(0, 0)
  let second = page(300, 200)
  document.add_object_given_number(
    root,
    PdfDictionary([
      (key("/Type"), PdfNameObject(key("/Pages"))),
      (key("/Kids"), PdfArray([PdfIndirect(first), PdfIndirect(second)])),
      (key("/Count"), PdfInteger(2)),
    ]),
  )
  ignore(document.add_root(root, []))
  @pdflite.pdf_write_document(document)
}

///|
test "a background PDF page that fails leaves another page of the PDF alone" {
  // recto takes page 1, which cannot be imported; verso page 2, which can
  let pages = pdf_import_convert(
    ":page-background-image-recto: image:mixed.pdf[page=1]\n:page-background-image-verso: image:mixed.pdf[page=2]\n\none\n\n<<<\n\ntwo\n\n<<<\n\nthree\n",
  )
  assert_eq(pages.map(p => p.2), [false, true, false])
  let warnings = conversion_warnings().filter(w => {
    w.contains("could not embed page background image: /doc/mixed.pdf;")
  })
  assert_eq(warnings.length(), 1)
}

///|
test "a page list that selects nothing never reads the file" {
  for pages in ["", ";", ","] {
    let text = "image::bad.pdf[format=pdf,pages=\"\{pages}\"]\n\nafter\n"
    assert_true(pdf_import_failure(text) is None)
    debug_inspect(
      pdf_import_convert(text),
      content=(
        #|[(595.28, 841.89, false)]
      ),
    )
  }
}

///|
test "an inline PDF image in a title that is not laid out does not warn" {
  ignore(
    pdf_import_convert(
      "= Title\n:doctype: book\n\n[%notitle]\n== Hidden image:src.pdf[]\n\ntext\n",
    ),
  )
  assert_true(
    !conversion_warnings().iter().any(w => w.contains("could not embed image")),
  )
  // laid out, it warns once, though its paragraph is measured first
  ignore(
    pdf_import_convert(
      "= Title\n:doctype: book\n\n== Shown\n\n[%unbreakable]\n--\ntext image:src.pdf[] text\n--\n",
    ),
  )
  assert_eq(
    conversion_warnings()
    .filter(w => w.contains("could not embed image"))
    .length(),
    1,
  )
}
