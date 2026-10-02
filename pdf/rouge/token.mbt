///|
// Rouge's token types (lib/rouge/token.rb) are named here by their
// qualified names, `Name.Function`, `Literal.String.Double`; the table of
// them is generated (tokens_data.mbt).

///|
let shortnames : Map[String, String] = {
  let m = Map([])
  for entry in token_table {
    m[entry.0] = entry.1
  }
  m
}

///|
/// The short name of a token type (`nf` for `Name.Function`), as Rouge's
/// HTML formatter uses it for CSS classes.
pub fn shortname(tok : String) -> String? {
  shortnames.get(tok)
}

///|
/// Whether `tok` is a token type of Rouge.
pub fn is_token(tok : String) -> Bool {
  shortnames.contains(tok)
}

///|
/// The parent of a token type (`Name` for `Name.Function`), None for a
/// top-level one.
pub fn token_parent(tok : String) -> String? {
  match tok.rev_find(".") {
    Some(i) => Some(tok.unsafe_substring(start=0, end=i))
    None => None
  }
}
