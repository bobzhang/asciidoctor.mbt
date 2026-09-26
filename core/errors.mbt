///|
/// Raised by the public API when it is given invalid arguments (Ruby
/// `ArgumentError`).
pub(all) suberror ArgumentError {
  ArgumentError(String)
}

///|
pub impl Show for ArgumentError with fn output(self, logger) {
  let ArgumentError(msg) = self
  logger.write_string(msg)
}

///|
/// Raised when a document cannot be processed.
pub(all) suberror ProcessingError {
  /// No converter is registered for the backend (Ruby raises
  /// `NotImplementedError`).
  MissingConverter(String)
  /// A converter aborted the conversion (Ruby raises a `RuntimeError`), e.g.
  /// the manpage converter for a document whose doctype is not `manpage`.
  ConversionFailed(String)
}

///|
/// The message Ruby Asciidoctor uses for the error.
pub fn ProcessingError::message(self : ProcessingError) -> String {
  match self {
    MissingConverter(backend) =>
      "asciidoctor: FAILED: missing converter for backend '\{backend}'. Processing aborted."
    ConversionFailed(msg) => msg
  }
}

///|
pub impl Show for ProcessingError with fn output(self, logger) {
  logger.write_string(self.message())
}

///|
/// Aborts the processing of the document `self` belongs to with `error` (Ruby:
/// raising from a converter or an extension). The pure pipeline cannot unwind
/// through converters and extension callbacks, so the error is recorded on the
/// root document (the first error wins) and processing continues; its output
/// must be discarded. `@asciidoctor.convert` raises the recorded error, and
/// `processing_error` returns it.
pub fn Node::abort_processing(self : Node, error : Error) -> Unit {
  let root = self.root_document()
  guard root.doc_ is Some(dd) else { return }
  if dd.error is None {
    dd.error = Some(error)
  }
}

///|
/// The error that aborted the processing of this document, if any (see
/// `abort_processing`). A document whose backend has no registered converter
/// reports `MissingConverter` right after it is created (and is not parsed).
pub fn Node::processing_error(self : Node) -> Error? {
  match self.root_document().doc_ {
    Some(dd) => dd.error
    None => None
  }
}

///|
/// The outermost document (nested AsciiDoc table cell documents point to
/// their parent document).
fn Node::root_document(self : Node) -> Node {
  let mut doc = self.document()
  while doc.doc_ is Some(dd) && dd.parent_document is Some(p) {
    doc = p.document()
  }
  doc
}
