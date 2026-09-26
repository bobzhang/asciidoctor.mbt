// File-system integration for the (pure, synchronous) processor.
//
// The core reads include files, docinfo, stylesheets and images through a
// synchronous `@core.Vfs`. `FsVfs` serves those reads from a cache; every miss
// is recorded. `run_with_files` runs the pipeline, loads the missed paths
// asynchronously with `moonbitlang/async/fs`, and reruns until no new paths are
// requested. The final run sees every file it asks for, so its output (and its
// log messages, which are replayed to the real logger) is exact.
//
// Files are only discovered for the work done *inside* the rerun function:
// `convert` and `convert_file` parse and convert inside it, so include files,
// docinfo, stylesheets and data-URI images are all resolved. `load` and
// `load_file` only parse inside it unless `prefetch_conversion` is set.

///|
/// Raised when the output cannot be written (Ruby `IOError` raised by
/// `Asciidoctor.convert`): the target directory does not exist and `mkdirs`
/// is not set, or the output file would overwrite the input file.
pub suberror IOError {
  IOError(String)
}

///|
pub impl Show for IOError with fn output(self, logger) {
  let IOError(msg) = self
  logger.write_string(msg)
}

///|
/// Raised by `run_with_files` when the pipeline still requests uncached
/// files after `rounds` runs. `unresolved` lists the paths requested by the
/// last run that were never loaded.
pub suberror FixpointExhausted {
  FixpointExhausted(rounds~ : Int, unresolved~ : Array[String])
}

///|
pub impl Show for FixpointExhausted with fn output(self, logger) {
  let FixpointExhausted(rounds~, unresolved~) = self
  logger.write_string(
    "file requests did not settle after \{rounds} rounds; unresolved: \{unresolved.join(", ")}",
  )
}

///|
/// A cached path that is not a directory.
priv enum Entry {
  /// A regular file and its contents.
  Present(Bytes)
  /// Missing, or not a regular file (Ruby `File.file?` is false).
  Absent
  /// A regular file that could not be read (e.g. permission denied).
  Unreadable
}

///|
/// A caching VFS backed by the real file system (filled asynchronously).
pub struct FsVfs {
  priv files : Map[String, Entry]
  priv dirs : Map[String, Bool]
  priv misses : Array[String]
  priv missed : Map[String, Bool]
  priv working_dir : String
  priv home_dir : String
}

///|
/// Creates a VFS rooted at the current working directory.
pub fn FsVfs::new(cwd? : String, home? : String) -> FsVfs {
  let working_dir = match cwd {
    Some(c) => c
    None => @env.current_dir().unwrap_or("/")
  }
  {
    files: {},
    dirs: {},
    misses: [],
    missed: {},
    working_dir,
    home_dir: match home {
      Some(h) => h
      None => @env.get_env_var("HOME").unwrap_or("/")
    },
  }
}

///|
fn FsVfs::miss(self : FsVfs, path : String) -> Unit {
  if !self.missed.contains(path) {
    self.missed[path] = true
    self.misses.push(path)
  }
}

///|
pub impl @core.Vfs for FsVfs with fn read(self, path) {
  match self.files.get(path) {
    Some(Present(data)) => Some(data)
    Some(Absent | Unreadable) => None
    None => {
      self.miss(path)
      None
    }
  }
}

///|
/// Like Ruby `File.file?`: true for unreadable regular files too, so the
/// reader reports them as "not readable" rather than "not found".
pub impl @core.Vfs for FsVfs with fn is_file(self, path) {
  match self.files.get(path) {
    Some(Present(_) | Unreadable) => true
    Some(Absent) => false
    None =>
      if self.dirs.contains(path) {
        false
      } else {
        self.miss(path)
        false
      }
  }
}

///|
pub impl @core.Vfs for FsVfs with fn is_dir(self, path) {
  match self.dirs.get(path) {
    Some(d) => d
    None => {
      if !self.files.contains(path) {
        self.miss(path)
      }
      false
    }
  }
}

///|
pub impl @core.Vfs for FsVfs with fn cwd(self) {
  self.working_dir
}

///|
pub impl @core.Vfs for FsVfs with fn home(self) {
  self.home_dir
}

///|
/// Loads a path into the cache, as a directory, a file, an unreadable file,
/// or absent.
///
/// Mirrors Ruby: `File.file?` and `File.directory?` are false when the path
/// cannot be stat'ed for any reason, so such a path is absent (an include of
/// it logs "include file not found"). A regular file whose contents cannot be
/// read (e.g. permission denied) is cached as unreadable: `is_file` is true
/// and `read` fails, so an include of it logs "include file not readable".
/// Errors other than OS errors (e.g. cancellation) propagate.
pub async fn FsVfs::fetch(self : FsVfs, path : String) -> Unit {
  let kind = @fs.kind(path) catch {
    @os_error.OSError(_, ..) => {
      self.files[path] = Absent
      return
    }
    e => raise e
  }
  match kind {
    Directory => self.dirs[path] = true
    Regular | SymLink => {
      let data = @fs.read_file(path).binary() catch {
        @os_error.OSError(_, ..) => {
          self.files[path] = Unreadable
          return
        }
        e => raise e
      }
      self.files[path] = Present(data)
    }
    _ => self.files[path] = Absent
  }
}

///|
/// Adds content for a path directly (e.g. stdin or generated files).
pub fn FsVfs::add(self : FsVfs, path : String, data : Bytes) -> Unit {
  self.files[path] = Present(data)
}

///|
/// Runs `f` until it no longer requests uncached files, then replays the log
/// messages of the final run to the global logger and returns its result.
///
/// An error raised by `f` in a run that requested uncached files is ignored
/// (the run is repeated once the files are loaded); an error raised by the
/// final run is re-raised after its log messages are replayed. Raises
/// `FixpointExhausted` if `f` still requests uncached files after
/// `max_rounds` runs.
pub async fn[T] run_with_files(
  vfs : FsVfs,
  f : () -> T raise,
  max_rounds? : Int = 32,
) -> T {
  fixpoint(vfs, f, max_rounds, replay=true)
}

///|
async fn[T] fixpoint(
  vfs : FsVfs,
  f : () -> T raise,
  max_rounds : Int,
  replay~ : Bool,
) -> T {
  use_system_time_zone()
  let process_state = @core.snapshot_process_state()
  for round = 1; ; round = round + 1 {
    vfs.misses.clear()
    vfs.missed.clear()
    @core.restore_process_state(process_state)
    let (result, messages) = @core.with_memory_logger(() => {
      let r : Result[T, Error] = try f() |> Ok catch {
        e => Err(e)
      }
      r
    })
    if vfs.misses.is_empty() {
      if replay {
        let logger = @core.logger()
        for m in messages {
          logger.add(m)
        }
      }
      match result {
        Ok(v) => return v
        Err(e) => raise e
      }
    }
    if round >= max_rounds {
      raise FixpointExhausted(rounds=round, unresolved=vfs.misses.copy())
    }
    for p in vfs.misses.copy() {
      vfs.fetch(p)
    }
  }
}

///|
fn with_vfs(options : @core.Options, vfs : FsVfs) -> @core.Options {
  let o = { ..options, attributes: options.attributes.copy(), }
  o.vfs = Some(vfs)
  o
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
/// Metadata of an input file, as Ruby `Asciidoctor.load_file` computes it.
priv struct InputFile {
  path : String // absolute
  text : String
  mtime : Int64
}

///|
async fn read_input(vfs : FsVfs, path : String) -> InputFile {
  let abs = @core.expand_path_from(vfs.working_dir, path)
  let data = @fs.read_file(abs).binary()
  vfs.add(abs, data)
  let (secs, _) = @fs.mtime(abs) catch { _ => (0L, 0) }
  { path: abs, text: @core.decode_text(data), mtime: secs, }
}

///|
fn input_options(
  options : @core.Options,
  input : InputFile,
  vfs : FsVfs,
) -> @core.Options {
  let o = with_vfs(options, vfs)
  let docdir = @core.dirname(input.path)
  let suffix = @core.extname(input.path, fallback="")
  o.attributes = [
    ("docfile", @core.AttrVal::Str(input.path)),
    ("docdir", Str(docdir)),
    ("docfilesuffix", Str(suffix)),
    ("docname", Str(@core.basename(input.path, drop_ext=true))),
    ..options.attributes,
  ]
  o.input_mtime = Some(input.mtime)
  o
}

///|
/// Loads (parses) `text`, resolving the files read while parsing. With
/// `prefetch_conversion`, the files read while converting are cached too.
async fn load_text(
  vfs : FsVfs,
  text : String,
  opts : @core.Options,
  prefetch_conversion : Bool,
) -> @core.Node {
  if prefetch_conversion {
    // Discovery runs on throwaway documents (conversion mutates the
    // document); their log messages are dropped. Both modes are converted so
    // a later `convert_with(standalone=...)` override is covered as well.
    fixpoint(
      vfs,
      () => {
        @asciidoctor.load(text, options=opts).convert_with(standalone=true)
        |> ignore
        @asciidoctor.load(text, options=opts).convert_with(standalone=false)
        |> ignore
      },
      32,
      replay=false,
    )
  }
  run_with_files(vfs, () => @asciidoctor.load(text, options=opts))
}

///|
/// Loads a document from a file (Ruby `Asciidoctor.load_file`).
///
/// Only the files read while *parsing* (include files) are loaded from the
/// file system. Files read while *converting* (docinfo, the embedded
/// stylesheet, data-URI images) are not, so calling `convert()` on the
/// returned document may silently miss them. Use `convert_file` to load and
/// convert in one step, or pass `prefetch_conversion=true` to also cache the
/// files that converting the returned document (with its load options, as
/// `convert()` or `convert_with(standalone=...)` does) will read; that costs
/// an extra parse and conversion.
pub async fn load_file(
  path : String,
  options? : @core.Options = @core.Options::new(),
  prefetch_conversion? : Bool = false,
) -> @core.Node {
  let vfs = FsVfs::new()
  let input = read_input(vfs, path)
  let opts = input_options(options, input, vfs)
  load_text(vfs, input.text, opts, prefetch_conversion)
}

///|
/// Loads a document from a string, resolving includes from the file system.
/// See `load_file` for what is (and is not) resolved.
pub async fn load(
  input : String,
  options? : @core.Options = @core.Options::new(),
  prefetch_conversion? : Bool = false,
) -> @core.Node {
  let vfs = FsVfs::new()
  let opts = with_vfs(options, vfs)
  load_text(vfs, input, opts, prefetch_conversion)
}

///|
/// Converts a string, resolving includes/docinfo/assets from the file system.
pub async fn convert(
  input : String,
  options? : @core.Options = @core.Options::new(),
) -> String {
  let vfs = FsVfs::new()
  let opts = with_vfs(options, vfs)
  run_with_files(vfs, () => @asciidoctor.load(input, options=opts).convert())
}

///|
/// Where `convert_file` writes its output.
pub(all) enum Destination {
  /// Next to the input file (or in `to_dir` if given), named after the document.
  Default
  /// A specific file, resolved against `to_dir` if given. `File("/dev/null")`
  /// only loads the document (Ruby `to_file: '/dev/null'`).
  File(String)
  /// Standard output.
  Stdout
  /// Do not write; return the output.
  NoWrite
}

///|
/// The output file name Ruby derives from the document.
fn output_name(doc : @core.Node) -> String {
  "\{doc.attributes.str("docname").unwrap_or("")}\{doc.outfilesuffix()}"
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
  match (to_dir, to_file) {
    (Some(d), _) => {
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
    (None, f) => {
      let outfile = doc.normalize_system_path_checked(
        f.unwrap_or(""),
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
/// Converts a file (Ruby `Asciidoctor.convert_file`). Returns the converted
/// output.
///
/// With the `Default` destination and no `to_dir`, the output is written
/// next to the input file, named after the document (`docname` +
/// `outfilesuffix`). Otherwise (`to_dir` and/or `File`) the target is
/// resolved against `options.base_dir` (or the working directory); when the
/// safe mode is SAFE or stricter it must not escape that directory, else
/// `@core.SecurityError` is raised. The target directory must exist unless
/// `mkdirs` is set (`IOError` otherwise). `to_dir` is ignored for `Stdout` and
/// `NoWrite`, as in Ruby.
///
/// When writing a file with `linkcss` and `copycss` set (and safe mode below
/// SECURE), the stylesheet is copied next to the output (into `stylesdir`).
pub async fn convert_file(
  path : String,
  options? : @core.Options = @core.Options::new(),
  destination? : Destination = Default,
  to_dir? : String,
  mkdirs? : Bool = false,
) -> String {
  let vfs = FsVfs::new()
  let input = read_input(vfs, path)
  let opts = input_options(options, input, vfs)
  if destination is File("/dev/null") {
    run_with_files(vfs, () => @asciidoctor.load(input.text, options=opts))
    |> ignore
    return ""
  }
  let cwd = vfs.working_dir
  let to_file = match destination {
    File(f) => Some(f)
    _ => None
  }
  // Ruby `sibling_path` (next to the input) / `write_to_target` (explicit).
  let sibling = destination is Default && to_dir is None
  let target = to_file is Some(_) ||
    (destination is Default && to_dir is Some(_))
  if opts.standalone is None && (sibling || target) {
    opts.standalone = Some(true)
  }
  if sibling {
    opts.to_dir = Some(@core.dirname(input.path))
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
    let doc = @asciidoctor.load(input.text, options=opts)
    let out = if sibling {
      let outdir = @core.dirname(input.path)
      Some((file_join(outdir, output_name(doc)), outdir))
    } else if target {
      let (outfile, outdir) = resolve_target(doc, working_dir, to_dir, to_file)
      Some((outfile, outdir))
    } else {
      None
    }
    match out {
      Some((outfile, _)) if outfile == input.path =>
        raise IOError(
          "input file and output file cannot be the same: \{outfile}",
        )
      Some((_, outdir)) if target && !mkdirs && !@core.Vfs::is_dir(vfs, outdir) =>
        // Ruby refers to the directory as it was passed to the API.
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
  match out {
    Some((outfile, outdir)) => {
      if target && mkdirs {
        @fs.mkdir(outdir, recursive=true, allow_exist=true)
      }
      @fs.write_file(outfile, output, create_mode=CreateOrTruncate)
      copy_stylesheet(doc, vfs, outdir, mkdirs)
    }
    None =>
      if destination is Stdout && output != "" {
        @stdio.stdout.write(@rb.chomp(output) + "\n")
      }
  }
  output
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
  match @core.Vfs::read(vfs, src) {
    Some(data) => {
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
    // Ruby: don't warn if the source can't be read but the target exists
    None =>
      if !is_regular_file(dest) {
        doc.read_asset(src, warn_on_failure=true, label="stylesheet") |> ignore
      }
  }
}

///|
let system_time_zone_installed : Ref[Bool] = { val: false, }

///|
/// Date attributes (`localdatetime`, `docdatetime`, ...) use the system time
/// zone, as in Ruby. The first `@io` conversion installs it in the core with
/// `@core.set_utc_offset`; a later call to `@core.set_utc_offset` overrides it.
fn use_system_time_zone() -> Unit {
  if !system_time_zone_installed.val {
    system_time_zone_installed.val = true
    @core.set_utc_offset(@localtime.utc_offset)
  }
}
