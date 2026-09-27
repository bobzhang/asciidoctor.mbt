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
// the conversion driver (convert.mbt, Ruby convert.rb) parses and converts
// inside it, so include files, docinfo, stylesheets and data-URI images are
// all resolved. `load` and `load_file` (load.mbt, Ruby load.rb) only parse
// inside it unless `prefetch_conversion` is set.

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
/// Raised inside a round that already requested uncached files, to skip work
/// whose result would be discarded (the round is rerun).
priv suberror MissingFiles

///|
/// Raises `MissingFiles` if this round requested uncached files, so a caller
/// can stop early (e.g. skip converting after a parse that missed includes).
fn FsVfs::raise_if_missing(self : FsVfs) -> Unit raise MissingFiles {
  if !self.misses.is_empty() {
    raise MissingFiles
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
