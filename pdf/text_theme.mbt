///|
// The theme's settings for inline text (asciidoctor-pdf's
// `FormattedText::Transform` and its `@theme_settings`): the `button`,
// `codespan`, `kbd`, `link`, `mark` and `menu` categories for their tags,
// and the `role_<name>_*` keys for the roles of an element's `class`.

///|
/// Apply the font settings of a theme category to `style`: its font
/// family, size (points or relative), colour, style (`font_style`, and
/// `text_decoration` where the category has one), background (with its
/// `border_offset`) and text transform. `family` is the family key, when
/// not `<category>_font_family`.
fn apply_text_category(
  style : Style,
  category : String,
  family_key? : String,
  decoration? : Bool = false,
  background? : Bool = true,
) -> Style {
  let mut s = style
  match t_color(category + "_font_color") {
    Some(color) => s = { ..s, color, }
    None => ()
  }
  let family = t_str(family_key.unwrap_or(category + "_font_family"))
  match family {
    Some(family) => s = { ..s, family, font_set: true, }
    None => ()
  }
  match resolve_font_size(tv(category + "_font_size"), s.size) {
    Some(size) => s = { ..s, size, }
    None => ()
  }
  let font_style = t_str(category + "_font_style")
  let text_decoration = if decoration {
    t_str(category + "_text_decoration")
  } else {
    None
  }
  s = apply_text_styles(s, category, font_style, text_decoration)
  if background {
    let bg = t_color(category + "_background_color")
    let border = t_num(category + "_border_width").unwrap_or(0.0) > 0.0
    match bg {
      Some(color) => s = { ..s, background: Some(color), }
      None => ()
    }
    if bg is Some(_) || border {
      match t_num(category + "_border_offset") {
        Some(offset) => s = { ..s, border_offset: offset, }
        None => ()
      }
    }
  }
  match t_str(category + "_text_transform") {
    Some("none") => s = { ..s, text_transform: None, }
    Some(transform) => s = { ..s, text_transform: Some(transform), }
    None => ()
  }
  s
}

///|
/// Merge a theme's `font_style` and `text_decoration` into `style`
/// (`update_fragment`): `normal` (of `normal_italic`) drops the bold and
/// italic the text has, but only the first time the setting is applied
/// (asciidoctor-pdf deletes it from the theme's own set as it applies it).
fn apply_text_styles(
  style : Style,
  setting : String,
  font_style : String?,
  text_decoration : String?,
) -> Style {
  let mut s = style
  match font_style {
    Some(fs) => {
      if fs == "normal_italic" && !session.normal_spent.contains(setting) {
        session.normal_spent[setting] = true
        s = { ..s, bold: false, italic: false, }
      }
      let (bold, italic) = font_style_of(fs)
      if bold {
        s = { ..s, bold: true, }
      }
      if italic {
        s = { ..s, italic: true, }
      }
    }
    None => ()
  }
  match text_decoration {
    Some("underline") => s = { ..s, underline: true, }
    Some("line-through") => s = { ..s, strike: true, }
    _ => ()
  }
  s
}

///|
/// The roles of an element's `class`, applied in order: each role's
/// `role_<name>_*` theme keys (a role name with an underscore cannot have
/// any, as asciidoctor-pdf splits the key at the first one), else the
/// built-in `underline`, `line-through`, `big` and `small`; and `wj`, a
/// word joiner.
fn apply_roles(style : Style, classes : String) -> Style {
  let mut s = style
  for role in classes.split(" ") {
    let role = role.to_owned()
    if role == "" {
      continue
    }
    if role == "wj" {
      s = { ..s, wj: true, }
    }
    let themed = !role.contains("_") && role_has_settings(role)
    if themed {
      s = apply_role_settings(s, role)
    } else {
      match role {
        "underline" => s = { ..s, underline: true, }
        "line-through" => s = { ..s, strike: true, }
        "big" => s = { ..s, size: s.size * relative_size("large", 1.1667), }
        "small" => s = { ..s, size: s.size * relative_size("small", 0.8333), }
        _ => ()
      }
    }
  }
  s
}

///|
/// `base_font_size_<which>` relative to the base font size, to five
/// decimals, else `fallback` (the `big` and `small` roles' default sizes).
fn relative_size(which : String, fallback : Double) -> Double {
  match t_num("base_font_size_" + which) {
    Some(size) => {
      let ratio = size / base_font_size()
      (ratio * 100000.0).round() / 100000.0
    }
    None => fallback
  }
}

///|
/// The properties a role's theme keys can set (`ThemeKeyToFragmentProperty`
/// and the styles).
let role_properties : Array[String] = [
  "background_color", "border_color", "border_offset", "border_radius", "border_width",
  "font_color", "font_family", "font_size", "text_decoration_color", "text_decoration_width",
  "text_transform", "font_style", "text_decoration",
]

///|
fn role_has_settings(role : String) -> Bool {
  role_properties.iter().any(p => current_theme.val.has("role_\{role}_\{p}"))
}

///|
/// A role's `role_<name>_*` settings.
fn apply_role_settings(style : Style, role : String) -> Style {
  let key = "role_" + role
  let mut s = style
  match t_color(key + "_font_color") {
    Some(color) => s = { ..s, color, }
    None => ()
  }
  match t_str(key + "_font_family") {
    Some(family) => s = { ..s, family, font_set: true, }
    None => ()
  }
  match resolve_font_size(tv(key + "_font_size"), s.size) {
    Some(size) => s = { ..s, size, }
    None => ()
  }
  if current_theme.val.has(key + "_font_style") ||
    current_theme.val.has(key + "_text_decoration") {
    s = apply_text_styles(
      s,
      key,
      t_str(key + "_font_style"),
      t_str(key + "_text_decoration"),
    )
  }
  match t_color(key + "_background_color") {
    Some(color) => s = { ..s, background: Some(color), }
    None => ()
  }
  match t_num(key + "_border_offset") {
    Some(offset) => s = { ..s, border_offset: offset, }
    None => ()
  }
  match t_str(key + "_text_transform") {
    Some("none") => s = { ..s, text_transform: None, }
    Some(transform) => s = { ..s, text_transform: Some(transform), }
    None => ()
  }
  s
}

///|
/// asciidoctor-pdf's `transform_text`: `uppercase`, `lowercase`, or
/// `capitalize` (each word's first letter upper case); anything else
/// leaves the text as it is.
fn transform_text(text : String, transform : String) -> String {
  match transform {
    "uppercase" => text.to_upper()
    "lowercase" => text.to_lower()
    "capitalize" => {
      let sb = StringBuilder()
      let mut start = true
      for c in text {
        if start && c.is_ascii_lowercase() {
          sb.write_char(c.to_ascii_uppercase())
        } else {
          sb.write_char(c)
        }
        start = c == ' ' || c == '\t' || c == '\n' || c == '-'
      }
      sb.to_string()
    }
    _ => text
  }
}

///|
/// The style a tag gives its content.
fn tag_style(tag : String, attrs : Map[String, String], style : Style) -> Style {
  match tag {
    "strong" | "b" => { ..style, bold: true, }
    "em" | "i" => { ..style, italic: true, }
    "code" => apply_text_category(style, "codespan")
    "kbd" =>
      apply_text_category(
        style,
        "kbd",
        family_key=if current_theme.val.has("kbd_font_family") {
          "kbd_font_family"
        } else {
          "codespan_font_family"
        },
      )
    "button" => apply_text_category(style, "button")
    "menu" => apply_text_category(style, "menu", background=false)
    "mark" => apply_text_category(style, "mark")
    "sup" => { ..style, size: style.size * 0.583, script: 1, }
    "sub" => { ..style, size: style.size * 0.583, script: -1, }
    "u" => { ..style, underline: true, }
    "del" | "s" | "strikethrough" => { ..style, strike: true, }
    "a" =>
      match attrs.get("href") {
        Some(href) =>
          apply_text_category(
            { ..style, link: Some(Uri(href)), },
            "link",
            decoration=true,
          )
        None =>
          match attrs.get("anchor") {
            Some(anchor) =>
              apply_text_category(
                { ..style, link: Some(Named(pdf_anchor_name(anchor))), },
                "link",
                decoration=true,
              )
            None => style
          }
      }
    "font" | "color" | "span" => {
      let mut s = style
      match attrs.get("size") {
        Some(size) => s = { ..s, size: parse_size(size, s.size), }
        None => ()
      }
      match attrs.get("name") {
        Some(family) => s = { ..s, family, font_set: true, }
        None => ()
      }
      match
        (match attrs.get("color") {
          Some(c) => Some(c)
          None => attrs.get("rgb")
        }) {
        Some(color) =>
          match parse_color(color) {
            Some(c) => s = { ..s, color: c, }
            None => ()
          }
        None => ()
      }
      s
    }
    _ => style
  }
}
