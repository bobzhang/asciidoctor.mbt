///|
// Running content: the page header and footer (asciidoctor-pdf's
// `ink_running_content` and `allocate_running_content_layout`), from the
// theme's `header_*` and `footer_*` keys: each page side (recto, verso)
// has up to three columns (left, center, right) whose content is text with
// attribute references (`{page-number}`, `{chapter-title}`, ...).

///|
/// The geometry of a periphery on one page side: its box (from the page's
/// left and top edges), its padding and the content area inside.
priv struct Trim {
  left : Double
  top : Double
  width : Double
  height : Double
  padding : (Double, Double, Double, Double)
}

///|
/// A trim margin or content margin value: `inherit` on the sides, else a
/// length.
fn trim_rect(v : @theme.Value) -> Array[@theme.Value] {
  let items = match v {
    Array(items) => items
    Null => [Int(0), Str("inherit"), Int(0), Str("inherit")]
    other => [other]
  }
  match items.length() {
    0 => [Int(0), Int(0), Int(0), Int(0)]
    1 => [items[0], items[0], items[0], items[0]]
    2 => [items[0], items[1], items[0], items[1]]
    3 => [items[0], items[1], items[2], items[1]]
    _ => items[:4].to_owned()
  }
}

///|
/// The (left, right) page margins of recto and verso pages when they
/// differ (`media=prepress`), else None.
let side_margins : Ref[((Double, Double), (Double, Double))?] = { val: None, }

///|
/// A periphery's box on a page side (`allocate_running_content_layout`).
fn periphery_trim(
  periphery : String,
  side : String,
  page_size? : (Double, Double),
) -> Trim {
  let setup = session().page_setup
  let (page_w, page_h) = page_size.unwrap_or((setup.width, setup.height))
  let (margin_left, margin_right) = match side_margins.val {
    Some((recto, verso)) => if side == "verso" { verso } else { recto }
    None => (setup.margin_left, setup.margin_right)
  }
  let page_margin = [
    setup.margin_top,
    margin_right,
    setup.margin_bottom,
    margin_left,
  ]
  let side_key = (name : String) => {
    match tv("\{periphery}_\{side}_\{name}") {
      Null => tv("\{periphery}_\{name}")
      v => v
    }
  }
  let margin = trim_rect(side_key("margin")).mapi((i, v) => {
    if i % 2 == 1 && v is Str("inherit") {
      page_margin[i]
    } else {
      v.to_f()
    }
  })
  let content_margin = trim_rect(side_key("content_margin")).mapi((i, v) => {
    if i % 2 == 1 && v is Str("inherit") {
      page_margin[i] - margin[i]
    } else {
      v.to_f()
    }
  })
  let padding = match side_key("padding") {
    Null => content_margin
    v => {
      let (t, r, b, l) = expand_rect(v)
      [t, r, b, l].mapi((i, x) => x + content_margin[i])
    }
  }
  let height = t_num_or(periphery + "_height", 0.0)
  let top = if periphery == "header" {
    margin[0]
  } else {
    page_h - height - margin[2]
  }
  {
    left: margin[3],
    top,
    width: page_w - margin[3] - margin[1],
    height,
    padding: (padding[0], padding[1], padding[2], padding[3]),
  }
}

///|
/// The columns of a periphery on a page side (`<periphery>_columns`, e.g.
/// `<40% =20% >40%`): each position's alignment, offset and width in the
/// content area; without the key, each position spans it.
fn periphery_columns(
  periphery : String,
  side : String,
  content_width : Double,
) -> Array[(String, Alignment, Double, Double)] {
  let spec = match tv("\{periphery}_\{side}_columns") {
    Null => tv("\{periphery}_columns")
    v => v
  }
  match spec {
    Null =>
      [
        ("left", Left, 0.0, content_width),
        ("center", Center, 0.0, content_width),
        ("right", Right, 0.0, content_width),
      ]
    v => {
      let specs = v
        .to_ruby_s()
        .replace_all(old=",", new=" ")
        .split(" ")
        .filter(s => s != "")
        .map(s => s.to_owned())
        .collect()
      let (l, c, r) = match specs.length() {
        0 | 1 => ("0", specs.get(0).unwrap_or("100"), "0")
        2 => (specs[0], "0", specs[1])
        _ => (specs[0], specs[1], specs[2])
      }
      let parse = (s : String) => {
        let first = s.get_char(0).unwrap_or('0')
        if first >= '0' && first <= '9' {
          (Alignment::Left, @theme.ruby_string_to_f(s))
        } else {
          let align = match first {
            '=' => Alignment::Center
            '>' => Alignment::Right
            _ => Alignment::Left
          }
          (align, @theme.ruby_string_to_f(s[1:].to_owned()))
        }
      }
      let cols = [("left", parse(l)), ("center", parse(c)), ("right", parse(r))]
      let total = cols.fold(init=0.0, (acc, col) => acc + col.1.1)
      let widths = cols.map(col => {
        if total > 0.0 {
          col.1.1 / total * content_width
        } else {
          0.0
        }
      })
      [
        ("left", cols[0].1.0, 0.0, widths[0]),
        ("center", cols[1].1.0, widths[0], widths[1]),
        ("right", cols[2].1.0, widths[0] + widths[1], widths[2]),
      ]
    }
  }
}

///|
/// The title a section shows in running content (`<periphery>_title_style`:
/// `toc` numbered, `basic` plain, else numbered formally).
fn running_title(section : @core.Node, periphery : String) -> String {
  match t_str(periphery + "_title_style") {
    Some("toc") => numbered_title(section)
    Some("basic") => section.title().unwrap_or("")
    _ => numbered_title(section, formal=true)
  }
}

///|
/// asciidoctor-pdf's `apply_subs_discretely` with
/// `drop_lines_with_unresolved_attributes`: the normal substitutions with
/// missing attributes left as they are, then the lines still holding a
/// reference of the original dropped.
fn apply_subs_discretely(doc : @core.Node, value : String) -> String {
  let saved_missing = doc.attr("attribute-missing")
  ignore(doc.set_attr("attribute-missing", value=Str("skip")))
  let escaped = value.contains("\\{")
  let source = if escaped {
    value.replace_all(old="\\{", new="\\\\\\{")
  } else {
    value
  }
  let result = doc.apply_subs(source, @core.normal_subs)
  let result = if result.contains("{") {
    let kept = []
    for line in result.split("\n") {
      let line = line.to_owned()
      let mut drop = false
      // a simple attribute reference left unresolved: `{name}`
      let mut i = 0
      while i < line.length() {
        if line[i] == '{' {
          match line[i + 1:].find("}") {
            Some(j) => {
              let name = line[i + 1:i + 1 + j].to_owned()
              if name != "" &&
                name
                .iter()
                .all(c => {
                  c.is_ascii_alphabetic() ||
                  c.is_ascii_digit() ||
                  c == '_' ||
                  c == '-'
                }) &&
                source.contains("{" + name + "}") {
                drop = true
                break
              }
            }
            None => ()
          }
        }
        i += 1
      }
      if !drop {
        kept.push(line)
      }
    }
    kept.join("\n")
  } else {
    result
  }
  let result = if escaped {
    result.replace_all(old="\\{", new="{")
  } else {
    result
  }
  match saved_missing {
    Some(m) => ignore(doc.set_attr("attribute-missing", value=Str(m)))
    None => ignore(doc.remove_attr("attribute-missing"))
  }
  result
}

///|
/// A page's section context for running content: the part, chapter and
/// section it is in (their titles and numerals).
priv struct PageSections {
  part : (String, String?)
  chapter : (String, String?)
  section : (String, String?)
}

///|
/// The part, chapter and section of each page (1-based), as
/// `ink_running_content` indexes them by the pages sections start on.
fn Converter::sections_by_page(
  self : Converter,
  periphery : String,
  num_pages : Int,
  body_start : Int,
) -> Array[PageSections] {
  let doc = self.doc
  let is_book = doc.doctype() == "book"
  let sectlevels = t_num_or(periphery + "_sectlevels", 2.0).to_int()
  let sections = doc.find_by(context=Section).filter(s => s.level <= sectlevels)
  let part_starts : Map[Int, @core.Node?] = Map([])
  let chapter_starts : Map[Int, @core.Node] = Map([])
  let section_starts : Map[Int, @core.Node] = Map([])
  let trailing_starts : Map[Int, @core.Node] = Map([])
  for sect in sections {
    let pgnum = match sect.attr("pdf-page-start") {
      Some(n) => @string.parse_int(n) catch { _ => 0 }
      None => 0
    }
    let is_part = sect.sectname == Some("part")
    if is_book && (is_part || sect.level == 1) {
      if is_part {
        if !part_starts.contains(pgnum) {
          part_starts[pgnum] = Some(sect)
        }
      } else {
        if !chapter_starts.contains(pgnum) {
          chapter_starts[pgnum] = sect
        }
        if sect.sectname == Some("appendix") && !part_starts.is_empty() {
          part_starts[pgnum] = None
        }
      }
    } else {
      trailing_starts[pgnum] = sect
      if !section_starts.contains(pgnum) {
        section_starts[pgnum] = sect
      }
    }
  }
  let info = (s : @core.Node?) => {
    match s {
      Some(sect) => (running_title(sect, periphery), sect.numeral)
      None => ("", None)
    }
  }
  let toc_range = match self.toc_extent {
    Some(extent) => Some((extent.from_page + 1, extent.to_page + 1))
    None => None
  }
  let toc_title = doc.attr("toc-title").unwrap_or("")
  let result = [{ part: ("", None), chapter: ("", None), section: ("", None), }]
  let mut last_part : @core.Node? = None
  let mut last_chap : @core.Node? = None
  let mut pre = is_book
  let mut last_sect : @core.Node? = None
  let mut threshold = 1
  for pgnum in 1..<=num_pages {
    let part = part_starts.get(pgnum)
    match part {
      Some(p) => {
        last_part = p
        last_chap = None
        pre = false
        last_sect = None
      }
      None => ()
    }
    let chap = chapter_starts.get(pgnum)
    match chap {
      Some(c) => {
        last_chap = Some(c)
        pre = false
        last_sect = None
      }
      None => ()
    }
    match section_starts.get(pgnum) {
      Some(s) => last_sect = Some(s)
      None =>
        if part is Some(_) || chap is Some(_) {
          threshold = pgnum
        } else if last_sect is Some(_) {
          for prev = pgnum - 1; prev >= threshold; prev = prev - 1 {
            match trailing_starts.get(prev) {
              Some(s) => {
                last_sect = Some(s)
                break
              }
              None => ()
            }
          }
        }
    }
    let in_toc = match toc_range {
      Some((from, to)) => pgnum >= from && pgnum <= to
      None => false
    }
    let (chapter, section) = if in_toc {
      if is_book {
        ((toc_title, None), ("", None))
      } else {
        match section_starts.get(pgnum) {
          Some(s) => (("", None), info(Some(s)))
          None => (("", None), (toc_title, None))
        }
      }
    } else if pre && last_chap is None {
      let title = if pgnum < body_start {
        doc.doctitle().unwrap_or("")
      } else {
        match doc.attr("preface-title") {
          Some(t) => t
          None =>
            if doc.attribute_locked("preface-title") {
              ""
            } else {
              "Preface"
            }
        }
      }
      ((title, None), info(last_sect))
    } else {
      (info(last_chap), info(last_sect))
    }
    result.push({ part: info(last_part), chapter, section, })
  }
  result
}

///|
/// Ink the running content of `periphery` (`header`, `footer`) on every
/// page after the first `skip_pages`, numbering pages after the first
/// `skip_pagenums` (earlier ones in roman numerals).
fn Converter::ink_running_content(
  self : Converter,
  periphery : String,
  skip_pages : Int,
  skip_pagenums : Int,
  body_start : Int,
) -> Unit {
  let doc = self.doc
  let flow = self.flow
  let pages = flow.model.pages
  let num_pages = pages.length()
  if skip_pages >= num_pages {
    return
  }
  let by_page = self.sections_by_page(periphery, num_pages, body_start)
  // the document title, and the page count, as attributes
  match doc.doctitle_partitioned(use_fallback=true) {
    Some(t) => {
      ignore(doc.set_attr("document-title", value=Str(t.main)))
      match t.subtitle {
        Some(sub) => ignore(doc.set_attr("document-subtitle", value=Str(sub)))
        None => ()
      }
    }
    None => ()
  }
  ignore(
    doc.set_attr(
      "page-count",
      value=Str((num_pages - skip_pagenums).to_string()),
    ),
  )
  let pagenums = doc.has_attr("pagenums")
  let (base, line_height) = category_font(periphery)
  let bg = t_color(periphery + "_background_color")
  let border_width = t_num_or(periphery + "_border_width", 0.0)
  let border_color = if border_width > 0.0 {
    match tv(periphery + "_border_color") {
      Null => base_border_color()
      Transparent => None
      v => value_color(v)
    }
  } else {
    None
  }
  if t_num_or(periphery + "_column_rule_width", 0.0) > 0.0 {
    unsupported("theme", periphery + "_column_rule", doc)
  }
  let valign = t_str(periphery + "_vertical_align").unwrap_or("middle")
  // images go by `<periphery>_image_vertical_align`, else by the content's
  let img_valign = match
    t_str(periphery + "_image_vertical_align").or_some(Some(valign)) {
    Some("middle") | None => "center"
    Some(v) => v
  }
  // the image a column's content names, resolved once per side and column
  let images : Map[String, Background] = Map([])
  let face = flow.font(base)
  let metrics = line_metrics(line_height, face, base.size)
  // the footer's content moves down by half its border
  let content_offset = if periphery == "footer" {
    border_width * 0.5
  } else {
    0.0
  }
  let disable_on_pages = self.disable_running_content
    .get(periphery)
    .unwrap_or([])
  for index in skip_pages..<num_pages {
    let pgnum = index + 1
    if disable_on_pages.contains(pgnum) {
      continue
    }
    let virtual_pgnum = pgnum - skip_pagenums
    let label = if virtual_pgnum < 1 {
      roman(pgnum, false)
    } else {
      virtual_pgnum.to_string()
    }
    // `pdf-folio-placement`: by the physical or the virtual page number
    // (physical for prepress), optionally inverted
    let placement = doc
      .attr("pdf-folio-placement")
      .unwrap_or(
        if doc.attr("media") == Some("prepress") {
          "physical"
        } else {
          "virtual"
        },
      )
    let basis = if placement.has_prefix("physical") {
      pgnum
    } else {
      virtual_pgnum
    }
    let even = basis % 2 == 0
    let side = if even != placement.has_suffix("-inverted") {
      "verso"
    } else {
      "recto"
    }
    if pagenums {
      ignore(doc.set_attr("page-number", value=Str(label)))
    }
    let info = by_page[pgnum]
    ignore(doc.set_attr("part-title", value=Str(info.part.0)))
    match info.part.1 {
      Some(n) => ignore(doc.set_attr("part-numeral", value=Str(n)))
      None => ignore(doc.remove_attr("part-numeral"))
    }
    ignore(doc.set_attr("chapter-title", value=Str(info.chapter.0)))
    match info.chapter.1 {
      Some(n) => ignore(doc.set_attr("chapter-numeral", value=Str(n)))
      None => ignore(doc.remove_attr("chapter-numeral"))
    }
    ignore(doc.set_attr("section-title", value=Str(info.section.0)))
    ignore(
      doc.set_attr(
        "section-or-chapter-title",
        value=Str(
          if info.section.0 != "" {
            info.section.0
          } else {
            info.chapter.0
          },
        ),
      ),
    )
    ignore(
      doc.set_attr(
        "page-layout",
        value=Str(
          if pages[index].width_pt > pages[index].height_pt {
            "landscape"
          } else {
            "portrait"
          },
        ),
      ),
    )
    let page = pages[index]
    let trim = periphery_trim(
      periphery,
      side,
      page_size=(page.width_pt, page.height_pt),
    )
    let (pad_top, pad_right, pad_bottom, pad_left) = trim.padding
    match bg {
      Some(color) =>
        page.items.push(
          rect_item(trim.left, trim.top, trim.width, trim.height, fill=color),
        )
      None => ()
    }
    match border_color {
      Some(color) => {
        let y = if periphery == "header" {
          trim.top + trim.height
        } else {
          trim.top
        }
        page.items.push(
          hrule(trim.left, trim.left + trim.width, y, border_width, color),
        )
      }
      None => ()
    }
    let content_left = trim.left + pad_left
    let content_width = trim.width - pad_left - pad_right
    let content_height = trim.height - pad_top - pad_bottom - border_width * 0.5
    let prose_height = content_height -
      metrics.padding_top -
      metrics.padding_bottom
    let box_top = trim.top + pad_top + content_offset
    for column in periphery_columns(periphery, side, content_width) {
      let (position, align, x, width) = column
      if width <= 0.0 {
        continue
      }
      let key = "\{periphery}_\{side}_\{position}"
      let mut raw = match tv(key + "_content") {
        Null | Str("") => continue
        v => v.to_ruby_s()
      }
      // content that is an image macro is an image in the column, aligned
      // as the column is; one that cannot be read stays an inline image
      // (its alt text)
      match image_macro(raw) {
        Some((_, attrlist)) => {
          let resolved = match images.get(key) {
            Some(r) => r
            None => {
              let r = self.resolve_box_image(
                raw,
                true,
                (width, content_height),
                background=false,
              )
              images[key] = r
              r
            }
          }
          match resolved {
            Found(img) => {
              let img = {
                ..img,
                position: match align {
                  Center => "center"
                  Right => "right"
                  _ => "left"
                },
                vposition: img_valign,
              }
              match
                self.box_image_items(
                  img,
                  content_left + x,
                  box_top,
                  width,
                  content_height,
                ) {
                Some((drawn, iw, ih)) => {
                  page.items.append(drawn)
                  match img.link {
                    Some(link) if link != "" => {
                      let (ix, iy) = match drawn.get(0) {
                        Some(Image(i)) => (i.x_pt, i.y_pt)
                        Some(Graphic(g)) => (g.x_pt, g.y_pt)
                        _ => (content_left + x, box_top)
                      }
                      page.items.push(
                        Link({
                          x_pt: ix,
                          y_pt: iy,
                          w_pt: iw,
                          h_pt: ih,
                          target: if link.has_prefix("#") {
                            Named(pdf_anchor_name(link[1:].to_owned()))
                          } else {
                            Uri(link)
                          },
                        }),
                      )
                    }
                    _ => ()
                  }
                  continue
                }
                // an image that cannot be drawn shows its alt text
                None =>
                  match img.alt {
                    Some(alt) => raw = alt
                    None => continue
                  }
              }
            }
            Unreadable(path) => raw = "image:\{path}[\{attrlist}]"
            _ => raw = "image:[\{attrlist}]"
          }
        }
        None => ()
      }
      let (style, _) = theme_font(base, line_height, key)
      let content = if raw == "{page-number}" {
        if pagenums {
          label
        } else {
          continue
        }
      } else {
        apply_subs_discretely(doc, raw)
      }
      let content = match style.text_transform {
        Some(transform) => transform_text(content, transform)
        None => content
      }
      let style = { ..style, text_transform: None, }
      let lines = typeset_lines(
        parse_formatted(content, style),
        flow.text(),
        width,
        align,
      )
      if lines.is_empty() {
        continue
      }
      let sface = flow.font(style)
      // the lines that fit in the content area (`overflow: :truncate`),
      // placed from its top, middle or bottom
      let placed = []
      let mut height = 0.0
      let mut baseline = 0.0
      for i, line in lines {
        let (a, d, h) = line_extent(line, sface, style.size, false)
        let next = if i == 0 { a } else { baseline + h + metrics.leading }
        if next + d > prose_height + 0.0001 && i > 0 {
          break
        }
        baseline = next
        height = next + d
        placed.push((line, next))
      }
      let shift = match valign {
        "top" => 0.0
        "bottom" => prose_height - height
        // centred: the box starts half a descender lower
        // (`font.descender * 0.5`), and Prawn centres the text half a
        // descender higher (`@at[1] -= (@height - height + @descender) *
        // 0.5`)
        _ => (prose_height - height) / 2.0
      }
      for entry in placed {
        let (line, at) = entry
        page.items.append(
          flow.line_items(line, content_left + x, box_top + shift + at),
        )
      }
    }
  }
}
