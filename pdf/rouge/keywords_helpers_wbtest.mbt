///|
/// Compare a builtin table of a ported lexer (`name`: lua, php or matlab;
/// `module_`: the table's module, empty for MATLAB's single set) with
/// Rouge's words, in full.
fn check_keywords(
  name : String,
  module_ : String,
  expected : String,
) -> Unit raise {
  let words : Array[String] = match name {
    "lua" | "php" => {
      let table = if name == "lua" { lua_builtins } else { php_builtins }
      match table.iter().find_first(e => e.0 == module_) {
        Some(entry) => entry.1.copy()
        None => fail("\{name}: no module \{module_}")
      }
    }
    "matlab" => matlab_builtins.iter().collect()
    _ => fail("no keyword table \{name}")
  }
  // Ruby sorts by bytes: code unit order here (the words are ASCII)
  words.sort_by((a, b) => {
    let n = if a.length() < b.length() { a.length() } else { b.length() }
    for i in 0..<n {
      if a[i] != b[i] {
        return a[i].compare(b[i])
      }
    }
    a.length().compare(b.length())
  })
  let got = words.join(" ")
  if got != expected {
    fail("\{name} \{module_}: the words differ from Rouge's")
  }
}
