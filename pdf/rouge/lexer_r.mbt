///|
/// R's keywords (Rouge's `R::KEYWORDS`).
let r_keywords : Array[String] = words(
  "if else for while repeat in next break function",
)

///|
/// Rouge's `R::KEYWORD_CONSTANTS`.
let r_keyword_constants : Array[String] = words(
  (
    #|NULL Inf TRUE FALSE NaN NA
    #|NA_integer_ NA_real_ NA_complex_ NA_character_
  ),
)

///|
/// Rouge's `R::BUILTIN_CONSTANTS`.
let r_builtin_constants : Array[String] = words(
  "LETTERS letters month.abb month.name pi T F",
)

///|
/// The functions in `base` that are implemented as a `.Primitive`, minus
/// those that are also keywords (Rouge's `R::PRIMITIVE_FUNCTIONS`).
let r_primitive_functions : Array[String] = words(
  (
    #|abs acos acosh all any anyNA Arg as.call as.character
    #|as.complex as.double as.environment as.integer as.logical
    #|as.null.default as.numeric as.raw asin asinh atan atanh attr
    #|attributes baseenv browser c call ceiling class Conj cos cosh
    #|cospi cummax cummin cumprod cumsum digamma dim dimnames
    #|emptyenv exp expression floor forceAndCall gamma gc.time
    #|globalenv Im interactive invisible is.array is.atomic is.call
    #|is.character is.complex is.double is.environment is.expression
    #|is.finite is.function is.infinite is.integer is.language
    #|is.list is.logical is.matrix is.na is.name is.nan is.null
    #|is.numeric is.object is.pairlist is.raw is.recursive is.single
    #|is.symbol lazyLoadDBfetch length lgamma list log max min
    #|missing Mod names nargs nzchar oldClass on.exit pos.to.env
    #|proc.time prod quote range Re rep retracemem return round
    #|seq_along seq_len seq.int sign signif sin sinh sinpi sqrt
    #|standardGeneric substitute sum switch tan tanh tanpi tracemem
    #|trigamma trunc unclass untracemem UseMethod xtfrm
  ),
)

///|
/// Rouge's `R` (lexers/r.rb).
pub fn r(options : Map[String, String]) -> Lexer {
  let lx = Lexer::new("r", options~)
  lx.state("root", fn(s) {
    s.rule("#'.*?$", "Comment.Doc")
    s.rule("#.*?$", "Comment.Single")
    s.rule("\\s+", "Text.Whitespace", flags="m")
    s.rule("`[^`]+?`", "Name")
    s.rule("'(\\\\.|.)*?'", "Literal.String.Single", flags="m")
    s.rule("\"(\\\\.|.)*?\"", "Literal.String.Double", flags="m")
    s.rule("%[^%]*?%", "Operator")
    s.rule("0[xX][a-fA-F0-9]+([pP][0-9]+)?[Li]?", "Literal.Number.Hex")
    s.rule(
      "[+-]?(\\d+([.]\\d+)?|[.]\\d+)([eE][+-]?\\d+)?[Li]?", "Literal.Number",
    )
    // Only recognize built-in functions when they are actually used as a
    // function call, i.e. followed by an opening parenthesis.
    // `Name::Builtin` would be more logical, but is usually not
    // highlighted specifically; thus use `Name::Function`.
    s.rule("\\b(?<!.)(\{alt(r_primitive_functions)})(?=\\()", "Name.Function")
    s.call("(?:(?:[[:alpha:]]|[.][._[:alpha:]])[._[:alnum:]]*)|[.]", fn(lx, m) {
      let name = m.matched()
      if r_keywords.contains(name) {
        lx.token("Keyword")
      } else if r_keyword_constants.contains(name) {
        lx.token("Keyword.Constant")
      } else if r_builtin_constants.contains(name) {
        lx.token("Name.Builtin")
      } else {
        lx.token("Name")
      }
    })
    s.rule("[\\[\\]{}();,]", "Punctuation")
    s.rule("[-<>?*+^/!=~$@:%&|]", "Operator")
  })
  lx
}
