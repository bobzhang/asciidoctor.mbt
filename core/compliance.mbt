///|
/// Global compliance settings (Ruby `Asciidoctor::Compliance`).
pub(all) struct Compliance {
  mut block_terminates_paragraph : Bool
  mut strict_verbatim_paragraphs : Bool
  mut underline_style_section_titles : Bool
  mut unwrap_standalone_preamble : Bool
  mut attribute_missing : String
  mut attribute_undefined : String
  mut shorthand_property_syntax : Bool
  mut natural_xrefs : Bool
  mut unique_id_start_index : Int
  mut markdown_syntax : Bool
}

///|
fn Compliance::defaults() -> Compliance {
  {
    block_terminates_paragraph: true,
    strict_verbatim_paragraphs: true,
    underline_style_section_titles: true,
    unwrap_standalone_preamble: true,
    attribute_missing: "skip",
    attribute_undefined: "drop-line",
    shorthand_property_syntax: true,
    natural_xrefs: true,
    unique_id_start_index: 2,
    markdown_syntax: true,
  }
}

///|
/// The global compliance settings.
pub let compliance : Compliance = Compliance::defaults()

///|
/// Restores the default compliance settings.
pub fn reset_compliance() -> Unit {
  let d = Compliance::defaults()
  compliance.block_terminates_paragraph = d.block_terminates_paragraph
  compliance.strict_verbatim_paragraphs = d.strict_verbatim_paragraphs
  compliance.underline_style_section_titles = d.underline_style_section_titles
  compliance.unwrap_standalone_preamble = d.unwrap_standalone_preamble
  compliance.attribute_missing = d.attribute_missing
  compliance.attribute_undefined = d.attribute_undefined
  compliance.shorthand_property_syntax = d.shorthand_property_syntax
  compliance.natural_xrefs = d.natural_xrefs
  compliance.unique_id_start_index = d.unique_id_start_index
  compliance.markdown_syntax = d.markdown_syntax
}
