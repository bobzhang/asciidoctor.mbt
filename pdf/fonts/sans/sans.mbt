///|
let bundle : @fonts.Bundle = @fonts.Bundle::from_armoured(bundled_files())

///|
/// asciidoctor-pdf 2.3.27's Noto Sans fonts, which its `default-sans` theme
/// uses, by their names in its `data/fonts`
/// (`notosans-regular-subset.ttf`, `-bold-`, `-italic-`, `-bold_italic-`).
pub fn fonts() -> @fonts.Bundle {
  bundle
}
