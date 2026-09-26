// The `asciidoctor` command line interface (Ruby `Asciidoctor::Cli`).

///|
let usage : String =
  #|Usage: asciidoctor [OPTION]... FILE...
  #|Convert the AsciiDoc input FILE(s) to the backend output format (e.g., HTML 5, DocBook 5, etc.)
  #|Unless specified otherwise, the output is written to a file whose name is derived from the input file.
  #|Application log messages are printed to STDERR.
  #|
  #|Input options:
  #|    -b, --backend BACKEND            set backend output format: [html5, xhtml5, docbook5, manpage] (default: html5)
  #|    -d, --doctype DOCTYPE            document type to use when converting document: [article, book, manpage, inline] (default: article)
  #|    -e, --embedded                   suppress enclosing document structure and output an embedded document (default: false)
  #|    -o, --out-file FILE              output file (default: based on path of input file); use - to output to STDOUT
  #|        --safe                       set safe mode level to safe (default: unsafe)
  #|    -S, --safe-mode SAFE_MODE        set safe mode level explicitly: [unsafe, safe, server, secure] (default: unsafe)
  #|        --sourcemap                  add source location information to each parsed block (default: false)
  #|    -s, --no-header-footer           suppress enclosing document structure and output an embedded document (default: false)
  #|    -n, --section-numbers            auto-number section titles in the HTML backend; disabled by default
  #|    -a, --attribute name[=value]     a document attribute to set in the form of name, name!, or name=value pair
  #|    -B, --base-dir DIR               base directory containing the document and resources (default: directory of source file)
  #|    -D, --destination-dir DIR        destination output directory (default: directory of source file)
  #|        --log-level LEVEL            set minimum level of log messages that get logged: [DEBUG, INFO, WARN, ERROR, FATAL] (default: WARN)
  #|        --failure-level LEVEL        set minimum log level that yields a non-zero exit code: [INFO, WARN, ERROR, FATAL] (default: FATAL)
  #|    -q, --quiet                      silence application log messages and script warnings (default: false)
  #|    -v, --verbose                    show all application log messages, including DEBUG and INFO levels (default: false)
  #|    -h, --help                       print this help message
  #|    -V, --version                    display the version
  #|

///|
fn parse_level(s : String) -> @core.Severity? {
  match @rb.upcase(s) {
    "DEBUG" => Some(Debug)
    "INFO" => Some(Info)
    "WARN" | "WARNING" => Some(Warn)
    "ERROR" => Some(Error)
    "FATAL" => Some(Fatal)
    _ => None
  }
}

///|
priv struct CliOptions {
  mut backend : String?
  mut doctype : String?
  attributes : Array[(String, @core.AttrVal)]
  mut out_file : String?
  mut safe : Int
  mut standalone : Bool
  mut sourcemap : Bool
  mut base_dir : String?
  mut destination_dir : String?
  mut log_level : @core.Severity
  mut failure_level : @core.Severity
  inputs : Array[String]
}

///|
async fn write_err(s : String) -> Unit {
  @stdio.stderr.write(s)
}

///|
async fn main {
  let args = @env.args()
  let opts : CliOptions = {
    backend: None,
    doctype: None,
    attributes: [],
    out_file: None,
    safe: @core.SAFE_UNSAFE,
    standalone: true,
    sourcemap: false,
    base_dir: None,
    destination_dir: None,
    log_level: Warn,
    failure_level: Fatal,
    inputs: [],
  }
  let mut i = 1
  let next_arg = fn(name : String) -> String raise {
    i += 1
    match args.get(i) {
      Some(v) => v
      None => fail("missing argument: \{name}")
    }
  }
  while i < args.length() {
    let arg = args[i]
    match arg {
      "-h" | "--help" => {
        @stdio.stdout.write(usage)
        return
      }
      "-V" | "--version" => {
        @stdio.stdout.write(
          "Asciidoctor \{@core.VERSION} [https://asciidoctor.org] (MoonBit port)\n",
        )
        return
      }
      "-b" | "--backend" => opts.backend = Some(next_arg(arg))
      "-d" | "--doctype" => opts.doctype = Some(next_arg(arg))
      "-e" | "--embedded" | "-s" | "--no-header-footer" =>
        opts.standalone = false
      "-o" | "--out-file" => opts.out_file = Some(next_arg(arg))
      "--safe" => opts.safe = @core.SAFE_SAFE
      "-S" | "--safe-mode" => {
        let v = next_arg(arg)
        opts.safe = match @core.safe_mode_value_for_name(v) {
          Some(s) => s
          None => fail("invalid safe mode: \{v}")
        }
      }
      "--sourcemap" => opts.sourcemap = true
      "-n" | "--section-numbers" => opts.attributes.push(("sectnums", Str("")))
      "-a" | "--attribute" => {
        let v = next_arg(arg)
        let (name, sep, value) = @rb.partition(v, "=")
        opts.attributes.push(
          (name, if sep == "" { Str("") } else { Str(value) }),
        )
      }
      "-B" | "--base-dir" => opts.base_dir = Some(next_arg(arg))
      "-D" | "--destination-dir" => opts.destination_dir = Some(next_arg(arg))
      "--log-level" =>
        opts.log_level = parse_level(next_arg(arg)).unwrap_or(Warn)
      "--failure-level" =>
        opts.failure_level = parse_level(next_arg(arg)).unwrap_or(Fatal)
      "-q" | "--quiet" => opts.log_level = Unknown
      "-v" | "--verbose" => opts.log_level = Debug
      "-w" | "--warnings" | "-t" | "--timings" | "--trace" => ()
      _ =>
        if arg.has_prefix("-a") && arg.length() > 2 {
          let v = @rb.from(arg, 2)
          let (name, sep, value) = @rb.partition(v, "=")
          opts.attributes.push(
            (name, if sep == "" { Str("") } else { Str(value) }),
          )
        } else if arg.has_prefix("-") && arg != "-" {
          write_err("asciidoctor: invalid option: \{arg}\n")
          @stdio.stderr.write(usage)
          c_exit(1)
        } else {
          opts.inputs.push(arg)
        }
    }
    i += 1
  }
  if opts.inputs.is_empty() {
    @stdio.stderr.write(usage)
    c_exit(1)
  }
  for input in opts.inputs {
    guard input != "-" else { continue }
    if !@fs.exists(input) {
      write_err("asciidoctor: FAILED: input file \{input} is missing\n")
      c_exit(1)
    }
    match @fs.kind(input) {
      Regular | Pipe =>
        if !@fs.can_read(input) {
          write_err(
            "asciidoctor: FAILED: input file \{input} is not readable\n",
          )
          c_exit(1)
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
        write_err(
          "asciidoctor: FAILED: input path \{input} is a \{ftype}, not a file\n",
        )
        c_exit(1)
      }
    }
  }
  let messages : Array[@core.LogMessage] = []
  let logger = @core.Logger::new(m => messages.push(m), level=opts.log_level)
  @core.set_logger(logger) |> ignore
  @core.set_utc_offset(@localtime.utc_offset)
  match @env.get_env_var("SOURCE_DATE_EPOCH") {
    Some(s) => @core.set_source_date_epoch(Some(@rb.to_i(s).to_int64()))
    None => ()
  }
  let flush_messages = async fn() {
    for m in messages {
      @stdio.stderr.write(@core.format_log_message(m) + "\n")
    }
    messages.clear()
  }
  for input in opts.inputs {
    let options = @core.Options::new(
      attributes=opts.attributes.copy(),
      safe=opts.safe,
      backend?=opts.backend,
      doctype?=opts.doctype,
      standalone=opts.standalone,
      base_dir?=opts.base_dir,
      sourcemap=opts.sourcemap,
    )
    if input == "-" {
      let text = @stdio.stdin.read_all().text()
      let output = @io.convert(text, options~)
      match opts.out_file {
        Some(f) if f != "-" =>
          @fs.write_file(f, output, create_mode=CreateOrTruncate)
        _ => @stdio.stdout.write(@rb.chomp(output) + "\n")
      }
    } else {
      let destination : @io.Destination = match opts.out_file {
        Some("-") => Stdout
        Some(f) => File(f)
        None => Default
      }
      @io.convert_file(
        input,
        options~,
        destination~,
        to_dir?=opts.destination_dir,
        mkdirs=opts.destination_dir is Some(_),
      )
      |> ignore
    }
    flush_messages()
  }
  match logger.max_severity {
    Some(s) if s.to_int() >= opts.failure_level.to_int() => c_exit(1)
    _ => ()
  }
}

///|
#cfg(target="native")
extern "C" fn c_exit(code : Int) = "exit"

///|
#cfg(target="wasm")
fn c_exit(code : Int) = "wasi_snapshot_preview1" "proc_exit"
