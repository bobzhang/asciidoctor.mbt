///|
// The title page (asciidoctor-pdf's `ink_title_page`), styled by the
// theme's `title_page_*` keys.

///|
/// asciidoctor-pdf's `resolve_top`: a position down the page from the
/// cursor: `vh` of the page height (from its top edge), `%` of the content
/// area's height, or a length.
fn resolve_top(flow : Flow, value : @theme.Value) -> Double {
  let s = value.to_ruby_s()
  if s.has_suffix("vh") {
    page_height() * (@theme.ruby_string_to_f(s) / 100.0)
  } else if s.has_suffix("%") {
    let setup = page_setup.val
    let effective = setup.height - setup.margin_top - setup.margin_bottom
    flow.y + effective * (@theme.ruby_string_to_f(s) / 100.0)
  } else {
    flow.y + @theme.str_to_pt(s)
  }
}

///|
/// asciidoctor-pdf's `with_author`: `body` with the document's author
/// attributes (`author`, `authorinitials`, `firstname`, `middlename`,
/// `lastname`, `email`) set to those of `author` (the primary author's are
/// the document's own) and `url` to its email (`mailto:` when it has an
/// `@`); restored afterwards.
fn[T] with_author(
  doc : @core.Node,
  author : @core.Author,
  primary : Bool,
  body : () -> T,
) -> T {
  let original_url = doc.attr("url")
  if original_url is Some(_) {
    ignore(doc.remove_attr("url"))
  }
  let url_of = (email : String) => {
    if email.contains("@") {
      "mailto:\{email}"
    } else {
      email
    }
  }
  let mut email : String? = None
  let result = if primary {
    email = doc.attr("email")
    match email {
      Some(e) => ignore(doc.set_attr("url", value=Str(url_of(e))))
      None => ()
    }
    body()
  } else {
    let names = [
      ("author", author.name),
      ("authorinitials", author.initials),
      ("firstname", author.firstname),
      ("middlename", author.middlename),
      ("lastname", author.lastname),
      ("email", author.email),
    ]
    let saved = names.map(n => (n.0, doc.attr(n.0)))
    for entry in names {
      match entry.1 {
        Some(v) => ignore(doc.set_attr(entry.0, value=Str(v)))
        None => ignore(doc.remove_attr(entry.0))
      }
    }
    email = author.email
    match email {
      Some(e) => ignore(doc.set_attr("url", value=Str(url_of(e))))
      None => ()
    }
    let result = body()
    for s in saved {
      match s.1 {
        Some(v) => ignore(doc.set_attr(s.0, value=Str(v)))
        None => ignore(doc.remove_attr(s.0))
      }
    }
    result
  }
  match original_url {
    Some(url) => ignore(doc.set_attr("url", value=Str(url)))
    None => if email is Some(_) { ignore(doc.remove_attr("url")) }
  }
  result
}

///|
/// The title page logo (the start of `ink_title_page`): `title-logo-image`,
/// else the theme's `title_page_logo_image`, a block image pinned to the
/// title page (from `top`, else `title_page_logo_top`, down the page),
/// aligned by its `align`, else `title_page_logo_align`, else the title
/// page's alignment. An image macro from the document resolves against the
/// images directory, a bare path against the base directory; a value from
/// the theme is substituted and resolved against the theme's directory.
fn Converter::ink_title_page_logo(
  self : Converter,
  title_align : Alignment,
) -> Unit {
  let doc = self.doc
  let flow = self.flow
  if t_str("title_page_logo_display") == Some("none") {
    return
  }
  let (value, from_theme) = match doc.attr("title-logo-image") {
    Some(v) => (v, false)
    None =>
      match t_str("title_page_logo_image") {
        Some(v) => (v, true)
        None => return
      }
  }
  let themesdir = current_theme.val.dir()
  let from_theme_path = (path : String) => {
    let path = with_attrs(doc, [("imagesdir", themesdir)], () => {
      apply_subs_discretely(doc, path)
    })
    if path.has_prefix("/") || @core.is_uriish(path) {
      path
    } else {
      @theme.resolve_theme_asset(theme_files(doc), path, theme_dir=themesdir)
    }
  }
  let attrs = @core.Attributes::new()
  let (path, relative_to_imagesdir) = match image_macro(value) {
    Some((target, attrlist)) => {
      attrs.update(
        @core.parse_attribute_list(attrlist, positional_attrs=[
          Some("alt"),
          Some("width"),
          Some("height"),
        ]),
      )
      if from_theme {
        (from_theme_path(target), false)
      } else {
        (target, true)
      }
    }
    None => (if from_theme { from_theme_path(value) } else { value }, false)
  }
  if image_target_and_format(path, attrs_str(attrs, "format")).1 == "pdf" {
    report(
      "ERROR " + "PDF format not supported for title page logo image: \{path}",
    )
    return
  }
  attrs.set_str("target", path)
  let valid = (a : String?) => a is Some("left" | "center" | "right")
  let align = attrs_str(attrs, "align")
  ignore(attrs.remove("align"))
  let align = if valid(align) {
    align
  } else if valid(t_str("title_page_logo_align")) {
    t_str("title_page_logo_align")
  } else {
    Some(
      match title_align {
        Center => "center"
        Right => "right"
        _ => "left"
      },
    )
  }
  match align {
    Some(a) => attrs.set_str("align", a)
    None => ()
  }
  let initial_y = flow.y
  let top = match attrs.get("top") {
    Some(Str(t)) => Some(@theme.Value::Str(t))
    _ =>
      match tv("title_page_logo_top") {
        Null => None
        v => Some(v)
      }
  }
  match top {
    Some(t) => flow.y = resolve_top(flow, t)
    None => ()
  }
  let logo = @core.Node::new_block(
    doc,
    Image,
    content_model=Empty,
    attributes=attrs,
  )
  self.pinned = true
  flow.indent(
    t_num_or("title_page_logo_margin_left", 0.0),
    t_num_or("title_page_logo_margin_right", 0.0),
    () => self.convert_image(logo, relative_to_imagesdir~),
  )
  self.pinned = false
  if top is Some(_) {
    flow.y = initial_y
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
  self.ink_title_page_logo(align)
  let (base, line_height) = theme_font(
    base_style(),
    base_line_height(),
    "title_page",
  )
  match tv("title_page_title_top") {
    Null => ()
    top => flow.y = resolve_top(flow, top)
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
  if title_page_shows("authors") && doc.has_attr("authors") {
    // each author by `title_page_authors_content` (`_name_only`,
    // `_with_email`, `_with_url` by the author's url), else the name
    let generic = t_str("title_page_authors_content")
    let content = (key : String) => {
      t_str("title_page_authors_content_\{key}").or_some(generic)
    }
    let themesdir = current_theme.val.dir()
    let texts = authors.mapi((index, author) => {
      with_author(doc, author, index == 0, () => {
        let key = match doc.attr("url") {
          Some(url) if url.has_prefix("mailto:") => "with_email"
          Some(_) => "with_url"
          None => "name_only"
        }
        match content(key) {
          Some(c) =>
            with_attrs(doc, [("imagesdir", themesdir)], () => {
              apply_subs_discretely(doc, c)
            })
          None => doc.attr("author").unwrap_or("")
        }
      })
    })
    let delimiter = t_str("title_page_authors_delimiter").unwrap_or(", ")
    self.ink_title_page_part(
      "authors",
      texts.join(delimiter),
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
