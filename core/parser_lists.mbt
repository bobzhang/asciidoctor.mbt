///|
/// How sibling list items are recognized: by a regexp (dlist) or by a marker.
priv enum SiblingTrait {
  Pattern(@regex.Regex)
  Marker(String)
}

///|
fn list_rx_for(ctx : Context) -> @regex.Regex {
  match ctx {
    Ulist => unordered_list_rx
    Olist => ordered_list_rx
    Dlist => description_list_rx
    _ => callout_list_rx
  }
}

///|
fn parse_list(
  reader : Reader,
  list_type : Context,
  parent : Node,
  style : String?,
  start? : String?,
) -> Node {
  let start_i = match start {
    Some(Some(s)) => Some(@rb.to_i(s))
    _ => None
  }
  let list_block = match start_i {
    Some(s) if s != 1 =>
      Node::new_list(
        parent,
        list_type,
        attributes=Attributes::from_array([("start", Int(s))]),
      )
    _ => Node::new_list(parent, list_type)
  }
  let list_rx = list_rx_for(list_type)
  while reader.has_more_lines() {
    guard list_rx.find(reader.peek_line().unwrap_or("")) is Some(m) else {
      break
    }
    match parse_list_item(reader, list_block, m, Marker(m.at(1)), style) {
      Item(li) => list_block.blocks.push(li)
      Pair(_) => ()
    }
    if reader.skip_blank_lines() is None {
      break
    }
  }
  list_block
}

///|
fn parse_description_list(
  reader : Reader,
  m : @regex.MatchData,
  parent : Node,
) -> Node {
  let list_block = Node::new_list(parent, Dlist)
  let sibling_pattern = description_list_sibling_rx.get(m.at(2)).unwrap()
  let mut current_pair = match
    parse_list_item(reader, list_block, m, Pattern(sibling_pattern), None) {
    Pair(p) => p
    Item(_) => abort("unexpected")
  }
  list_block.dlist_items.push(current_pair)
  while reader.has_more_lines() {
    guard sibling_pattern.find(reader.peek_line().unwrap_or("")) is Some(m2) else {
      break
    }
    let next_pair = match
      parse_list_item(reader, list_block, m2, Pattern(sibling_pattern), None) {
      Pair(p) => p
      Item(_) => abort("unexpected")
    }
    if current_pair.desc is Some(_) {
      list_block.dlist_items.push(next_pair)
      current_pair = next_pair
    } else {
      current_pair.terms.push(next_pair.terms[0])
      current_pair.desc = next_pair.desc
    }
  }
  list_block
}

///|
fn parse_callout_list(
  reader : Reader,
  m : @regex.MatchData?,
  parent : Node,
  callouts : Callouts,
) -> Node {
  let list_block = Node::new_list(parent, Colist)
  let mut next_index = 1
  let mut autonum = 0
  let mut m = m
  while true {
    let cur = match m {
      Some(mm) => mm
      None =>
        match reader.peek_line() {
          Some(l) =>
            match callout_list_rx.find(l) {
              Some(mm) => {
                reader.mark() |> ignore
                mm
              }
              None => break
            }
          None => break
        }
    }
    let mut num = cur.at(1)
    if num == "." {
      autonum += 1
      num = autonum.to_string()
    }
    if num != next_index.to_string() {
      log_warn(
        "callout list item index: expected \{next_index}, got \{num}",
        source_location=reader.cursor_at_mark(),
      )
    }
    match parse_list_item(reader, list_block, cur, Marker("<1>"), None) {
      Item(list_item) => {
        list_block.blocks.push(list_item)
        let coids = callouts.callout_ids(list_block.blocks.length())
        if coids == "" {
          log_warn(
            "no callout found for <\{list_block.blocks.length()}>",
            source_location=reader.cursor_at_mark(),
          )
        } else {
          list_item.attributes.set_str("coids", coids)
        }
      }
      Pair(_) => ()
    }
    next_index += 1
    m = None
  }
  callouts.next_list()
  list_block
}

///|
priv enum ListItemResult {
  Item(Node)
  Pair(DlistItem)
}

///|
fn parse_list_item(
  reader : Reader,
  list_block : Node,
  m : @regex.MatchData,
  sibling_trait : SiblingTrait,
  style : String?,
) -> ListItemResult {
  let list_type = list_block.context
  let mut dlist = false
  let mut has_text = true
  let mut sourcemap_assignment_deferred = false
  let mut list_term : Node? = None
  let mut sibling_trait = sibling_trait
  let list_item = if list_type == Dlist {
    dlist = true
    let term_text = m.at(1)
    let lt = Node::new_list_item(list_block, text=term_text)
    list_term = Some(lt)
    if term_text.has_prefix("[[") {
      match leading_inline_anchor_rx.find(term_text) {
        Some(am) =>
          catalog_inline_anchor(
            am.at(1),
            match am.group(2) {
              Some(r) => Some(r)
              None => Some(@rb.lstrip(am.post_match()))
            },
            lt,
            Some(reader.cursor()),
            lt.document(),
          )
        None => ()
      }
    }
    has_text = m.has(3)
    let li = Node::new_list_item(list_block, text?=m.group(3))
    if list_block.document().sourcemap() {
      lt.source_location = Some(reader.cursor())
      if has_text {
        li.source_location = lt.source_location
      } else {
        sourcemap_assignment_deferred = true
      }
    }
    li
  } else {
    has_text = true
    let item_text = m.at(2)
    let li = Node::new_list_item(list_block, text=item_text)
    if list_block.document().sourcemap() {
      li.source_location = Some(reader.cursor())
    }
    match list_type {
      Ulist => {
        li.marker = match sibling_trait {
          Marker(s) => Some(s)
          _ => None
        }
        if item_text.has_prefix("[") {
          if style == Some("bibliography") {
            match inline_biblio_anchor_rx.find(item_text) {
              Some(am) =>
                catalog_inline_biblio_anchor(am.at(1), am.group(2), li, reader)
              None => ()
            }
          } else if item_text.has_prefix("[[") {
            match leading_inline_anchor_rx.find(item_text) {
              Some(am) =>
                catalog_inline_anchor(
                  am.at(1),
                  am.group(2),
                  li,
                  Some(reader.cursor()),
                  li.document(),
                )
              None => ()
            }
          } else if item_text.has_prefix("[ ] ") ||
            item_text.has_prefix("[x] ") ||
            item_text.has_prefix("[*] ") {
            list_block.attributes.set_str("checklist-option", "")
            li.attributes.set_str("checkbox", "")
            if !item_text.has_prefix("[ ") {
              li.attributes.set_str("checked", "")
            }
            li.set_text(Some(@rb.from(item_text, 4)))
          }
        }
      }
      Olist => {
        let mut ordinal = list_block.blocks.length()
        let first = ordinal == 0
        let mut validate = true
        let marker0 = match sibling_trait {
          Marker(s) => s
          _ => ""
        }
        match list_block.attributes.get("start") {
          Some(start) if start.truthy() => ordinal += start.to_i() - 1
          _ =>
            if first {
              let start = resolve_ordered_list_start(marker0)
              if start != 1 {
                list_block.attributes.set("start", Int(start))
                ordinal += start - 1
                validate = false
              }
            }
        }
        let (marker, implicit_style) = resolve_ordered_list_marker(
          marker0,
          ordinal=Some(ordinal),
          validate~,
          reader=Some(reader),
        )
        sibling_trait = Marker(marker)
        li.marker = Some(marker)
        if first && style is None {
          list_block.style = Some(
            match implicit_style {
              Some(s) => s
              None =>
                match marker.length() - 1 {
                  0 => "arabic"
                  1 => "loweralpha"
                  2 => "lowerroman"
                  3 => "upperalpha"
                  4 => "upperroman"
                  _ => "arabic"
                }
            },
          )
        }
        if item_text.has_prefix("[[") {
          match leading_inline_anchor_rx.find(item_text) {
            Some(am) =>
              catalog_inline_anchor(
                am.at(1),
                am.group(2),
                li,
                Some(reader.cursor()),
                li.document(),
              )
            None => ()
          }
        }
      }
      _ => {
        li.marker = match sibling_trait {
          Marker(s) => Some(s)
          _ => None
        }
        if item_text.has_prefix("[[") {
          match leading_inline_anchor_rx.find(item_text) {
            Some(am) =>
              catalog_inline_anchor(
                am.at(1),
                am.group(2),
                li,
                Some(reader.cursor()),
                li.document(),
              )
            None => ()
          }
        }
      }
    }
    li
  }
  reader.shift() |> ignore
  let block_cursor = reader.cursor()
  let list_item_reader = Reader::new(
    read_lines_for_list_item(reader, list_type, sibling_trait, has_text),
    cursor=block_cursor,
  )
  if list_item_reader.has_more_lines() {
    if sourcemap_assignment_deferred {
      list_item.source_location = Some(block_cursor)
    }
    let comment_lines = list_item_reader.skip_line_comments()
    let mut content_adjacent = false
    match list_item_reader.peek_line() {
      Some(subsequent_line) => {
        if !comment_lines.is_empty() {
          list_item_reader.unshift_lines(comment_lines)
        }
        if subsequent_line != "" {
          content_adjacent = true
          if !dlist {
            has_text = false
          }
        }
      }
      None => ()
    }
    match
      next_block(
        list_item_reader,
        list_item,
        Attributes::new(),
        text_only=!has_text,
        list_type~,
      ) {
      Some(b) => list_item.blocks.push(b)
      None => ()
    }
    while list_item_reader.has_more_lines() {
      match
        next_block(list_item_reader, list_item, Attributes::new(), list_type~) {
        Some(b) => list_item.blocks.push(b)
        None => ()
      }
    }
    if content_adjacent &&
      (match list_item.blocks.get(0) {
        Some(fb) => fb.context == Paragraph
        None => false
      }) {
      list_item.fold_first()
    }
  }
  if dlist {
    Pair({
      terms: [list_term.unwrap()],
      desc: if list_item.has_text() || list_item.has_blocks() {
        Some(list_item)
      } else {
        None
      },
    })
  } else {
    Item(list_item)
  }
}

///|
/// Reads the lines belonging to a list item (Ruby `read_lines_for_list_item`).
/// List continuation markers are tracked in a parallel array (Ruby uses
/// string identity via a marker module).
fn read_lines_for_list_item(
  reader : Reader,
  list_type : Context,
  sibling_trait : SiblingTrait,
  has_text : Bool,
) -> Array[String] {
  let buffer : Array[String] = []
  let is_marker : Array[Bool] = []
  let push = fn(line : String, marker : Bool) {
    buffer.push(line)
    is_marker.push(marker)
  }
  let concat = fn(lines : Array[String]) {
    for l in lines {
      buffer.push(l)
      is_marker.push(false)
    }
  }
  let mut has_text = has_text
  let mut continuation = 0 // 0 inactive, 1 active, 2 frozen
  let mut within_nested_list = false
  let mut detached_continuation : Int? = None
  let dlist = list_type == Dlist
  let mut this_line : String? = None
  while reader.has_more_lines() {
    let mut line = reader.read_line().unwrap()
    this_line = Some(line)
    if is_sibling_list_item(line, list_type, sibling_trait) {
      break
    }
    let mut line_is_marker = line == "+"
    let prev_idx = buffer.length() - 1
    let prev_line : String? = if prev_idx >= 0 {
      Some(buffer[prev_idx])
    } else {
      None
    }
    let prev_is_marker = prev_idx >= 0 && is_marker[prev_idx]
    if prev_is_marker {
      if continuation == 0 {
        continuation = 1
        has_text = true
        if !within_nested_list {
          buffer[prev_idx] = ""
          is_marker[prev_idx] = true
        }
      }
      if line_is_marker {
        if continuation != 2 {
          continuation = 2
          push(line, true)
        }
        this_line = None
        continue
      }
    }
    match is_delimited_block(line) {
      Some(dm) => {
        if continuation != 1 {
          break
        }
        push(line, line_is_marker)
        concat(
          reader.read_lines_until(
            terminator=dm.terminator,
            read_last_line=true,
            context=None,
          ),
        )
        continuation = 0
      }
      None =>
        if dlist &&
          continuation != 1 &&
          line.has_prefix("[") &&
          block_attribute_line_rx.matches(line) {
          let block_attribute_lines = [line]
          let mut interrupt = false
          while reader.peek_line() is Some(next_line) {
            if is_delimited_block(next_line) is Some(_) {
              interrupt = true
            } else if next_line == "" ||
              (
                next_line.has_prefix("[") &&
                block_attribute_line_rx.matches(next_line)
              ) {
              block_attribute_lines.push(reader.read_line().unwrap())
              continue
            } else if any_list_rx.matches(next_line) &&
              !is_sibling_list_item(next_line, list_type, sibling_trait) {
              concat(block_attribute_lines)
            } else {
              interrupt = true
            }
            break
          }
          if interrupt {
            this_line = None
            reader.unshift_lines(block_attribute_lines)
            break
          }
        } else if continuation == 1 && line != "" {
          if literal_paragraph_rx.matches(line) {
            reader.unshift_line(line)
            if dlist {
              concat(
                reader.read_lines_until(
                  preserve_last_line=true,
                  break_on_blank_lines=true,
                  break_on_list_continuation=true,
                  break_if=l => {
                    is_sibling_list_item(l, list_type, sibling_trait)
                  },
                ),
              )
            } else {
              concat(
                reader.read_lines_until(
                  preserve_last_line=true,
                  break_on_blank_lines=true,
                  break_on_list_continuation=true,
                ),
              )
            }
            continuation = 0
          } else if (line.has_prefix(".") && block_title_rx.matches(line)) ||
            (line.has_prefix("[") && block_attribute_line_rx.matches(line)) ||
            (line.has_prefix(":") && attribute_entry_rx.matches(line)) {
            push(line, line_is_marker)
          } else {
            let candidates = if within_nested_list {
              [Dlist]
            } else {
              [Ulist, Olist, Dlist]
            }
            for ctx in candidates {
              match list_rx_for(ctx).find(line) {
                Some(nm) => {
                  within_nested_list = true
                  if ctx == Dlist && nm.at(3) == "" {
                    has_text = false
                  }
                  break
                }
                None => ()
              }
            }
            push(line, line_is_marker)
            continuation = 0
          }
        } else if prev_line == Some("") {
          if line == "" {
            if reader.skip_blank_lines() is None {
              this_line = None
              break
            }
            match reader.read_line() {
              Some(l) => {
                line = l
                this_line = Some(l)
                line_is_marker = l == "+"
              }
              None => {
                this_line = None
                break
              }
            }
            if is_sibling_list_item(line, list_type, sibling_trait) {
              break
            }
          }
          if line == "+" {
            detached_continuation = Some(buffer.length())
            push(line, true)
          } else if has_text {
            if is_sibling_list_item(line, list_type, sibling_trait) {
              break
            }
            let mut nested : Context? = None
            let mut nested_m : @regex.MatchData? = None
            for ctx in [Ulist, Olist, Dlist] {
              match list_rx_for(ctx).find(line) {
                Some(nm) => {
                  nested = Some(ctx)
                  nested_m = Some(nm)
                  break
                }
                None => ()
              }
            }
            match nested {
              Some(ctx) => {
                push(line, line_is_marker)
                within_nested_list = true
                if ctx == Dlist && nested_m.unwrap().at(3) == "" {
                  has_text = false
                }
              }
              None =>
                if literal_paragraph_rx.matches(line) {
                  reader.unshift_line(line)
                  if dlist {
                    concat(
                      reader.read_lines_until(
                        preserve_last_line=true,
                        break_on_blank_lines=true,
                        break_on_list_continuation=true,
                        break_if=l => {
                          is_sibling_list_item(l, list_type, sibling_trait)
                        },
                      ),
                    )
                  } else {
                    concat(
                      reader.read_lines_until(
                        preserve_last_line=true,
                        break_on_blank_lines=true,
                        break_on_list_continuation=true,
                      ),
                    )
                  }
                } else {
                  break
                }
            }
          } else {
            if !within_nested_list {
              buffer.pop() |> ignore
              is_marker.pop() |> ignore
            }
            push(line, line_is_marker)
            has_text = true
          }
        } else if line_is_marker {
          has_text = true
          push(line, true)
        } else {
          if line != "" {
            has_text = true
            let candidates = if within_nested_list {
              [Dlist]
            } else {
              [Ulist, Olist, Dlist]
            }
            for ctx in candidates {
              match list_rx_for(ctx).find(line) {
                Some(nm) => {
                  within_nested_list = true
                  if ctx == Dlist && nm.at(3) == "" {
                    has_text = false
                  }
                  break
                }
                None => ()
              }
            }
          }
          push(line, false)
        }
    }
    this_line = None
  }
  match this_line {
    Some(l) => reader.unshift_line(l)
    None => ()
  }
  match detached_continuation {
    Some(i) => {
      buffer[i] = ""
      is_marker[i] = true
    }
    None => ()
  }
  while !buffer.is_empty() {
    let last = buffer.length() - 1
    if is_marker[last] {
      buffer.pop() |> ignore
      is_marker.pop() |> ignore
      break
    } else if buffer[last] == "" {
      buffer.pop() |> ignore
      is_marker.pop() |> ignore
    } else {
      break
    }
  }
  buffer
}

///|
fn resolve_list_marker(list_type : Context, marker : String) -> String {
  match list_type {
    Ulist => marker
    Olist => resolve_ordered_list_marker(marker).0
    _ => "<1>"
  }
}

///|
fn ordered_list_style_of(marker : String) -> String? {
  for s in ["arabic", "loweralpha", "lowerroman", "upperalpha", "upperroman"] {
    if ordered_list_marker_rx_map.get(s).unwrap().matches(marker) {
      return Some(s)
    }
  }
  None
}

///|
fn resolve_ordered_list_marker(
  marker : String,
  ordinal? : Int?,
  validate? : Bool = false,
  reader? : Reader?,
) -> (String, String?) {
  if marker.has_prefix(".") {
    return (marker, None)
  }
  let style = ordered_list_style_of(marker)
  let ordinal_v = ordinal.unwrap_or(None)
  let mut expected = ""
  let mut actual = ""
  let new_marker = match style {
    Some("arabic") => {
      if validate {
        expected = (ordinal_v.unwrap_or(0) + 1).to_string()
        actual = @rb.to_i(marker).to_string()
      }
      "1."
    }
    Some("loweralpha") => {
      if validate {
        expected = (97 + ordinal_v.unwrap_or(0)).unsafe_to_char().to_string()
        actual = @rb.chop(marker)
      }
      "a."
    }
    Some("upperalpha") => {
      if validate {
        expected = (65 + ordinal_v.unwrap_or(0)).unsafe_to_char().to_string()
        actual = @rb.chop(marker)
      }
      "A."
    }
    Some("lowerroman") => {
      if validate {
        expected = @rb.downcase(@rb.int_to_roman(ordinal_v.unwrap_or(0) + 1))
        actual = @rb.chop(marker)
      }
      "i)"
    }
    Some("upperroman") => {
      if validate {
        expected = @rb.int_to_roman(ordinal_v.unwrap_or(0) + 1)
        actual = @rb.chop(marker)
      }
      "I)"
    }
    _ => marker
  }
  match ordinal_v {
    Some(_) => {
      if validate && expected != actual {
        match reader.unwrap_or(None) {
          Some(r) =>
            log_warn(
              "list item index: expected \{expected}, got \{actual}",
              source_location=r.cursor(),
            )
          None =>
            log_warn("list item index: expected \{expected}, got \{actual}")
        }
      }
      (new_marker, style)
    }
    None => (new_marker, None)
  }
}

///|
fn resolve_ordered_list_start(marker : String) -> Int {
  if marker.has_prefix(".") {
    return 1
  }
  match ordered_list_style_of(marker) {
    Some("arabic") => @rb.to_i(marker)
    Some("loweralpha") => @rb.chop(marker)[0].to_int() - 96
    Some("upperalpha") => @rb.chop(marker)[0].to_int() - 64
    Some("lowerroman") => roman_to_int(@rb.upcase(@rb.chop(marker)))
    Some("upperroman") => roman_to_int(@rb.chop(marker))
    _ => 1
  }
}

///|
fn is_sibling_list_item(
  line : String,
  list_type : Context,
  sibling_trait : SiblingTrait,
) -> Bool {
  match sibling_trait {
    Pattern(rx) => rx.matches(line)
    Marker(s) =>
      match list_rx_for(list_type).find(line) {
        Some(m) => s == resolve_list_marker(list_type, m.at(1))
        None => false
      }
  }
}
