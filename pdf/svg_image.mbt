///|
// SVG images, drawn as vector graphics by the `svg` package (a port of
// prawn-svg, which asciidoctor-pdf draws them with): block images after
// the SVG branch of asciidoctor-pdf's `convert_image`, inline images after
// its `InlineImageArranger` and `InlineImageRenderer`.

///|
/// The transformation stacks of the Prawn documents asciidoctor-pdf draws
/// SVG images into: the document, and the scratch document of dry runs
/// (see `@svg.TransformationStack`).
let svg_stacks : Array[@svg.TransformationStack] = [
  @svg.TransformationStack::new(),
  @svg.TransformationStack::new(),
]

///|
fn reset_svg_stacks() -> Unit {
  svg_stacks[0] = @svg.TransformationStack::new()
  svg_stacks[1] = @svg.TransformationStack::new()
}

///|
fn Flow::svg_stack(self : Flow) -> @svg.TransformationStack {
  svg_stacks[if self.scratch { 1 } else { 0 }]
}

///|
/// Whether an image is SVG: its `format` attribute, else its target's
/// extension (`Asciidoctor::Image.format`).
fn is_svg(node : @core.Node, target : String) -> Bool {
  match node.attr("format") {
    Some(format) => format.to_lower() == "svg"
    None => target.to_lower().has_suffix(".svg")
  }
}

///|
/// The families Prawn knows (`font_families`), with their styles: the
/// catalog's (not the icon sets'), and Prawn's built-in AFM families.
fn FontCatalog::svg_families(
  self : FontCatalog,
) -> Array[(String, Array[String])] {
  let families : Array[(String, Array[String])] = []
  for key, _ in self.faces {
    let parts = key.split("|").map(p => p.to_owned()).collect()
    guard parts.length() == 3 else { continue }
    let family = parts[0]
    if self.icons.contains(family) {
      continue
    }
    let style = match (parts[1] == "true", parts[2] == "true") {
      (false, false) => "normal"
      (true, false) => "bold"
      (false, true) => "italic"
      (true, true) => "bold_italic"
    }
    match families.iter().find_first(f => f.0 == family) {
      Some(f) => f.1.push(style)
      None => families.push((family, [style]))
    }
  }
  for afm in ["Courier", "Times-Roman", "Helvetica"] {
    if !families.iter().any(f => f.0 == afm) {
      families.push((afm, ["normal", "bold", "italic", "bold_italic"]))
    }
  }
  families
}

///|
/// The font SVG text in a font Prawn lacks is drawn in (asciidoctor-pdf's
/// `fallback_svg_font_name`).
fn fallback_svg_font_name() -> String {
  t_str("svg_fallback_font_family").unwrap_or(base_font_family())
}

///|
/// The width of a page's content area: the bounds an inline SVG image is
/// sized in.
fn content_width() -> Double {
  let setup = page_setup.val
  setup.width - setup.margin_left - setup.margin_right
}

///|
/// What SVG images in `node`'s document are drawn with: the catalog's
/// fonts (added to `model` as text uses them) and files relative to
/// `svg_path`'s directory.
fn svg_environment(
  catalog : FontCatalog,
  model : @pagelayout.PageModel,
  node : @core.Node,
  svg_path : String,
) -> @svg.Environment {
  let dir = match svg_path.rev_find("/") {
    Some(i) => svg_path[:i].to_owned()
    None => "."
  }
  let families = catalog.svg_families()
  let load_font = fn(family : String, subfamily : String) -> @svg.SvgFont? {
    guard families.iter().any(f => f.0 == family) else { return None }
    let (bold, italic) = (
      subfamily.contains("bold"),
      subfamily.contains("italic"),
    )
    // the catalog holds the PDF standard fonts Prawn knows (its AFM fonts)
    // unless a theme family takes their name; one it lacks altogether is
    // drawn in the base font
    let family = if catalog.faces.contains(face_key(family, false, false)) {
      family
    } else {
      unsupported("image", "SVG text in the \{family} font", node)
      base_font_family()
    }
    let face = catalog.face(family, bold, italic)
    let index = model.add_font({ family, bold, italic, })
    Some({
      index,
      advances: (text, size) => {
        let out = []
        let n = text.length()
        for i in 0..<n {
          let unit = text[i].to_int()
          if unit >= 0xDC00 && unit <= 0xDFFF {
            out.push(0.0)
            continue
          }
          let (cp, next) = if unit >= 0xD800 && unit <= 0xDBFF && i + 1 < n {
            (
              0x10000 +
              ((unit - 0xD800) << 10) +
              (text[i + 1].to_int() - 0xDC00),
              i + 2,
            )
          } else {
            (unit, i + 1)
          }
          let mut w = face.prawn_width(cp)
          if next < n {
            w += face.kerning(cp, text[next].to_int())
          }
          out.push(w * size / 1000.0)
        }
        out
      },
      height: size => face.height_pt(size),
    })
  }
  {
    families,
    load_font,
    fallback_font: fallback_svg_font_name(),
    read_file: path => {
      let resolved = node.normalize_system_path(path, start=dir)
      node.vfs().read(resolved)
    },
    ambient_font_size: base_style().size,
  }
}

///|
/// An inline SVG image's document, sized in the bounds of the page's
/// content (asciidoctor-pdf's `intrinsic_image_dimensions` reads it in the
/// bounds current where the paragraph is converted); None when the SVG
/// cannot be read.
fn inline_svg(
  data : Bytes,
  path : String,
  node : @core.Node,
) -> @svg.SvgDocument? {
  try
    @svg.SvgDocument::parse(
      @utf8.decode_lossy(data),
      (content_width(), content_height()),
    )
  catch {
    @svg.SvgError(message) => {
      if session.scratch == 0 {
        warning("could not embed image: \{path}; \{message}", node)
      }
      None
    }
  } noraise {
    doc => Some(doc)
  }
}

///|
/// The graphic of an inline SVG image drawn `w` wide with its top-left
/// corner at `(x, y)`.
fn Flow::inline_svg_item(
  self : Flow,
  image : (@svg.SvgDocument, String, @core.Node),
  x : Double,
  y : Double,
  w : Double,
) -> @pagelayout.PageItem? {
  let (doc, path, node) = image
  doc.sizing.resize(width=w)
  let env = svg_environment(self.catalog, self.model, node, path)
  let ops = doc.render(
    env,
    origin=(x, y),
    page_height=page_height(),
    stack=self.svg_stack(),
  )
  report_svg_warnings(doc, path, node, self.scratch)
  if ops.is_empty() {
    None
  } else {
    Some(Graphic({ x_pt: x, y_pt: y, ops, }))
  }
}

///|
/// Report prawn-svg's warnings as asciidoctor-pdf logs them.
fn report_svg_warnings(
  doc : @svg.SvgDocument,
  path : String,
  node : @core.Node,
  scratch : Bool,
) -> Unit {
  if scratch {
    return
  }
  for w in doc.warnings {
    warning("problem encountered in image: \{path}; \{w}", node)
  }
}

///|
/// asciidoctor-pdf's `resolve_explicit_width` for an SVG: a width in
/// points, or a scale of the intrinsic width (`iw`, `scale`).
fn svg_explicit_width(node : @core.Node, bounds : Double) -> (Double?, Double?) {
  let percent = fn(s : String) { @string.parse_double(s) catch { _ => 100.0 } }
  match node.attr("pdfwidth") {
    Some(w) if w.has_suffix("iw") =>
      (None, Some(percent(w[:w.length() - 2].to_owned()) / 100.0))
    Some(w) if w.has_suffix("vw") =>
      (
        Some(page_width() * percent(w[:w.length() - 2].to_owned()) / 100.0),
        None,
      )
    Some(w) => (resolve_length(w, bounds, bare_px=false), None)
    None =>
      match node.attr("scale") {
        Some(s) => (None, Some(percent(s) / 100.0))
        None =>
          match node.attr("scaledwidth") {
            Some(w) => (resolve_length(w, bounds, bare_px=false), None)
            None =>
              match node.attr("width") {
                Some(w) if w.has_suffix("%") =>
                  (
                    resolve_length(w, bounds).map(v => @cmp.minimum(v, bounds)),
                    None,
                  )
                Some(w) if w != "" && w.iter().all(c => c >= '0' && c <= '9') =>
                  (
                    resolve_length(w, bounds).map(v => @cmp.minimum(v, bounds)),
                    None,
                  )
                _ => (None, None)
              }
          }
      }
  }
}

///|
/// A block SVG image (`convert_image`'s SVG branch). False when the SVG
/// cannot be read, for the caller to show the alt text.
fn Converter::convert_svg_image(
  self : Converter,
  node : @core.Node,
  path : String,
  data : Bytes,
  alignment : String,
) -> Bool {
  let flow = self.flow
  let available_w = flow.width()
  let bounds_h = flow.bottom - flow.page_top
  let (width, scale) = svg_explicit_width(node, available_w)
  let doc = @svg.SvgDocument::parse(
    @utf8.decode_lossy(data),
    (available_w, bounds_h),
    width?,
  ) catch {
    @svg.SvgError(message) => {
      if !flow.scratch {
        warning("could not embed image: \{path}; \{message}", node)
      }
      return false
    }
  }
  let sizing = doc.sizing
  let mut rendered_w = sizing.output_width
  match scale {
    Some(s) => {
      sizing.resize(width=@cmp.minimum(available_w, rendered_w * s))
      rendered_w = sizing.output_width
    }
    None =>
      if width is None &&
        doc.root.attr("width") is Some(_) &&
        rendered_w > available_w {
        sizing.resize(width=available_w)
        rendered_w = available_w
      }
  }
  let caption_height = self.image_caption_height(node, alignment, width)
  let mut rendered_h = sizing.output_height
  if rendered_h > flow.cursor() - caption_height {
    if !flow.at_page_top() && !first_child_at_top(node) {
      flow.advance_page()
    }
    let available_h = flow.cursor() - caption_height
    if rendered_h > available_h {
      sizing.resize(height=available_h)
      rendered_h = available_h
      rendered_w = sizing.output_width
    }
  }
  self.add_dest(node)
  self.ink_image_caption(node, alignment, rendered_w, top=true)
  let left = match alignment {
    "center" => flow.left + (available_w - rendered_w) * 0.5
    "right" => flow.left + available_w - rendered_w
    _ => flow.left
  }
  let env = svg_environment(flow.catalog, flow.model, node, path)
  let top = flow.y
  let ops = doc.render(
    env,
    origin=(left, top),
    page_height=page_height(),
    stack=flow.svg_stack(),
  )
  report_svg_warnings(doc, path, node, flow.scratch)
  if !ops.is_empty() {
    flow.push(Graphic({ x_pt: left, y_pt: top, ops, }))
  }
  match node.attr("link") {
    Some(link) if link != "" =>
      flow.push(
        Link({
          x_pt: left,
          y_pt: top,
          w_pt: rendered_w,
          h_pt: rendered_h,
          target: if link.has_prefix("#") {
            Named(pdf_anchor_name(link[1:].to_owned()))
          } else {
            Uri(link)
          },
        }),
      )
    _ => ()
  }
  if !sizing.invalid {
    flow.move_down(rendered_h)
  }
  self.finish_image(node, alignment, rendered_w, rendered_h, caption_height)
  true
}
