// Loading documents from files and strings (Ruby lib/asciidoctor/load.rb).

///|
fn with_vfs(options : @core.Options, vfs : FsVfs) -> @core.Options {
  let o = { ..options, attributes: options.attributes.copy(), }
  o.vfs = Some(vfs)
  o
}

///|
/// Metadata of an input file, as Ruby `Asciidoctor.load` computes it.
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
/// The options for loading `input`: the file attributes (`docfile`, `docdir`,
/// `docfilesuffix`, `docname`) are added after the user's attributes, so they
/// override them, as in Ruby.
fn input_options(
  options : @core.Options,
  input : InputFile,
  vfs : FsVfs,
) -> @core.Options {
  let o = with_vfs(options, vfs)
  o.attributes.push(("docfile", Str(input.path)))
  o.attributes.push(("docdir", Str(@core.dirname(input.path))))
  o.attributes.push(
    ("docfilesuffix", Str(@core.extname(input.path, fallback=""))),
  )
  o.attributes.push(("docname", Str(@core.basename(input.path, drop_ext=true))))
  o.input_mtime = Some(input.mtime)
  o
}

///|
/// Reads the input of a conversion (Ruby `load` reading its input), timing it
/// as part of the `read` phase. Returns the text, the absolute path of an
/// input file, the load options and the time spent reading.
async fn read_source(
  source : Source,
  options : @core.Options,
  vfs : FsVfs,
) -> (String, String?, @core.Options, Double) {
  let timings = options.timings
  if timings is Some(t) {
    t.start("read")
  }
  let (text, path, opts) = match source {
    Path(path) => {
      let input = read_input(vfs, path)
      (input.text, Some(input.path), input_options(options, input, vfs))
    }
    Text(text) => (text, None, with_vfs(options, vfs))
  }
  let read_time = match timings {
    Some(t) => {
      t.record("read")
      t.read().unwrap_or(0.0)
    }
    None => 0.0
  }
  (text, path, opts, read_time)
}

///|
/// Adds the time spent reading the input to the `read` phase that loading
/// the document recorded.
fn add_read_time(options : @core.Options, read_time : Double) -> Unit {
  if options.timings is Some(t) {
    t.set("read", read_time + t.read().unwrap_or(0.0))
  }
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
    // document); their log messages and timings are dropped. Both modes are
    // converted so a later `convert_with(standalone=...)` override is covered
    // as well.
    let discovery = { ..opts, timings: None, }
    fixpoint(
      vfs,
      () => {
        @asciidoctor.load(text, options=discovery).convert_with(standalone=true)
        |> ignore
        @asciidoctor.load(text, options=discovery).convert_with(
          standalone=false,
        )
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
///
/// As with `@asciidoctor.load`, an error that aborts processing (e.g. a
/// missing converter) is reported by `@core.Node::processing_error`.
pub async fn load_file(
  path : String,
  options? : @core.Options = @core.Options::new(),
  prefetch_conversion? : Bool = false,
) -> @core.Node {
  let vfs = FsVfs::new()
  let (text, _, opts, read_time) = read_source(Path(path), options, vfs)
  let doc = load_text(vfs, text, opts, prefetch_conversion)
  add_read_time(opts, read_time)
  doc
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
