///|
using @pagelayout {type Color}

///|
fn rgb_hex(value : Int) -> Color {
  Color::rgb((value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF)
}

///|
/// One face of the font catalog, with the metrics Prawn (the layout engine
/// behind Ruby asciidoctor-pdf) derives from it. Prawn works in 1/1000 em
/// and truncates every metric to an integer there; so does this.
priv struct Face {
  metrics : @fonts.FaceMetrics
  /// OS/2 typo metrics (hhea when zero), 1/1000 em, truncated
  ascender : Int
  descender : Int
  line_gap : Int
  /// `kern` table pairs, (left glyph << 16 | right glyph) → 1/1000 em
  kern : Map[Int, Double]
}

///|
/// Prawn's glyph width in 1/1000 em (truncated), used to break lines as
/// Prawn does.
fn Face::prawn_width(self : Face, codepoint : Int) -> Double {
  (self.metrics.advance_pt(codepoint, 1000.0) + 1.0e-9).floor()
}

///|
/// The width the PDF declares for the glyph (`/Widths`, rounded), used to
/// place glyphs so that no per-glyph displacement is needed.
fn Face::drawn_width(self : Face, codepoint : Int) -> Double {
  self.metrics.advance_pt(codepoint, 1000.0).round()
}

///|
/// Kerning between two codepoints, 1/1000 em (negative tightens).
fn Face::kerning(self : Face, left : Int, right : Int) -> Double {
  if self.kern.is_empty() {
    return 0.0
  }
  let l = self.metrics.cmap.get(left).unwrap_or(0)
  let r = self.metrics.cmap.get(right).unwrap_or(0)
  self.kern.get((l << 16) | r).unwrap_or(0.0)
}

///|
fn Face::ascender_pt(self : Face, size : Double) -> Double {
  self.ascender.to_double() / 1000.0 * size
}

///|
/// Positive depth below the baseline.
fn Face::descender_pt(self : Face, size : Double) -> Double {
  -self.descender.to_double() / 1000.0 * size
}

///|
fn Face::line_gap_pt(self : Face, size : Double) -> Double {
  self.line_gap.to_double() / 1000.0 * size
}

///|
/// Prawn's `font.height`: ascender − descender + line gap.
fn Face::height_pt(self : Face, size : Double) -> Double {
  (self.ascender - self.descender + self.line_gap).to_double() / 1000.0 * size
}

///|
fn read_u16(data : Bytes, offset : Int) -> Int {
  (data[offset].to_int() << 8) | data[offset + 1].to_int()
}

///|
fn read_i16(data : Bytes, offset : Int) -> Int {
  let value = read_u16(data, offset)
  if value >= 0x8000 {
    value - 0x10000
  } else {
    value
  }
}

///|
/// Integer(x) in Ruby: truncation toward zero.
fn truncate(x : Double) -> Int {
  if x < 0.0 {
    -(-x).floor().to_int()
  } else {
    x.floor().to_int()
  }
}

///|
/// Parse the first subtable of a `kern` table when it is format 0: ttfunk,
/// and so Prawn, reads only that one.
fn parse_kern(data : Bytes, scale : Double) -> Map[Int, Double] {
  let pairs : Map[Int, Double] = Map([])
  guard @pdflite.pdf_truetype_table(data, "kern") is Some(table) else {
    return pairs
  }
  let base = table.offset
  // version 0 header: version, nTables; then the first subtable's version,
  // length, coverage (format in the high byte), nPairs and search fields
  guard read_u16(data, base) == 0 && read_u16(data, base + 2) > 0 else {
    return pairs
  }
  let subtable = base + 4
  guard read_u16(data, subtable + 4) >> 8 == 0 else { return pairs }
  let n = read_u16(data, subtable + 6)
  let mut p = subtable + 14
  for _ in 0..<n {
    let left = read_u16(data, p)
    let right = read_u16(data, p + 2)
    pairs[(left << 16) | right] = read_i16(data, p + 4).to_double() * scale
    p += 6
  }
  pairs
}

///|
/// Build a face from a TrueType file and register it with pagelayout for
/// measurement and embedding.
fn load_face(
  family : String,
  bold : Bool,
  italic : Bool,
  data : Bytes,
) -> Face raise {
  let metrics = @fonts.register_face(family, data, bold~, italic~)
  @fontoutlines.register_outline(family, data, bold~, italic~)
  let scale = 1000.0 / metrics.units_per_em.to_double()
  // ttfunk: the OS/2 typo value when present and nonzero, else hhea
  let mut ascent = metrics.ascender
  let mut descent = metrics.descender
  let mut gap = metrics.line_gap
  match @pdflite.pdf_truetype_table(data, "OS/2") {
    Some(os2) => {
      let typo_ascent = read_i16(data, os2.offset + 68)
      let typo_descent = read_i16(data, os2.offset + 70)
      let typo_gap = read_i16(data, os2.offset + 72)
      if typo_ascent != 0 {
        ascent = typo_ascent
      }
      if typo_descent != 0 {
        descent = typo_descent
      }
      if typo_gap != 0 {
        gap = typo_gap
      }
    }
    None => ()
  }
  {
    metrics,
    ascender: truncate(ascent.to_double() * scale),
    descender: truncate(descent.to_double() * scale),
    line_gap: truncate(gap.to_double() * scale),
    kern: parse_kern(data, scale),
  }
}

///|
/// The font catalog of the theme: family → the four styles.
pub struct FontCatalog {
  priv faces : Map[String, Face]
}

///|
fn face_key(family : String, bold : Bool, italic : Bool) -> String {
  "\{family}|\{bold}|\{italic}"
}

///|
/// The file names of the default theme's catalog (asciidoctor-pdf's
/// `data/fonts`): (family, bold, italic, file).
pub fn default_font_files() -> Array[(String, Bool, Bool, String)] {
  [
    ("Noto Serif", false, false, "notoserif-regular-subset.ttf"),
    ("Noto Serif", true, false, "notoserif-bold-subset.ttf"),
    ("Noto Serif", false, true, "notoserif-italic-subset.ttf"),
    ("Noto Serif", true, true, "notoserif-bold_italic-subset.ttf"),
    ("M+ 1mn", false, false, "mplus1mn-regular-subset.ttf"),
    ("M+ 1mn", true, false, "mplus1mn-bold-subset.ttf"),
    ("M+ 1mn", false, true, "mplus1mn-italic-subset.ttf"),
    ("M+ 1mn", true, true, "mplus1mn-bold_italic-subset.ttf"),
  ]
}

///|
/// Load a catalog from font files: (family, bold, italic, TrueType bytes).
pub fn FontCatalog::load(
  files : Array[(String, Bool, Bool, Bytes)],
) -> FontCatalog raise {
  let faces : Map[String, Face] = Map([])
  for file in files {
    let (family, bold, italic, data) = file
    faces[face_key(family, bold, italic)] = load_face(
      family, bold, italic, data,
    )
  }
  { faces, }
}

///|
fn FontCatalog::face(
  self : FontCatalog,
  family : String,
  bold : Bool,
  italic : Bool,
) -> Face {
  match self.faces.get(face_key(family, bold, italic)) {
    Some(face) => face
    None =>
      match self.faces.get(face_key(family, false, false)) {
        Some(face) => face
        None =>
          match self.faces.get(face_key(base_font_family, bold, italic)) {
            Some(face) => face
            None => abort("font catalog has no face for \{family}")
          }
      }
  }
}
