///|
/// A catalog that stands pagelayout's bundled Liberation faces in for the
/// theme's fonts, so the test needs no font files.
fn test_catalog() -> FontCatalog raise {
  let files = []
  for entry in default_font_files() {
    let (family, bold, italic, _) = entry
    let bundled = if family == "M+ 1mn" {
      "Liberation Mono"
    } else {
      "Liberation Serif"
    }
    files.push(
      (
        family,
        bold,
        italic,
        @fontoutlines.outline_sfnt(bundled, bold~, italic~).unwrap(),
      ),
    )
  }
  FontCatalog::load(files)
}

///|
test "a document converts to a paginated pdf" {
  register()
  let catalog = test_catalog()
  let body = StringBuilder()
  body.write_string("= Title\n\n== Section\n\n")
  for i in 0..<120 {
    body.write_string(
      "Paragraph \{i} with *bold* and a https://example.org[link].\n\n",
    )
  }
  body.write_string("----\ncode\n----\n")
  let doc = @asciidoctor.load(
    body.to_string(),
    options=@core.Options::new(backend="pdf", standalone=true),
  )
  let pdf = convert_document(doc, catalog)
  let document = @pdflite.pdf_read_document_from_bytes(pdf)
  inspect(document.pages_of_pagetree().length() > 1, content="true")
}

///|
test "inline markup becomes styled fragments" {
  let fragments = parse_formatted(
    "a <strong>b</strong> <a href=\"https://x\">c</a>&#8217;s",
    Style::new(),
  )
  let described = fragments.map(fn(f) {
    let link = f.style.link.unwrap_or("-")
    "[\{f.text}] bold=\{f.style.bold} link=\{link}"
  })
  inspect(
    described.join("; "),
    content=(
      #|[a ] bold=false link=-; [b] bold=true link=-; [ ] bold=false link=-; [c] bold=false link=https://x; [’s] bold=false link=-
    ),
  )
}

///|
test "unsupported blocks and inline nodes are reported with their location" {
  register()
  let catalog = test_catalog()
  let doc = @asciidoctor.load(
    "= Title\n\nSee image:logo.png[Logo] here.\n\nvideo::intro.mp4[]\n\n++++\n<b>raw</b>\n++++\n",
    options=@core.Options::new(backend="pdf", standalone=true, sourcemap=true),
  )
  ignore(convert_document(doc, catalog))
  inspect(
    conversion_warnings().join("\n"),
    content=(
      #|UNSUPPORTED inline image at <stdin>:3
      #|UNSUPPORTED block video at <stdin>:5
      #|UNSUPPORTED block pass at <stdin>:7
    ),
  )
  // a new conversion starts a new report
  ignore(
    convert_document(
      @asciidoctor.load("plain", options=@core.Options::new(backend="pdf")),
      catalog,
    ),
  )
  inspect(conversion_warnings().length(), content="0")
}

///|
test "information dictionary dates follow Prawn's form" {
  inspect(
    pdf_date_of_attribute("2026-09-29 15:12:28 +0800").unwrap_or("-"),
    content="D:20260929151228+08'00'",
  )
  inspect(
    pdf_date_of_attribute("2019-01-02 03:04:05 UTC").unwrap_or("-"),
    content="D:20190102030405+00'00'",
  )
  inspect(
    pdf_date_of_attribute("2019-01-02 03:04:05 -0530").unwrap_or("-"),
    content="D:20190102030405-05'30'",
  )
  inspect(pdf_date_of_attribute("yesterday").unwrap_or("-"), content="-")
}

///|
test "document info, top anchor and outline levels" {
  register()
  let doc = @asciidoctor.load(
    "= Title\nJane Doe; John Roe\n:publisher: ACME\n:keywords: a, b\n:outlinelevels: 3:1\n:reproducible:\n\ntext\n",
    options=@core.Options::new(backend="pdf", standalone=true),
  )
  let info = pdf_info(doc)
  let entries = [
    ("Title", info.title),
    ("Author", info.author),
    ("Subject", info.subject),
    ("Keywords", info.keywords),
    ("Creator", info.creator),
    ("Producer", info.producer),
    ("CreationDate", info.creation_date),
    ("ModDate", info.mod_date),
  ].filter_map(entry => entry.1.map(value => "\{entry.0}=\{value}"))
  inspect(
    entries.join("; "),
    content="Title=Title; Author=Jane Doe, John Roe; Keywords=a, b; Creator=ACME; Producer=asciidoctor.mbt (spike)",
  )
  inspect(top_anchor(doc), content="__anchor-top")
  let (num, expand) = outline_levels(doc)
  inspect("\{num}:\{expand}", content="3:1")
  let plain = @asciidoctor.load(
    "= T\n:toclevels: 3\n\nx\n",
    options=@core.Options::new(backend="pdf"),
  )
  let (num, expand) = outline_levels(plain)
  inspect("\{num}:\{expand}", content="3:3")
}

///|
test "destination names and the untitled document title follow asciidoctor-pdf" {
  inspect(pdf_anchor_name("_intro"), content="_intro")
  inspect(pdf_anchor_name("test-é"), content="0x746573742dc3a9")
  register()
  let untitled = @asciidoctor.load(
    "== Section\n\ntext\n",
    options=@core.Options::new(backend="pdf", standalone=true),
  )
  inspect(resolve_doctitle(untitled).unwrap_or("-"), content="Untitled")
  inspect(pdf_info(untitled).title.unwrap_or("-"), content="Untitled")
}

///|
test "index terms are anchored, stored and sorted as asciidoctor-pdf does" {
  register()
  let doc = @asciidoctor.load(
    "= T\n\nA ((tiger)) and (((cats, big cats, lions))) a lion.\nindexterm:[Felis,see=cat] ((émigré)) ((42))\n",
    options=@core.Options::new(backend="pdf", standalone=true),
  )
  let text = doc.blocks[0].content()
  // a concealed term is an anchor only, a visible one keeps its text
  inspect(
    text.contains(
      "<a id=\"__indexterm-1\" type=\"indexterm\" visible=\"true\"></a>tiger",
    ),
    content="true",
  )
  inspect(
    text.contains("<a id=\"__indexterm-2\" type=\"indexterm\"></a>"),
    content="true",
  )
  let index = session.index
  inspect(
    index.sorted_categories().map(c => c.name).join(" "),
    content="@ C F T É",
  )
  let cats = index.categories.get("C").unwrap().sorted_terms()[0]
  inspect(cats.is_container(), content="true")
  inspect(cats.sorted_terms()[0].sorted_terms()[0].name, content="lions")
  // the anchor's page makes the occurrence count (roman before the body)
  index.start_page_number = 3
  index.link_dest_to_page("__indexterm-1", 1)
  index.link_dest_to_page("__indexterm-2", 4)
  let tiger = index.categories.get("T").unwrap().sorted_terms()[0]
  inspect(
    tiger.paged_dests().map(d => d.page.unwrap_or("-")).join(","),
    content="i",
  )
  inspect(tiger.anchor(), content="__indextermdef-\{md5_hex(b"tiger")}")
  index.link_associations()
  let felis = index.categories.get("F").unwrap().sorted_terms()[0]
  inspect(felis.see.map(s => s.is_term), content="Some(false)")
  // a dry run stores nothing
  session.scratch += 1
  let before = index.sequence
  ignore(doc.blocks[0].content())
  inspect(index.sequence == before, content="true")
  session.scratch -= 1
}

///|
test "a concealed index term swallows the space before it" {
  let fragments = parse_formatted(
    "Lions <a id=\"__indexterm-1\" type=\"indexterm\"></a> live, <a id=\"__indexterm-2\" type=\"indexterm\" visible=\"true\"></a>tigers",
    Style::new(),
  )
  inspect(
    fragments.map(f => f.anchor.unwrap_or(f.text)).join("|"),
    content="Lions|__indexterm-1| live, |__indexterm-2|tigers",
  )
}

///|
test "names order case-insensitively first, as Ruby's casecmp" {
  let names = ["b", "B", "a", "_x", "Émigré", "A"]
  names.sort_by(compare_index_names)
  inspect(names.join(" "), content="_x A a B b Émigré")
}

///|
test "page labels are roman before the body" {
  inspect(page_label(1, 2), content="i")
  inspect(page_label(2, 2), content="ii")
  inspect(page_label(3, 2), content="1")
  inspect(page_label(7, 0), content="7")
}

///|
test "sections are numbered as asciidoctor-pdf's numbered_title" {
  register()
  let book = @asciidoctor.load(
    "= B\n:doctype: book\n:sectnums:\n\n== One\n\n=== Sub\n\ntext\n\n[appendix]\n== App\n\ntext\n",
    options=@core.Options::new(backend="pdf", standalone=true),
  )
  let chapter = book.sections()[0]
  inspect(numbered_title(chapter), content="1. One")
  inspect(numbered_title(chapter, formal=true), content="Chapter 1. One")
  inspect(numbered_title(chapter.sections()[0]), content="1.1. Sub")
  inspect(numbered_title(book.sections()[1]), content="Appendix A: App")
  let article = @asciidoctor.load(
    "= A\n\n== One\n",
    options=@core.Options::new(backend="pdf", standalone=true),
  )
  inspect(numbered_title(article.sections()[0], formal=true), content="One")
}

///|
test "a word split across fragments breaks at the last word of the fragment before" {
  // "(" + "iss91v2" + ")," is one word to Prawn, but when ")," does not fit
  // only "iss91v2" goes with it to the next line (as in Pro Git's third
  // chapter)
  let style = Style::new()
  let code = { ..style, family: mono_font_family, font_set: true, }
  let fragments : Array[Fragment] = [
    { text: "handling the same thing (", style, anchor: None, },
    { text: "iss91v2", style: code, anchor: None, },
    { text: "), going", style, anchor: None, },
  ]
  let catalog = test_catalog()
  // room for everything up to the code word, not for what follows it
  let (items, _) = build_items(fragments, catalog)
  let mut before = 0.0
  for item in items {
    if item.fragment == 2 {
      break
    }
    before += item.fit
  }
  let lines = typeset_lines(fragments, catalog, before + 2.0, Left)
  inspect(
    lines[0].runs.map(r => r.text).join("|"),
    content="handling the same thing (",
  )
  inspect(lines[1].runs[0].text, content="iss91v2")
}

///|
test "an AsciiDoc table cell lays out its blocks and a TOC reserves its pages" {
  register()
  let catalog = test_catalog()
  let doc = @asciidoctor.load(
    "= T\n:toc:\n\n== One\n\n[cols=\"1a\"]\n|===\n|* item\n\nparagraph\n|===\n\n== Two\n\ntext\n",
    options=@core.Options::new(backend="pdf", standalone=true),
  )
  let pdf = convert_document(doc, catalog)
  inspect(conversion_warnings().length(), content="0")
  let document = @pdflite.pdf_read_document_from_bytes(pdf)
  inspect(document.pages_of_pagetree().length(), content="1")
}
