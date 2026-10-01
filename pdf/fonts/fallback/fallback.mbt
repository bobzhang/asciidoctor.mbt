///|
let bundle : @fonts.Bundle = @fonts.Bundle::from_armoured(bundled_files())

///|
/// asciidoctor-pdf 2.3.27's fallback fonts, which its
/// `default-with-font-fallbacks` theme uses, by their names in its
/// `data/fonts`: M+ 1p Fallback (`mplus1p-regular-fallback.ttf`, mostly
/// for CJK) and Noto Emoji (`notoemoji-subset.ttf`).
pub fn fonts() -> @fonts.Bundle {
  bundle
}
