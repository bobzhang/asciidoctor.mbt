///|
// asciidoctor-pdf INPUT [-o OUTPUT] [-a NAME=VALUE]... [--theme THEME]
//                 [--fonts-dir DIR]
//
// Converts an AsciiDoc file to PDF with the spike backend. The theme is
// the `pdf-theme` attribute's (`--theme THEME` sets it), looked up in
// `pdf-themesdir`, else the bundled default theme. `--trace FILE` writes
// where each block went (see `conversion_trace`). The bundled fonts the
// themes name (`GEM_FONTS_DIR`: asciidoctor-pdf's `data/fonts`) are read
// from `--fonts-dir`, else from $ASCIIDOCTOR_PDF_FONTS_DIR; the icon fonts
// of `icons=font` (Font Awesome and the other sets of prawn-icon's
// `data/fonts`) from `--icon-fonts-dir`, else
// $ASCIIDOCTOR_PDF_ICON_FONTS_DIR.

///|
fn usage() -> String {
  "Usage: asciidoctor-pdf INPUT [-o OUTPUT] [-a NAME[=VALUE]]... [--theme THEME] [--fonts-dir DIR] [--icon-fonts-dir DIR] [--trace FILE]"
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
      // `--theme NAME` is `-a pdf-theme=NAME`, as in asciidoctor-pdf
      "--theme" if i + 1 < args.length() && !args[i + 1].has_prefix("-") => {
        attributes.push(("pdf-theme", Str(args[i + 1])))
        i += 2
        continue
      }
      arg if arg.has_prefix("--theme=") => {
        attributes.push(("pdf-theme", Str(arg[8:].to_owned())))
        i += 1
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
  let cwd = @env.current_dir().unwrap_or("/")
  // the theme's fonts are read as the conversion needs them: the bundled
  // ones (`GEM_FONTS_DIR`) from the fonts directory, and the icon fonts of
  // `icons=font` (prawn-icon's) from theirs
  @asciidoctor_pdf.register(
    fonts_dir=@core.expand_path_from(cwd, fonts_dir),
    icon_fonts_dir?=icon_fonts_dir.map(d => @core.expand_path_from(cwd, d)),
  )
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
    @asciidoctor_pdf.convert(doc)
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
