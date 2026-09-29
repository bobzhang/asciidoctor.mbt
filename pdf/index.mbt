///|
// The index: asciidoctor-pdf's IndexCatalog (lib/asciidoctor/pdf/
// index_catalog.rb). Every index term met while converting inline content
// (`((term))`, `(((a, b, c)))`, `indexterm:[]`, `indexterm2:[]`) is
// anchored where it occurs (`__indexterm-N`) and stored under its category
// (the upper-cased first letter, `@` for anything else) with the page the
// anchor lands on, which the `[index]` section lists.

///|
/// One occurrence of a term: its anchor and, once inked, the page label
/// and physical page number (`dest[:page]`, `dest[:page_sortable]`).
priv struct IndexDest {
  anchor : String
  mut page : String?
  mut page_sortable : Int
}

///|
/// A term, a category (the terms under a letter) or an unresolved `see`
/// target: asciidoctor-pdf's IndexTermGroup and its subclasses.
priv struct IndexTerm {
  /// the formatted-text markup of the name
  markup : String
  /// the plain text of the name (FormattedString#to_s), which orders and
  /// matches terms
  name : String
  /// subterms (or a category's terms), by markup, in insertion order
  terms : Map[String, IndexTerm]
  dests : Array[IndexDest]
  /// the `see` and `see-also` associations, as markup
  mut see_markup : String?
  see_also_markup : Array[String]
  /// resolved associations: a term, or an unresolved name (no anchor)
  mut see : IndexTerm?
  mut see_also : Array[IndexTerm]
  /// whether this is a term (it has an anchor) rather than an unresolved
  /// name or a category
  is_term : Bool
}

///|
fn IndexTerm::new(markup : String, is_term? : Bool = true) -> IndexTerm {
  {
    markup,
    name: formatted_plain_text(markup),
    terms: Map([]),
    dests: [],
    see_markup: None,
    see_also_markup: [],
    see: None,
    see_also: [],
    is_term,
  }
}

///|
/// The text of formatted markup, as the fragments asciidoctor-pdf's
/// `parse_text ... normalize: true` yields would spell it.
fn formatted_plain_text(markup : String) -> String {
  let sb = StringBuilder()
  for fragment in parse_formatted(markup, Style::new()) {
    sb.write_string(fragment.text)
  }
  sb.to_string()
}

///|
/// The destination name of a term's own entry in the index.
fn IndexTerm::anchor(self : IndexTerm) -> String {
  "__indextermdef-\{md5_hex(@utf8.encode(self.name))}"
}

///|
/// `IndexTermGroup#store_term`
fn IndexTerm::store_term(
  self : IndexTerm,
  markup : String,
  dest : IndexDest?,
  see? : String? = None,
  see_also? : Array[String] = [],
) -> IndexTerm {
  let term = match self.terms.get(markup) {
    Some(term) => term
    None => {
      let term = IndexTerm::new(markup)
      self.terms[markup] = term
      term
    }
  }
  match dest {
    Some(d) => term.dests.push(d)
    None => ()
  }
  if term.see_markup is None && see is Some(_) {
    term.see_markup = see
  }
  term.see_also_markup.append(see_also)
  term
}

///|
/// Ruby's `IndexTermGroup#<=>`: case-insensitive (ASCII) first, then by
/// bytes.
fn compare_index_names(a : String, b : String) -> Int {
  let fold = fn(s : String) -> String {
    let sb = StringBuilder()
    for c in s {
      sb.write_char(
        if c >= 'A' && c <= 'Z' {
          (c.to_int() + 32).unsafe_to_char()
        } else {
          c
        },
      )
    }
    sb.to_string()
  }
  let c = compare_bytes(@utf8.encode(fold(a)), @utf8.encode(fold(b)))
  if c != 0 {
    c
  } else {
    compare_bytes(@utf8.encode(a), @utf8.encode(b))
  }
}

///|
fn compare_bytes(a : Bytes, b : Bytes) -> Int {
  let n = @cmp.minimum(a.length(), b.length())
  for i in 0..<n {
    if a[i] != b[i] {
      return a[i].to_int() - b[i].to_int()
    }
  }
  a.length() - b.length()
}

///|
/// The subterms (a category's terms), sorted.
fn IndexTerm::sorted_terms(self : IndexTerm) -> Array[IndexTerm] {
  let terms = self.terms.values().collect()
  terms.sort_by((a, b) => compare_index_names(a.name, b.name))
  terms
}

///|
/// `IndexTerm#dests`: the occurrences inked so far, by page.
fn IndexTerm::paged_dests(self : IndexTerm) -> Array[IndexDest] {
  let dests = self.dests.filter(d => d.page is Some(_))
  dests.sort_by((a, b) => a.page_sortable - b.page_sortable)
  dests
}

///|
/// `IndexTerm#container?`: no occurrence of its own on any page.
fn IndexTerm::is_container(self : IndexTerm) -> Bool {
  self.dests.iter().all(d => d.page is None)
}

///|
priv struct IndexCatalog {
  categories : Map[String, IndexTerm]
  dests : Map[String, IndexDest]
  mut sequence : Int
  mut start_page_number : Int
}

///|
fn IndexCatalog::new() -> IndexCatalog {
  { categories: Map([]), dests: Map([]), sequence: 0, start_page_number: 1, }
}

///|
fn IndexCatalog::next_anchor_name(self : IndexCatalog) -> String {
  self.sequence += 1
  "__indexterm-\{self.sequence}"
}

///|
/// Ruby's `/^\p{Alpha}/` on an upper-cased first character, for the
/// scripts the default fonts cover.
fn is_alpha_char(c : Char) -> Bool {
  let cp = c.to_int()
  (cp >= 'A'.to_int() && cp <= 'Z'.to_int()) ||
  (cp >= 'a'.to_int() && cp <= 'z'.to_int()) ||
  cp == 0xAA ||
  cp == 0xB5 ||
  cp == 0xBA ||
  (cp >= 0xC0 && cp <= 0x24F && cp != 0xD7 && cp != 0xF7) ||
  (
    cp >= 0x370 &&
    cp <= 0x3FF &&
    cp != 0x375 &&
    cp != 0x37E &&
    cp != 0x384 &&
    cp != 0x385 &&
    cp != 0x387
  ) ||
  (cp >= 0x400 && cp <= 0x481) ||
  (cp >= 0x48A && cp <= 0x52F) ||
  (cp >= 0x3040 && cp <= 0x30FF && cp != 0x30A0 && cp != 0x30FB) ||
  (cp >= 0x4E00 && cp <= 0x9FFF) ||
  (cp >= 0xAC00 && cp <= 0xD7A3)
}

///|
/// Ruby's `String#upcase` of one character, for Latin, Greek and Cyrillic.
fn upcase_char(c : Char) -> Char {
  let cp = c.to_int()
  let upper = if cp >= 'a'.to_int() && cp <= 'z'.to_int() {
    cp - 32
  } else if cp >= 0xE0 && cp <= 0xFE && cp != 0xF7 {
    cp - 32
  } else if cp == 0xFF {
    0x178
  } else if cp >= 0x100 &&
    cp <= 0x17F &&
    cp != 0x131 &&
    cp != 0x138 &&
    cp != 0x149 &&
    cp != 0x17F {
    // alternating pairs (with the odd stretch 0x139..0x148, 0x179..0x17E)
    if (cp >= 0x139 && cp <= 0x148) || (cp >= 0x179 && cp <= 0x17E) {
      if cp % 2 == 0 {
        cp - 1
      } else {
        cp
      }
    } else if cp % 2 == 1 {
      cp - 1
    } else {
      cp
    }
  } else if cp >= 0x3B1 && cp <= 0x3C9 && cp != 0x3C2 {
    cp - 32
  } else if cp >= 0x430 && cp <= 0x44F {
    cp - 32
  } else if cp >= 0x450 && cp <= 0x45F {
    cp - 80
  } else {
    cp
  }
  upper.unsafe_to_char()
}

///|
/// `init_category`
fn IndexCatalog::init_category(self : IndexCatalog, name : String) -> IndexTerm {
  let first = match name.get_char(0) {
    Some(c) => upcase_char(c)
    None => '@'
  }
  let key = if is_alpha_char(first) { first.to_string() } else { "@" }
  match self.categories.get(key) {
    Some(category) => category
    None => {
      let category = IndexTerm::new(key, is_term=false)
      self.categories[key] = category
      category
    }
  }
}

///|
/// `store_term`: a primary, secondary or tertiary term (the names are
/// markup), occurring at `dest`.
fn IndexCatalog::store_term(
  self : IndexCatalog,
  names : Array[String],
  dest : IndexDest,
  see? : String? = None,
  see_also? : Array[String] = [],
) -> Unit {
  if names.is_empty() {
    return
  }
  self.dests[dest.anchor] = dest
  let primary = names[0]
  let category = self.init_category(formatted_plain_text(primary))
  match names.length() {
    1 => ignore(category.store_term(primary, Some(dest), see~, see_also~))
    2 =>
      ignore(
        category
        .store_term(primary, None)
        .store_term(names[1], Some(dest), see~, see_also~),
      )
    _ =>
      ignore(
        category
        .store_term(primary, None)
        .store_term(names[1], None)
        .store_term(names[2], Some(dest), see~, see_also~),
      )
  }
}

///|
/// `link_dest_to_page`: the anchor `anchor` was inked on physical page
/// `physical` (1-based).
fn IndexCatalog::link_dest_to_page(
  self : IndexCatalog,
  anchor : String,
  physical : Int,
) -> Unit {
  match self.dests.get(anchor) {
    Some(dest) => {
      dest.page_sortable = physical
      let virtual_number = physical - (self.start_page_number - 1)
      dest.page = Some(
        if virtual_number < 1 {
          roman(physical, false)
        } else {
          virtual_number.to_string()
        },
      )
    }
    None => ()
  }
}

///|
/// `find_primary_term`: a term of any category whose name reads `name`.
fn IndexCatalog::find_primary_term(
  self : IndexCatalog,
  name : String,
) -> IndexTerm? {
  for category in self.categories.values() {
    for term in category.terms.values() {
      if term.name == name {
        return Some(term)
      }
    }
  }
  None
}

///|
/// `link_associations`: resolve `see` and `see also` names to terms.
fn IndexCatalog::link_associations(self : IndexCatalog) -> Unit {
  fn resolve(markup : String) -> IndexTerm {
    match self.find_primary_term(formatted_plain_text(markup)) {
      Some(term) => term
      None => IndexTerm::new(markup, is_term=false)
    }
  }

  fn walk(group : IndexTerm) -> Unit {
    for term in group.terms.values() {
      match term.see_markup {
        Some(see) => term.see = Some(resolve(see))
        None =>
          if !term.see_also_markup.is_empty() {
            term.see_also = term.see_also_markup.map(resolve)
          }
      }
      if !term.terms.is_empty() {
        walk(term)
      }
    }
  }

  for category in self.categories.values() {
    walk(category)
  }
}

///|
fn IndexCatalog::is_empty(self : IndexCatalog) -> Bool {
  self.categories.is_empty()
}

///|
fn IndexCatalog::sorted_categories(self : IndexCatalog) -> Array[IndexTerm] {
  let categories = self.categories.values().collect()
  categories.sort_by((a, b) => compare_index_names(a.name, b.name))
  categories
}
