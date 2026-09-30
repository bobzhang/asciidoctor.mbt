///|
// An SVG document ready to draw: its tree, stylesheet and sizing, as
// prawn-svg's `Document`; and what drawing needs from the host (fonts and
// files).

///|
/// A font the host can draw SVG text with.
pub(all) struct SvgFont {
  /// the font's index in the page model
  index : Int
  /// the advance of each UTF-16 code unit of a string at a size, kerning
  /// included (Prawn's `width_of`)
  advances : (String, Double) -> Array[Double]
  /// the font's height at a size: ascender, descender and line gap
  height : (Double) -> Double
}

///|
/// What an SVG is drawn with.
pub(all) struct Environment {
  /// the installed font families (Prawn's `font_families`), each with its
  /// styles: `normal`, `bold`, `italic`, `bold_italic`
  families : Array[(String, Array[String])]
  /// a family's font in a style, if the host can draw it
  load_font : (String, String) -> SvgFont?
  /// the family used when none the SVG names is installed
  fallback_font : String
  /// the bytes of a file an `<image>` names (a path relative to the SVG's
  /// directory, or absolute), if readable
  read_file : (String) -> Bytes?
  /// the font size the document is at where the SVG is drawn (what
  /// `dominant-baseline: middle` measures with, as prawn-svg does)
  ambient_font_size : Double
}

///|
/// A parsed SVG document.
pub struct SvgDocument {
  root : Element
  /// its size, recalculated by `Sizing::resize`
  sizing : Sizing
  /// problems found while drawing (prawn-svg's `warnings`)
  warnings : Array[String]
  priv styles : Map[Int, Array[(String, String)]]
  priv elements_by_id : Map[String, Node]
  priv gradients : Map[String, GradientElement]
  priv mut env : Environment?
}

///|
/// Why an SVG cannot be read.
pub suberror SvgError {
  SvgError(String)
}

///|
/// Parse an SVG document to be drawn in `bounds` (width, height), at
/// `width` and/or `height` when given (prawn-svg's `Document.new` with its
/// `:width` and `:height` options).
pub fn SvgDocument::parse(
  text : String,
  bounds : (Double, Double),
  width? : Double,
  height? : Double,
  preserve_aspect_ratio? : String,
) -> SvgDocument raise SvgError {
  let root = parse_xml(text) catch {
    XmlError(message) => raise SvgError(message)
  }
  let sizing = Sizing::new(
    bounds,
    width?=root.attr("width"),
    height?=root.attr("height"),
    view_box?=root.attr("viewBox"),
    preserve_aspect_ratio?=match preserve_aspect_ratio {
      Some(p) => Some(p)
      None => root.attr("preserveAspectRatio")
    },
  )
  sizing.resize(width?, height?)
  let all = root.descendants()
  {
    root,
    sizing,
    warnings: [],
    styles: element_styles(root, all),
    elements_by_id: {},
    gradients: {},
    env: None,
  }
}

///|
/// The first element of the tree whose `id` is `id` (prawn-svg's XPath
/// fallback for references to elements not processed yet).
fn SvgDocument::find_raw(self : SvgDocument, id : String) -> Element? {
  for e in self.root.descendants() {
    if e.attr("id") == Some(id) {
      return Some(e)
    }
  }
  None
}

///|
/// Draw the document at its sizing (prawn-svg's `Renderer#draw`): the ops
/// of a graphic whose origin is the image's top-left corner, clipped to
/// its size. Nothing, with a warning, when the sizing is invalid.
///
/// The image's top-left corner is at `origin` (points, y down) on a page
/// `page_height` tall, and `stack` is the transformation stack of the
/// Prawn document it is drawn into (see `TransformationStack`).
pub fn SvgDocument::render(
  self : SvgDocument,
  env : Environment,
  origin~ : (Double, Double),
  page_height~ : Double,
  stack~ : TransformationStack,
) -> Array[@pagelayout.GraphicOp] {
  let calls = self.calls(env)
  let ops = []
  if calls is Some(calls) {
    let top = page_height - origin.1
    lower(calls, self, env, ops, stack, (origin.0, top), {
      a: 1,
      b: 0,
      c: 0,
      d: -1,
      e: origin.0,
      f: top,
    })
  }
  ops
}

///|
/// The drawing calls of the document, wrapped as `Renderer#draw` wraps
/// them (a state saved around a clip to the image's box); None when the
/// sizing is invalid.
fn SvgDocument::calls(self : SvgDocument, env : Environment) -> Array[Call]? {
  self.env = Some(env)
  let sizing = self.sizing
  if sizing.invalid {
    self.warnings.push(
      "Zero or negative sizing data means this SVG cannot be rendered",
    )
    return None
  }
  self.warnings.clear()
  self.elements_by_id.clear()
  self.gradients.clear()
  let calls = []
  let root = Node::new(self, Root, Some(self.root), calls, State::new(sizing))
  root.process()
  Some([
    SaveState(
      [
        Rectangle(0, 0, sizing.output_width, sizing.output_height),
        Clip,
        ..calls,
      ],
    ),
  ])
}
