///|
/// Splits a string into lines, trimming trailing whitespace (or only the
/// line ending when `trim_end` is false). Ruby `Helpers.prepare_source_string`.
pub fn prepare_source_string(
  data : String,
  trim_end? : Bool = true,
) -> Array[String] {
  if data == "" {
    return []
  }
  let data = if data.has_prefix("\u{FEFF}") { @rb.from(data, 1) } else { data }
  let lines = []
  let n = data.length()
  let mut start = 0
  let mut i = 0
  while i < n {
    if data[i] == '\n' {
      let line = data.unsafe_substring(start~, end=i + 1)
      lines.push(if trim_end { @rb.rstrip(line) } else { @rb.chomp(line) })
      start = i + 1
    }
    i += 1
  }
  if start < n {
    let line = data.unsafe_substring(start~, end=n)
    lines.push(if trim_end { @rb.rstrip(line) } else { @rb.chomp(line) })
  }
  lines
}

///|
/// Ruby `Helpers.prepare_source_array`.
pub fn prepare_source_array(
  data : Array[String],
  trim_end? : Bool = true,
) -> Array[String] {
  if data.is_empty() {
    return []
  }
  let out = data.map(line => {
    if trim_end {
      @rb.rstrip(line)
    } else {
      @rb.chomp(line)
    }
  })
  if out[0].has_prefix("\u{FEFF}") {
    out[0] = @rb.from(out[0], 1)
  }
  out
}

///|
/// Whether `str` looks like a URI (Ruby `Helpers.uriish?`).
pub fn is_uriish(str : String) -> Bool {
  str.contains(":") && uri_sniff_rx.matches(str)
}

///|
/// Percent-encodes a URI component (Ruby `CGI.escapeURIComponent`).
pub fn encode_uri_component(str : String) -> String {
  let sb = StringBuilder()
  let hex = "0123456789ABCDEF"
  let bytes = @utf8.encode(str)
  for b in bytes {
    let c = b.to_int()
    if (c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') ||
      (c >= '0' && c <= '9') ||
      c == '-' ||
      c == '.' ||
      c == '_' ||
      c == '~' {
      sb.write_char(c.unsafe_to_char())
    } else {
      sb.write_char('%')
      sb.write_char(hex[c >> 4].to_int().unsafe_to_char())
      sb.write_char(hex[c & 15].to_int().unsafe_to_char())
    }
  }
  sb.to_string()
}

///|
/// Replaces spaces with `%20`.
pub fn encode_spaces_in_uri(str : String) -> String {
  if str.contains(" ") {
    str.replace_all(old=" ", new="%20")
  } else {
    str
  }
}

///|
/// Removes the file extension (Ruby `Helpers.rootname`).
pub fn rootname(filename : String) -> String {
  match filename.rev_find(".") {
    Some(i) =>
      if @rb.index_of(filename, "/", from=i) is Some(_) {
        filename
      } else {
        @rb.slice(filename, 0, i)
      }
    None => filename
  }
}

///|
/// Last path segment, optionally without extension (Ruby `Helpers.basename`).
pub fn basename(filename : String, drop_ext? : Bool = false) -> String {
  // File.basename strips all trailing slashes; a path of only slashes is "/"
  let mut trimmed = filename
  while trimmed.length() > 1 && trimmed.has_suffix("/") {
    trimmed = @rb.chop(trimmed)
  }
  if trimmed == "/" {
    return trimmed
  }
  let base = match trimmed.rev_find("/") {
    Some(i) => @rb.from(trimmed, i + 1)
    None => trimmed
  }
  if drop_ext {
    let ext = extname(base, fallback="")
    if ext != "" && ext != base {
      @rb.slice(base, 0, base.length() - ext.length())
    } else {
      base
    }
  } else {
    base
  }
}

///|
/// Directory part of a path (Ruby `File.dirname`).
pub fn dirname(path : String) -> String {
  let p = if path.length() > 1 && path.has_suffix("/") {
    @rb.chop(path)
  } else {
    path
  }
  match p.rev_find("/") {
    Some(0) => "/"
    Some(i) => @rb.slice(p, 0, i)
    None => "."
  }
}

///|
/// Whether the path has a file extension.
pub fn has_extname(path : String) -> Bool {
  match path.rev_find(".") {
    Some(i) => @rb.index_of(path, "/", from=i) is None
    None => false
  }
}

///|
/// The file extension including the dot, or `fallback`.
pub fn extname(path : String, fallback? : String = "") -> String {
  match path.rev_find(".") {
    Some(i) =>
      if @rb.index_of(path, "/", from=i) is Some(_) {
        fallback
      } else {
        @rb.from(path, i)
      }
    None => fallback
  }
}

///|
/// Ruby `Helpers.roman_to_int`.
pub fn roman_to_int(val : String) -> Int {
  let value = fn(c : Char) -> Int {
    match c {
      'I' => 1
      'V' => 5
      'X' => 10
      'L' => 50
      'C' => 100
      'D' => 500
      'M' => 1000
      _ => 0
    }
  }
  let vals = val.to_array().map(value)
  let mut result = 0
  for i, v in vals {
    if i + 1 < vals.length() && vals[i + 1] > v {
      result -= v
    } else {
      result += v
    }
  }
  result
}

///|
/// Joins a path onto a base (Ruby `File.join`).
fn file_join(a : String, b : String) -> String {
  if a == "" {
    b
  } else if a.has_suffix("/") {
    a + b
  } else {
    a + "/" + b
  }
}

///|
/// Expands `path` against `cwd` (Ruby `File.expand_path`, no symlinks).
pub fn expand_path_from(cwd : String, path : String) -> String {
  let full = if path.has_prefix("/") { path } else { file_join(cwd, path) }
  let segs = []
  for s in @rb.split(full, "/") {
    if s == "" || s == "." {
      continue
    } else if s == ".." {
      segs.pop() |> ignore
    } else {
      segs.push(s)
    }
  }
  "/" + segs.join("/")
}

///|
/// Base64 encodes bytes (Ruby `[data].pack 'm0'`).
pub fn base64_encode(data : Bytes) -> String {
  let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  let sb = StringBuilder()
  let n = data.length()
  let mut i = 0
  while i + 2 < n {
    let v = (data[i].to_int() << 16) |
      (data[i + 1].to_int() << 8) |
      data[i + 2].to_int()
    sb.write_char(chars[(v >> 18) & 63].to_int().unsafe_to_char())
    sb.write_char(chars[(v >> 12) & 63].to_int().unsafe_to_char())
    sb.write_char(chars[(v >> 6) & 63].to_int().unsafe_to_char())
    sb.write_char(chars[v & 63].to_int().unsafe_to_char())
    i += 3
  }
  if n - i == 1 {
    let v = data[i].to_int() << 16
    sb.write_char(chars[(v >> 18) & 63].to_int().unsafe_to_char())
    sb.write_char(chars[(v >> 12) & 63].to_int().unsafe_to_char())
    sb.write_string("==")
  } else if n - i == 2 {
    let v = (data[i].to_int() << 16) | (data[i + 1].to_int() << 8)
    sb.write_char(chars[(v >> 18) & 63].to_int().unsafe_to_char())
    sb.write_char(chars[(v >> 12) & 63].to_int().unsafe_to_char())
    sb.write_char(chars[(v >> 6) & 63].to_int().unsafe_to_char())
    sb.write_char('=')
  }
  sb.to_string()
}

// ---------------------------------------------------------------------------
// AbstractNode path / asset helpers

///|
/// Ruby `icon_uri(name)`.
pub fn Node::icon_uri(self : Node, name : String) -> String {
  let doc = self.document()
  let icon = if self.has_attr("icon") {
    let icon = self.attr("icon").unwrap_or("")
    if has_extname(icon) {
      icon
    } else {
      "\{icon}.\{doc.attr("icontype", default="png").unwrap_or("png")}"
    }
  } else {
    "\{name}.\{doc.attr("icontype", default="png").unwrap_or("png")}"
  }
  self.image_uri(icon, asset_dir_key=Some("iconsdir"))
}

///|
/// Ruby `image_uri(target, asset_dir_key)`.
pub fn Node::image_uri(
  self : Node,
  target_image : String,
  asset_dir_key? : String? = Some("imagesdir"),
) -> String {
  let doc = self.document()
  let images_base = match asset_dir_key {
    Some(k) => self.attr(k, inherited=true)
    None => None
  }
  if doc.safe() < SAFE_SECURE && doc.has_attr("data-uri") {
    if is_uriish(target_image) {
      let t = encode_spaces_in_uri(target_image)
      return t
    }
    match images_base {
      Some(base) if is_uriish(base) =>
        return self.normalize_web_path(
          target_image,
          start=base,
          preserve_uri_target=false,
        )
      _ => ()
    }
    self.generate_data_uri(target_image, asset_dir_key?)
  } else {
    self.normalize_web_path(target_image, start?=images_base)
  }
}

///|
/// Ruby `media_uri(target, asset_dir_key)`.
pub fn Node::media_uri(
  self : Node,
  target : String,
  asset_dir_key? : String? = Some("imagesdir"),
) -> String {
  let base = match asset_dir_key {
    Some(k) => self.attr(k, inherited=true)
    None => None
  }
  self.normalize_web_path(target, start?=base)
}

///|
/// Ruby `generate_data_uri(target_image, asset_dir_key)`.
pub fn Node::generate_data_uri(
  self : Node,
  target_image : String,
  asset_dir_key? : String,
) -> String {
  let ext = extname(target_image, fallback="")
  let mimetype = if ext == "" {
    "application/octet-stream"
  } else if ext == ".svg" {
    "image/svg+xml"
  } else {
    "image/\{@rb.from(ext, 1)}"
  }
  let image_path = match asset_dir_key {
    Some(k) =>
      self.normalize_system_path(
        target_image,
        start?=self.attr(k, inherited=true),
        target_name="image",
      )
    None => self.normalize_system_path(target_image)
  }
  match self.document().vfs().read(image_path) {
    Some(data) => "data:\{mimetype};base64,\{base64_encode(data)}"
    None => {
      log_warn("image to embed not found or not readable: \{image_path}")
      "data:\{mimetype};base64,"
    }
  }
}

///|
/// Ruby `normalize_asset_path`.
pub fn Node::normalize_asset_path(
  self : Node,
  asset_ref : String,
  asset_name? : String = "path",
  autocorrect? : Bool = true,
) -> String {
  let doc = self.document()
  doc
  .path_resolver()
  .system_path(
    Some(asset_ref),
    start=doc.base_dir(),
    target_name=asset_name,
    recover=autocorrect,
  ) catch {
    SecurityError(msg) => abort(msg)
  }
}

///|
/// Ruby `normalize_system_path(target, start, jail, opts)` (recovering mode).
pub fn Node::normalize_system_path(
  self : Node,
  target : String,
  start? : String,
  jail? : String,
  target_name? : String = "path",
) -> String {
  self.normalize_system_path_checked(target, start?, jail?, target_name~) catch {
    SecurityError(msg) => {
      log_error(msg)
      target
    }
  }
}

///|
/// Like `normalize_system_path` but raises on jail violations when `recover` is false.
pub fn Node::normalize_system_path_checked(
  self : Node,
  target : String,
  start? : String,
  jail? : String,
  target_name? : String = "path",
  recover? : Bool = true,
) -> String raise SecurityError {
  let doc = self.document()
  let pr = doc.path_resolver()
  let mut start = start
  let mut jail = jail
  if doc.safe() < SAFE_SAFE {
    start = match start {
      Some(s) =>
        if pr.is_root(s) {
          Some(s)
        } else {
          Some(file_join(doc.base_dir(), s))
        }
      None => Some(doc.base_dir())
    }
  } else {
    if start is None {
      start = Some(doc.base_dir())
    }
    if jail is None {
      jail = Some(doc.base_dir())
    }
  }
  pr.system_path(Some(target), start?, jail?, target_name~, recover~)
}

///|
/// Ruby `normalize_web_path(target, start, preserve_uri_target)`.
pub fn Node::normalize_web_path(
  self : Node,
  target : String,
  start? : String,
  preserve_uri_target? : Bool = true,
) -> String {
  if preserve_uri_target && is_uriish(target) {
    encode_spaces_in_uri(target)
  } else {
    self.document().path_resolver().web_path(target, start?)
  }
}

///|
/// Reads an asset from the VFS (Ruby `read_asset`).
pub fn Node::read_asset(
  self : Node,
  path : String,
  normalize? : Bool = false,
  warn_on_failure? : Bool = false,
  label? : String = "file",
) -> String? {
  let doc = self.document()
  match doc.vfs().read(path) {
    Some(data) => {
      let text = decode_text(data)
      if normalize {
        Some(prepare_source_string(text).join("\n"))
      } else {
        Some(text)
      }
    }
    None => {
      if warn_on_failure {
        log_warn(
          "\{doc.attributes.str("docfile").unwrap_or("<stdin>")}: \{label} does not exist or cannot be read: \{path}",
        )
      }
      None
    }
  }
}

///|
/// Reads contents of a local target (URIs are not supported by the pure core).
pub fn Node::read_contents(
  self : Node,
  target : String,
  start? : String,
  normalize? : Bool = false,
  warn_on_failure? : Bool = true,
  warn_if_empty? : Bool = false,
  label? : String = "asset",
) -> String? {
  let doc = self.document()
  let web_start = match start {
    Some(s) if is_uriish(s) => true
    _ => false
  }
  if is_uriish(target) || web_start {
    let t = if web_start {
      doc.path_resolver().web_path(target, start?)
    } else {
      target
    }
    if doc.has_attr("allow-uri-read") {
      match doc.vfs().read(t) {
        Some(data) => {
          let text = decode_text(data)
          return Some(
            if normalize {
              prepare_source_string(text).join("\n")
            } else {
              text
            },
          )
        }
        None => {
          if warn_on_failure {
            log_warn("could not retrieve contents of \{label} at URI: \{t}")
          }
          return None
        }
      }
    } else {
      if warn_on_failure {
        log_warn(
          "cannot retrieve contents of \{label} at URI: \{t} (allow-uri-read attribute not enabled)",
        )
      }
      return None
    }
  }
  let target = self.normalize_system_path(target, start?, target_name=label)
  let contents = self.read_asset(target, normalize~, warn_on_failure~, label~)
  match contents {
    Some(c) if warn_if_empty && c == "" =>
      log_warn("contents of \{label} is empty: \{target}")
    _ => ()
  }
  contents
}
