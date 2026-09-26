// The conversion driver (Ruby lib/asciidoctor/convert.rb and
// `Document#write`): loads a file or a string, converts it inside the
// fixpoint of `run_with_files`, and writes the output next to the input, to
// an explicit file or directory, or to standard output.

///|
/// The input of a conversion.
pub(all) enum Source {
  /// A file (Ruby `Asciidoctor.convert_file`), relative to the working
  /// directory. Its location sets `docfile`, `docdir`, `docname` and
  /// `docfilesuffix`, overriding attributes of the same name in the options.
  Path(String)
  /// AsciiDoc text, e.g. read from standard input (Ruby `Asciidoctor.convert`
  /// with a string or an IO).
  Text(String)
}

///|
/// Where the output is written.
pub(all) enum Destination {
  /// Next to the input file (Ruby `to_file: nil`), or in `to_dir` if given,
  /// named after the document (`docname` + `outfilesuffix`). A `Text` source
  /// is only written when `to_dir` is given.
  Default
  /// A specific file (Ruby `to_file: path`), resolved against `to_dir` if
  /// given. `File("/dev/null")` only loads the document.
  File(String)
  /// Standard output (Ruby `to_file: $stdout`).
  Stdout
  /// Do not write; return the output (Ruby `to_file: false`).
  NoWrite
}

///|
/// The result of `convert_source`.
pub struct Conversion {
  /// The converted (or, for `File("/dev/null")`, only loaded) document.
  document : @core.Node
  /// The output; empty if the document was only loaded.
  output : String
  /// The file the output was written to, if any.
  outfile : String?
}

///|
fn file_join(dir : String, name : String) -> String {
  if dir.has_suffix("/") {
    dir + name
  } else {
    dir + "/" + name
  }
}

///|
/// The output file name Ruby derives from the document.
fn output_name(doc : @core.Node) -> String {
  "\{doc.attributes.str("docname").unwrap_or("")}\{doc.outfilesuffix()}"
}

///|
/// Raises the error that aborted the processing of `doc` (where Ruby raises
/// from `load` or `convert`).
fn raise_processing_error(doc : @core.Node) -> Unit raise {
  match doc.processing_error() {
    Some(e) => raise e
    None => ()
  }
}

///|
/// Resolves the output file and directory of an explicit target (Ruby
/// `Asciidoctor.convert`, `write_to_target` branch). In safe mode (safe >=
/// SAFE) the target must stay inside `working_dir`.
fn resolve_target(
  doc : @core.Node,
  working_dir : String,
  to_dir : String?,
  to_file : String?,
) -> (String, String) raise @core.SecurityError {
  let jail = if doc.safe() >= @core.SAFE_SAFE {
    Some(working_dir)
  } else {
    None
  }
  match to_dir {
    Some(d) => {
      let outdir = doc.normalize_system_path_checked(
        d,
        start=working_dir,
        jail?,
        target_name="to_dir",
        recover=false,
      )
      match to_file {
        Some(f) => {
          // Ruby passes no jail here; the document's base_dir applies in safe mode.
          let outfile = doc.normalize_system_path_checked(
            f,
            start=outdir,
            target_name="to_dir",
            recover=false,
          )
          (outfile, @core.dirname(outfile))
        }
        None => (file_join(outdir, output_name(doc)), outdir)
      }
    }
    None => {
      let outfile = doc.normalize_system_path_checked(
        to_file.unwrap_or(""),
        start=working_dir,
        jail?,
        target_name="to_dir",
        recover=false,
      )
      (outfile, @core.dirname(outfile))
    }
  }
}

///|
/// Converts a file or a string and writes the output (Ruby
/// `Asciidoctor.convert`, which `convert_file` and `convert` wrap).
///
/// The destination is resolved as in Ruby:
/// * `Default` without `to_dir` writes a `Path` source next to the input
///   file, named after the document (`docname` + `outfilesuffix`); a `Text`
///   source is not written.
/// * `File` and/or `to_dir` write to an explicit target, resolved against
///   `options.base_dir` (or the working directory). When the safe mode is SAFE
///   or stricter it must not escape that directory, else
///   `@core.SecurityError` is raised. Its directory must exist unless
///   `mkdirs` is set (`IOError` otherwise).
/// * `Stdout` writes to standard output and `NoWrite` writes nothing; both
///   ignore `to_dir`.
///
/// Writing to a file makes the document standalone unless
/// `options.standalone` says otherwise. The output never overwrites the input
/// file (`IOError`). A man page (`manpage` backend) written to a file gets a
/// `.so` redirect page for each additional name in its NAME section, and with
/// `linkcss` and `copycss` set (and a safe mode below SECURE) the stylesheet
/// is copied next to an HTML output file (into `stylesdir`).
///
/// The error that aborts processing (`@core.Node::processing_error`, e.g.
/// `@core.MissingConverter` for an unknown backend) is raised before anything
/// is written. `options.timings`, if set, records the read, parse, convert
/// and write phases.
pub async fn convert_source(
  source : Source,
  options? : @core.Options = @core.Options::new(),
  destination? : Destination = Default,
  to_dir? : String,
  mkdirs? : Bool = false,
) -> Conversion {
  let vfs = FsVfs::new()
  let cwd = vfs.working_dir
  let (text, input_path, opts, read_time) = read_source(source, options, vfs)
  if destination is File("/dev/null") {
    let doc = run_with_files(vfs, () => {
      let doc = @asciidoctor.load(text, options=opts)
      raise_processing_error(doc)
      doc
    })
    add_read_time(opts, read_time)
    return { document: doc, output: "", outfile: None, }
  }
  let to_file = match destination {
    File(f) => Some(f)
    _ => None
  }
  // Ruby `sibling_path` (next to the input) / `write_to_target` (explicit)
  let sibling = if destination is Default && to_dir is None {
    input_path
  } else {
    None
  }
  let target = to_file is Some(_) ||
    (destination is Default && to_dir is Some(_))
  if opts.standalone is None && (sibling is Some(_) || target) {
    opts.standalone = Some(true)
  }
  if sibling is Some(path) {
    opts.to_dir = Some(@core.dirname(path))
  } else if target {
    opts.to_dir = match (to_dir, to_file) {
      (Some(d), Some(f)) =>
        Some(
          @core.dirname(
            @core.expand_path_from(@core.expand_path_from(cwd, d), f),
          ),
        )
      (Some(d), None) => Some(@core.expand_path_from(cwd, d))
      (None, Some(f)) => Some(@core.dirname(@core.expand_path_from(cwd, f)))
      (None, None) => None
    }
    opts.to_file = to_file
  }
  let working_dir = match options.base_dir {
    Some(b) => @core.expand_path_from(cwd, b)
    None => cwd
  }
  let (doc, out, output) = run_with_files(vfs, () => {
    let doc = @asciidoctor.load(text, options=opts)
    raise_processing_error(doc)
    let out = match sibling {
      Some(path) => {
        let outdir = @core.dirname(path)
        Some((file_join(outdir, output_name(doc)), outdir))
      }
      None if target => Some(resolve_target(doc, working_dir, to_dir, to_file))
      None => None
    }
    match (out, input_path) {
      (Some((outfile, _)), Some(path)) if outfile == path =>
        raise IOError(
          "input file and output file cannot be the same: \{outfile}",
        )
      _ => ()
    }
    match out {
      Some((_, outdir)) if target && !mkdirs && !@core.Vfs::is_dir(vfs, outdir) =>
        // Ruby refers to the directory as it was passed to the API
        raise IOError(
          "target directory does not exist: \{to_dir.unwrap_or("")} (hint: set :mkdirs option)",
        )
      _ => ()
    }
    let output = match out {
      Some((outfile, outdir)) => doc.convert_with(outfile~, outdir~)
      None => doc.convert()
    }
    (doc, out, output)
  })
  add_read_time(opts, read_time)
  // Ruby creates the target directory before converting
  if out is Some((_, outdir)) && target && mkdirs {
    @fs.mkdir(outdir, recursive=true, allow_exist=true)
  }
  raise_processing_error(doc)
  if out is Some((outfile, _)) {
    write(doc, output, Some(outfile), timings=opts.timings)
  } else if destination is Stdout {
    write(doc, output, None, timings=opts.timings)
  }
  if out is Some((_, outdir)) {
    copy_stylesheet(doc, vfs, outdir, mkdirs)
  }
  { document: doc, output, outfile: out.map(o => o.0), }
}

///|
/// Writes the output (Ruby `Document#write`) to `outfile`, with the `.so`
/// pages of a man page's alternate names, or else to standard output.
async fn write(
  doc : @core.Node,
  output : String,
  outfile : String?,
  timings~ : @core.Timings?,
) -> Unit {
  if timings is Some(t) {
    t.start("write")
  }
  match outfile {
    Some(outfile) => {
      @fs.write_file(outfile, output, create_mode=CreateOrTruncate)
      if doc.backend() == "manpage" {
        write_alternate_pages(doc, outfile)
      }
    }
    None => if output != "" { @stdio.stdout.write(@rb.chomp(output) + "\n") }
  }
  if timings is Some(t) {
    t.record("write")
  }
}

///|
/// Writes a `.so` redirect page for each alternate name of a man page (Ruby
/// `ManPageConverter.write_alternate_pages`).
async fn write_alternate_pages(doc : @core.Node, target : String) -> Unit {
  guard doc.attributes.get("mannames") is Some(List(mannames)) &&
    mannames.length() > 1 else {
    return
  }
  let manvolext = ".\{doc.attr("manvolnum").unwrap_or("")}"
  let dir = @core.dirname(target)
  let basename = @core.basename(target)
  for manname in mannames[1:] {
    @fs.write_file(
      file_join(dir, "\{manname}\{manvolext}"),
      ".so \{basename}",
      create_mode=CreateOrTruncate,
    )
  }
}

///|
async fn is_directory(path : String) -> Bool {
  let kind = @fs.kind(path) catch {
    @os_error.OSError(_, ..) => return false
    e => raise e
  }
  kind is Directory
}

///|
async fn is_regular_file(path : String) -> Bool {
  let kind = @fs.kind(path) catch {
    @os_error.OSError(_, ..) => return false
    e => raise e
  }
  kind is Regular
}

///|
/// Copies the stylesheet next to the output when `linkcss` and `copycss` are
/// set (Ruby `Asciidoctor.convert`): the default stylesheet, or the user
/// stylesheet (read from `copycss` if it names a file).
async fn copy_stylesheet(
  doc : @core.Node,
  vfs : FsVfs,
  outdir : String,
  mkdirs : Bool,
) -> Unit {
  guard doc.safe() < @core.SAFE_SECURE &&
    doc.has_attr("linkcss") &&
    doc.has_attr("copycss") &&
    doc.is_basebackend("html") else {
    return
  }
  let stylesdir = doc.attr("stylesdir")
  if stylesdir is Some(d) && @core.is_uriish(d) {
    return
  }
  let (copy_default, copy_user) = match doc.attr("stylesheet") {
    Some("" | "DEFAULT") => (true, false)
    Some(ss) => (false, !@core.is_uriish(ss))
    None => (false, false)
  }
  guard copy_default || copy_user else { return }
  let jail = if doc.safe() >= @core.SAFE_SAFE { Some(outdir) } else { None }
  let stylesoutdir = doc.normalize_system_path(
    stylesdir.unwrap_or(""),
    start=outdir,
    jail?,
  )
  if mkdirs {
    @fs.mkdir(stylesoutdir, recursive=true, allow_exist=true)
  } else if !is_directory(stylesoutdir) {
    raise IOError(
      "target stylesheet directory does not exist: \{stylesoutdir} (hint: set :mkdirs option)",
    )
  }
  if copy_default {
    @fs.write_file(
      file_join(stylesoutdir, "asciidoctor.css"),
      @core.primary_stylesheet_data,
      create_mode=CreateOrTruncate,
    )
    return
  }
  let stylesheet = doc.attr("stylesheet").unwrap_or("")
  let src = match doc.attr("copycss") {
    Some("") | None => doc.normalize_system_path(stylesheet)
    // copycss names the source location (which cannot be a URI)
    Some(loc) => doc.normalize_system_path(loc)
  }
  let dest = doc.normalize_system_path(stylesheet, start=stylesoutdir, jail?)
  guard src != dest else { return }
  vfs.fetch(src)
  // Ruby: don't warn if the source can't be read but the target exists
  let data = doc.read_asset(
    src,
    warn_on_failure=!is_regular_file(dest),
    label="stylesheet",
  )
  guard data is Some(data) else { return }
  let dest_dir = @core.dirname(dest)
  if dest_dir != stylesoutdir && !is_directory(dest_dir) {
    if !mkdirs {
      raise IOError(
        "target stylesheet directory does not exist: \{dest_dir} (hint: set :mkdirs option)",
      )
    }
    @fs.mkdir(dest_dir, recursive=true, allow_exist=true)
  }
  @fs.write_file(dest, data, create_mode=CreateOrTruncate)
}

///|
/// Converts a file (Ruby `Asciidoctor.convert_file`) and returns the output;
/// see `convert_source` for the destinations and errors.
///
/// With the `Default` destination and no `to_dir`, the output is written
/// next to the input file.
pub async fn convert_file(
  path : String,
  options? : @core.Options = @core.Options::new(),
  destination? : Destination = Default,
  to_dir? : String,
  mkdirs? : Bool = false,
) -> String {
  convert_source(Path(path), options~, destination~, to_dir?, mkdirs~).output
}

///|
/// Converts a string, resolving includes, docinfo and assets from the file
/// system (Ruby `Asciidoctor.convert`), and returns the output; see
/// `convert_source` for the destinations and errors. By default nothing is
/// written.
pub async fn convert(
  input : String,
  options? : @core.Options = @core.Options::new(),
  destination? : Destination = Default,
  to_dir? : String,
  mkdirs? : Bool = false,
) -> String {
  convert_source(Text(input), options~, destination~, to_dir?, mkdirs~).output
}
