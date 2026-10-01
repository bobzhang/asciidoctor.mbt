///|
// Loading the document's theme and its fonts (asciidoctor-pdf's
// `load_theme`, `prepare_theme` and `register_fonts`). Theme files, fonts
// and icon fonts are read through the document's VFS, so a conversion run
// with `@io.run_with_files` loads whatever the theme names.

///|
/// Where the fonts the theme loader's virtual `GEM_FONTS_DIR`
/// (`@theme.fonts_dir`) stands for really are, and prawn-icon's icon fonts
/// (`icons=font`); set by `register`.
priv struct FontSources {
  /// the bundled fonts, searched in order (unless `fonts_dir`)
  mut bundles : Array[@bundled.Bundle]
  /// the bundled icon fonts (unless `icon_fonts_dir`)
  mut icon_bundle : @bundled.Bundle?
  mut fonts_dir : String?
  mut icon_fonts_dir : String?
  /// the `pdf_theme` API option (see `register`)
  mut pdf_theme : ((@theme.Files) -> @theme.Theme raise)?
}

///|
let font_sources : FontSources = {
  bundles: [@bundled.default_fonts()],
  icon_bundle: None,
  fonts_dir: None,
  icon_fonts_dir: None,
  pdf_theme: None,
}

///|
/// The theme loader's view of the document's VFS: text files by absolute
/// path.
fn theme_files(doc : @core.Node) -> @theme.Files {
  let vfs = doc.vfs()
  @theme.Files::new(
    read=path => vfs.read(path).map(@core.decode_text),
    cwd=vfs.cwd(),
    home=vfs.home(),
  )
}

///|
/// `str.sub '{docdir}', docdir`
fn sub_docdir(value : String, doc : @core.Node) -> String {
  match value.find("{docdir}") {
    Some(i) =>
      value[:i].to_owned() +
      doc.attr("docdir").unwrap_or("") +
      value[i + 8:].to_owned()
    None => value
  }
}

///|
/// asciidoctor-pdf's `load_theme doc`: the theme `pdf-theme` names (looked
/// up in `pdf-themesdir`), else the default theme (`default-for-print` for
/// `media=print` or `prepress`); a theme that cannot be loaded is reported
/// and the default theme is used instead. Prepared (`prepare_theme`), and
/// the theme of the conversion from then on.
fn load_document_theme(doc : @core.Node) -> @theme.Theme {
  let doc = doc.document()
  let files = theme_files(doc)
  let themesdir = doc.attr("pdf-themesdir").map(d => sub_docdir(d, doc))
  // the `pdf_theme` option wins over `pdf-theme` and `media` (a copy: the
  // conversion's defaults must not leak into the next one)
  let option_theme = match font_sources.pdf_theme {
    Some(build) =>
      Some(
        build(files).copy() catch {
          e => {
            diagnostics.push(
              "WARNING could not load the pdf_theme option because of \{e}; reverting to default theme at <document>",
            )
            @theme.load_theme(files) catch {
              _ => @theme.Theme::new()
            }
          }
        },
      )
    None => None
  }
  let theme = match (option_theme, doc.attr("pdf-theme")) {
    (Some(theme), _) => theme
    (None, Some(name)) =>
      @theme.load_theme(files, theme_name=name, theme_dir?=themesdir) catch {
        e => {
          let where_ = match themesdir {
            Some(dir) => "the pdf theme `\{name}' in \{dir}"
            None => "the built-in pdf theme `\{name}'"
          }
          diagnostics.push(
            "WARNING could not locate or load \{where_} because of \{e}; reverting to default theme at <document>",
          )
          @theme.load_theme(files) catch {
            _ => @theme.Theme::new()
          }
        }
      }
    (None, None) => {
      let name = if doc.attr("media").unwrap_or("screen") == "screen" {
        None
      } else {
        Some("default-for-print")
      }
      @theme.load_theme(files, theme_name?=name) catch {
        _ => @theme.Theme::new()
      }
    }
  }
  prepare_theme(theme)
  theme
}

///|
/// The theme of `doc`'s conversion, loaded once per document (the inline
/// conversions of the parse ask for it before the conversion starts, as
/// asciidoctor-pdf's `convert_inline_*` do with `load_theme node.document`).
fn document_theme(doc : @core.Node) -> @theme.Theme {
  match session.theme {
    Some(theme) => theme
    None => {
      let theme = load_document_theme(doc)
      session.theme = Some(theme)
      current_theme.val = theme
      theme
    }
  }
}

///|
/// The font catalog of `doc`'s conversion: the one `register` was given,
/// else its theme's fonts, loaded once per document.
fn document_catalog(doc : @core.Node) -> FontCatalog raise {
  match session.catalog {
    Some(catalog) => catalog
    None => {
      let catalog = load_document_fonts(doc)
      session.catalog = Some(catalog)
      catalog
    }
  }
}

///|
/// asciidoctor-pdf's `prepare_theme`: the defaults of keys a theme may
/// leave out.
fn prepare_theme(theme : @theme.Theme) -> Unit {
  let default = (key : String, value : @theme.Value) => {
    if !theme[key].truthy() {
      theme[key] = value
    }
  }
  if theme["base_border_color"] is Transparent {
    theme["base_border_color"] = Null
  }
  default("base_font_color", Str("000000"))
  default("base_font_family", Str("Helvetica"))
  if !theme["base_font_style"].truthy() {
    theme["base_font_style"] = Str("normal")
  }
  default("page_numbering_start_at", Str("body"))
  default("running_content_start_at", Str("body"))
  default("heading_chapter_break_before", Str("always"))
  default("heading_part_break_before", Str("always"))
  default("heading_margin_page_top", Int(0))
  default("heading_margin_top", Int(0))
  default("heading_margin_bottom", Int(0))
  default("prose_text_indent", Int(0))
  default("prose_text_indent_inner", Int(0))
  default("prose_margin_bottom", Int(0))
  default("block_margin_bottom", Int(0))
  default("list_indent", Int(0))
  default("list_item_spacing", Int(0))
  default("description_list_term_spacing", Int(0))
  default("description_list_description_indent", Int(0))
  let border = if theme["base_border_color"].truthy() {
    theme["base_border_color"]
  } else {
    Str("000000")
  }
  default("table_border_color", border)
  default("table_border_width", Float(0.5))
  default("thematic_break_border_color", border)
  default("image_border_width", Int(0))
  default("code_linenum_font_color", Str("999999"))
  default("callout_list_margin_top_after_code", Int(0))
  default("role_unresolved_font_color", Str("FF0000"))
  default("footnotes_margin_top", Str("auto"))
  default("footnotes_item_spacing", Int(0))
  default("index_columns", Int(2))
  default("index_column_gap", theme["base_font_size"])
  default("kbd_separator", Str("+"))
  default("title_page_authors_delimiter", Str(", "))
  default("title_page_revision_delimiter", Str(", "))
  default("toc_indent", Int(0))
  default("toc_hanging_indent", Int(0))
  // `TypographicQuotes`: character references, which the substitutions
  // that follow the quotes' do not take for word characters
  let typographic = ["&#8220;", "&#8221;", "&#8216;", "&#8217;"]
  match theme["quotes"] {
    Array(items) => {
      let items = items.copy()
      for i, q in typographic {
        if i >= items.length() {
          items.push(Str(q))
        } else if !items[i].truthy() {
          items[i] = Str(q)
        }
      }
      theme["quotes"] = Array(items)
    }
    _ => theme["quotes"] = Array(typographic.map(q => (Str(q) : @theme.Value)))
  }
}

///|
/// A file of asciidoctor-pdf's font directory (`GEM_FONTS_DIR`), by its
/// name there: from `fonts_dir` when `register` was given one, else from
/// the bundled fonts.
fn read_gem_font_file(vfs : &@core.Vfs, name : String) -> Bytes? {
  match font_sources.fonts_dir {
    Some(dir) => vfs.read(dir + "/" + name)
    None => {
      for bundle in font_sources.bundles {
        if bundle.get(name) is Some(data) {
          return Some(data)
        }
      }
      None
    }
  }
}

///|
/// Whether the theme sets text in an icon font without `icons=font`: a
/// font family (`ulist_marker_checked_font_family: fas`), a fallback font,
/// or `<font name="fas">` in a content template.
fn theme_uses_icon_fonts(theme : @theme.Theme) -> Bool {
  let names = icon_set_names
  let mentions = (value : @theme.Value) => {
    match value {
      Str(s) =>
        names.contains(s) || names.iter().any(n => s.contains("\"\{n}\""))
      Array(items) => items.iter().any(v => v is Str(s) && names.contains(s))
      _ => false
    }
  }
  theme.keys().iter().any(key => mentions(theme.at(key)))
}

///|
/// A font file: one under the theme loader's virtual `GEM_FONTS_DIR` (see
/// `read_gem_font_file`), else a file of the document's VFS.
fn read_font_file(vfs : &@core.Vfs, path : String) -> Bytes? {
  if path.has_prefix(@theme.fonts_dir + "/") {
    read_gem_font_file(vfs, path[@theme.fonts_dir.length() + 1:].to_owned())
  } else {
    vfs.read(path)
  }
}

///|
/// `File.absolute_path(path, dir)`
fn absolute_path_in(path : String, dir : String) -> String {
  @core.expand_path_from(dir, path)
}

///|
/// The font catalog of `doc`'s theme (`register_fonts`): each family's
/// styles, looked for in the `pdf-fontsdir` directories (`;` or `,`
/// separated, `GEM_FONTS_DIR` or an empty entry for the bundled fonts),
/// else in the theme's directory and then the bundled fonts; plus
/// prawn-icon's icon fonts when `register` was told where they are.
fn load_document_fonts(doc : @core.Node) -> FontCatalog raise {
  let doc = doc.document()
  let theme = document_theme(doc)
  let vfs = doc.vfs()
  let spec = match doc.attr("pdf-fontsdir") {
    Some(dirs) => sub_docdir(dirs, doc)
    None =>
      if theme.dir() == @theme.themes_dir {
        "GEM_FONTS_DIR"
      } else {
        theme.dir() + ";GEM_FONTS_DIR"
      }
  }
  let dirs = []
  let mut start = 0
  for i in 0..<=spec.length() {
    if i == spec.length() || spec[i] == ';' || spec[i] == ',' {
      let dir = spec[start:i].to_owned()
      dirs.push(
        if dir == "GEM_FONTS_DIR" || dir == "" {
          @theme.fonts_dir
        } else {
          // relative to the working directory
          @core.expand_path_from(vfs.cwd(), dir)
        },
      )
      start = i + 1
    }
  }
  let files : Array[(String, Bool, Bool, Bytes)] = []
  match theme["font_catalog"] {
    Hash(families, ..) =>
      for family, styles in families {
        guard styles is Hash(styles, ..) else { continue }
        for style, path in styles {
          let (bold, italic) = match style {
            "normal" => (false, false)
            "bold" => (true, false)
            "italic" => (false, true)
            "bold_italic" => (true, true)
            _ => continue
          }
          let path = path.to_ruby_s()
          let mut data : Bytes? = None
          for dir in dirs {
            data = read_font_file(vfs, absolute_path_in(path, dir))
            if data is Some(_) {
              break
            }
          }
          match data {
            Some(bytes) => files.push((family, bold, italic, bytes))
            None =>
              fail(
                "font \{path} not found in \{spec.replace_all(old=";", new=" or ")}",
              )
          }
        }
      }
    _ => ()
  }
  // prawn-icon's fonts, which only `icons=font` draws with (prawn-icon
  // loads them on demand; the catalog is complete once loaded, so they are
  // loaded with it, when the document asks for font icons)
  let icon_sets : Array[IconSet] = []
  let read_icon_file : ((String) -> Bytes?)? = match
    (font_sources.icon_fonts_dir, font_sources.icon_bundle) {
    _ if doc.attr("icons") != Some("font") && !theme_uses_icon_fonts(theme) =>
      None
    (Some(dir), _) => Some(file => vfs.read(dir + "/" + file))
    (None, Some(bundle)) => Some(file => bundle.get(file))
    (None, None) => None
  }
  if read_icon_file is Some(read) {
    for entry in default_icon_font_files() {
      let (name, font, legend) = entry
      match (read(font), read(legend)) {
        (Some(font), Some(legend)) =>
          icon_sets.push({ name, font, legend: @core.decode_text(legend), })
        _ => ()
      }
    }
  }
  let legacy_icon_mapping = if icon_sets.is_empty() {
    ""
  } else {
    read_gem_font_file(vfs, "fa-legacy-mapping.yml")
    .map(@core.decode_text)
    .unwrap_or("")
  }
  let fallbacks = match theme["font_fallbacks"] {
    Array(items) => items.map(v => v.to_ruby_s())
    _ => []
  }
  FontCatalog::load(files, icon_sets~, legacy_icon_mapping~, fallbacks~)
}
