///|
// Image targets as asciidoctor-pdf resolves them (its `Asciidoctor::Image`
// extension and `resolve_image_path`): a data URI carries the image
// itself, anything else is a path whose extension (or `format`) names the
// format.

///|
/// An image target: a path, or the bytes of a data URI.
priv enum ImageTarget {
  Path(String)
  Data(Bytes)
}

///|
/// `Asciidoctor::Image.target_and_format`: a data URI
/// (`data:image/<fmt>;base64,<data>`, `jpg` read as `jpeg` and `svg+xml` as
/// `svg`) decoded, else the target and the `format` attribute or its
/// lowercased extension ("" when it has none).
fn image_target_and_format(
  target : String,
  format : String?,
) -> (ImageTarget, String) {
  if target.has_prefix("data:image/") {
    let rest = target["data:image/".length():].to_owned()
    match rest.find(";base64,") {
      Some(i) => {
        let fmt = rest[:i].to_owned()
        if fmt
          is ("png"
          | "jpg"
          | "jpeg"
          | "gif"
          | "pdf"
          | "bmp"
          | "tiff"
          | "svg+xml") {
          let fmt = match fmt {
            "jpg" => "jpeg"
            "svg+xml" => "svg"
            f => f
          }
          return (Data(@svg.decode_base64(rest[i + 8:])), fmt)
        }
      }
      None => ()
    }
  }
  let format = match format {
    Some(f) => f
    None => {
      let ext = @core.extname(target, fallback="")
      if ext.length() > 1 {
        ext[1:].to_owned().to_lower()
      } else {
        ""
      }
    }
  }
  (Path(target), format)
}

///|
/// The bytes of an image target; a path is resolved against `start` (the
/// images directory) in the document's jail. Also the path, for messages
/// (the target itself for a data URI).
fn load_image_target(
  node : @core.Node,
  target : ImageTarget,
  start? : String,
) -> (Bytes?, String) {
  match target {
    Data(bytes) => (Some(bytes), "")
    Path(p) => {
      let path = node.normalize_system_path(p, start?)
      (node.vfs().read(path), path)
    }
  }
}
