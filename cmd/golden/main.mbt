// Golden fixture runner: replays tests/golden/*.jsonl (harvested from the
// Ruby test suite) against the MoonBit port and reports parity.
//
// Usage: moon run cmd/golden --target native -- [-v] [-f filter] [files...]

///|
let root_placeholder = "$ROOT"

///|
priv struct Ctx {
  root : String
  vfs : @core.MemoryVfs
  verbose : Bool
  filter : String?
  trace : Bool
  only : Int
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
fn subst_root(ctx : Ctx, s : String) -> String {
  s.replace_all(old=root_placeholder, new=ctx.root)
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
  ctx : Ctx,
  opts : Map[String, Json],
) -> @core.Options raise Unsupported {
  let o = @core.Options::new()
  o.vfs = Some(ctx.vfs)
  for k, v in opts {
    if k != "input_mtime" && v is Object(m) && m.contains("__unsupported__") {
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
      "base_dir" => o.base_dir = json_str(v).map(s => subst_root(ctx, s))
      "to_dir" => o.to_dir = json_str(v).map(s => subst_root(ctx, s))
      "to_file" =>
        match v {
          String(s) => o.to_file = Some(subst_root(ctx, s))
          _ => ()
        }
      "mkdirs" => o.mkdirs = v is True
      "sourcemap" => o.sourcemap = v is True
      "parse_header_only" => o.parse_header_only = v is True
      "catalog_assets" => o.catalog_assets = v is True
      "parse" => o.parse = !(v is False)
      "input_mtime" | "timings" | "logger" => ()
      "safe_mode" => ()
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
  failures : Array[String]
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
fn run_record(ctx : Ctx, rec : Map[String, Json], stats : Stats) -> Unit {
  let test_name = rec
    .get("test")
    .map(t => json_str(t).unwrap_or("?"))
    .unwrap_or("?")
  match ctx.filter {
    Some(f) => if !test_name.contains(f) { return }
    None => ()
  }
  stats.records += 1
  if ctx.trace {
    println("RUN \{test_name}")
  }
  let opts_json = match rec.get("options") {
    Some(Object(m)) => m
    _ => {}
  }
  let options = build_options(ctx, opts_json) catch {
    Unsupported(what) => {
      stats.skipped += 1
      if ctx.verbose {
        println("SKIP \{test_name}: unsupported \{what}")
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
    return
  }
  match rec.get("files") {
    Some(Object(files)) =>
      for path, data in files {
        match data {
          String(b64) =>
            ctx.vfs.add_bytes(subst_root(ctx, path), base64_decode(b64))
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
  let (doc, _messages) = @core.with_memory_logger(fn() {
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
          "AST \{test_name}\n\{first_diff(expected.replace_all(old=",", new=",\n"), actual.replace_all(old=",", new=",\n"))}",
        )
      }
    }
    _ => ()
  }
  let has_converter = @core.lookup_converter(doc.backend()) is Some(_)
  if !has_converter && rec.contains("converted") {
    stats.skipped += 1
    return
  }
  match rec.get("converted") {
    Some(Array(convs)) =>
      for conv in convs {
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
        let (actual, _) = @core.with_memory_logger(fn() {
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
            "OUT \{test_name}\n\{first_diff(expected, actual)}",
          )
        }
      }
    _ => ()
  }
}

///|
async fn main {
  let args = @env.args()
  let mut verbose = false
  let mut trace = false
  let mut prune = false
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
  // resolve symlinks so worktrees that link .repos see the harvested absolute paths
  let root = @fs.realpath("\{cwd}/.repos/asciidoctor")
  let home = @env.get_env_var("HOME").unwrap_or("/")
  let vfs = @core.MemoryVfs::new(cwd=root, home~)
  load_dir(vfs, "\{root}/test/fixtures")
  let files_given_is_all = files.is_empty() && filter is None
  if files.is_empty() {
    for name in @fs.readdir("tests/golden", sort=true) {
      if name.has_suffix(".jsonl") {
        files.push("tests/golden/\{name}")
      }
    }
  }
  let ctx = { root, vfs, verbose, filter, trace, only, }
  let total : Stats = {
    records: 0,
    skipped: 0,
    ast_total: 0,
    ast_pass: 0,
    out_total: 0,
    out_pass: 0,
    failures: [],
  }
  for file in files {
    let text = @fs.read_file(file).text()
    let stats : Stats = {
      records: 0,
      skipped: 0,
      ast_total: 0,
      ast_pass: 0,
      out_total: 0,
      out_pass: 0,
      failures: [],
    }
    let mut rec_idx = -1
    for line in text.split("\n") {
      let line = line.to_owned()
      if line == "" {
        continue
      }
      rec_idx += 1
      if ctx.only >= 0 && rec_idx != ctx.only {
        continue
      }
      let rec = @json.parse(line) catch { _ => continue }
      guard rec is Object(m) else { continue }
      run_record(ctx, m, stats)
    }
    println(
      "\{@rb.ljust(file, 36)} records \{stats.records} skipped \{stats.skipped} ast \{stats.ast_pass}/\{stats.ast_total} output \{stats.out_pass}/\{stats.out_total}",
    )
    total.records += stats.records
    total.skipped += stats.skipped
    total.ast_total += stats.ast_total
    total.ast_pass += stats.ast_pass
    total.out_total += stats.out_total
    total.out_pass += stats.out_pass
    for f in stats.failures {
      total.failures.push(f)
    }
  }
  println(
    "TOTAL records \{total.records} skipped \{total.skipped} ast \{total.ast_pass}/\{total.ast_total} output \{total.out_pass}/\{total.out_total}",
  )
  // compare with the known-failure list
  let known : Map[String, String] = Map([])
  let known_text = @fs.read_file("tests/golden/known_failures.txt").text() catch {
    _ => ""
  }
  for line in known_text.split("\n") {
    let line = line.to_owned()
    if line == "" || line.has_prefix("#") {
      continue
    }
    let (category, _, key) = @rb.partition(line, "\t")
    known[key] = category
  }
  let failed_keys : Map[String, Bool] = Map([])
  let unexpected = []
  for f in total.failures {
    let key = @rb.partition(f, "\n").0
    failed_keys[key] = true
    if !known.contains(key) {
      unexpected.push(f)
    }
  }
  let mut fixed = 0
  if files_given_is_all {
    for key, _ in known {
      if !failed_keys.contains(key) {
        fixed += 1
      }
    }
  }
  println(
    "known failures: \{total.failures.length() - unexpected.length()}, unexpected failures: \{unexpected.length()}\{if files_given_is_all { ", known now passing: \{fixed}" } else { "" }}",
  )
  if prune && files_given_is_all && fixed > 0 {
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
      "tests/golden/known_failures.txt",
      kept.join("\n") + "\n",
      create_mode=CreateOrTruncate,
    )
    println("pruned \{fixed} entries from tests/golden/known_failures.txt")
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
