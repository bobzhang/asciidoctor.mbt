///|
/// Synchronous virtual file system used by the (pure) processor for include
/// directives, docinfo files, stylesheets and embedded images. Real file
/// access is provided by the `io` package, which preloads files asynchronously.
pub(open) trait Vfs {
  /// Contents of the file at `path`, or None if it does not exist / is unreadable.
  fn read(Self, String) -> Bytes?
  /// Whether `path` names a regular file.
  fn is_file(Self, String) -> Bool
  /// Whether `path` names a directory.
  fn is_dir(Self, String) -> Bool
  /// The working directory (absolute, POSIX separators).
  fn cwd(Self) -> String
  /// The user's home directory.
  fn home(Self) -> String
}

///|
/// A file system without any files.
pub struct NullVfs {
  priv working_dir : String
}

///|
pub fn NullVfs::new(cwd? : String = "/") -> &Vfs {
  ({ working_dir: cwd, } : NullVfs)
}

///|
pub impl Vfs for NullVfs with fn read(_self, _path) {
  None
}

///|
pub impl Vfs for NullVfs with fn is_file(_self, _path) {
  false
}

///|
pub impl Vfs for NullVfs with fn is_dir(_self, _path) {
  false
}

///|
pub impl Vfs for NullVfs with fn cwd(self) {
  self.working_dir
}

///|
pub impl Vfs for NullVfs with fn home(_self) {
  "/"
}

///|
/// An in-memory file system: a map from absolute path to contents.
pub struct MemoryVfs {
  files : Map[String, Bytes]
  working_dir : String
  home_dir : String
}

///|
pub fn MemoryVfs::new(cwd? : String = "/", home? : String = "/") -> MemoryVfs {
  { files: {}, working_dir: cwd, home_dir: home, }
}

///|
/// Adds a text file (encoded as UTF-8).
pub fn MemoryVfs::add_text(
  self : MemoryVfs,
  path : String,
  text : String,
) -> Unit {
  self.files[path] = @utf8.encode(text)
}

///|
pub fn MemoryVfs::add_bytes(
  self : MemoryVfs,
  path : String,
  data : Bytes,
) -> Unit {
  self.files[path] = data
}

///|
pub impl Vfs for MemoryVfs with fn read(self, path) {
  self.files.get(path)
}

///|
pub impl Vfs for MemoryVfs with fn is_file(self, path) {
  self.files.contains(path)
}

///|
pub impl Vfs for MemoryVfs with fn is_dir(self, path) {
  let prefix = if path.has_suffix("/") { path } else { path + "/" }
  for k, _ in self.files {
    if k.has_prefix(prefix) {
      return true
    }
  }
  path == "/" || path == self.working_dir
}

///|
pub impl Vfs for MemoryVfs with fn cwd(self) {
  self.working_dir
}

///|
pub impl Vfs for MemoryVfs with fn home(self) {
  self.home_dir
}

///|
/// Decodes file contents as text: strips a UTF-8 BOM, decodes UTF-16 with a
/// BOM, otherwise decodes UTF-8 (invalid sequences become U+FFFD).
pub fn decode_text(data : Bytes) -> String {
  let n = data.length()
  if n >= 2 && data[0] == 0xFF && data[1] == 0xFE {
    let sb = StringBuilder()
    let mut i = 2
    while i + 1 < n {
      let u = data[i].to_int() | (data[i + 1].to_int() << 8)
      sb.write_char(u.unsafe_to_char())
      i += 2
    }
    return fix_surrogates(sb.to_string())
  }
  if n >= 2 && data[0] == 0xFE && data[1] == 0xFF {
    let sb = StringBuilder()
    let mut i = 2
    while i + 1 < n {
      let u = (data[i].to_int() << 8) | data[i + 1].to_int()
      sb.write_char(u.unsafe_to_char())
      i += 2
    }
    return fix_surrogates(sb.to_string())
  }
  let start = if n >= 3 && data[0] == 0xEF && data[1] == 0xBB && data[2] == 0xBF {
    3
  } else {
    0
  }
  @utf8.decode_lossy(data[start:])
}

///|
fn fix_surrogates(s : String) -> String {
  s
}

///|
/// Decodes file contents using the named encoding (Ruby `File.read` with an
/// encoding mode). Supports UTF-8 (default), ISO-8859-1/Latin-1 and US-ASCII;
/// unknown encodings fall back to UTF-8, like Ruby ignoring invalid names.
pub fn decode_text_with(data : Bytes, encoding : String?) -> String {
  match encoding.map(e => @rb.downcase_ascii(e)) {
    Some("iso-8859-1")
    | Some("iso8859-1")
    | Some("latin1")
    | Some("binary")
    | Some("ascii-8bit") => {
      let sb = StringBuilder(size_hint=data.length())
      for b in data {
        sb.write_char(b.to_int().unsafe_to_char())
      }
      sb.to_string()
    }
    _ => decode_text(data)
  }
}
