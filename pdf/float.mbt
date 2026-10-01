///|
// Image floats (asciidoctor-pdf's `init_float_box` and
// `ink_paragraph_in_float_box`): a block image with `float=left` or
// `float=right` narrower than the content area leaves the space beside it
// to the paragraphs that follow, which wrap into it; text that does not
// fit continues below at the full width.

///|
/// The space beside a floated image, in flow coordinates (y down).
priv struct FloatBox {
  page : Int
  /// the top of the image (its caption included)
  top : Double
  /// the bottom of the box: the image's bottom plus the bottom gap, or the
  /// page's bottom when that comes first
  bottom : Double
  left : Double
  width : Double
  height : Double
  /// the bottom gap (`image_float_gap`'s second value)
  gap_bottom : Double
}

///|
/// Whether a block wraps around a float (`supports_float_wrapping?`).
fn supports_float_wrapping(node : @core.Node) -> Bool {
  node.context == Paragraph
}

///|
/// `init_float_box`: the box beside a `block_width` × `block_height` block
/// floated to `float_to`, inked above the cursor; the cursor goes back up
/// to the block's top.
fn Converter::init_float_box(
  self : Converter,
  block_width : Double,
  block_height : Double,
  float_to : String,
) -> Unit {
  let flow = self.flow
  let (gap_side, gap_bottom) = match tv("image_float_gap") {
    Array(items) =>
      (
        items.get(0).bind(value_num).unwrap_or(12.0),
        items.get(1).bind(value_num).unwrap_or(6.0),
      )
    v =>
      match value_num(v) {
        Some(g) => (g, g)
        None => (12.0, 6.0)
      }
  }
  let float_w = block_width + gap_side
  let float_h = block_height + gap_bottom
  let left = flow.left + (if float_to == "right" { 0.0 } else { float_w })
  let top = flow.y - block_height
  let width = flow.width() - float_w
  // the cursor at the block's top, as Prawn measures it
  let height = @cmp.minimum(flow.bottom - top, float_h)
  flow.y = top
  self.float_box = Some({
    page: flow.page,
    top,
    bottom: top + height,
    left,
    width,
    height,
    gap_bottom,
  })
}

///|
/// Prawn's formatted text box with a height (`text_box`): the lines of
/// `fragments` set `width` wide from `x` (the first one `text_indent`
/// further in, Prawn's `indent_paragraphs`), the first hanging from the
/// cursor plus the line padding, as many as fit in `height`. Returns the
/// fragments that did not fit and the baseline of the last line inked
/// (None when none was); the cursor does not move.
fn Flow::typeset_box(
  self : Flow,
  fragments : Array[Fragment],
  metrics : LineMetrics,
  base : Style,
  align~ : Alignment,
  x~ : Double,
  width~ : Double,
  height~ : Double,
  text_indent~ : Double,
) -> (Array[Fragment], Double?) {
  self.last_line = None
  let base_face = self.font(base)
  let top = self.y + metrics.padding_top
  let mut remaining = self.catalog.apply_fallbacks(fragments)
  let mut baseline = 0.0
  let mut placed = 0
  let mut last : Double? = None
  while !remaining.is_empty() {
    let indent = if placed == 0 { text_indent } else { 0.0 }
    let (line, rest) = split_first_line(
      remaining,
      remaining,
      self.catalog,
      width - indent,
      align,
    )
    let (a, d, h) = line_extent(line, base_face, base.size, false)
    let next = if placed == 0 { a } else { baseline + h + metrics.leading }
    if next + d > height + 0.0001 {
      break
    }
    baseline = next
    self.ink_line(line, x + indent, top + baseline)
    self.last_line = Some((line, self.page, top + baseline))
    self.last_line_first = placed == 0
    last = Some(top + baseline)
    placed += 1
    remaining = rest
  }
  (remaining, last)
}

///|
/// `ink_paragraph_in_float_box`: `node`'s text set in the float box from
/// the cursor down; what does not fit continues below at the full width.
/// The box stays for the next paragraph while there is room left in it.
fn Converter::ink_paragraph_in_float_box(
  self : Converter,
  node : @core.Node,
  float_box : FloatBox,
  style : Style,
  align : Alignment,
  line_height : Double,
  text_indent : Double,
) -> Unit {
  let flow = self.flow
  self.float_box = None
  let face = flow.font(style)
  let metrics = line_metrics(line_height, face, style.size)
  // allocate the space of at least one empty line below the block
  let line_height_length = line_height * style.size +
    metrics.leading +
    metrics.padding_top
  let start_page = float_box.page
  let start_y = flow.y
  let block_bottom = float_box.bottom - float_box.gap_bottom
  let height = @cmp.minimum(
    flow.cursor(),
    float_box.height - (start_y - float_box.top) + line_height_length,
  )
  let final_gap = face.descender_pt(style.size) + metrics.padding_bottom
  let (overflow, end_y) = flow.typeset_box(
    parse_formatted(node.content(), style),
    metrics,
    style,
    align~,
    x=float_box.left,
    width=float_box.width,
    height~,
    text_indent~,
  )
  match end_y {
    Some(y) => flow.y = y + final_gap
    None => ()
  }
  let next = next_enclosed_block(node)
  let insert_margin_bottom = () => {
    match next {
      Some(next) =>
        match t_num("prose_margin_inner") {
          Some(inner) if next.context == Paragraph => flow.margin(inner)
          _ => flow.margin(prose_margin_bottom())
        }
      None => ()
    }
  }
  if overflow.is_empty() {
    match next {
      Some(next_block) if supports_float_wrapping(next_block) => {
        insert_margin_bottom()
        if flow.page == start_page && flow.y < start_y + height {
          self.float_box = Some(float_box)
        }
      }
      _ =>
        // the cursor after the last line (`end_cursor` less the final gap)
        match end_y {
          Some(_) if flow.y < block_bottom => {
            flow.y = block_bottom
            self.block_margin_bottom(node)
          }
          _ => insert_margin_bottom()
        }
    }
  } else {
    let indent = if end_y is None {
      if start_y < float_box.bottom {
        flow.y = float_box.bottom
      }
      text_indent
    } else {
      0.0
    }
    flow.typeset(overflow, metrics, style, align~, text_indent=indent)
    insert_margin_bottom()
  }
}

///|
/// A block image's `float` (`left` or `right`), when it has one.
fn image_float(node : @core.Node) -> String? {
  match node.attr("float") {
    Some("left" | "right") as f => f
    _ => None
  }
}

///|
/// The caption's `max_width` of a block image: `image_caption_max_width`,
/// `fit-content` when the image floats.
fn image_caption_max_width(node : @core.Node) -> String? {
  let max_width = value_str(tv("image_caption_max_width"))
  if image_float(node) is Some(_) &&
    !(max_width is Some(m) && m.has_prefix("fit-content")) {
    Some("fit-content")
  } else {
    max_width
  }
}

///|
/// The alignment of an image caption (`image_caption_align`, else
/// `caption_align`; `inherit` takes the image's).
fn Converter::image_caption_align(
  self : Converter,
  block_align : Alignment,
) -> Alignment {
  let value = match tv("image_caption_align") {
    Null => tv("caption_align")
    v => v
  }
  match value_str(value) {
    Some("inherit") => block_align
    Some(a) => alignment_of(a)
    None => self.text_align
  }
}

///|
/// The height a block image's caption (below it) takes, its inside margin
/// included, measured as wide as `ink_caption` sets it for a block
/// `block_width` wide (the explicit width, when there is one).
fn Converter::image_caption_height(
  self : Converter,
  node : @core.Node,
  alignment : String,
  block_width : Double?,
) -> Double {
  if !node.has_title() {
    return 0.0
  }
  let flow = self.flow
  let style = Style::new(size=caption_font_size(), doc_italic=true)
  let block_align = alignment_of(alignment)
  let (left, right) = caption_indents(
    flow.width(),
    self.image_caption_align(block_align),
    Some(block_align),
    block_width,
    image_caption_max_width(node),
  )
  flow.indent(left, right, () => {
    flow.height_of(
      parse_formatted(node.captioned_title(), style, normalize=false),
      line_metrics(base_line_height(), flow.font(style), caption_font_size()),
      style,
    )
  }) +
  caption_margin_inside()
}

///|
/// Whether block image captions go above the image (`image_caption_end:
/// top`) rather than below it.
fn image_caption_on_top() -> Bool {
  t_str("image_caption_end") == Some("top")
}

///|
/// A block image's caption, when it has one and it goes at this end
/// (`top`: above the image), as wide as `max_width` allows for an image
/// `rendered_w` wide.
fn Converter::ink_image_caption(
  self : Converter,
  node : @core.Node,
  alignment : String,
  rendered_w : Double,
  top~ : Bool,
) -> Unit {
  if node.has_title() && image_caption_on_top() == top {
    self.ink_caption(
      node.captioned_title(),
      bottom=!top,
      category="image",
      block_align=alignment_of(alignment),
      block_width=rendered_w,
      max_width?=image_caption_max_width(node),
    )
  }
}

///|
/// A block image's caption below it, then its bottom margin, or the float
/// box beside it when it floats and a paragraph follows (the end of
/// asciidoctor-pdf's `convert_image`).
fn Converter::finish_image(
  self : Converter,
  node : @core.Node,
  alignment : String,
  rendered_w : Double,
  rendered_h : Double,
  caption_height : Double,
) -> Unit {
  self.ink_image_caption(node, alignment, rendered_w, top=false)
  if self.pinned {
    return
  }
  match (image_float(node), next_enclosed_block(node)) {
    (Some(float_to), Some(next)) if supports_float_wrapping(next) &&
      rendered_w < self.flow.width() =>
      self.init_float_box(rendered_w, rendered_h + caption_height, float_to)
    _ => self.block_margin_bottom(node)
  }
}
