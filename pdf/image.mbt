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
  let data = if is_gif(node, target) { None } else { node.vfs().read(path) }
  let info = data.bind(image_info)
  // `float` (left or right), else `align` (left when unknown), else the
  // last alignment role
  let alignment = match node.attr("float") {
    Some("left") => "left"
    Some("right") => "right"
    _ =>
      match node.attr("align") {
        Some("center") => "center"
        Some("right") => "right"
        Some(_) => "left"
        None =>
          node
          .roles()
          .rev_iter()
          .find_first(r => r == "left" || r == "center" || r == "right")
          .unwrap_or("left")
      }
  }
  guard data is Some(bytes) && info is Some((px_w, px_h, mime)) else {
    if data is Some(_) {
      // asciidoctor-pdf draws SVG, GIF, ... itself
      unsupported("image", "format of \{target}", node)
    }
    // asciidoctor-pdf's `on_image_error`: the alt text in brackets (linked
    // when the image is) and the target in italics, then the caption
    let (open, close) = match node.attr("link") {
      Some(link) => ("<a href=\"\{link}\">", "</a>")
      None => ("", "")
    }
    self.ink_prose(
      "\{open}[\{node.attr("alt").unwrap_or(target)}]\{close} | <em>\{target}</em>",
      align=match alignment {
        "center" => Center
        "right" => Right
        _ => Left
      },
      margin_bottom=0.0,
      normalize=false,
    )
    if node.has_title() {
      self.ink_caption(node.captioned_title(), bottom=true)
    }
    self.block_margin_bottom(node)
    return
  }
  let bounds = flow.width()
  let intrinsic = px_w.to_double() * 0.75
  // resolve_explicit_width: `pdfwidth` (`iw`: of the intrinsic width),
  // `scale`, `scaledwidth`, then `width` (a percentage, or digits taken
  // as pixels, and no wider than the bounds; other values are ignored)
  let explicit = match node.attr("pdfwidth") {
    Some(w) if w.has_suffix("iw") => {
      let percent = @string.parse_double(w[:w.length() - 2].to_owned()) catch {
        _ => 100.0
      }
      Some(percent / 100.0 * intrinsic)
    }
    Some(w) => resolve_length(w, bounds, bare_px=false)
    None =>
      match node.attr("scale") {
        Some(s) =>
          Some(
            (@string.parse_double(s) catch { _ => 100.0 }) / 100.0 * intrinsic,
          )
        None =>
          match node.attr("scaledwidth") {
            Some(w) => resolve_length(w, bounds, bare_px=false)
            None =>
              match node.attr("width") {
                Some(w) if w.has_suffix("%") =>
                  resolve_length(w, bounds).map(v => @cmp.minimum(v, bounds))
                Some(w) if w != "" && w.iter().all(c => c >= '0' && c <= '9') =>
                  resolve_length(w, bounds).map(v => @cmp.minimum(v, bounds))
                _ => None
              }
          }
      }
  }
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
  let x = match alignment {
    "center" => flow.left + (bounds - width) / 2.0
    "right" => flow.left + bounds - width
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
  // add_link_to_image: a link annotation over the image
  match node.attr("link") {
    Some(link) if link != "" =>
      flow.push(
        Link({
          x_pt: x,
          y_pt: flow.y,
          w_pt: width,
          h_pt: height,
          // add_link_to_image: `#name` is a destination, anything else a
          // URI action
          target: if link.has_prefix("#") {
            Named(pdf_anchor_name(link[1:].to_owned()))
          } else {
            Uri(link)
          },
        }),
      )
    _ => ()
  }
  if node.attr("float") is Some("left" | "right") &&
    width < bounds &&
    next_enclosed_block(node) is Some(next) &&
    next.context == Paragraph {
    // init_float_box: the next paragraph wraps around the image
    unsupported("image", "float wrapping", node)
  }
  flow.move_down(height)
  if node.has_title() {
    self.ink_caption(node.captioned_title(), bottom=true)
  }
  self.block_margin_bottom(node)
}

///|
/// An inline image (`image:target[]`): its bytes and media type, its
/// intrinsic size in pixels, the width asciidoctor-pdf gives its `<img>`
/// (points, `N%` of the line, or `N%W`: N% of the intrinsic width W) and
/// its `fit`.
priv struct InlineImage {
  data : Bytes
  mime : String
  px_w : Int
  px_h : Int
  width : String
  fit : String?
}

///|
/// asciidoctor-pdf's `convert_inline_image`: a readable PNG or JPEG becomes
/// an `<img>` whose `src` numbers it among the session's inline images (the
/// formatted text then reserves its width in the line and draws it there,
/// see `inline_image_size`); any other image is its alt text in brackets.
/// A `link` makes it a link.
fn convert_inline_image(node : @core.Node) -> String {
  let target = node.target.unwrap_or("")
  let alt = node.attr("alt").unwrap_or("")
  let path = node.normalize_system_path(
    target,
    start=node.document().attr("imagesdir").unwrap_or(""),
  )
  let bytes = if is_gif(node, target) { None } else { node.vfs().read(path) }
  let img = match
    bytes.bind(data => image_info(data).map(info => (data, info))) {
    Some((data, (px_w, px_h, mime))) => {
      let intrinsic = px_w.to_double() * 0.75
      // resolve_explicit_width without bounds: a percentage stays one (of
      // the intrinsic width, in a table cell), `iw` and `scale` are of the
      // intrinsic width, digits are pixels; else the intrinsic width
      let percent = fn(value : String) {
        @string.parse_double(value) catch {
          _ => 100.0
        }
      }
      let width = match node.attr("pdfwidth") {
        Some(w) if w.has_suffix("%") => w
        Some(w) if w.has_suffix("iw") =>
          (percent(w[:w.length() - 2].to_owned()) / 100.0 * intrinsic).to_string()
        Some(w) =>
          resolve_length(w, 0.0, bare_px=false)
          .map(v => v.to_string())
          .unwrap_or(intrinsic.to_string())
        None =>
          match node.attr("scale") {
            Some(s) => (percent(s) / 100.0 * intrinsic).to_string()
            None =>
              match node.attr("scaledwidth") {
                Some(w) if w.has_suffix("%") => w
                Some(w) =>
                  resolve_length(w, 0.0, bare_px=false)
                  .map(v => v.to_string())
                  .unwrap_or(intrinsic.to_string())
                None =>
                  match node.attr("width") {
                    Some(w) if w.has_suffix("%") => w
                    Some(w) if w != "" &&
                      w.iter().all(c => c >= '0' && c <= '9') =>
                      (percent(w) * 0.75).to_string()
                    _ => intrinsic.to_string()
                  }
              }
          }
      }
      let in_cell = match node.parent() {
        Some(parent) => parent.context == TableCell
        None => false
      }
      let width = if in_cell && width.has_suffix("%") {
        width + intrinsic.to_string()
      } else {
        width
      }
      let index = session.inline_images.length()
      session.inline_images.push({
        data,
        mime,
        px_w,
        px_h,
        width,
        fit: node.attr("fit"),
      })
      "<img src=\"\{index}\">"
    }
    None => {
      // a missing image is its alt text in Ruby too; asciidoctor-pdf draws
      // SVG and GIF (with prawn-gmagick) images this backend cannot
      if bytes is Some(_) {
        unsupported("inline", "image \{target}", node)
      }
      "[\{alt}&#93;"
    }
  }
  match node.attr("link") {
    // Ruby's link annotation over an inline image names only the first
    // character of the anchor as its destination (`/Dest (_)` for
    // `link=#_section`), which this reproduces
    Some(link) if link.has_prefix("#") => {
      let anchor = if img.has_prefix("<img") {
        String::from_iter(link.iter().drop(1).take(1))
      } else {
        link[1:].to_owned()
      }
      "<a anchor=\"\{anchor}\">\{img}</a>"
    }
    Some(link) if link != "" => "<a href=\"\{link}\">\{img}</a>"
    _ => img
  }
}

///|
/// The size an inline image takes in a line `available` wide
/// (InlineImageArranger#arrange_images): its width (a percentage of the
/// line, or of its intrinsic width, or points, never wider than the line)
/// and height, shrunk to fit `max_height` (the bounds, or the line for
/// `fit=line`); and whether it is taller than one and a half lines of
/// `font_height`, when the line grows to hold it.
fn inline_image_size(
  image : InlineImage,
  available : Double,
  font_height : Double,
) -> (Double, Double, Bool) {
  let number = fn(text : String) {
    @string.parse_double(text) catch {
      _ => 0.0
    }
  }
  let spec = image.width
  let mut width = match spec.find("%") {
    Some(i) if i + 1 < spec.length() =>
      @cmp.minimum(
        available,
        number(spec[:i].to_owned()) / 100.0 * number(spec[i + 1:].to_owned()),
      )
    Some(i) =>
      @cmp.minimum(available, number(spec[:i].to_owned()) / 100.0 * available)
    None => @cmp.minimum(available, number(spec))
  }
  let max_height = if image.fit == Some("line") {
    @cmp.minimum(content_height, font_height)
  } else {
    content_height
  }
  let aspect = image.px_h.to_double() / image.px_w.to_double()
  let mut height = width * aspect
  if height > max_height {
    height = max_height
    width = height / aspect
  }
  (width, height, height > font_height * 1.5)
}

///|
/// The height of a page's content area: the bounds an inline image must
/// fit in.
let content_height : Double = page_height - margin_top - margin_bottom

///|
/// Whether the image is a GIF (its `format` attribute, else its target's
/// extension): without prawn-gmagick, asciidoctor-pdf treats it as missing
/// and shows its alt text.
fn is_gif(node : @core.Node, target : String) -> Bool {
  match node.attr("format") {
    Some(format) => format.to_lower() == "gif"
    None => target.to_lower().has_suffix(".gif")
  }
}
