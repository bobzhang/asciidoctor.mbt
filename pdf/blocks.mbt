///|
// Delimited blocks drawn in a frame (code, example, sidebar) and the frame
// itself (asciidoctor-pdf's `theme_fill_and_stroke_block`), styled by the
// theme's `<category>_*` keys.

///|
/// The frame of a block category: its background and border (width,
/// colour, radius), as `theme_fill_and_stroke_block` resolves them; None
/// when it has neither.
priv struct Frame {
  background : Color?
  border_width : Double
  border_color : Color
  /// how far the dashed continuation line stays from the sides
  inset : Double
  /// the colour of the dashed line where the block breaks across pages
  gap_color : Color
  /// how far the dashed line moves out of the block
  shift : Double
}

///|
/// The frame of `category` (`<category>_border_width`, `_border_color`,
/// `_border_radius`, `_background_color`, or `background` in place of the
/// last).
fn frame_of(category : String, background? : Color?) -> Frame? {
  let mut radius_override : Double? = None
  let mut width = match tv(category + "_border_width") {
    Array(items) => {
      radius_override = Some(0.0)
      items.get(0).bind(value_num)
    }
    v => value_num(v)
  }
  if width.unwrap_or(0.0) <= 0.0 {
    width = None
  }
  let bg = match background {
    Some(bg) => bg
    None => t_color(category + "_background_color")
  }
  if width is None && bg is None {
    return None
  }
  let page_bg = page_background_color()
  // `resolve_theme_color :<category>_border_color, base_border_color,
  // page_bg_color`: transparent is the page's colour
  let border_color = match tv(category + "_border_color") {
    Transparent => page_bg
    Null =>
      match tv("base_border_color") {
        Transparent => page_bg
        v => value_color(v).unwrap_or(page_bg)
      }
    v => value_color(v).unwrap_or(page_bg)
  }
  let radius = radius_override.unwrap_or(
    t_num_or(category + "_border_radius", 0.0),
  )
  let (gap_color, shift, border_width) = match width {
    Some(w) =>
      if border_color == page_bg {
        (page_bg, w * 0.5, w)
      } else {
        match bg {
          Some(b) if b != border_color => (b, 0.0, w)
          _ => (page_bg, 0.0, w)
        }
      }
    None => (page_bg, 0.25, 0.0)
  }
  Some({
    background: bg,
    border_width,
    border_color,
    inset: radius + border_width,
    gap_color,
    shift,
  })
}

///|
/// The items that paint `frame` on the part of a block from `top` to
/// `bottom` of one page: the background and border, and a dashed line in
/// the gap colour cutting into the edge where the block continues from or
/// onto another page.
fn Frame::items(
  self : Frame,
  left : Double,
  right : Double,
  top : Double,
  bottom : Double,
  first : Bool,
  last : Bool,
) -> Array[@pagelayout.PageItem] {
  let items = [
    rect_item(
      left,
      top,
      right - left,
      bottom - top,
      fill?=self.background,
      stroke?=if self.border_width > 0.0 {
        Some(self.border_color)
      } else {
        None
      },
      stroke_width=self.border_width,
    ),
  ]
  let width = (if self.border_width > 0.0 { self.border_width } else { 0.5 }) *
    1.2
  if !first {
    items.append(
      dashed_hrule(
        left + self.inset,
        right - self.inset,
        top - self.shift,
        width,
        self.gap_color,
      ),
    )
  }
  if !last {
    items.append(
      dashed_hrule(
        left + self.inset,
        right - self.inset,
        bottom + self.shift,
        width,
        self.gap_color,
      ),
    )
  }
  items
}

///|
/// A category's padding (`<category>_padding`): top, right, bottom, left.
fn padding_of(category : String) -> (Double, Double, Double, Double) {
  t_padding(category + "_padding")
}

///|
/// Whether a category's captions go below the block (`<category>_caption_end:
/// bottom`, formerly `_caption_side`).
fn caption_below(category : String) -> Bool {
  t_str(category + "_caption_end") == Some("bottom")
}

///|
/// asciidoctor-pdf's `convert_code` (listing, literal and source blocks,
/// without syntax highlighting): the content in the `code` font, in the
/// code padding, over the code frame; a stem block's text is shown as it
/// is.
fn Converter::convert_code(
  self : Converter,
  node : @core.Node,
  plain? : Bool = false,
) -> Unit {
  let flow = self.flow
  let (style, line_height) = theme_font(
    base_style(),
    base_line_height(),
    "code",
  )
  let face = flow.font(style)
  let metrics = line_metrics(line_height, face, style.size)
  let chunks = self.code_chunks(node, style, plain~)
  // the highlighter's text colour, for the fragments that set none
  let style = match chunks.font_color {
    Some(color) => { ..style, color, }
    None => style
  }
  let fragments = chunks.fragments
  let (pad_top, pad_right, pad_bottom, pad_left) = padding_of("code")
  // `autofit` (`compute_autofit_font_size`): a smaller font when the widest
  // line does not fit, no smaller than `code_font_size_min` (else
  // `base_font_size_min`); the line metrics stay those of the code font
  let (fragments, style) = if node.has_option("autofit") ||
    node.document().has_attr("autofit-option") {
    let widths = [0.0]
    for fragment in fragments {
      let parts = fragment.text.split("\n").collect()
      for i, part in parts {
        if i > 0 {
          widths.push(0.0)
        }
        widths[widths.length() - 1] += flow.width_of(
          part.to_owned(),
          fragment.style,
        )
      }
    }
    let actual = widths.fold(init=0.0, @cmp.maximum)
    let available = flow.width() - pad_left - pad_right
    if actual > available {
      let adjusted = (available * style.size / actual * 10000.0).floor() /
        10000.0
      let min = match tv("code_font_size_min") {
        Null => tv("base_font_size_min")
        v => v
      }
      let size = match resolve_font_size(min, style.size) {
        Some(m) if adjusted < m => m
        _ => adjusted
      }
      (
        fragments.map(f => {
          ..f,
          style: { ..f.style, size: f.style.size * size / style.size, },
        }),
        { ..style, size, },
      )
    } else {
      (fragments, style)
    }
  } else {
    (fragments, style)
  }
  let below = caption_below("code")
  // arrange_block: the caption and the background are tared, so the block
  // starts on the next page when not even its first line (with the room
  // its bottom padding needs, when it is the last) fits here
  self.arrange_block(keep_together=node.has_option("unbreakable"), node~, fn(
    c,
  ) {
    let flow = c.flow
    c.add_dest(node)
    if node.has_title() && !below {
      flow.tared(() => c.ink_caption(node.captioned_title(), category="code"))
    }
    let start = flow.mark()
    let (left, right) = (flow.left, flow.right)
    flow.move_down(pad_top)
    flow.indent(pad_left, pad_right, fn() {
      let fragments = if chunks.source_wrap {
        match source_wrap(fragments, flow.text(), flow.width()) {
          Some(wrapped) => wrapped
          None => {
            // a line that cannot fit fails the conversion, as Prawn's
            // CannotFit does in Ruby
            session().failure = Some("Prawn::Errors::CannotFit")
            fragments
          }
        }
      } else {
        fragments
      }
      if chunks.highlighted && fragments.is_empty() {
        // no text (an empty block a highlighter left without fragments):
        // Prawn prints no line, only the bottom padding of the line
        // metrics follows
        flow.y += metrics.padding_bottom
      } else {
        flow.typeset(fragments, metrics, style, bottom_gutter=pad_bottom)
      }
    })
    flow.pad_bottom(pad_bottom)
    let frame = match chunks.background {
      Some(bg) => frame_of("code", background=Some(bg))
      None => frame_of("code")
    }
    match frame {
      Some(frame) =>
        flow.underlay(start, fn(top, bottom, first, last) {
          frame.items(left, right, top, bottom, first, last)
        })
      None => ()
    }
  })
  if node.has_title() && below {
    self.ink_caption(node.captioned_title(), bottom=true, category="code")
  }
  self.block_margin_bottom(node)
}

///|
/// A category's font (`theme_font <category>`) over the base font: the
/// style and line height a block's content is set in.
fn category_font(category : String) -> (Style, Double) {
  theme_font(base_style(), base_line_height(), category)
}

///|
/// The admonition label of `name` in its font (`theme_font_cascade
/// [:admonition_label, :admonition_label_<name>]`): the label's style and
/// its text, transformed.
fn admonition_label_font(name : String, text : String) -> (Style, String) {
  let (style, lh) = category_font("admonition_label")
  let (style, _) = theme_font(style, lh, "admonition_label_" + name)
  let text = match style.text_transform {
    Some(transform) => transform_text(text, transform)
    None => text
  }
  // the label is set as it is (`inline_format: false`), in the font
  (
    {
      ..style,
      text_transform: None,
      font_set: true,
      bold: style.doc_bold,
      italic: style.doc_italic,
    },
    text,
  )
}

///|
/// asciidoctor-pdf's `AdmonitionIcons` merged with the theme's
/// `admonition_icon_<name>` (`admonition_icon_data`): the icon set, icon
/// name, colour and size of an admonition type (a type without one takes
/// the note's icon, in the text colour).
fn admonition_icon(name : String) -> (String, String, Color, Double) {
  let (default_name, default_color) = match name {
    "caution" => ("fas-fire", Some(rgb_hex(0xBF3400)))
    "important" => ("fas-exclamation-circle", Some(rgb_hex(0xBF0000)))
    "note" => ("fas-info-circle", Some(rgb_hex(0x19407C)))
    "tip" => ("far-lightbulb", Some(rgb_hex(0x111111)))
    "warning" => ("fas-exclamation-triangle", Some(rgb_hex(0xBF6900)))
    _ => ("fas-info-circle", None)
  }
  let data = match tv("admonition_icon_" + name) {
    Hash(map, ..) => map
    _ => Map([])
  }
  let icon_name = data.get("name").bind(value_str).unwrap_or(default_name)
  let color = data
    .get("stroke_color")
    .bind(value_color)
    .or_some(default_color)
    .unwrap_or(base_font_color())
  let size = data.get("size").bind(value_num).unwrap_or(24.0)
  let (set, glyph_name) = match icon_name.find("-") {
    Some(i) => (icon_name[:i].to_owned(), icon_name[i + 1:].to_owned())
    None => ("fas", icon_name)
  }
  (set, glyph_name, color, size)
}

///|
/// asciidoctor-pdf's `convert_admonition`: the label (or, with
/// `icons=font`, the icon) in a column left of a rule
/// (`admonition_column_rule_*`), the content right of it in the
/// `admonition` font, all in the admonition padding and frame.
fn Converter::admonition_icon_image(
  self : Converter,
  node : @core.Node,
  name : String,
) -> BoxImage? {
  // `convert_admonition` with image icons: the `icon` attribute's image
  // (or `<iconsdir>/<name>.<icontype>`, `get_icon_image_path`) unless the
  // theme's `admonition_icon_<name>` has an `image`, resolved against the
  // theme's directory
  let doc = self.doc
  let has_icon = node.has_attr("icon")
  let theme_image = match tv("admonition_icon_\{name}") {
    Hash(map, ..) =>
      match map.get("image") {
        Some(Null) | None => None
        Some(v) => Some(v.to_ruby_s())
      }
    _ => None
  }
  let (path, format) = match theme_image {
    Some(image) if !has_icon => {
      let themesdir = current_theme.val.dir()
      let path = with_attrs(doc, [("imagesdir", themesdir)], () => {
        apply_subs_discretely(doc, image)
      })
      (
        @theme.resolve_theme_asset(theme_files(doc), path, theme_dir=themesdir),
        image_target_and_format(path, None).1,
      )
    }
    _ => {
      // the data-uri attribute is off while the icon's path is computed
      let data_uri = doc.attr("data-uri")
      if data_uri is Some(_) {
        ignore(doc.remove_attr("data-uri"))
      }
      let uri = node.icon_uri(name)
      match data_uri {
        Some(v) => ignore(doc.set_attr("data-uri", value=Str(v)))
        None => ()
      }
      let (_, format) = image_target_and_format(uri, None)
      let path = if uri.has_prefix("/") {
        uri
      } else {
        doc.normalize_system_path(uri)
      }
      (path, format)
    }
  }
  match doc.vfs().read(path) {
    Some(data) =>
      Some({
        data,
        svg: format == "svg",
        path,
        fit: None,
        width: None,
        height: None,
        position: "center",
        vposition: "center",
        link: None,
        alt: None,
        pdf_page: None,
      })
    None => {
      warning(
        "admonition icon image\{if has_icon { "" } else { " for " + name.to_upper() }} not found or not readable: \{path}",
        node,
      )
      None
    }
  }
}

///|
fn Converter::convert_admonition(self : Converter, node : @core.Node) -> Unit {
  let flow = self.flow
  let name = node.attr("name").unwrap_or("")
  let label_align = t_align("admonition_label_text_align", Center)
  let valign = t_str("admonition_label_vertical_align").unwrap_or("middle")
  let min_width = t_num("admonition_label_min_width")
  // `icons=font`: the admonition's icon in a column one and a half times as
  // wide as it; other icons (images) are left out, and the label is text
  let icon = match self.doc.attr("icons") {
    Some("font") if !node.has_attr("icon") => {
      let (set, icon_name, color, size) = admonition_icon(name)
      match flow.catalog.icon_glyph(set, icon_name) {
        Some(glyph) => Some((set, glyph, color, size))
        None => None
      }
    }
    _ => None
  }
  // other icons are images: the `icon` attribute's, else the theme's
  // `admonition_icon_<name>` image, else `<iconsdir>/<name>.<icontype>`
  let icon_image = match self.doc.attr("icons") {
    Some(icons) if icon is None && (icons != "font" || node.has_attr("icon")) =>
      self.admonition_icon_image(node, name)
    _ => None
  }
  let (label_style, label) = admonition_label_font(
    name,
    sanitize(node.caption().unwrap_or(name)),
  )
  let label_lines = if icon is Some(_) {
    []
  } else {
    typeset_lines(
      [{ text: label, style: label_style, anchor: None, }],
      flow.text(),
      1.0e6,
      Left,
    )
  }
  let natural_width = match icon {
    Some((_, _, _, size)) => size * 1.5
    None =>
      if label_lines.length() > 0 {
        label_lines[0].fit_width
      } else {
        0.0
      }
  }
  let label_width = match (icon_image, min_width) {
    // an image takes `admonition_label_min_width`, else 36pt
    (Some(_), Some(w)) => w
    (Some(_), None) => 36.0
    (None, Some(w)) if w > natural_width => w
    _ => natural_width
  }
  let (pad_top, pad_right, pad_bottom, pad_left) = admonition_padding()
  let (_, label_pad_right, _, label_pad_left) = match
    tv("admonition_label_padding") {
    Null => admonition_padding()
    v => expand_rect(v)
  }
  let label_face = flow.font(label_style)
  let rule_width = admonition_column_rule_width()
  let rule_color = match tv("admonition_column_rule_color") {
    Null => base_border_color()
    Transparent => None
    v => value_color(v)
  }
  let (content_style, content_lh) = category_font("admonition")
  // arrange_block: the label and the rule are drawn once the extent is
  // known, so they take no part in keeping the block on this page; the
  // title is content
  self.arrange_block(keep_together=node.has_option("unbreakable"), node~, fn(
    c,
  ) {
    let flow = c.flow
    c.add_dest(node)
    let start = flow.mark()
    let (left, right) = (flow.left, flow.right)
    let box_left = flow.left + label_pad_left
    let rule_x = box_left + label_width + label_pad_right
    flow.indent(label_pad_left, pad_right, fn() {
      flow.move_down(pad_top)
      flow.indent(label_width + label_pad_right + pad_left, 0.0, fn() {
        if node.has_title() {
          c.ink_caption(node.title().unwrap_or(""), category="admonition")
        }
        c.push_gutter(node, pad_bottom)
        with_font(content_style, content_lh, () => c.traverse(node))
        c.pop_gutter()
      })
      flow.pad_bottom(pad_bottom)
    })
    let frame = frame_of("admonition")
    flow.underlay(start, fn(top, bottom, first, last) {
      let items = match frame {
        Some(frame) => frame.items(left, right, top, bottom, first, last)
        None => []
      }
      match rule_color {
        Some(color) if rule_width > 0.0 =>
          items.push(vrule(rule_x, top, bottom, rule_width, color))
        _ => ()
      }
      match icon {
        Some((set, glyph, color, icon_size)) if first => {
          // the icon, no taller than the label box, centred in it: moved
          // down by half the room it leaves, then set as Prawn's `text`
          // (the first baseline an ascender below the top), across the
          // column (`fit_icon_to_bounds`, `icon`)
          let height = bottom - top
          let size = @cmp.minimum(height, icon_size)
          let offset = if valign == "middle" {
            @cmp.maximum((height - size) * 0.5, 0.0)
          } else {
            0.0
          }
          let style = {
            ..text_style(family=set, size~, color~),
            font_set: true,
          }
          let lines = typeset_lines(
            [{ text: glyph, style, anchor: None, }],
            flow.text(),
            label_width,
            label_align,
          )
          let face = flow.font(style)
          if lines.length() > 0 {
            items.append(
              flow.line_items(
                lines[0],
                box_left,
                top + offset + face.ascender_pt(size),
              ),
            )
          }
        }
        _ if first &&
          (match icon_image {
            Some(img) => {
              // the image in the label box, as wide as the label column
              // (a raster image no wider than its natural size), no taller
              // than the box
              let height = bottom - top
              let img = match image_info(img.data) {
                Some((px_w, px_h, _)) if !img.svg => {
                  let mut w = @cmp.minimum(px_w.to_double() * 0.75, label_width)
                  let h = w * px_h.to_double() / px_w.to_double()
                  if h > height {
                    w = w * height / h
                  }
                  { ..img, width: Some(w), }
                }
                _ => { ..img, width: Some(label_width), height: Some(height), }
              }
              let img = {
                ..img,
                position: match label_align {
                  Center => "center"
                  Right => "right"
                  _ => "left"
                },
                vposition: if valign == "middle" {
                  "center"
                } else {
                  valign
                },
              }
              match c.box_image_items(img, box_left, top, label_width, height) {
                Some((drawn, _, _)) => {
                  items.append(drawn)
                  true
                }
                None => false
              }
            }
            None => false
          }) => ()
        _ =>
          if first && label_lines.length() > 0 {
            // the label is centred vertically on the part of the block on
            // its first page, and across its column
            // (`height_of_typeset_text label, line_height: 1`: the line gap
            // above the text, then its ascender and descender)
            let a = label_face.ascender_pt(label_style.size)
            let d = label_face.descender_pt(label_style.size)
            let gap = label_face.line_gap_pt(label_style.size)
            let centring = if valign == "middle" {
              @cmp.maximum((bottom - top - (gap + a + d)) / 2.0, 0.0)
            } else {
              0.0
            }
            let offset = centring + gap
            let x = match label_align {
              Center =>
                box_left + (label_width - label_lines[0].fit_width) / 2.0
              Right => box_left + label_width - label_lines[0].fit_width
              _ => box_left
            }
            items.append(flow.line_items(label_lines[0], x, top + offset + a))
          }
      }
      items
    })
  })
  self.block_margin_bottom(node)
}

///|
fn Converter::convert_example(self : Converter, node : @core.Node) -> Unit {
  if node.has_option("collapsible") {
    self.convert_collapsible(node)
    return
  }
  self.framed_block(node, "example", caption=true)
}

///|
fn Converter::convert_sidebar(self : Converter, node : @core.Node) -> Unit {
  self.framed_block(node, "sidebar", caption=false)
}

///|
/// asciidoctor-pdf's `convert_pass`: the content as it is, in the code font
/// and the base colour, with no box around it.
fn Converter::convert_pass(self : Converter, node : @core.Node) -> Unit {
  let flow = self.flow
  let (style, line_height) = category_font("code")
  let style = { ..style, color: base_font_color(), }
  let face = flow.font(style)
  flow.typeset(
    [{ text: guard_indentation(node.content()), style, anchor: None, }],
    line_metrics(line_height, face, style.size),
    style,
  )
  self.block_margin_bottom(node)
}

///|
/// asciidoctor-pdf's `convert_video` and `convert_audio` without a poster
/// image: a play symbol (the `fas-play` icon with `icons=font`), the link
/// to the media and its kind, then the caption below.
fn Converter::convert_media(
  self : Converter,
  node : @core.Node,
  kind : String,
) -> Unit {
  let target = node.attr("target").unwrap_or("")
  let (path, what) = match node.attr("poster") {
    Some("youtube") if kind == "video" =>
      ("https://www.youtube.com/watch?v=\{target}", "YouTube video")
    Some("vimeo") if kind == "video" =>
      ("https://vimeo.com/\{target}", "Vimeo video")
    Some(poster) if kind == "video" && poster != "" => {
      unsupported("block", "video poster image", node)
      (node.media_uri(target), kind)
    }
    _ => (node.media_uri(target), kind)
  }
  self.add_dest(node)
  let play = match
    (self.doc.attr("icons"), self.flow.catalog.icon_glyph("fas", "play")) {
    (Some("font"), Some(glyph)) => "<font name=\"fas\">\{glyph}</font>"
    _ => "\u{25ba}"
  }
  self.ink_prose(
    "\{play}\u{a0}<a href=\"\{path}\">\{path}</a> <em>(\{what})</em>",
    normalize=false,
    margin_bottom=0.0,
  )
  if node.has_title() {
    self.ink_caption(node.title().unwrap_or(""), bottom=true)
  }
  self.block_margin_bottom(node)
}

///|
/// asciidoctor-pdf's `convert_abstract`: its title in the `abstract_title`
/// font, then its paragraphs in the `abstract` font, the first line of the
/// first one in `abstract_first_line_font_style` (and colour); other
/// blocks as usual.
fn Converter::convert_abstract(self : Converter, node : @core.Node) -> Unit {
  self.add_dest(node)
  self.outdent_section(() => self.ink_abstract(node))
}

///|
fn Converter::ink_abstract(self : Converter, node : @core.Node) -> Unit {
  let flow = self.flow
  if t_set("abstract_padding") {
    unsupported("theme", "abstract_padding", node)
  }
  if node.has_title() {
    let (style, _) = category_font("abstract_title")
    flow.margin(heading_margin_top())
    self.ink_prose(
      node.title().unwrap_or(""),
      style~,
      align=t_align("abstract_title_text_align", self.text_align),
      margin_bottom=heading_margin_bottom(),
      line_height=t_num("heading_line_height").unwrap_or(base_line_height()),
    )
  }
  let (style, line_height) = category_font("abstract")
  let align = t_align("abstract_text_align", self.text_align)
  // the first line's style (`abstract_first_line_font_style`, `_font_color`)
  let first = {
    let mut first = style
    match t_str("abstract_first_line_font_style") {
      Some(fs) => {
        let (b, i) = font_style_of(fs)
        first = match fs {
          "normal" =>
            {
              ..first,
              bold: false,
              italic: false,
              font_set: false,
              doc_bold: false,
              doc_italic: false,
            }
          "normal_italic" => { ..first, doc_bold: false, doc_italic: true, }
          _ =>
            {
              ..first,
              doc_bold: first.doc_bold || b,
              doc_italic: first.doc_italic || i,
            }
        }
      }
      None => ()
    }
    match t_color("abstract_first_line_font_color") {
      Some(color) => first = { ..first, color, }
      None => ()
    }
    match t_str("abstract_first_line_text_transform") {
      Some(t) => first = { ..first, text_transform: Some(t), }
      None => ()
    }
    first
  }
  let has_first = t_set("abstract_first_line_font_style") ||
    t_set("abstract_first_line_font_color") ||
    t_set("abstract_first_line_text_transform")
  let mut first_line = has_first
  if node.has_blocks() {
    for child in node.blocks {
      if child.context != Paragraph {
        self.convert_block(child)
        continue
      }
      child.document().playback_attributes(child.attributes)
      self.add_dest(child)
      if child.has_title() {
        self.ink_caption(child.title().unwrap_or(""))
      }
      self.ink_prose(
        child.content(),
        style~,
        align=text_align_from_roles(child.roles(), query_theme=true).unwrap_or(
          align,
        ),
        margin_bottom=0.0,
        line_height~,
        bottom_gutter=self.gutter(child),
        first_line_style?=if first_line { Some(first) } else { None },
        // convert_paragraph: the indent goes by the role's alignment, else
        // the document's (not the abstract's)
        text_indent=paragraph_text_indent(
          child,
          text_align_from_roles(child.roles(), query_theme=true).unwrap_or(
            self.text_align,
          ),
        ),
      )
      first_line = false
      // convert_paragraph's insert_margin_bottom
      match next_enclosed_block(child) {
        Some(next) =>
          match t_num("prose_margin_inner") {
            Some(inner) if next.context == Paragraph => flow.margin(inner)
            _ => flow.margin(prose_margin_bottom())
          }
        None => ()
      }
    }
  } else {
    let text = node.content()
    if !text.is_empty() {
      let align = role_align(node.roles(), align)
      self.ink_prose(
        text,
        style~,
        align~,
        margin_bottom=0.0,
        line_height~,
        first_line_style?=if has_first { Some(first) } else { None },
        text_indent=if align is (Justify | Left) {
          t_num_or("prose_text_indent", 0.0)
        } else {
          0.0
        },
      )
    }
  }
  self.block_margin_bottom(node)
}

///|
/// asciidoctor-pdf's `convert_collapsible`: an example block with the
/// `collapsible` option is its title (default `Details`) after a
/// down-pointing triangle, as a caption, then its content indented by the
/// triangle's width; arranged when it has an id.
fn Converter::convert_collapsible(self : Converter, node : @core.Node) -> Unit {
  let marker = "\u{25bc} "
  let title = marker + node.title().unwrap_or("Details")
  let (caption_style, _) = category_font("caption")
  let indent_by = self.flow.width_of(marker, caption_style)
  let body = fn(c : Converter) {
    c.add_dest(node)
    c.flow.tared(() => c.ink_caption(title))
    c.flow.indent(indent_by, 0.0, () => c.traverse(node))
  }
  if !self.flow.at_page_top() &&
    (node.id is Some(_) || node.has_option("unbreakable")) {
    self.arrange_block(
      keep_together=node.has_option("unbreakable"),
      node~,
      body,
    )
  } else {
    body(self)
  }
  self.block_margin_bottom(node)
}

///|
/// A padded block in a frame (example, sidebar), in `arrange_block`: its
/// destination, then its caption (example) or title (sidebar, in the
/// `sidebar_title` font), both tared, then its content in the category's
/// font; the frame is the category's (`theme_fill_and_stroke_block`).
fn Converter::framed_block(
  self : Converter,
  node : @core.Node,
  category : String,
  caption~ : Bool,
) -> Unit {
  let (pad_top, pad_right, pad_bottom, pad_left) = padding_of(category)
  let below = caption && caption_below(category)
  let (content_style, content_lh) = category_font(category)
  self.arrange_block(keep_together=node.has_option("unbreakable"), node~, fn(
    c,
  ) {
    let flow = c.flow
    c.add_dest(node)
    if caption && !below && node.has_title() {
      flow.tared(() => c.ink_caption(node.captioned_title(), category~))
    }
    let start = flow.mark()
    let (left, right) = (flow.left, flow.right)
    flow.move_down(pad_top)
    flow.indent(pad_left, pad_right, fn() {
      if !caption && node.has_title() {
        let (style, _) = category_font(category + "_title")
        flow.tared(() => {
          c.ink_prose(
            node.title().unwrap_or(""),
            style~,
            align=match t_str(category + "_title_text_align") {
              Some(a) => alignment_of(a)
              None => t_align("heading_text_align", c.text_align)
            },
            margin_bottom=heading_margin_bottom(),
            line_height=t_num("heading_line_height").unwrap_or(
              base_line_height(),
            ),
          )
        })
      }
      c.push_gutter(node, pad_bottom)
      with_font(content_style, content_lh, () => c.traverse(node))
      c.pop_gutter()
    })
    flow.pad_bottom(pad_bottom)
    match frame_of(category) {
      Some(frame) =>
        flow.underlay(start, fn(top, bottom, first, last) {
          frame.items(left, right, top, bottom, first, last)
        })
      None => ()
    }
  })
  if below && node.has_title() {
    self.ink_caption(node.captioned_title(), bottom=true, category~)
  }
  self.block_margin_bottom(node)
}

///|
/// asciidoctor-pdf's `convert_quote_or_verse`: the content in the
/// category's padding and font, a rule down its left side
/// (`<category>_border_left_width`, `_border_color`) or a frame, then the
/// attribution in the `<category>_cite` font.
fn Converter::convert_quote(self : Converter, node : @core.Node) -> Unit {
  let category = if node.context == Verse { "verse" } else { "quote" }
  let (pad_top, pad_right, pad_bottom, pad_left) = padding_of(category)
  let border_color = match tv(category + "_border_color") {
    Null => base_border_color()
    Transparent => None
    v => value_color(v)
  }
  let left_width = match t_num(category + "_border_left_width") {
    Some(w) if w > 0.0 && border_color is Some(_) => Some(w)
    _ => None
  }
  let attribution = node.attr("attribution")
  let (style, line_height) = category_font(category)
  // arrange_block: the destination, the caption (tared), then the content
  // in the padding, whose bottom the last line keeps clear of unless an
  // attribution follows
  self.arrange_block(keep_together=node.has_option("unbreakable"), node~, fn(
    c,
  ) {
    let flow = c.flow
    c.add_dest(node)
    if node.has_title() {
      flow.tared(() => c.ink_caption(node.title().unwrap_or(""), category~))
    }
    let start = flow.mark()
    let (left, right) = (flow.left, flow.right)
    flow.move_down(pad_top)
    flow.indent(pad_left, pad_right, fn() {
      if attribution is None {
        c.push_gutter(node, pad_bottom)
      } else {
        c.gutters.push(None)
      }
      if node.context == Verse {
        c.ink_prose(
          guard_indentation(node.content()),
          style~,
          align=role_align(node.roles(), Left),
          margin_bottom=0.0,
          line_height~,
          normalize=false,
          bottom_gutter=c.gutter(node),
        )
      } else if !node.has_blocks() {
        // a quoted paragraph (`[quote]` on a paragraph) carries its text
        // itself (`traverse`)
        let text = node.content()
        if !text.is_empty() {
          c.ink_prose(
            text,
            style~,
            align=role_align(node.roles(), c.text_align),
            margin_bottom=0.0,
            line_height~,
            bottom_gutter=c.gutter(node),
          )
        }
      } else {
        with_font(style, line_height, () => c.traverse(node))
      }
      c.pop_gutter()
      match attribution {
        Some(attribution) => {
          flow.margin(block_margin_bottom())
          let cite = match node.attr("citetitle") {
            Some(title) => "\{attribution}, \{title}"
            None => attribution
          }
          let (cite_style, cite_lh) = theme_font(
            base_style(),
            base_line_height(),
            category + "_cite",
          )
          c.ink_prose(
            "\u{2014} \{cite}",
            style=cite_style,
            align=Left,
            margin_bottom=0.0,
            line_height=cite_lh,
            normalize=false,
          )
        }
        None => ()
      }
    })
    flow.pad_bottom(pad_bottom)
    let frame = if left_width is None { frame_of(category) } else { None }
    flow.underlay(start, fn(top, bottom, first, last) {
      let items = match frame {
        Some(frame) => frame.items(left, right, top, bottom, first, last)
        None => []
      }
      match (left_width, border_color) {
        (Some(w), Some(color)) =>
          items.push(vrule(left + w / 2.0, top, bottom, w, color))
        _ => ()
      }
      items
    })
  })
  self.block_margin_bottom(node)
}

///|
fn Converter::convert_open(self : Converter, node : @core.Node) -> Unit {
  if node.style == Some("abstract") {
    self.convert_abstract(node)
    return
  }
  // a titled open block, or one with an id, is arranged: its caption is
  // tared, so it moves on with the content after it
  if !self.flow.at_page_top() &&
    (node.has_title() || node.id is Some(_) || node.has_option("unbreakable")) {
    self.arrange_block(keep_together=node.has_option("unbreakable"), node~, fn(
      c,
    ) {
      c.add_dest(node)
      if node.has_title() {
        c.flow.tared(() => c.ink_caption(node.title().unwrap_or("")))
      }
      c.traverse(node)
    })
  } else {
    self.add_dest(node)
    if node.has_title() {
      self.ink_caption(node.title().unwrap_or(""))
    }
    self.traverse(node)
  }
}

///|
/// asciidoctor-pdf's `convert_thematic_break`: a rule
/// (`thematic_break_border_*`) in the thematic break padding.
fn Converter::convert_thematic_break(
  self : Converter,
  node : @core.Node,
) -> Unit {
  let flow = self.flow
  let (top, right, bottom, left) = match tv("thematic_break_padding") {
    Null =>
      (
        t_num_or("thematic_break_margin_top", 0.0),
        0.0,
        t_num_or("thematic_break_margin_top", 0.0),
        0.0,
      )
    v => expand_rect(v)
  }
  flow.move_down(top)
  match tv("thematic_break_border_color") {
    Transparent | Null => ()
    v =>
      match value_color(v) {
        Some(color) =>
          flow.push(
            hrule(
              flow.left + left,
              flow.right - right,
              flow.y,
              t_num_or("thematic_break_border_width", 0.5),
              color,
            ),
          )
        None => ()
      }
  }
  flow.move_down(bottom)
  self.block_margin_bottom(node)
}

///|
/// Footnotes not yet inked (asciidoctor-pdf's `ink_footnotes`), in the
/// `footnotes` font `footnotes_item_spacing` apart: at the bottom of the
/// page with `footnotes_margin_top: auto`, else that far below the
/// content; after the document, and in a book after each chapter. Labels
/// count from the first footnote inked here.
fn Converter::ink_footnotes(self : Converter, node : @core.Node) -> Unit {
  let footnotes = self.doc.footnotes()
  if footnotes.length() <= session().rendered_footnotes {
    return
  }
  let pending = footnotes[session().rendered_footnotes:].to_owned()
  let flow = self.flow
  let is_last = match self.doc.blocks.last() {
    Some(last) => physical_equal(last, node)
    None => false
  }
  if node.context == Document || is_last {
    flow.margin(block_margin_bottom())
  }
  let bottom_aligned = match tv("footnotes_margin_top") {
    Str("auto") => true
    v => {
      flow.margin(value_num(v).unwrap_or(0.0))
      false
    }
  }
  let (style, line_height) = category_font("footnotes")
  let spacing = t_num_or("footnotes_item_spacing", 0.0)
  let face = flow.font(style)
  let metrics = line_metrics(line_height, face, style.size)
  let offset = session().rendered_footnotes
  let texts = pending.map(fn(fn_) {
    "<a id=\"_footnotedef_\{fn_.index}\"></a>[<a anchor=\"_footnoteref_\{fn_.index}\">\{fn_.index - offset}</a>] \{fn_.text}"
  })
  if bottom_aligned {
    let mut height = 0.0
    for text in texts {
      height += flow.height_of(parse_formatted(text, style), metrics, style) +
        spacing
    }
    if height < flow.cursor() {
      flow.move_down(flow.cursor() - height - 0.0001)
    }
  }
  if self.doc.has_attr("footnotes-title") {
    unsupported("attribute", "footnotes-title", node)
  }
  for text in texts {
    self.ink_prose(text, style~, margin_bottom=spacing, line_height~)
  }
  if !flow.scratch {
    // a later reference to one of these (an xref footnote) shows its label,
    // with the chapter it is in
    if node.context == Section {
      let xreftext = node
        .xreftext(xrefstyle?=self.doc.attr("xrefstyle"))
        .unwrap_or("")
      for fn_ in pending {
        session().footnote_labels[fn_.index] = "\{fn_.index - offset} - \{xreftext}"
      }
    }
    session().rendered_footnotes = footnotes.length()
  }
}
