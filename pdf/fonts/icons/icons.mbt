///|
let bundle : @fonts.Bundle = @fonts.Bundle::from_armoured(bundled_files())

///|
/// prawn-icon 3.0.0's icon fonts, which `icons=font` draws with, by their
/// paths in its `data/fonts`: each set's font and legend (`fas/fa-solid.ttf`
/// and `fas/fas.yml`; the sets are Font Awesome 5's `fas`, `far` and
/// `fab`, Foundation Icons' `fi` and PaymentFont's `pf`).
pub fn fonts() -> @fonts.Bundle {
  bundle
}
