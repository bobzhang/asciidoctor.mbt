// Command line option parsing (Ruby `Asciidoctor::Cli::Options`, built on
// Ruby's OptionParser). `parse_args` is pure: it does not touch the file
// system or the streams; `main` checks the input files and runs the command.

///|
let usage : String =
  #|Usage: asciidoctor [OPTION]... FILE...
  #|Convert the AsciiDoc input FILE(s) to the backend output format (e.g., HTML 5, DocBook 5, etc.)
  #|Unless specified otherwise, the output is written to a file whose name is derived from the input file.
  #|Application log messages are printed to STDERR.
  #|Example: asciidoctor input.adoc
  #|
  #|    -b, --backend BACKEND            set backend output format: [html5, xhtml5, docbook5, manpage] (default: html5)
  #|                                     additional backends are supported via extended converters (e.g., pdf, epub3)
  #|    -d, --doctype DOCTYPE            document type to use when converting document: [article, book, manpage, inline] (default: article)
  #|    -e, --embedded                   suppress enclosing document structure and output an embedded document (default: false)
  #|    -o, --out-file FILE              output file (default: based on path of input file); use - to output to STDOUT
  #|        --safe                       set safe mode level to safe (default: unsafe)
  #|                                     enables include directives, but prevents access to ancestor paths of source file
  #|                                     provided for compatibility with the asciidoc command
  #|    -S, --safe-mode SAFE_MODE        set safe mode level explicitly: [unsafe, safe, server, secure] (default: unsafe)
  #|                                     disables potentially dangerous macros in source files, such as include::[]
  #|        --sourcemap                  add source location information to each parsed block (default: false)
  #|    -s, --no-header-footer           suppress enclosing document structure and output an embedded document (default: false)
  #|    -n, --section-numbers            auto-number section titles in the HTML backend; disabled by default
  #|        --eruby ERUBY                specify eRuby implementation to use when rendering custom ERB templates: [erb, erubi, erubis] (default: erb)
  #|    -a, --attribute name[=value]     a document attribute to set in the form of name, name!, or name=value pair
  #|                                     that takes precedence over the same attribute defined in the source document
  #|                                     unless either the name or value ends in @ (i.e., name@=value or name=value@)
  #|                                     may be specified more than once
  #|    -T, --template-dir DIR           a directory containing custom converter templates that override the built-in converter (requires tilt gem)
  #|                                     may be specified more than once
  #|    -E, --template-engine NAME       template engine to use for the custom converter templates (loads gem on demand)
  #|    -B, --base-dir DIR               base directory containing the document and resources (default: directory of source file)
  #|    -R, --source-dir DIR             source root directory (used for calculating path in destination directory)
  #|    -D, --destination-dir DIR        destination output directory (default: directory of source file)
  #|    -I, --load-path DIRECTORY        add a directory to the $LOAD_PATH
  #|                                     may be specified more than once
  #|    -r, --require LIBRARY            require the specified library before executing the processor (using require)
  #|                                     may be specified more than once
  #|        --log-level LEVEL            set minimum level of log messages that get logged: [DEBUG, INFO, WARN, ERROR, FATAL] (default: WARN)
  #|        --failure-level LEVEL        set minimum log level that yields a non-zero exit code: [INFO, WARN, ERROR, FATAL] (default: FATAL)
  #|    -q, --quiet                      silence application log messages and script warnings (default: false)
  #|        --trace                      include backtrace information when reporting errors (default: false)
  #|    -v, --verbose                    show all application log messages, including DEBUG and INFO levels (default: false)
  #|    -w, --warnings                   turn on script warnings (default: false)
  #|    -t, --timings                    print timings report (default: false)
  #|    -h, --help [TOPIC]               print a help message
  #|                                     show this usage if TOPIC is not specified or recognized
  #|                                     show an overview of the AsciiDoc syntax if TOPIC is syntax
  #|                                     dump the Asciidoctor man page (in troff/groff format) if TOPIC is manpage
  #|    -V, --version                    display the version and runtime environment (or -v if no other flags or arguments)
  #|

///|
/// The version report (Ruby `Options#print_version`), naming this port as the
/// runtime environment.
fn version_text() -> String {
  "Asciidoctor \{@core.VERSION} [https://asciidoctor.org]\nRuntime Environment (MoonBit port, \{target_name()}) (lc:UTF-8 fs:UTF-8 in:UTF-8 ex:UTF-8)\n"
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
/// The options of a conversion run (Ruby `Cli::Options` hash).
priv struct CliOptions {
  /// Document attributes in insertion order (a Ruby Hash: a repeated name
  /// keeps its first position and takes the last value). `-b` and `-d` are
  /// stored here as `backend` and `doctype`, like Ruby.
  attributes : Array[(String, String)]
  input_files : Array[String]
  mut output_file : String?
  mut safe : Int
  mut standalone : Bool
  template_dirs : Array[String]
  /// 0 (`-q`), 1 (default) or 2 (`-v`)
  mut verbose : Int
  load_paths : Array[String]
  requires : Array[String]
  mut base_dir : String?
  mut source_dir : String?
  mut destination_dir : String?
  mut log_level : @core.Severity?
  mut failure_level : @core.Severity
  mut sourcemap : Bool
  mut trace : Bool
  mut timings : Bool
  /// Warnings to print on stderr before converting.
  notices : Array[String]
}

///|
fn CliOptions::new() -> CliOptions {
  {
    attributes: [],
    input_files: [],
    output_file: None,
    safe: @core.SAFE_UNSAFE,
    standalone: true,
    template_dirs: [],
    verbose: 1,
    load_paths: [],
    requires: [],
    base_dir: None,
    source_dir: None,
    destination_dir: None,
    log_level: None,
    failure_level: Fatal,
    sourcemap: false,
    trace: false,
    timings: false,
    notices: [],
  }
}

///|
fn CliOptions::set_attribute(
  self : CliOptions,
  name : String,
  value : String,
) -> Unit {
  match self.attributes.search_by(entry => entry.0 == name) {
    Some(i) => self.attributes[i] = (name, value)
    None => self.attributes.push((name, value))
  }
}

///|
/// What the command line asks for.
priv enum CliCommand {
  /// Convert the input files (`-` is standard input).
  Convert(CliOptions)
  /// `-h [TOPIC]`: print the usage (or the topic) on stdout.
  Help(String?)
  /// `-V`, or `-v` without input files: print the version on stdout.
  Version
  /// No input files: print the usage on stderr and fail.
  Usage
}

///|
/// An invalid command line. The message is the line Ruby prints on stderr
/// (followed by the usage on stdout).
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
  /// The accepted values of an enumerated argument (empty: any value).
  values : Array[String]
}

///|
let log_levels : Array[String] = [
  "debug", "DEBUG", "info", "INFO", "warning", "WARNING", "error", "ERROR", "fatal",
  "FATAL",
]

///|
/// The switches in Ruby's definition order.
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
]

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
  let fold = fn(s : String) { if icase { @rb.downcase(s) } else { s } }
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
  match @rb.upcase(level) {
    "DEBUG" => Debug
    "INFO" => Info
    "WARNING" => Warn
    "ERROR" => Error
    _ => Fatal
  }
}

///|
/// Parses the command line arguments (without the program name), like Ruby's
/// `Cli::Options.parse!`: options may follow the input files, long options may
/// be abbreviated and written `--name=value`, short options may be clustered
/// (`-sn`) or take an attached value (`-bdocbook5`), and `--` ends the options.
/// Input files are not checked here.
fn parse_args(args : Array[String]) -> CliCommand raise CliError {
  let opts = CliOptions::new()
  let inputs = []
  // pending arguments, processed front to back (short clusters are pushed back)
  let queue = args.rev()
  while queue.pop() is Some(arg) {
    if arg == "--" {
      while queue.pop() is Some(a) {
        inputs.push(a)
      }
      break
    }
    if arg.has_prefix("--") {
      let (name0, eq, value) = @rb.partition(@rb.from(arg, 2), "=")
      let name = name0.replace_all(old="_", new="-")
      let (sw, ambiguous) = find_long(name, icase=true)
      guard sw is Some(sw) else {
        if ambiguous {
          raise CliError("asciidoctor: ambiguous option: \{arg}")
        }
        raise CliError("asciidoctor: invalid option: \{arg}")
      }
      let attached = if eq == "" { None } else { Some(value) }
      match apply(opts, sw, arg, attached, queue) {
        Some(command) => return command
        None => ()
      }
    } else if arg.has_prefix("-") && arg.length() > 1 {
      let c = arg[1].to_int().unsafe_to_char()
      let rest = @rb.from(arg, 2)
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
    "backend" => opts.set_attribute("backend", value)
    "doctype" => opts.set_attribute("doctype", value)
    "embedded" | "no-header-footer" => opts.standalone = false
    "out-file" => opts.output_file = Some(value)
    "safe" => opts.safe = @core.SAFE_SAFE
    "safe-mode" =>
      opts.safe = @core.safe_mode_value_for_name(value).unwrap_or(
        @core.SAFE_SECURE,
      )
    "sourcemap" => opts.sourcemap = true
    "section-numbers" => opts.set_attribute("sectnums", "")
    // eRuby, template engines and Ruby warnings only matter to Ruby
    "eruby" | "template-engine" | "warnings" => ()
    "attribute" => {
      let attr = @rb.rstrip(value)
      if attr != "" && attr != "=" {
        let (name, _, val) = @rb.partition(attr, "=")
        opts.set_attribute(name, val)
      }
    }
    "template-dir" => opts.template_dirs.push(value)
    "base-dir" => opts.base_dir = Some(value)
    "source-dir" => opts.source_dir = Some(value)
    "destination-dir" => opts.destination_dir = Some(value)
    "load-path" => opts.load_paths.push_iter(@rb.split(value, ":").iter())
    "require" => opts.requires.push(value)
    "log-level" => opts.log_level = Some(severity_of(value))
    "failure-level" => opts.failure_level = severity_of(value)
    "quiet" => opts.verbose = 0
    "trace" => opts.trace = true
    "verbose" => opts.verbose = 2
    "timings" => opts.timings = true
    "help" => return Some(Help(if value == "" { None } else { Some(value) }))
    "version" => return Some(Version)
    _ => ()
  }
  None
}
