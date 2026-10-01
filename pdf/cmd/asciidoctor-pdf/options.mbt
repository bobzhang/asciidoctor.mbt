// Command line option parsing, as Ruby asciidoctor-pdf's `bin/asciidoctor-pdf`:
// Asciidoctor's `Cli::Options` (OptionParser) with the backend preset to
// `pdf`, a `--theme` option and the version naming Asciidoctor PDF; plus a
// few options of this port (fonts directories, theme and attribute JSON,
// the layout trace). `parse_args` is pure: it does not touch the file
// system or the streams; `main` checks the input files and converts.

///|
let usage : String =
  #|Usage: asciidoctor-pdf [OPTION]... FILE...
  #|Convert the AsciiDoc input FILE(s) to PDF
  #|Unless specified otherwise, the output is written to a file whose name is derived from the input file.
  #|Application log messages are printed to STDERR.
  #|Example: asciidoctor-pdf input.adoc
  #|
  #|    -b, --backend BACKEND            set backend output format: [pdf] (default: pdf)
  #|    -d, --doctype DOCTYPE            document type to use when converting document: [article, book, manpage, inline] (default: article)
  #|    -o, --out-file FILE              output file (default: based on path of input file); use - to output to STDOUT
  #|        --safe                       set safe mode level to safe (default: unsafe)
  #|                                     enables include directives, but prevents access to ancestor paths of source file
  #|                                     provided for compatibility with the asciidoc command
  #|    -S, --safe-mode SAFE_MODE        set safe mode level explicitly: [unsafe, safe, server, secure] (default: unsafe)
  #|                                     disables potentially dangerous macros in source files, such as include::[]
  #|    -n, --section-numbers            auto-number section titles; disabled by default
  #|    -a, --attribute name[=value]     a document attribute to set in the form of name, name!, or name=value pair
  #|                                     that takes precedence over the same attribute defined in the source document
  #|                                     unless either the name or value ends in @ (i.e., name@=value or name=value@)
  #|                                     may be specified more than once
  #|        --theme THEME                the PDF theme: the name of a bundled theme (default, default-sans,
  #|                                     default-with-font-fallbacks, base, ...) or a theme file (same as -a pdf-theme=THEME)
  #|    -B, --base-dir DIR               base directory containing the document and resources (default: directory of source file)
  #|    -R, --source-dir DIR             source root directory (used for calculating path in destination directory)
  #|    -D, --destination-dir DIR        destination output directory (default: directory of source file)
  #|    -r, --require LIBRARY            require the specified library before executing the processor
  #|                                     only asciidoctor-pdf is accepted (it is built in); Ruby libraries cannot be loaded
  #|        --log-level LEVEL            set minimum level of log messages that get logged: [DEBUG, INFO, WARN, ERROR, FATAL] (default: WARN)
  #|        --failure-level LEVEL        set minimum log level that yields a non-zero exit code: [INFO, WARN, ERROR, FATAL] (default: FATAL)
  #|    -q, --quiet                      silence application log messages (default: false)
  #|        --trace                      include backtrace information when reporting errors (default: false)
  #|    -v, --verbose                    show all application log messages, including DEBUG and INFO levels (default: false)
  #|    -t, --timings                    print timings report (default: false)
  #|    -h, --help                       print this help message
  #|    -V, --version                    display the version and runtime environment (or -v if no other flags or arguments)
  #|
  #|Options of this MoonBit port:
  #|        --fonts-dir DIR              read the fonts themes call GEM_FONTS_DIR from DIR (a copy of asciidoctor-pdf's
  #|                                     data/fonts) instead of the bundled ones (also: $ASCIIDOCTOR_PDF_FONTS_DIR)
  #|        --icon-fonts-dir DIR         read the icon fonts (icons=font) from DIR (prawn-icon's data/fonts) instead of
  #|                                     the bundled ones (also: $ASCIIDOCTOR_PDF_ICON_FONTS_DIR)
  #|        --pdf-theme-json FILE        the pdf_theme API option, as JSON (see the source of the command)
  #|        --attributes-json FILE       API attributes as a JSON object (null unsets, false soft-unsets)
  #|        --layout-trace FILE          write where each block was placed to FILE
  #|

///|
/// The version report: Ruby asciidoctor-pdf's `print_version` (which puts
/// `Asciidoctor PDF <version> using ` before Asciidoctor's), naming this
/// port as the runtime environment.
fn version_text() -> String {
  "Asciidoctor PDF \{@asciidoctor_pdf.version} using Asciidoctor \{@core.VERSION} [https://asciidoctor.org]\nRuntime Environment (MoonBit port of asciidoctor-pdf \{@asciidoctor_pdf.ruby_version}, \{target_name()}) (lc:UTF-8 fs:UTF-8 in:UTF-8 ex:UTF-8)\n"
}

///|
#cfg(target="native")
fn target_name() -> String {
  "native"
}

///|
#cfg(not(target="native"))
fn target_name() -> String {
  "wasm"
}

///|
/// The options of a conversion run.
priv struct CliOptions {
  /// document attributes, in order (a later one wins)
  attributes : Array[(String, @core.AttrVal)]
  input_files : Array[String]
  mut output_file : String?
  mut safe : Int
  mut doctype : String?
  /// 0 (`-q`), 1 (default) or 2 (`-v`)
  mut verbose : Int
  mut base_dir : String?
  mut source_dir : String?
  mut destination_dir : String?
  mut log_level : @core.Severity?
  mut failure_level : @core.Severity
  mut trace : Bool
  mut timings : Bool
  /// the libraries `-r` names (only asciidoctor-pdf itself is accepted)
  requires : Array[String]
  mut fonts_dir : String?
  mut icon_fonts_dir : String?
  mut pdf_theme_json : String?
  /// `--attributes-json` files, in order with the `-a` options
  attributes_json : Array[(Int, String)]
  mut layout_trace : String?
  /// warnings to print on stderr before converting
  notices : Array[String]
}

///|
fn CliOptions::new() -> CliOptions {
  {
    attributes: [],
    input_files: [],
    output_file: None,
    safe: @core.SAFE_UNSAFE,
    doctype: None,
    verbose: 1,
    base_dir: None,
    source_dir: None,
    destination_dir: None,
    log_level: None,
    failure_level: Fatal,
    trace: false,
    timings: false,
    requires: [],
    fonts_dir: None,
    icon_fonts_dir: None,
    pdf_theme_json: None,
    attributes_json: [],
    layout_trace: None,
    notices: [],
  }
}

///|
/// What the command line asks for.
priv enum CliCommand {
  /// Convert the input files (`-` is standard input).
  Convert(CliOptions)
  /// `-h`: print the usage on stdout.
  Help
  /// `-V`, or `-v` without input files: print the version on stdout.
  Version
  /// No input files: print the usage on stderr and fail.
  Usage
}

///|
/// An invalid command line: the line Ruby prints on stderr (followed by
/// the usage on stdout).
priv suberror CliError {
  CliError(String)
}

///|
priv enum ArgKind {
  NoArg
  Required
  Optional
}

///|
priv struct Switch {
  short : Char?
  long : String
  arg : ArgKind
  /// the accepted values of an enumerated argument (empty: any value)
  values : Array[String]
}

///|
let log_levels : Array[String] = [
  "debug", "DEBUG", "info", "INFO", "warning", "WARNING", "error", "ERROR", "fatal",
  "FATAL",
]

///|
/// The switches, in Ruby's definition order, then this port's.
let switches : Array[Switch] = [
  { short: Some('b'), long: "backend", arg: Required, values: [], },
  {
    short: Some('d'),
    long: "doctype",
    arg: Required,
    values: ["article", "book", "manpage", "inline"],
  },
  { short: Some('e'), long: "embedded", arg: NoArg, values: [], },
  { short: Some('o'), long: "out-file", arg: Required, values: [], },
  { short: None, long: "safe", arg: NoArg, values: [], },
  {
    short: Some('S'),
    long: "safe-mode",
    arg: Required,
    values: ["unsafe", "safe", "server", "secure"],
  },
  { short: None, long: "sourcemap", arg: NoArg, values: [], },
  { short: Some('s'), long: "no-header-footer", arg: NoArg, values: [], },
  { short: Some('n'), long: "section-numbers", arg: NoArg, values: [], },
  {
    short: None,
    long: "eruby",
    arg: Required,
    values: ["erb", "erubi", "erubis"],
  },
  { short: Some('a'), long: "attribute", arg: Required, values: [], },
  { short: Some('T'), long: "template-dir", arg: Required, values: [], },
  { short: Some('E'), long: "template-engine", arg: Required, values: [], },
  { short: Some('B'), long: "base-dir", arg: Required, values: [], },
  { short: Some('R'), long: "source-dir", arg: Required, values: [], },
  { short: Some('D'), long: "destination-dir", arg: Required, values: [], },
  { short: Some('I'), long: "load-path", arg: Required, values: [], },
  { short: Some('r'), long: "require", arg: Required, values: [], },
  { short: None, long: "log-level", arg: Required, values: log_levels, },
  {
    short: None,
    long: "failure-level",
    arg: Required,
    values: log_levels[2:].to_owned(),
  },
  { short: Some('q'), long: "quiet", arg: NoArg, values: [], },
  { short: None, long: "trace", arg: NoArg, values: [], },
  { short: Some('v'), long: "verbose", arg: NoArg, values: [], },
  { short: Some('w'), long: "warnings", arg: NoArg, values: [], },
  { short: Some('t'), long: "timings", arg: NoArg, values: [], },
  { short: Some('h'), long: "help", arg: Optional, values: [], },
  { short: Some('V'), long: "version", arg: NoArg, values: [], },
  { short: None, long: "fonts-dir", arg: Required, values: [], },
  { short: None, long: "icon-fonts-dir", arg: Required, values: [], },
  { short: None, long: "pdf-theme-json", arg: Required, values: [], },
  { short: None, long: "attributes-json", arg: Required, values: [], },
  { short: None, long: "layout-trace", arg: Required, values: [], },
]

///|
fn ascii_downcase(s : String) -> String {
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

///|
priv enum Completion {
  NoMatch
  Match(String)
  Ambiguous
}

///|
/// OptionParser's completion: the candidates starting with `key` (sorted by
/// length) must all extend the shortest one, which is chosen.
fn complete(
  candidates : Array[String],
  key : String,
  icase~ : Bool,
) -> Completion {
  let fold = fn(s : String) { if icase { ascii_downcase(s) } else { s } }
  let k = fold(key)
  let matches = candidates.filter(c => abbreviates(k, fold(c)))
  guard !matches.is_empty() else { return NoMatch }
  matches.sort_by_key(c => c.length())
  let canon = matches[0]
  for other in matches[1:] {
    guard other.has_prefix(canon) else { return Ambiguous }
  }
  Match(canon)
}

///|
fn is_word_char(c : UInt16) -> Bool {
  (c >= 'a' && c <= 'z') ||
  (c >= 'A' && c <= 'Z') ||
  (c >= '0' && c <= '9') ||
  c == '_'
}

///|
/// Whether `key` abbreviates `name`: OptionParser matches `/\A#{key}/` with
/// `\w*` after each word of the key, so every word may be shortened
/// (`--b-d` is `--base-dir`).
fn abbreviates(key : String, name : String) -> Bool {
  let mut j = 0
  for i in 0..<key.length() {
    let c = key[i]
    guard j < name.length() && name[j] == c else { return false }
    j += 1
    if is_word_char(c) && (i + 1 == key.length() || !is_word_char(key[i + 1])) {
      while j < name.length() && is_word_char(name[j]) {
        j += 1
      }
    }
  }
  true
}

///|
fn find_long(name : String, icase~ : Bool) -> (Switch?, Bool) {
  match switches.search_by(sw => sw.long == name) {
    Some(i) => return (Some(switches[i]), false)
    None => ()
  }
  match complete(switches.map(sw => sw.long), name, icase~) {
    Match(l) =>
      (switches.search_by(sw => sw.long == l).map(i => switches[i]), false)
    NoMatch => (None, false)
    Ambiguous => (None, true)
  }
}

///|
fn severity_of(level : String) -> @core.Severity {
  match ascii_downcase(level) {
    "debug" => Debug
    "info" => Info
    "warning" => Warn
    "error" => Error
    _ => Fatal
  }
}

///|
/// Ruby asciidoctor-pdf's rewrite of `--theme THEME` (or `--theme=THEME`)
/// into `-a pdf-theme=THEME`, before the options are parsed: only the
/// first, and only when a value follows that is not an option.
fn rewrite_theme(args : Array[String]) -> Array[String] {
  let args = args.copy()
  match args.search_by(a => a == "--theme" || a.has_prefix("--theme=")) {
    Some(i) =>
      if args[i].length() > 7 {
        // `--theme=THEME`
        args[i] = "pdf" + args[i][1:].to_owned()
        args.insert(i, "-a")
      } else if i + 1 < args.length() && !args[i + 1].has_prefix("-") {
        args[i] = "-a"
        args[i + 1] = "pdf-theme=\{args[i + 1]}"
      }
    None => ()
  }
  args
}

///|
/// Parses the command line arguments (without the program name), like Ruby's
/// `Cli::Options.parse!`: options may follow the input files, long options may
/// be abbreviated and written `--name=value`, short options may be clustered
/// (`-qn`) or take an attached value (`-Ssafe`), and `--` ends the options.
/// Input files are not checked here.
fn parse_args(args : Array[String]) -> CliCommand raise CliError {
  let opts = CliOptions::new()
  let inputs = []
  // pending arguments, processed front to back (short clusters are pushed
  // back)
  let queue = rewrite_theme(args).rev()
  while queue.pop() is Some(arg) {
    if arg == "--" {
      while queue.pop() is Some(a) {
        inputs.push(a)
      }
      break
    }
    if arg.has_prefix("--") {
      let rest = arg[2:].to_owned()
      let (name0, attached) = match rest.find("=") {
        Some(i) => (rest[:i].to_owned(), Some(rest[i + 1:].to_owned()))
        None => (rest, None)
      }
      let name = name0.replace_all(old="_", new="-")
      let (sw, ambiguous) = find_long(name, icase=true)
      guard sw is Some(sw) else {
        if ambiguous {
          raise CliError("asciidoctor: ambiguous option: \{arg}")
        }
        raise CliError("asciidoctor: invalid option: \{arg}")
      }
      match apply(opts, sw, arg, attached, queue) {
        Some(command) => return command
        None => ()
      }
    } else if arg.has_prefix("-") && arg.length() > 1 {
      let c = arg[1].to_int().unsafe_to_char()
      let rest = arg[2:].to_owned()
      let sw = match switches.search_by(sw => sw.short == Some(c)) {
        Some(i) => switches[i]
        None => {
          // no such short option: OptionParser completes it as a long one
          let (sw, ambiguous) = find_long(c.to_string(), icase=false)
          guard sw is Some(sw) else {
            if ambiguous {
              raise CliError("asciidoctor: ambiguous option: \{arg}")
            }
            raise CliError("asciidoctor: invalid option: \{arg}")
          }
          sw
        }
      }
      match sw.arg {
        NoArg if rest.has_prefix("=") =>
          raise CliError("asciidoctor: needless argument: \{arg}")
        NoArg => {
          if rest != "" {
            // the rest of the cluster holds more short options
            queue.push("-\{rest}")
          }
          match apply(opts, sw, "-\{c}", None, queue) {
            Some(command) => return command
            None => ()
          }
        }
        _ => {
          let attached = if rest == "" { None } else { Some(rest) }
          let label = if rest == "" { "-\{c}" } else { arg }
          match apply(opts, sw, label, attached, queue) {
            Some(command) => return command
            None => ()
          }
        }
      }
    } else {
      inputs.push(arg)
    }
  }
  if inputs.is_empty() {
    return if opts.verbose == 2 { Version } else { Usage }
  }
  if inputs is ["-"] {
    opts.input_files.push("-")
  } else {
    for file in inputs {
      if file.has_prefix("-") {
        // warn, but don't panic; we may have enough to proceed
        let unparsed = inputs.join("', '")
        opts.notices.push(
          "asciidoctor: WARNING: extra arguments detected (unparsed arguments: '\{unparsed}') or incorrect usage of stdin",
        )
      } else {
        opts.input_files.push(file)
      }
    }
  }
  Convert(opts)
}

///|
/// Applies a switch. `label` is the option as written (with the value when it
/// was attached); a required value that is not attached is taken from the
/// queue. Returns a command when the switch ends the parsing (`-h`, `-V`).
fn apply(
  opts : CliOptions,
  sw : Switch,
  label : String,
  attached : String?,
  queue : Array[String],
) -> CliCommand? raise CliError {
  let value = match sw.arg {
    NoArg => {
      if attached is Some(_) {
        raise CliError("asciidoctor: needless argument: \{label}")
      }
      ""
    }
    Optional =>
      match attached {
        Some(v) => v
        None =>
          match queue.last() {
            Some(next) if !next.has_prefix("-") => queue.unsafe_pop()
            _ => ""
          }
      }
    Required => {
      let (v, shown) = match attached {
        Some(v) => (v, label)
        None =>
          match queue.pop() {
            Some(v) => (v, "\{label} \{v}")
            None =>
              raise CliError("asciidoctor: option missing argument: \{label}")
          }
      }
      if sw.values.is_empty() {
        v
      } else {
        match complete(sw.values, v, icase=false) {
          Match(m) => m
          NoMatch => raise CliError("asciidoctor: invalid argument: \{shown}")
          Ambiguous =>
            raise CliError("asciidoctor: ambiguous argument: \{shown}")
        }
      }
    }
  }
  match sw.long {
    "backend" =>
      if value != "pdf" {
        raise CliError(
          "asciidoctor: invalid argument: \{label} \{value} (only the pdf backend is supported)",
        )
      }
    "doctype" => opts.doctype = Some(value)
    "out-file" => opts.output_file = Some(value)
    "safe" => opts.safe = @core.SAFE_SAFE
    "safe-mode" =>
      opts.safe = @core.safe_mode_value_for_name(value).unwrap_or(
        @core.SAFE_SECURE,
      )
    "section-numbers" => opts.attributes.push(("sectnums", Str("")))
    // a PDF is always standalone and always has its source map; eRuby,
    // template engines, load paths and Ruby warnings only matter to Ruby
    "embedded"
    | "no-header-footer"
    | "sourcemap"
    | "eruby"
    | "template-engine"
    | "load-path"
    | "warnings" => ()
    "attribute" => {
      let attr = value.trim_end(chars=" \t\n\r").to_owned()
      if attr != "" && attr != "=" {
        // `name`, `name=value`; the `!` and `@` suffixes are the API's
        let (name, val) = match attr.find("=") {
          Some(i) => (attr[:i].to_owned(), attr[i + 1:].to_owned())
          None => (attr, "")
        }
        opts.attributes.push((name, Str(val)))
      }
    }
    "template-dir" =>
      raise CliError(
        "asciidoctor: FAILED: custom converter templates (-T) are not supported by asciidoctor-pdf",
      )
    "base-dir" => opts.base_dir = Some(value)
    "source-dir" => opts.source_dir = Some(value)
    "destination-dir" => opts.destination_dir = Some(value)
    "require" => opts.requires.push(value)
    "log-level" => opts.log_level = Some(severity_of(value))
    "failure-level" => opts.failure_level = severity_of(value)
    "quiet" => opts.verbose = 0
    "trace" => opts.trace = true
    "verbose" => opts.verbose = 2
    "timings" => opts.timings = true
    "help" => return Some(Help)
    "version" => return Some(Version)
    "fonts-dir" => opts.fonts_dir = Some(value)
    "icon-fonts-dir" => opts.icon_fonts_dir = Some(value)
    "pdf-theme-json" => opts.pdf_theme_json = Some(value)
    "attributes-json" =>
      opts.attributes_json.push((opts.attributes.length(), value))
    "layout-trace" => opts.layout_trace = Some(value)
    _ => ()
  }
  None
}
