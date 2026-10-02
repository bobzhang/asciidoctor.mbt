///|
/// The keywords of `shell` (Shell::KEYWORDS).
let shell_keywords : String = alt(
  words(
    (
      #|if fi else while do done for then return function
      #|select continue until esac elif in
    ),
  ),
)

///|
/// The builtins of `shell` (Shell::BUILTINS).
let shell_builtins : String = alt(
  words(
    (
      #|alias bg bind break builtin caller cd command compgen
      #|complete declare dirs disown enable eval exec exit
      #|export false fc fg getopts hash help history jobs let
      #|local logout mapfile popd pushd pwd read readonly set
      #|shift shopt source suspend test time times trap true type
      #|typeset ulimit umask unalias unset wait
      #|
      #|cat tac nl od base32 base64 fmt pr fold head tail split csplit
      #|wc sum cksum b2sum md5sum sha1sum sha224sum sha256sum sha384sum
      #|sha512sum sort shuf uniq comm ptx tsort cut paste join tr expand
      #|unexpand ls dir vdir dircolors cp dd install mv rm shred link ln
      #|mkdir mkfifo mknod readlink rmdir unlink chown chgrp chmod touch
      #|df du stat sync truncate echo printf yes expr tee basename dirname
      #|pathchk mktemp realpath pwd stty printenv tty id logname whoami
      #|groups users who date arch nproc uname hostname hostid uptime chcon
      #|runcon chroot env nice nohup stdbuf timeout kill sleep factor numfmt
      #|seq tar grep sudo awk sed gzip gunzip
    ),
  ),
)

///|
/// Rouge's `Shell` (lexers/shell.rb): sh, bash, zsh and ksh.
pub fn shell(options : Map[String, String]) -> Lexer {
  let lx = Lexer::new("shell", options~)
  // the terminator of the heredoc being lexed (escaped)
  let mut heredocstr = ""
  lx.state("basic", fn(s) {
    s.rule("#.*$", "Comment")
    s.rule("\\b(\{shell_keywords})\\s*\\b", "Keyword")
    s.rule("\\bcase\\b", "Keyword", next="case")
    s.rule("\\b(\{shell_builtins})\\s*\\b(?!(\\.|-))", "Name.Builtin")
    s.rule("[.](?=\\s)", "Name.Builtin")
    s.call("(\\b\\w+)(=)", fn(lx, _) {
      lx.groups(["Name.Variable", "Operator"])
    })
    s.rule("[\\[\\]{}()!=>]", "Operator")
    s.rule("&&|\\|\\|", "Operator")
    // here-string
    s.rule("<<<", "Operator")
    s.call("(<<-?)(\\s*)(['\"]?)(\\\\?)(\\w+)(\\3)", fn(lx, m) {
      lx.groups([
        "Operator", "Text", "Literal.String.Heredoc", "Literal.String.Heredoc", "Name.Constant",
        "Literal.String.Heredoc",
      ])
      heredocstr = rx_escape(group_text(m, 5))
      lx.push("heredoc")
    })
  })
  lx.state("heredoc", fn(s) {
    s.rule("\\n", "Literal.String.Heredoc", next="heredoc_nl")
    s.rule("[^$\\n\\\\]+", "Literal.String.Heredoc")
    s.mix_in("interp")
    s.rule("[$]", "Literal.String.Heredoc")
  })
  lx.state("heredoc_nl", fn(s) {
    s.call("\\s*(\\w+)\\s*\\n", fn(lx, m) {
      if group_text(m, 1) == heredocstr {
        lx.token("Name.Constant")
        lx.pop(times=2)
      } else {
        lx.token("Literal.String.Heredoc")
      }
    })
    s.call("", fn(lx, _) { lx.pop() })
  })
  lx.state("double_quotes", fn(s) {
    // NB: "abc$" is literally the string abc$.
    // Here we prevent :interp from interpreting $" as a variable.
    s.rule("(?:\\$#?)?\"", "Literal.String.Double", next="#pop")
    s.mix_in("interp")
    s.rule("[^\"`\\\\$]+", "Literal.String.Double")
  })
  lx.state("ansi_string", fn(s) {
    s.rule("\\\\.", "Literal.String.Escape")
    s.rule("[^\\\\']+", "Literal.String.Single")
    s.mix_in("single_quotes")
  })
  lx.state("single_quotes", fn(s) {
    s.rule("'", "Literal.String.Single", next="#pop")
    s.rule("[^']+", "Literal.String.Single")
  })
  lx.state("data", fn(s) {
    s.rule("\\s+", "Text")
    s.rule("\\\\.", "Literal.String.Escape")
    s.rule("\\$?\"", "Literal.String.Double", next="double_quotes")
    s.rule("\\$'", "Literal.String.Single", next="ansi_string")
    // single quotes are much easier than double quotes - we can literally
    // just scan until the next single quote
    s.rule("'", "Literal.String.Single", next="single_quotes")
    s.rule("\\*", "Keyword")
    s.rule(";", "Punctuation")
    s.rule("--?[\\w-]+", "Name.Tag")
    s.rule("[^=\\*\\s{}()$\"'`;\\\\<]+", "Text")
    s.rule("\\d+(?= |\\Z)", "Literal.Number")
    s.rule("<", "Text")
    s.mix_in("interp")
  })
  lx.state("curly", fn(s) {
    s.rule("}", "Keyword", next="#pop")
    s.rule(":-", "Keyword")
    s.rule("[a-zA-Z0-9_]+", "Name.Variable")
    s.rule("[^}:\"`'$]+", "Punctuation")
    s.mix_in("root")
  })
  // the state inside $(...)
  lx.state("paren_interp", fn(s) {
    s.rule("\\)", "Literal.String.Interpol", next="#pop")
    s.rule("\\(", "Operator", next="paren_inner")
    s.mix_in("root")
  })
  // used to balance parentheses inside interpolation
  lx.state("paren_inner", fn(s) {
    s.rule("\\(", "Operator", next="#push")
    s.rule("\\)", "Operator", next="#pop")
    s.mix_in("root")
  })
  lx.state("math", fn(s) {
    s.rule("\\)\\)", "Keyword", next="#pop")
    s.rule("[-+*/%^|&!]|\\*\\*|\\|\\|", "Operator")
    s.rule("\\d+(#\\w+)?", "Literal.Number")
    s.mix_in("root")
  })
  lx.state("case", fn(s) {
    s.rule("\\besac\\b", "Keyword", next="#pop")
    s.rule("\\|", "Punctuation")
    s.rule("\\)", "Punctuation", next="case_stanza")
    s.mix_in("root")
  })
  lx.state("case_stanza", fn(s) {
    s.rule(";;", "Punctuation", next="#pop")
    s.mix_in("root")
  })
  lx.state("backticks", fn(s) {
    s.rule("`", "Literal.String.Backtick", next="#pop")
    s.mix_in("root")
  })
  lx.state("interp", fn(s) {
    s.rule("\\\\$", "Literal.String.Escape") // line continuation
    s.rule("\\\\.", "Literal.String.Escape")
    s.rule("\\$\\(\\(", "Keyword", next="math")
    s.rule("\\$\\(", "Literal.String.Interpol", next="paren_interp")
    s.rule("\\${#?", "Keyword", next="curly")
    s.rule("`", "Literal.String.Backtick", next="backticks")
    s.rule("\\$#?(\\w+|.)", "Name.Variable")
    s.rule("\\$[*@]", "Name.Variable")
  })
  lx.state("root", fn(s) {
    s.mix_in("basic")
    s.mix_in("data")
  })
  lx
}
