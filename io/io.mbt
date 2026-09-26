// File-system integration for the (pure, synchronous) processor.
//
// The core reads include files, docinfo, stylesheets and images through a
// synchronous `@core.Vfs`. `FsVfs` serves those reads from a cache; every miss
// is recorded. `run_with_files` runs the pipeline, loads the missed paths
// asynchronously with `moonbitlang/async/fs`, and reruns until no new paths are
// requested. The final run sees every file it asks for, so its output (and its
// log messages, which are replayed to the real logger) is exact.

///|
/// A caching VFS backed by the real file system (filled asynchronously).
pub struct FsVfs {
  priv files : Map[String, Bytes?] // None: known to be absent
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
    Some(v) => v
    None => {
      self.miss(path)
      None
    }
  }
}

///|
pub impl @core.Vfs for FsVfs with fn is_file(self, path) {
  match self.files.get(path) {
    Some(v) => v is Some(_)
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
/// Loads a path into the cache (as file, directory, or absent).
pub async fn FsVfs::fetch(self : FsVfs, path : String) -> Unit {
  let kind = @fs.kind(path) catch {
    _ => {
      self.files[path] = None
      return
    }
  }
  match kind {
    Directory => self.dirs[path] = true
    Regular | SymLink => {
      let data = @fs.read_file(path).binary() catch {
        _ => {
          self.files[path] = None
          return
        }
      }
      self.files[path] = Some(data)
    }
    _ => self.files[path] = None
  }
}

///|
/// Adds content for a path directly (e.g. stdin or generated files).
pub fn FsVfs::add(self : FsVfs, path : String, data : Bytes) -> Unit {
  self.files[path] = Some(data)
}

///|
/// Runs `f` until it no longer requests uncached files, then replays the log
/// messages of the final run to the global logger.
pub async fn[T] run_with_files(
  vfs : FsVfs,
  f : () -> T,
  max_rounds? : Int = 32,
) -> T {
  let mut round = 0
  let process_state = @core.snapshot_process_state()
  while true {
    vfs.misses.clear()
    vfs.missed.clear()
    @core.restore_process_state(process_state)
    let (result, messages) = @core.with_memory_logger(f)
    round += 1
    if vfs.misses.is_empty() || round >= max_rounds {
      let logger = @core.logger()
      for m in messages {
        logger.add(m)
      }
      return result
    }
    let pending = vfs.misses.copy()
    for p in pending {
      vfs.fetch(p)
    }
  }
  abort("unreachable")
}

///|
fn with_vfs(options : @core.Options, vfs : FsVfs) -> @core.Options {
  let o = { ..options, attributes: options.attributes.copy(), }
  o.vfs = Some(vfs)
  o
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
/// Loads a document from a file (Ruby `Asciidoctor.load_file`).
pub async fn load_file(
  path : String,
  options? : @core.Options = @core.Options::new(),
) -> @core.Node {
  let vfs = FsVfs::new()
  let input = read_input(vfs, path)
  let opts = input_options(options, input, vfs)
  run_with_files(vfs, () => @asciidoctor.load(input.text, options=opts))
}

///|
/// Loads a document from a string, resolving includes from the file system.
pub async fn load(
  input : String,
  options? : @core.Options = @core.Options::new(),
) -> @core.Node {
  let vfs = FsVfs::new()
  let opts = with_vfs(options, vfs)
  run_with_files(vfs, () => @asciidoctor.load(input, options=opts))
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
  /// A specific file.
  File(String)
  /// Standard output.
  Stdout
  /// Do not write; return the output.
  NoWrite
}

///|
/// Converts a file (Ruby `Asciidoctor.convert_file`). Returns the converted
/// output. With the default destination the output is written next to the
/// input file (or into `to_dir`), using the document's `outfilesuffix`.
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
  let writes = destination is (Default | File(_))
  if opts.standalone is None && writes {
    opts.standalone = Some(true)
  }
  match (destination, to_dir) {
    (File(f), Some(d)) =>
      opts.to_dir = Some(@core.dirname(@core.expand_path_from(d, f)))
    (File(f), None) =>
      opts.to_dir = Some(
        @core.dirname(@core.expand_path_from(vfs.working_dir, f)),
      )
    (Default, Some(d)) =>
      opts.to_dir = Some(@core.expand_path_from(vfs.working_dir, d))
    (Default, None) => opts.to_dir = Some(@core.dirname(input.path))
    _ => ()
  }
  match destination {
    File(f) => opts.to_file = Some(f)
    _ => ()
  }
  let (doc, outfile, output) = run_with_files(vfs, () => {
    let doc = @asciidoctor.load(input.text, options=opts)
    let outfile = match (destination, to_dir) {
      (Default, None) =>
        Some(
          "\{@core.dirname(input.path)}/\{doc.attributes.str("docname").unwrap_or("")}\{doc.outfilesuffix()}",
        )
      (Default, Some(d)) =>
        Some(
          "\{@core.expand_path_from(vfs.working_dir, d)}/\{doc.attributes.str("docname").unwrap_or("")}\{doc.outfilesuffix()}",
        )
      (File(f), Some(d)) =>
        Some(
          @core.expand_path_from(@core.expand_path_from(vfs.working_dir, d), f),
        )
      (File(f), None) => Some(@core.expand_path_from(vfs.working_dir, f))
      _ => None
    }
    let output = match outfile {
      Some(of) => doc.convert_with(outfile=of, outdir=@core.dirname(of))
      None => doc.convert()
    }
    (doc, outfile, output)
  })
  match outfile {
    Some(of) => {
      if of == input.path {
        fail("input file and output file cannot be the same: \{of}")
      }
      let outdir = @core.dirname(of)
      if mkdirs {
        @fs.mkdir(outdir, recursive=true, allow_exist=true)
      }
      @fs.write_file(of, output, create_mode=CreateOrTruncate)
      copy_stylesheet(doc, outdir, mkdirs)
    }
    None =>
      if destination is Stdout {
        if output != "" {
          @stdio.stdout.write(@rb.chomp(output) + "\n")
        }
      }
  }
  output
}

///|
/// Copies the default stylesheet next to the output when `linkcss` and
/// `copycss` are set (Ruby `Asciidoctor.convert`).
async fn copy_stylesheet(
  doc : @core.Node,
  outdir : String,
  mkdirs : Bool,
) -> Unit {
  if !(doc.safe() < @core.SAFE_SECURE &&
    doc.has_attr("linkcss") &&
    doc.has_attr("copycss") &&
    doc.is_basebackend("html")) {
    return
  }
  let stylesdir = doc.attr("stylesdir")
  match stylesdir {
    Some(d) if @core.is_uriish(d) => return
    _ => ()
  }
  let stylesheet = doc.attr("stylesheet")
  guard stylesheet is Some(ss) && (ss == "" || ss == "DEFAULT") else { return }
  let stylesoutdir = doc.normalize_system_path(
    stylesdir.unwrap_or("."),
    start=outdir,
    jail?=if doc.safe() >= @core.SAFE_SAFE { Some(outdir) } else { None },
  )
  if mkdirs {
    @fs.mkdir(stylesoutdir, recursive=true, allow_exist=true)
  }
  @fs.write_file(
    "\{stylesoutdir}/asciidoctor.css",
    @core.primary_stylesheet_data,
    create_mode=CreateOrTruncate,
  )
}
