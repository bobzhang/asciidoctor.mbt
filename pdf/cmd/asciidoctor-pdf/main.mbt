///|
// asciidoctor-pdf INPUT [-o OUTPUT] [-a NAME=VALUE]... [--fonts-dir DIR]
//
// Converts an AsciiDoc file to PDF with the spike backend. `--trace FILE`
// writes where each block went (see `conversion_trace`). The default
// theme's fonts (Noto Serif, M+ 1mn) are read from `--fonts-dir`, else
// from $ASCIIDOCTOR_PDF_FONTS_DIR; the icon fonts of `icons=font` (Font
// Awesome and the other sets of prawn-icon's `data/fonts`) from
// `--icon-fonts-dir`, else $ASCIIDOCTOR_PDF_ICON_FONTS_DIR.

///|
fn usage() -> String {
  "Usage: asciidoctor-pdf INPUT [-o OUTPUT] [-a NAME[=VALUE]]... [--fonts-dir DIR] [--icon-fonts-dir DIR] [--trace FILE]"
}

///|
async fn main {
  let args = @env.args()
  let mut input : String? = None
  let mut output : String? = None
  let mut fonts_dir = @env.get_env_var("ASCIIDOCTOR_PDF_FONTS_DIR")
  let mut trace_file : String? = None
  let mut icon_fonts_dir = @env.get_env_var("ASCIIDOCTOR_PDF_ICON_FONTS_DIR")
  let attributes : Array[(String, @core.AttrVal)] = []
  let mut i = 1
  while i < args.length() {
    let arg = args[i]
    match arg {
      "-o" | "--out-file" if i + 1 < args.length() => {
        output = Some(args[i + 1])
        i += 2
        continue
      }
      "-a" | "--attribute" if i + 1 < args.length() => {
        attributes.append(@asciidoctor.parse_attributes_option(args[i + 1]))
        i += 2
        continue
      }
      "--fonts-dir" if i + 1 < args.length() => {
        fonts_dir = Some(args[i + 1])
        i += 2
        continue
      }
      "--icon-fonts-dir" if i + 1 < args.length() => {
        icon_fonts_dir = Some(args[i + 1])
        i += 2
        continue
      }
      "--trace" if i + 1 < args.length() => {
        trace_file = Some(args[i + 1])
        i += 2
        continue
      }
      "-h" | "--help" => {
        println(usage())
        return
      }
      _ => ()
    }
    input = Some(arg)
    i += 1
  }
  guard input is Some(input) else {
    println(usage())
    fail("bad arguments")
  }
  guard fonts_dir is Some(fonts_dir) else {
    println(
      "asciidoctor-pdf: no fonts; pass --fonts-dir or set ASCIIDOCTOR_PDF_FONTS_DIR",
    )
    fail("bad arguments")
  }
  let files : Array[(String, Bool, Bool, Bytes)] = []
  for entry in @asciidoctor_pdf.default_font_files() {
    let (family, bold, italic, file) = entry
    files.push(
      (family, bold, italic, @fs.read_file(fonts_dir + "/" + file).binary()),
    )
  }
  // the icon fonts (prawn-icon's), for `icons=font`, and asciidoctor-pdf's
  // mapping of Font Awesome 4 icon names, next to its fonts
  let icon_sets : Array[@asciidoctor_pdf.IconSet] = []
  match icon_fonts_dir {
    Some(dir) =>
      for entry in @asciidoctor_pdf.default_icon_font_files() {
        let (name, font, legend) = entry
        icon_sets.push({
          name,
          font: @fs.read_file(dir + "/" + font).binary(),
          legend: @fs.read_file(dir + "/" + legend).text(),
        })
      }
    None => ()
  }
  let legacy_icon_mapping = @fs.read_file(fonts_dir + "/fa-legacy-mapping.yml").text() catch {
    _ => ""
  }
  let catalog = @asciidoctor_pdf.FontCatalog::load(
    files,
    icon_sets~,
    legacy_icon_mapping~,
  )
  @asciidoctor_pdf.register(catalog~)
  let cwd = @env.current_dir().unwrap_or("/")
  let path = @core.expand_path_from(cwd, input)
  let data = @fs.read_file(path).binary()
  let vfs = @io.FsVfs::new(cwd~)
  vfs.add(path, data)
  let text = @core.decode_text(data)
  let doc_attributes : Array[(String, @core.AttrVal)] = [
    ("docfile", Str(path)),
    ("docdir", Str(@core.dirname(path))),
    ("docfilesuffix", Str(@core.extname(path, fallback=""))),
    ("docname", Str(@core.basename(path, drop_ext=true))),
  ]
  // the user's attributes come after the file's, so they win
  doc_attributes.append(attributes)
  let options = @core.Options::new(
    backend="pdf",
    safe=0,
    standalone=true,
    attributes=doc_attributes,
    vfs~,
    // block locations, for the warnings about unsupported content
    sourcemap=true,
  )
  // `docdatetime` (the PDF's ModDate) is the input's modification time,
  // unless SOURCE_DATE_EPOCH pins every date
  let (mtime, _) = @fs.mtime(path) catch { _ => (0L, 0) }
  options.input_mtime = Some(mtime)
  match @env.get_env_var("SOURCE_DATE_EPOCH") {
    Some(s) =>
      @core.set_source_date_epoch(
        Some(@string.parse_int64(s.trim()) catch { _ => 0L }),
      )
    None => ()
  }
  let pdf = @io.run_with_files(vfs, () => {
    let doc = @asciidoctor.load(text, options~)
    @asciidoctor_pdf.convert_document(doc, catalog)
  })
  // what the spike left out or approximated, with its source location
  for warning in @asciidoctor_pdf.conversion_warnings() {
    @stdio.stderr.write("asciidoctor-pdf: \{warning}\n")
  }
  let out = match output {
    Some(o) => @core.expand_path_from(cwd, o)
    None =>
      @core.dirname(path) + "/" + @core.basename(path, drop_ext=true) + ".pdf"
  }
  @fs.write_file(out, pdf, create_mode=CreateOrTruncate)
  match trace_file {
    Some(file) =>
      @fs.write_file(
        @core.expand_path_from(cwd, file),
        @asciidoctor_pdf.conversion_trace().map(l => l + "\n").join(""),
        create_mode=CreateOrTruncate,
      )
    None => ()
  }
}
