///|
// The table of contents, after asciidoctor-pdf's `allocate_toc`, `ink_toc`
// and `ink_toc_level`. Before the body is laid out, a dry run inks the
// titles of the entries with room kept on their right for a page number of
// `toc-max-pagenum-digits` zeros, and that many pages are reserved; after
// the body, the entries are inked on the reserved pages with dot leaders
// and their actual page numbers, all linked to their sections.

///|
/// Where the reserved TOC pages start (page index, cursor y).
priv struct TocExtent {
  from_page : Int
  from_y : Double
  /// the last page reserved
  to_page : Int
}

///|
/// The document's `toclevels` (asciidoctor-pdf's `resolve_toclevels`).
fn resolve_toclevels(doc : @core.Node) -> Int {
  let levels = @string.parse_int(doc.attr("toclevels").unwrap_or("2")) catch {
    _ => 2
  }
  if levels < 1 {
    if doc.doctype() == "book" &&
      doc.sections().iter().any(s => s.sectname == Some("part")) {
      0
    } else {
      1
    }
  } else {
    levels
  }
}

///|
/// A signifier attribute (`chapter-signifier`, `part-signifier`): its
/// value, else `default` unless it was unset.
fn signifier(doc : @core.Node, name : String, default : String) -> String {
  match doc.attr(name) {
    Some(value) => value
    None => if doc.attribute_locked(name) { "" } else { default }
  }
}

///|
/// A section's title as asciidoctor-pdf numbers it (its
/// `Section#numbered_title`): the section number in front when numbered;
/// `formal` adds the part or chapter signifier in a book. The index
/// section has no title while there are no index terms (it is hidden).
fn numbered_title(section : @core.Node, formal? : Bool = false) -> String {
  if section.sectname == Some("index") && session.index.is_empty() {
    return ""
  }
  let doc = section.document()
  let title = section.title().unwrap_or("")
  let sectnumlevels = @string.parse_int(
    doc.attr("sectnumlevels").unwrap_or("3"),
  ) catch {
    _ => 3
  }
  if section.numbered != NotNumbered &&
    section.caption() is None &&
    section.level <= sectnumlevels {
    if doc.doctype() == "book" && section.level == 0 {
      let numbered = "\{section.sectnum(append=Some(":"))} \{title}"
      if formal {
        let s = signifier(doc, "part-signifier", "Part")
        if s == "" {
          numbered
        } else {
          "\{s} \{numbered}"
        }
      } else {
        numbered
      }
    } else if doc.doctype() == "book" && section.level == 1 {
      let numbered = "\{section.sectnum()} \{title}"
      if formal {
        let s = signifier(doc, "chapter-signifier", "Chapter")
        if s == "" {
          numbered
        } else {
          "\{s} \{numbered}"
        }
      } else {
        numbered
      }
    } else {
      "\{section.sectnum()} \{title}"
    }
  } else if section.level == 0 {
    title
  } else {
    section.captioned_title()
  }
}

///|
/// The width Prawn measures for a string (`rendered_width_of_string`):
/// glyph widths in whole thousandths of an em, kerned throughout.
fn Converter::string_width(
  self : Converter,
  text : String,
  style : Style,
) -> Double {
  let face = self.flow.font(style)
  let scale = style.size / 1000.0
  let mut width = 0.0
  let chars = text.iter().collect()
  for i, c in chars {
    width += face.prawn_width(c.to_int()) * scale
    if i + 1 < chars.length() {
      width += face.kerning(c.to_int(), chars[i + 1].to_int()) * scale
    }
  }
  width
}

///|
/// The page label of a physical page (1-based) when the first
/// `front_matter` pages are front matter: its number counted from the body,
/// else roman.
fn page_label(physical : Int, front_matter : Int) -> String {
  let number = physical - front_matter
  if number < 1 {
    roman(physical, false)
  } else {
    number.to_string()
  }
}

///|
/// asciidoctor-pdf's `ink_toc`: the title and the entries, from `y` on page
/// `page`. In a dry run (`self.flow.scratch`) only the titles are inked,
/// narrowed by the room a page number takes; otherwise the entries get dot
/// leaders and page numbers (labelled after `front_matter` pages). Returns
/// the last page it inked on.
fn Converter::ink_toc(
  self : Converter,
  levels : Int,
  page : Int,
  y : Double,
  front_matter : Int,
) -> Int {
  let flow = self.flow
  flow.go_to_page(page)
  flow.y = y
  flow.top = flow.page_top
  match self.doc.attr("toc-title") {
    Some(title) if title != "" => {
      let align = match t_str("toc_title_text_align") {
        Some(a) => alignment_of(a)
        None => self.heading_align(2)
      }
      self.ink_heading(title, 2, align~, category="toc_title", outdent=true)
    }
    _ => ()
  }
  if levels >= 0 {
    flow.margin(t_num_or("toc_margin_top", 0.0))
    self.ink_toc_level(self.doc.sections(), levels, front_matter)
  }
  flow.page
}

///|
/// The TOC's font for entries of `level` (`theme_font :toc, level:`: the
/// `toc_h<n>_*` keys, else the `toc_*` ones) and its line height.
fn toc_font(level : Int) -> (Style, Double) {
  theme_font_heading(base_style(), base_line_height(), level, category="toc")
}

///|
/// The dot leader of the TOC (`toc_dot_leader_*`): its text (default `. `,
/// in `toc_dot_leader_font_color`, style and size), and the levels that
/// have one (None: all).
priv struct DotLeader {
  text : String
  style : Style
  levels : Array[Int]?
}

///|
fn toc_dot_leader() -> DotLeader {
  let (base, _) = theme_font(base_style(), base_line_height(), "toc")
  let (bold, italic) = font_style_of(
    t_str("toc_dot_leader_font_style").unwrap_or("normal"),
  )
  let size = resolve_font_size(tv("toc_dot_leader_font_size"), base.size).unwrap_or(
    base.size,
  )
  let color = t_color("toc_dot_leader_font_color").unwrap_or(base.color)
  let levels = match tv("toc_dot_leader_levels") {
    Str("none") => Some([])
    Null | Str("all") => None
    v =>
      Some(
        v
        .to_ruby_s()
        .split(" ")
        .filter(s => s != "")
        .map(s => @theme.ruby_string_to_i(s.to_owned()).to_int())
        .collect(),
      )
  }
  {
    text: t_str("toc_dot_leader_content").unwrap_or(". "),
    style: {
      ..base,
      size,
      color,
      doc_bold: bold,
      doc_italic: italic,
      bold,
      italic,
      font_set: true,
    },
    levels,
  }
}

///|
fn Converter::ink_toc_level(
  self : Converter,
  entries : Array[@core.Node],
  levels : Int,
  front_matter : Int,
) -> Unit {
  let flow = self.flow
  let hanging_indent = t_num_or("toc_hanging_indent", 0.0)
  let dot_leader = toc_dot_leader()
  for entry in entries {
    let entry_level = entry.level + 1
    let levels_for_entry = match entry.attr("toclevels") {
      Some(v) => @string.parse_int(v) catch { _ => levels }
      None => levels
    }
    if levels_for_entry < entry_level - 1 {
      continue
    }
    if entry.has_option("notitle") &&
      self.doc.blocks.last() is Some(last) &&
      physical_equal(last, entry) &&
      entry.blocks.is_empty() {
      continue
    }
    let title = numbered_title(entry)
    if title == "" {
      continue
    }
    let (style, line_height) = toc_font(entry_level)
    let face = flow.font(style)
    let metrics = line_metrics(line_height, face, style.size)
    let title = drop_anchors(title)
    let title = match style.text_transform {
      Some(transform) => transform_text(title, transform)
      None => title
    }
    let style = { ..style, text_transform: None, }
    let placeholder = self.string_width(
      "0".repeat(toc_max_pagenum_digits(self.doc)),
      style,
    )
    if flow.scratch {
      // the title alone, as prose (justified), narrowed by the page
      // number's room
      flow.indent(0.0, placeholder, fn() {
        flow.typeset(
          parse_formatted(title, style, normalize=false),
          metrics,
          style,
          align=self.text_align,
          hanging_indent~,
          normalize_line_height=true,
        )
      })
    } else {
      let anchor = match entry.attr("pdf-anchor") {
        Some(a) => a
        None => entry.id.unwrap_or("")
      }
      let label = match entry.attr("pdf-page-start") {
        Some(n) =>
          page_label(@string.parse_int(n) catch { _ => 0 }, front_matter)
        None => "?"
      }
      let start_page = flow.page
      let mut start_y = flow.y
      let linked = { ..style, link: Some(Named(pdf_anchor_name(anchor))), }
      let fragments = parse_formatted(title, linked, normalize=false)
      flow.indent(0.0, placeholder, fn() {
        flow.typeset(
          fragments,
          metrics,
          style,
          align=Left,
          hanging_indent~,
          normalize_line_height=true,
        )
      })
      guard flow.last_line is Some((line, line_page, baseline)) else { break }
      // the dots start after the title's last fragment, on its line: Prawn
      // places fragments by their kerned widths
      let mut start_dots = if flow.last_line_first {
        0.0
      } else {
        hanging_indent
      }
      for run in line.runs {
        start_dots += self.string_width(run.text, run.style)
      }
      let last_top = baseline - line.ascender - metrics.padding_top
      if line_page > start_page ||
        last_top - start_y > metrics.leading + style.size {
        start_y = last_top
      }
      let (end_page, end_y) = (flow.page, flow.y)
      flow.go_to_page(line_page)
      flow.y = start_y
      let leader_here = dot_leader.text != "" &&
        (match dot_leader.levels {
          Some(levels) => levels.contains(entry_level - 1)
          None => true
        })
      let label_fragment : Fragment = {
        text: label,
        style: linked,
        anchor: None,
      }
      if leader_here {
        // the dot leader, a quarter-size no-break space, then the page
        // number
        let dot = self.string_width(dot_leader.text, dot_leader.style)
        let spacer_style = { ..style, size: style.size * 0.25, }
        let spacer = self.string_width("\u{a0}", spacer_style)
        let label_width = self.string_width(label, style)
        let count = @cmp.maximum(
          ((flow.width() - start_dots - spacer - label_width) / dot)
          .floor()
          .to_int(),
          0,
        )
        let leader : Array[Fragment] = [
          {
            text: dot_leader.text.repeat(count),
            style: dot_leader.style,
            anchor: None,
          },
          { text: "\u{a0}", style: spacer_style, anchor: None, },
          label_fragment,
        ]
        flow.typeset(leader, metrics, style, align=Right)
      } else {
        flow.typeset([label_fragment], metrics, style, align=Right)
      }
      flow.go_to_page(end_page)
      flow.y = end_y
    }
    if levels_for_entry >= entry_level {
      flow.indent(toc_indent(), 0.0, fn() {
        self.ink_toc_level(entry.sections(), levels_for_entry, front_matter)
      })
    }
  }
}

///|
/// `toc-max-pagenum-digits` (default 3).
fn toc_max_pagenum_digits(doc : @core.Node) -> Int {
  @string.parse_int(doc.attr("toc-max-pagenum-digits").unwrap_or("3")) catch {
    _ => 3
  }
}

///|
/// asciidoctor-pdf's `allocate_toc`: a dry run of the TOC from the cursor
/// (restarted at the top of the next page when nothing of it fits on this
/// one), then the pages it takes are reserved. With `break_after`, the
/// body starts on the page after the TOC; otherwise it continues below it,
/// after the block margin.
fn Converter::allocate_toc(
  self : Converter,
  levels : Int,
  break_after : Bool,
) -> TocExtent {
  let flow = self.flow
  let at_top = flow.at_page_top()
  let run = fn(start_y : Double) {
    self.dry_run(flow.left, flow.right, start_y~, fn(scratch) {
      ignore(scratch.ink_toc(levels, 0, start_y, 0))
      if !break_after {
        scratch.flow.margin(block_margin_bottom())
      }
    })
  }
  let mut scratch = run(flow.y)
  let mut advanced = false
  // stop_if_first_page_empty: nothing fit on the first page
  if !at_top &&
    scratch.model.pages.length() > 1 &&
    scratch.model.pages[0].items.iter().all(i => i is Anchor(_)) {
    advanced = true
    scratch = run(flow.page_top)
  }
  let start_y = if advanced { flow.page_top } else { flow.y }
  let mut pages = scratch.model.pages.length()
  let mut end_y = scratch.y
  // a trailing blank page is dropped: the extent ends at the bottom of the
  // page before
  if pages > 1 && scratch.at_page_top() {
    pages -= 1
    end_y = flow.bottom
  }
  if advanced {
    flow.advance_page()
  }
  let from_page = flow.page
  if break_after {
    for _ in 0..<pages {
      flow.advance_page()
    }
  } else {
    for _ in 1..<pages {
      flow.advance_page()
    }
    flow.y = end_y
  }
  { from_page, from_y: start_y, to_page: from_page + pages - 1, }
}

///|
/// Whether the document has a TOC to ink: the `toc` attribute and sections
/// to list.
fn has_toc(doc : @core.Node) -> Bool {
  doc.has_attr("toc") && !doc.sections().is_empty()
}

///|
/// asciidoctor-pdf's `convert_toc`: the TOC where the `toc::[]` macro is
/// (`placement` "macro") or at the end of the preamble ("preamble"), when
/// `toc-placement` asks for it there; one TOC per document.
fn Converter::convert_toc(
  self : Converter,
  node : @core.Node,
  placement : String,
) -> Unit {
  if self.toc_extent is Some(_) {
    return
  }
  let doc = self.doc
  let is_macro = placement == "macro"
  if doc.attr("toc-placement") != Some(placement) || !has_toc(doc) {
    return
  }
  let is_book = doc.doctype() == "book"
  let flow = self.flow
  if is_book {
    // start_toc_page: on a new page, a recto one in a prepress book unless
    // the macro is `nonfacing`
    if !flow.at_page_top() {
      flow.advance_page()
    }
    if self.ppbook &&
      flow.on_verso() &&
      !(is_macro && node.has_option("nonfacing")) {
      flow.advance_page()
    }
  }
  if is_macro {
    let id = node.id.unwrap_or("toc")
    let left = (flow.left * 10000.0).floor() / 10000.0
    let x = if left <= flow.margin_left { 0.0 } else { left }
    flow.add_anchor(id, x, flow.y)
    self.toc_node = Some((node, pdf_anchor_name(id)))
  }
  let title_as_page = is_book || doc.has_attr("title-page")
  let extent = self.allocate_toc(resolve_toclevels(doc), title_as_page)
  self.toc_extent = Some(extent)
  // the index numbers pages from the TOC (or after it) when the page
  // numbering starts there
  if title_as_page {
    match tv("page_numbering_start_at") {
      Str("toc") => session.index.start_page_number = extent.from_page + 1
      Str("after-toc") => {
        // in a prepress book, the recto page after the TOC
        let start = extent.to_page + 2
        session.index.start_page_number = if self.ppbook && start % 2 == 0 {
          start + 1
        } else {
          start
        }
      }
      _ => ()
    }
  }
  if is_macro {
    for periphery in ["header", "footer"] {
      if node.has_option("no" + periphery) {
        let pages = self.disable_running_content[periphery]
        for pgnum in (extent.from_page + 1)..<=(extent.to_page + 1) {
          pages.push(pgnum)
        }
      }
    }
  }
}
