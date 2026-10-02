///|
/// Rouge's `Cpp.keywords`: C's and C++'s.
let cpp_keywords : Set[String] = c_keywords.union(
  word_set(
    (
      #|asm auto catch char8_t concept
      #|consteval constexpr constinit const_cast co_await co_return co_yield
      #|delete dynamic_cast explicit export friend
      #|mutable namespace new operator private protected public
      #|reinterpret_cast requires restrict size_of static_cast this throw throws
      #|typeid typename using virtual final override
      #|
      #|alignas alignof decltype noexcept static_assert
      #|thread_local try
    ),
  ),
)

///|
/// Rouge's `Cpp.keywords_type`.
let cpp_keywords_type : Set[String] = c_keywords_type.union(word_set("bool"))

///|
/// Rouge's `Cpp.reserved`.
let cpp_reserved : Set[String] = c_reserved.union(
  word_set(
    (
      #|__virtual_inheritance __uuidof __super __single_inheritance
      #|__multiple_inheritance __interface __event
    ),
  ),
)

///|
/// Rouge's `Cpp` (lexers/cpp.rb), a `C` lexer.
pub fn cpp(options : Map[String, String]) -> Lexer {
  let lx = Lexer::new("cpp", options~)
  lx.set_fresh(fn() { cpp(Map([])) })
  c_states(lx, cpp_keywords, cpp_keywords_type, cpp_reserved, Set([]))
  let id = rx("[a-zA-Z_][a-zA-Z0-9_]*")
  lx.prepend("root", fn(s) {
    // Offload C++ extensions, http://offload.codeplay.com/
    s.rule("(?:__offload|__blockingoffload|__outer)\\b", "Keyword.Pseudo")
  })
  // digits with optional inner quotes
  // see www.open-std.org/jtc1/sc22/wg21/docs/papers/2013/n3781.pdf
  let dq = rx("\\d('?\\d)*")
  lx.prepend("statements", fn(s) {
    s.rule("(class|struct)\\b", "Keyword", next="classname")
    s.rule("template\\b", "Keyword", next="template")
    s.rule(
      "\{dq}(\\.\{dq})?(?:y|d|h|(?:min)|s|(?:ms)|(?:us)|(?:ns)|i|(?:if)|(?:il))\\b",
      "Literal.Number.Other",
    )
    s.rule(
      "(\{dq}[.]\{dq}?|[.]\{dq})(e[+-]?\{dq}[lu]*)?",
      "Literal.Number.Float",
      flags="i",
    )
    s.rule("\{dq}e[+-]?\{dq}[lu]*", "Literal.Number.Float", flags="i")
    s.rule("0x\\h('?\\h)*[lu]*", "Literal.Number.Hex", flags="i")
    s.rule("0b[01]+('[01]+)*", "Literal.Number.Bin")
    s.rule("0[0-7]('?[0-7])*[lu]*", "Literal.Number.Oct", flags="i")
    s.rule("\{dq}[lu]*", "Literal.Number.Integer", flags="i")
    s.rule("\\bnullptr\\b", "Name.Builtin")
    s.rule(
      "(?:u8|u|U|L)?R\"([a-zA-Z0-9_{}\\[\\]#<>%:;.?*\\+\\-\\/\\^&|~!=,\"']{,16})\\(.*?\\)\\1\"",
      "Literal.String",
      flags="m",
    )
    s.rule("(::|<=>)", "Operator")
    s.rule("[{}]", "Punctuation")
  })
  lx.state("classname", fn(s) {
    s.rule(id, "Name.Class", next="#pop")
    // template specification
    s.mix_in("whitespace")
    s.rule("[.]{3}", "Operator")
    s.rule(",", "Punctuation", next="#pop")
    s.call("", fn(lx, _) { lx.pop() })
  })
  lx.state("template", fn(s) {
    s.rule("[>;]", "Punctuation", next="#pop")
    s.rule("typename\\b", "Keyword", next="classname")
    s.mix_in("statements")
  })
  lx.state("case", fn(s) {
    s.rule(":(?!:)", "Punctuation", next="#pop")
    s.mix_in("statements")
  })
  lx
}
