///|
fn ManPageConverter::convert_document(
  self : ManPageConverter,
  node : @core.Node,
) -> String {
  ignore(self)
  if !node.has_attr("mantitle") {
    @core.logger().add({
      severity: Error,
      text: "asciidoctor: ERROR: doctype must be set to manpage when using manpage backend",
      source_location: None,
      include_location: None,
    })
    return ""
  }
  let mantitle = invalid_section_id_chars_rx.gsub(a(node, "mantitle"), "")
  let manvolnum = node.attr("manvolnum", default="1").unwrap_or("1")
  let manname = node.attr("manname", default=mantitle).unwrap_or(mantitle)
  let manmanual = node.attr("manmanual")
  let mansource = node.attr("mansource")
  let docdate = if node.has_attr("reproducible") {
    None
  } else {
    node.attr("docdate")
  }
  // NOTE the first line enables the table (tbl) preprocessor, necessary for non-Linux systems
  let authors_s = if node.has_attr("authors") {
    a(node, "authors")
  } else {
    "[see the \"AUTHOR(S)\" section]"
  }
  let result = [
    "'\\\" t\n.\\\"     Title: \{mantitle}\n.\\\"    Author: \{authors_s}\n.\\\" Generator: Asciidoctor \{a(node, "asciidoctor-version")}",
  ]
  match docdate {
    Some(d) => result.push(".\\\"      Date: \{d}")
    None => ()
  }
  let manual_c = match manmanual {
    Some(m) => @rb.tr_s(m, "\n\t ", ' ')
    None => "\\ \\&"
  }
  let source_c = match mansource {
    Some(m) => @rb.tr_s(m, "\n\t ", ' ')
    None => "\\ \\&"
  }
  result.push(
    ".\\\"    Manual: \{manual_c}\n.\\\"    Source: \{source_c}\n.\\\"  Language: English\n.\\\"",
  )
  let source_th = match mansource {
    Some(m) => manify(m)
    None => "\\ \\&"
  }
  let manual_th = match manmanual {
    Some(m) => manify(m)
    None => "\\ \\&"
  }
  result.push(
    ".TH \"\{manify(@rb.upcase(manname))}\" \"\{manvolnum}\" \"\{docdate.unwrap_or("")}\" \"\{source_th}\" \"\{manual_th}\"",
  )
  // define portability settings
  result.push(".ie \\n(.g .ds Aq \\(aq")
  result.push(".el       .ds Aq '")
  // set sentence_space_size to 0 to prevent extra space between sentences separated by a newline
  result.push(".ss \\n[.ss] 0")
  // disable hyphenation
  result.push(".nh")
  // disable justification (adjust text to left margin only)
  result.push(".ad l")
  // define URL macro for portability
  result.push(
    ".de URL\n\\fI\\\\$2\\fP <\\\\$1>\\\\$3\n..\n.als MTO URL\n.if \\n[.g] \\{\\\n.  mso www.tmac\n.  am URL\n.    ad l\n.  .\n.  am MTO\n.    ad l\n.  .",
  )
  result.push(
    ".  LINKSTYLE \{node.attr("man-linkstyle", default="blue R < >").unwrap_or("blue R < >")}",
  )
  result.push(".\\}")
  if !node.noheader() && node.has_attr("manpurpose") {
    let mannames = match node.attributes.get("mannames") {
      Some(List(l)) => l
      Some(v) => [v.to_s()]
      None => [manname]
    }
    let names = mannames
      .map(n => manify(n).replace_all(old="\\-", new="-"))
      .join(", ")
    let title = @rb.upcase(
      node.attr("manname-title", default="NAME").unwrap_or("NAME"),
    )
    result.push(
      ".SH \"\{title}\"\n\{names} \\- \{manify(a(node, "manpurpose"), whitespace=Normalize)}",
    )
  }
  result.push(node.content())
  // QUESTION should NOTES come after AUTHOR(S)?
  append_footnotes(result, node)
  let authors = node.authors()
  if !authors.is_empty() {
    if authors.length() > 1 {
      result.push(".SH \"AUTHORS\"")
      for author in authors {
        result.push(".sp\n\{author.name.unwrap_or("")}")
      }
    } else {
      result.push(".SH \"AUTHOR\"\n.sp\n\{authors[0].name.unwrap_or("")}")
    }
  }
  result.join("\n")
}

///|
/// NOTE embedded doesn't really make sense in the manpage backend
fn ManPageConverter::convert_embedded(
  self : ManPageConverter,
  node : @core.Node,
) -> String {
  ignore(self)
  let result = [node.content()]
  append_footnotes(result, node)
  result.join("\n")
}

///|
fn append_footnotes(result : Array[String], node : @core.Node) -> Unit {
  if !node.has_footnotes() || node.has_attr("nofootnotes") {
    return
  }
  result.push(".SH \"NOTES\"")
  for fn_ in node.footnotes() {
    result.push(".IP [\{fn_.index}]")
    // NOTE restore newline in escaped macro that gets removed by normalize_text in substitutor
    let text = fn_.text
    let text = if text.contains("\{ESC}\\c \{ESC}.") {
      let fixed = malformed_escaped_macro_rx.replace(text, m => {
        "\{m.group(1).unwrap_or("")}\n\{m.group(2).unwrap_or("")}"
      })
      @rb.chomp_suffix(manify("\{fixed} ", whitespace=Normalize), " ")
    } else {
      manify(text, whitespace=Normalize)
    }
    result.push(text)
  }
}
