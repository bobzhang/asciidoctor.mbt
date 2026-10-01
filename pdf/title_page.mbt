///|
// The title page (asciidoctor-pdf's `ink_title_page`), styled by the
// theme's `title_page_*` keys.

///|
/// asciidoctor-pdf's `resolve_top`: a position down the page from the
/// cursor: `vh` of the page height (from its top edge), `%` of the content
/// area's height, or a length.
fn Flow::resolve_top(self : Flow, value : @theme.Value) -> Double {
  let s = value.to_ruby_s()
  if s.has_suffix("vh") {
    page_height() * (@theme.ruby_string_to_f(s) / 100.0)
  } else if s.has_suffix("%") {
    let setup = page_setup.val
    let effective = setup.height - setup.margin_top - setup.margin_bottom
    self.y + effective * (@theme.ruby_string_to_f(s) / 100.0)
  } else {
    self.y + @theme.str_to_pt(s)
  }
}

///|
/// `title_page_<part>_display: none` hides a part.
fn title_page_shows(part : String) -> Bool {
  t_str("title_page_\{part}_display") != Some("none")
}

///|
/// Ink one part of the title page (`title`, `subtitle`, `authors`,
/// `revision`) in its theme font, between its margins.
fn Converter::ink_title_page_part(
  self : Converter,
  part : String,
  text : String,
  base : Style,
  line_height : Double,
  align : Alignment,
  normalize? : Bool = true,
) -> Unit {
  let flow = self.flow
  let key = "title_page_\{part}"
  flow.move_down(t_num_or(key + "_margin_top", 0.0))
  flow.indent(
    t_num_or(key + "_margin_left", 0.0),
    t_num_or(key + "_margin_right", 0.0),
    () => {
      let (style, line_height) = theme_font(base, line_height, key)
      self.ink_prose(
        text,
        style~,
        align~,
        margin_bottom=0.0,
        line_height~,
        normalize~,
      )
    },
  )
  flow.move_down(t_num_or(key + "_margin_bottom", 0.0))
}

///|
/// The title page of a book (asciidoctor-pdf's `ink_title_page`): the
/// title from `title_page_title_top` down the page, then the subtitle,
/// authors and revision, each in its `title_page_*` font, aligned by
/// `title_page_text_align`.
fn Converter::ink_title_page(self : Converter) -> Unit {
  let doc = self.doc
  let flow = self.flow
  let align = t_align("title_page_text_align", self.text_align)
  if doc.has_attr("title-logo-image") || t_set("title_page_logo_image") {
    unsupported("image", "title page logo", doc)
  }
  let (base, line_height) = theme_font(
    base_style(),
    base_line_height(),
    "title_page",
  )
  match tv("title_page_title_top") {
    Null => ()
    top => flow.y = flow.resolve_top(top)
  }
  let (main, subtitle) = match doc.doctitle_partitioned() {
    Some(t) => (t.main, t.subtitle)
    None => (doc.doctitle().unwrap_or(""), None)
  }
  if title_page_shows("title") {
    self.ink_title_page_part("title", main, base, line_height, align)
  }
  match subtitle {
    Some(sub) if title_page_shows("subtitle") =>
      self.ink_title_page_part("subtitle", sub, base, line_height, align)
    _ => ()
  }
  let authors = doc.authors()
  if title_page_shows("authors") && !authors.is_empty() {
    if t_set("title_page_authors_content") ||
      t_set("title_page_authors_content_name_only") ||
      t_set("title_page_authors_content_with_email") ||
      t_set("title_page_authors_content_with_url") {
      unsupported("theme", "title_page_authors_content", doc)
    }
    let delimiter = t_str("title_page_authors_delimiter").unwrap_or(", ")
    self.ink_title_page_part(
      "authors",
      authors.map(a => a.name.unwrap_or("")).join(delimiter),
      base,
      line_height,
      align,
    )
  }
  let revision = []
  match doc.attr("revnumber") {
    Some(n) =>
      revision.push("\{doc.attr("version-label").unwrap_or("Version")} \{n}")
    None => ()
  }
  match doc.attr("revdate") {
    Some(d) => revision.push(d)
    None => ()
  }
  if title_page_shows("revision") && !revision.is_empty() {
    let delimiter = t_str("title_page_revision_delimiter").unwrap_or(", ")
    let text = match doc.attr("revremark") {
      Some(remark) => "\{revision.join(delimiter)}: \{remark}"
      None => revision.join(delimiter)
    }
    self.ink_title_page_part(
      "revision",
      text,
      base,
      line_height,
      align,
      normalize=false,
    )
  }
}
