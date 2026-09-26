// Golden fixture runner: replays tests/golden/*.jsonl (harvested from the
// Ruby test suite) against the MoonBit port and reports parity in three
// categories: the parsed AST, the converted output and the log messages.
//
// Usage: moon run cmd/golden --target native -- [options] [files...]
//   -v                 print every failure (and skip reasons)
//   -t                 trace each record
//   -f <filter>        only replay tests whose name contains <filter>
//   -k <index>         only replay the record at this line index of each file
//   -n <count>         print at most <count> failures (default 20)
//   --prune-known      drop known-failure entries that now pass
//   --update-known     rewrite the known-failure list from the current failures
//                      (categories are kept; new entries get "uncategorized")
//   --update-counts    rewrite tests/golden/record_counts.txt
//
// Harvested records use placeholders for machine-specific paths ($ROOT for
// the upstream checkout, $TMPDIR, $HOME); they are replaced before parsing so
// that replay does not depend on the machine, the checkout location or $HOME.

///|
let known_failures_path = "tests/golden/known_failures.txt"

///|
let record_counts_path = "tests/golden/record_counts.txt"

///|
/// Fixed stand-ins for the harvest machine's home and temp directories.
let fake_home = "/home/golden"

///|
let fake_tmpdir = "/tmp/golden"

///|
priv struct Ctx {
  /// Files of the upstream test/fixtures directory, shared (read-only) by
  /// every record.
  fixtures : @core.MemoryVfs
  verbose : Bool
  trace : Bool
}

///|
/// The file system seen by one record: the shared fixtures plus the files
/// harvested for that record, so records cannot see each other's files.
priv struct RecordVfs {
  base : @core.MemoryVfs
  files : Map[String, Bytes]
}

///|
impl @core.Vfs for RecordVfs with fn read(self, path) {
  match self.files.get(path) {
    Some(data) => Some(data)
    None => self.base.read(path)
  }
}

///|
impl @core.Vfs for RecordVfs with fn is_file(self, path) {
  self.files.contains(path) || self.base.is_file(path)
}

///|
impl @core.Vfs for RecordVfs with fn is_dir(self, path) {
  let prefix = if path.has_suffix("/") { path } else { path + "/" }
  for k, _ in self.files {
    if k.has_prefix(prefix) {
      return true
    }
  }
  self.base.is_dir(path)
}

///|
impl @core.Vfs for RecordVfs with fn cwd(self) {
  self.base.cwd()
}

///|
impl @core.Vfs for RecordVfs with fn home(self) {
  self.base.home()
}

///|
async fn load_dir(vfs : @core.MemoryVfs, dir : String) -> Unit {
  let entries = @fs.readdir(dir) catch { _ => return }
  for name in entries {
    let path = "\{dir}/\{name}"
    let kind = @fs.kind(path) catch { _ => continue }
    match kind {
      Directory => load_dir(vfs, path)
      Regular => {
        let data = @fs.read_file(path).binary() catch { _ => continue }
        vfs.add_bytes(path, data)
      }
      _ => ()
    }
  }
}

///|
/// Replaces the harvest placeholders in a raw record line.
fn subst_placeholders(root : String, line : String) -> String {
  line
  .replace_all(old="$ROOT", new=root)
  .replace_all(old="$TMPDIR", new=fake_tmpdir)
  .replace_all(old="$HOME", new=fake_home)
}

///|
priv suberror Unsupported {
  Unsupported(String)
}

///|
fn json_str(j : Json) -> String? {
  match j {
    String(s) => Some(s)
    _ => None
  }
}

///|
fn to_attr_val(j : Json) -> @core.AttrVal raise Unsupported {
  match j {
    String(s) => Str(s)
    Null => Nil
    False => Bool(false)
    True => Str("")
    Number(n, ..) => if n == n.floor() { Int(n.to_int()) } else { Float(n) }
    _ => raise Unsupported("attribute value")
  }
}

///|
fn build_options(
  vfs : RecordVfs,
  opts : Map[String, Json],
) -> @core.Options raise Unsupported {
  let o = @core.Options::new()
  o.vfs = Some(vfs)
  for k, v in opts {
    // Ruby objects the replay can ignore: the logger in effect is captured as
    // "log_level" and its messages as "messages"; timings only measure.
    let ignorable = k == "input_mtime" || k == "logger" || k == "timings"
    if !ignorable && v is Object(m) && m.contains("__unsupported__") {
      raise Unsupported("option \{k}")
    }
    match k {
      "attributes" =>
        match v {
          Object(m) =>
            for ak, av in m {
              o.attributes.push((ak, to_attr_val(av)))
            }
          Array(a) =>
            for e in a {
              let s = json_str(e).unwrap_or("")
              let (k2, _, v2) = @rb.partition(s, "=")
              o.attributes.push((k2, Str(v2)))
            }
          String(s) => o.attributes = @asciidoctor.parse_attributes_option(s)
          Null => ()
          _ => raise Unsupported("attributes")
        }
      "safe" =>
        o.safe = match v {
          String(s) => @core.safe_mode_value_for_name(s)
          Number(n, ..) => Some(n.to_int())
          _ => None
        }
      "backend" => o.backend = json_str(v)
      "doctype" => o.doctype = json_str(v)
      "standalone" | "header_footer" => o.standalone = Some(v is True)
      "base_dir" => o.base_dir = json_str(v)
      "to_dir" => o.to_dir = json_str(v)
      "to_file" =>
        match v {
          String(s) => o.to_file = Some(s)
          _ => ()
        }
      "mkdirs" => o.mkdirs = v is True
      "sourcemap" => o.sourcemap = v is True
      "parse_header_only" => o.parse_header_only = v is True
      "catalog_assets" => o.catalog_assets = v is True
      "parse" => o.parse = !(v is False)
      "input_mtime" | "timings" | "logger" => ()
      "safe_mode" => ()
      // CLI (Invoker) settings that the document itself does not read
      "warnings" | "failure_level" | "verbose" | "trace" => ()
      _ => raise Unsupported("option \{k}")
    }
  }
  o
}

///|
priv struct Stats {
  mut records : Int
  mut skipped : Int
  mut ast_total : Int
  mut ast_pass : Int
  mut out_total : Int
  mut out_pass : Int
  mut msg_total : Int
  mut msg_pass : Int
  failures : Array[String]
}

///|
fn Stats::new() -> Stats {
  {
    records: 0,
    skipped: 0,
    ast_total: 0,
    ast_pass: 0,
    out_total: 0,
    out_pass: 0,
    msg_total: 0,
    msg_pass: 0,
    failures: [],
  }
}

///|
fn Stats::add(self : Stats, other : Stats) -> Unit {
  self.records += other.records
  self.skipped += other.skipped
  self.ast_total += other.ast_total
  self.ast_pass += other.ast_pass
  self.out_total += other.out_total
  self.out_pass += other.out_pass
  self.msg_total += other.msg_total
  self.msg_pass += other.msg_pass
  for f in other.failures {
    self.failures.push(f)
  }
}

///|
fn Stats::summary(self : Stats) -> String {
  "records \{self.records} skipped \{self.skipped} ast \{self.ast_pass}/\{self.ast_total} output \{self.out_pass}/\{self.out_total} messages \{self.msg_pass}/\{self.msg_total}"
}

///|
fn first_diff(expected : String, actual : String) -> String {
  let el = @rb.split(expected, "\n", limit=-1)
  let al = @rb.split(actual, "\n", limit=-1)
  let n = if el.length() > al.length() { el.length() } else { al.length() }
  for i in 0..<n {
    let e = el.get(i).unwrap_or("<EOF>")
    let a = al.get(i).unwrap_or("<EOF>")
    if e != a {
      return "line \{i + 1}:\n  expected: \{e}\n  actual:   \{a}"
    }
  }
  "(no line diff)"
}

///|
fn severity_of_int(n : Int) -> @core.Severity {
  match n {
    0 => Debug
    1 => Info
    2 => Warn
    3 => Error
    4 => Fatal
    _ => Unknown
  }
}

///|
/// Runs `f` with a logger that records every message while answering
/// `is_debug`/`is_info` like a Ruby logger at `level`.
fn[T] capture_messages(
  level : @core.Severity,
  msgs : Array[@core.LogMessage],
  f : () -> T,
) -> T {
  let old = @core.set_logger(@core.Logger::recording(msgs, level~))
  let r = f()
  @core.set_logger(old) |> ignore
  r
}

///|
/// One message as "<SEVERITY> <location>: <text>" (location omitted when absent).
fn format_message(
  severity : @core.Severity,
  location : String?,
  text : String,
) -> String {
  match location {
    Some(loc) => "\{severity.label()} \{loc}: \{text}"
    None => "\{severity.label()} \{text}"
  }
}

///|
fn expected_messages(rec : Map[String, Json]) -> Array[String] {
  guard rec.get("messages") is Some(Array(entries)) else { return [] }
  entries.map(e => {
    guard e is Object(m) else { return "<malformed message>" }
    let severity = match m.get("severity") {
      Some(Number(n, ..)) => severity_of_int(n.to_int())
      _ => Unknown
    }
    let location = m.get("source_location").bind(json_str)
    let text = m.get("message").bind(json_str).unwrap_or("")
    format_message(severity, location, text)
  })
}

///|
/// Replays one record. `key` identifies it: "<test name>@<index of the
/// record among the records of that test>".
fn run_record(
  ctx : Ctx,
  rec : Map[String, Json],
  key : String,
  stats : Stats,
) -> Unit {
  stats.records += 1
  if ctx.trace {
    println("RUN \{key}")
  }
  let vfs : RecordVfs = { base: ctx.fixtures, files: {}, }
  let opts_json = match rec.get("options") {
    Some(Object(m)) => m
    _ => {}
  }
  let options = build_options(vfs, opts_json) catch {
    Unsupported(what) => {
      stats.skipped += 1
      if ctx.verbose {
        println("SKIP \{key}: unsupported \{what}")
      }
      return
    }
  }
  let lines : Array[String]? = match rec.get("source_lines") {
    Some(Array(a)) => Some(a.map(x => json_str(x).unwrap_or("")))
    _ =>
      match rec.get("source") {
        Some(String(s)) => Some(@core.prepare_source_string(s))
        _ => None
      }
  }
  guard lines is Some(lines) else {
    stats.skipped += 1
    if ctx.verbose {
      println("SKIP \{key}: no source")
    }
    return
  }
  match rec.get("files") {
    Some(Object(files)) =>
      for path, data in files {
        match data {
          String(b64) => vfs.files[path] = base64_decode(b64)
          _ => ()
        }
      }
    _ => ()
  }
  @core.set_source_date_epoch(
    Some(
      match rec.get("source_date_epoch") {
        Some(String(s)) => @rb.to_i(s).to_int64()
        _ => 1700000000L
      },
    ),
  )
  // each record behaves like a fresh process (e.g. one-time warnings)
  @core.restore_process_state([])
  @core.reset_compliance()
  match rec.get("compliance") {
    Some(Object(c)) =>
      for k, v in c {
        match (k, v) {
          ("block_terminates_paragraph", _) =>
            @core.compliance.block_terminates_paragraph = v is True
          ("strict_verbatim_paragraphs", _) =>
            @core.compliance.strict_verbatim_paragraphs = v is True
          ("underline_style_section_titles", _) =>
            @core.compliance.underline_style_section_titles = v is True
          ("unwrap_standalone_preamble", _) =>
            @core.compliance.unwrap_standalone_preamble = v is True
          ("shorthand_property_syntax", _) =>
            @core.compliance.shorthand_property_syntax = v is True
          ("natural_xrefs", _) => @core.compliance.natural_xrefs = v is True
          ("markdown_syntax", _) => @core.compliance.markdown_syntax = v is True
          ("attribute_missing", String(s)) =>
            @core.compliance.attribute_missing = s
          ("attribute_undefined", String(s)) =>
            @core.compliance.attribute_undefined = s
          ("unique_id_start_index", Number(n, ..)) =>
            @core.compliance.unique_id_start_index = n.to_int()
          _ => ()
        }
      }
    _ => ()
  }
  let level = match rec.get("log_level") {
    Some(Number(n, ..)) => severity_of_int(n.to_int())
    _ => Warn
  }
  let messages = []
  let doc = capture_messages(level, messages, fn() {
    @asciidoctor.load_lines(
      if rec.contains("source_lines") {
        @core.prepare_source_array(lines)
      } else {
        lines
      },
      options~,
    )
  })
  match rec.get("ast") {
    Some(expected_ast) if options.parse => {
      stats.ast_total += 1
      let actual = canon(dump_node(doc))
      let expected = canon(expected_ast)
      if actual == expected {
        stats.ast_pass += 1
      } else {
        if ctx.trace {
          println("EXPECTED AST: \{expected}")
          println("ACTUAL AST:   \{actual}")
        }
        stats.failures.push(
          "AST \{key}\n\{first_diff(expected.replace_all(old=",", new=",\n"), actual.replace_all(old=",", new=",\n"))}",
        )
      }
    }
    _ => ()
  }
  let has_converter = @core.lookup_converter(doc.backend()) is Some(_)
  if !has_converter && rec.contains("converted") {
    stats.skipped += 1
    if ctx.verbose {
      println("SKIP \{key}: no converter for backend \{doc.backend()}")
    }
    return
  }
  match rec.get("converted") {
    Some(Array(convs)) =>
      for idx, conv in convs {
        guard conv is Object(c) else { continue }
        stats.out_total += 1
        let expected = c
          .get("output")
          .map(o => json_str(o).unwrap_or(""))
          .unwrap_or("")
        let copts = match c.get("opts") {
          Some(Object(m)) => m
          _ => {}
        }
        let standalone = match copts.get("standalone") {
          Some(True) => Some(true)
          Some(False) => Some(false)
          _ =>
            match copts.get("header_footer") {
              Some(True) => Some(true)
              Some(False) => Some(false)
              _ => None
            }
        }
        let actual = capture_messages(level, messages, fn() {
          doc.convert_with(
            standalone?,
            outfile?=copts.get("outfile").map(j => json_str(j).unwrap_or("")),
            outdir?=copts.get("outdir").map(j => json_str(j).unwrap_or("")),
          )
        })
        if actual == expected {
          stats.out_pass += 1
        } else {
          stats.failures.push(
            "OUT \{key}.\{idx}\n\{first_diff(expected, actual)}",
          )
        }
      }
    _ => ()
  }
  // Ruby messages are only harvested while the document is created, parsed or
  // converted; a document that Ruby never parsed is not comparable.
  if rec.contains("ast") || rec.contains("converted") {
    stats.msg_total += 1
    let expected = expected_messages(rec).join("\n")
    let actual = messages
      .map(m => {
        format_message(
          m.severity,
          m.source_location.map(l => l.line_info()),
          m.text,
        )
      })
      .join("\n")
    if actual == expected {
      stats.msg_pass += 1
    } else {
      stats.failures.push("MSG \{key}\n\{first_diff(expected, actual)}")
    }
  }
}

///|
/// Parses "<a>\t<b>" lines, skipping comments and blank lines.
fn parse_tab_lines(text : String) -> Array[(String, String)] {
  let out = []
  for line in text.split("\n") {
    let line = line.to_owned()
    if line == "" || line.has_prefix("#") {
      continue
    }
    let (a, _, b) = @rb.partition(line, "\t")
    out.push((a, b))
  }
  out
}

///|
/// "<test>@<n>" or "<test>@<n>.<c>" -> "<test>" (unchanged without an index).
fn strip_record_index(key : String) -> String {
  guard key.rev_find("@") is Some(i) else { return key }
  let suffix = key.unsafe_substring(start=i + 1, end=key.length())
  let is_index = suffix != "" &&
    suffix.iter().all(c => (c >= '0' && c <= '9') || c == '.')
  if is_index {
    key.unsafe_substring(start=0, end=i)
  } else {
    key
  }
}

///|
/// The key of a failure (its first line, e.g. "AST <test>@0").
fn failure_key(f : String) -> String {
  @rb.partition(f, "\n").0
}

///|
/// The category of a failure key from the known-failure list; falls back to
/// the category of another failure of the same kind in the same test.
fn category_for(
  known : Map[String, String],
  by_test : Map[String, String],
  key : String,
) -> String {
  match known.get(key) {
    Some(c) => c
    None => {
      let (kind, _, rest) = @rb.partition(key, " ")
      let tname = strip_record_index(rest)
      match by_test.get("\{kind} \{tname}") {
        Some(c) => c
        None =>
          match by_test.get(tname) {
            Some(c) => c
            None => "uncategorized"
          }
      }
    }
  }
}

///|
async fn main {
  let args = @env.args()
  let mut verbose = false
  let mut trace = false
  let mut prune = false
  let mut update_known = false
  let mut update_counts = false
  let mut only = -1
  let mut filter : String? = None
  let mut max_failures = 20
  let files = []
  let mut i = 1
  while i < args.length() {
    match args[i] {
      "-v" => verbose = true
      "-t" => trace = true
      "--prune-known" => prune = true
      "--update-known" => update_known = true
      "--update-counts" => update_counts = true
      "-k" => {
        i += 1
        only = @rb.to_i(args.get(i).unwrap_or("-1"))
      }
      "-f" => {
        i += 1
        filter = args.get(i)
      }
      "-n" => {
        i += 1
        max_failures = @rb.to_i(args.get(i).unwrap_or("20"))
      }
      a => files.push(a)
    }
    i += 1
  }
  @core.set_source_date_epoch(Some(1700000000L))
  let cwd = @fs.realpath(".")
  // resolve symlinks so worktrees that link .repos see the same paths
  let root = @fs.realpath("\{cwd}/.repos/asciidoctor")
  let fixtures = @core.MemoryVfs::new(cwd=root, home=fake_home)
  load_dir(fixtures, "\{root}/test/fixtures")
  let running_all = files.is_empty() && filter is None && only < 0
  if files.is_empty() {
    let names = @fs.readdir("tests/golden")
    names.sort()
    for name in names {
      if name.has_suffix(".jsonl") {
        files.push("tests/golden/\{name}")
      }
    }
  }
  let ctx = { fixtures, verbose, trace, }
  let total = Stats::new()
  // number of records in each file (for the coverage check)
  let counts : Array[(String, Int)] = []
  for file in files {
    let text = @fs.read_file(file).text()
    let stats = Stats::new()
    let per_test : Map[String, Int] = Map([])
    let mut rec_idx = -1
    for lineno, line in text.split("\n").collect() {
      let line = line.to_owned()
      if line == "" {
        continue
      }
      rec_idx += 1
      let rec = @json.parse(subst_placeholders(root, line)) catch {
        e => fail("\{file}:\{lineno + 1}: malformed golden record: \{e}")
      }
      guard rec is Object(m) else {
        fail("\{file}:\{lineno + 1}: golden record is not a JSON object")
      }
      let test_name = m.get("test").bind(json_str).unwrap_or("?")
      let n = per_test.get(test_name).unwrap_or(0)
      per_test[test_name] = n + 1
      if only >= 0 && rec_idx != only {
        continue
      }
      match filter {
        Some(f) => if !test_name.contains(f) { continue }
        None => ()
      }
      run_record(ctx, m, "\{test_name}@\{n}", stats)
    }
    counts.push((file, rec_idx + 1))
    println("\{@rb.ljust(file, 38)} \{stats.summary()}")
    total.add(stats)
  }
  println("TOTAL \{total.summary()}")
  // coverage: a golden file must not lose records (e.g. after a broken harvest)
  let coverage_errors = []
  if running_all {
    let expected_counts = parse_tab_lines(
      @fs.read_file(record_counts_path).text() catch {
        _ => ""
      },
    )
    if update_counts {
      let out = [
        "# Number of records in each golden file; cmd/golden fails if a file has fewer.",
        "# Regenerate with `golden.exe --update-counts` after harvesting.",
      ]
      for c in counts {
        out.push("\{c.1}\t\{c.0}")
      }
      @fs.write_file(
        record_counts_path,
        out.join("\n") + "\n",
        create_mode=CreateOrTruncate,
      )
      println("wrote \{record_counts_path}")
    } else {
      let actual : Map[String, Int] = Map::from_array(counts)
      for e in expected_counts {
        let want = @rb.to_i(e.0)
        match actual.get(e.1) {
          None =>
            coverage_errors.push("\{e.1}: missing (expected \{want} records)")
          Some(got) if got < want =>
            coverage_errors.push(
              "\{e.1}: \{got} records, expected at least \{want}",
            )
          _ => ()
        }
      }
    }
  }
  // compare with the known-failure list
  let known_text = @fs.read_file(known_failures_path).text() catch { _ => "" }
  let known : Map[String, String] = Map([])
  // categories by "<KIND> <test>" and by "<test>", for new keys of known tests
  let by_test : Map[String, String] = Map([])
  for e in parse_tab_lines(known_text) {
    known[e.1] = e.0
    let (kind, _, rest) = @rb.partition(e.1, " ")
    let tname = strip_record_index(rest)
    by_test["\{kind} \{tname}"] = e.0
    by_test[tname] = e.0
  }
  let failed_keys : Map[String, Bool] = Map([])
  let unexpected = []
  for f in total.failures {
    let key = failure_key(f)
    failed_keys[key] = true
    if !known.contains(key) {
      unexpected.push(f)
    }
  }
  let mut fixed = 0
  if running_all {
    for key, _ in known {
      if !failed_keys.contains(key) {
        fixed += 1
      }
    }
  }
  println(
    "known failures: \{total.failures.length() - unexpected.length()}, unexpected failures: \{unexpected.length()}\{if running_all { ", known now passing: \{fixed}" } else { "" }}",
  )
  if update_known && running_all {
    // rewrite the list from the current failures, keeping the header comments
    let kept = []
    for line in known_text.split("\n") {
      let line = line.to_owned()
      if line.has_prefix("#") {
        kept.push(line)
      } else {
        break
      }
    }
    kept.push("")
    let mut uncategorized = 0
    for f in total.failures {
      let key = failure_key(f)
      let category = category_for(known, by_test, key)
      if category == "uncategorized" {
        uncategorized += 1
      }
      kept.push("\{category}\t\{key}")
    }
    @fs.write_file(
      known_failures_path,
      kept.join("\n") + "\n",
      create_mode=CreateOrTruncate,
    )
    println(
      "wrote \{total.failures.length()} entries to \{known_failures_path} (\{uncategorized} uncategorized)",
    )
  } else if prune && running_all && fixed > 0 {
    // drop entries that now pass, keeping comments and order
    let kept = []
    for line in known_text.split("\n") {
      let line = line.to_owned()
      if line.has_prefix("#") || line == "" {
        kept.push(line)
      } else if failed_keys.contains(@rb.partition(line, "\t").2) {
        kept.push(line)
      }
    }
    while kept.length() > 0 && kept[kept.length() - 1] == "" {
      kept.pop() |> ignore
    }
    @fs.write_file(
      known_failures_path,
      kept.join("\n") + "\n",
      create_mode=CreateOrTruncate,
    )
    println("pruned \{fixed} entries from \{known_failures_path}")
  }
  for idx, f in unexpected {
    if idx >= max_failures {
      break
    }
    println("UNEXPECTED ---- \{f}")
  }
  if verbose || filter is Some(_) {
    for idx, f in total.failures {
      if idx >= max_failures {
        break
      }
      println("---- \{f}")
    }
  }
  for e in coverage_errors {
    println("COVERAGE ---- \{e}")
  }
  if total.records == 0 {
    fail("no golden records replayed")
  }
  if !coverage_errors.is_empty() {
    fail("\{coverage_errors.length()} golden files lost records")
  }
  if unexpected.length() > 0 && !update_known {
    fail("\{unexpected.length()} unexpected golden failures")
  }
}

///|
fn base64_decode(s : String) -> Bytes {
  let value = fn(c : Int) -> Int {
    if c >= 'A' && c <= 'Z' {
      c - 'A'
    } else if c >= 'a' && c <= 'z' {
      c - 'a' + 26
    } else if c >= '0' && c <= '9' {
      c - '0' + 52
    } else if c == '+' {
      62
    } else if c == '/' {
      63
    } else {
      -1
    }
  }
  let out = Buffer()
  let mut acc = 0
  let mut bits = 0
  for i in 0..<s.length() {
    let v = value(s[i].to_int())
    if v < 0 {
      continue
    }
    acc = (acc << 6) | v
    bits += 6
    if bits >= 8 {
      bits -= 8
      out.write_byte(((acc >> bits) & 0xFF).to_byte())
    }
  }
  out.to_bytes()
}
