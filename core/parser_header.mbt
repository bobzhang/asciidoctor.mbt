///|
/// Parses the document (Ruby `Parser.parse`).
fn parse_document(
  reader : Reader,
  document : Node,
  header_only~ : Bool,
) -> Unit {
  let mut block_attributes = parse_document_header(
    reader, document, header_only,
  )
  if !header_only {
    while reader.has_more_lines() {
      let (new_section, attrs) = next_section(
        reader, document, block_attributes,
      )
      block_attributes = attrs
      match new_section {
        Some(s) => {
          document.assign_numeral(s)
          document.blocks.push(s)
        }
        None => ()
      }
    }
  }
}

///|
fn parse_document_header(
  reader : Reader,
  document : Node,
  header_only : Bool,
) -> Attributes {
  let block_attrs = if reader.skip_blank_lines() is Some(_) {
    parse_block_metadata_lines(reader, document, Attributes::new())
  } else {
    Attributes::new()
  }
  let doc_attrs = document.attributes
  let dd = document.doc()
  let implicit_doctitle = is_next_line_doctitle(
    reader,
    block_attrs,
    doc_attrs.str("leveloffset"),
  )
  if implicit_doctitle &&
    (block_attrs.truthy("title") || block_attrs.truthy("style")) {
    doc_attrs.set("authorcount", Int(0))
    return document.finalize_header(block_attrs, header_valid=false)
  }
  let mut doctitle_attr_val : String? = None
  match doc_attrs.str("doctitle") {
    Some(val) if val != "" => {
      document.set_title(Some(val))
      doctitle_attr_val = Some(val)
    }
    _ => ()
  }
  if implicit_doctitle {
    let source_location = if dd.sourcemap {
      Some(reader.cursor())
    } else {
      None
    }
    let (id, _, l0_title, _, atx) = parse_section_title(reader, document, None)
    document.id = id
    let mut l0_section_title : String? = Some(l0_title)
    if doctitle_attr_val is Some(_) {
      l0_section_title = None
    } else {
      document.set_title(Some(l0_title))
      let mut v = sub_specialchars(l0_title)
      doc_attrs.set_str("doctitle", v)
      if v.contains("{") {
        v = document.sub_attributes(v, attribute_missing="skip")
        doc_attrs.set_str("doctitle", v)
      }
      doctitle_attr_val = Some(v)
    }
    match source_location {
      Some(sl) => dd.header.unwrap().source_location = Some(sl)
      None => ()
    }
    if !atx && !document.attribute_locked("compat-mode") {
      doc_attrs.set_str("compat-mode", "")
    }
    match block_attrs.str("separator") {
      Some(sep) =>
        if !document.attribute_locked("title-separator") {
          doc_attrs.set_str("title-separator", sep)
        }
      None => ()
    }
    let doc_id = match block_attrs.str("id") {
      Some(i) => {
        document.id = Some(i)
        Some(i)
      }
      None => document.id
    }
    match block_attrs.str("role") {
      Some(r) => doc_attrs.set_str("role", r)
      None => ()
    }
    match block_attrs.str("reftext") {
      Some(r) => doc_attrs.set_str("reftext", r)
      None => ()
    }
    block_attrs.clear()
    let modified_attrs = dd.attributes_modified
    modified_attrs.remove("doctitle")
    parse_header_metadata(reader, Some(document)) |> ignore
    if modified_attrs.contains("doctitle") {
      match doc_attrs.str("doctitle") {
        Some(val) if val != "" && Some(val) != doctitle_attr_val =>
          document.set_title(Some(val))
        _ =>
          match doctitle_attr_val {
            Some(v) => doc_attrs.set_str("doctitle", v)
            None => ()
          }
      }
    } else if l0_section_title is None {
      modified_attrs["doctitle"] = true
    }
    match doc_id {
      Some(i) => document.register_ref(i, document) |> ignore
      None => ()
    }
  } else if doc_attrs.str("author") is Some(author) {
    let author_metadata = process_authors(
      [author],
      names_only=true,
      multiple=false,
    )
    if doc_attrs.truthy("authorinitials") {
      author_metadata.remove("authorinitials") |> ignore
    }
    doc_attrs.update(author_metadata)
  } else if doc_attrs.str("authors") is Some(author) {
    let author_metadata = process_authors([author], names_only=true)
    doc_attrs.update(author_metadata)
  } else {
    doc_attrs.set("authorcount", Int(0))
  }
  if document.doctype() == "manpage" {
    parse_manpage_header(reader, document, block_attrs, header_only)
  }
  document.finalize_header(block_attrs)
}

///|
fn parse_manpage_header(
  reader : Reader,
  document : Node,
  block_attributes : Attributes,
  header_only : Bool,
) -> Unit {
  let doc_attrs = document.attributes
  let mut manvolnum = "1"
  match manpage_title_volnum_rx.find(doc_attrs.str("doctitle").unwrap_or("")) {
    Some(m) => {
      manvolnum = m.at(2)
      doc_attrs.set_str("manvolnum", manvolnum)
      let mantitle = m.at(1)
      doc_attrs.set_str(
        "mantitle",
        @rb.downcase(
          if mantitle.contains("{") {
            document.sub_attributes(mantitle)
          } else {
            mantitle
          },
        ),
      )
    }
    None => {
      log_error(
        "non-conforming manpage title",
        source_location=reader.cursor_at_line(1),
      )
      doc_attrs.set_str(
        "mantitle",
        match doc_attrs.str("doctitle") {
          Some(t) => t
          None => doc_attrs.str("docname").unwrap_or("command")
        },
      )
      doc_attrs.set_str("manvolnum", "1")
    }
  }
  let set_output = fn(manname : String) {
    if document.backend() == "manpage" {
      doc_attrs.set_str("docname", manname)
      doc_attrs.set_str("outfilesuffix", ".\{manvolnum}")
    }
  }
  match (doc_attrs.str("manname"), doc_attrs.str("manpurpose")) {
    (Some(manname), Some(_)) => {
      doc_attrs.set_default("manname-title", Str("Name"))
      doc_attrs.set("mannames", List([manname]))
      set_output(manname)
    }
    _ =>
      if !header_only {
        reader.skip_blank_lines() |> ignore
        reader.save()
        block_attributes.update(
          parse_block_metadata_lines(reader, document, Attributes::new()),
        )
        let mut error_msg : String? = None
        match is_next_line_section(reader, Attributes::new()) {
          Some(1) => {
            let name_section = initialize_section(
              reader,
              document,
              Attributes::new(),
            )
            let name_section_buffer = reader
              .read_lines_until(
                break_on_blank_lines=true,
                skip_line_comments=true,
              )
              .map(@rb.lstrip)
              .join(" ")
            match manpage_name_purpose_rx.find(name_section_buffer) {
              Some(m) => {
                let mut manname = m.at(1)
                if manname.contains("{") {
                  manname = document.sub_attributes(manname)
                }
                let mannames = if manname.contains(",") {
                  @rb.split(manname, ",").map(@rb.lstrip)
                } else {
                  [manname]
                }
                manname = mannames[0]
                let mut manpurpose = m.at(2)
                if manpurpose.contains("{") {
                  manpurpose = document.sub_attributes(manpurpose)
                }
                doc_attrs.set_default(
                  "manname-title",
                  match name_section.title() {
                    Some(t) => Str(t)
                    None => Nil
                  },
                )
                match name_section.id {
                  Some(i) => doc_attrs.set_str("manname-id", i)
                  None => ()
                }
                doc_attrs.set_str("manname", manname)
                doc_attrs.set("mannames", List(mannames))
                doc_attrs.set_str("manpurpose", manpurpose)
                set_output(manname)
              }
              None => error_msg = Some("non-conforming name section body")
            }
          }
          Some(_) => error_msg = Some("name section must be at level 1")
          None => error_msg = Some("name section expected")
        }
        match error_msg {
          Some(msg) => {
            reader.restore_save()
            log_error(msg, source_location=reader.cursor())
            let manname = doc_attrs.str("docname").unwrap_or("command")
            doc_attrs.set_str("manname", manname)
            doc_attrs.set("mannames", List([manname]))
            set_output(manname)
          }
          None => reader.discard_save()
        }
      }
  }
}

///|
/// Parses the next section (Ruby `Parser.next_section`).
fn next_section(
  reader : Reader,
  parent : Node,
  attributes : Attributes,
) -> (Node?, Attributes) {
  let mut attributes = attributes
  let mut preamble : Node? = None
  let mut intro : Node? = None
  let mut part = false
  let mut section = parent
  let mut current_level = 0
  let mut expected_next_level : Int? = None
  let mut expected_next_level_alt : Int? = None
  let mut sectname = ""
  let document = parent.document()
  let book = document.doctype() == "book"
  let parent_is_doc_start = parent.context == Document &&
    parent.blocks.is_empty() &&
    ({
      let has_header = parent.has_header()
      has_header ||
      attributes.remove("invalid-header") is Some(_) ||
      is_next_line_section(reader, attributes) is None
    })
  if parent_is_doc_start {
    let has_header = parent.has_header()
    if has_header || (book && attributes.pos_str(1) != Some("abstract")) {
      let p = Node::new_block(parent, Preamble, content_model=Compound)
      if book && parent.has_attr("preface-title") {
        p.set_title(parent.attr("preface-title"))
      }
      parent.blocks.push(p)
      preamble = Some(p)
      intro = Some(p)
    }
    section = parent
    current_level = 0
    if parent.attributes.contains("fragment") {
      expected_next_level = Some(-1)
    } else if book {
      expected_next_level = Some(1)
      expected_next_level_alt = Some(0)
    } else {
      expected_next_level = Some(1)
    }
  } else {
    section = initialize_section(reader, parent, attributes)
    attributes = match attributes.get("title") {
      Some(t) if t.truthy() => Attributes::from_array([("title", t)])
      _ => Attributes::new()
    }
    current_level = section.level
    expected_next_level = Some(current_level + 1)
    if current_level == 0 {
      part = book
    } else if current_level == 1 && section.special {
      sectname = section.sectname.unwrap_or("")
      if !(sectname == "appendix" ||
        sectname == "preface" ||
        sectname == "abstract") {
        expected_next_level = None
      }
    }
  }
  reader.skip_blank_lines() |> ignore
  while reader.has_more_lines() {
    parse_block_metadata_lines(reader, document, attributes) |> ignore
    match is_next_line_section(reader, attributes) {
      Some(nl) => {
        let mut next_level = nl
        if document.has_attr("leveloffset") {
          next_level += @rb.to_i(document.attr("leveloffset").unwrap_or("0"))
          if next_level < 0 {
            next_level = 0
          }
        }
        if next_level > current_level {
          match expected_next_level {
            Some(enl) =>
              if !(next_level == enl ||
                expected_next_level_alt == Some(next_level) ||
                enl < 0) {
                let expected_condition = match expected_next_level_alt {
                  Some(alt) => "expected levels \{alt} or \{enl}"
                  None => "expected level \{enl}"
                }
                log_warn(
                  "section title out of sequence: \{expected_condition}, got level \{next_level}",
                  source_location=reader.cursor(),
                )
              }
            None =>
              log_error(
                "\{sectname} sections do not support nested sections",
                source_location=reader.cursor(),
              )
          }
          let (new_section, attrs2) = next_section(reader, section, attributes)
          attributes = attrs2
          section.assign_numeral(new_section.unwrap())
          section.blocks.push(new_section.unwrap())
        } else if next_level == 0 && physical_equal(section, document) {
          if !book {
            log_error(
              "level 0 sections can only be used when doctype is book",
              source_location=reader.cursor(),
            )
          }
          let (new_section, attrs2) = next_section(reader, section, attributes)
          attributes = attrs2
          section.assign_numeral(new_section.unwrap())
          section.blocks.push(new_section.unwrap())
        } else {
          break
        }
      }
      None => {
        let block_cursor = reader.cursor()
        let target_parent = match intro {
          Some(i) => i
          None => section
        }
        match
          next_block(reader, target_parent, attributes, parse_metadata=false) {
          Some(new_block) => {
            if part {
              if !section.has_blocks() {
                if new_block.style != Some("partintro") {
                  if new_block.style == Some("open") &&
                    new_block.context == Open {
                    new_block.style = Some("partintro")
                  } else {
                    let i = Node::new_block(
                      section,
                      Open,
                      content_model=Compound,
                    )
                    new_block.set_parent(i)
                    i.style = Some("partintro")
                    section.blocks.push(i)
                    intro = Some(i)
                  }
                } else if new_block.content_model == Simple {
                  new_block.content_model = Compound
                  new_block.append(
                    Node::new_block(
                      new_block,
                      Paragraph,
                      source=new_block.lines,
                      subs=ExplicitSubs(new_block.subs),
                    ),
                  )
                  new_block.lines.clear()
                  new_block.subs.clear()
                }
              } else if section.blocks.length() == 1 {
                let first_block = section.blocks[0]
                if intro is None && first_block.content_model == Compound {
                  log_error(
                    "illegal block content outside of partintro block",
                    source_location=block_cursor,
                  )
                } else if first_block.content_model != Compound {
                  let i = Node::new_block(section, Open, content_model=Compound)
                  new_block.set_parent(i)
                  i.style = Some("partintro")
                  if first_block.style == Some("partintro") {
                    first_block.set_context(Paragraph)
                    first_block.style = None
                  }
                  section.blocks.remove(0) |> ignore
                  i.append(first_block)
                  section.blocks.push(i)
                  intro = Some(i)
                }
              }
            }
            match intro {
              Some(i) => i.blocks.push(new_block)
              None => section.blocks.push(new_block)
            }
            attributes.clear()
          }
          None => ()
        }
      }
    }
    if reader.skip_blank_lines() is None {
      break
    }
  }
  if part {
    if !(section.has_blocks() &&
      section.blocks[section.blocks.length() - 1].context == Section) {
      log_error(
        "invalid part, must have at least one section (e.g., chapter, appendix, etc.)",
        source_location=reader.cursor(),
      )
    }
  } else {
    match preamble {
      Some(p) =>
        if p.has_blocks() {
          if book ||
            document.blocks.length() > 1 ||
            !compliance.unwrap_standalone_preamble {
            if document.sourcemap() {
              p.source_location = p.blocks[0].source_location
            }
          } else {
            document.blocks.remove(0) |> ignore
            while !p.blocks.is_empty() {
              let child = p.blocks.remove(0)
              document.append(child)
            }
          }
        } else {
          document.blocks.remove(0) |> ignore
        }
      None => ()
    }
  }
  (
    if physical_equal(section, parent) {
      None
    } else {
      Some(section)
    },
    attributes.copy(),
  )
}

///|
/// Creates a section from the title at the reader position (Ruby `initialize_section`).
fn initialize_section(
  reader : Reader,
  parent : Node,
  attributes : Attributes,
) -> Node {
  let document = parent.document()
  let doctype = document.doctype()
  let book = doctype == "book"
  let source_location = if document.sourcemap() {
    Some(reader.cursor())
  } else {
    None
  }
  let sect_style = attributes.pos_str(1)
  let (sect_id, sect_reftext, sect_title, sect_level0, sect_atx) = parse_section_title(
    reader,
    document,
    attributes.str("id"),
  )
  let mut sect_level = sect_level0
  let mut sect_name = "section"
  let mut sect_special = false
  let mut sect_numbered = false
  match sect_style {
    Some(style) =>
      if book && style == "abstract" {
        sect_name = "chapter"
        sect_level = 1
      } else if style.has_prefix("sect") &&
        section_level_style_rx.matches(style) {
        sect_name = "section"
      } else {
        sect_name = style
        sect_special = true
        if sect_level == 0 {
          sect_level = 1
        }
        sect_numbered = sect_name == "appendix"
      }
    None =>
      if book {
        sect_name = if sect_level == 0 {
          "part"
        } else if sect_level > 1 {
          "section"
        } else {
          "chapter"
        }
      } else if doctype == "manpage" &&
        @rb.downcase_ascii(sect_title) == "synopsis" {
        sect_name = "synopsis"
        sect_special = true
      } else {
        sect_name = "section"
      }
  }
  match sect_reftext {
    Some(r) => attributes.set_str("reftext", r)
    None => ()
  }
  let section = Node::new_section(Some(parent), level=sect_level)
  section.id = sect_id
  section.set_title(Some(sect_title))
  section.sectname = Some(sect_name)
  section.source_location = source_location
  if sect_special {
    section.special = true
    if sect_numbered {
      section.numbered = Numbered
    } else if document.attributes.str("sectnums") == Some("all") {
      section.numbered = if book && sect_level == 1 {
        NumberedChapter
      } else {
        Numbered
      }
    }
  } else if document.attributes.truthy("sectnums") && sect_level > 0 {
    section.numbered = if section.special {
      if parent.numbered != NotNumbered {
        Numbered
      } else {
        NotNumbered
      }
    } else {
      Numbered
    }
  } else if book && sect_level == 0 && document.attributes.truthy("partnums") {
    section.numbered = Numbered
  }
  let mut id = section.id
  match id {
    Some(i) =>
      if i == "" {
        section.id = None
        id = None
      } else if sect_title.contains("{") {
        section.title() |> ignore
      }
    None =>
      if document.attributes.contains("sectids") {
        let gid = generate_section_id(section.title().unwrap_or(""), document)
        section.id = Some(gid)
        id = Some(gid)
      }
  }
  match id {
    Some(i) =>
      if !document.register_ref(i, section) {
        log_warn(
          "id assigned to section already in use: \{i}",
          source_location=reader.cursor_at_line(
            reader.lineno() - (if sect_atx { 1 } else { 2 }),
          ),
        )
      }
    None => ()
  }
  section.update_attributes(attributes)
  reader.skip_blank_lines() |> ignore
  section
}

///|
/// Level of the section title at the reader position, if any.
fn is_next_line_section(reader : Reader, attributes : Attributes) -> Int? {
  let style = attributes.pos_str(1)
  if style == Some("discrete") || style == Some("float") {
    return None
  }
  if compliance.underline_style_section_titles {
    let next_lines = reader.peek_lines(num=2, direct=style == Some("comment"))
    is_section_title(next_lines.get(0).unwrap_or(""), next_lines.get(1))
  } else {
    atx_section_title(reader.peek_line().unwrap_or(""))
  }
}

///|
fn is_next_line_doctitle(
  reader : Reader,
  attributes : Attributes,
  leveloffset : String?,
) -> Bool {
  match leveloffset {
    Some(lo) =>
      match is_next_line_section(reader, attributes) {
        Some(sl) => sl + @rb.to_i(lo) == 0
        None => false
      }
    None => is_next_line_section(reader, attributes) == Some(0)
  }
}

///|
fn is_section_title(line1 : String, line2 : String?) -> Int? {
  match atx_section_title(line1) {
    Some(l) => Some(l)
    None =>
      match line2 {
        Some(l2) if l2 != "" => setext_section_title(line1, l2)
        _ => None
      }
  }
}

///|
fn atx_section_title(line : String) -> Int? {
  let m = if compliance.markdown_syntax {
    if line.has_prefix("=") || line.has_prefix("#") {
      ext_atx_section_title_rx.find(line)
    } else {
      None
    }
  } else if line.has_prefix("=") {
    atx_section_title_rx.find(line)
  } else {
    None
  }
  match m {
    Some(m) => Some(m.at(1).length() - 1)
    None => None
  }
}

///|
fn setext_level(ch : String) -> Int? {
  match ch {
    "=" => Some(0)
    "-" => Some(1)
    "~" => Some(2)
    "^" => Some(3)
    "+" => Some(4)
    _ => None
  }
}

///|
fn first_char(s : String) -> String {
  if s == "" {
    ""
  } else {
    let w = if s[0] >= 0xD800 && s[0] <= 0xDBFF && s.length() > 1 {
      2
    } else {
      1
    }
    s.unsafe_substring(start=0, end=w)
  }
}

///|
fn setext_section_title(line1 : String, line2 : String) -> Int? {
  let ch0 = first_char(line2)
  match setext_level(ch0) {
    Some(level) => {
      let line2_len = line2.length()
      if is_uniform(line2, ch0, line2_len) &&
        setext_section_title_rx.matches(line1) &&
        (@rb.char_length(line1) - @rb.char_length(line2)).abs() < 2 {
        Some(level)
      } else {
        None
      }
    }
    None => None
  }
}

///|
/// Parses a section title (Ruby `parse_section_title`): (id, reftext, title, level, atx).
fn parse_section_title(
  reader : Reader,
  document : Node,
  sect_id : String?,
) -> (String?, String?, String, Int, Bool) {
  let mut sect_id = sect_id
  let mut sect_reftext : String? = None
  let line1 = reader.read_line().unwrap_or("")
  let mut sect_level = 0
  let mut sect_title = ""
  let mut atx = false
  let atx_m = if compliance.markdown_syntax {
    if line1.has_prefix("=") || line1.has_prefix("#") {
      ext_atx_section_title_rx.find(line1)
    } else {
      None
    }
  } else if line1.has_prefix("=") {
    atx_section_title_rx.find(line1)
  } else {
    None
  }
  match atx_m {
    Some(m) => {
      sect_level = m.at(1).length() - 1
      sect_title = m.at(2)
      atx = true
      if sect_id is None && sect_title.has_suffix("]]") {
        match inline_section_anchor_rx.find(sect_title) {
          Some(am) if !am.has(1) => {
            sect_title = @rb.slice(
              sect_title,
              0,
              sect_title.length() - am.matched().length(),
            )
            sect_id = am.group(2)
            sect_reftext = am.group(3)
          }
          _ => ()
        }
      }
    }
    None => {
      let line2 = if compliance.underline_style_section_titles {
        reader.peek_line(direct=true)
      } else {
        None
      }
      let setext = match line2 {
        Some(l2) if l2 != "" =>
          match setext_level(first_char(l2)) {
            Some(level) =>
              if is_uniform(l2, first_char(l2), l2.length()) &&
                (@rb.char_length(line1) - @rb.char_length(l2)).abs() < 2 {
                match setext_section_title_rx.find(line1) {
                  Some(m) => Some((level, m.at(1)))
                  None => None
                }
              } else {
                None
              }
            None => None
          }
        _ => None
      }
      match setext {
        Some((level, title)) => {
          sect_level = level
          sect_title = title
          atx = false
          if sect_id is None && sect_title.has_suffix("]]") {
            match inline_section_anchor_rx.find(sect_title) {
              Some(am) if !am.has(1) => {
                sect_title = @rb.slice(
                  sect_title,
                  0,
                  sect_title.length() - am.matched().length(),
                )
                sect_id = am.group(2)
                sect_reftext = am.group(3)
              }
              _ => ()
            }
          }
          reader.shift() |> ignore
        }
        None =>
          abort(
            "Unrecognized section at \{reader.cursor_at_prev_line().line_info()}",
          )
      }
    }
  }
  if document.has_attr("leveloffset") {
    sect_level += @rb.to_i(document.attr("leveloffset").unwrap_or("0"))
    if sect_level < 0 {
      sect_level = 0
    }
  }
  (sect_id, sect_reftext, sect_title, sect_level, atx)
}

///|
/// Parses the author and revision lines (Ruby `parse_header_metadata`).
fn parse_header_metadata(reader : Reader, document : Node?) -> Attributes {
  let doc_attrs = document.map(d => d.attributes)
  process_attribute_entries(reader, document, None)
  let mut implicit_author_metadata = Attributes::new()
  let rev_metadata = Attributes::new()
  let mut author_metadata : Attributes? = None
  let mut implicit_author : String? = None
  let mut implicit_authorinitials : String? = None
  let mut implicit_authors : String? = None
  let mut authorcount : Int? = None
  if reader.has_more_lines() && !reader.next_line_empty() {
    implicit_author_metadata = process_authors([reader.read_line().unwrap()])
    let ac = implicit_author_metadata
      .remove("authorcount")
      .map(v => v.to_i())
      .unwrap_or(0)
    authorcount = Some(ac)
    match (document, doc_attrs) {
      (Some(doc), Some(da)) => {
        da.set("authorcount", Int(ac))
        if ac > 0 {
          for k, v in implicit_author_metadata.iter() {
            if k is Name(key) && !da.contains(key) {
              da.set_str(key, doc.apply_header_subs(v.to_s()))
            }
          }
          implicit_author = da.str("author")
          implicit_authorinitials = da.str("authorinitials")
          implicit_authors = da.str("authors")
        }
      }
      _ => ()
    }
    implicit_author_metadata.set("authorcount", Int(ac))
    process_attribute_entries(reader, document, None)
    if reader.has_more_lines() && !reader.next_line_empty() {
      let rev_line = reader.read_line().unwrap()
      match revision_info_line_rx.find(rev_line) {
        Some(m) => {
          match m.group(1) {
            Some(g1) => rev_metadata.set_str("revnumber", @rb.rstrip(g1))
            None => ()
          }
          let component = @rb.strip(m.at(2))
          if component != "" {
            if !m.has(1) && component.has_prefix("v") {
              rev_metadata.set_str("revnumber", @rb.from(component, 1))
            } else {
              rev_metadata.set_str("revdate", component)
            }
          }
          match m.group(3) {
            Some(g3) => rev_metadata.set_str("revremark", @rb.rstrip(g3))
            None => ()
          }
          match (document, doc_attrs) {
            (Some(doc), Some(da)) if !rev_metadata.is_empty() =>
              for k, v in rev_metadata.iter() {
                if k is Name(key) && !da.contains(key) {
                  da.set_str(key, doc.apply_header_subs(v.to_s()))
                }
              }
            _ => ()
          }
        }
        None => reader.unshift_line(rev_line)
      }
    }
    process_attribute_entries(reader, document, None)
    reader.skip_blank_lines() |> ignore
  }
  match doc_attrs {
    Some(da) => {
      let mut am : Attributes = Attributes::new()
      if da.contains("author") && da.str("author") != implicit_author {
        am = process_authors(
          [da.str("author").unwrap_or("")],
          names_only=true,
          multiple=false,
        )
        if da.str("authorinitials") != implicit_authorinitials {
          am.remove("authorinitials") |> ignore
        }
      } else if da.contains("authors") && da.str("authors") != implicit_authors {
        am = process_authors([da.str("authors").unwrap_or("")], names_only=true)
      } else {
        let authors : Array[String?] = []
        let mut author_idx = 1
        let mut author_key = "author_1"
        let mut explicit = false
        let mut sparse = false
        while da.contains(author_key) {
          let author_override = da.str(author_key)
          if author_override == implicit_author_metadata.str(author_key) {
            authors.push(None)
            sparse = true
          } else {
            authors.push(author_override)
            explicit = true
          }
          author_idx += 1
          author_key = "author_\{author_idx}"
        }
        if explicit {
          if sparse {
            for idx, author in authors {
              if author is None {
                let name_idx = idx + 1
                let parts = [
                  implicit_author_metadata.str("firstname_\{name_idx}"),
                  implicit_author_metadata.str("middlename_\{name_idx}"),
                  implicit_author_metadata.str("lastname_\{name_idx}"),
                ]
                authors[idx] = Some(
                  parts
                  .filter(p => p is Some(_))
                  .map(p => p.unwrap().replace_all(old=" ", new="_"))
                  .join(" "),
                )
              }
            }
          }
          am = process_authors(
            authors.map(a => a.unwrap_or("")),
            names_only=true,
            multiple=false,
          )
        } else {
          am = Attributes::from_array([("authorcount", Int(0))])
        }
      }
      if am.get("authorcount").map(v => v.to_i()) == Some(0) {
        if authorcount is Some(_) {
          author_metadata = None
        } else {
          da.set("authorcount", Int(0))
        }
      } else {
        da.update(am)
        author_metadata = Some(am)
        if !da.contains("email") && da.contains("email_1") {
          da.set("email", da.get("email_1").unwrap())
        }
      }
    }
    None => ()
  }
  let result = implicit_author_metadata.copy()
  result.update(rev_metadata)
  match author_metadata {
    Some(am) => result.update(am)
    None => ()
  }
  result
}

///|
let author_keys : Array[String] = [
  "author", "authorinitials", "firstname", "middlename", "lastname", "email",
]

///|
/// Parses author lines (Ruby `process_authors`).
fn process_authors(
  author_lines : Array[String],
  names_only? : Bool = false,
  multiple? : Bool = true,
) -> Attributes {
  let author_metadata = Attributes::new()
  let mut author_idx = 0
  let entries = if multiple &&
    author_lines.length() == 1 &&
    author_lines[0].contains(";") {
    author_delimiter_rx.split(author_lines[0])
  } else {
    author_lines
  }
  for author_entry0 in entries {
    let mut author_entry = author_entry0
    if author_entry == "" {
      continue
    }
    author_idx += 1
    let key = fn(k : String) {
      if author_idx == 1 {
        k
      } else {
        "\{k}_\{author_idx}"
      }
    }
    let mut segments : Array[String]? = None
    if names_only {
      if author_entry.contains("<") {
        author_metadata.set_str(
          key("author"),
          author_entry.replace_all(old="_", new=" "),
        )
        author_entry = xml_sanitize_rx.gsub(author_entry, "")
      }
      let segs = split_ws_limit(author_entry, 3)
      if segs.length() == 3 {
        segs[2] = @rb.squeeze(segs[2], chars=" ")
      }
      segments = Some(segs)
    } else {
      match author_info_line_rx.find(author_entry) {
        Some(m) => {
          let segs = []
          for i in 1..<m.size() {
            match m.group(i) {
              Some(s) => segs.push(s)
              None => segs.push("\u{0}")
            }
          }
          segments = Some(segs)
        }
        None => ()
      }
    }
    let seg = fn(segs : Array[String], i : Int) -> String? {
      match segs.get(i) {
        Some(s) => if s == "\u{0}" { None } else { Some(s) }
        None => None
      }
    }
    match segments {
      Some(segs) => {
        let fname = seg(segs, 0).unwrap_or("").replace_all(old="_", new=" ")
        let mut author = fname
        author_metadata.set_str(key("firstname"), fname)
        author_metadata.set_str(key("authorinitials"), first_char(fname))
        match seg(segs, 1) {
          Some(s1) =>
            match seg(segs, 2) {
              Some(s2) => {
                let mname = s1.replace_all(old="_", new=" ")
                let lname = s2.replace_all(old="_", new=" ")
                author_metadata.set_str(key("middlename"), mname)
                author_metadata.set_str(key("lastname"), lname)
                author = fname + " " + mname + " " + lname
                author_metadata.set_str(
                  key("authorinitials"),
                  "\{first_char(fname)}\{first_char(mname)}\{first_char(lname)}",
                )
              }
              None => {
                let lname = s1.replace_all(old="_", new=" ")
                author_metadata.set_str(key("lastname"), lname)
                author = fname + " " + lname
                author_metadata.set_str(
                  key("authorinitials"),
                  "\{first_char(fname)}\{first_char(lname)}",
                )
              }
            }
          None => ()
        }
        author_metadata.set_default(key("author"), Str(author))
        if !names_only {
          match seg(segs, 3) {
            Some(email) => author_metadata.set_str(key("email"), email)
            None => ()
          }
        }
      }
      None => {
        let fname = @rb.strip(@rb.squeeze(author_entry, chars=" "))
        author_metadata.set_str(key("author"), fname)
        author_metadata.set_str(key("firstname"), fname)
        author_metadata.set_str(key("authorinitials"), first_char(fname))
      }
    }
    if author_idx == 1 {
      author_metadata.set(
        "authors",
        author_metadata.get(key("author")).unwrap_or(Nil),
      )
    } else {
      if author_idx == 2 {
        for k in author_keys {
          if author_metadata.contains(k) {
            author_metadata.set("\{k}_1", author_metadata.get(k).unwrap())
          }
        }
      }
      author_metadata.set_str(
        "authors",
        "\{author_metadata.str("authors").unwrap_or("")}, \{author_metadata.str(key("author")).unwrap_or("")}",
      )
    }
  }
  author_metadata.set("authorcount", Int(author_idx))
  author_metadata
}

///|
/// Ruby `str.split(nil, limit)`: whitespace split with a field limit.
fn split_ws_limit(s : String, limit : Int) -> Array[String] {
  let out = []
  let n = s.length()
  let mut i = 0
  while i < n && @rb.is_space(s[i]) {
    i += 1
  }
  while i < n {
    if out.length() == limit - 1 {
      out.push(s.unsafe_substring(start=i, end=n))
      return out
    }
    let start = i
    while i < n && !@rb.is_space(s[i]) {
      i += 1
    }
    out.push(s.unsafe_substring(start~, end=i))
    while i < n && @rb.is_space(s[i]) {
      i += 1
    }
  }
  out
}

///|
/// Parses consecutive block metadata lines.
fn parse_block_metadata_lines(
  reader : Reader,
  document : Node,
  attributes : Attributes,
  text_only? : Bool = false,
) -> Attributes {
  while parse_block_metadata_line(reader, document, attributes, text_only~) {
    reader.shift() |> ignore
    if reader.skip_blank_lines() is None {
      break
    }
  }
  attributes
}

///|
/// Parses one block metadata line (anchor, attribute list, title, comment,
/// attribute entry). Returns true if the line was metadata.
fn parse_block_metadata_line(
  reader : Reader,
  document : Node,
  attributes : Attributes,
  text_only? : Bool = false,
) -> Bool {
  guard reader.peek_line() is Some(next_line) else { return false }
  let normal = !text_only &&
    (
      next_line.has_prefix("[") ||
      next_line.has_prefix(".") ||
      next_line.has_prefix("/") ||
      next_line.has_prefix(":")
    )
  if !(if text_only {
      next_line.has_prefix("[") || next_line.has_prefix("/")
    } else {
      normal
    }) {
    return false
  }
  if next_line.has_prefix("[") {
    if next_line.has_prefix("[[") {
      if next_line.has_suffix("]]") &&
        block_anchor_rx.find(next_line) is Some(m) {
        match m.group(1) {
          Some(id) => attributes.set_str("id", id)
          None => attributes.set("id", Nil)
        }
        match m.group(2) {
          Some(reftext) =>
            attributes.set_str(
              "reftext",
              if reftext.contains("{") {
                document.sub_attributes(reftext)
              } else {
                reftext
              },
            )
          None => ()
        }
        return true
      }
    } else if next_line.has_suffix("]") &&
      block_attribute_list_rx.find(next_line) is Some(m) {
      let current_style = attributes.get_pos(1)
      let parsed = document.parse_attributes(
        m.at(1),
        [],
        sub_input=true,
        sub_result=true,
        into=attributes,
      )
      if parsed.get_pos(1) is Some(v) && v.truthy() {
        match parse_style_attribute(attributes, Some(reader)) {
          Some(s) => attributes.set_pos(1, Str(s))
          None => attributes.set_pos(1, current_style.unwrap_or(Nil))
        }
      }
      return true
    }
  } else if normal && next_line.has_prefix(".") {
    match block_title_rx.find(next_line) {
      Some(m) => {
        attributes.set_str("title", m.at(1))
        return true
      }
      None => ()
    }
  } else if !normal || next_line.has_prefix("/") {
    if next_line.has_prefix("//") {
      if next_line == "//" {
        return true
      } else if normal && is_uniform(next_line, "/", next_line.length()) {
        if next_line.length() != 3 {
          reader.read_lines_until(
            terminator=next_line,
            skip_first_line=true,
            preserve_last_line=true,
            skip_processing=true,
            context=Some("comment"),
          )
          |> ignore
          return true
        }
      } else if !next_line.has_prefix("///") {
        return true
      }
    }
  } else if normal &&
    next_line.has_prefix(":") &&
    attribute_entry_rx.find(next_line) is Some(m) {
    process_attribute_entry(reader, Some(document), Some(attributes), Some(m))
    |> ignore
    return true
  }
  false
}

///|
fn process_attribute_entries(
  reader : Reader,
  document : Node?,
  attributes : Attributes?,
) -> Unit {
  reader.skip_comment_lines()
  while process_attribute_entry(reader, document, attributes, None) {
    reader.shift() |> ignore
    reader.skip_comment_lines()
  }
}

///|
fn process_attribute_entry(
  reader : Reader,
  document : Node?,
  attributes : Attributes?,
  m : @regex.MatchData?,
) -> Bool {
  let m = match m {
    Some(m) => m
    None =>
      if reader.has_more_lines() {
        match attribute_entry_rx.find(reader.peek_line().unwrap_or("")) {
          Some(m) => m
          None => return false
        }
      } else {
        return false
      }
  }
  let mut value = match m.group(2) {
    Some(v) => v
    None => ""
  }
  if value != "" && (value.has_suffix(" \\") || value.has_suffix(" +")) {
    let con = @rb.from(value, value.length() - 2)
    value = @rb.rstrip(@rb.slice(value, 0, value.length() - 2))
    while reader.advance() {
      let next_line0 = reader.peek_line().unwrap_or("")
      if next_line0 == "" {
        break
      }
      let mut next_line = @rb.lstrip(next_line0)
      let keep_open = next_line.has_suffix(con)
      if keep_open {
        next_line = @rb.rstrip(@rb.slice(next_line, 0, next_line.length() - 2))
      }
      value = "\{value}\{if value.has_suffix(" +") { "\n" } else { " " }}\{next_line}"
      if !keep_open {
        break
      }
    }
  }
  store_attribute(m.at(1), Some(value), doc=document, attrs=attributes)
  |> ignore
  true
}

///|
/// Stores an attribute entry (Ruby `Parser.store_attribute`); returns (name, value).
fn store_attribute(
  name : String,
  value : String?,
  doc~ : Node?,
  attrs~ : Attributes?,
) -> (String, String?) {
  let mut name = name
  let mut value = value
  if name.has_suffix("!") {
    name = @rb.chop(name)
    value = None
  } else if name.has_prefix("!") {
    name = @rb.from(name, 1)
    value = None
  }
  name = sanitize_attribute_name(name)
  if name == "numbered" {
    name = "sectnums"
  } else if name == "hardbreaks" {
    name = "hardbreaks-option"
  } else if name == "showtitle" {
    store_attribute(
      "notitle",
      if value is Some(_) {
        None
      } else {
        Some("")
      },
      doc~,
      attrs~,
    )
    |> ignore
  }
  match doc {
    Some(d) =>
      match value {
        Some(v0) => {
          let mut v = v0
          if name == "leveloffset" {
            if v.has_prefix("+") {
              v = (@rb.to_i(d.attr("leveloffset", default="0").unwrap_or("0")) +
              @rb.to_i(@rb.from(v, 1))).to_string()
            } else if v.has_prefix("-") {
              v = (@rb.to_i(d.attr("leveloffset", default="0").unwrap_or("0")) -
              @rb.to_i(@rb.from(v, 1))).to_string()
            }
          }
          match d.set_attribute(name, value=v) {
            Some(resolved) => {
              value = Some(resolved)
              match attrs {
                Some(a) =>
                  a.save_entry(AttributeEntry::new(name, Some(resolved)))
                None => ()
              }
            }
            None => value = Some(v)
          }
        }
        None =>
          if d.delete_attribute(name) {
            match attrs {
              Some(a) => a.save_entry(AttributeEntry::new(name, None))
              None => ()
            }
          }
      }
    None =>
      match attrs {
        Some(a) => a.save_entry(AttributeEntry::new(name, value))
        None => ()
      }
  }
  (name, value)
}

///|
fn sanitize_attribute_name(name : String) -> String {
  @rb.downcase(invalid_attribute_name_chars_rx.gsub(name, ""))
}

///|
/// Whether `str` consists of `len` copies of `chr` (Ruby `uniform?`).
fn is_uniform(str : String, chr : String, len : Int) -> Bool {
  @rb.count(str, chr) * chr.length() == len && str.length() == len
}

///|
/// Parses the style attribute shorthand (`#id.role%option`), Ruby `parse_style_attribute`.
fn parse_style_attribute(attributes : Attributes, reader : Reader?) -> String? {
  match attributes.pos_str(1) {
    Some(raw_style) if !raw_style.contains(" ") &&
      compliance.shorthand_property_syntax => {
      let mut name : String? = None
      let accum = StringBuilder()
      let mut parsed_style : String? = None
      let mut parsed_id : String? = None
      let mut has_id = false
      let roles : Array[String] = []
      let mut has_role = false
      let options : Array[String] = []
      let mut has_option = false
      let flush = fn(nm : String?, value : String) {
        match nm {
          Some(n) =>
            if value == "" {
              match reader {
                Some(r) =>
                  log_warn(
                    "invalid empty \{n} detected in style attribute",
                    source_location=r.cursor_at_prev_line(),
                  )
                None =>
                  log_warn("invalid empty \{n} detected in style attribute")
              }
            } else if n == "id" {
              if has_id {
                match reader {
                  Some(r) =>
                    log_warn(
                      "multiple ids detected in style attribute",
                      source_location=r.cursor_at_prev_line(),
                    )
                  None => log_warn("multiple ids detected in style attribute")
                }
              }
              has_id = true
              parsed_id = Some(value)
            } else if n == "role" {
              has_role = true
              roles.push(value)
            } else {
              has_option = true
              options.push(value)
            }
          None => if value != "" { parsed_style = Some(value) }
        }
      }
      for c in raw_style {
        match c {
          '.' => {
            flush(name, accum.to_string())
            accum.reset()
            name = Some("role")
          }
          '#' => {
            flush(name, accum.to_string())
            accum.reset()
            name = Some("id")
          }
          '%' => {
            flush(name, accum.to_string())
            accum.reset()
            name = Some("option")
          }
          _ => accum.write_char(c)
        }
      }
      match name {
        Some(_) => {
          flush(name, accum.to_string())
          match parsed_style {
            Some(s) => attributes.set_str("style", s)
            None => ()
          }
          if has_id {
            match parsed_id {
              Some(i) => attributes.set_str("id", i)
              None => ()
            }
          }
          if has_role {
            let existing = attributes.str("role")
            attributes.set_str(
              "role",
              match existing {
                Some(e) if e != "" => "\{e} \{roles.join(" ")}"
                _ => roles.join(" ")
              },
            )
          }
          if has_option {
            for opt in options {
              attributes.set_str("\{opt}-option", "")
            }
          }
          parsed_style
        }
        None => {
          attributes.set_str("style", raw_style)
          Some(raw_style)
        }
      }
    }
    raw => {
      match raw {
        Some(s) => attributes.set_str("style", s)
        None => attributes.set("style", Nil)
      }
      raw
    }
  }
}

///|
/// Adjusts indentation of lines (Ruby `adjust_indentation!`).
fn adjust_indentation(
  lines : Array[String],
  indent_size? : Int = 0,
  tab_size? : Int = 0,
) -> Unit {
  if lines.is_empty() {
    return
  }
  if tab_size > 0 && lines.iter().any(l => l.contains("\t")) {
    let full_tab_space = @rb.repeat(" ", tab_size)
    for i, line0 in lines {
      if line0 == "" || !line0.contains("\t") {
        continue
      }
      let mut line = line0
      if line.has_prefix("\t") {
        let mut leading_tabs = 0
        while leading_tabs < line.length() && line[leading_tabs] == '\t' {
          leading_tabs += 1
        }
        line = @rb.repeat(full_tab_space, leading_tabs) +
          @rb.from(line, leading_tabs)
        if !line.contains("\t") {
          lines[i] = line
          continue
        }
      }
      let mut spaces_added = 0
      let mut idx = 0
      let result = StringBuilder()
      for c in line {
        if c == '\t' {
          let offset = idx + spaces_added
          if offset % tab_size == 0 {
            spaces_added += tab_size - 1
            result.write_string(full_tab_space)
          } else {
            let spaces = tab_size - offset % tab_size
            if spaces != 1 {
              spaces_added += spaces - 1
            }
            result.write_string(@rb.repeat(" ", spaces))
          }
        } else {
          result.write_char(c)
        }
        idx += 1
      }
      lines[i] = result.to_string()
    }
  }
  if indent_size < 0 {
    return
  }
  let mut block_indent : Int? = None
  for line in lines {
    if line == "" {
      continue
    }
    let line_indent = line.length() - @rb.lstrip(line).length()
    if line_indent == 0 {
      block_indent = None
      break
    }
    match block_indent {
      Some(bi) if bi < line_indent => ()
      _ => block_indent = Some(line_indent)
    }
  }
  if indent_size == 0 {
    match block_indent {
      Some(bi) =>
        for i, line in lines {
          if line != "" {
            lines[i] = @rb.from(line, bi)
          }
        }
      None => ()
    }
  } else {
    let new_block_indent = @rb.repeat(" ", indent_size)
    for i, line in lines {
      if line != "" {
        lines[i] = match block_indent {
          Some(bi) => new_block_indent + @rb.from(line, bi)
          None => new_block_indent + line
        }
      }
    }
  }
}
