///|
/// Section number, e.g. `2.3.` (Ruby `Section#sectnum`).
pub fn Node::sectnum(
  self : Node,
  delimiter? : String = ".",
  append? : String?,
) -> String {
  let append = match append {
    Some(Some(a)) => a
    Some(None) => ""
    None => delimiter
  }
  match self.parent_ {
    Some(p) if self.level > 1 && p.context == Section =>
      "\{p.sectnum(delimiter~, append=Some(delimiter))}\{self.numeral.unwrap_or("")}\{append}"
    _ => "\{self.numeral.unwrap_or("")}\{append}"
  }
}

///|
/// Generates an id for this section from its title.
pub fn Node::generate_id(self : Node) -> String {
  generate_section_id(self.title().unwrap_or(""), self.document())
}

///|
/// Ruby `Section.generate_id(title, document)`.
pub fn generate_section_id(title : String, document : Node) -> String {
  let attrs = document.attributes
  let pre = attrs.str("idprefix").unwrap_or("_")
  let mut sep = "_"
  let mut sep_sub : String? = Some(" _.-")
  let mut no_sep = false
  match attrs.get("idseparator") {
    Some(v) if v.truthy() => {
      sep = v.to_s()
      sep_sub = None
      if sep.length() == 1 {
        sep_sub = Some(
          if sep == "-" || sep == "." {
            " .-"
          } else {
            " \{sep}.-"
          },
        )
      } else if sep == "" {
        no_sep = true
      } else {
        // use the first character only
        let first = match sep.get_char(0) {
          Some(c) => c.to_string()
          None => ""
        }
        attrs.set_str("idseparator", first)
        sep = first
        sep_sub = Some(
          if sep == "-" || sep == "." {
            " .-"
          } else {
            " \{sep}.-"
          },
        )
      }
    }
    _ => ()
  }
  let mut gen_id = pre +
    invalid_section_id_chars_rx.gsub(@rb.downcase(title), "")
  if no_sep {
    gen_id = @rb.delete_chars(gen_id, " ")
  } else {
    let sep_char = sep.get_char(0).unwrap_or('_')
    gen_id = @rb.tr_s(gen_id, sep_sub.unwrap_or(""), sep_char)
    if gen_id.has_suffix(sep) {
      gen_id = @rb.chop(gen_id)
    }
    if pre == "" && gen_id.has_prefix(sep) {
      gen_id = @rb.from(gen_id, sep.length())
    }
  }
  let refs = document.catalog().refs
  if refs.contains(gen_id) {
    let mut cnt = compliance.unique_id_start_index
    while refs.contains("\{gen_id}\{sep}\{cnt}") {
      cnt += 1
    }
    "\{gen_id}\{sep}\{cnt}"
  } else {
    gen_id
  }
}

///|
fn Node::section_xreftext(self : Node, xrefstyle? : String) -> String? {
  match self.reftext() {
    Some(v) if v != "" => return Some(v)
    _ => ()
  }
  let title = self.title().unwrap_or("")
  let sectname = self.sectname.unwrap_or("")
  let emphasize = fn() {
    if sectname == "chapter" || sectname == "appendix" {
      sub_placeholder(self.sub_quotes("_%s_"), title)
    } else {
      title
    }
  }
  match xrefstyle {
    None => Some(title)
    Some(style) =>
      if self.numbered != NotNumbered {
        let doc = self.document()
        match style {
          "full" => {
            let quoted_title = if sectname == "chapter" ||
              sectname == "appendix" {
              sub_placeholder(self.sub_quotes("_%s_"), title)
            } else {
              sub_placeholder(
                self.sub_quotes(
                  if doc.compat_mode() {
                    "``%s''"
                  } else {
                    "\"`%s`\""
                  },
                ),
                title,
              )
            }
            match doc.attributes.str("\{sectname}-refsig") {
              Some(signifier) =>
                Some(
                  "\{signifier} \{self.sectnum(delimiter=".", append=Some(","))} \{quoted_title}",
                )
              None =>
                Some(
                  "\{self.sectnum(delimiter=".", append=Some(","))} \{quoted_title}",
                )
            }
          }
          "short" =>
            match doc.attributes.str("\{sectname}-refsig") {
              Some(signifier) =>
                Some(
                  "\{signifier} \{self.sectnum(delimiter=".", append=Some(""))}",
                )
              None => Some(self.sectnum(delimiter=".", append=Some("")))
            }
          _ => Some(emphasize())
        }
      } else {
        Some(emphasize())
      }
  }
}
