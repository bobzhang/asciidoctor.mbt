///|
/// Rouge's `Go` (lexers/go.rb). Its regex constants are kept as sources
/// (with their flags where they have some) and interpolated with `rx`.
pub fn go(options : Map[String, String]) -> Lexer {
  let lx = Lexer::new("go", options~)
  // Characters
  let white_space = "\\s+"
  let newline = "\\n"
  let unicode_char = "[^\\n]"
  let unicode_letter = "[[:alpha:]]"
  let unicode_digit = "[[:digit:]]"
  // Letters and digits
  let letter = "\{rx(unicode_letter)}|_"
  let decimal_digit = "[0-9]"
  let octal_digit = "[0-7]"
  let hex_digit = "[0-9A-Fa-f]"
  // Comments
  let line_comment = "\\/\\/(?:(?!\{rx(newline)}).)*"
  let general_comment = "\\/\\*(?:(?!\\*\\/).)*\\*\\/" // m
  let comment = "\{rx(line_comment)}|\{rx(general_comment, flags="m")}"
  // Keywords
  let keyword =
    #|\b(?:
    #|                                 break       | default     | func
    #|                               | interface   | select      | case
    #|                               | defer       | go          | map
    #|                               | struct      | chan        | else
    #|                               | goto        | package     | switch
    #|                               | const       | fallthrough | if
    #|                               | range       | type        | continue
    #|                               | for         | import      | return
    #|                               | var
    #|                               )\b
  // x
  // Identifiers
  let identifier = " (?!\{rx(keyword, flags="x")})\n                                 \{rx(letter)}(?:\{rx(letter)}|\{rx(unicode_digit)})* " // x
  // Operators and delimiters
  let operator =
    #| \+=    | \+\+   | \+     | &\^=   | &\^
    #|                               | &=     | &&     | &      | ==     | =
    #|                               | \!=    | \!     | -=     | --     | -
    #|                               | \|=    | \|\|   | \|     | <=     | <-
    #|                               | <<=    | <<     | <      | \*=    | \*
    #|                               | \^=    | \^     | >>=    | >>     | >=
    #|                               | >      | \/     | \/=    | :=     | %
    #|                               | %=     | \.\.\. | \.     | :
    #|
  // x
  let separator =
    #| \(     | \)     | \[     | \]     | \{
    #|                               | \}     | ,      | ;
    #|
  // x
  // Integer literals
  let decimal_lit = "[0-9]\{rx(decimal_digit)}*"
  let octal_lit = "0\{rx(octal_digit)}*"
  let hex_lit = "0[xX]\{rx(hex_digit)}+"
  let int_lit = "\{rx(hex_lit)}|\{rx(decimal_lit)}|\{rx(octal_lit)}"
  // Floating-point literals
  let decimals = "\{rx(decimal_digit)}+"
  let exponent = "[eE][+\\-]?\{rx(decimals)}"
  let float_lit = " \{rx(decimals)} \\. \{rx(decimals)}? \{rx(exponent)}?\n                               | \{rx(decimals)} \{rx(exponent)}\n                               | \\. \{rx(decimals)} \{rx(exponent)}?\n                               " // x
  // Imaginary literals
  let imaginary_lit = "(?:\{rx(decimals)}|\{rx(float_lit, flags="x")})i"
  // Rune literals
  let escaped_char = "\\\\[abfnrtv\\\\'\"]"
  let little_u_value = "\\\\u\{rx(hex_digit)}{4}"
  let big_u_value = "\\\\U\{rx(hex_digit)}{8}"
  let unicode_value = " \{rx(unicode_char)} | \{rx(little_u_value)}\n                               | \{rx(big_u_value)}  | \{rx(escaped_char)}\n                               " // x
  let octal_byte_value = "\\\\\{rx(octal_digit)}{3}"
  let hex_byte_value = "\\\\x\{rx(hex_digit)}{2}"
  let byte_value = "\{rx(octal_byte_value)}|\{rx(hex_byte_value)}"
  let char_lit = "'(?:\{rx(unicode_value, flags="x")}|\{rx(byte_value)})'"
  let escape_sequence = " \{rx(escaped_char)}\n                               | \{rx(little_u_value)}\n                               | \{rx(big_u_value)}\n                               | \{rx(hex_byte_value)}\n                               " // x
  // Predeclared identifiers
  let predeclared_types =
    #|\b(?:
    #|                                 bool       | byte       | complex64
    #|                               | complex128 | error      | float32
    #|                               | float64    | int8       | int16
    #|                               | int32      | int64      | int
    #|                               | rune       | string     | uint8
    #|                               | uint16     | uint32     | uint64
    #|                               | uintptr    | uint
    #|                               )\b
  // x
  let predeclared_constants = "\\b(?:true|false|iota|nil)\\b"
  let predeclared_functions =
    #|\b(?:
    #|                                 append  | cap     | close   | complex
    #|                               | copy    | delete  | imag    | len
    #|                               | make    | new     | panic   | print
    #|                               | println | real    | recover
    #|                               )\b
  // x
  lx.state("simple_tokens", fn(s) {
    s.rule(comment, "Comment")
    s.rule(keyword, "Keyword", flags="x")
    s.rule(predeclared_types, "Keyword.Type", flags="x")
    s.rule(predeclared_functions, "Name.Builtin", flags="x")
    s.rule(predeclared_constants, "Name.Constant")
    s.rule(imaginary_lit, "Literal.Number")
    s.rule(float_lit, "Literal.Number", flags="x")
    s.rule(int_lit, "Literal.Number")
    s.rule(char_lit, "Literal.String.Char")
    s.rule(operator, "Operator", flags="x")
    s.rule(separator, "Punctuation", flags="x")
    s.rule(identifier, "Name", flags="x")
    s.rule(white_space, "Text")
  })
  lx.state("root", fn(s) {
    s.mix_in("simple_tokens")
    s.rule("`", "Literal.String", next="raw_string")
    s.rule("\"", "Literal.String", next="interpreted_string")
  })
  lx.state("interpreted_string", fn(s) {
    s.rule(escape_sequence, "Literal.String.Escape", flags="x")
    s.rule("\\\\.", "Error")
    s.rule("\"", "Literal.String", next="#pop")
    s.rule("[^\"\\\\]+", "Literal.String")
  })
  lx.state("raw_string", fn(s) {
    s.rule("`", "Literal.String", next="#pop")
    s.rule("[^`]+", "Literal.String", flags="m")
  })
  lx
}
