///|
/// The lexers of the C family group (see `lexer_list`).
let c_lexers : Array[(String, Array[String], LexerFactory)] = [
  ("c", [], c),
  ("cpp", ["c++"], cpp),
  ("d", ["dlang"], d),
  ("go", ["go", "golang"], go),
  (
    "rust",
    [
      "rs", "rust,no_run", "rs,no_run", "rust,ignore", "rs,ignore", "rust,should_panic",
      "rs,should_panic",
    ],
    rust,
  ),
  ("csharp", ["c#", "cs"], csharp),
  ("kotlin", [], kotlin),
  ("scala", ["scala"], scala),
  ("groovy", [], groovy),
  ("gradle", [], gradle),
  ("swift", [], swift),
  ("protobuf", ["proto"], protobuf),
  ("dart", [], dart),
]
