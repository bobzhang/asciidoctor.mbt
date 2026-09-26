// Conversion driver of the CLI: a port of Ruby `Asciidoctor.convert`
// (convert.rb) and `Document#write` for both input files and standard input,
// on top of the caching file system of the `io` package.

///|
/// The input of a conversion.
priv enum CliInput {
  /// Standard input (its text).
  Stdin(String)
  /// A file, as named on the command line.
  InputFile(String)
}

///|
/// Where the output goes (Ruby `:to_file` option).
priv enum ToFile {
  /// Derived from the input file: next to it, or in `to_dir`.
  Derived
  /// Standard output (`-o -`).
  Stream
  /// An explicit file (`-o FILE`).
  Path(String)
}

///|
/// A failure Ruby reports with an `IOError`.
priv suberror CliIOError {
  CliIOError(String)
}

///|
impl Show for CliIOError with fn output(self, logger) {
  let CliIOError(msg) = self
  logger.write_string(msg)
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
fn output_name(doc : @core.Node) -> String {
  "\{doc.attributes.str("docname").unwrap_or("")}\{doc.outfilesuffix()}"
}

///|
fn raise_processing_error(doc : @core.Node) -> Unit raise {
  match doc.processing_error() {
    Some(e) => raise e
    None => ()
  }
}

///|
/// Converts `input` and writes the output (Ruby `Asciidoctor.convert` with
/// the options the CLI passes). `options.timings`, if set, records the
/// read, parse, convert and write phases.
async fn convert_input(
  input : CliInput,
  options : @core.Options,
  to_file~ : ToFile,
  to_dir~ : String?,
  mkdirs~ : Bool,
) -> Unit {
  let cwd = @env.current_dir().unwrap_or("/")
  let vfs = @io.FsVfs::new(cwd~)
  let opts = { ..options, attributes: options.attributes.copy(), }
  opts.vfs = Some(vfs)
  let timings = opts.timings
  // read the input (Ruby `load`); file attributes override the user's
  let read_started = monotonic_seconds()
  let (text, input_path) = match input {
    Stdin(text) => (text, None)
    InputFile(path) => {
      let abs = @core.expand_path_from(cwd, path)
      let data = @fs.read_file(abs).binary()
      vfs.add(abs, data)
      let (mtime, _) = @fs.mtime(abs) catch { _ => (0L, 0) }
      opts.input_mtime = Some(mtime)
      let suffix = @core.extname(abs, fallback="")
      opts.attributes.push(("docfile", Str(abs)))
      opts.attributes.push(("docdir", Str(@core.dirname(abs))))
      opts.attributes.push(("docfilesuffix", Str(suffix)))
      opts.attributes.push(("docname", Str(@core.basename(abs, drop_ext=true))))
      (@core.decode_text(data), Some(abs))
    }
  }
  let read_time = monotonic_seconds() - read_started
  // Ruby: sibling_path (next to the input), write_to_target (explicit file
  // or directory) or stream output
  let (sibling, target, stream, explicit_file) = match to_file {
    Derived =>
      match to_dir {
        Some(_) => (None, true, false, None)
        None => (input_path, false, false, None)
      }
    Path("/dev/null") => {
      @io.run_with_files(vfs, () => {
        let doc = @adoc.load(text, options=opts)
        raise_processing_error(doc)
      })
      return
    }
    Path(f) => (None, true, false, Some(f))
    Stream => (None, false, true, None)
  }
  if explicit_file is Some(f) {
    opts.to_file = Some(f)
  }
  if opts.standalone is None && (sibling is Some(_) || target) {
    opts.standalone = Some(true)
  }
  match sibling {
    Some(path) => opts.to_dir = Some(@core.dirname(path))
    None =>
      if target {
        opts.to_dir = match (to_dir, explicit_file) {
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
      }
  }
  let working_dir = match options.base_dir {
    Some(b) => @core.expand_path_from(cwd, b)
    None => cwd
  }
  let (doc, out, output) = @io.run_with_files(vfs, () => {
    let doc = @adoc.load(text, options=opts)
    raise_processing_error(doc)
    let out = match sibling {
      Some(path) => {
        let outdir = @core.dirname(path)
        Some((file_join(outdir, output_name(doc)), outdir))
      }
      None =>
        if target {
          Some(resolve_target(doc, working_dir, to_dir, explicit_file))
        } else {
          None
        }
    }
    match (out, input_path) {
      (Some((outfile, _)), Some(path)) if outfile == path =>
        raise CliIOError(
          "input file and output file cannot be the same: \{outfile}",
        )
      _ => ()
    }
    match out {
      Some((_, outdir)) if target && !mkdirs && !@core.Vfs::is_dir(vfs, outdir) =>
        // Ruby refers to the directory as it was passed to the API
        raise CliIOError(
          "target directory does not exist: \{to_dir.unwrap_or("")} (hint: set :mkdirs option)",
        )
      _ => ()
    }
    let output = match out {
      Some((outfile, outdir)) => doc.convert_with(outfile~, outdir~)
      None => doc.convert()
    }
    raise_processing_error(doc)
    (doc, out, output)
  })
  if timings is Some(t) {
    t.set("read", read_time + t.time(["read"]).unwrap_or(0.0))
    t.start("write")
  }
  match out {
    Some((outfile, outdir)) => {
      if mkdirs {
        @fs.mkdir(outdir, recursive=true, allow_exist=true)
      }
      @fs.write_file(outfile, output, create_mode=CreateOrTruncate)
      if doc.backend() == "manpage" {
        write_alternate_pages(doc, outfile)
      }
    }
    None =>
      if stream && output != "" {
        @stdio.stdout.write(@rb.chomp(output) + "\n")
      }
  }
  if timings is Some(t) {
    t.record("write")
  }
  if out is Some((_, outdir)) {
    copy_stylesheet(doc, vfs, outdir, mkdirs)
  }
}

///|
/// Resolves the output file and directory of an explicit target (Ruby
/// `Asciidoctor.convert`, `write_to_target` branch). In safe mode the target
/// must stay inside `working_dir`.
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
  vfs : @io.FsVfs,
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
    raise CliIOError(
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
      raise CliIOError(
        "target stylesheet directory does not exist: \{dest_dir} (hint: set :mkdirs option)",
      )
    }
    @fs.mkdir(dest_dir, recursive=true, allow_exist=true)
  }
  @fs.write_file(dest, data, create_mode=CreateOrTruncate)
}
