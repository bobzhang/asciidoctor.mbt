///|
/// The lexers of the shell and configuration group (see `lexer_list`).
let shell_lexers : Array[(String, Array[String], LexerFactory)] = [
  ("shell", ["bash", "zsh", "ksh", "sh"], shell),
  ("console", ["terminal", "shell_session", "shell-session"], console),
  ("irb", ["pry"], irb),
  ("irb_output", [], irb_output),
  ("yaml", ["yml"], yaml),
  ("sql", [], sql),
  ("apache", [], apache),
  ("properties", [], properties),
  ("ini", [], ini),
  ("toml", [], toml),
  ("docker", ["dockerfile", "Dockerfile"], docker),
  ("make", ["makefile", "mf", "gnumake", "bsdmake"], make),
  ("nginx", [], nginx),
  ("conf", ["config", "configuration"], conf),
  ("powershell", ["posh", "microsoftshell", "msshell"], powershell),
  ("batchfile", ["bat", "batch", "dosbatch", "winbatch"], batchfile),
]
