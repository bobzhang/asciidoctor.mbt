///|
/// A summary of what a command line asks for.
fn parsed(args : Array[String]) -> String {
  let command = parse_args(args) catch {
    CliError(msg) => return "error: \{msg}"
  }
  match command {
    Help => "help"
    Version => "version"
    Usage => "usage"
    Convert(opts) => {
      let parts = ["inputs=\{opts.input_files.join(",")}"]
      if opts.output_file is Some(o) {
        parts.push("out=\{o}")
      }
      if opts.destination_dir is Some(d) {
        parts.push("dir=\{d}")
      }
      if opts.base_dir is Some(d) {
        parts.push("base=\{d}")
      }
      if opts.doctype is Some(d) {
        parts.push("doctype=\{d}")
      }
      if opts.safe != @core.SAFE_UNSAFE {
        parts.push("safe=\{opts.safe}")
      }
      if opts.verbose != 1 {
        parts.push("verbose=\{opts.verbose}")
      }
      for attr in opts.attributes {
        let value = match attr.1 {
          Str(s) => s
          _ => "?"
        }
        parts.push("-a \{attr.0}=\{value}")
      }
      for library in opts.requires {
        parts.push("-r \{library}")
      }
      for notice in opts.notices {
        parts.push(notice)
      }
      parts.join(" ")
    }
  }
}

///|
test "commands" {
  inspect(parsed([]), content="usage")
  inspect(parsed(["-h"]), content="help")
  inspect(parsed(["--help"]), content="help")
  inspect(parsed(["-V"]), content="version")
  inspect(parsed(["--version"]), content="version")
  // `-v` alone is the version, as in Ruby
  inspect(parsed(["-v"]), content="version")
  inspect(parsed(["-v", "doc.adoc"]), content="inputs=doc.adoc verbose=2")
}

///|
test "conversion options" {
  inspect(
    parsed(["-o", "out.pdf", "-D", "build", "-B", "base", "doc.adoc"]),
    content="inputs=doc.adoc out=out.pdf dir=build base=base",
  )
  inspect(parsed(["-o", "-", "-"]), content="inputs=- out=-")
  // abbreviated long options, `--name=value`, clustered short options and
  // attached values
  inspect(
    parsed(["--out=a.pdf", "--doc", "book", "-qn", "-Ssafe", "x.adoc"]),
    content="inputs=x.adoc out=a.pdf doctype=book safe=1 verbose=0 -a sectnums=",
  )
  inspect(
    parsed(["-a", "toc", "-a", "title=A Title", "-a", "icons=font@", "x.adoc"]),
    content="inputs=x.adoc -a toc= -a title=A Title -a icons=font@",
  )
  inspect(
    parsed(["-r", "asciidoctor-pdf", "x.adoc"]),
    content="inputs=x.adoc -r asciidoctor-pdf",
  )
  inspect(
    parsed(["x.adoc", "-"]),
    content="inputs=x.adoc asciidoctor: WARNING: extra arguments detected (unparsed arguments: 'x.adoc', '-') or incorrect usage of stdin",
  )
}

///|
test "--theme is -a pdf-theme" {
  inspect(
    parsed(["--theme", "default-sans", "x.adoc"]),
    content="inputs=x.adoc -a pdf-theme=default-sans",
  )
  inspect(
    parsed(["--theme=my-theme.yml", "x.adoc"]),
    content="inputs=x.adoc -a pdf-theme=my-theme.yml",
  )
}

///|
test "invalid command lines" {
  inspect(
    parsed(["--bogus"]),
    content="error: asciidoctor: invalid option: --bogus",
  )
  inspect(
    parsed(["-o"]),
    content="error: asciidoctor: option missing argument: -o",
  )
  inspect(
    parsed(["-d", "bogus", "x.adoc"]),
    content="error: asciidoctor: invalid argument: -d bogus",
  )
  inspect(
    parsed(["-b", "html5", "x.adoc"]),
    content="error: asciidoctor: invalid argument: -b html5 (only the pdf backend is supported)",
  )
  inspect(
    parsed(["--t", "x.adoc"]),
    content="error: asciidoctor: ambiguous option: --t",
  )
}

///|
test "output targets" {
  let target = (args : Array[String], input : String?) => {
    guard parse_args(args) is Convert(opts) else { return "?" }
    output_target(opts, "/work", input).unwrap_or("(stdout)")
  }
  inspect(target(["d/x.adoc"], Some("/work/d/x.adoc")), content="/work/d/x.pdf")
  inspect(
    target(["-o", "out.pdf", "x.adoc"], Some("/work/x.adoc")),
    content="/work/out.pdf",
  )
  inspect(
    target(["-o", "-", "x.adoc"], Some("/work/x.adoc")),
    content="(stdout)",
  )
  inspect(target(["-"], None), content="(stdout)")
  inspect(target(["-o", "o.pdf", "-"], None), content="/work/o.pdf")
  inspect(
    target(["-D", "build", "d/x.adoc"], Some("/work/d/x.adoc")),
    content="/work/build/x.pdf",
  )
  inspect(
    target(["-D", "build", "-o", "o.pdf", "x.adoc"], Some("/work/x.adoc")),
    content="/work/build/o.pdf",
  )
  // relative to the base directory
  inspect(
    target(["-B", "/base", "-o", "o.pdf", "x.adoc"], Some("/work/x.adoc")),
    content="/base/o.pdf",
  )
  // the input's directory below the source root is kept
  inspect(
    target(
      ["-R", "src", "-D", "out", "src/a/x.adoc"],
      Some("/work/src/a/x.adoc"),
    ),
    content="/work/out/a/x.pdf",
  )
}
