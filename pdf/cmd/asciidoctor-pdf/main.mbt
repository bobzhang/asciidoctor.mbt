// The `asciidoctor-pdf` command (Ruby asciidoctor-pdf's `bin/asciidoctor-pdf`,
// which runs Asciidoctor's `Cli::Invoker` with the pdf backend): option
// parsing is in options.mbt; this file converts.
//
// The fonts are bundled: the default, default-sans and
// default-with-font-fallbacks themes' fonts and prawn-icon's icon fonts
// (`icons=font`), so no font files are needed. `--fonts-dir DIR` (or
// $ASCIIDOCTOR_PDF_FONTS_DIR) reads the fonts the themes call
// `GEM_FONTS_DIR` from DIR instead, `--icon-fonts-dir DIR` (or
// $ASCIIDOCTOR_PDF_ICON_FONTS_DIR) the icon fonts.
//
// INPUT `-` reads the document from standard input, as Ruby's
// `Asciidoctor.convert` of a string: no docfile, docdir or docname, and
// paths resolve from the base directory (`-B`, default the working
// directory); the PDF goes to standard output unless `-o` says otherwise.
//
// `--attributes-json FILE` passes API attributes as a JSON object, with
// Ruby's value semantics: a string sets, `null` unsets (and locks), `false`
// soft-unsets, `true` sets to empty, numbers are kept (this is how
// scripts/pdf_compare.mbtx replays the harvested spec cases).
//
// `--pdf-theme-json FILE` is the API's `pdf_theme` option (a theme object,
// used instead of the `pdf-theme` attribute and `media`), as JSON: either
// `{"extends": NAME, "overrides": {KEY: VALUE, ...}}`, asciidoctor-pdf's
// spec helper `build_pdf_theme overrides, extends` (the theme NAME, or the
// default theme when NAME is null, loaded with `ThemeLoader.load_theme`,
// then each flattened key set to its value as is, unprocessed by the
// loader), or `{"table": {KEY: VALUE, ...}}`, a theme's table as is.
//
// `--layout-trace FILE` writes where each block went (see
// `conversion_trace`).

///|
/// A Ruby theme value from JSON: objects are hashes, and numbers are
/// integers when integral (JSON keeps no other distinction).
fn json_theme_value(value : Json) -> @theme.Value {
  match value {
    Null => Null
    True => Bool(true)
    False => Bool(false)
    String(s) => Str(s)
    Number(n, ..) =>
      if n == n.floor() && n.abs() < 9.0e15 {
        Int(n.to_int64())
      } else {
        Float(n)
      }
    Array(items) => Array(items.map(json_theme_value))
    Object(entries) => {
      let map : Map[String, @theme.Value] = Map([])
      for k, v in entries {
        map[k] = json_theme_value(v)
      }
      Hash(map, symbols=false)
    }
  }
}

///|
/// The `pdf_theme` option of `--pdf-theme-json` (see the header).
fn pdf_theme_option(
  json : Json,
) -> ((@theme.Files) -> @theme.Theme raise) raise {
  match json {
    Object(spec) if spec.get("table") is Some(Object(table)) =>
      _files => {
        let theme = @theme.Theme::new()
        for k, v in table {
          theme[k] = json_theme_value(v)
        }
        theme
      }
    Object(spec) => {
      let extends = match spec.get("extends") {
        Some(String(name)) => Some(name)
        _ => None
      }
      let overrides = match spec.get("overrides") {
        Some(Object(m)) => m
        _ => Map([])
      }
      files => {
        let theme = @theme.load_theme(files, theme_name?=extends)
        for k, v in overrides {
          theme[k] = json_theme_value(v)
        }
        theme
      }
    }
    _ => fail("--pdf-theme-json: not a JSON object")
  }
}

///|
/// An API attribute value from JSON (see the header).
fn json_attr(value : Json) -> @core.AttrVal? {
  match value {
    String(s) => Some(Str(s))
    Null => Some(Nil)
    False => Some(Bool(false))
    True => Some(Str(""))
    Number(n, ..) =>
      Some(if n == n.floor() { Int(n.to_int()) } else { Float(n) })
    _ => None
  }
}

///|
async fn write_err(s : String) -> Unit {
  @stdio.stderr.write(s)
}

///|
async fn main {
  let args = @env.args()
  let code = run(args[1:].to_owned())
  if code != 0 {
    c_exit(code)
  }
}

///|
/// Runs the command line and returns the exit code.
async fn run(args : Array[String]) -> Int {
  let command = parse_args(args) catch {
    CliError(msg) => {
      write_err(msg + "\n")
      @stdio.stdout.write(usage)
      return 1
    }
  }
  match command {
    Help => {
      @stdio.stdout.write(usage)
      0
    }
    Version => {
      @stdio.stdout.write(version_text())
      0
    }
    Usage => {
      write_err(usage)
      1
    }
    Convert(opts) => {
      for notice in opts.notices {
        write_err(notice + "\n")
      }
      match check_inputs(opts) {
        Some(msg) => {
          write_err(msg)
          return 1
        }
        None => ()
      }
      invoke(opts)
    }
  }
}

///|
/// Checks the input files and the libraries `-r` names (Ruby
/// `Options#parse!` after parsing). Returns the error to print.
async fn check_inputs(opts : CliOptions) -> String? {
  for input in opts.input_files {
    guard input != "-" else { continue }
    if !@fs.exists(input) {
      return Some("asciidoctor: FAILED: input file \{input} is missing\n")
    }
    match @fs.kind(input) {
      Regular | Pipe =>
        if !@fs.can_read(input) {
          return Some(
            "asciidoctor: FAILED: input file \{input} is not readable\n",
          )
        }
      kind => {
        let ftype = match kind {
          Directory => "directory"
          CharDevice => "characterSpecial"
          BlockDevice => "blockSpecial"
          Socket => "socket"
          SymLink => "link"
          _ => "unknown"
        }
        return Some(
          "asciidoctor: FAILED: input path \{input} is a \{ftype}, not a file\n",
        )
      }
    }
  }
  let trace_hint = if opts.trace {
    ""
  } else {
    "  Use --trace to show backtrace\n"
  }
  // asciidoctor-pdf is built in; Ruby libraries cannot be loaded
  for library in opts.requires {
    if library is ("asciidoctor-pdf" | "asciidoctor/pdf") {
      continue
    }
    return Some(
      "asciidoctor: FAILED: '\{library}' could not be loaded\n\{trace_hint}",
    )
  }
  None
}

///|
/// The message for an error that aborted a conversion.
fn error_message(e : Error) -> String {
  match e {
    Failure(msg) => msg
    // Ruby RuntimeErrors are printed with their class
    @core.ConversionFailed(msg) => "\{msg} (RuntimeError)"
    @core.SecurityError(msg) => msg
    e => e.to_string()
  }
}

///|
/// The document attributes of the command line: `-a` options and
/// `--attributes-json` files, in order.
async fn cli_attributes(opts : CliOptions) -> Array[(String, @core.AttrVal)] {
  let out : Array[(String, @core.AttrVal)] = []
  let mut next = 0
  let flush = (upto : Int) => {
    while next < upto {
      out.push(opts.attributes[next])
      next += 1
    }
  }
  for entry in opts.attributes_json {
    let (at, file) = entry
    flush(at)
    let json = @json.parse(@fs.read_file(file).text())
    guard json is Object(entries) else {
      fail("--attributes-json: \{file} is not a JSON object")
    }
    for name, value in entries {
      guard json_attr(value) is Some(v) else {
        fail("--attributes-json: unsupported value for \{name}")
      }
      out.push((name, v))
    }
  }
  flush(opts.attributes.length())
  out
}

///|
/// Where a document's PDF goes: standard output (`None`) or a file, as
/// Ruby's `Asciidoctor.convert` resolves `to_file` and `to_dir` (relative
/// to the base directory, else the working directory); without either,
/// next to the input file, named after it.
fn output_target(opts : CliOptions, cwd : String, input : String?) -> String? {
  let working_dir = match opts.base_dir {
    Some(d) => @core.expand_path_from(cwd, d)
    None => cwd
  }
  // `-R`: the input's directory below the source root is kept below `-D`
  let to_dir = match (opts.destination_dir, opts.source_dir, input) {
    (Some(d), Some(srcdir), Some(path)) => {
      let srcdir = @core.expand_path_from(cwd, srcdir)
      let indir = @core.dirname(path)
      let d = @core.expand_path_from(working_dir, d)
      if indir.has_prefix(srcdir + "/") {
        Some(d + indir[srcdir.length():].to_owned())
      } else {
        Some(d)
      }
    }
    (Some(d), _, _) => Some(@core.expand_path_from(working_dir, d))
    (None, _, _) => None
  }
  match (opts.output_file, to_dir, input) {
    (Some("-"), _, _) => None
    (Some(f), Some(d), _) => Some(@core.expand_path_from(d, f))
    (Some(f), None, _) => Some(@core.expand_path_from(working_dir, f))
    // standard input goes to standard output
    (None, _, None) => None
    (None, Some(d), Some(path)) =>
      Some(d + "/" + @core.basename(path, drop_ext=true) + ".pdf")
    (None, None, Some(path)) =>
      Some(
        @core.dirname(path) + "/" + @core.basename(path, drop_ext=true) + ".pdf",
      )
  }
}

///|
/// Converts the input files (Ruby `Invoker#invoke!`) and returns the exit
/// code.
async fn invoke(opts : CliOptions) -> Int {
  let cwd = @env.current_dir().unwrap_or("/")
  let messages : Array[@core.LogMessage] = []
  let logger = if opts.verbose == 0 {
    @core.Logger::null()
  } else {
    let default_level : @core.Severity = if opts.verbose == 2 {
      Debug
    } else {
      Warn
    }
    @core.Logger::new(
      m => messages.push(m),
      level=opts.log_level.unwrap_or(default_level),
    )
  }
  @core.set_logger(logger) |> ignore
  match @env.get_env_var("SOURCE_DATE_EPOCH") {
    Some(s) =>
      @core.set_source_date_epoch(
        Some(@string.parse_int64(s.trim()) catch { _ => 0L }),
      )
    None => ()
  }
  let flush_messages = async fn() {
    for m in messages {
      write_err(@core.format_log_message(m) + "\n")
    }
    messages.clear()
  }
  // the backend's own warnings (`WARNING ...`), which count towards
  // `--failure-level` like the log's
  let mut warned = false
  let trace_hint = if opts.trace {
    ""
  } else {
    "  Use --trace to show backtrace\n"
  }
  let failed = async fn(e : Error) {
    flush_messages()
    write_err("asciidoctor: FAILED: \{error_message(e)}\n\{trace_hint}")
    1
  }
  let fonts_dir = match opts.fonts_dir {
    Some(d) => Some(d)
    None => @env.get_env_var("ASCIIDOCTOR_PDF_FONTS_DIR")
  }
  let icon_fonts_dir = match opts.icon_fonts_dir {
    Some(d) => Some(d)
    None => @env.get_env_var("ASCIIDOCTOR_PDF_ICON_FONTS_DIR")
  }
  let (attributes, pdf_theme) = try {
    let pdf_theme = match opts.pdf_theme_json {
      Some(file) =>
        Some(pdf_theme_option(@json.parse(@fs.read_file(file).text())))
      None => None
    }
    (cli_attributes(opts), pdf_theme)
  } catch {
    e => return failed(e)
  }
  @asciidoctor_pdf.register(
    fonts=[@bundled.default_fonts(), @sans.fonts(), @fallback.fonts()],
    icon_fonts=@icons.fonts(),
    fonts_dir?=fonts_dir.map(d => @core.expand_path_from(cwd, d)),
    icon_fonts_dir?=icon_fonts_dir.map(d => @core.expand_path_from(cwd, d)),
    pdf_theme?,
  )
  for input in opts.input_files {
    let stdin = input == "-"
    let path = if stdin {
      None
    } else {
      Some(@core.expand_path_from(cwd, input))
    }
    let timings = if opts.timings {
      Some(@core.Timings::new(() => @async.now().to_double() / 1000.0))
    } else {
      None
    }
    let start = (phase : String) => if timings is Some(t) { t.start(phase) }
    let record = (phase : String) => if timings is Some(t) { t.record(phase) }
    try {
      start("read")
      let data = match path {
        None => @stdio.stdin.read_all().binary()
        Some(path) => @fs.read_file(path).binary()
      }
      let vfs = @io.FsVfs::new(cwd~)
      let doc_attributes : Array[(String, @core.AttrVal)] = match path {
        None => []
        Some(path) => {
          vfs.add(path, data)
          [
            ("docfile", Str(path)),
            ("docdir", Str(@core.dirname(path))),
            ("docfilesuffix", Str(@core.extname(path, fallback=""))),
            ("docname", Str(@core.basename(path, drop_ext=true))),
          ]
        }
      }
      let text = @core.decode_text(data)
      record("read")
      // the user's attributes come after the file's, so they win
      doc_attributes.append(attributes)
      let options = @core.Options::new(
        backend="pdf",
        safe=opts.safe,
        standalone=true,
        attributes=doc_attributes,
        doctype?=opts.doctype,
        base_dir?=opts.base_dir.map(d => @core.expand_path_from(cwd, d)),
        vfs~,
        // block locations, for the warnings about unsupported content
        sourcemap=true,
      )
      // `docdatetime` (the PDF's ModDate) is the input's modification
      // time, unless SOURCE_DATE_EPOCH pins every date
      if path is Some(path) {
        let (mtime, _) = @fs.mtime(path) catch { _ => (0L, 0) }
        options.input_mtime = Some(mtime)
      }
      start("parse")
      let pdf = @io.run_with_files(vfs, () => {
        let doc = @asciidoctor.load(text, options~)
        if doc.processing_error() is Some(e) {
          raise e
        }
        record("parse")
        start("convert")
        @asciidoctor_pdf.convert(doc)
      })
      record("convert")
      flush_messages()
      // what the port left out or approximated, with its source location
      for diagnostic in @asciidoctor_pdf.conversion_warnings() {
        if diagnostic.has_prefix("WARNING ") {
          warned = true
        }
        if opts.verbose > 0 {
          write_err("asciidoctor-pdf: \{diagnostic}\n")
        }
      }
      start("write")
      match output_target(opts, cwd, path) {
        None => @stdio.stdout.write(pdf)
        Some(out) => {
          if path == Some(out) {
            fail("input file and output file cannot be the same: \{out}")
          }
          let outdir = @core.dirname(out)
          if !@fs.exists(outdir) {
            @fs.mkdir(outdir, recursive=true)
          }
          @fs.write_file(out, pdf, create_mode=CreateOrTruncate)
        }
      }
      record("write")
      match opts.layout_trace {
        Some(file) =>
          @fs.write_file(
            @core.expand_path_from(cwd, file),
            @asciidoctor_pdf.conversion_trace().map(l => l + "\n").join(""),
            create_mode=CreateOrTruncate,
          )
        None => ()
      }
      if timings is Some(t) {
        write_err(t.report(subject=input))
      }
    } catch {
      e => return failed(e)
    }
  }
  let max_severity = match (logger.max_severity, warned) {
    (Some(s), true) if s.to_int() >= @core.Severity::Warn.to_int() => Some(s)
    (_, true) => Some(@core.Severity::Warn)
    (s, false) => s
  }
  match max_severity {
    Some(s) if s.to_int() >= opts.failure_level.to_int() => 1
    _ => 0
  }
}

///|
#cfg(target="native")
extern "C" fn c_exit(code : Int) = "exit"

///|
#cfg(target="wasm")
fn c_exit(code : Int) = "wasi_snapshot_preview1" "proc_exit"
