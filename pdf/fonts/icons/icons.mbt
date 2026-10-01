///|
let bundle : @fonts.Bundle = @fonts.Bundle::from_armoured(bundled_files())

///|
/// The icon fonts prawn-icon 3.0.0 ships, which `icons=font` draws with, by
/// their paths in its `data/fonts` (`fas/fa-solid.ttf`; the sets are Font
/// Awesome 5's `fas`, `far` and `fab`, Foundation Icons' `fi` and
/// PaymentFont's `pf`), and each set's icon names (`fas/glyphs.txt`:
/// `name: glyph` lines, made from the fonts' glyph names, or Foundation
/// Icons' and PaymentFont's stylesheets, by scripts/pdf_bundle_fonts.mbtx,
/// which checks them against prawn-icon's legends).
pub fn fonts() -> @fonts.Bundle {
  bundle
}
