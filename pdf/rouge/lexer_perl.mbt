///|
/// Rouge's `Perl` (lexers/perl.rb).
pub fn perl(options : Map[String, String]) -> Lexer {
  let lx = Lexer::new("perl", options~)
  let keywords = words(
    (
      #|case continue do else elsif for foreach if last my next our
      #|redo reset then unless until while use print new BEGIN CHECK
      #|INIT END return
    ),
  )
  let builtins = words(
    (
      #|abs accept alarm atan2 bind binmode bless caller chdir chmod
      #|chomp chop chown chr chroot close closedir connect continue cos
      #|crypt dbmclose dbmopen defined delete die dump each endgrent
      #|endhostent endnetent endprotoent endpwent endservent eof eval
      #|exec exists exit exp fcntl fileno flock fork format formline getc
      #|getgrent getgrgid getgrnam gethostbyaddr gethostbyname gethostent
      #|getlogin getnetbyaddr getnetbyname getnetent getpeername
      #|getpgrp getppid getpriority getprotobyname getprotobynumber
      #|getprotoent getpwent getpwnam getpwuid getservbyname getservbyport
      #|getservent getsockname getsockopt glob gmtime goto grep hex
      #|import index int ioctl join keys kill last lc lcfirst length
      #|link listen local localtime log lstat map mkdir msgctl msgget
      #|msgrcv msgsnd my next no oct open opendir ord our pack package
      #|pipe pop pos printf prototype push quotemeta rand read readdir
      #|readline readlink readpipe recv redo ref rename require reverse
      #|rewinddir rindex rmdir scalar seek seekdir select semctl semget
      #|semop send setgrent sethostent setnetent setpgrp setpriority
      #|setprotoent setpwent setservent setsockopt shift shmctl shmget
      #|shmread shmwrite shutdown sin sleep socket socketpair sort splice
      #|split sprintf sqrt srand stat study substr symlink syscall sysopen
      #|sysread sysseek system syswrite tell telldir tie tied time times
      #|tr truncate uc ucfirst umask undef unlink unpack unshift untie
      #|utime values vec wait waitpid wantarray warn write
    ),
  )
  let re_tok = "Literal.String.Regex"
  lx.state("balanced_regex", fn(s) {
    s.rule("/(\\\\[\\\\/]|[^/])*/[egimosx]*", re_tok, flags="m", next="#pop")
    s.rule("!(\\\\[\\\\!]|[^!])*![egimosx]*", re_tok, flags="m", next="#pop")
    s.rule(
      (
        #|\\(\\\\|[^\\])*\\[egimosx]*
      ),
      re_tok,
      flags="m",
      next="#pop",
    )
    s.rule("{(\\\\[\\\\}]|[^}])*}[egimosx]*", re_tok, next="#pop")
    s.rule("<(\\\\[\\\\>]|[^>])*>[egimosx]*", re_tok, next="#pop")
    s.rule(
      (
        #|\[(\\[\\\]]|[^\]])*\][egimosx]*
      ),
      re_tok,
      next="#pop",
    )
    s.rule(
      (
        #|\((\\[\\\)]|[^\)])*\)[egimosx]*
      ),
      re_tok,
      next="#pop",
    )
    s.rule("@(\\\\[\\\\@]|[^@])*@[egimosx]*", re_tok, next="#pop")
    s.rule("%(\\\\[\\\\%]|[^%])*%[egimosx]*", re_tok, next="#pop")
    s.rule(
      (
        #|\$(\\[\\\$]|[^\$])*\$[egimosx]*
      ),
      re_tok,
      next="#pop",
    )
  })
  lx.state("root", fn(s) {
    s.rule("#.*", "Comment.Single")
    s.rule("^=[a-zA-Z0-9]+\\s+.*?\\n=cut", "Comment.Multiline", flags="m")
    s.rule("(?:\{alt(keywords)})\\b", "Keyword")
    s.call("(format)(\\s+)([a-zA-Z0-9_]+)(\\s*)(=)(\\s*\\n)", fn(lx, _) {
      lx.groups(["Keyword", "Text", "Name", "Text", "Punctuation", "Text"])
      lx.push("format")
    })
    s.rule("(?:eq|lt|gt|le|ge|ne|not|and|or|cmp)\\b", "Operator.Word")
    // substitution/transliteration: balanced delimiters
    s.rule(
      (
        #|(?:s|tr|y){(\\\\|\\}|[^}])*}\s*
      ),
      re_tok,
      next="balanced_regex",
    )
    s.rule(
      (
        #|(?:s|tr|y)<(\\\\|\\>|[^>])*>\s*
      ),
      re_tok,
      next="balanced_regex",
    )
    s.rule(
      (
        #|(?:s|tr|y)\[(\\\\|\\\]|[^\]])*\]\s*
      ),
      re_tok,
      next="balanced_regex",
    )
    s.rule(
      (
        #|(?:s|tr|y)\((\\\\|\\\)|[^\)])*\)\s*
      ),
      re_tok,
      next="balanced_regex",
    )
    // substitution/transliteration: arbitrary non-whitespace delimiters
    s.rule(
      (
        #|(?:s|tr|y)\s*([^\w\s])((\\\\|\\\1)|[^\1])*?\1((\\\\|\\\1)|[^\1])*?\1[msixpodualngcr]*
      ),
      re_tok,
      flags="m",
    )
    s.rule(
      (
        #|(?:s|tr|y)\s+(\w)((\\\\|\\\1)|[^\1])*?\1((\\\\|\\\1)|[^\1])*?\1[msixpodualngcr]*
      ),
      re_tok,
      flags="m",
    )
    // matches: common case, m-optional
    s.rule(
      (
        #|m?/(\\\\|\\/|[^/\n])*/[msixpodualngc]*
      ),
      re_tok,
    )
    s.rule(
      (
        #|m(?=[/!\\{<\[\(@%\$])
      ),
      re_tok,
      next="balanced_regex",
    )
    // arbitrary non-whitespace delimiters
    s.rule(
      (
        #|m\s*([^\w\s])((\\\\|\\\1)|[^\1])*?\1[msixpodualngc]*
      ),
      re_tok,
      flags="m",
    )
    s.rule(
      (
        #|m\s+(\w)((\\\\|\\\1)|[^\1])*?\1[msixpodualngc]*
      ),
      re_tok,
      flags="m",
    )
    s.rule(
      (
        #|((?<==~)|(?<=\())\s*/(\\\\|\\/|[^/])*/[msixpodualngc]*
      ),
      re_tok,
      next="balanced_regex",
    )
    s.rule("\\s+", "Text")
    s.call(
      "(?=[a-z_]\\w*(\\s*#.*\\n)*\\s*=>)",
      fn(lx, _) { lx.push("fat_comma") },
      flags="i",
    )
    s.rule("(?:\{alt(builtins)})\\b", "Name.Builtin")
    s.rule(
      "((__(DIE|WARN)__)|(DATA|STD(IN|OUT|ERR)))\\b", "Name.Builtin.Pseudo",
    )
    s.rule(
      (
        #|<<([\'"]?)([a-zA-Z_][a-zA-Z0-9_]*)\1;?\n.*?\n\2\n
      ),
      "Literal.String",
      flags="m",
    )
    s.rule("(__(END|DATA)__)\\b", "Comment.Preproc", next="end_part")
    s.rule("\\$\\^[ADEFHILMOPSTWX]", "Name.Variable.Global")
    s.rule(
      (
        #|\$[\\"'\[\]&`+*.,;=%~?@$!<>(^\|\/_-](?!\w)
      ),
      "Name.Variable.Global",
    )
    s.rule(
      "[$@%&*][$@%&*#_]*(?=[a-z{\\[;])",
      "Name.Variable",
      flags="i",
      next="varname",
    )
    s.rule(
      (
        #|[-+\/*%=<>&^\|!\\~]=?
      ),
      "Operator",
    )
    s.rule("0_?[0-7]+(_[0-7]+)*", "Literal.Number.Oct")
    s.rule("0x[0-9A-Fa-f]+(_[0-9A-Fa-f]+)*", "Literal.Number.Hex")
    s.rule("0b[01]+(_[01]+)*", "Literal.Number.Bin")
    s.rule(
      "(\\d*(_\\d*)*\\.\\d+(_\\d*)*|\\d+(_\\d*)*\\.\\d+(_\\d*)*)(e[+-]?\\d+)?",
      "Literal.Number.Float",
      flags="i",
    )
    s.rule("\\d+(_\\d*)*e[+-]?\\d+(_\\d*)*", "Literal.Number.Float", flags="i")
    s.rule("\\d+(_\\d+)*", "Literal.Number.Integer")
    s.rule("'", "Punctuation", next="sq")
    s.rule("\"", "Punctuation", next="dq")
    s.rule("`", "Punctuation", next="bq")
    s.rule("<([^\\s>]+)>", re_tok)
    s.rule("(q|qq|qw|qr|qx)\\{", "Literal.String.Other", next="cb_string")
    s.rule("(q|qq|qw|qr|qx)\\(", "Literal.String.Other", next="rb_string")
    s.rule("(q|qq|qw|qr|qx)\\[", "Literal.String.Other", next="sb_string")
    s.rule("(q|qq|qw|qr|qx)<", "Literal.String.Other", next="lt_string")
    s.rule("(q|qq|qw|qr|qx)(\\W)(.|\\n)*?\\2", "Literal.String.Other")
    s.rule("package\\s+", "Keyword", next="modulename")
    s.rule("sub\\s+", "Keyword", next="funcname")
    s.rule(
      (
        #|\[\]|\*\*|::|<<|>>|>=|<=|<=>|={3}|!=|=~|!~|&&?|\|\||\.{1,3}
      ),
      "Operator",
    )
    s.rule(
      (
        #|[()\[\]:;,<>\/?{}]
      ),
      "Punctuation",
    )
    s.call("(?=\\w)", fn(lx, _) { lx.push("name") })
  })
  lx.state("format", fn(s) {
    s.rule("\\.\\n", "Literal.String.Interpol", next="#pop")
    s.rule(".*?\\n", "Literal.String.Interpol")
  })
  lx.state("fat_comma", fn(s) {
    s.rule("#.*", "Comment.Single")
    s.rule("\\w+", "Literal.String")
    s.rule("\\s+", "Text")
    s.rule("=>", "Operator", next="#pop")
  })
  lx.state("name_common", fn(s) {
    s.rule("\\w+::", "Name.Namespace")
    s.rule("[\\w:]+", "Name.Variable", next="#pop")
  })
  lx.state("varname", fn(s) {
    s.rule("\\s+", "Text")
    s.rule("[{\\[]", "Punctuation", next="#pop") // hash syntax
    s.rule("[),]", "Punctuation", next="#pop") // arg specifier
    s.rule("[;]", "Punctuation", next="#pop") // postfix
    s.mix_in("name_common")
  })
  lx.state("name", fn(s) {
    s.mix_in("name_common")
    s.rule("[A-Z_]+(?=[^a-zA-Z0-9_])", "Name.Constant", next="#pop")
    s.call("(?=\\W)", fn(lx, _) { lx.pop() })
  })
  lx.state("modulename", fn(s) {
    s.rule("[a-z_]\\w*", "Name.Namespace", flags="i", next="#pop")
  })
  lx.state("funcname", fn(s) {
    s.rule("[a-zA-Z_]\\w*[!?]?", "Name.Function")
    s.rule("\\s+", "Text")
    // argument declaration
    s.call("(\\([$@%]*\\))(\\s*)", fn(lx, _) {
      lx.groups(["Punctuation", "Text"])
    })
    s.rule(".*?{", "Punctuation", next="#pop")
    s.rule(";", "Punctuation", next="#pop")
  })
  lx.state("sq", fn(s) {
    s.rule("\\\\[\\\\']", "Literal.String.Escape")
    s.rule("[^\\\\']+", "Literal.String.Single")
    s.rule("'", "Punctuation", next="#pop")
    s.rule("\\\\", "Literal.String.Single")
  })
  lx.state("dq", fn(s) {
    s.mix_in("string_intp")
    s.rule("\\\\[\\\\tnrabefluLUE\"$@]", "Literal.String.Escape")
    s.rule("\\\\0\\d{2}", "Literal.String.Escape")
    s.rule("\\\\o\\{\\d+\\}", "Literal.String.Escape")
    s.rule("\\\\x\\h{2}", "Literal.String.Escape")
    s.rule("\\\\x\\{\\h+\\}", "Literal.String.Escape")
    s.rule("\\\\c.", "Literal.String.Escape")
    s.rule("\\\\N\\{[^\\}]+\\}", "Literal.String.Escape")
    s.rule("[^\\\\\"]+?", "Literal.String.Double")
    s.rule("\"", "Punctuation", next="#pop")
    s.rule("\\\\", "Literal.String.Escape")
  })
  lx.state("bq", fn(s) {
    s.mix_in("string_intp")
    s.rule("\\\\[\\\\tnr`]", "Literal.String.Escape")
    s.rule("[^\\\\`]+?", "Literal.String.Backtick")
    s.rule("`", "Punctuation", next="#pop")
  })
  for
    spec in [
      ("cb", "\\{", "\\}"),
      ("rb", "\\(", "\\)"),
      ("sb", "\\[", "\\]"),
      ("lt", "<", ">"),
    ] {
    let (name, open, close) = spec
    let tok = "Literal.String.Other"
    lx.state(name + "_string", fn(s) {
      s.rule("\\\\[\{open}\{close}\\\\]", tok)
      s.rule("\\\\", tok)
      s.call(open, fn(lx, _) {
        lx.token(tok)
        lx.push_self()
      })
      s.rule(close, tok, next="#pop")
      s.rule("[^\{open}\{close}\\\\]+", tok)
    })
  }
  lx.state("in_interp", fn(s) {
    s.rule("}", "Literal.String.Interpol", next="#pop")
    s.rule("\\s+", "Text")
    s.rule("[a-z_]\\w*", "Literal.String.Interpol", flags="i")
  })
  lx.state("string_intp", fn(s) {
    s.rule("[$@][{]", "Literal.String.Interpol", next="in_interp")
    s.rule("[$@][a-z_]\\w*", "Literal.String.Interpol", flags="i")
  })
  lx.state("end_part", fn(s) {
    // eat the rest of the stream
    s.rule(".+", "Comment.Preproc", flags="m", next="#pop")
  })
  lx
}
