///|
/// The cmdlet binding attributes of `powershell` (Powershell::ATTRIBUTES).
let powershell_attributes : Array[String] = words(
  (
    #|ConfirmImpact DefaultParameterSetName HelpURI PositionalBinding
    #|SupportsPaging SupportsShouldProcess
  ),
)

///|
/// The automatic variables of `powershell` (Powershell::AUTO_VARS).
let powershell_auto_vars : String = alt(
  words(
    (
      #|\$\$ \$\? \$\^ \$_
      #|\$args \$ConsoleFileName \$Error \$Event \$EventArgs \$EventSubscriber
      #|\$ExecutionContext \$false \$foreach \$HOME \$Host \$input \$IsCoreCLR
      #|\$IsLinux \$IsMacOS \$IsWindows \$LastExitCode \$Matches \$MyInvocation
      #|\$NestedPromptLevel \$null \$PID \$PROFILE \$PSBoundParameters \$PSCmdlet
      #|\$PSCommandPath \$PSCulture \$PSDebugContext \$PSHOME \$PSItem
      #|\$PSScriptRoot \$PSSenderInfo \$PSUICulture \$PSVersionTable \$PWD
      #|\$REPORTERRORSHOWEXCEPTIONCLASS \$REPORTERRORSHOWINNEREXCEPTION
      #|\$REPORTERRORSHOWSOURCE \$REPORTERRORSHOWSTACKTRACE
      #|\$SENDER \$ShellId \$StackTrace \$switch \$this \$true
    ),
  ),
)

///|
/// The reserved words of `powershell` (Powershell::KEYWORDS).
let powershell_keywords : String = alt(
  words(
    (
      #|assembly exit process base filter public begin finally return break for
      #|sequence catch foreach static class from switch command function throw
      #|configuration hidden trap continue if try data in type define
      #|inlinescript until do interface using dynamicparam module var else
      #|namespace while elseif parallel workflow end param enum private
    ),
  ),
)

///|
/// The operators of `powershell` (Powershell::OPERATORS).
let powershell_operators : String = alt(
  words(
    (
      #|-split -isplit -csplit -join -is -isnot -as -eq -ieq -ceq -ne -ine -cne
      #|-gt -igt -cgt -ge -ige -cge -lt -ilt -clt -le -ile -cle -like -ilike
      #|-clike -notlike -inotlike -cnotlike -match -imatch -cmatch -notmatch
      #|-inotmatch -cnotmatch -contains -icontains -ccontains -notcontains
      #|-inotcontains -cnotcontains -replace -ireplace -creplace -shl -shr -band
      #|-bor -bxor -and -or -xor -not \+= -= \*= \/= %=
    ),
  ),
)

///|
/// The comment-based help keywords of `powershell`
/// (Powershell::MULTILINE_KEYWORDS).
let powershell_multiline_keywords : String = alt(
  words(
    (
      #|synopsis description parameter example inputs outputs notes link
      #|component role functionality forwardhelptargetname forwardhelpcategory
      #|remotehelprunspace externalhelp
    ),
  ),
)

///|
/// Rouge's `Powershell` (lexers/powershell.rb).
pub fn powershell(options : Map[String, String]) -> Lexer {
  let lx = Lexer::new("powershell", options~)
  lx.state("variable", fn(s) {
    s.rule(powershell_auto_vars, "Name.Builtin.Pseudo")
    s.call("(\\$)(?:(\\w+)(:))?(\\w+|\\{(?:[^`]|`.)+?\\})", fn(lx, _) {
      lx.groups([
        "Name.Variable", "Name.Namespace", "Punctuation", "Name.Variable",
      ])
    })
    s.rule("\\$\\w+", "Name.Variable")
    s.rule("\\$\\{(?:[^`]|`.)+?\\}", "Name.Variable")
  })
  lx.state("multiline", fn(s) {
    s.rule(
      "\\.(?:\{powershell_multiline_keywords})",
      "Comment.Special",
      flags="i",
    )
    s.rule("#>", "Comment.Multiline", next="#pop")
    s.rule("[^#.]+?", "Comment.Multiline", flags="m")
    s.rule("[#.]+", "Comment.Multiline")
  })
  lx.state("interpol", fn(s) {
    s.rule("\\)", "Literal.String.Interpol", next="#pop")
    s.mix_in("root")
  })
  lx.state("dq", fn(s) {
    // NB: "abc$" is literally the string abc$.
    // Here we prevent :interp from interpreting $" as a variable.
    s.rule("(?:\\$#?)?\"", "Literal.String.Double", next="#pop")
    s.rule("\\$\\(", "Literal.String.Interpol", next="interpol")
    s.rule("`$", "Literal.String.Escape") // line continuation
    s.rule("`.", "Literal.String.Escape")
    s.rule("[^\"`$]+", "Literal.String.Double")
    s.mix_in("variable")
  })
  lx.state("sq", fn(s) {
    s.rule("'", "Literal.String.Single", next="#pop")
    s.rule("[^']+", "Literal.String.Single")
  })
  lx.state("heredoc", fn(s) {
    s.rule("(?:\\$#?)?\"@", "Literal.String.Heredoc", next="#pop")
    s.rule("\\$\\(", "Literal.String.Interpol", next="interpol")
    s.rule("`$", "Literal.String.Escape") // line continuation
    s.rule("`.", "Literal.String.Escape")
    s.rule("[^\"`$]+?", "Literal.String.Heredoc", flags="m")
    s.rule("\"+", "Literal.String.Heredoc")
    s.mix_in("variable")
  })
  lx.state("class", fn(s) {
    s.rule("\\{", "Punctuation", next="#pop")
    s.rule("\\s+", "Text.Whitespace")
    s.rule("\\w+", "Name.Class")
    s.rule("[:,]", "Punctuation")
  })
  lx.state("expr", fn(s) {
    s.mix_in("comments")
    s.rule("\"", "Literal.String.Double", next="dq")
    s.rule("'", "Literal.String.Single", next="sq")
    s.rule("@\"", "Literal.String.Heredoc", next="heredoc")
    s.rule("@'.*?'@", "Literal.String.Heredoc", flags="m")
    s.rule("\\d*\\.\\d+", "Literal.Number.Float")
    s.rule("\\d+", "Literal.Number.Integer")
    s.rule("@\\{", "Punctuation", next="hasht")
    s.rule("@\\(", "Punctuation", next="array")
    s.rule("{", "Punctuation", next="brace")
    s.rule("\\[", "Punctuation", next="bracket")
  })
  lx.state("hasht", fn(s) {
    s.rule("\\}", "Punctuation", next="#pop")
    s.rule("=", "Operator")
    s.rule("[,;]", "Punctuation")
    s.mix_in("expr")
    s.rule("\\w+", "Name.Other")
    s.mix_in("variable")
  })
  lx.state("array", fn(s) {
    s.rule("\\s+", "Text.Whitespace")
    s.rule("\\)", "Punctuation", next="#pop")
    s.rule("[,;]", "Punctuation")
    s.mix_in("expr")
    s.mix_in("variable")
  })
  lx.state("brace", fn(s) {
    s.rule("[}]", "Punctuation", next="#pop")
    s.mix_in("root")
  })
  lx.state("bracket", fn(s) {
    s.rule("\\]", "Punctuation", next="#pop")
    s.rule("[A-Za-z]\\w+\\.", "Name")
    s.call("([A-Za-z]\\w+)", fn(lx, m) {
      if powershell_attributes.contains(m.matched()) {
        lx.token("Name.Builtin.Pseudo")
      } else {
        lx.token("Name")
      }
    })
    s.mix_in("root")
  })
  lx.state("parameters", fn(s) {
    s.rule("`.", "Literal.String.Escape", flags="m")
    s.rule("\\s*?\\n", "Text.Whitespace", next="#pop")
    s.rule("[;(){}\\]]", "Punctuation", next="#pop")
    s.rule("[|=]", "Operator", next="#pop")
    s.rule("[\\/\\\\~\\w][-.:\\/\\\\~\\w]*", "Name.Other")
    s.rule("\\w[-\\w]+", "Name.Other")
    s.mix_in("root")
  })
  lx.state("comments", fn(s) {
    s.rule("\\s+", "Text.Whitespace")
    s.rule("#.*", "Comment")
    s.rule("<#", "Comment.Multiline", next="multiline")
  })
  lx.state("root", fn(s) {
    s.mix_in("comments")
    s.rule("#requires\\s-version \\d(?:\\.\\d+)?", "Comment.Preproc")
    s.rule("\\.\\.(?=\\.?\\d)", "Operator")
    s.rule("(?:\{powershell_operators})\\b", "Operator", flags="i")
    s.call(
      "(class)(\\s+)(\\w+)",
      fn(lx, _) {
        lx.groups(["Keyword.Reserved", "Text.Whitespace", "Name.Class"])
        lx.push("class")
      },
      flags="i",
    )
    s.call(
      "(function)(\\s+)(?:(\\w+)(:))?(\\w[-\\w]+)",
      fn(lx, _) {
        lx.groups([
          "Keyword.Reserved", "Text.Whitespace", "Name.Namespace", "Punctuation",
          "Name.Function",
        ])
      },
      flags="i",
    )
    s.rule(
      "(?:\{powershell_keywords})\\b(?![-.])",
      "Keyword.Reserved",
      flags="i",
    )
    s.rule("-{1,2}\\w+", "Name.Tag")
    s.call("(\\.)?([-\\w]+)(\\[)", fn(lx, _) {
      lx.groups(["Operator", "Name", "Punctuation"])
      lx.push("bracket")
    })
    s.call(
      "([\\/\\\\~[a-z]][-.:\\/\\\\~\\w]*)(\\n)?",
      fn(lx, _) {
        lx.groups(["Name", "Text.Whitespace"])
        lx.push("parameters")
      },
      flags="i",
    )
    s.call("(\\.)([-\\w]+)(?:(\\()|(\\n))?", fn(lx, m) {
      lx.groups(["Operator", "Name.Function", "Punctuation", "Text.Whitespace"])
      if m.group(3) is Some(_) {
        lx.push("parameters")
      }
    })
    s.rule("\\?", "Name.Function", next="parameters")
    s.mix_in("expr")
    s.mix_in("variable")
    s.rule("[-+*\\/%=!.&|]", "Operator")
    s.rule("[{}(),:;]", "Punctuation")
  })
  lx
}
