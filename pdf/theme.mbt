///|
// The default theme of Ruby asciidoctor-pdf (data/themes/default-theme.yml),
// resolved to numbers. Loading theme YAML is out of scope for the spike;
// every key the converter reads is a constant here, named after the key.

///|
let base_font_family = "Noto Serif"

///|
let mono_font_family = "M+ 1mn"

///|
let base_font_size = 10.5

///|
let base_line_height_length = 12.0

///|
let base_line_height : Double = base_line_height_length / base_font_size

///|
let base_font_color : Color = rgb_hex(0x333333)

///|
let vertical_rhythm = 12.0

///|
let horizontal_rhythm = 12.0

///|
let block_margin_bottom = 12.0

///|
let prose_margin_bottom = 12.0

///|
let link_font_color : Color = rgb_hex(0x428BCA)

///|
let codespan_font_color : Color = rgb_hex(0xB12146)

///|
let heading_margin_top : Double = vertical_rhythm * 0.4

///|
let heading_margin_bottom : Double = vertical_rhythm * 0.9

///|
let heading_min_height_after : Double = base_line_height_length * 1.5

///|
/// `heading_h<n>_font_size`
fn heading_font_size(level : Int) -> Double {
  match level {
    1 => (base_font_size * 2.6).floor()
    2 => (base_font_size * 2.15).floor()
    3 => (base_font_size * 1.7).round()
    4 => (base_font_size * 1.25).round()
    5 => base_font_size
    _ => (base_font_size * 0.85).round()
  }
}

///|
let caption_font_size : Double = base_font_size * 0.95

///|
let caption_margin_inside : Double = vertical_rhythm / 3.0

///|
let code_font_size : Double = base_font_size.ceil()

///|
let code_line_height = 1.25

///|
let code_padding : Double = code_font_size

///|
let code_background_color : Color = rgb_hex(0xF5F5F5)

///|
let code_border_color : Color = rgb_hex(0xCCCCCC)

///|
let code_border_width = 0.75

///|
let list_indent : Double = horizontal_rhythm * 1.5

///|
let list_item_spacing : Double = vertical_rhythm / 2.0

///|
let description_list_term_spacing : Double = vertical_rhythm / 4.0

///|
let description_list_description_indent : Double = horizontal_rhythm * 1.25

///|
let table_border_color : Color = rgb_hex(0xDDDDDD)

///|
let table_border_width = 0.5

///|
let table_head_border_bottom_width : Double = table_border_width * 2.5

///|
let table_cell_padding = 3.0

///|

///|
let table_foot_background_color : Color = rgb_hex(0xF0F0F0)

///|
let admonition_column_rule_color : Color = rgb_hex(0xEEEEEE)

///|
let admonition_column_rule_width = 0.5

///|
/// `admonition_padding`: [top, right, bottom, left]
let admonition_padding : (Double, Double, Double, Double) = (
  vertical_rhythm / 3.0,
  horizontal_rhythm,
  vertical_rhythm / 3.0,
  horizontal_rhythm,
)

///|
let example_border_color : Color = rgb_hex(0xEEEEEE)

///|
let example_border_width = 0.75

///|
let sidebar_background_color : Color = rgb_hex(0xEEEEEE)

///|
let sidebar_border_color : Color = rgb_hex(0xE1E1E1)

///|
let quote_border_color : Color = rgb_hex(0xEEEEEE)

///|
let quote_font_size : Double = (base_font_size * 1.25).round()

///|
let thematic_break_color : Color = rgb_hex(0xEEEEEE)

///|
let footer_font_size : Double = (base_font_size * 0.85).round()

///|
let footer_height : Double = base_line_height_length * 2.5

///|
let footer_border_color : Color = rgb_hex(0xDDDDDD)

///|
let footer_border_width = 0.25

///|
/// Page geometry: A4, margins [0.5in, 0.67in, 0.67in, 0.67in].
let page_width = 595.28

///|
let page_height = 841.89

///|
let margin_top = 36.0

///|
let margin_side : Double = 0.67 * 72.0

///|
let margin_bottom : Double = 0.67 * 72.0
