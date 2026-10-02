///|
/// The keywords of `batchfile` (Batchfile.keywords).
let batchfile_keywords : Set[String] = word_set(
  "if else for in do goto call exit",
)

///|
/// The operator words of `batchfile` (Batchfile.operator_words).
let batchfile_operator_words : Set[String] = word_set(
  "exist defined errorlevel cmdextversion not equ neq lss leq gtr geq",
)

///|
/// The device names of `batchfile` (Batchfile.devices).
let batchfile_devices : Set[String] = word_set(
  (
    #|con prn aux nul com1 com2 com3 com4 com5 com6 com7 com8 com9 lpt1 lpt2
    #|lpt3 lpt4 lpt5 lpt6 lpt7 lpt8 lpt9
  ),
)

///|
/// The builtin commands of `batchfile` (Batchfile.builtin_commands).
let batchfile_builtin_commands : Set[String] = word_set(
  (
    #|assoc attrib break bcdedit cacls cd chcp chdir chkdsk chkntfs choice
    #|cls cmd color comp compact convert copy date del dir diskpart doskey
    #|dpath driverquery echo endlocal erase fc find findstr format fsutil
    #|ftype gpresult graftabl help icacls label md mkdir mklink mode more
    #|move openfiles path pause popd print prompt pushd rd recover ren
    #|rename replace rmdir robocopy setlocal sc schtasks shift shutdown sort
    #|start subst systeminfo takeown tasklist taskkill time timeout title
    #|tree type ver verify vol xcopy waitfor wmic
  ),
)

///|
/// The other commands of `batchfile` (Batchfile.other_commands).
let batchfile_other_commands : Set[String] = word_set(
  (
    #|addusers admodcmd ansicon arp at bcdboot bitsadmin browstat certreq
    #|certutil change cidiag cipher cleanmgr clip cmdkey compress convertcp
    #|coreinfo csccmd csvde cscript curl debug defrag delprof deltree devcon
    #|diamond dirquota diruse diskshadow diskuse dism dnscmd dsacls dsadd
    #|dsget dsquery dsmod dsmove dsrm dsmgmt dsregcmd edlin eventcreate
    #|expand extract fdisk fltmc forfiles freedisk ftp getmac gpupdate
    #|hostname ifmember inuse ipconfig kill lgpo lodctr logman logoff
    #|logtime makecab mapisend mbsacli mem mountvol moveuser msg mshta
    #|msiexec msinfo32 mstsc nbtstat net net1 netdom netsh netstat nlsinfo
    #|nltest now nslookup ntbackup ntdsutil ntoskrnl ntrights nvspbind
    #|pathping perms ping portqry powercfg pngout pnputil printbrm prncnfg
    #|prnmngr procdump psexec psfile psgetsid psinfo pskill pslist
    #|psloggedon psloglist pspasswd psping psservice psshutdown pssuspend
    #|qbasic qgrep qprocess query quser qwinsta rasdial reg reg1 regdump
    #|regedt32 regsvr32 regini reset restore rundll32 rmtshare route rpcping
    #|run runas scandisk setspn setx sfc share shellrunas shortcut sigcheck
    #|sleep slmgr strings subinacl sysmon telnet tftp tlist touch tracerpt
    #|tracert tscon tsdiscon tskill tttracer typeperf tzutil undelete
    #|unformat verifier vmconnect vssadmin w32tm wbadmin wecutil wevtutil
    #|wget where whoami windiff winrm winrs wpeutil wpr wusa wuauclt wscript
  ),
)

///|
/// The attributes of `batchfile` (Batchfile.attributes).
let batchfile_attributes : Set[String] = word_set(
  "on off disable enableextensions enabledelayedexpansion",
)

///|
/// Rouge's `Batchfile` (lexers/batchfile.rb): Windows batch files.
pub fn batchfile(options : Map[String, String]) -> Lexer {
  let lx = Lexer::new("batchfile", options~)
  lx.state("basic", fn(s) {
    // Comments
    s.rule("@?\\brem\\b.*$", "Comment", flags="i")
    // Empty Labels
    s.rule("^::.*$", "Comment")
    // Labels
    s.rule(":[a-z]+", "Name.Label", flags="i")
    s.call(
      "([a-z]\\w*)(\\.exe|com|bat|cmd|msi)?",
      fn(lx, m) {
        let word = group_text(m, 1)
        if batchfile_devices.contains(word) {
          lx.groups(["Keyword.Reserved", "Error"])
        } else if batchfile_keywords.contains(word) {
          lx.groups(["Keyword", "Error"])
        } else if batchfile_operator_words.contains(word) {
          lx.groups(["Operator.Word", "Error"])
        } else if batchfile_builtin_commands.contains(word) ||
          batchfile_other_commands.contains(word) {
          lx.token("Name.Builtin")
        } else if batchfile_attributes.contains(word) {
          lx.groups(["Name.Attribute", "Error"])
        } else {
          // `"set".casecmp m[1]` is an integer, always true: Rouge never
          // reaches its `token Text` branch
          lx.groups(["Keyword.Declaration", "Error"])
        }
      },
      flags="i",
    )
    s.rule("((?:[\\/\\+]|--?)[a-z]+)\\s*", "Name.Attribute", flags="i")
    s.mix_in("expansions")
    s.rule("[<>&|(){}\\[\\]\\-+=;,~?*]", "Operator")
  })
  lx.state("escape", fn(s) {
    s.rule("\\^.", "Literal.String.Escape", flags="m")
  })
  lx.state("expansions", fn(s) {
    // Normal and Delayed expansion
    s.rule("[%!]+([a-z_$@#]+)[%!]+", "Name.Variable", flags="i")
    // For Variables
    s.rule("(\\%+~?[a-z]+\\d?)", "Name.Variable.Magic", flags="i")
  })
  lx.state("double_quotes", fn(s) {
    s.mix_in("escape")
    s.rule("[\"]", "Literal.String.Double", next="#pop")
    s.mix_in("expansions")
    s.rule("[^\\^\"%!]+", "Literal.String.Double")
  })
  lx.state("single_quotes", fn(s) {
    s.mix_in("escape")
    s.rule("[']", "Literal.String.Single", next="#pop")
    s.mix_in("expansions")
    s.rule("[^\\^'%!]+", "Literal.String.Single")
  })
  lx.state("backtick", fn(s) {
    s.mix_in("escape")
    s.rule("[`]", "Literal.String.Backtick", next="#pop")
    s.mix_in("expansions")
    s.rule("[^\\^`%!]+", "Literal.String.Backtick")
  })
  lx.state("data", fn(s) {
    s.rule("\\s+", "Text")
    s.rule("0x[0-9a-f]+", "Literal.Number.Hex", flags="i")
    s.rule("[0-9]", "Literal.Number")
    s.rule("[\"]", "Literal.String.Double", next="double_quotes")
    s.rule("[']", "Literal.String.Single", next="single_quotes")
    s.rule("[`]", "Literal.String.Backtick", next="backtick")
    s.rule("[^\\s&|()\\[\\]{}\\^=;!%+\\-,\"'`~?*]+", "Text")
    s.mix_in("escape")
  })
  lx.state("root", fn(s) {
    s.mix_in("basic")
    s.mix_in("data")
  })
  lx
}
