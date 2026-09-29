///|
// Block images (PNG and JPEG), after asciidoctor-pdf's `convert_image`:
// the width comes from `pdfwidth`, `scaledwidth` or `width`, else the
// intrinsic width at 0.75 pt/px capped to the bounds; an image that does not
// fit below the cursor moves to the next page, or shrinks to fit a page; the
// title is a caption below.

///|
fn be32(data : Bytes, offset : Int) -> Int {
  (data[offset].to_int() << 24) |
  (data[offset + 1].to_int() << 16) |
  (data[offset + 2].to_int() << 8) |
  data[offset + 3].to_int()
}

///|
/// Intrinsic (width, height) in pixels and the media type, for PNG and
/// JPEG.
fn image_info(data : Bytes) -> (Int, Int, String)? {
  if data.length() > 24 &&
    data[0] == b'\x89' &&
    data[1] == b'P' &&
    data[2] == b'N' &&
    data[3] == b'G' {
    return Some((be32(data, 16), be32(data, 20), "image/png"))
  }
  if data.length() > 4 && data[0] == b'\xFF' && data[1] == b'\xD8' {
    let mut i = 2
    while i + 9 < data.length() {
      if data[i] != b'\xFF' {
        i += 1
        continue
      }
      let marker = data[i + 1].to_int()
      let length = read_u16(data, i + 2)
      // start-of-frame markers carry the dimensions
      if marker >= 0xC0 &&
        marker <= 0xCF &&
        marker != 0xC4 &&
        marker != 0xC8 &&
        marker != 0xCC {
        let height = read_u16(data, i + 5)
        let width = read_u16(data, i + 7)
        return Some((width, height, "image/jpeg"))
      }
      i += 2 + length
    }
  }
  None
}

///|
/// A length attribute in points: `%` of `bounds`, `in`, `mm`, `cm`, `pt`,
/// `px` or a bare number of pixels.
fn resolve_length(
  value : String,
  bounds : Double,
  bare_px? : Bool = true,
) -> Double? {
  let number = fn(text : String) -> Double? {
    Some(@string.parse_double(text)) catch {
      _ => None
    }
  }
  if value.has_suffix("%") {
    number(value[:value.length() - 1].to_owned()).map(v => v / 100.0 * bounds)
  } else if value.has_suffix("in") {
    number(value[:value.length() - 2].to_owned()).map(v => v * 72.0)
  } else if value.has_suffix("mm") {
    number(value[:value.length() - 2].to_owned()).map(v => v * 72.0 / 25.4)
  } else if value.has_suffix("cm") {
    number(value[:value.length() - 2].to_owned()).map(v => v * 72.0 / 2.54)
  } else if value.has_suffix("pt") {
    number(value[:value.length() - 2].to_owned())
  } else if value.has_suffix("px") {
    number(value[:value.length() - 2].to_owned()).map(v => v * 0.75)
  } else if bare_px {
    number(value).map(v => v * 0.75)
  } else {
    number(value)
  }
}

///|
fn Converter::convert_image(self : Converter, node : @core.Node) -> Unit {
  let flow = self.flow
  let target = node.attr("target").unwrap_or("")
  let path = node.normalize_system_path(
    target,
    start=node.document().attr("imagesdir").unwrap_or(""),
  )
  let data = node.vfs().read(path)
  let info = data.bind(image_info)
  guard data is Some(bytes) && info is Some((px_w, px_h, mime)) else {
    if data is Some(_) {
      // asciidoctor-pdf draws SVG, GIF, ... itself
      unsupported("image", "format of \{target}", node)
    }
    // asciidoctor-pdf prints the alt text in brackets
    self.ink_prose(
      "[\{node.attr("alt").unwrap_or(target)}] | \{target}",
      align=Left,
      margin_bottom=0.0,
    )
    self.block_margin_bottom(node)
    return
  }
  let bounds = flow.width()
  let explicit = match node.attr("pdfwidth") {
    Some(w) => resolve_length(w, bounds, bare_px=false)
    None =>
      match node.attr("scaledwidth") {
        Some(w) => resolve_length(w, bounds, bare_px=false)
        None =>
          match node.attr("width") {
            Some(w) => resolve_length(w, bounds)
            None => None
          }
      }
  }
  let intrinsic = px_w.to_double() * 0.75
  let mut width = match explicit {
    Some(w) => w
    None => @cmp.minimum(intrinsic, bounds)
  }
  let aspect = px_h.to_double() / px_w.to_double()
  let mut height = width * aspect
  // the image keeps its caption (below it) on the same page
  let caption_height = if node.has_title() {
    let style = Style::new(size=caption_font_size, doc_italic=true)
    flow.height_of(
      parse_formatted(node.captioned_title(), style, normalize=false),
      line_metrics(base_line_height, flow.font(style), caption_font_size),
      style,
    ) +
    caption_margin_inside
  } else {
    0.0
  }
  if height > flow.cursor() - caption_height {
    if !flow.at_page_top() {
      flow.advance_page()
    }
    if height > flow.cursor() - caption_height {
      height = flow.cursor() - caption_height
      width = height / aspect
    }
  }
  self.add_dest(node)
  let x = match node.attr("align") {
    Some("center") => flow.left + (bounds - width) / 2.0
    Some("right") => flow.left + bounds - width
    _ => flow.left
  }
  flow.push(
    Image({
      x_pt: x,
      y_pt: flow.y,
      w_pt: width,
      h_pt: height,
      data: bytes,
      mime,
    }),
  )
  flow.move_down(height)
  if node.has_title() {
    self.ink_caption(node.captioned_title(), bottom=true)
  }
  self.block_margin_bottom(node)
}
