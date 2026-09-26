///|
/// The context (kind) of a node. Mirrors the Ruby symbols (`:paragraph`, ...).
pub(all) enum Context {
  Document
  Section
  Preamble
  Paragraph
  Admonition
  Listing
  Literal
  Example
  Sidebar
  Quote
  Verse
  Open
  Pass
  Stem
  Image
  Audio
  Video
  ThematicBreak
  PageBreak
  FloatingTitle
  Toc
  Ulist
  Olist
  Dlist
  Colist
  ListItem
  Table
  TableCell
  TableColumn
  // inline contexts
  Anchor
  Break
  Button
  Callout
  Footnote
  Indexterm
  Kbd
  Menu
  Quoted
  // contexts used transiently by the parser
  Source
  FencedCode
  Comment
  Abstract
  PartIntro
  LatexMath
  AsciiMath
  Custom(String)
} derive(Eq, Hash, Debug)

///|
/// The Ruby name of the context (`:floating_title` → "floating_title").
pub fn Context::name(self : Context) -> String {
  match self {
    Document => "document"
    Section => "section"
    Preamble => "preamble"
    Paragraph => "paragraph"
    Admonition => "admonition"
    Listing => "listing"
    Literal => "literal"
    Example => "example"
    Sidebar => "sidebar"
    Quote => "quote"
    Verse => "verse"
    Open => "open"
    Pass => "pass"
    Stem => "stem"
    Image => "image"
    Audio => "audio"
    Video => "video"
    ThematicBreak => "thematic_break"
    PageBreak => "page_break"
    FloatingTitle => "floating_title"
    Toc => "toc"
    Ulist => "ulist"
    Olist => "olist"
    Dlist => "dlist"
    Colist => "colist"
    ListItem => "list_item"
    Table => "table"
    TableCell => "table_cell"
    TableColumn => "table_column"
    Anchor => "anchor"
    Break => "break"
    Button => "button"
    Callout => "callout"
    Footnote => "footnote"
    Indexterm => "indexterm"
    Kbd => "kbd"
    Menu => "menu"
    Quoted => "quoted"
    Source => "source"
    FencedCode => "fenced_code"
    Comment => "comment"
    Abstract => "abstract"
    PartIntro => "partintro"
    LatexMath => "latexmath"
    AsciiMath => "asciimath"
    Custom(s) => s
  }
}

///|
/// Parses a Ruby context name (Ruby `String#to_sym`).
pub fn Context::from_name(s : String) -> Context {
  match s {
    "document" => Document
    "section" => Section
    "preamble" => Preamble
    "paragraph" => Paragraph
    "admonition" => Admonition
    "listing" => Listing
    "literal" => Literal
    "example" => Example
    "sidebar" => Sidebar
    "quote" => Quote
    "verse" => Verse
    "open" => Open
    "pass" => Pass
    "stem" => Stem
    "image" => Image
    "audio" => Audio
    "video" => Video
    "thematic_break" => ThematicBreak
    "page_break" => PageBreak
    "floating_title" => FloatingTitle
    "toc" => Toc
    "ulist" => Ulist
    "olist" => Olist
    "dlist" => Dlist
    "colist" => Colist
    "list_item" => ListItem
    "table" => Table
    "table_cell" => TableCell
    "table_column" => TableColumn
    "anchor" => Anchor
    "break" => Break
    "button" => Button
    "callout" => Callout
    "footnote" => Footnote
    "indexterm" => Indexterm
    "kbd" => Kbd
    "menu" => Menu
    "quoted" => Quoted
    "source" => Source
    "fenced_code" => FencedCode
    "comment" => Comment
    "abstract" => Abstract
    "partintro" => PartIntro
    "latexmath" => LatexMath
    "asciimath" => AsciiMath
    _ => Custom(s)
  }
}

///|
/// How the content of a block is processed.
pub(all) enum ContentModel {
  Compound
  Simple
  Verbatim
  Raw
  Empty
  Skip
  Attributes // only used by block macro extension configs
} derive(Eq, Debug)

///|
pub fn ContentModel::name(self : ContentModel) -> String {
  match self {
    Compound => "compound"
    Simple => "simple"
    Verbatim => "verbatim"
    Raw => "raw"
    Empty => "empty"
    Skip => "skip"
    Attributes => "attributes"
  }
}

///|
/// A substitution step.
pub(all) enum Sub {
  SpecialCharacters
  Quotes
  Attributes
  Replacements
  Macros
  PostReplacements
  Callouts
  Highlight
} derive(Eq, Hash, Debug)

///|
pub fn Sub::name(self : Sub) -> String {
  match self {
    SpecialCharacters => "specialcharacters"
    Quotes => "quotes"
    Attributes => "attributes"
    Replacements => "replacements"
    Macros => "macros"
    PostReplacements => "post_replacements"
    Callouts => "callouts"
    Highlight => "highlight"
  }
}

///|
/// Safe mode levels (Ruby `SafeMode`).
pub const SAFE_UNSAFE : Int = 0

///|
pub const SAFE_SAFE : Int = 1

///|
pub const SAFE_SERVER : Int = 10

///|
pub const SAFE_SECURE : Int = 20

///|
/// Safe mode value for a (case-insensitive) name.
pub fn safe_mode_value_for_name(name : String) -> Int? {
  match @rb.downcase_ascii(name) {
    "unsafe" => Some(SAFE_UNSAFE)
    "safe" => Some(SAFE_SAFE)
    "server" => Some(SAFE_SERVER)
    "secure" => Some(SAFE_SECURE)
    _ => None
  }
}

///|
pub fn safe_mode_name_for_value(value : Int) -> String? {
  match value {
    0 => Some("unsafe")
    1 => Some("safe")
    10 => Some("server")
    20 => Some("secure")
    _ => None
  }
}

///|
/// A source location (Ruby `Reader::Cursor`).
pub(all) struct Cursor {
  file : String?
  dir : String?
  path : String?
  mut lineno : Int
} derive(Debug, Eq)

///|
pub fn Cursor::new(
  file? : String,
  dir? : String,
  path? : String,
  lineno? : Int = 1,
) -> Cursor {
  { file, dir, path, lineno, }
}

///|
pub fn Cursor::advance(self : Cursor, num : Int) -> Unit {
  self.lineno += num
}

///|
pub fn Cursor::dup(self : Cursor) -> Cursor {
  { file: self.file, dir: self.dir, path: self.path, lineno: self.lineno, }
}

///|
/// `path: line N` (Ruby `Cursor#line_info` / `to_s`).
pub fn Cursor::line_info(self : Cursor) -> String {
  "\{self.path.unwrap_or("")}: line \{self.lineno}"
}

///|
/// Whether a section is numbered, and if so whether like a chapter.
pub(all) enum Numbered {
  NotNumbered
  Numbered
  NumberedChapter
} derive(Eq, Debug)
