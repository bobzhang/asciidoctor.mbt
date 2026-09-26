///|
priv struct BlockMatchData {
  context : Context
  masq : Array[String]
  tip : String
  terminator : String
}

///|
fn delimited_block_info(tip : String) -> (Context, Array[String])? {
  match tip {
    "--" =>
      Some(
        (
          Open,
          [
            "comment", "example", "literal", "listing", "pass", "quote", "sidebar",
            "source", "verse", "admonition", "abstract", "partintro",
          ],
        ),
      )
    "----" => Some((Listing, ["literal", "source"]))
    "...." => Some((Literal, ["listing", "source"]))
    "====" => Some((Example, ["admonition"]))
    "****" => Some((Sidebar, []))
    "____" => Some((Quote, ["verse"]))
    "++++" => Some((Pass, ["stem", "latexmath", "asciimath"]))
    "|===" | ",===" | ":===" | "!===" => Some((Table, []))
    "~~~~" => Some((Open, ["abstract", "partintro"]))
    "////" => Some((Comment, []))
    "```" => Some((FencedCode, []))
    _ => None
  }
}

///|
fn is_delimited_block_head(head : String) -> Bool {
  match head {
    "--"
    | ".."
    | "=="
    | "**"
    | "__"
    | "++"
    | "|="
    | ",="
    | ":="
    | "!="
    | "~~"
    | "//"
    | "``" => true
    _ => false
  }
}

///|
/// Checks whether the line is a delimited block delimiter (Ruby `is_delimited_block?`).
fn is_delimited_block(line0 : String) -> BlockMatchData? {
  let mut line = line0
  let mut line_len = line.length()
  if !(line_len > 1 && is_delimited_block_head(@rb.slice(line, 0, 2))) {
    return None
  }
  let mut tip = ""
  let mut tip_len = 0
  if line_len == 2 {
    tip = line
    tip_len = 2
  } else {
    if line_len < 5 {
      tip = line
      tip_len = line_len
    } else {
      tip = @rb.slice(line, 0, 4)
      tip_len = 4
    }
    if compliance.markdown_syntax && tip.has_prefix("`") {
      if tip_len == 4 {
        if tip == "````" {
          return None
        }
        tip = @rb.chop(tip)
        if tip != "```" {
          return None
        }
        line = tip
        line_len = 3
        tip_len = 3
      } else if tip != "```" {
        return None
      }
    } else if tip_len == 3 {
      return None
    }
  }
  match delimited_block_info(tip) {
    Some((context, masq)) => {
      let tail = @rb.from(tip, tip.length() - 1)
      if line_len == tip_len ||
        (tip_len == 4 && is_uniform(@rb.from(line, 1), tail, line_len - 1)) {
        Some({ context, masq, tip, terminator: line, })
      } else {
        None
      }
    }
    None => None
  }
}

///|
fn start_of_block(l : String) -> Bool {
  (l.has_prefix("[") && block_attribute_line_rx.matches(l)) ||
  is_delimited_block(l) is Some(_)
}

///|
fn start_of_list(l : String) -> Bool {
  any_list_rx.matches(l)
}

///|
fn start_of_block_or_list(l : String) -> Bool {
  is_delimited_block(l) is Some(_) ||
  (l.has_prefix("[") && block_attribute_line_rx.matches(l)) ||
  any_list_rx.matches(l)
}

///|
fn read_paragraph_lines(
  reader : Reader,
  break_at_list : Bool,
  skip_line_comments? : Bool = false,
  skip_processing? : Bool = false,
) -> Array[String] {
  reader.read_lines_until(
    break_on_blank_lines=true,
    break_on_list_continuation=true,
    preserve_last_line=true,
    skip_line_comments~,
    skip_processing~,
    break_if?=if compliance.block_terminates_paragraph {
      Some(if break_at_list { start_of_block_or_list } else { start_of_block })
    } else if break_at_list {
      Some(start_of_list)
    } else {
      None
    },
  )
}

///|
fn layout_break_context(ch0 : String) -> Context? {
  match ch0 {
    "'" | "-" | "*" | "_" => Some(ThematicBreak)
    "<" => Some(PageBreak)
    _ => None
  }
}

///|
let admonition_styles : Array[String] = [
  "NOTE", "TIP", "IMPORTANT", "WARNING", "CAUTION",
]

///|
let paragraph_styles : Array[String] = [
  "comment", "example", "literal", "listing", "normal", "open", "pass", "quote",
  "sidebar", "source", "verse", "abstract", "partintro",
]

///|
let verbatim_styles : Array[String] = ["literal", "listing", "source", "verse"]

///|
/// Parses the next block (Ruby `Parser.next_block`).
fn next_block(
  reader : Reader,
  parent : Node,
  attributes : Attributes,
  text_only? : Bool = false,
  parse_metadata? : Bool = true,
  list_type? : Context,
) -> Node? {
  guard reader.skip_blank_lines() is Some(skipped) else { return None }
  let mut text_only = text_only
  if text_only && skipped > 0 {
    text_only = false
  }
  let document = parent.document()
  if parse_metadata {
    while parse_block_metadata_line(reader, document, attributes, text_only~) {
      reader.shift() |> ignore
      if reader.skip_blank_lines() is None {
        return None
      }
    }
  }
  let extensions = document.extensions()
  let block_extensions = match extensions {
    Some(e) => !e.block_processors.is_empty()
    None => false
  }
  let block_macro_extensions = match extensions {
    Some(e) => !e.block_macros.is_empty()
    None => false
  }
  reader.mark() |> ignore
  let this_line = reader.read_line().unwrap_or("")
  let doc_attrs = document.attributes
  let mut style = attributes.pos_str(1)
  let mut block : Node? = None
  let mut block_context : Context = Paragraph
  let mut cloaked_context : Context = Paragraph
  let mut terminator = ""
  let delimited_block = is_delimited_block(this_line)
  match delimited_block {
    Some(db) => {
      block_context = db.context
      cloaked_context = db.context
      terminator = db.terminator
      match style {
        Some(s) =>
          if s != block_context.name() {
            if db.masq.contains(s) {
              block_context = Context::from_name(s)
            } else if db.masq.contains("admonition") &&
              admonition_styles.contains(s) {
              block_context = Admonition
            } else if block_extensions &&
              extensions.unwrap().registered_for_block(s, block_context)
              is Some(_) {
              block_context = Context::from_name(s)
            } else {
              if logger().is_debug() {
                log_debug(
                  "unknown style for \{block_context.name()} block: \{s}",
                  source_location=reader.cursor_at_mark(),
                )
              }
              style = Some(block_context.name())
            }
          }
        None => {
          style = Some(block_context.name())
          attributes.set_str("style", block_context.name())
        }
      }
    }
    None => ()
  }
  if delimited_block is None {
    // loop that executes once (Ruby `while true ... break`)
    let mut ch0 = ""
    let mut indented = false
    let mut done = false
    if style is Some(s) &&
      compliance.strict_verbatim_paragraphs &&
      verbatim_styles.contains(s) {
      block_context = Context::from_name(s)
      cloaked_context = Paragraph
      reader.unshift_line(this_line)
      done = true
    }
    if !done {
      if text_only {
        indented = this_line.has_prefix(" ") || this_line.has_prefix("\t")
      } else if this_line.has_prefix(" ") {
        indented = true
        ch0 = " "
        let stripped = @rb.lstrip(this_line)
        if compliance.markdown_syntax &&
          (
            stripped.has_prefix("-") ||
            stripped.has_prefix("*") ||
            stripped.has_prefix("_")
          ) &&
          markdown_thematic_break_rx.matches(this_line) {
          block = Some(
            Node::new_block(parent, ThematicBreak, content_model=Empty),
          )
          done = true
        }
      } else if this_line.has_prefix("\t") {
        indented = true
        ch0 = "\t"
      } else {
        indented = false
        ch0 = first_char(this_line)
        let lb = if compliance.markdown_syntax {
          layout_break_context(ch0)
        } else if ch0 == "'" || ch0 == "<" {
          layout_break_context(ch0)
        } else {
          None
        }
        match lb {
          Some(lbc) if (if compliance.markdown_syntax {
              ext_layout_break_rx.matches(this_line)
            } else {
              is_uniform(this_line, ch0, this_line.length()) &&
              this_line.length() > 2
            }) => {
            block = Some(Node::new_block(parent, lbc, content_model=Empty))
            done = true
          }
          _ =>
            if this_line.has_suffix("]") && this_line.contains("::") {
              if (
                  ch0 == "i" ||
                  this_line.has_prefix("video:") ||
                  this_line.has_prefix("audio:")
                ) &&
                block_media_macro_rx.find(this_line) is Some(m) {
                let blk_ctx = Context::from_name(m.at(1))
                let mut target = m.at(2)
                let b = Node::new_block(parent, blk_ctx, content_model=Empty)
                match m.group(3) {
                  Some(blk_attrs) => {
                    let posattrs : Array[String?] = match blk_ctx {
                      Video => [Some("poster"), Some("width"), Some("height")]
                      Audio => []
                      _ => [Some("alt"), Some("width"), Some("height")]
                    }
                    b.parse_attributes(
                      blk_attrs,
                      posattrs,
                      sub_input=true,
                      into=attributes,
                    )
                    |> ignore
                  }
                  None => ()
                }
                if attributes.contains("style") {
                  attributes.remove("style") |> ignore
                }
                if target.contains("{") {
                  let expanded = b.sub_attributes(target)
                  if expanded == "" &&
                    doc_attrs
                    .str("attribute-missing")
                    .unwrap_or(compliance.attribute_missing) ==
                    "drop-line" &&
                    b.sub_attributes(
                      target + " ",
                      attribute_missing="drop-line",
                      drop_line_ignore=true,
                    ) ==
                    "" {
                    attributes.clear()
                    return None
                  } else {
                    target = expanded
                  }
                }
                if blk_ctx == Image {
                  document.register_image(target)
                  if !attributes.truthy("imagesdir") {
                    attributes.set(
                      "imagesdir",
                      doc_attrs.get("imagesdir").unwrap_or(Nil),
                    )
                  }
                  if !attributes.truthy("alt") {
                    match style {
                      Some(s) => attributes.set_str("alt", s)
                      None => {
                        let default_alt = basename(target, drop_ext=true)
                          .replace_all(old="_", new=" ")
                          .replace_all(old="-", new=" ")
                        attributes.set_str("default-alt", default_alt)
                        attributes.set_str("alt", default_alt)
                      }
                    }
                  }
                  match attributes.remove_str("scaledwidth") {
                    Some(sw) if sw != "" =>
                      attributes.set_str(
                        "scaledwidth",
                        if trailing_digits_rx.matches(sw) {
                          "\{sw}%"
                        } else {
                          sw
                        },
                      )
                    _ => ()
                  }
                  match attributes.remove_str("title") {
                    Some(t) => {
                      b.set_title(Some(t))
                      b.assign_caption(
                        attributes.remove_str("caption"),
                        caption_context="figure",
                      )
                    }
                    None => ()
                  }
                }
                attributes.set_str("target", target)
                block = Some(b)
                done = true
              } else if ch0 == "t" &&
                this_line.has_prefix("toc:") &&
                block_toc_macro_rx.find(this_line) is Some(m) {
                let b = Node::new_block(parent, Toc, content_model=Empty)
                match m.group(1) {
                  Some(a) =>
                    b.parse_attributes(a, [], sub_input=true, into=attributes)
                    |> ignore
                  None => ()
                }
                block = Some(b)
                done = true
              } else if block_macro_extensions {
                match custom_block_macro_rx.find(this_line) {
                  Some(m) =>
                    match
                      extensions.unwrap().registered_for_block_macro(m.at(1)) {
                      Some(extension) => {
                        let content = m.group(3)
                        let mut target = m.at(2)
                        if target.contains("{") {
                          let expanded = parent.sub_attributes(target)
                          if expanded == "" &&
                            doc_attrs
                            .str("attribute-missing")
                            .unwrap_or(compliance.attribute_missing) ==
                            "drop-line" &&
                            parent.sub_attributes(
                              target + " ",
                              attribute_missing="drop-line",
                              drop_line_ignore=true,
                            ) ==
                            "" {
                            attributes.clear()
                            return None
                          } else {
                            target = expanded
                          }
                        }
                        if extension.config.content_model == Some(Attributes) {
                          match content {
                            Some(c) =>
                              document.parse_attributes(
                                c,
                                extension.config.positional_attrs.map(x => {
                                  Some(x)
                                }),
                                sub_input=true,
                                into=attributes,
                              )
                              |> ignore
                            None => ()
                          }
                        } else {
                          attributes.set_str("text", content.unwrap_or(""))
                        }
                        for d in extension.config.default_attrs {
                          if !attributes.contains(d.0) {
                            attributes.set_str(d.0, d.1)
                          }
                        }
                        match (extension.process)(parent, target, attributes) {
                          Some(b) if !physical_equal(b, parent) => {
                            attributes.replace(b.attributes)
                            block = Some(b)
                            done = true
                          }
                          _ => {
                            attributes.clear()
                            return None
                          }
                        }
                      }
                      None =>
                        if logger().is_debug() {
                          log_debug(
                            "unknown name for block macro: \{m.at(1)}",
                            source_location=reader.cursor_at_mark(),
                          )
                        }
                    }
                  None => ()
                }
              } else if logger().is_debug() {
                match custom_block_macro_rx.find(this_line) {
                  Some(m) =>
                    log_debug(
                      "unknown name for block macro: \{m.at(1)}",
                      source_location=reader.cursor_at_mark(),
                    )
                  None => ()
                }
              }
            }
        }
      }
    }
    if !done {
      if ch0 == "" {
        ch0 = first_char(this_line)
      }
      if !indented && ch0 == "<" && callout_list_rx.find(this_line) is Some(m) {
        reader.unshift_line(this_line)
        block = Some(
          parse_callout_list(reader, Some(m), parent, document.callouts()),
        )
        attributes.set_str("style", "arabic")
        done = true
      } else if unordered_list_rx.matches(this_line) {
        reader.unshift_line(this_line)
        if style is None &&
          parent.context == Section &&
          parent.sectname == Some("bibliography") {
          attributes.set_str("style", "bibliography")
          style = Some("bibliography")
        }
        block = Some(parse_list(reader, Ulist, parent, style))
        done = true
      } else if ordered_list_rx.matches(this_line) {
        reader.unshift_line(this_line)
        let b = parse_list(
          reader,
          Olist,
          parent,
          style,
          start=attributes.remove_str("start"),
        )
        match b.style {
          Some(s) => attributes.set_str("style", s)
          None => ()
        }
        block = Some(b)
        done = true
      } else if (this_line.contains("::") || this_line.contains(";;")) &&
        description_list_rx.find(this_line) is Some(m) {
        reader.unshift_line(this_line)
        block = Some(parse_description_list(reader, m, parent))
        done = true
      } else if (style == Some("float") || style == Some("discrete")) &&
        (if compliance.underline_style_section_titles {
          is_section_title(this_line, reader.peek_line()) is Some(_)
        } else {
          !indented && atx_section_title(this_line) is Some(_)
        }) {
        reader.unshift_line(this_line)
        let (float_id, float_reftext, block_title, float_level, _) = parse_section_title(
          reader,
          document,
          attributes.str("id"),
        )
        match float_reftext {
          Some(r) => attributes.set_str("reftext", r)
          None => ()
        }
        let b = Node::new_block(parent, FloatingTitle, content_model=Empty)
        b.set_title(Some(block_title))
        attributes.remove("title") |> ignore
        b.id = match float_id {
          Some(i) => Some(i)
          None =>
            if doc_attrs.contains("sectids") {
              Some(generate_section_id(b.title().unwrap_or(""), document))
            } else {
              None
            }
        }
        b.level = float_level
        block = Some(b)
        done = true
      } else if style is Some(s) && s != "normal" {
        if paragraph_styles.contains(s) {
          block_context = Context::from_name(s)
          cloaked_context = Paragraph
          reader.unshift_line(this_line)
          done = true
        } else if admonition_styles.contains(s) {
          block_context = Admonition
          cloaked_context = Paragraph
          reader.unshift_line(this_line)
          done = true
        } else if block_extensions &&
          extensions.unwrap().registered_for_block(s, Paragraph) is Some(_) {
          block_context = Context::from_name(s)
          cloaked_context = Paragraph
          reader.unshift_line(this_line)
          done = true
        } else {
          if logger().is_debug() {
            log_debug(
              "unknown style for paragraph: \{s}",
              source_location=reader.cursor_at_mark(),
            )
          }
          style = None
        }
      }
    }
    if !done {
      reader.unshift_line(this_line)
      if indented && style is None {
        let content_adjacent = if skipped == 0 { list_type } else { None }
        let lines = read_paragraph_lines(
          reader,
          content_adjacent is Some(_),
          skip_line_comments=text_only,
        )
        adjust_indentation(lines)
        if text_only || content_adjacent == Some(Dlist) {
          block = Some(
            Node::new_block(
              parent,
              Paragraph,
              content_model=Simple,
              source=lines,
              attributes~,
            ),
          )
        } else {
          block = Some(
            Node::new_block(
              parent,
              Literal,
              content_model=Verbatim,
              source=lines,
              attributes~,
            ),
          )
        }
      } else {
        let lines = read_paragraph_lines(
          reader,
          skipped == 0 && list_type is Some(_),
          skip_line_comments=true,
        )
        if text_only {
          if indented && style == Some("normal") {
            adjust_indentation(lines)
          }
          block = Some(
            Node::new_block(
              parent,
              Paragraph,
              content_model=Simple,
              source=lines,
              attributes~,
            ),
          )
        } else if admonition_styles.iter().any(s => first_char(s) == ch0) &&
          this_line.contains(":") &&
          admonition_paragraph_rx.find(this_line) is Some(m) {
          lines[0] = m.post_match()
          let admonition_name = @rb.downcase(m.at(1))
          attributes.set_str("style", m.at(1))
          attributes.set_str("name", admonition_name)
          attributes.set(
            "textlabel",
            match attributes.remove("caption") {
              Some(c) if c.truthy() => c
              _ => doc_attrs.get("\{admonition_name}-caption").unwrap_or(Nil)
            },
          )
          block = Some(
            Node::new_block(
              parent,
              Admonition,
              content_model=Simple,
              source=lines,
              attributes~,
            ),
          )
        } else if compliance.markdown_syntax &&
          ch0 == ">" &&
          this_line.has_prefix("> ") {
          for i, line in lines {
            lines[i] = if line == ">" {
              @rb.from(line, 1)
            } else if line.has_prefix("> ") {
              @rb.from(line, 2)
            } else {
              line
            }
          }
          let mut credit_line : String? = None
          if lines[lines.length() - 1].has_prefix("-- ") {
            credit_line = Some(@rb.from(lines.pop().unwrap(), 3))
            if !lines.is_empty() {
              while !lines.is_empty() && lines[lines.length() - 1] == "" {
                lines.pop() |> ignore
              }
            }
          }
          attributes.set_str("style", "quote")
          let b = build_block(
            Quote,
            Compound,
            None,
            parent,
            Reader::new(lines),
            attributes,
            reader_only=true,
          )
          match (credit_line, b) {
            (Some(cl), Some(b)) => {
              let parts = @rb.split(
                b.apply_subs(cl, normal_subs),
                ", ",
                limit=2,
              )
              match parts.get(0) {
                Some(a) => attributes.set_str("attribution", a)
                None => ()
              }
              match parts.get(1) {
                Some(c) => attributes.set_str("citetitle", c)
                None => ()
              }
            }
            _ => ()
          }
          block = b
        } else if ch0 == "\"" &&
          lines.length() > 1 &&
          lines[lines.length() - 1].has_prefix("-- ") &&
          lines[lines.length() - 2].has_suffix("\"") {
          lines[0] = @rb.from(this_line, 1)
          let credit_line = @rb.from(lines.pop().unwrap(), 3)
          while !lines.is_empty() && lines[lines.length() - 1] == "" {
            lines.pop() |> ignore
          }
          let last = lines.pop().unwrap()
          lines.push(@rb.chop(last))
          attributes.set_str("style", "quote")
          let b = Node::new_block(
            parent,
            Quote,
            content_model=Simple,
            source=lines,
            attributes~,
          )
          let parts = @rb.split(
            b.apply_subs(credit_line, normal_subs),
            ", ",
            limit=2,
          )
          match parts.get(0) {
            Some(a) => attributes.set_str("attribution", a)
            None => ()
          }
          match parts.get(1) {
            Some(c) => attributes.set_str("citetitle", c)
            None => ()
          }
          block = Some(b)
        } else {
          if indented && style == Some("normal") {
            adjust_indentation(lines)
          }
          block = Some(
            Node::new_block(
              parent,
              Paragraph,
              content_model=Simple,
              source=lines,
              attributes~,
            ),
          )
        }
        match block {
          Some(b) =>
            catalog_inline_anchors(lines.join("\n"), b, document, reader)
          None => ()
        }
      }
    }
  }
  if block is None {
    match block_context {
      Listing | Source => {
        let mut language : String? = None
        let is_source = block_context == Source ||
          ({
            language = if attributes.pos_str(1) is Some(_) {
              None
            } else {
              match attributes.pos_str(2) {
                Some(l) => Some(l)
                None => doc_attrs.str("source-language")
              }
            }
            language is Some(_)
          })
        if is_source {
          match language {
            Some(lang) => {
              attributes.set_str("style", "source")
              attributes.set_str("language", lang)
              rekey_attributes(attributes, [None, None, Some("linenums")])
              |> ignore
            }
            None => {
              rekey_attributes(attributes, [
                None,
                Some("language"),
                Some("linenums"),
              ])
              |> ignore
              if !attributes.contains("language") &&
                doc_attrs.contains("source-language") {
                attributes.set(
                  "language",
                  doc_attrs.get("source-language").unwrap(),
                )
              }
              if cloaked_context != Listing {
                attributes.set_str("cloaked-context", cloaked_context.name())
              }
            }
          }
          if !attributes.contains("linenums-option") &&
            (
              attributes.contains("linenums") ||
              doc_attrs.contains("source-linenums-option")
            ) {
            attributes.set_str("linenums-option", "")
          }
          if !attributes.contains("indent") &&
            doc_attrs.contains("source-indent") {
            attributes.set("indent", doc_attrs.get("source-indent").unwrap())
          }
        }
        block = build_block(
          Listing,
          Verbatim,
          opt_terminator(delimited_block, terminator),
          parent,
          reader,
          attributes,
        )
      }
      FencedCode => {
        attributes.set_str("style", "source")
        let ll = this_line.length()
        let mut language = ""
        if ll > 3 {
          language = @rb.from(this_line, 3)
          match language.find(",") {
            Some(comma_idx) =>
              if comma_idx > 0 {
                language = @rb.strip(@rb.slice(language, 0, comma_idx))
                if comma_idx < ll - 4 {
                  attributes.set_str("linenums", "")
                }
              } else {
                if ll > 4 {
                  attributes.set_str("linenums", "")
                }
                language = @rb.slice(language, 0, comma_idx)
              }
            None => language = @rb.lstrip(language)
          }
        }
        if language == "" {
          if doc_attrs.contains("source-language") {
            attributes.set(
              "language",
              doc_attrs.get("source-language").unwrap(),
            )
          }
        } else {
          attributes.set_str("language", language)
        }
        attributes.set_str("cloaked-context", cloaked_context.name())
        if !attributes.contains("linenums-option") &&
          (
            attributes.contains("linenums") ||
            doc_attrs.contains("source-linenums-option")
          ) {
          attributes.set_str("linenums-option", "")
        }
        if !attributes.contains("indent") && doc_attrs.contains("source-indent") {
          attributes.set("indent", doc_attrs.get("source-indent").unwrap())
        }
        block = build_block(
          Listing,
          Verbatim,
          Some(@rb.slice(terminator, 0, 3)),
          parent,
          reader,
          attributes,
        )
      }
      Table => {
        let block_cursor = reader.cursor()
        let block_reader = Reader::new(
          reader.read_lines_until(
            terminator~,
            skip_line_comments=true,
            context=Some("table"),
            cursor_at_mark=true,
          ),
          cursor=block_cursor,
        )
        if !(terminator.has_prefix("|") || terminator.has_prefix("!")) {
          if !attributes.truthy("format") {
            attributes.set_str(
              "format",
              if terminator.has_prefix(",") {
                "csv"
              } else {
                "dsv"
              },
            )
          }
        }
        block = Some(parse_table(block_reader, parent, attributes))
      }
      Sidebar =>
        block = build_block(
          block_context,
          Compound,
          opt_terminator(delimited_block, terminator),
          parent,
          reader,
          attributes,
        )
      Admonition => {
        let admonition_name = @rb.downcase(style.unwrap_or(""))
        attributes.set_str("name", admonition_name)
        attributes.set(
          "textlabel",
          match attributes.remove("caption") {
            Some(c) if c.truthy() => c
            _ => doc_attrs.get("\{admonition_name}-caption").unwrap_or(Nil)
          },
        )
        block = build_block(
          block_context,
          Compound,
          opt_terminator(delimited_block, terminator),
          parent,
          reader,
          attributes,
        )
      }
      Open | Abstract | PartIntro =>
        block = build_block(
          Open,
          Compound,
          opt_terminator(delimited_block, terminator),
          parent,
          reader,
          attributes,
        )
      Literal =>
        block = build_block(
          block_context,
          Verbatim,
          opt_terminator(delimited_block, terminator),
          parent,
          reader,
          attributes,
        )
      Example => {
        if attributes.truthy("collapsible-option") {
          attributes.set_str("caption", "")
        }
        block = build_block(
          block_context,
          Compound,
          opt_terminator(delimited_block, terminator),
          parent,
          reader,
          attributes,
        )
      }
      Quote | Verse => {
        rekey_attributes(attributes, [
          None,
          Some("attribution"),
          Some("citetitle"),
        ])
        |> ignore
        block = build_block(
          block_context,
          if block_context == Verse {
            Verbatim
          } else {
            Compound
          },
          opt_terminator(delimited_block, terminator),
          parent,
          reader,
          attributes,
        )
      }
      Stem | LatexMath | AsciiMath => {
        if block_context == Stem {
          attributes.set_str(
            "style",
            stem_type_alias(
              match attributes.pos_str(2) {
                Some(s) => Some(s)
                None => doc_attrs.str("stem")
              },
            ),
          )
        }
        block = build_block(
          Stem,
          Raw,
          opt_terminator(delimited_block, terminator),
          parent,
          reader,
          attributes,
        )
      }
      Pass =>
        block = build_block(
          block_context,
          Raw,
          opt_terminator(delimited_block, terminator),
          parent,
          reader,
          attributes,
        )
      Comment => {
        build_block(
          block_context,
          Skip,
          opt_terminator(delimited_block, terminator),
          parent,
          reader,
          attributes,
        )
        |> ignore
        attributes.clear()
        return None
      }
      _ => {
        let extension = if block_extensions {
          extensions
          .unwrap()
          .registered_for_block(block_context.name(), cloaked_context)
        } else {
          None
        }
        guard extension is Some(extension) else {
          abort(
            "Unsupported block type \{block_context.name()} at \{reader.cursor().line_info()}",
          )
        }
        let content_model = extension.config.content_model.unwrap_or(Compound)
        if content_model != Skip {
          let pos = extension.config.positional_attrs
          if !pos.is_empty() {
            rekey_attributes(attributes, [None] + pos.map(x => Some(x)))
            |> ignore
          }
          for d in extension.config.default_attrs {
            if !attributes.truthy(d.0) {
              attributes.set_str(d.0, d.1)
            }
          }
          attributes.set_str("cloaked-context", cloaked_context.name())
        }
        match
          build_block(
            block_context,
            content_model,
            opt_terminator(delimited_block, terminator),
            parent,
            reader,
            attributes,
            extension~,
          ) {
          Some(b) => block = Some(b)
          None => {
            attributes.clear()
            return None
          }
        }
      }
    }
  }
  guard block is Some(block) else { return None }
  if document.sourcemap() {
    block.source_location = Some(reader.cursor_at_mark())
  }
  let mut block_title : String? = None
  match attributes.remove_str("title") {
    Some(t) => {
      block.set_title(Some(t))
      block_title = Some(t)
      if caption_attribute_name(block.context.name()) is Some(_) {
        block.assign_caption(attributes.remove_str("caption"))
      }
    }
    None => ()
  }
  block.style = attributes.str("style")
  let block_id = match block.id {
    Some(i) => Some(i)
    None => {
      block.id = attributes.str("id")
      block.id
    }
  }
  match block_id {
    Some(i) => {
      let should_sub_title = match block_title {
        Some(t) => t.contains("{")
        None => block.has_title()
      }
      if should_sub_title {
        block.title() |> ignore
      }
      if !document.register_ref(i, block) {
        log_warn(
          "id assigned to block already in use: \{i}",
          source_location=reader.cursor_at_mark(),
        )
      }
    }
    None => ()
  }
  if !attributes.is_empty() {
    block.update_attributes(attributes)
  }
  block.commit_subs()
  if block.has_sub(Callouts) {
    if !catalog_callouts(block.source(), document) {
      block.remove_sub(Callouts)
    }
  }
  Some(block)
}

///|
fn opt_terminator(delimited : BlockMatchData?, terminator : String) -> String? {
  match delimited {
    Some(_) => Some(terminator)
    None => None
  }
}

///|
/// Builds a block from lines read up to the terminator (Ruby `build_block`).
fn build_block(
  block_context : Context,
  content_model : ContentModel,
  terminator : String?,
  parent : Node,
  reader : Reader,
  attributes : Attributes,
  reader_only? : Bool = false,
  extension? : BlockProcessor,
) -> Node? {
  let (skip_processing, parse_as_content_model) = match content_model {
    Skip => (true, Simple)
    Raw => (false, Simple)
    _ => (false, content_model)
  }
  let mut content_model = content_model
  let mut lines : Array[String]? = None
  let mut block_reader : Reader? = None
  if reader_only {
    block_reader = Some(reader)
  } else {
    match terminator {
      None =>
        if parse_as_content_model == Verbatim {
          lines = Some(
            reader.read_lines_until(
              break_on_blank_lines=true,
              break_on_list_continuation=true,
            ),
          )
        } else {
          if content_model == Compound {
            content_model = Simple
          }
          lines = Some(
            read_paragraph_lines(
              reader,
              false,
              skip_line_comments=true,
              skip_processing~,
            ),
          )
        }
      Some(t) =>
        if parse_as_content_model != Compound {
          lines = Some(
            reader.read_lines_until(
              terminator=t,
              skip_processing~,
              context=Some(block_context.name()),
              cursor_at_mark=true,
            ),
          )
        } else {
          let block_cursor = reader.cursor()
          block_reader = Some(
            Reader::new(
              reader.read_lines_until(
                terminator=t,
                skip_processing~,
                context=Some(block_context.name()),
                cursor_at_mark=true,
              ),
              cursor=block_cursor,
            ),
          )
        }
    }
  }
  match content_model {
    Verbatim => {
      let tab_size = match attributes.get("tabsize") {
        Some(v) if v.truthy() => v.to_i()
        _ =>
          match parent.document().attributes.get("tabsize") {
            Some(v) => v.to_i()
            None => 0
          }
      }
      match attributes.get("indent") {
        Some(indent) if indent.truthy() =>
          adjust_indentation(
            lines.unwrap_or([]),
            indent_size=indent.to_i(),
            tab_size~,
          )
        _ =>
          if tab_size > 0 {
            adjust_indentation(lines.unwrap_or([]), indent_size=-1, tab_size~)
          }
      }
    }
    Skip => return None
    _ => ()
  }
  let block = match extension {
    Some(ext) => {
      attributes.remove("style") |> ignore
      let r = match block_reader {
        Some(r) => r
        None => Reader::new(lines.unwrap_or([]))
      }
      match (ext.process)(parent, r, attributes.copy()) {
        Some(b) if !physical_equal(b, parent) => {
          attributes.replace(b.attributes)
          if b.content_model == Compound && !b.lines.is_empty() {
            content_model = Compound
            block_reader = Some(Reader::new(b.lines))
          }
          b
        }
        _ => return None
      }
    }
    None =>
      Node::new_block(
        parent,
        block_context,
        content_model~,
        source?=lines,
        attributes~,
      )
  }
  if content_model == Compound {
    match block_reader {
      Some(r) => parse_blocks(r, block, None)
      None => ()
    }
  }
  Some(block)
}

///|
/// Parses blocks into `parent` until the reader is exhausted.
fn parse_blocks(
  reader : Reader,
  parent : Node,
  attributes : Attributes?,
) -> Unit {
  while true {
    let attrs = match attributes {
      Some(a) => a.copy()
      None => Attributes::new()
    }
    match next_block(reader, parent, attrs) {
      Some(b) => parent.blocks.push(b)
      None => if !reader.has_more_lines() { break }
    }
  }
}

///|
/// Registers the callouts found in `text` (Ruby `catalog_callouts`).
fn catalog_callouts(text : String, document : Node) -> Bool {
  let mut found = false
  let mut autonum = 0
  if text.contains("<") {
    for m in callout_scan_rx.find_all(text) {
      if !m.matched().has_prefix("\\") {
        let num = if m.at(2) == "." {
          autonum += 1
          autonum.to_string()
        } else {
          m.at(2)
        }
        document.callouts().register(num) |> ignore
      }
      found = true
    }
  }
  found
}

///|
/// Registers an inline anchor (Ruby `Parser.catalog_inline_anchor`).
fn catalog_inline_anchor(
  id : String,
  reftext : String?,
  node : Node,
  location : Cursor?,
  doc : Node,
) -> Unit {
  let reftext = match reftext {
    Some(r) if r.contains("{") => Some(doc.sub_attributes(r))
    r => r
  }
  if !doc.register_ref(
      id,
      Node::new_inline(node, Anchor, text?=reftext, type_="ref", id~),
    ) {
    log_warn(
      "id assigned to anchor already in use: \{id}",
      source_location?=location,
    )
  }
}

///|
fn catalog_inline_anchors(
  text : String,
  block : Node,
  document : Node,
  reader : Reader,
) -> Unit {
  if !(text.contains("[[") || text.contains("or:")) {
    return
  }
  for m in inline_anchor_scan_rx.find_all(text) {
    let mut id = ""
    let mut reftext : String? = None
    match m.group(1) {
      Some(i) => {
        id = i
        reftext = m.group(2)
        match reftext {
          Some(r) if r.contains("{") => {
            let r2 = document.sub_attributes(r)
            if r2 == "" {
              continue
            }
            reftext = Some(r2)
          }
          _ => ()
        }
      }
      None => {
        id = m.at(3)
        reftext = m.group(4)
        match reftext {
          Some(r) =>
            if r.contains("]") {
              let r2 = r.replace_all(old="\\]", new="]")
              reftext = Some(
                if r2.contains("{") {
                  document.sub_attributes(r2)
                } else {
                  r2
                },
              )
            } else if r.contains("{") {
              let r2 = document.sub_attributes(r)
              reftext = if r2 == "" { None } else { Some(r2) }
            }
          None => ()
        }
      }
    }
    if !document.register_ref(
        id,
        Node::new_inline(block, Anchor, text?=reftext, type_="ref", id~),
      ) {
      let location = reader.cursor_at_mark()
      let pre = m.pre_match()
      let offset = @rb.count(pre, "\n") +
        (if m.matched().has_prefix("\n") { 1 } else { 0 })
      if offset > 0 {
        location.advance(offset)
      }
      log_warn(
        "id assigned to anchor already in use: \{id}",
        source_location=location,
      )
    }
  }
}

///|
fn catalog_inline_biblio_anchor(
  id : String,
  reftext : String?,
  node : Node,
  reader : Reader,
) -> Unit {
  let text = match reftext {
    Some(r) => Some("[\{r}]")
    None => None
  }
  if !node
    .document()
    .register_ref(
      id,
      Node::new_inline(node, Anchor, text?, type_="bibref", id~),
    ) {
    log_warn(
      "id assigned to bibliography anchor already in use: \{id}",
      source_location=reader.cursor(),
    )
  }
}
