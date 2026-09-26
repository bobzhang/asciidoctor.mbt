// Option parsing tests, ported from test/options_test.rb plus OptionParser
// behavior checked against Ruby (`--opt=value`, abbreviations, clustered
// short options, error messages). White-box: the CLI is a main package.

///|
fn level_name(level : @core.Severity) -> String {
  match level {
    Debug => "DEBUG"
    Info => "INFO"
    Warn => "WARN"
    Error => "ERROR"
    Fatal => "FATAL"
    Unknown => "UNKNOWN"
  }
}

///|
fn show_list(values : Array[String]) -> String {
  "[\{values.map(v => "\"\{v}\"").join(", ")}]"
}

///|
fn show_pairs(pairs : Array[(String, String)]) -> String {
  "[\{pairs.map(p => "(\"\{p.0}\", \"\{p.1}\")").join(", ")}]"
}

///|
/// Renders the result of `parse_args`: the error message, or the command with
/// the options that differ from the defaults.
fn parse(args : Array[String]) -> String {
  let command = parse_args(args) catch { CliError(msg) => return msg }
  match command {
    Help(topic) => "Help(\{topic.unwrap_or("-")})"
    Version => "Version"
    Usage => "Usage"
    Convert(o) => {
      let d = CliOptions::new()
      let lines = ["Convert"]
      let add = fn(name : String, value : String) {
        lines.push("  \{name}: \{value}")
      }
      if !o.input_files.is_empty() {
        add("input_files", show_list(o.input_files))
      }
      if !o.attributes.is_empty() {
        add("attributes", show_pairs(o.attributes))
      }
      if o.output_file is Some(f) {
        add("output_file", f)
      }
      if o.safe != d.safe {
        add("safe", o.safe.to_string())
      }
      if !o.standalone {
        add("standalone", "false")
      }
      if !o.template_dirs.is_empty() {
        add("template_dirs", show_list(o.template_dirs))
      }
      if o.verbose != d.verbose {
        add("verbose", o.verbose.to_string())
      }
      if !o.load_paths.is_empty() {
        add("load_paths", show_list(o.load_paths))
      }
      if !o.requires.is_empty() {
        add("requires", show_list(o.requires))
      }
      if o.base_dir is Some(v) {
        add("base_dir", v)
      }
      if o.source_dir is Some(v) {
        add("source_dir", v)
      }
      if o.destination_dir is Some(v) {
        add("destination_dir", v)
      }
      if o.log_level is Some(l) {
        add("log_level", level_name(l))
      }
      if o.failure_level != d.failure_level {
        add("failure_level", level_name(o.failure_level))
      }
      if o.sourcemap {
        add("sourcemap", "true")
      }
      if o.trace {
        add("trace", "true")
      }
      if o.timings {
        add("timings", "true")
      }
      for n in o.notices {
        add("notice", n)
      }
      lines.join("\n")
    }
  }
}

///|
test "help and version" {
  inspect(
    parse(["-h"]),
    content=(
      #|Help(-)
    ),
  )
  inspect(
    parse(["--help"]),
    content=(
      #|Help(-)
    ),
  )
  inspect(
    parse(["-h", "unknown"]),
    content=(
      #|Help(unknown)
    ),
  )
  inspect(
    parse(["-hsyntax"]),
    content=(
      #|Help(syntax)
    ),
  )
  inspect(
    parse(["--help=manpage"]),
    content=(
      #|Help(manpage)
    ),
  )
  // an option does not become the topic
  inspect(
    parse(["-h", "-e"]),
    content=(
      #|Help(-)
    ),
  )
  // -h and -V end the parsing
  inspect(
    parse(["-h", "--bogus"]),
    content=(
      #|Help(-)
    ),
  )
  inspect(
    parse(["-sh"]),
    content=(
      #|Help(-)
    ),
  )
  inspect(parse(["-V"]), content="Version")
  inspect(parse(["--version", "doc.adoc"]), content="Version")
  inspect(parse(["--vers"]), content="Version")
  // -v without input files prints the version
  inspect(parse(["-v"]), content="Version")
  inspect(parse(["-q", "--verbose", "-v"]), content="Version")
  inspect(parse(["-vq"]), content="Usage")
  inspect(parse([]), content="Usage")
  inspect(parse(["-e"]), content="Usage")
}

///|
test "usage shows safe modes in severity order" {
  inspect(usage.has_prefix("Usage:"), content="true")
  inspect(usage.contains("unsafe, safe, server, secure"), content="true")
}

///|
test "version line names the MoonBit port" {
  inspect(
    version_text().has_prefix(
      "Asciidoctor \{@core.VERSION} [https://asciidoctor.org]\nRuntime Environment (MoonBit port, ",
    ),
    content="true",
  )
}

///|
test "invalid options" {
  inspect(parse(["--foobar"]), content="asciidoctor: invalid option: --foobar")
  inspect(
    parse(["--foobar=1", "x"]),
    content="asciidoctor: invalid option: --foobar=1",
  )
  inspect(parse(["-Z"]), content="asciidoctor: invalid option: -Z")
  inspect(parse(["-x=1"]), content="asciidoctor: invalid option: -x=1")
  // the rest of a cluster is reported
  inspect(parse(["-sx"]), content="asciidoctor: invalid option: -x")
  inspect(
    parse(["--no-embedded", "x"]),
    content="asciidoctor: invalid option: --no-embedded",
  )
  // Ruby crashes with an uncaught OptionParser error for these
  inspect(parse(["--s", "x"]), content="asciidoctor: ambiguous option: --s")
  inspect(parse(["-l", "x"]), content="asciidoctor: ambiguous option: -l")
  inspect(
    parse(["--safe=1", "x"]),
    content="asciidoctor: needless argument: --safe=1",
  )
  inspect(parse(["-e=1", "x"]), content="asciidoctor: needless argument: -e=1")
}

///|
test "missing arguments" {
  inspect(parse(["-b"]), content="asciidoctor: option missing argument: -b")
  inspect(
    parse(["--backend"]),
    content="asciidoctor: option missing argument: --backend",
  )
  inspect(
    parse(["--back"]),
    content="asciidoctor: option missing argument: --back",
  )
  inspect(
    parse(["-b", "html5", "--log-level"]),
    content="asciidoctor: option missing argument: --log-level",
  )
  inspect(parse(["-sb"]), content="asciidoctor: option missing argument: -b")
}

///|
test "invalid arguments" {
  inspect(
    parse(["-d", "chapter", "input.ad"]),
    content="asciidoctor: invalid argument: -d chapter",
  )
  inspect(
    parse(["--doctype=nope", "x"]),
    content="asciidoctor: invalid argument: --doctype=nope",
  )
  inspect(
    parse(["--doc", "nope", "x"]),
    content="asciidoctor: invalid argument: --doc nope",
  )
  inspect(
    parse(["-d=book", "x"]),
    content="asciidoctor: invalid argument: -d=book",
  )
  inspect(
    parse(["-S", "Safe", "x"]),
    content="asciidoctor: invalid argument: -S Safe",
  )
  inspect(
    parse(["-S", "s", "x"]),
    content="asciidoctor: ambiguous argument: -S s",
  )
  inspect(
    parse(["--safe-mode=", "x"]),
    content="asciidoctor: ambiguous argument: --safe-mode=",
  )
  inspect(
    parse(["--log-level", "nope", "x"]),
    content="asciidoctor: invalid argument: --log-level nope",
  )
  inspect(
    parse(["--failure-level=foobar", "x"]),
    content="asciidoctor: invalid argument: --failure-level=foobar",
  )
  inspect(
    parse(["--failure-level", "debug", "x"]),
    content="asciidoctor: invalid argument: --failure-level debug",
  )
  inspect(
    parse(["--eruby", "nope", "x"]),
    content="asciidoctor: invalid argument: --eruby nope",
  )
}

///|
test "basic argument assignment" {
  inspect(
    parse(["-w", "-v", "-e", "-d", "book", "test/fixtures/sample.adoc"]),
    content=(
      #|Convert
      #|  input_files: ["test/fixtures/sample.adoc"]
      #|  attributes: [("doctype", "book")]
      #|  standalone: false
      #|  verbose: 2
    ),
  )
  inspect(
    parse(["-s", "sample.adoc"]),
    content=(
      #|Convert
      #|  input_files: ["sample.adoc"]
      #|  standalone: false
    ),
  )
}

///|
test "long options with values" {
  inspect(
    parse([
      "--backend=docbook5", "--doctype=book", "--attribute=x=y", "--out-file=x",
      "--safe-mode=safe", "--destination-dir=d", "--base-dir=b", "--source-dir=s",
      "doc.adoc",
    ]),
    content=(
      #|Convert
      #|  input_files: ["doc.adoc"]
      #|  attributes: [("backend", "docbook5"), ("doctype", "book"), ("x", "y")]
      #|  output_file: x
      #|  safe: 1
      #|  base_dir: b
      #|  source_dir: s
      #|  destination_dir: d
    ),
  )
  // separate values, abbreviations, case-insensitive names, `_` for `-`
  inspect(
    parse([
      "--back", "html5", "--B_D", "b", "--sa", "--tim", "--sourcemap", "--trace",
      "doc.adoc",
    ]),
    content=(
      #|Convert
      #|  input_files: ["doc.adoc"]
      #|  attributes: [("backend", "html5")]
      #|  safe: 1
      #|  base_dir: b
      #|  sourcemap: true
      #|  trace: true
      #|  timings: true
    ),
  )
}

///|
test "short options: clusters and attached values" {
  inspect(
    parse(["-sn", "-bdocbook5", "-ahello=world", "-o-", "doc.adoc"]),
    content=(
      #|Convert
      #|  input_files: ["doc.adoc"]
      #|  attributes: [("sectnums", ""), ("backend", "docbook5"), ("hello", "world")]
      #|  output_file: -
      #|  standalone: false
    ),
  )
  // an attached short value keeps a leading `=`, like Ruby
  inspect(
    parse(["-b=docbook5", "doc.adoc"]),
    content=(
      #|Convert
      #|  input_files: ["doc.adoc"]
      #|  attributes: [("backend", "=docbook5")]
    ),
  )
  // a letter that is not a short option completes a long option
  inspect(
    parse(["-fwarn", "-f", "ERR", "doc.adoc"]),
    content=(
      #|Convert
      #|  input_files: ["doc.adoc"]
      #|  failure_level: ERROR
    ),
  )
}

///|
test "options may follow the input files; -- ends the options" {
  inspect(
    parse(["doc.adoc", "-o", "-", "--", "-weird.adoc", "other.adoc"]),
    content=(
      #|Convert
      #|  input_files: ["doc.adoc", "other.adoc"]
      #|  output_file: -
      #|  notice: asciidoctor: WARNING: extra arguments detected (unparsed arguments: 'doc.adoc', '-weird.adoc', 'other.adoc') or incorrect usage of stdin
    ),
  )
  // a required value may start with a dash
  inspect(
    parse(["-o", "-", "-"]),
    content=(
      #|Convert
      #|  input_files: ["-"]
      #|  output_file: -
    ),
  )
}

///|
test "should emit warning when unparsed options remain" {
  inspect(
    parse(["-b", "docbook", "-", "-"]),
    content=(
      #|Convert
      #|  attributes: [("backend", "docbook")]
      #|  notice: asciidoctor: WARNING: extra arguments detected (unparsed arguments: '-', '-') or incorrect usage of stdin
      #|  notice: asciidoctor: WARNING: extra arguments detected (unparsed arguments: '-', '-') or incorrect usage of stdin
    ),
  )
}

///|
test "attribute assignment" {
  inspect(
    parse([
      "-a", "docinfosubs=attributes,replacements", "-a", "icons", "-a", "name=value=value",
      "-a", "icons=font", "-a", "", "-a", "=", "-a", "trail  ", "sample.adoc",
    ]),
    content=(
      #|Convert
      #|  input_files: ["sample.adoc"]
      #|  attributes: [("docinfosubs", "attributes,replacements"), ("icons", "font"), ("name", "value=value"), ("trail", "")]
    ),
  )
  inspect(
    parse(["-a", "platform-name=云平台", "-"]),
    content=(
      #|Convert
      #|  input_files: ["-"]
      #|  attributes: [("platform-name", "云平台")]
    ),
  )
  // -b, -d and -n are attributes too; the last value wins
  inspect(
    parse(["-b", "html5", "-a", "backend=docbook5", "-n", "-d", "inline", "x"]),
    content=(
      #|Convert
      #|  input_files: ["x"]
      #|  attributes: [("backend", "docbook5"), ("sectnums", ""), ("doctype", "inline")]
    ),
  )
}

///|
test "safe mode, doctype and backend" {
  inspect(
    parse(["-S", "safe", "x"]),
    content=(
      #|Convert
      #|  input_files: ["x"]
      #|  safe: 1
    ),
  )
  inspect(
    parse(["-S", "sec", "x"]),
    content=(
      #|Convert
      #|  input_files: ["x"]
      #|  safe: 20
    ),
  )
  inspect(
    parse(["-d", "boo", "-b", "my_custom_backend", "x"]),
    content=(
      #|Convert
      #|  input_files: ["x"]
      #|  attributes: [("doctype", "book"), ("backend", "my_custom_backend")]
    ),
  )
}

///|
test "templates, requires and load paths" {
  inspect(
    parse([
      "-T", "custom-backend", "-T", "custom-backend-hacks", "-E", "haml", "-r", "foobar",
      "-r", "/no-such-folder/a,b,c/ext.rb", "-I", "foobar:foobaz", "--eruby", "erubi",
      "x",
    ]),
    content=(
      #|Convert
      #|  input_files: ["x"]
      #|  template_dirs: ["custom-backend", "custom-backend-hacks"]
      #|  load_paths: ["foobar", "foobaz"]
      #|  requires: ["foobar", "/no-such-folder/a,b,c/ext.rb"]
    ),
  )
}

///|
test "log and failure levels" {
  inspect(
    parse(["--log-level", "debug", "x"]),
    content=(
      #|Convert
      #|  input_files: ["x"]
      #|  log_level: DEBUG
    ),
  )
  let levels = []
  for
    value in [
      "f", "fatal", "FATAL", "e", "err", "ERR", "error", "ERROR", "w", "warn", "WARN",
      "warning", "WARNING", "i", "INFO",
    ] {
    let command = parse_args(["--failure-level=\{value}", "x"])
    guard command is Convert(o) else { fail("unexpected \{value}") }
    levels.push("\{value}=\{level_name(o.failure_level)}")
  }
  inspect(
    levels.join(" "),
    content="f=FATAL fatal=FATAL FATAL=FATAL e=ERROR err=ERROR ERR=ERROR error=ERROR ERROR=ERROR w=WARN warn=WARN WARN=WARN warning=WARN WARNING=WARN i=INFO INFO=INFO",
  )
}

///|
test "verbosity" {
  inspect(
    parse(["-q", "x"]),
    content=(
      #|Convert
      #|  input_files: ["x"]
      #|  verbose: 0
    ),
  )
  inspect(
    parse(["-q", "-v", "x"]),
    content=(
      #|Convert
      #|  input_files: ["x"]
      #|  verbose: 2
    ),
  )
  inspect(
    parse(["-v", "-q", "x"]),
    content=(
      #|Convert
      #|  input_files: ["x"]
      #|  verbose: 0
    ),
  )
}

///|
test "error messages of the invoker" {
  inspect(
    error_message(@core.MissingConverter("nope")),
    content="asciidoctor: FAILED: missing converter for backend 'nope'. Processing aborted.",
  )
  inspect(
    error_message(
      @core.ConversionFailed(
        "asciidoctor: ERROR: doctype must be set to manpage when using manpage backend",
      ),
    ),
    content="asciidoctor: ERROR: doctype must be set to manpage when using manpage backend (RuntimeError)",
  )
  // other errors (`@io.IOError`, `@core.SecurityError`) print their message;
  // scripts/cli_parity.mbtx compares them with Ruby
}
