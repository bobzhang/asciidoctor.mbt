///|
fn strs(items : Array[String]) -> AttrVal {
  List(items)
}

///|
fn hide_uri_scheme(doc_attrs : Attributes, target : String) -> String {
  if doc_attrs.contains("hide-uri-scheme") {
    uri_sniff_rx.sub(target, "")
  } else {
    target
  }
}

///|
/// Replaces inline macros (Ruby `sub_macros`).
pub fn Node::sub_macros(self : Node, text : String) -> String {
  let found_square_bracket = text.contains("[")
  let found_colon = text.contains(":")
  let found_macroish = found_square_bracket && found_colon
  let found_macroish_short = found_macroish && text.contains(":[")
  let doc = self.document()
  let doc_attrs = doc.attributes
  let mut text = text
  // extension inline macros
  match doc.extensions() {
    Some(exts) if !exts.inline_macros.is_empty() =>
      for ext in exts.inline_macros {
        let rx = match ext.config.regexp {
          Some(r) => r
          None => inline_macro_regexp(ext.name, ext.config.format)
        }
        text = rx.replace(text, m => {
          let matched = m.matched()
          if matched.has_prefix("\\") {
            return @rb.from(matched, 1)
          }
          let (target0, content) = if m.has_names() {
            (m.named("target"), m.named("content"))
          } else {
            (m.group(1), m.group(2))
          }
          let mut target = target0
          let attributes = Attributes::new()
          for d in ext.config.default_attrs {
            attributes.set_str(d.0, d.1)
          }
          match content {
            Some(c) => {
              if c == "" {
                if ext.config.content_model != Some(Attributes) {
                  attributes.set_str("text", c)
                }
              } else {
                let c = normalize_text(
                  c,
                  normalize_whitespace=true,
                  unescape_closing_square_brackets=true,
                )
                if ext.config.content_model == Some(Attributes) {
                  self.parse_attributes(
                    c,
                    ext.config.positional_attrs.map(x => Some(x)),
                    into=attributes,
                  )
                  |> ignore
                } else {
                  attributes.set_str("text", c)
                }
              }
              if target is None && ext.config.format == Some("short") {
                target = Some(c)
              }
            }
            None => ()
          }
          match (ext.process)(self, target.unwrap_or(""), attributes) {
            Some(InlineNode(replacement)) => {
              match replacement.attributes.remove_str("subs") {
                Some(inline_subs) =>
                  match
                    self.expand_subs(inline_subs, subject="custom inline macro") {
                    Some(s) =>
                      replacement.text_ = Some(
                        self.apply_subs(replacement.text_.unwrap_or(""), s),
                      )
                    None => ()
                  }
                None => ()
              }
              replacement.convert()
            }
            Some(InlineText(s)) => s
            None => ""
          }
        })
      }
    _ => ()
  }
  if doc_attrs.contains("experimental") {
    if found_macroish_short && (text.contains("kbd:") || text.contains("btn:")) {
      text = inline_kbd_btn_macro_rx.replace(text, m => {
        if m.has(1) {
          @rb.from(m.matched(), 1)
        } else if m.at(2) == "kbd" {
          let mut keys = @rb.strip(m.at(3))
          if keys.contains("]") {
            keys = keys.replace_all(old="\\]", new="]")
          }
          let key_list = if keys.length() > 1 {
            let comma = @rb.index_of(keys, ",", from=1)
            let plus = @rb.index_of(keys, "+", from=1)
            let delim_idx = match (comma, plus) {
              (Some(c), Some(p)) => Some(if c < p { c } else { p })
              (Some(c), None) => Some(c)
              (None, Some(p)) => Some(p)
              (None, None) => None
            }
            match delim_idx {
              Some(di) => {
                let delim = @rb.slice(keys, di, di + 1)
                if keys.has_suffix(delim) {
                  let ks = @rb.split(@rb.chop(keys), delim, limit=-1).map(
                    @rb.strip,
                  )
                  ks[ks.length() - 1] = ks[ks.length() - 1] + delim
                  ks
                } else {
                  @rb.split(keys, delim).map(@rb.strip)
                }
              }
              None => [keys]
            }
          } else {
            [keys]
          }
          let attrs = Attributes::new()
          attrs.set("keys", strs(key_list))
          Node::new_inline(self, Kbd, attributes=attrs).convert()
        } else {
          Node::new_inline(
            self,
            Button,
            text=normalize_text(
              m.at(3),
              normalize_whitespace=true,
              unescape_closing_square_brackets=true,
            ),
          ).convert()
        }
      })
    }
    if found_macroish && text.contains("menu:") {
      text = inline_menu_macro_rx.replace(text, m => {
        if m.matched().has_prefix("\\") {
          return @rb.from(m.matched(), 1)
        }
        let menu = m.at(1)
        let mut submenus : Array[String] = []
        let mut menuitem : String? = None
        match m.group(2) {
          Some(items0) => {
            let items = if items0.contains("]") {
              items0.replace_all(old="\\]", new="]")
            } else {
              items0
            }
            let delim = if items.contains("&gt;") {
              Some("&gt;")
            } else if items.contains(",") {
              Some(",")
            } else {
              None
            }
            match delim {
              Some(d) => {
                submenus = @rb.split(items, d).map(@rb.strip)
                menuitem = submenus.pop()
              }
              None => menuitem = Some(@rb.rstrip(items))
            }
          }
          None => ()
        }
        let attrs = Attributes::new()
        attrs.set_str("menu", menu)
        attrs.set("submenus", strs(submenus))
        attrs.set(
          "menuitem",
          match menuitem {
            Some(mi) => Str(mi)
            None => Nil
          },
        )
        Node::new_inline(self, Menu, attributes=attrs).convert()
      })
    }
    if text.contains("\"") && text.contains("&gt;") {
      text = inline_menu_rx.replace(text, m => {
        if m.matched().has_prefix("\\") {
          return @rb.from(m.matched(), 1)
        }
        let parts = @rb.split(m.at(1), "&gt;").map(@rb.strip)
        let menu = parts.remove(0)
        let menuitem = parts.pop()
        let attrs = Attributes::new()
        attrs.set_str("menu", menu)
        attrs.set("submenus", strs(parts))
        attrs.set(
          "menuitem",
          match menuitem {
            Some(mi) => Str(mi)
            None => Nil
          },
        )
        Node::new_inline(self, Menu, attributes=attrs).convert()
      })
    }
  }
  if found_macroish && (text.contains("image:") || text.contains("icon:")) {
    text = inline_image_macro_rx.replace(text, m => {
      let matched = m.matched()
      if matched.has_prefix("\\") {
        return @rb.from(matched, 1)
      }
      let (type_, posattrs) = if matched.has_prefix("icon:") {
        ("icon", [Some("size")])
      } else {
        ("image", [Some("alt"), Some("width"), Some("height")])
      }
      let target = m.at(1)
      let attrs = self.parse_attributes(m.at(2), posattrs, unescape_input=true)
      let mut id : String? = None
      if type_ != "icon" {
        id = attrs.str("id")
        doc.register_image(target)
        if !attrs.truthy("imagesdir") {
          match doc_attrs.get("imagesdir") {
            Some(v) => attrs.set("imagesdir", v)
            None => attrs.set("imagesdir", Nil)
          }
        }
      }
      if !attrs.truthy("alt") {
        let default_alt = basename(target, drop_ext=true)
          .replace_all(old="_", new=" ")
          .replace_all(old="-", new=" ")
        attrs.set_str("default-alt", default_alt)
        attrs.set_str("alt", default_alt)
      }
      Node::new_inline(self, Image, type_~, target~, id?, attributes=attrs).convert()
    })
  }
  if (text.contains("((") && text.contains("))")) ||
    (found_macroish_short && text.contains("dexterm")) {
    text = inline_indexterm_macro_rx.replace(text, m => {
      self.convert_indexterm(m)
    })
  }
  if found_colon && text.contains("://") {
    text = inline_link_rx.replace(text, m => {
      self.convert_inline_link(m, doc, doc_attrs)
    })
  }
  if found_macroish && (text.contains("link:") || text.contains("ilto:")) {
    text = inline_link_macro_rx.replace(text, m => {
      let matched = m.matched()
      if matched.has_prefix("\\") {
        return @rb.from(matched, 1)
      }
      let mailto = m.has(1)
      let mailto_text = m.at(2)
      let mut target = if mailto { "mailto:" + mailto_text } else { m.at(2) }
      let mut attrs : Attributes? = None
      let mut id : String? = None
      let mut link_text = m.at(3)
      if link_text != "" {
        if link_text.contains("]") {
          link_text = link_text.replace_all(old="\\]", new="]")
        }
        if mailto {
          if !doc.compat_mode() && link_text.contains(",") {
            let (lt, a) = self.extract_attributes_from_text(
              link_text,
              default_text=Some(""),
            )
            link_text = lt.unwrap_or("")
            attrs = Some(a)
            id = a.str("id")
            if a.contains_pos(2) {
              let subject = encode_uri_component(a.get_pos(2).unwrap().to_s())
              if a.contains_pos(3) {
                target = "\{target}?subject=\{subject}&amp;body=\{encode_uri_component(a.get_pos(3).unwrap().to_s())}"
              } else {
                target = "\{target}?subject=\{subject}"
              }
            }
          }
        } else if !doc.compat_mode() && link_text.contains("=") {
          let (lt, a) = self.extract_attributes_from_text(
            link_text,
            default_text=Some(""),
          )
          link_text = lt.unwrap_or("")
          attrs = Some(a)
          id = a.str("id")
        }
        if link_text.has_suffix("^") {
          link_text = @rb.chop(link_text)
          match attrs {
            Some(a) => a.set_default("window", Str("_blank"))
            None =>
              attrs = Some(Attributes::from_array([("window", Str("_blank"))]))
          }
        }
      }
      if link_text == "" {
        if mailto {
          link_text = mailto_text
        } else {
          if doc_attrs.contains("hide-uri-scheme") {
            link_text = uri_sniff_rx.sub(target, "")
            if link_text == "" {
              link_text = target
            }
          } else {
            link_text = target
          }
          match attrs {
            Some(a) =>
              a.set_str(
                "role",
                match a.str("role") {
                  Some(r) if a.contains("role") => "bare \{r}"
                  _ => "bare"
                },
              )
            None =>
              attrs = Some(Attributes::from_array([("role", Str("bare"))]))
          }
        }
      }
      doc.register_link(target)
      Node::new_inline(
        self,
        Anchor,
        text=link_text,
        type_="link",
        target~,
        id?,
        attributes?=attrs,
      ).convert()
    })
  }
  if text.contains("@") {
    text = inline_email_rx.replace(text, m => {
      match m.group(1) {
        Some(lead) =>
          if lead == "\\" {
            @rb.from(m.matched(), 1)
          } else {
            m.matched()
          }
        None => {
          let address = m.matched()
          let target = "mailto:" + address
          doc.register_link(target)
          Node::new_inline(self, Anchor, text=address, type_="link", target~).convert()
        }
      }
    })
  }
  if found_square_bracket &&
    self.context == ListItem &&
    (match self.parent_ {
      Some(p) => p.style == Some("bibliography")
      None => false
    }) {
    text = inline_biblio_anchor_rx.replace_first(text, m => {
      Node::new_inline(self, Anchor, text?=m.group(2), type_="bibref", id=m.at(1)).convert()
    })
  }
  if (found_square_bracket && text.contains("[[")) ||
    (found_macroish && text.contains("or:")) {
    text = inline_anchor_rx.replace(text, m => {
      if m.has(1) {
        return @rb.from(m.matched(), 1)
      }
      let (id, reftext) = match m.group(2) {
        Some(id) => (id, m.group(3))
        None => {
          let reftext = match m.group(5) {
            Some(r) if r.contains("]") =>
              Some(r.replace_all(old="\\]", new="]"))
            r => r
          }
          (m.at(4), reftext)
        }
      }
      Node::new_inline(self, Anchor, text?=reftext, type_="ref", id~).convert()
    })
  }
  if (text.contains("&") && text.contains(";&l")) ||
    (found_macroish && text.contains("xref:")) {
    text = inline_xref_macro_rx.replace(text, m => self.convert_xref(m, doc))
  }
  if found_macroish && text.contains("tnote") {
    text = inline_footnote_macro_rx.replace(text, m => {
      let matched = m.matched()
      if matched.has_prefix("\\") {
        return @rb.from(matched, 1)
      }
      let mut id : String? = None
      let mut content : String? = None
      if m.has(1) {
        if m.has(3) {
          let parts = @rb.split(m.at(3), ",", limit=2)
          id = parts.get(0)
          content = parts.get(1)
          if !doc.compat_mode() {
            log_warn(
              "found deprecated footnoteref macro: \{matched}; use footnote macro with target instead",
            )
          }
        } else {
          return matched
        }
      } else {
        id = m.group(2)
        content = m.group(3)
      }
      let mut index : String? = None
      let mut type_ : String? = None
      let mut target : String? = None
      match id {
        Some(fid) =>
          match doc.footnotes().search_by(f => f.id == Some(fid)) {
            Some(i) => {
              let footnote = doc.footnotes()[i]
              index = Some(footnote.index.to_string())
              content = Some(footnote.text)
              type_ = Some("xref")
              target = Some(fid)
              id = None
            }
            None =>
              match content {
                Some(c) => {
                  let c = self.restore_passthroughs(
                    normalize_text(
                      c,
                      normalize_whitespace=true,
                      unescape_closing_square_brackets=true,
                    ),
                  )
                  content = Some(c)
                  let idx = doc.counter("footnote-number")
                  index = Some(idx)
                  doc.register_footnote({
                    index: @rb.to_i(idx),
                    id: Some(fid),
                    text: c,
                  })
                  type_ = Some("ref")
                }
                None => {
                  log_warn("invalid footnote reference: \{fid}")
                  type_ = Some("xref")
                  target = Some(fid)
                  content = Some(fid)
                  id = None
                }
              }
          }
        None =>
          match content {
            Some(c) => {
              let c = self.restore_passthroughs(
                normalize_text(
                  c,
                  normalize_whitespace=true,
                  unescape_closing_square_brackets=true,
                ),
              )
              content = Some(c)
              let idx = doc.counter("footnote-number")
              index = Some(idx)
              doc.register_footnote({ index: @rb.to_i(idx), id: None, text: c, })
            }
            None => return matched
          }
      }
      let attrs = Attributes::new()
      attrs.set(
        "index",
        match index {
          Some(i) =>
            match @rb.parse_int(i) {
              Some(n) => Int(n)
              None => Str(i)
            }
          None => Nil
        },
      )
      Node::new_inline(
        self,
        Footnote,
        text?=content,
        attributes=attrs,
        id?,
        target?,
        type_?,
      ).convert()
    })
  }
  text
}

///|
let inline_macro_rx_cache : Map[String, @regex.Regex] = {}

///|
/// Default regexp for an inline macro extension (Ruby `resolve_regexp`).
fn inline_macro_regexp(name : String, format : String?) -> @regex.Regex {
  let key = name + ":" + format.unwrap_or("long")
  match inline_macro_rx_cache.get(key) {
    Some(r) => r
    None => {
      let src = if format == Some("short") {
        "\\\\?\{name}:\\[((?:\\\\\\]|[^\\]])*?)\\]"
      } else {
        "\\\\?\{name}:(\\S+?)\\[((?:\\\\\\]|[^\\]])*?)\\]"
      }
      let r = @regex.re(src)
      inline_macro_rx_cache[key] = r
      r
    }
  }
}

///|
fn Node::convert_indexterm(self : Node, m : @regex.MatchData) -> String {
  let matched = m.matched()
  let see_also_list = fn(see_also : String) -> AttrVal {
    if see_also.contains(",") {
      List(@rb.split(see_also, ",").map(@rb.lstrip))
    } else {
      List([see_also])
    }
  }
  match m.group(1) {
    Some("indexterm") => {
      if matched.has_prefix("\\") {
        return @rb.from(matched, 1)
      }
      let attrlist = normalize_text(
        m.at(2),
        normalize_whitespace=true,
        unescape_closing_square_brackets=true,
      )
      let attrs = if attrlist.contains("=") {
        let attrs = parse_attribute_list(attrlist, block=self)
        match attrs.pos_str(1) {
          Some(primary) => {
            let terms = [primary]
            match attrs.pos_str(2) {
              Some(secondary) => {
                terms.push(secondary)
                match attrs.pos_str(3) {
                  Some(tertiary) => terms.push(tertiary)
                  None => ()
                }
              }
              None => ()
            }
            attrs.set("terms", List(terms))
            match attrs.str("see-also") {
              Some(sa) => attrs.set("see-also", see_also_list(sa))
              None => ()
            }
            attrs
          }
          None => Attributes::from_array([("terms", Str(attrlist))])
        }
      } else {
        Attributes::from_array([("terms", List(split_simple_csv(attrlist)))])
      }
      Node::new_inline(self, Indexterm, attributes=attrs).convert()
    }
    Some(_) => {
      // indexterm2
      if matched.has_prefix("\\") {
        return @rb.from(matched, 1)
      }
      let mut term = normalize_text(
        m.at(2),
        normalize_whitespace=true,
        unescape_closing_square_brackets=true,
      )
      let mut attrs : Attributes? = None
      if term.contains("=") {
        let a = parse_attribute_list(term, block=self)
        match a.pos_str(1) {
          Some(t) => {
            term = t
            attrs = Some(a)
            match a.str("see-also") {
              Some(sa) => a.set("see-also", see_also_list(sa))
              None => ()
            }
          }
          None => ()
        }
      }
      Node::new_inline(
        self,
        Indexterm,
        text=term,
        attributes?=attrs,
        type_="visible",
      ).convert()
    }
    None => {
      let mut encl_text = m.at(3)
      let mut visible = true
      let mut before : String? = None
      let mut after = ""
      if matched.has_prefix("\\") {
        if encl_text.has_prefix("(") && encl_text.has_suffix(")") {
          encl_text = @rb.slice(encl_text, 1, encl_text.length() - 1)
          before = Some("(")
          after = ")"
        } else {
          return @rb.from(matched, 1)
        }
      } else if encl_text.has_prefix("(") {
        if encl_text.has_suffix(")") {
          encl_text = @rb.slice(encl_text, 1, encl_text.length() - 1)
          visible = false
        } else {
          encl_text = @rb.from(encl_text, 1)
          before = Some("(")
          after = ""
        }
      } else if encl_text.has_suffix(")") {
        encl_text = @rb.chop(encl_text)
        before = Some("")
        after = ")"
      }
      let subbed_term = if visible {
        let mut term = normalize_text(encl_text, normalize_whitespace=true)
        let mut attrs : Attributes? = None
        if term.contains(";&") {
          if term.contains(" &gt;&gt; ") {
            let (t, _, see) = @rb.partition(term, " &gt;&gt; ")
            term = t
            attrs = Some(Attributes::from_array([("see", Str(see))]))
          } else if term.contains(" &amp;&gt; ") {
            let parts = @rb.split(term, " &amp;&gt; ")
            term = parts.remove(0)
            attrs = Some(Attributes::from_array([("see-also", List(parts))]))
          }
        }
        Node::new_inline(
          self,
          Indexterm,
          text=term,
          attributes?=attrs,
          type_="visible",
        ).convert()
      } else {
        let attrs = Attributes::new()
        let mut terms = normalize_text(encl_text, normalize_whitespace=true)
        if terms.contains(";&") {
          if terms.contains(" &gt;&gt; ") {
            let (t, _, see) = @rb.partition(terms, " &gt;&gt; ")
            terms = t
            attrs.set_str("see", see)
          } else if terms.contains(" &amp;&gt; ") {
            let parts = @rb.split(terms, " &amp;&gt; ")
            terms = parts.remove(0)
            attrs.set("see-also", List(parts))
          }
        }
        attrs.set("terms", List(split_simple_csv(terms)))
        Node::new_inline(self, Indexterm, attributes=attrs).convert()
      }
      match before {
        Some(b) => "\{b}\{subbed_term}\{after}"
        None => subbed_term
      }
    }
  }
}

///|
fn Node::convert_inline_link(
  self : Node,
  m : @regex.MatchData,
  doc : Node,
  doc_attrs : Attributes,
) -> String {
  let matched = m.matched()
  let g1 = m.at(1)
  if m.has(2) && !m.has(5) {
    if g1.has_prefix("\\") {
      return @rb.from(matched, 1)
    }
    if m.at(3).has_prefix("\\") {
      return "\{g1}\{@rb.from(matched, g1.length() + 1)}"
    }
    guard m.group(6) is Some(g6) else { return matched }
    let target = m.at(3) + g6
    doc.register_link(target)
    let link_text = hide_uri_scheme(doc_attrs, target)
    return Node::new_inline(
      self,
      Anchor,
      text=link_text,
      type_="link",
      target~,
      attributes=Attributes::from_array([("role", Str("bare"))]),
    ).convert()
  }
  if m.at(3).has_prefix("\\") {
    return "\{g1}\{@rb.from(matched, g1.length() + 1)}"
  }
  let mut prefix = g1
  let mut target = m.at(3) +
    (match m.group(4) {
      Some(g4) => g4
      None => m.at(7)
    })
  let mut suffix = ""
  let mut link_text : String? = None
  match m.group(5) {
    Some(g5) => {
      if prefix == "link:" {
        prefix = ""
      }
      link_text = if g5 == "" { None } else { Some(g5) }
    }
    None => {
      match prefix {
        "link:" | "\"" | "'" => return matched
        _ => ()
      }
      match m.group(8) {
        Some(";") => {
          target = @rb.chop(target)
          if target.has_suffix(")") {
            target = @rb.chop(target)
            suffix = ");"
          } else {
            suffix = ";"
          }
          if target == m.at(3) {
            return matched
          }
        }
        Some(":") => {
          target = @rb.chop(target)
          if target.has_suffix(")") {
            target = @rb.chop(target)
            suffix = "):"
          } else {
            suffix = ":"
          }
          if target == m.at(3) {
            return matched
          }
        }
        _ => ()
      }
    }
  }
  let mut attrs : Attributes? = None
  let mut id : String? = None
  let mut bare = false
  match link_text {
    Some(lt0) => {
      let mut lt = lt0
      if lt.contains("]") {
        lt = lt.replace_all(old="\\]", new="]")
      }
      let mut new_link_text : String? = Some(lt)
      if !doc.compat_mode() && lt.contains("=") {
        let (t, a) = self.extract_attributes_from_text(
          lt,
          default_text=Some(""),
        )
        lt = t.unwrap_or("")
        new_link_text = Some(lt)
        attrs = Some(a)
        id = a.str("id")
      }
      if lt.has_suffix("^") {
        lt = @rb.chop(lt)
        new_link_text = Some(lt)
        match attrs {
          Some(a) => a.set_default("window", Str("_blank"))
          None =>
            attrs = Some(Attributes::from_array([("window", Str("_blank"))]))
        }
      }
      if new_link_text == Some("") {
        lt = hide_uri_scheme(doc_attrs, target)
        bare = true
      }
      link_text = Some(lt)
    }
    None => {
      link_text = Some(hide_uri_scheme(doc_attrs, target))
      bare = true
    }
  }
  if bare {
    match attrs {
      Some(a) =>
        a.set_str(
          "role",
          if a.contains("role") {
            "bare \{a.str("role").unwrap_or("")}"
          } else {
            "bare"
          },
        )
      None => attrs = Some(Attributes::from_array([("role", Str("bare"))]))
    }
  }
  doc.register_link(target)
  "\{prefix}\{Node::new_inline(self, Anchor, text?=link_text, type_="link", target~, id?=id, attributes?=attrs).convert()}\{suffix}"
}

///|
fn Node::convert_xref(self : Node, m : @regex.MatchData, doc : Node) -> String {
  let matched = m.matched()
  if matched.has_prefix("\\") {
    return @rb.from(matched, 1)
  }
  let mut attrs = Attributes::new()
  let mut refid = ""
  let mut link_text : String? = None
  let mut macro_ = false
  match m.group(1) {
    Some(r) => {
      refid = r
      if r.contains(",") {
        let (a, _, b) = @rb.partition(r, ",")
        refid = a
        let lt = @rb.lstrip(b)
        link_text = if lt == "" { None } else { Some(lt) }
      }
    }
    None => {
      macro_ = true
      refid = m.at(2)
      match m.group(3) {
        Some(lt0) => {
          let mut lt = lt0
          if lt.contains("]") {
            lt = lt.replace_all(old="\\]", new="]")
          }
          link_text = Some(lt)
          if !doc.compat_mode() && lt.contains("=") {
            let (t, a) = self.extract_attributes_from_text(lt)
            link_text = t
            attrs = a
          }
        }
        None => ()
      }
    }
  }
  let mut fragment : String? = None
  let mut path : String? = None
  let mut src2src : String? = None
  let mut target : String? = None
  if doc.compat_mode() {
    fragment = Some(refid)
  } else {
    match refid.find("#") {
      Some(hash_idx) if (if hash_idx == 0 {
          refid[refid.length() - 1]
        } else {
          refid[hash_idx - 1]
        }) !=
        '&' =>
        if hash_idx > 0 {
          let fragment_len = refid.length() - 1 - hash_idx
          if fragment_len > 0 {
            path = Some(@rb.slice(refid, 0, hash_idx))
            fragment = Some(@rb.slice(refid, hash_idx + 1, refid.length()))
          } else {
            path = Some(@rb.chop(refid))
          }
          let p = path.unwrap()
          if macro_ {
            if p.has_suffix(".adoc") {
              let p2 = @rb.slice(p, 0, p.length() - 5)
              path = Some(p2)
              src2src = Some(p2)
            } else if !has_extname(p) {
              src2src = Some(p)
            }
          } else if [".adoc", ".asciidoc", ".asc", ".ad", ".txt"]
            .iter()
            .any(e => p.has_suffix(e)) {
            let p2 = @rb.slice(p, 0, p.rev_find(".").unwrap())
            path = Some(p2)
            src2src = Some(p2)
          } else {
            src2src = Some(p)
          }
        } else {
          target = Some(refid)
          fragment = Some(@rb.from(refid, 1))
        }
      _ =>
        if macro_ {
          if refid.has_suffix(".adoc") {
            let p = @rb.slice(refid, 0, refid.length() - 5)
            path = Some(p)
            src2src = Some(p)
          } else if has_extname(refid) {
            path = Some(refid)
          } else {
            fragment = Some(refid)
          }
        } else {
          fragment = Some(refid)
        }
    }
  }
  let refs = doc.catalog().refs
  let mut refid_out : String? = None
  if target is Some(_) {
    refid_out = fragment
    if logger().is_info() && !refs.contains(fragment.unwrap_or("")) {
      log_info("possible invalid reference: \{fragment.unwrap_or("")}")
    }
  } else if path is Some(p) {
    if src2src is Some(_) &&
      (
        doc.attributes.str("docname") == Some(p) ||
        doc.catalog().includes.get(p) == Some(true)
      ) {
      match fragment {
        Some(f) => {
          refid_out = Some(f)
          path = None
          target = Some("#\{f}")
          if logger().is_info() && !refs.contains(f) {
            log_info("possible invalid reference: \{f}")
          }
        }
        None => {
          refid_out = None
          path = None
          target = Some("#")
        }
      }
    } else {
      let suffix = if src2src is Some(_) {
        match doc.attributes.get("relfilesuffix") {
          Some(v) => v.to_s()
          None => doc.outfilesuffix()
        }
      } else {
        ""
      }
      let full = "\{doc.attributes.str("relfileprefix").unwrap_or("")}\{p}\{suffix}"
      refid_out = Some(p)
      path = Some(full)
      match fragment {
        Some(f) => {
          refid_out = Some("\{p}#\{f}")
          target = Some("\{full}#\{f}")
        }
        None => target = Some(full)
      }
    }
  } else {
    let f = fragment.unwrap_or("")
    if doc.compat_mode() || !compliance.natural_xrefs {
      refid_out = Some(f)
      target = Some("#\{f}")
      if logger().is_info() && !refs.contains(f) {
        log_info("possible invalid reference: \{f}")
      }
    } else if refs.contains(f) {
      refid_out = Some(f)
      target = Some("#\{f}")
    } else {
      match
        (if f.contains(" ") || @rb.downcase(f) != f {
          doc.resolve_id(f)
        } else {
          None
        }) {
        Some(r) => {
          refid_out = Some(r)
          fragment = Some(r)
          target = Some("#\{r}")
        }
        None => {
          refid_out = Some(f)
          target = Some("#\{f}")
          if logger().is_info() {
            log_info("possible invalid reference: \{f}")
          }
        }
      }
    }
  }
  let opt = fn(v : String?) -> AttrVal {
    match v {
      Some(s) => Str(s)
      None => Nil
    }
  }
  attrs.set("path", opt(path))
  attrs.set("fragment", opt(fragment))
  attrs.set("refid", opt(refid_out))
  Node::new_inline(
    self,
    Anchor,
    text?=link_text,
    type_="xref",
    target?,
    attributes=attrs,
  ).convert()
}
