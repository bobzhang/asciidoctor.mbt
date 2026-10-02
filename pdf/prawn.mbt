///|
// The Prawn layer (bobzhang/prawn) the converter lays documents out with,
// and the hooks through which it calls back into the converter.

///|
using @pagelayout {type Color}

///|

///|
/// Re-exported: what `register` and `convert_document` take, and the fonts
/// the default theme names.
pub using @prawn {
  type FontCatalog,
  type IconSet,
  default_font_files,
  default_icon_font_files,
}

///|
using @prawn {
  type Alignment,
  type CodeBackground,
  type Face,
  type Fragment,
  type Flow,
  type Hooks,
  type Line,
  type LineMetrics,
  type PageSetup,
  type Style,
  type TextContext,
  dashed_hrule,
  face_key,
  hrule,
  line_extent,
  line_metrics,
  pdf_anchor_name,
  rect_item,
  rgb_hex,
  source_wrap,
  typeset_lines,
  vrule,
}

///|
/// The hooks of the document being converted: the theme's base font
/// family, unknown fonts reported once, its inline images
/// (InlineImageArranger, InlineImageRenderer) and the pages of its index
/// terms (InlineDestinationMarker).
fn document_hooks() -> Hooks {
  // every hook runs in this document's session, whichever is active
  let session = session()
  {
    base_family: base_font_family(),
    unknown_font: key => {
      with_session(session, () => {
        if !session.unknown_fonts.contains(key) {
          session.unknown_fonts[key] = true
          report(
            "WARNING \{key} is not a known font; using Helvetica instead at <document>",
          )
        }
      })
    },
    image_size: (index, available, font_height) => {
      with_session(session, () => {
        inline_image_size(session.inline_images[index], available, font_height)
      })
    },
    image_items: (flow, index, x, top, w, h) => {
      with_session(session, () => {
        let image = session.inline_images[index]
        match image.svg {
          Some(svg) =>
            match inline_svg_item(flow, svg, x, top, w) {
              Some(item) => [item]
              None => []
            }
          None =>
            [
              Image({
                x_pt: x,
                y_pt: top,
                w_pt: w,
                h_pt: h,
                data: image.data,
                mime: image.mime,
              }),
            ]
        }
      })
    },
    anchor_inked: (name, page) => {
      with_session(session, () => {
        if name.has_prefix("__indexterm-") {
          session.index.link_dest_to_page(name, page)
        }
      })
    },
  }
}

///|
/// A flow over the document's pages (`scratch` for a dry run).
fn new_flow(catalog : FontCatalog, scratch? : Bool = false) -> Flow {
  Flow::new(catalog, session().page_setup, hooks=document_hooks(), scratch~)
}
