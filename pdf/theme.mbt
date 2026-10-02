///|
// The theme of the conversion (asciidoctor-pdf's `@theme`): loaded by the
// theme package from the document's `pdf-theme` (default: the bundled
// default theme), prepared as `prepare_theme` does, and read through the
// accessors below; each styling value the converter uses is a function
// named after its theme key.

///|
/// The theme of the conversion in progress.
let current_theme : Ref[@theme.Theme] = { val: @theme.Theme::new(), }

///|
/// `self`, else `other` (Ruby's `a || b` on optional values).
fn[T] Option::or_some(self : T?, other : T?) -> T? {
  match self {
    Some(_) => self
    None => other
  }
}

///|
/// The value of a theme key (nil when absent).
fn tv(key : String) -> @theme.Value {
  current_theme.val[key]
}

///|
/// A numeric theme value.
fn value_num(v : @theme.Value) -> Double? {
  match v {
    Int(i) => Some(i.to_double())
    Float(f) => Some(f)
    _ => None
  }
}

///|
fn t_num(key : String) -> Double? {
  value_num(tv(key))
}

///|
fn t_num_or(key : String, default : Double) -> Double {
  t_num(key).unwrap_or(default)
}

///|
/// A string theme value (a number as Ruby prints it).
fn value_str(v : @theme.Value) -> String? {
  match v {
    Str(s) | Hex(s) => Some(s)
    Int(_) | Float(_) | Bool(_) | Transparent => Some(v.to_ruby_s())
    _ => None
  }
}

///|
fn t_str(key : String) -> String? {
  value_str(tv(key))
}

///|
/// Whether the key is set to something other than nil or false.
fn t_set(key : String) -> Bool {
  tv(key).truthy()
}

///|
/// A theme color: a hex color (`HexColorValue`, or a plain six-digit
/// string as the base theme has), a CMYK color (approximated in RGB, which
/// is all the renderer has), None for nil and `transparent`.
fn value_color(v : @theme.Value) -> Color? {
  match v {
    Hex(s) | Str(s) => {
      let hex = if s.has_prefix("#") { s[1:].to_owned() } else { s }
      let hex = if hex.length() == 3 {
        let sb = StringBuilder()
        for c in hex {
          sb.write_char(c)
          sb.write_char(c)
        }
        sb.to_string()
      } else {
        hex
      }
      if hex.length() != 6 {
        return None
      }
      parse_int_radix(hex, 16).map(rgb_hex)
    }
    Cmyk(items) => {
      let c = items.map(x => value_num(x).unwrap_or(0.0) / 100.0)
      let k = 1.0 - c[3]
      let channel = (x : Double) => ((1.0 - x) * k * 255.0).round().to_int()
      Some(Color::rgb(channel(c[0]), channel(c[1]), channel(c[2])))
    }
    Int(_) => value_color(Str(v.to_ruby_s()))
    _ => None
  }
}

///|
fn t_color(key : String) -> Color? {
  value_color(tv(key))
}

///|
fn t_color_or(key : String, default : Color) -> Color {
  t_color(key).unwrap_or(default)
}

///|
/// A font style (`bold`, `italic`, `bold_italic`, `normal`,
/// `normal_italic`) as (bold, italic).
fn font_style_of(style : String) -> (Bool, Bool) {
  match style {
    "bold" => (true, false)
    "italic" | "normal_italic" => (false, true)
    "bold_italic" => (true, true)
    _ => (false, false)
  }
}

///|
/// A font size: points, or relative to `current` (`1.2em`, `80%`) or to
/// the root font size (`1.2rem`), as asciidoctor-pdf's `font_size` reads
/// it.
fn resolve_font_size(v : @theme.Value, current : Double) -> Double? {
  match v {
    Int(_) | Float(_) => value_num(v)
    Str(s) =>
      if s.has_suffix("rem") {
        Some(base_font_size() * @theme.ruby_string_to_f(s))
      } else if s.has_suffix("em") {
        Some(current * @theme.ruby_string_to_f(s))
      } else if s.has_suffix("%") {
        Some(current * (@theme.ruby_string_to_f(s) / 100.0))
      } else {
        Some(@theme.ruby_string_to_f(s))
      }
    _ => None
  }
}

///|
/// A theme value as a length in points (`str_to_pt` for a string).
fn value_pt(v : @theme.Value) -> Double? {
  match v {
    Int(_) | Float(_) => value_num(v)
    Str(s) => Some(@theme.str_to_pt(s))
    _ => None
  }
}

///|
/// asciidoctor-pdf's `expand_rect_values` (padding, margin): one value for
/// all sides, [vertical, horizontal], [top, horizontal, bottom] or [top,
/// right, bottom, left]; nil entries count as 0.
fn expand_rect(v : @theme.Value) -> (Double, Double, Double, Double) {
  match v {
    Array(items) => {
      let at = (i : Int) => items.get(i).bind(value_pt).unwrap_or(0.0)
      match items.length() {
        0 => (0.0, 0.0, 0.0, 0.0)
        1 => (at(0), at(0), at(0), at(0))
        2 => (at(0), at(1), at(0), at(1))
        3 => (at(0), at(1), at(2), at(1))
        _ => (at(0), at(1), at(2), at(3))
      }
    }
    other => {
      let x = value_pt(other).unwrap_or(0.0)
      (x, x, x, x)
    }
  }
}

///|
/// The theme's padding for a category (`<category>_padding`).
fn t_padding(key : String) -> (Double, Double, Double, Double) {
  expand_rect(tv(key))
}

///|
/// The page setup of a document before its own is resolved: A4 with
/// asciidoctor-pdf's default margins.
fn default_page_setup() -> PageSetup {
  {
    width: 595.28,
    height: 841.89,
    margin_top: 36.0,
    margin_right: 48.24,
    margin_bottom: 48.24,
    margin_left: 48.24,
  }
}

///|
fn page_width() -> Double {
  session().page_setup.width
}

///|
fn page_height() -> Double {
  session().page_setup.height
}

///|
/// PDF::Core's named page sizes (`PageGeometry::SIZES`), portrait.
let named_page_sizes : Array[(String, Double, Double)] = [
  ("4A0", 4767.87, 6740.79),
  ("2A0", 3370.39, 4767.87),
  ("A0", 2383.94, 3370.39),
  ("A1", 1683.78, 2383.94),
  ("A2", 1190.55, 1683.78),
  ("A3", 841.89, 1190.55),
  ("A4", 595.28, 841.89),
  ("A5", 419.53, 595.28),
  ("A6", 297.64, 419.53),
  ("A7", 209.76, 297.64),
  ("A8", 147.40, 209.76),
  ("A9", 104.88, 147.40),
  ("A10", 73.70, 104.88),
  ("B0", 2834.65, 4008.19),
  ("B1", 2004.09, 2834.65),
  ("B2", 1417.32, 2004.09),
  ("B3", 1000.63, 1417.32),
  ("B4", 708.66, 1000.63),
  ("B5", 498.90, 708.66),
  ("B6", 354.33, 498.90),
  ("B7", 249.45, 354.33),
  ("B8", 175.75, 249.45),
  ("B9", 124.72, 175.75),
  ("B10", 87.87, 124.72),
  ("C0", 2599.37, 3676.54),
  ("C1", 1836.85, 2599.37),
  ("C2", 1298.27, 1836.85),
  ("C3", 918.43, 1298.27),
  ("C4", 649.13, 918.43),
  ("C5", 459.21, 649.13),
  ("C6", 323.15, 459.21),
  ("C7", 229.61, 323.15),
  ("C8", 161.57, 229.61),
  ("C9", 113.39, 161.57),
  ("C10", 79.37, 113.39),
  ("RA0", 2437.80, 3458.27),
  ("RA1", 1729.13, 2437.80),
  ("RA2", 1218.90, 1729.13),
  ("RA3", 864.57, 1218.90),
  ("RA4", 609.45, 864.57),
  ("SRA0", 2551.18, 3628.35),
  ("SRA1", 1814.17, 2551.18),
  ("SRA2", 1275.59, 1814.17),
  ("SRA3", 907.09, 1275.59),
  ("SRA4", 637.80, 907.09),
  ("EXECUTIVE", 521.86, 756.00),
  ("FOLIO", 612.00, 936.00),
  ("LEGAL", 612.00, 1008.00),
  ("LETTER", 612.00, 792.00),
  ("TABLOID", 792.00, 1224.00),
]

///|
/// `MeasurementPartsRx`: `^(\d+(?:\.\d+)?)(in|mm|cm|p[txc])?$`, in points
/// truncated to four decimals (as PDF::Core keeps them); None otherwise.
fn measurement_pt(s : String) -> Double? {
  let (number, units) = if s.length() >= 2 &&
    ["in", "mm", "cm", "pt", "px", "pc"].contains(s[s.length() - 2:].to_owned()) {
    (s[:s.length() - 2].to_owned(), s[s.length() - 2:].to_owned())
  } else {
    (s, "")
  }
  let parts = number.split(".").map(p => p.to_owned()).collect()
  let digits = (p : String) => {
    p != "" && p.iter().all(c => c >= '0' && c <= '9')
  }
  let ok = match parts {
    [a] => digits(a)
    [a, b] => digits(a) && digits(b)
    _ => false
  }
  guard ok else { return None }
  let pt = @theme.to_pt(@theme.ruby_string_to_f(number), units).unwrap_or(0.0)
  Some((pt * 10000.0).floor() / 10000.0)
}

///|
/// asciidoctor-pdf's `resolve_page_margin`: 1 to 4 margins from an array,
/// a number, or a string (`[a, b]` or one measurement).
fn resolve_page_margin(v : @theme.Value) -> Array[Double]? {
  match v {
    Array([]) | Null | Str("") => None
    Array(items) =>
      Some(
        items[:@cmp.minimum(items.length(), 4)]
        .iter()
        .map(x => {
          match x {
            Int(_) | Float(_) => value_num(x).unwrap_or(0.0)
            other => @theme.str_to_pt(other.to_ruby_s())
          }
        })
        .collect(),
      )
    Int(_) | Float(_) => Some([value_num(v).unwrap_or(0.0)])
    Str(s) =>
      if s.has_prefix("[") && s.has_suffix("]") {
        let inner = s[1:s.length() - 1].trim_end(chars=" \t\n").to_owned()
        if inner == "" {
          return None
        }
        let parts = inner.split(",").map(p => p.to_owned()).collect()
        let parts = parts[:@cmp.minimum(parts.length(), 4)]
        Some(
          parts.map(p => @theme.str_to_pt(p.trim_end(chars=" \t\n").to_owned())),
        )
      } else {
        Some([@theme.str_to_pt(s)])
      }
    _ => None
  }
}

///|
/// The page size, layout and margins of `doc` (`build_pdf_options`): the
/// `pdf-page-size`, `pdf-page-layout` and `pdf-page-margin` attributes,
/// else the theme's `page_size`, `page_layout` and `page_margin`.
fn resolve_page_setup(doc : @core.Node) -> PageSetup {
  let margin = match doc.attr("pdf-page-margin") {
    Some(m) => resolve_page_margin(Str(m))
    None => resolve_page_margin(tv("page_margin"))
  }
  let (top, right, bottom, left) = expand_rect(
    Array(margin.unwrap_or([36.0]).map(m => (Float(m) : @theme.Value))),
  )
  // the size: a name, or [width, height]
  let size : @theme.Value = match doc.attr("pdf-page-size") {
    Some(s) if s != "" => {
      let s = s.trim().to_owned()
      if s.has_prefix("[") && s.has_suffix("]") && s.contains(",") {
        let inner = s[1:s.length() - 1].to_owned()
        match inner.find(",") {
          Some(i) =>
            Array([
              Str(inner[:i].trim().to_owned()),
              Str(inner[i + 1:].trim().to_owned()),
            ])
          None => Str(s)
        }
      } else if s.contains("x") &&
        s.find("x") is Some(i) &&
        measurement_pt(s[:i].trim().to_owned()) is Some(_) {
        Array([Str(s[:i].trim().to_owned()), Str(s[i + 1:].trim().to_owned())])
      } else {
        Str(s)
      }
    }
    _ => tv("page_size")
  }
  let mut width = 595.28
  let mut height = 841.89
  match size {
    Str(name) =>
      for entry in named_page_sizes {
        if entry.0 == name.to_upper() {
          width = entry.1
          height = entry.2
        }
      }
    Array(dims) if dims.length() > 0 => {
      let dims = if dims.length() == 1 { [dims[0], dims[0]] } else { dims }
      let resolved = dims[:2]
        .iter()
        .map(d => {
          match d {
            Int(_) | Float(_) =>
              value_num(d).bind(x => if x > 0.0 { Some(x) } else { None })
            Str(s) =>
              measurement_pt(s).bind(x => if x > 0.0 { Some(x) } else { None })
            _ => None
          }
        })
        .collect()
      if resolved.iter().all(x => x is Some(_)) {
        width = resolved[0].unwrap()
        height = resolved[1].unwrap()
      }
    }
    _ => ()
  }
  let layout = match doc.attr("pdf-page-layout") {
    Some(l) if l != "" => Some(l)
    _ => t_str("page_layout")
  }
  if layout == Some("landscape") {
    let w = width
    width = height
    height = w
  }
  {
    width,
    height,
    margin_top: top,
    margin_right: right,
    margin_bottom: bottom,
    margin_left: left,
  }
}

///|
/// asciidoctor-pdf's `theme_font category`: the font settings of a theme
/// category on top of the current ones (`base`, and the base line height
/// `line_height`): its family, size (points, or relative to the current
/// size), style (replacing the current one), colour, line height and text
/// transform, each when the theme sets it.
fn theme_font(
  base : Style,
  line_height : Double,
  category : String,
) -> (Style, Double) {
  let mut s = base
  match t_str(category + "_font_family") {
    Some(family) => s = { ..s, family, }
    None => ()
  }
  match resolve_font_size(tv(category + "_font_size"), s.size) {
    Some(size) => s = { ..s, size, }
    None => ()
  }
  match t_str(category + "_font_style") {
    Some(style) => {
      let (doc_bold, doc_italic) = font_style_of(style)
      s = { ..s, doc_bold, doc_italic, }
    }
    None => ()
  }
  match t_color(category + "_font_color") {
    Some(color) => s = { ..s, color, }
    None => ()
  }
  match t_str(category + "_text_transform") {
    Some("none") => s = { ..s, text_transform: None, }
    Some(transform) => s = { ..s, text_transform: Some(transform), }
    None => ()
  }
  (s, t_num(category + "_line_height").unwrap_or(line_height))
}

///|
/// `theme_font :heading, level: n`: the `heading_h<n>_*` keys, else the
/// `heading_*` ones; the family defaults to the base font's, the size to
/// the root size, and the style to normal.
fn theme_font_heading(
  base : Style,
  line_height : Double,
  level : Int,
  category? : String = "heading",
) -> (Style, Double) {
  let key = (name : String) => {
    match tv("\{category}_h\{level}_\{name}") {
      Null => tv("\{category}_\{name}")
      v => v
    }
  }
  let family = value_str(key("font_family")).unwrap_or(base_font_family())
  let size = match key("font_size") {
    Null => base_font_size()
    v => resolve_font_size(v, base.size).unwrap_or(base_font_size())
  }
  let (doc_bold, doc_italic) = font_style_of(
    value_str(key("font_style")).unwrap_or("normal"),
  )
  let color = value_color(key("font_color")).unwrap_or(base.color)
  let transform = match value_str(key("text_transform")) {
    Some("none") => None
    Some(t) => Some(t)
    None => base.text_transform
  }
  (
    {
      ..base,
      family,
      size,
      doc_bold,
      doc_italic,
      color,
      text_transform: transform,
    },
    value_num(key("line_height")).unwrap_or(line_height),
  )
}

///|
/// A block's text alignment from its roles (`text-left` ...) or, with
/// `query_theme`, the theme's `role_<role>_text_align` of its roles (last
/// first); None when neither says (`resolve_text_align_from_role`).
fn text_align_from_roles(
  roles : Array[String],
  query_theme? : Bool = false,
) -> Alignment? {
  for i = roles.length() - 1; i >= 0; i = i - 1 {
    match roles[i] {
      "text-left" => return Some(Left)
      "text-right" => return Some(Right)
      "text-center" => return Some(Center)
      "text-justify" => return Some(Justify)
      _ => ()
    }
  }
  if query_theme {
    for i = roles.length() - 1; i >= 0; i = i - 1 {
      match t_str("role_\{roles[i]}_text_align") {
        Some(align) => return Some(alignment_of(align))
        None => ()
      }
    }
  }
  None
}

///|
/// A theme alignment (`left`, `center`, `right`, `justify`).
fn alignment_of(value : String) -> Alignment {
  match value {
    "center" => Center
    "right" => Right
    "justify" => Justify
    _ => Left
  }
}

///|
/// A theme key's alignment, else `default`.
fn t_align(key : String, default : Alignment) -> Alignment {
  match t_str(key) {
    Some(value) => alignment_of(value)
    None => default
  }
}

// ---------------------------------------------------------------------------
// the keys the converter reads, with the defaults `prepare_theme` gives
// them

///|
fn base_font_family() -> String {
  t_str("base_font_family").unwrap_or("Helvetica")
}

///|
/// The size of captions (`theme_font :caption`).
fn caption_font_size() -> Double {
  theme_font(base_style(), base_line_height(), "caption").0.size
}

///|
/// `caption_margin_inside`
fn caption_margin_inside() -> Double {
  t_num_or("caption_margin_inside", 0.0)
}

///|
/// The root font size (`@root_font_size`).
fn base_font_size() -> Double {
  t_num_or("base_font_size", 12.0)
}

///|
fn base_font_color() -> Color {
  t_color_or("base_font_color", rgb_hex(0))
}

///|
/// `base_font_style` as (bold, italic).
fn base_font_style() -> (Bool, Bool) {
  font_style_of(t_str("base_font_style").unwrap_or("normal"))
}

///|
/// The current font (asciidoctor-pdf's current font and `@font_color`):
/// the base font, or the enclosing category's.
fn base_style() -> Style {
  match session().font_scope {
    Some((style, _)) => style
    None => text_style()
  }
}

///|
/// The current base line height (`@base_line_height`).
fn base_line_height() -> Double {
  match session().font_scope {
    Some((_, line_height)) => line_height
    None => t_num_or("base_line_height", 1.0)
  }
}

///|
/// Run `body` in the font `style` with the base line height `line_height`
/// (`theme_font` around a block's content).
fn with_font(style : Style, line_height : Double, body : () -> Unit) -> Unit {
  let saved = session().font_scope
  session().font_scope = Some((style, line_height))
  body()
  session().font_scope = saved
}

///|
/// `base_border_color` (`transparent` is none).
fn base_border_color() -> Color? {
  t_color("base_border_color")
}

///|
/// `page_background_color` (`@page_bg_color`).
fn page_background_color() -> Color {
  t_color_or("page_background_color", rgb_hex(0xFFFFFF))
}

///|
fn block_margin_bottom() -> Double {
  t_num_or("block_margin_bottom", 0.0)
}

///|
fn prose_margin_bottom() -> Double {
  t_num_or("prose_margin_bottom", 0.0)
}

///|
fn heading_margin_top() -> Double {
  t_num_or("heading_margin_top", 0.0)
}

///|
fn heading_margin_bottom() -> Double {
  t_num_or("heading_margin_bottom", 0.0)
}

///|
fn list_indent() -> Double {
  t_num_or("list_indent", 0.0)
}

///|
fn list_item_spacing() -> Double {
  t_num_or("list_item_spacing", 0.0)
}

///|
fn description_list_term_spacing() -> Double {
  t_num_or("description_list_term_spacing", 0.0)
}

///|
fn description_list_description_indent() -> Double {
  t_num_or("description_list_description_indent", 0.0)
}

///|
fn admonition_column_rule_width() -> Double {
  t_num_or("admonition_column_rule_width", 0.0)
}

///|
/// `admonition_padding`: [top, right, bottom, left]
fn admonition_padding() -> (Double, Double, Double, Double) {
  t_padding("admonition_padding")
}

///|
/// `toc_indent`
fn toc_indent() -> Double {
  t_num_or("toc_indent", 0.0)
}

///|
/// `index_columns` (2 when the theme sets none)
fn index_columns() -> Int {
  t_num_or("index_columns", 2.0).to_int()
}

///|
/// `index_column_gap` (the root font size when the theme sets none)
fn index_column_gap() -> Double {
  t_num_or("index_column_gap", base_font_size())
}
