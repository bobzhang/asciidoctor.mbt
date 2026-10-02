///|
/// The lexers of the scripting languages group (see `lexer_list`).
let script_lexers : Array[(String, Array[String], LexerFactory)] = [
  ("php", ["php", "php3", "php4", "php5"], php),
  ("python", ["py"], python),
  ("lua", [], lua),
  ("perl", ["pl"], perl),
  ("markdown", ["md", "mkd"], markdown),
  ("elixir", ["elixir", "exs"], elixir),
  ("r", ["r", "R", "s", "S"], r),
  ("haskell", ["hs"], haskell),
  ("matlab", ["m"], matlab),
]
