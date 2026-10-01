///|
// Images placed in a box rather than in the flow (asciidoctor-pdf's
// `resolve_background_image` and `resolve_image_options`, drawn with
// Prawn's `image` in a canvas or bounding box): page background and
// foreground images, the title page background, cover pages, and images
// in the running content.

///|
/// An image resolved for a box, with Prawn's sizing options.
priv struct BoxImage {
  data : Bytes
  svg : Bool
  /// the file (the target for a data URI), for SVG references and messages
  path : String
  /// Prawn's `:fit` (the box to fit in), `:width` and `:height`
  fit : (Double, Double)?
  width : Double?
  height : Double?
  /// `:position` (left, center, right) and `:vposition` (top, center,
  /// bottom)
  position : String
  vposition : String
  /// the macro's `link`
  link : String?
}

///|
/// What `resolve_background_image` finds: nothing, a symbolic value (`""`
/// or `~` where the caller accepts them), or an image.
priv enum Background {
  /// no value, or an image that cannot be read
  NoImage
  /// `none`
  Cleared
  Symbolic(String)
  Found(BoxImage)
}

///|
/// `ImageAttributeValueRx`: `image:target[attrs]` (or `image::`), as the
/// target and the attribute list.
fn image_macro(value : String) -> (String, String)? {
  let rest = if value.has_prefix("image::") {
    value[7:].to_owned()
  } else if value.has_prefix("image:") {
    value[6:].to_owned()
  } else {
    return None
  }
  guard rest.has_suffix("]") && rest.find("[") is Some(i) else { return None }
  Some((rest[:i].to_owned(), rest[i + 1:rest.length() - 1].to_owned()))
}

///|
/// A string attribute of a parsed attribute list.
fn attrs_str(attrs : @core.Attributes, name : String) -> String? {
  match attrs.get(name) {
    Some(Str(s)) => Some(s)
    Some(Int(i)) => Some(i.to_string())
    _ => None
  }
}

///|
/// `resolve_explicit_width` of an image macro's attributes: `pdfwidth`
/// (`%` of the bounds, else a length), `scaledwidth`, then `width` (`%` of
/// the bounds, or digits taken as pixels). `iw`, `vw` and `scale` widths
/// are left to the caller (None).
fn macro_explicit_width(attrs : @core.Attributes, bounds : Double) -> Double? {
  match attrs_str(attrs, "pdfwidth") {
    Some(w) if w.has_suffix("%") =>
      Some(@theme.ruby_string_to_f(w) / 100.0 * bounds)
    Some(w) if w.has_suffix("iw") || w.has_suffix("vw") => None
    Some(w) => Some(@theme.str_to_pt(w))
    None =>
      if attrs.contains("scale") {
        None
      } else {
        match attrs_str(attrs, "scaledwidth") {
          Some(w) if w.has_suffix("%") =>
            Some(@theme.ruby_string_to_f(w) / 100.0 * bounds)
          Some(w) => Some(@theme.str_to_pt(w))
          None =>
            match attrs_str(attrs, "width") {
              Some(w) if w.has_suffix("%") =>
                Some(@theme.ruby_string_to_f(w) / 100.0 * bounds)
              Some(w) if w != "" && w.iter().all(c => c >= '0' && c <= '9') =>
                Some(@theme.ruby_string_to_f(w) * 0.75)
              _ => None
            }
        }
      }
  }
}

///|
/// `resolve_background_position`: `left`, `right` or `center` (centered
/// vertically), `top` or `bottom` (centered horizontally), or two keywords;
/// None for anything else.
fn background_position(value : String) -> (String, String)? {
  if value.contains(" ") {
    let mut position : String? = None
    let mut vposition : String? = None
    let mut center = false
    let parts = match value.find(" ") {
      Some(i) => [value[:i].to_owned(), value[i + 1:].to_owned()]
      None => [value]
    }
    for keyword in parts {
      match keyword {
        "left" | "right" => position = Some(keyword)
        "top" | "bottom" => vposition = Some(keyword)
        "center" => center = true
        _ => ()
      }
    }
    if center {
      Some((position.unwrap_or("center"), vposition.unwrap_or("center")))
    } else {
      match (position, vposition) {
        (Some(p), Some(v)) => Some((p, v))
        _ => None
      }
    }
  } else {
    match value {
      "left" | "right" | "center" => Some((value, "center"))
      "top" | "bottom" => Some(("center", value))
      _ => None
    }
  }
}

///|
/// The intrinsic size of an image in points (`intrinsic_image_dimensions`:
/// prawn-svg's for SVG, 0.75 pt per pixel otherwise).
fn intrinsic_size(
  data : Bytes,
  svg : Bool,
  container : (Double, Double),
) -> (Double, Double) {
  if svg {
    let doc = @svg.SvgDocument::parse(@utf8.decode_lossy(data), container) catch {
      _ => return (0.0, 0.0)
    }
    (doc.sizing.output_width, doc.sizing.output_height)
  } else {
    match image_info(data) {
      Some((w, h, _)) => (w.to_double() * 0.75, h.to_double() * 0.75)
      None => (0.0, 0.0)
    }
  }
}

///|
/// asciidoctor-pdf's `resolve_background_image` (with `background: true`):
/// the image the `attr` document attribute names, else the theme's
/// `theme_key`; `image:target[attrs]` takes attributes (`fit`, `position`,
/// widths), a value from the theme is resolved against the theme's
/// directory after attribute substitution (`{page-layout}` included), and
/// a bare value from the document against the base directory. `none` is no
/// image; with `symbolic`, `""` and `~` come back as they are.
fn Converter::resolve_background_image(
  self : Converter,
  attr : String?,
  theme_key : String,
  container : (Double, Double),
  symbolic? : Bool = false,
  layout? : String = "portrait",
) -> Background {
  let doc = self.doc
  let (value, from_theme) = match attr.bind(a => doc.attr(a)) {
    Some(v) => (v, false)
    None =>
      match tv(theme_key) {
        Null | Bool(false) => return NoImage
        v => (v.to_ruby_s(), true)
      }
  }
  let key = attr.unwrap_or(theme_key)
  if symbolic && (value == "" || value == "~") {
    return Symbolic(value)
  }
  if value == "none" {
    return Cleared
  }
  let mut path = value
  let mut attrs : @core.Attributes? = None
  // relative to: the images directory (an image macro), the theme's
  // directory (a theme value), else the base directory
  let mut relative_to : String? = None
  let mut relative_to_imagesdir = false
  match image_macro(value) {
    Some((target, attrlist)) => {
      attrs = Some(
        @core.parse_attribute_list(attrlist, positional_attrs=[
          Some("alt"),
          Some("width"),
        ]),
      )
      path = target
      relative_to_imagesdir = true
    }
    None => ()
  }
  if from_theme {
    let themesdir = current_theme.val.dir()
    path = with_attrs(
      doc,
      [("imagesdir", themesdir), ("page-layout", layout)],
      () => apply_subs_discretely(doc, path),
    )
    relative_to = Some(themesdir)
    relative_to_imagesdir = false
  } else if path.contains("{page-layout}") {
    path = path.replace(old="{page-layout}", new=layout)
  }
  let (target, format) = image_target_and_format(
    path,
    attrs.bind(a => attrs_str(a, "format")),
  )
  let (data, resolved) = match target {
    Data(bytes) => (Some(bytes), path)
    Path(p) => {
      if p.has_prefix("http://") || p.has_prefix("https://") {
        if !doc.has_attr("allow-uri-read") {
          warning(
            "cannot embed remote image: \{p} (allow-uri-read attribute not enabled)",
            doc,
          )
        }
        return NoImage
      }
      let start = if relative_to_imagesdir {
        match doc.attr("imagesdir") {
          Some("" | "." | "./") | None => None
          dir => dir
        }
      } else {
        relative_to
      }
      let resolved = if p.has_prefix("/") {
        p
      } else {
        match start {
          Some(dir) if dir.has_prefix("/") => @core.expand_path_from(dir, p)
          _ => doc.normalize_system_path(p, start?)
        }
      }
      (doc.vfs().read(resolved), resolved)
    }
  }
  guard data is Some(data) else {
    warning(
      "\{key.replace_all(old="-", new=" ").replace_all(old="_", new=" ")} not found or readable: \{resolved}",
      doc,
    )
    return NoImage
  }
  if format == "pdf" {
    unsupported("image", "format of \{path}", doc)
    return NoImage
  }
  let svg = format == "svg"
  let (cw, ch) = container
  let mut position = "center"
  let mut vposition = "center"
  let mut fit : (Double, Double)? = None
  let mut width : Double? = None
  let mut height : Double? = None
  match attrs {
    Some(attrs) => {
      match attrs_str(attrs, "position").bind(background_position) {
        Some((p, v)) => {
          position = p
          vposition = v
        }
        None => ()
      }
      let image_fit = match attrs_str(attrs, "fit").unwrap_or("contain") {
        "fill" if svg => "contain"
        f => f
      }
      match image_fit {
        "none" => width = macro_explicit_width(attrs, cw)
        "scale-down" =>
          match macro_explicit_width(attrs, cw) {
            Some(w) =>
              if w > cw {
                fit = Some(container)
              } else {
                let (iw, ih) = intrinsic_size(data, svg, container)
                if iw > 0.0 && w * (ih / iw) > ch {
                  fit = Some(container)
                } else {
                  width = Some(w)
                }
              }
            None => {
              let (iw, ih) = intrinsic_size(data, svg, container)
              if iw > cw || ih > ch {
                fit = Some(container)
              }
            }
          }
        "cover" => {
          let (iw, ih) = intrinsic_size(data, svg, container)
          if iw > 0.0 && cw * (ih / iw) < ch {
            height = Some(ch)
          } else {
            width = Some(cw)
          }
        }
        "fill" => {
          width = Some(cw)
          height = Some(ch)
        }
        _ => fit = Some(container)
      }
    }
    None => fit = Some(container)
  }
  Found({
    data,
    svg,
    path: resolved,
    fit,
    width,
    height,
    position,
    vposition,
    link: attrs.bind(a => attrs_str(a, "link")),
  })
}

///|
/// `body` with document attributes temporarily set (asciidoctor-pdf's
/// `apply_subs_discretely` options).
fn[T] with_attrs(
  doc : @core.Node,
  values : Array[(String, String)],
  body : () -> T,
) -> T {
  let saved = values.map(v => (v.0, doc.attr(v.0)))
  for v in values {
    ignore(doc.set_attr(v.0, value=Str(v.1)))
  }
  let result = body()
  for s in saved {
    match s.1 {
      Some(old) => ignore(doc.set_attr(s.0, value=Str(old)))
      None => ignore(doc.remove_attr(s.0))
    }
  }
  result
}

///|
/// Prawn's `image` of `img` in the box at (`left`, `top`) `w` × `h` (y
/// down), positioned by its `position` and `vposition`: the page items,
/// and the size it was drawn at (None when the image cannot be drawn).
fn Converter::box_image_items(
  self : Converter,
  img : BoxImage,
  left : Double,
  top : Double,
  w : Double,
  h : Double,
) -> (Array[@pagelayout.PageItem], Double, Double)? {
  let flow = self.flow
  let place = (iw : Double, ih : Double) => {
    let x = match img.position {
      "left" => left
      "right" => left + w - iw
      _ => left + (w - iw) / 2.0
    }
    let y = match img.vposition {
      "top" => top
      "bottom" => top + h - ih
      _ => top + (h - ih) / 2.0
    }
    (x, y)
  }
  if img.svg {
    let doc = @svg.SvgDocument::parse(
      @utf8.decode_lossy(img.data),
      (w, h),
      width?=img.width,
      height?=if img.width is None { img.height } else { None },
    ) catch {
      @svg.SvgError(message) => {
        if !flow.scratch {
          warning("could not embed image: \{img.path}; \{message}", self.doc)
        }
        return None
      }
    }
    let sizing = doc.sizing
    match (img.fit, img.width, img.height) {
      (Some((fw, fh)), None, None) => {
        // fit to the width, then shrink to the height
        if sizing.output_width != fw {
          sizing.resize(width=fw)
        }
        if sizing.output_height > fh {
          sizing.resize(height=fh)
        }
      }
      (_, Some(_), Some(hh)) => sizing.resize(height=hh)
      _ => ()
    }
    let (iw, ih) = (sizing.output_width, sizing.output_height)
    let (x, y) = place(iw, ih)
    let env = svg_environment(flow.catalog, flow.model, self.doc, img.path)
    let ops = doc.render(
      env,
      origin=(x, y),
      page_height=page_height(),
      stack=flow.svg_stack(),
    )
    report_svg_warnings(doc, img.path, self.doc, flow.scratch)
    Some(([Graphic({ x_pt: x, y_pt: y, ops, })], iw, ih))
  } else {
    guard image_info(img.data) is Some((px_w, px_h, mime)) else {
      if !flow.scratch {
        warning("could not embed image: \{img.path}", self.doc)
      }
      return None
    }
    // Prawn's `calc_image_dimensions`: the natural size is a point a pixel
    let (nw, nh) = (px_w.to_double(), px_h.to_double())
    let (iw, ih) = match (img.width, img.height, img.fit) {
      (Some(iw), Some(ih), _) => (iw, ih)
      (Some(iw), None, _) => (iw, nh * iw / nw)
      (None, Some(ih), _) => (nw * ih / nh, ih)
      (None, None, Some((fw, fh))) => {
        let bp = fw / fh
        let ip = nw / nh
        if ip > bp {
          (fw, fw / ip)
        } else {
          (fh * ip, fh)
        }
      }
      (None, None, None) => (nw, nh)
    }
    let (x, y) = place(iw, ih)
    Some(
      (
        [Image({ x_pt: x, y_pt: y, w_pt: iw, h_pt: ih, data: img.data, mime, })],
        iw,
        ih,
      ),
    )
  }
}

///|
/// One side's page background image, as `get_page_bg_image` resolves it for
/// a page layout: `page-background-image`, overridden per side by
/// `page-background-image-recto` and `-verso` (`none` clears it).
fn Converter::page_bg_images(
  self : Converter,
  container : (Double, Double),
  layout : String,
) -> Map[String, BoxImage?] {
  let resolve = (attr : String) => {
    self.resolve_background_image(
      Some(attr),
      attr.replace_all(old="-", new="_"),
      container,
      layout~,
    )
  }
  let base = match resolve("page-background-image") {
    Found(img) => Some(img)
    _ => None
  }
  let sides : Map[String, BoxImage?] = Map([])
  for side in ["verso", "recto"] {
    sides[side] = match resolve("page-background-image-\{side}") {
      Found(img) => Some(img)
      Cleared => None
      _ => base
    }
  }
  sides
}

///|
/// The background of every page (`init_page`): `page_background_color`,
/// then the page background image of the page's side and layout; the title
/// page (`title_page`, an index) takes `title_page_background_color` and
/// `title-page-background-image` instead where they are set.
fn Converter::ink_page_backgrounds(self : Converter, title_page : Int?) -> Unit {
  let pages = self.flow.model.pages
  let color = page_background_color()
  let cache : Map[String, Map[String, BoxImage?]] = Map([])
  for index, page in pages {
    let (w, h) = (page.width_pt, page.height_pt)
    let layout = if w > h { "landscape" } else { "portrait" }
    let side = if (index + 1) % 2 == 1 { "recto" } else { "verso" }
    let is_title = title_page == Some(index)
    let page_color = match (is_title, t_color("title_page_background_color")) {
      (true, Some(c)) => c
      _ => color
    }
    let by_side = match cache.get(layout) {
      Some(sides) => sides
      None => {
        let sides = self.page_bg_images((w, h), layout)
        cache[layout] = sides
        sides
      }
    }
    let mut image = by_side.get(side).unwrap_or(None)
    if is_title {
      match
        self.resolve_background_image(
          Some("title-page-background-image"),
          "title_page_background_image",
          (w, h),
          layout~,
        ) {
        Found(img) => image = Some(img)
        Cleared => image = None
        _ => ()
      }
    }
    let items : Array[@pagelayout.PageItem] = []
    if page_color != rgb_hex(0xFFFFFF) {
      items.push(rect_item(0.0, 0.0, w, h, fill=page_color))
    }
    match image {
      Some(img) =>
        match self.box_image_items(img, 0.0, 0.0, w, h) {
          Some((drawn, _, _)) => items.append(drawn)
          None => ()
        }
      None => ()
    }
    for i, item in items {
      page.items.insert(i, item)
    }
  }
}
