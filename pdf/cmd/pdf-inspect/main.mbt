///|
// pdf-inspect: the PDF-structure half of scripts/pdf_compare.mbtx.
//
//   pdf-inspect info FILE
//     JSON on stdout: version, per-page boxes, link annotations and text
//     runs (baseline origin, size, font), fonts (embedded, ToUnicode),
//     outline (titles, depth, open state, resolved targets), named
//     destinations (in name-tree order, resolved), page labels, the
//     information dictionary and the catalog's viewer settings.
//   pdf-inspect content FILE PAGE
//     The decoded content streams of page PAGE (1-based), for triage.
//   pdf-inspect fontfile FILE NAME OUT
//     Write the embedded program of the font whose name ends with NAME.
//   pdf-inspect mutate KIND IN OUT
//     Write a deliberately corrupted copy of IN (for the comparison's
//     self-test): delete-text, reorder-lines, shift-block, drop-graphics,
//     extra-page, remove-link, name-order.
//   pdf-inspect rastercmp A.ppm B.ppm DIFF.png
//     Compare two binary PPM (P6) renderings: JSON counts of differing
//     pixels at several thresholds over the full page and over the content
//     region (the bounding box of ink in either image), and a half-size
//     PNG marking the differences (red: ink only in A, blue: only in B).
//
// Coordinates in the JSON are PDF points, y measured down from the top of
// the page (as pdftotext reports them).

///|
fn name(text : String) -> @core.PdfName {
  let bytes = Array::make(text.length(), b'\x00')
  for i in 0..<text.length() {
    bytes[i] = text[i].to_int().to_byte()
  }
  @core.pdf_name_of_bytes(Bytes::from_array(bytes))
}

///|
fn latin1(bytes : Bytes) -> String {
  let sb = StringBuilder()
  for b in bytes {
    sb.write_char(b.to_int().unsafe_to_char())
  }
  sb.to_string()
}

///|
/// A PDF name without its slash.
fn name_text(n : @core.PdfName) -> String {
  let text = latin1(n.bytes())
  if text.has_prefix("/") {
    text[1:].to_owned()
  } else {
    text
  }
}

///|
/// A PDF text string: UTF-16BE behind a byte order mark, else
/// PDFDocEncoding (read as Latin-1, which it matches for printable ASCII).
fn text_string(bytes : Bytes) -> String {
  if bytes.length() >= 2 && bytes[0] == b'\xFE' && bytes[1] == b'\xFF' {
    let sb = StringBuilder()
    let mut i = 2
    while i + 1 < bytes.length() {
      let unit = (bytes[i].to_int() << 8) | bytes[i + 1].to_int()
      if unit >= 0xD800 && unit <= 0xDBFF && i + 3 < bytes.length() {
        let low = (bytes[i + 2].to_int() << 8) | bytes[i + 3].to_int()
        sb.write_char(
          (0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00)).unsafe_to_char(),
        )
        i += 4
      } else {
        sb.write_char(unit.unsafe_to_char())
        i += 2
      }
    }
    sb.to_string()
  } else {
    latin1(bytes)
  }
}

///|
/// The URI a link action opens, as the ASCII URI a conforming writer
/// stores (the rule pagelayout's PDF backend writes by): a UTF-16 text
/// string is decoded first, the bytes are taken as UTF-8, and every byte
/// outside printable ASCII, and every ASCII character RFC 3986 never allows
/// (space, `"<>\^`{|}`), is percent-encoded; a `%` beginning an escape is
/// kept, a stray one becomes `%25`. Prawn writes an IRI as raw UTF-8 (text
/// links) or as a UTF-16 text string (image links), neither of them ASCII,
/// so both sides of a comparison are brought to this form first.
fn uri_text(stored : Bytes) -> String {
  let bytes : Array[Byte] = []
  if stored.length() >= 2 && stored[0] == b'\xFE' && stored[1] == b'\xFF' {
    for c in text_string(stored) {
      let cp = c.to_int()
      if cp < 0x80 {
        bytes.push(cp.to_byte())
      } else if cp < 0x800 {
        bytes.push((0xC0 | (cp >> 6)).to_byte())
        bytes.push((0x80 | (cp & 0x3F)).to_byte())
      } else if cp < 0x10000 {
        bytes.push((0xE0 | (cp >> 12)).to_byte())
        bytes.push((0x80 | ((cp >> 6) & 0x3F)).to_byte())
        bytes.push((0x80 | (cp & 0x3F)).to_byte())
      } else {
        bytes.push((0xF0 | (cp >> 18)).to_byte())
        bytes.push((0x80 | ((cp >> 12) & 0x3F)).to_byte())
        bytes.push((0x80 | ((cp >> 6) & 0x3F)).to_byte())
        bytes.push((0x80 | (cp & 0x3F)).to_byte())
      }
    }
  } else {
    for b in stored {
      bytes.push(b)
    }
  }
  let is_hex = fn(i : Int) {
    i < bytes.length() &&
    (
      (bytes[i] >= b'0' && bytes[i] <= b'9') ||
      (bytes[i] >= b'A' && bytes[i] <= b'F') ||
      (bytes[i] >= b'a' && bytes[i] <= b'f')
    )
  }
  let hex = "0123456789ABCDEF"
  let sb = StringBuilder()
  for i, b in bytes {
    let keep = match b {
      b'%' => is_hex(i + 1) && is_hex(i + 2)
      b'"' | b'<' | b'>' | b'\\' | b'^' | b'`' | b'{' | b'|' | b'}' => false
      _ => b > b' ' && b < b'\x7F'
    }
    if keep {
      sb.write_char(b.to_int().unsafe_to_char())
    } else {
      sb.write_char('%')
      sb.write_char(hex[b.to_int() >> 4].unsafe_to_char())
      sb.write_char(hex[b.to_int() & 0xF].unsafe_to_char())
    }
  }
  sb.to_string()
}

///|
priv struct Inspector {
  doc : @pdflite.PdfDocument
  /// page object number to page index
  page_index : Map[Int, Int]
  /// page heights (top of the media box), by index
  tops : Array[Double]
  /// named destinations, in name-tree order
  dest_names : Array[String]
  dests : Map[String, @syntax.PdfObject]
}

///|
fn Inspector::direct(
  self : Inspector,
  obj : @syntax.PdfObject,
) -> @syntax.PdfObject {
  self.doc.direct(obj)
}

///|
fn Inspector::get(
  self : Inspector,
  dict : @syntax.PdfObject,
  key : String,
) -> @syntax.PdfObject? {
  match self.direct(dict) {
    PdfDictionary(_) as d => self.doc.lookup_direct(name(key), d)
    PdfStreamObject(s) => self.doc.lookup_direct(name(key), s.dictionary)
    _ => None
  }
}

///|
fn number(obj : @syntax.PdfObject?) -> Double? {
  match obj {
    Some(PdfInteger(i)) => Some(i.to_double())
    Some(PdfReal(r)) => Some(r)
    _ => None
  }
}

///|
fn Inspector::numbers(
  self : Inspector,
  obj : @syntax.PdfObject?,
) -> Array[Double] {
  match obj.map(o => self.direct(o)) {
    Some(PdfArray(items)) =>
      items.map(item => number(Some(self.direct(item))).unwrap_or(0.0))
    _ => []
  }
}

///|
/// Walk a name tree in order, collecting its leaves' keys and values.
fn Inspector::walk_name_tree(
  self : Inspector,
  node : @syntax.PdfObject,
  out : Array[(String, @syntax.PdfObject)],
  depth : Int,
) -> Unit {
  if depth > 32 {
    return
  }
  match self.get(node, "/Names") {
    Some(PdfArray(items)) => {
      let mut i = 0
      while i + 1 < items.length() {
        match self.direct(items[i]) {
          PdfString(key) => out.push((latin1(key), items[i + 1]))
          _ => ()
        }
        i += 2
      }
    }
    _ => ()
  }
  match self.get(node, "/Kids") {
    Some(PdfArray(kids)) =>
      for kid in kids {
        self.walk_name_tree(kid, out, depth + 1)
      }
    _ => ()
  }
}

///|
/// A destination resolved to a page: named ones through the name tree.
fn Inspector::resolve_dest(
  self : Inspector,
  dest : @syntax.PdfObject,
  depth? : Int = 0,
) -> Json {
  if depth > 8 {
    return Json::null()
  }
  match self.direct(dest) {
    PdfString(key) =>
      match self.dests.get(latin1(key)) {
        Some(target) => {
          let resolved = self.resolve_dest(target, depth=depth + 1)
          match resolved {
            Object(map) => {
              map["name"] = Json::string(latin1(key))
              resolved
            }
            _ => { "name": latin1(key), "missing": true }
          }
        }
        None => { "name": latin1(key), "missing": true }
      }
    PdfNameObject(n) =>
      self.resolve_dest(PdfString(n.bytes()[1:].to_owned()), depth=depth + 1)
    PdfDictionary(_) as d =>
      match self.doc.lookup_direct(name("/D"), d) {
        Some(inner) => self.resolve_dest(inner, depth=depth + 1)
        None => Json::null()
      }
    PdfArray(items) if items.length() >= 2 => {
      let page = match items[0] {
        PdfIndirect(number) => self.page_index.get(number).unwrap_or(-1)
        PdfInteger(i) => i
        _ => -1
      }
      let kind = match self.direct(items[1]) {
        PdfNameObject(n) => name_text(n)
        _ => "?"
      }
      let top = if page >= 0 && page < self.tops.length() {
        self.tops[page]
      } else {
        0.0
      }
      let args = items[2:]
        .iter()
        .map(item => number(Some(self.direct(item))))
        .collect()
      // the destination's top edge, for the kinds that have one
      let y : Double? = match kind {
        "XYZ" => args.get(1).unwrap_or(None)
        "FitH" | "FitBH" => args.get(0).unwrap_or(None)
        "FitR" => args.get(3).unwrap_or(None)
        _ => None
      }
      let x : Double? = match kind {
        "XYZ" | "FitV" | "FitBV" | "FitR" => args.get(0).unwrap_or(None)
        _ => None
      }
      {
        "page": page.to_double(),
        "kind": kind,
        "x": match x {
          Some(v) => Json::number(v)
          None => Json::null()
        },
        "y": match y {
          Some(v) => Json::number(top - v)
          None => Json::null()
        },
      }
    }
    _ => Json::null()
  }
}

///|
fn Inspector::action_target(self : Inspector, dict : @syntax.PdfObject) -> Json {
  match self.get(dict, "/Dest") {
    Some(dest) => { "dest": self.resolve_dest(dest) }
    None =>
      match self.get(dict, "/A") {
        Some(action) => {
          let kind = match self.get(action, "/S") {
            Some(PdfNameObject(n)) => name_text(n)
            _ => "?"
          }
          match kind {
            "URI" =>
              match self.get(action, "/URI") {
                Some(PdfString(uri)) => { "uri": uri_text(uri) }
                _ => { "uri": "" }
              }
            "GoTo" =>
              match self.get(action, "/D") {
                Some(dest) => { "dest": self.resolve_dest(dest) }
                None => { "action": "GoTo" }
              }
            other => { "action": other }
          }
        }
        None => Json::null()
      }
  }
}

///|
fn Inspector::outline(
  self : Inspector,
  first : @syntax.PdfObject?,
  depth : Int,
  out : Array[Json],
) -> Unit {
  let mut item = first
  let mut guard_count = 0
  while item is Some(node) && guard_count < 100000 {
    guard_count += 1
    let title = match self.get(node, "/Title") {
      Some(PdfString(t)) => text_string(t)
      _ => ""
    }
    let count = number(self.get(node, "/Count").map(o => self.direct(o)))
    let children = self.get(node, "/First")
    out.push({
      "depth": depth.to_double(),
      "title": title,
      "count": match count {
        Some(c) => Json::number(c)
        None => Json::null()
      },
      "has_children": children is Some(_),
      "open": match count {
        Some(c) => c > 0.0
        None => false
      },
      "target": self.action_target(node),
    })
    if depth < 64 {
      self.outline(children, depth + 1, out)
    }
    item = match node {
      PdfIndirect(_) | PdfDictionary(_) => self.get(node, "/Next")
      _ => None
    }
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
  for i, v in values {
    while rest >= v {
      sb.write_string(symbols[i])
      rest -= v
    }
  }
  if upper {
    sb.to_string().to_upper()
  } else {
    sb.to_string()
  }
}

///|
fn letters(n : Int, upper : Bool) -> String {
  if n <= 0 {
    return ""
  }
  let base = if upper { 'A' } else { 'a' }
  let letter = (base.to_int() + (n - 1) % 26).unsafe_to_char()
  letter.to_string().repeat((n - 1) / 26 + 1)
}

///|
/// Effective page labels (PDF 32000-1 §12.4.2); decimal 1..n without
/// /PageLabels.
fn Inspector::page_labels(
  self : Inspector,
  catalog : @syntax.PdfObject,
) -> Array[String] {
  let count = self.tops.length()
  let labels = Array::makei(count, i => (i + 1).to_string())
  guard self.get(catalog, "/PageLabels") is Some(tree) else { return labels }
  let ranges = self.doc.read_number_tree(tree)
  for i in 0..<count {
    let mut found : (Int, @syntax.PdfObject)? = None
    for range in ranges {
      if range.0 <= i {
        found = Some(range)
      }
    }
    guard found is Some((start, dict)) else { continue }
    let prefix = match self.get(dict, "/P") {
      Some(PdfString(p)) => text_string(p)
      _ => ""
    }
    let first = number(self.get(dict, "/St")).unwrap_or(1.0).to_int()
    let n = first + i - start
    let body = match self.get(dict, "/S") {
      Some(PdfNameObject(s)) =>
        match name_text(s) {
          "D" => n.to_string()
          "R" => roman(n, true)
          "r" => roman(n, false)
          "A" => letters(n, true)
          "a" => letters(n, false)
          _ => ""
        }
      _ => ""
    }
    labels[i] = prefix + body
  }
  labels
}

///|
priv struct Matrix {
  a : Double
  b : Double
  c : Double
  d : Double
  e : Double
  f : Double
}

///|
let identity : Matrix = { a: 1.0, b: 0.0, c: 0.0, d: 1.0, e: 0.0, f: 0.0, }

///|
/// `m × n`: apply m, then n.
fn mul(m : Matrix, n : Matrix) -> Matrix {
  {
    a: m.a * n.a + m.b * n.c,
    b: m.a * n.b + m.b * n.d,
    c: m.c * n.a + m.d * n.c,
    d: m.c * n.b + m.d * n.d,
    e: m.e * n.a + m.f * n.c + n.e,
    f: m.e * n.b + m.f * n.d + n.f,
  }
}

///|
fn of_transform(t : @geometry.TransformMatrix) -> Matrix {
  { a: t.a, b: t.b, c: t.c, d: t.d, e: t.e, f: t.f, }
}

///|
/// The decoded, concatenated content streams of a page.
fn Inspector::content_bytes(self : Inspector, page : @page.PdfPage) -> Bytes {
  let buffer = Buffer()
  for entry in page.content {
    match self.direct(entry) {
      PdfStreamObject(_) as stream => {
        let bytes = stream.stream_bytes() catch { _ => b"" }
        buffer.write_bytes(bytes)
        buffer.write_byte(b'\n')
      }
      _ => ()
    }
  }
  buffer.to_bytes()
}

///|
/// The origin of every text-showing operator: where its first glyph's
/// baseline starts, its effective size and its font.
fn Inspector::text_runs(
  self : Inspector,
  page : @page.PdfPage,
  top : Double,
) -> Array[Json] {
  let runs : Array[Json] = []
  let ops = @pdflite.pdf_parse_content_ops_from_bytes(self.content_bytes(page)) catch {
    _ => return runs
  }
  let fonts : Map[String, String] = Map([])
  match self.get(page.resources, "/Font") {
    Some(PdfDictionary(entries)) =>
      for entry in entries {
        let base = match self.get(entry.1, "/BaseFont") {
          Some(PdfNameObject(n)) => name_text(n)
          _ => "?"
        }
        fonts[name_text(entry.0)] = base
      }
    _ => ()
  }
  let stack : Array[Matrix] = []
  let mut ctm = identity
  let mut tm = identity
  let mut tlm = identity
  let mut leading = 0.0
  let mut rise = 0.0
  let mut font = "?"
  let mut size = 0.0
  let show = fn() {
    let m = mul(tm, ctm)
    let x = m.c * rise + m.e
    let y = m.d * rise + m.f
    let scale = (m.c * m.c + m.d * m.d).sqrt()
    runs.push(
      ({ "x": x, "y": top - y, "size": size * scale, "font": font } : Json),
    )
  }
  for op in ops {
    match op {
      Op_q => stack.push(ctm)
      Op_Q => ctm = stack.pop().unwrap_or(identity)
      Op_cm(t) => ctm = mul(of_transform(t), ctm)
      Op_BT => {
        tm = identity
        tlm = identity
      }
      Op_Tf(n, s) => {
        font = fonts.get(name_text(n)).unwrap_or(name_text(n))
        size = s
      }
      Op_TL(l) => leading = l
      Op_Ts(r) => rise = r
      Op_Td(tx, ty) => {
        tlm = mul({ ..identity, e: tx, f: ty, }, tlm)
        tm = tlm
      }
      Op_TD(tx, ty) => {
        leading = -ty
        tlm = mul({ ..identity, e: tx, f: ty, }, tlm)
        tm = tlm
      }
      Op_Tm(t) => {
        tlm = of_transform(t)
        tm = tlm
      }
      Op_Tstar => {
        tlm = mul({ ..identity, f: -leading, }, tlm)
        tm = tlm
      }
      Op_Tj(_) | Op_TJ(_) => show()
      Op_quote(_) | Op_double_quote(_, _, _) => {
        tlm = mul({ ..identity, f: -leading, }, tlm)
        tm = tlm
        show()
      }
      _ => ()
    }
  }
  runs
}

///|
fn Inspector::new(doc : @pdflite.PdfDocument) -> Inspector raise {
  let numbers = doc.page_reference_numbers()
  let page_index : Map[Int, Int] = Map([])
  for i, n in numbers {
    page_index[n] = i
  }
  let pages = doc.pages_of_pagetree()
  let self : Inspector = {
    doc,
    page_index,
    tops: [],
    dest_names: [],
    dests: Map([]),
  }
  for page in pages {
    let box = self.numbers(Some(page.mediabox))
    self.tops.push(box.get(3).unwrap_or(0.0))
  }
  let catalog = doc.catalog()
  // named destinations: the /Names /Dests tree, or a PDF 1.1 /Dests dict
  let entries = []
  match self.get(catalog, "/Names") {
    Some(names) =>
      match self.get(names, "/Dests") {
        Some(tree) => self.walk_name_tree(tree, entries, 0)
        None => ()
      }
    None => ()
  }
  match self.get(catalog, "/Dests") {
    Some(PdfDictionary(items)) =>
      for item in items {
        entries.push((name_text(item.0), item.1))
      }
    _ => ()
  }
  for entry in entries {
    self.dest_names.push(entry.0)
    if !self.dests.contains(entry.0) {
      self.dests[entry.0] = entry.1
    }
  }
  self
}

///|
/// Byte-wise lexical order of two keys (every char here is one byte).
fn lexical_le(a : String, b : String) -> Bool {
  let n = if a.length() < b.length() { a.length() } else { b.length() }
  for i in 0..<n {
    if a[i] != b[i] {
      return a[i] < b[i]
    }
  }
  a.length() <= b.length()
}

///|
fn Inspector::fonts(self : Inspector) -> Array[Json] raise {
  let out : Array[Json] = []
  self.doc.iter_objects_in_order((_, obj) => {
    guard obj is PdfDictionary(_) else { return }
    guard self.get(obj, "/Type") is Some(PdfNameObject(t)) &&
      name_text(t) == "Font" else {
      return
    }
    let subtype = match self.get(obj, "/Subtype") {
      Some(PdfNameObject(n)) => name_text(n)
      _ => "?"
    }
    // descendants are described through their Type0 parent
    if subtype == "CIDFontType0" || subtype == "CIDFontType2" {
      return
    }
    let base = match self.get(obj, "/BaseFont") {
      Some(PdfNameObject(n)) => name_text(n)
      _ => ""
    }
    let encoding = match self.get(obj, "/Encoding") {
      Some(PdfNameObject(n)) => name_text(n)
      Some(PdfDictionary(_)) => "custom"
      _ => ""
    }
    let descriptor = if subtype == "Type0" {
      match self.get(obj, "/DescendantFonts") {
        Some(PdfArray(kids)) if kids.length() > 0 =>
          self.get(kids[0], "/FontDescriptor")
        _ => None
      }
    } else {
      self.get(obj, "/FontDescriptor")
    }
    let embedded = match descriptor {
      Some(d) =>
        self.get(d, "/FontFile") is Some(_) ||
        self.get(d, "/FontFile2") is Some(_) ||
        self.get(d, "/FontFile3") is Some(_)
      None => false
    }
    let ascent = number(descriptor.bind(d => self.get(d, "/Ascent")))
    let descent = number(descriptor.bind(d => self.get(d, "/Descent")))
    // a subset tag is six uppercase letters and a plus
    let (tag, family) = match base.find("+") {
      Some(6) => (base[:6].to_owned(), base[7:].to_owned())
      _ => ("", base)
    }
    out.push({
      "name": base,
      "family": family,
      "subset_tag": tag,
      "subtype": subtype,
      "encoding": encoding,
      "embedded": embedded,
      "tounicode": self.get(obj, "/ToUnicode") is Some(_),
      "ascent": match ascent {
        Some(v) => Json::number(v)
        None => Json::null()
      },
      "descent": match descent {
        Some(v) => Json::number(v)
        None => Json::null()
      },
    })
  })
  out
}

///|
/// The embedded font program (FontFile, FontFile2 or FontFile3) of the
/// font whose BaseFont ends with `name`.
fn Inspector::font_file(self : Inspector, name : String) -> Bytes? raise {
  let mut found : Bytes? = None
  self.doc.iter_objects_in_order((_, obj) => {
    guard found is None && obj is PdfDictionary(_) else { return }
    guard self.get(obj, "/Type") is Some(PdfNameObject(t)) &&
      name_text(t) == "FontDescriptor" else {
      return
    }
    guard self.get(obj, "/FontName") is Some(PdfNameObject(n)) &&
      name_text(n).has_suffix(name) else {
      return
    }
    for key in ["/FontFile", "/FontFile2", "/FontFile3"] {
      match self.get(obj, key) {
        Some(PdfStreamObject(_) as stream) => {
          found = Some(stream.stream_bytes() catch { _ => b"" })
          return
        }
        _ => ()
      }
    }
  })
  found
}

///|
fn box_json(values : Array[Double]) -> Json {
  if values.length() == 4 {
    Json::array(values.map(v => Json::number(v)))
  } else {
    Json::null()
  }
}

///|
fn Inspector::info(self : Inspector) -> Json raise {
  let doc = self.doc
  let catalog = doc.catalog()
  let pages = doc.pages_of_pagetree()
  let numbers = doc.page_reference_numbers()
  let page_json : Array[Json] = []
  for i, page in pages {
    let raw = doc.lookup_object_or_null(numbers[i])
    let media = self.numbers(Some(page.mediabox))
    let explicit : Map[String, Json] = Map([])
    for key in ["MediaBox", "CropBox", "BleedBox", "TrimBox", "ArtBox"] {
      match raw.lookup_immediate(name("/" + key)) {
        Some(value) => explicit[key] = box_json(self.numbers(Some(value)))
        None => ()
      }
    }
    // effective boxes: crop defaults to the media box, the rest to crop
    let crop = match raw.lookup_immediate(name("/CropBox")) {
      Some(value) => self.numbers(Some(value))
      None => media
    }
    let effective : Map[String, Json] = {
      "MediaBox": box_json(media),
      "CropBox": box_json(crop),
    }
    for key in ["BleedBox", "TrimBox", "ArtBox"] {
      effective[key] = match raw.lookup_immediate(name("/" + key)) {
        Some(value) => box_json(self.numbers(Some(value)))
        None => box_json(crop)
      }
    }
    let annots : Array[Json] = []
    match self.get(raw, "/Annots") {
      Some(PdfArray(items)) =>
        for item in items {
          let subtype = match self.get(item, "/Subtype") {
            Some(PdfNameObject(n)) => name_text(n)
            _ => "?"
          }
          let rect = self.numbers(self.get(item, "/Rect"))
          let top = self.tops[i]
          // x0, y0 (top), x1, y1 (bottom), top-down
          let r = if rect.length() == 4 {
            let y0 = if rect[1] < rect[3] { rect[3] } else { rect[1] }
            let y1 = if rect[1] < rect[3] { rect[1] } else { rect[3] }
            [rect[0], top - y0, rect[2], top - y1].map(v => Json::number(v))
          } else {
            []
          }
          annots.push({
            "subtype": subtype,
            "rect": Json::array(r),
            "target": self.action_target(item),
          })
        }
      _ => ()
    }
    let rotate = @page.pdf_page_int_of_rotation(page.rotate)
    page_json.push({
      "explicit_boxes": Json::object(explicit),
      "boxes": Json::object(effective),
      "rotate": rotate.to_double(),
      "annots": Json::array(annots),
      "runs": Json::array(self.text_runs(page, self.tops[i])),
    })
  }
  let outline : Array[Json] = []
  match self.get(catalog, "/Outlines") {
    Some(root) => self.outline(self.get(root, "/First"), 0, outline)
    None => ()
  }
  let outline_count = match self.get(catalog, "/Outlines") {
    Some(root) => number(self.get(root, "/Count"))
    None => None
  }
  let mut sorted = true
  for i in 1..<self.dest_names.length() {
    if !lexical_le(self.dest_names[i - 1], self.dest_names[i]) {
      sorted = false
    }
  }
  let dests = self.dest_names.map(key => {
    let resolved = self.resolve_dest(
      PdfString(
        Bytes::from_array(key.iter().map(c => c.to_int().to_byte()).collect()),
      ),
    )
    resolved
  })
  let info : Map[String, Json] = Map([])
  match self.get(doc.trailer_dict(), "/Info") {
    Some(PdfDictionary(entries)) =>
      for entry in entries {
        match self.direct(entry.1) {
          PdfString(s) =>
            info[name_text(entry.0)] = Json::string(text_string(s))
          PdfNameObject(n) =>
            info[name_text(entry.0)] = Json::string(name_text(n))
          _ => ()
        }
      }
    _ => ()
  }
  let page_mode = match self.get(catalog, "/PageMode") {
    Some(PdfNameObject(n)) => Json::string(name_text(n))
    _ => Json::null()
  }
  let open_action = match self.get(catalog, "/OpenAction") {
    Some(PdfArray(_) as dest) => self.resolve_dest(dest)
    Some(action) => self.action_target(action)
    None => Json::null()
  }
  let display_doc_title = match self.get(catalog, "/ViewerPreferences") {
    Some(prefs) => self.get(prefs, "/DisplayDocTitle") is Some(PdfBoolean(true))
    None => false
  }
  let (major, minor) = doc.version()
  {
    "version": "\{major}.\{minor}",
    "pages": Json::array(page_json),
    "fonts": Json::array(self.fonts()),
    "outline": Json::array(outline),
    "outline_count": match outline_count {
      Some(c) => Json::number(c)
      None => Json::null()
    },
    "dest_names": Json::array(self.dest_names.map(n => Json::string(n))),
    "dests": Json::array(dests),
    "dests_sorted": sorted,
    "page_labels": Json::array(
      self.page_labels(catalog).map(l => Json::string(l)),
    ),
    "info": Json::object(info),
    "page_mode": page_mode,
    "open_action": open_action,
    "display_doc_title": display_doc_title,
  }
}

// ---------------------------------------------------------------------------
// Mutations

///|
/// A text object: the index of its BT and ET, and its baseline (the `f` of
/// its last Tm or Td, which is how pagelayout positions every run).
priv struct TextObject {
  start : Int
  stop : Int
  y : Double
}

///|
fn text_objects(ops : Array[@content.PdfContentOp]) -> Array[TextObject] {
  let out : Array[TextObject] = []
  let mut start = -1
  let mut y = 0.0
  for i, op in ops {
    match op {
      Op_BT => start = i
      Op_Tm(t) => y = t.f
      Op_Td(_, ty) => y = ty
      Op_ET =>
        if start >= 0 {
          out.push({ start, stop: i, y, })
          start = -1
        }
      _ => ()
    }
  }
  out
}

///|
/// The distinct baselines of a page's text objects, top first.
fn baselines(objects : Array[TextObject]) -> Array[Double] {
  let ys : Array[Double] = []
  for o in objects {
    if !ys.iter().any(y => (y - o.y).abs() < 0.01) {
      ys.push(o.y)
    }
  }
  ys.sort_by((a, b) => b.compare(a))
  ys
}

///|
fn with_text_position(
  op : @content.PdfContentOp,
  dx : Double,
  y : Double?,
) -> @content.PdfContentOp {
  match op {
    Op_Tm(t) => Op_Tm({ ..t, e: t.e + dx, f: y.unwrap_or(t.f), })
    Op_Td(tx, ty) => Op_Td(tx + dx, y.unwrap_or(ty))
    other => other
  }
}

///|
fn Inspector::page_ops(
  self : Inspector,
  page : @page.PdfPage,
) -> Array[@content.PdfContentOp] raise {
  @pdflite.pdf_parse_content_ops_from_bytes(self.content_bytes(page))
}

///|
fn mutate(bytes : Bytes, kind : String) -> Bytes raise {
  let doc = @pdflite.pdf_decompress_pdf(
    @pdflite.pdf_read_document_from_bytes(bytes),
  )
  let self = Inspector::new(doc)
  let pages = doc.pages_of_pagetree()
  let set_ops = fn(index : Int, ops : Array[@content.PdfContentOp]) raise {
    pages[index] = {
      ..pages[index],
      content: [@pdflite.pdf_content_stream_of_ops(ops)],
    }
  }
  match kind {
    "delete-text" | "reorder-lines" | "shift-block" => {
      let ops = self.page_ops(pages[0])
      let objects = text_objects(ops)
      let lines = baselines(objects)
      if lines.length() < 4 {
        fail("page 1 has too few lines to mutate")
      }
      let middle = lines[lines.length() / 2]
      let next = lines[lines.length() / 2 + 1]
      let out : Array[@content.PdfContentOp] = []
      // op index → replacement decision
      let owner = Array::make(ops.length(), -1)
      for index, o in objects {
        for i in o.start..<=o.stop {
          owner[i] = index
        }
      }
      for i, op in ops {
        let index = owner[i]
        if index < 0 {
          out.push(op)
          continue
        }
        let o = objects[index]
        match kind {
          // the middle line of page 1 disappears
          "delete-text" => if (o.y - middle).abs() >= 0.01 { out.push(op) }
          // the middle line and the one below it change places
          "reorder-lines" =>
            if (o.y - middle).abs() < 0.01 {
              out.push(with_text_position(op, 0.0, Some(next)))
            } else if (o.y - next).abs() < 0.01 {
              out.push(with_text_position(op, 0.0, Some(middle)))
            } else {
              out.push(op)
            }
          // every line from the middle down moves 5pt to the right
          _ =>
            if o.y <= middle + 0.01 {
              out.push(with_text_position(op, 5.0, None))
            } else {
              out.push(op)
            }
        }
      }
      set_ops(0, out)
    }
    // every filled or stroked path disappears (backgrounds, borders,
    // rules), the text stays where it was
    "drop-graphics" =>
      for index, page in pages {
        let ops = self
          .page_ops(page)
          .map(op => {
            match op {
              Op_S
              | Op_s
              | Op_f
              | Op_F
              | Op_fstar
              | Op_B
              | Op_Bstar
              | Op_b
              | Op_bstar => @content.PdfContentOp::Op_n
              other => other
            }
          })
        set_ops(index, ops)
      }
    "extra-page" => {
      let last = pages[pages.length() - 1]
      pages.push({
        content: [],
        mediabox: last.mediabox,
        resources: PdfDictionary([]),
        rotate: last.rotate,
        rest: PdfDictionary([]),
      })
    }
    "remove-link" => {
      let mut done = false
      for i, page in pages {
        if done {
          break
        }
        match page.rest.lookup_immediate(name("/Annots")) {
          Some(annots) =>
            match self.direct(annots) {
              PdfArray(items) if items.length() > 0 => {
                let rest = page.rest.replace_dict_entry(
                  name("/Annots"),
                  PdfArray(items[1:].to_owned()),
                )
                pages[i] = { ..page, rest, }
                done = true
              }
              _ => ()
            }
          None => ()
        }
      }
      if !done {
        fail("no link annotation to remove")
      }
    }
    "name-order" => {
      let catalog = doc.catalog()
      guard self.get(catalog, "/Names") is Some(names) else {
        fail("no /Names")
      }
      let dests_ref = match self.direct(names) {
        PdfDictionary(_) as d => d.lookup_immediate(name("/Dests"))
        _ => None
      }
      guard dests_ref is Some(PdfIndirect(number)) else {
        fail("/Dests is not an indirect leaf")
      }
      let leaf = doc.lookup_object_or_null(number)
      guard leaf.lookup_immediate(name("/Names")) is Some(PdfArray(items)) else {
        fail("/Dests has no /Names")
      }
      // pairs in reverse order: every adjacent pair is now out of order
      let reversed : Array[@syntax.PdfObject] = []
      let mut i = items.length() - 2
      while i >= 0 {
        reversed.push(items[i])
        reversed.push(items[i + 1])
        i -= 2
      }
      doc.add_object_given_number(
        number,
        leaf.replace_dict_entry(name("/Names"), PdfArray(reversed)),
      )
      return @pdflite.pdf_write_document(doc)
    }
    other => fail("unknown mutation \{other}")
  }
  @pdflite.pdf_write_document(doc.change_pages(pages, change_references=true))
}

// ---------------------------------------------------------------------------
// Raster comparison

///|
priv struct Image {
  width : Int
  height : Int
  data : Bytes
  offset : Int
}

///|
/// A binary PPM (P6, maxval 255).
fn read_ppm(data : Bytes) -> Image raise {
  let fields = []
  let mut i = 0
  while fields.length() < 4 && i < data.length() {
    // whitespace and comments
    while i < data.length() &&
          (
            data[i] == b' ' ||
            data[i] == b'\n' ||
            data[i] == b'\r' ||
            data[i] == b'\t' ||
            data[i] == b'#'
          ) {
      if data[i] == b'#' {
        while i < data.length() && data[i] != b'\n' {
          i += 1
        }
      } else {
        i += 1
      }
    }
    let start = i
    while i < data.length() &&
          data[i] != b' ' &&
          data[i] != b'\n' &&
          data[i] != b'\r' &&
          data[i] != b'\t' {
      i += 1
    }
    fields.push(latin1(data[start:i].to_owned()))
  }
  if fields.length() < 4 || fields[0] != "P6" {
    fail("not a binary PPM")
  }
  let width = @string.parse_int(fields[1])
  let height = @string.parse_int(fields[2])
  let offset = i + 1
  if offset + width * height * 3 > data.length() {
    fail("truncated PPM")
  }
  { width, height, data, offset, }
}

///|
let crc_table : FixedArray[UInt] = {
  let table = FixedArray::make(256, 0U)
  for n in 0..<256 {
    let mut c = n.reinterpret_as_uint()
    for _ in 0..<8 {
      c = if (c & 1U) != 0U { 0xEDB88320U ^ (c >> 1) } else { c >> 1 }
    }
    table[n] = c
  }
  table
}

///|
fn crc32(data : Bytes) -> UInt {
  let mut c = 0xFFFFFFFFU
  for b in data {
    c = crc_table[((c ^ b.to_uint()) & 0xFFU).reinterpret_as_int()] ^ (c >> 8)
  }
  c ^ 0xFFFFFFFFU
}

///|
fn write_u32(buffer : Buffer, value : UInt) -> Unit {
  buffer.write_byte((value >> 24).to_byte())
  buffer.write_byte(((value >> 16) & 0xFFU).to_byte())
  buffer.write_byte(((value >> 8) & 0xFFU).to_byte())
  buffer.write_byte((value & 0xFFU).to_byte())
}

///|
fn png_chunk(out : Buffer, kind : String, data : Bytes) -> Unit {
  write_u32(out, data.length().reinterpret_as_uint())
  let body = Buffer()
  for c in kind {
    body.write_byte(c.to_int().to_byte())
  }
  body.write_bytes(data)
  let bytes = body.to_bytes()
  out.write_bytes(bytes)
  write_u32(out, crc32(bytes))
}

///|
/// An 8-bit RGB PNG of `rgb` (width × height × 3 bytes).
fn encode_png(width : Int, height : Int, rgb : FixedArray[Byte]) -> Bytes {
  let raw = Buffer()
  for y in 0..<height {
    raw.write_byte(b'\x00')
    for x in 0..<(width * 3) {
      raw.write_byte(rgb[y * width * 3 + x])
    }
  }
  let header = Buffer()
  write_u32(header, width.reinterpret_as_uint())
  write_u32(header, height.reinterpret_as_uint())
  header.write_bytes(b"\x08\x02\x00\x00\x00")
  let out = Buffer()
  out.write_bytes(b"\x89PNG\r\n\x1a\n")
  png_chunk(out, "IHDR", header.to_bytes())
  png_chunk(out, "IDAT", @flate.pdf_flate_encode(raw.to_bytes()))
  png_chunk(out, "IEND", b"")
  out.to_bytes()
}

///|
let thresholds : Array[Int] = [16, 64, 128]

///|
/// Differing pixels between two renderings, and the difference image.
fn raster_compare(a : Image, b : Image) -> (Json, Bytes) {
  if a.width != b.width || a.height != b.height {
    return ({ "size_mismatch": true }, b"")
  }
  let w = a.width
  let h = a.height
  let counts = Array::make(thresholds.length(), 0)
  let mut x0 = w
  let mut y0 = h
  let mut x1 = -1
  let mut y1 = -1
  let dw = (w + 1) / 2
  let dh = (h + 1) / 2
  let diff = FixedArray::make(dw * dh * 3, b'\xFF')
  let mut flat = 0
  // half-size background: a faded copy of A
  for y in 0..<h {
    for x in 0..<w {
      let p = (y * w + x) * 3
      let mut ink = false
      let mut delta = 0
      let mut dark_a = 0
      let mut dark_b = 0
      for ch in 0..<3 {
        let va = a.data[a.offset + p + ch].to_int()
        let vb = b.data[b.offset + p + ch].to_int()
        if va < 250 || vb < 250 {
          ink = true
        }
        let d = (va - vb).abs()
        if d > delta {
          delta = d
        }
        dark_a += 255 - va
        dark_b += 255 - vb
      }
      if ink {
        if x < x0 {
          x0 = x
        }
        if x > x1 {
          x1 = x
        }
        if y < y0 {
          y0 = y
        }
        if y > y1 {
          y1 = y
        }
      }
      for t, threshold in thresholds {
        if delta > threshold {
          counts[t] += 1
        }
      }
      // a faint difference where both renderings are flat (no glyph or
      // rule edge nearby): a missing or recoloured fill, which the
      // thresholds above cannot see, and which anti-aliasing never causes
      let flat_difference = delta > flat_threshold &&
        is_flat(a, x, y) &&
        is_flat(b, x, y)
      if flat_difference {
        flat += 1
      }
      let q = (y / 2 * dw + x / 2) * 3
      if flat_difference && delta <= 64 {
        diff[q] = b'\xE8'
        diff[q + 1] = b'\x90'
        diff[q + 2] = b'\x00'
      } else if delta > 64 {
        if dark_a >= dark_b {
          diff[q] = b'\xDC'
          diff[q + 1] = b'\x00'
          diff[q + 2] = b'\x00'
        } else {
          diff[q] = b'\x00'
          diff[q + 1] = b'\x40'
          diff[q + 2] = b'\xE0'
        }
      } else if diff[q] == b'\xFF' && diff[q + 1] == b'\xFF' && dark_a > 0 {
        // faded ink of A, unless the cell is already marked
        let v = 255 - dark_a / 3 / 4
        let g = v.to_byte()
        diff[q] = g
        diff[q + 1] = g
        diff[q + 2] = g
      }
    }
  }
  let area = w * h
  let content = if x1 >= x0 && y1 >= y0 {
    (x1 - x0 + 1) * (y1 - y0 + 1)
  } else {
    0
  }
  let by_threshold = []
  for t, threshold in thresholds {
    by_threshold.push(
      (
        { "threshold": threshold.to_double(), "pixels": counts[t].to_double() } :
        Json),
    )
  }
  (
    {
      "width": w.to_double(),
      "height": h.to_double(),
      "area": area.to_double(),
      "content_area": content.to_double(),
      "content_box": if content > 0 {
        Json::array([x0, y0, x1, y1].map(v => Json::number(v.to_double())))
      } else {
        Json::null()
      },
      "counts": Json::array(by_threshold),
      "flat_threshold": flat_threshold.to_double(),
      "flat_pixels": flat.to_double(),
    },
    encode_png(dw, dh, diff),
  )
}

///|
/// Differences above this many levels count where both images are flat.
let flat_threshold : Int = 6

///|
/// Whether the 3×3 neighbourhood of (x, y) is uniform: every channel of
/// every neighbour within 2 levels of the centre.
fn is_flat(img : Image, x : Int, y : Int) -> Bool {
  let center = img.offset + (y * img.width + x) * 3
  for dy in -1..<=1 {
    let yy = y + dy
    if yy < 0 || yy >= img.height {
      continue
    }
    for dx in -1..<=1 {
      let xx = x + dx
      if xx < 0 || xx >= img.width {
        continue
      }
      let p = img.offset + (yy * img.width + xx) * 3
      for ch in 0..<3 {
        if (img.data[p + ch].to_int() - img.data[center + ch].to_int()).abs() >
          2 {
          return false
        }
      }
    }
  }
  true
}

///|
fn usage() -> String {
  "usage: pdf-inspect info FILE | content FILE PAGE | fontfile FILE NAME OUT | mutate KIND IN OUT | rastercmp A.ppm B.ppm DIFF.png"
}

///|
async fn main {
  let args = @env.args()
  let command = args.get(1).unwrap_or("")
  match command {
    "info" if args.length() == 3 => {
      let bytes = @fs.read_file(args[2]).binary()
      let doc = @pdflite.pdf_decompress_pdf(
        @pdflite.pdf_read_document_from_bytes(bytes),
      )
      let json = Inspector::new(doc).info()
      @stdio.stdout.write(json.stringify() + "\n")
    }
    "content" if args.length() == 4 => {
      let bytes = @fs.read_file(args[2]).binary()
      let doc = @pdflite.pdf_decompress_pdf(
        @pdflite.pdf_read_document_from_bytes(bytes),
      )
      let inspector = Inspector::new(doc)
      let index = @string.parse_int(args[3]) - 1
      guard doc.pages_of_pagetree().get(index) is Some(page) else {
        fail("no page \{args[3]}")
      }
      @stdio.stdout.write(latin1(inspector.content_bytes(page)))
    }
    "fontfile" if args.length() == 5 => {
      let bytes = @fs.read_file(args[2]).binary()
      let doc = @pdflite.pdf_decompress_pdf(
        @pdflite.pdf_read_document_from_bytes(bytes),
      )
      guard Inspector::new(doc).font_file(args[3]) is Some(font) else {
        fail("no embedded font \{args[3]}")
      }
      @fs.write_file(args[4], font, create_mode=CreateOrTruncate)
    }
    "mutate" if args.length() == 5 => {
      let bytes = @fs.read_file(args[3]).binary()
      @fs.write_file(
        args[4],
        mutate(bytes, args[2]),
        create_mode=CreateOrTruncate,
      )
    }
    "rastercmp" if args.length() == 5 => {
      let a = read_ppm(@fs.read_file(args[2]).binary())
      let b = read_ppm(@fs.read_file(args[3]).binary())
      let (json, png) = raster_compare(a, b)
      if png.length() > 0 {
        @fs.write_file(args[4], png, create_mode=CreateOrTruncate)
      }
      @stdio.stdout.write(json.stringify() + "\n")
    }
    _ => {
      @stdio.stderr.write(usage() + "\n")
      fail("bad arguments")
    }
  }
}
