// The `asciidoctor` command line interface (Ruby `Asciidoctor::Cli`): option
// parsing is in options.mbt, the conversion driver in convert.mbt; this file
// is the invoker (Ruby `Cli::Invoker`).

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
    Help(topic) => help(topic)
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
/// `-h TOPIC`: the man page and the syntax overview are not bundled with the
/// port, so those topics fail like Ruby does when the files are missing.
async fn help(topic : String?) -> Int {
  match topic {
    Some("manpage") =>
      match @env.get_env_var("ASCIIDOCTOR_MANPAGE_PATH") {
        Some(path) if !path.has_suffix(".gz") && @fs.exists(path) => {
          @stdio.stdout.write(@rb.chomp(@fs.read_file(path).text()) + "\n")
          0
        }
        Some(path) => {
          write_err("asciidoctor: FAILED: manual page not found: \{path}\n")
          1
        }
        None => {
          write_err(
            "asciidoctor: FAILED: manual page not found; try `man asciidoctor`\n",
          )
          1
        }
      }
    Some("syntax") => {
      write_err(
        "asciidoctor: FAILED: syntax page not found; visit https://asciidoctor.org/docs\n",
      )
      1
    }
    _ => {
      @stdio.stdout.write(usage)
      0
    }
  }
}

///|
/// Checks the input files and the options the port cannot honor (Ruby
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
  if !opts.template_dirs.is_empty() {
    // Ruby: the tilt gem is required; the port has no template support
    return Some(
      "asciidoctor: FAILED: 'tilt' could not be loaded\n  Custom converter templates are not supported by the MoonBit port\n\{trace_hint}",
    )
  }
  // Ruby libraries (-r) cannot be loaded by the port
  match opts.requires.get(0) {
    Some(path) =>
      Some("asciidoctor: FAILED: '\{path}' could not be loaded\n\{trace_hint}")
    None => None
  }
}

///|
/// The message Ruby's invoker prints for an error that aborted the run.
fn error_message(e : Error) -> String {
  match e {
    // Ruby RuntimeErrors are printed with their class
    @core.ConversionFailed(msg) => "\{msg} (RuntimeError)"
    @core.SecurityError(msg) => msg
    e => e.to_string()
  }
}

///|
/// Converts the input files (Ruby `Invoker#invoke!`) and returns the exit code.
async fn invoke(opts : CliOptions) -> Int {
  let infiles = opts.input_files
  let mut outfile = opts.output_file
  let mut stdin = false
  if infiles.length() == 1 {
    if infiles[0] == "-" {
      outfile = Some(outfile.unwrap_or("-"))
      stdin = true
    } else if (@fs.kind(infiles[0]) catch { _ => Regular }) is Pipe {
      outfile = Some(outfile.unwrap_or("-"))
    }
  }
  // every file output creates the missing directories
  let (to_file, mkdirs) : (ToFile, Bool) = match outfile {
    Some("-") => (Stream, false)
    Some(f) => (Path(f), true)
    None => (Derived, true)
  }
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
  @core.set_utc_offset(@localtime.utc_offset)
  match @env.get_env_var("SOURCE_DATE_EPOCH") {
    Some(s) => @core.set_source_date_epoch(Some(@rb.to_i(s).to_int64()))
    None => ()
  }
  let flush_messages = async fn() {
    for m in messages {
      write_err(@core.format_log_message(m) + "\n")
    }
    messages.clear()
  }
  let new_options = fn() {
    @core.Options::new(
      attributes=opts.attributes.map(a => (a.0, @core.AttrVal::Str(a.1))),
      safe=opts.safe,
      standalone=opts.standalone,
      base_dir?=opts.base_dir,
      sourcemap=opts.sourcemap,
      timings?=if opts.timings {
        Some(@core.Timings::new(monotonic_seconds))
      } else {
        None
      },
    )
  }
  let cwd = @env.current_dir().unwrap_or("/")
  let abs_srcdir = opts.source_dir.map(d => @core.expand_path_from(cwd, d))
  let convert_one = async fn(input : CliInput, subject : String) {
    let options = new_options()
    let mut to_dir = opts.destination_dir
    match (input, abs_srcdir, to_dir) {
      (InputFile(path), Some(srcdir), Some(d)) => {
        let abs_indir = @core.dirname(@core.expand_path_from(cwd, path))
        if abs_indir.has_prefix(srcdir + "/") {
          to_dir = Some(d + @rb.from(abs_indir, srcdir.length()))
        }
      }
      _ => ()
    }
    convert_input(input, options, to_file~, to_dir~, mkdirs~)
    flush_messages()
    if options.timings is Some(t) {
      write_err(t.report(subject~))
    }
  }
  try {
    if stdin {
      let text = @stdio.stdin.read_all().text()
      convert_one(Stdin(text), "-")
    } else {
      for infile in infiles {
        convert_one(InputFile(infile), infile)
      }
    }
  } catch {
    e => {
      flush_messages()
      write_err(error_message(e) + "\n")
      if !opts.trace {
        write_err("  Use --trace to show backtrace\n")
      }
      return 1
    }
  }
  match logger.max_severity {
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
