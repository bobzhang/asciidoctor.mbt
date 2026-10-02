///|
// Rouge's guessing of a lexer from the source (Lexer.guess with
// `source:` and `mimetype:`, lib/rouge/guesser.rb and guessers/): over every
// lexer Rouge has (`lexer_table`, generated from Rouge, in Rouge's order),
// the mimetype guesser, the modeline guesser (vim and emacs modelines in the
// first and last five lines) and the source guesser (each lexer's own
// `detect?`, ported below for the 38 lexers that have one). A guess may
// name a lexer that is not ported; the lexers of this package that guess
// (markdown's fences) then fall back to plain text.

///|
/// Rouge's `TextAnalyzer#shebang`: what follows `#!` on the first line.
fn shebang(text : String) -> String? {
  compile("\\A\\s*#!(.*)$", "").find(text).bind(m => m.group(1))
}

///|
/// Rouge's `TextAnalyzer#shebang?`: whether the shebang names `name` (a
/// regex source, as Ruby interpolates it into `/\b#{name}(\s|$)/`).
fn shebang_is(text : String, name : String) -> Bool {
  match shebang(text) {
    Some(line) => compile("\\b\{name}(\\s|$)", "").find(line) is Some(_)
    None => false
  }
}

///|
/// Rouge's `TextAnalyzer#doctype`.
fn doctype(text : String) -> String? {
  compile(
    (
      #|\A\s*
      #|        (?:<\?.*?\?>\s*)? # possible <?xml...?> tag
      #|        <!DOCTYPE\s+(.+?)>
      #|
    ),
    "xm",
  )
  .find(text)
  .bind(m => m.group(1))
}

///|
/// Rouge's `TextAnalyzer#doctype?(type)`: the doctype matches `pattern`.
fn doctype_is(text : String, pattern : String, flags? : String = "") -> Bool {
  match doctype(text) {
    Some(d) => search(d, pattern, flags~)
    None => false
  }
}

///|
/// `text =~ /pattern/flags`.
fn search(text : String, pattern : String, flags? : String = "") -> Bool {
  compile(pattern, flags).find(text) is Some(_)
}

///|
/// Rouge's `detect?` of the lexer `tag`, for the lexers that have one.
fn detect(tag : String, text : String) -> Bool {
  let sh = (name : String) => shebang_is(text, name)
  match tag {
    "awk" => sh("awk")
    "xml" =>
      !doctype_is(text, "html") &&
      (search(text, "\\A<\\?xml\\b") || doctype(text) is Some(_))
    "biml" => search(text, "<\\s*Biml\\b")
    "coffeescript" => sh("coffee")
    "crystal" => sh("crystal")
    "python" => sh(rx("pythonw?(?:[23](?:\\.\\d+)?)?"))
    "diff" =>
      text.has_prefix("Index: ") ||
      search(text, "\\Adiff[^\\n]*?\\ba/[^\\n]*\\bb/") ||
      search(text, "---.*?\\n[+][+][+]") ||
      search(text, "[+][+][+].*?\\n---")
    "yaml" => search(text, "\\A\\s*%YAML", flags="m")
    "factor" => sh("factor")
    "gherkin" => sh("cucumber")
    "groovy" => sh(rx("groovy"))
    "php" =>
      if sh("php") {
        true
      } else if search(text, "^<\\?hh") {
        false
      } else {
        search(text, "^<\\?php")
      }
    "hack" =>
      search(text, "<\\?hh") ||
      sh("hhvm") ||
      search(text, "async function [a-zA-Z]") ||
      search(text, "\\): Awaitable<")
    "haskell" => sh("runhaskell")
    "haxe" => sh("haxe")
    "html" =>
      doctype_is(text, "\\bhtml\\b", flags="i") ||
      (!search(text, "\\A<\\?xml\\b") && search(text, "<\\s*html\\b"))
    "io" => sh("io")
    "ruby" => sh("ruby")
    "javascript" => sh("node") || sh("jsc")
    "julia" => sh("julia")
    "lasso" => sh("lasso9") || search(text, "\\A.*?<\\?(lasso(script)?|=)")
    "livescript" => sh("lsc")
    "lua" => sh("lua")
    "moonscript" => sh("moon")
    "mosel" => search(text, "^\\s*(model|package)\\s+")
    "perl" => sh("perl")
    "postscript" => search(text, "^%!")
    "praat" => sh("praat")
    "puppet" => sh("puppet-apply") || sh("puppet")
    "r" => sh("Rscript")
    "racket" =>
      match compile("\\A#lang\\s*(.*?)$", "").find(text).bind(m => m.group(1)) {
        Some(lang) => search(lang, "racket|scribble")
        None => false
      }
    "rust" => sh("rustc")
    "sed" => sh("sed")
    "shell" => sh(rx("(ba|z|k)?sh"))
    "solidity" => text.has_prefix("pragma solidity")
    "tcl" => sh("tclsh") || sh("wish") || sh("jimsh")
    "tex" =>
      search(
        text, "\\A\\s*\\\\(documentclass|input|documentstyle|relax|ProvidesPackage|ProvidesClass)",
      )
    "tulip" => sh("tulip")
    _ => false
  }
}

///|
/// Rouge's modelines (guessers/modeline.rb).
let modelines : Array[(String, String)] = [
  (
    "-\\*-\\s*(?:(?!mode)[\\w-]+\\s*:\\s*(?:[\\w+-]+)\\s*;?\\s*)*(?:mode\\s*:)?\\s*([\\w+-]+)\\s*(?:;\\s*(?!mode)[\\w-]+\\s*:\\s*[\\w+-]+\\s*)*;?\\s*-\\*-",
    "i",
  ),
  ("(?:vim|vi|ex):\\s*(?:ft|filetype|syntax)=(\\w+)\\s?", "i"),
  (
    "(?:vim|vi|Vim|ex):\\s*se(?:t)?.*\\s(?:ft|filetype|syntax)=(\\w+)\\s?.*:", "i",
  ),
]

///|
/// Rouge's `SourceNormalizer`: no BOM, `\n` line ends.
fn normalize_source(source : String) -> String {
  let source = if source.has_prefix("\u{feff}") {
    source[1:].to_owned()
  } else {
    source
  }
  source.replace_all(old="\r\n", new="\n")
}

///|
/// Rouge's `Lexer.guess(source:, mimetype:)`: the tags of the lexers left —
/// none when nothing narrowed the choice down (Rouge then answers plain
/// text), several when it is ambiguous (Rouge raises `Ambiguous`, whose
/// alternatives are in this order).
pub fn guess(source : String?, mimetype? : String) -> Array[String] {
  let all = lexer_table
  let mut lexers = all
  let narrow = (next : Array[(String, Array[String], Array[String], Bool)]) => {
    if !next.is_empty() {
      lexers = next
    }
  }
  match mimetype {
    Some(mt) => narrow(lexers.filter(l => l.2.contains(mt)))
    None => ()
  }
  match source {
    Some(source) => {
      let text = normalize_source(source)
      // modeline
      if lexers.length() != 1 {
        let lines = text.split("\n").map(l => l.to_owned()).collect()
        while lines.last() is Some("") {
          ignore(lines.pop())
        }
        let n = lines.length()
        let head = lines[:if n < 5 { n } else { 5 }].to_owned()
        let tail = lines[if n > 5 { n - 5 } else { 0 }:].to_owned()
        let space = [..head, ..tail].join("\n")
        let names : Set[String] = Set([])
        for modeline in modelines {
          match compile(modeline.0, modeline.1).find(space) {
            Some(m) => names.add(m.group(1).unwrap_or(""))
            None => ()
          }
        }
        if names.length() > 0 {
          narrow(
            lexers.filter(l => {
              names.contains(l.0) || l.1.iter().any(a => names.contains(a))
            }),
          )
        }
      }
      // source
      if lexers.length() != 1 {
        narrow(lexers.filter(l => l.3 && detect(l.0, text)))
      }
    }
    None => ()
  }
  if lexers.length() < all.length() {
    lexers.map(l => l.0)
  } else {
    []
  }
}
