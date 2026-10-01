///|
test "link targets compare as ascii uris whichever way they were stored" {
  // pagelayout's percent-encoded form, Prawn's raw UTF-8 (text links) and
  // its UTF-16 text string (image links) all mean the same URI
  let encoded = b"https://example.org/caf%C3%A9"
  let raw = b"https://example.org/caf\xC3\xA9"
  let utf16 = Bytes::from_array(
    [
      b'\xFE',
      b'\xFF',
      ..b"https://example.org/caf".to_array().map(b => [b'\x00', b]).flatten(),
      b'\x00',
      b'\xE9',
    ],
  )
  inspect(uri_text(encoded), content="https://example.org/caf%C3%A9")
  inspect(uri_text(raw), content="https://example.org/caf%C3%A9")
  inspect(uri_text(utf16), content="https://example.org/caf%C3%A9")
  // escapes are kept, a stray percent sign and a space are encoded
  inspect(uri_text(b"http://x/a%20b 100%"), content="http://x/a%20b%20100%25")
}
