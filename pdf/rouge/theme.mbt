///|
// Rouge's themes (lib/rouge/theme.rb, themes/*.rb, and asciidoctor-pdf's
// asciidoctor_pdf_default): the style of each token type, generated from
// Rouge itself (themes_data.mbt).

///|
/// The style a theme gives a token type (Rouge's `Theme::Style`): colors as
/// the theme writes them (`#888`, `#a61717`), unset when None.
pub(all) struct TokenStyle {
  fg : String?
  bg : String?
  bold : Bool
  italic : Bool
  underline : Bool
}

///|
/// A Rouge theme: the styles it sets (or inherits) by token type.
pub struct Theme {
  name : String
  priv styles : Map[String, TokenStyle]
}

///|
let themes : Map[String, Theme] = {
  let m = Map([])
  for entry in theme_table {
    let styles = Map([])
    for s in entry.1 {
      styles[s.0] = {
        fg: if s.1 == "" {
          None
        } else {
          Some(s.1)
        },
        bg: if s.2 == "" {
          None
        } else {
          Some(s.2)
        },
        bold: s.3,
        italic: s.4,
        underline: s.5,
      }
    }
    m[entry.0] = { name: entry.0, styles, }
  }
  m
}

///|
/// The theme registered as `name` (Rouge's `Theme.find`).
pub fn Theme::find(name : String) -> Theme? {
  themes.get(name)
}

///|
/// asciidoctor-pdf's default theme (`asciidoctor_pdf_default`, a variation
/// on pastie).
pub fn Theme::default() -> Theme {
  themes.get("asciidoctor_pdf_default").unwrap()
}

///|
/// The names of the registered themes.
pub fn Theme::names() -> Array[String] {
  themes.keys().collect()
}

///|
/// The style of the nearest of `tok` and its ancestors that has one
/// (Rouge's `get_own_style`).
fn Theme::own_style(self : Theme, tok : String) -> TokenStyle? {
  let mut t = tok
  while true {
    match self.styles.get(t) {
      Some(s) => return Some(s)
      None => ()
    }
    match token_parent(t) {
      Some(p) => t = p
      None => break
    }
  }
  None
}

///|
/// The style of `tok` (Rouge's `CSSTheme#style_for`): its own or an
/// ancestor's, else the theme's `Text` style, else None.
pub fn Theme::style_for(self : Theme, tok : String) -> TokenStyle? {
  match self.own_style(tok) {
    Some(s) => Some(s)
    None => self.own_style("Text")
  }
}
