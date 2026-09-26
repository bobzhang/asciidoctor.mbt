// File-system tests for the fixpoint driver. Each test works in its own
// temporary directory; paths in inspected output are shown relative to it
// (`$TMP`).

///|
/// Runs `f` in a fresh temporary directory, removed afterwards.
async fn with_tmp(f : async (String) -> Unit) -> Unit {
  let dir = @fs.realpath(@fs.tmpdir(prefix="asciidoctor-io-test"))
  defer @fs.rmdir(dir, recursive=true)
  f(dir)
}

///|
/// Runs `f` with a memory logger; returns its result and the formatted log
/// messages, one per line (with `dir` replaced by `$TMP`).
async fn[T] with_logs(dir : String, f : async () -> T) -> (T, String) {
  let messages = []
  let old = @core.set_logger(@core.Logger::memory(messages))
  defer @core.set_logger(old) |> ignore
  let result = f()
  (result, messages.map(m => rel(dir, @core.format_log_message(m))).join("\n"))
}

///|
fn rel(dir : String, s : String) -> String {
  s.replace_all(old=dir, new="$TMP")
}

///|
async fn write(path : String, content : String) -> Unit {
  @fs.mkdir(@core.dirname(path), recursive=true, allow_exist=true)
  @fs.write_file(path, content, create_mode=CreateOrTruncate)
}

///|
async fn read_text(path : String) -> String {
  @fs.read_file(path).text()
}

///|
/// The names in a directory, sorted (shorter names first) and separated by
/// spaces.
async fn listing(dir : String) -> String {
  let names = @fs.readdir(dir)
  names.sort()
  names.join(" ")
}

///|
fn safe_options(
  safe? : Int = @core.SAFE_SAFE,
  attributes? : Array[(String, @core.AttrVal)] = [],
  standalone? : Bool,
  base_dir? : String,
) -> @core.Options {
  @core.Options::new(safe~, attributes~, standalone?, base_dir?)
}

///|
/// Writes a document whose includes nest three levels deep (one fixpoint
/// round per level).
async fn write_nested_includes(dir : String) -> Unit {
  write("\{dir}/main.adoc", "= Main\n\ninclude::a.adoc[]\n")
  write("\{dir}/a.adoc", "A text\n\ninclude::sub/b.adoc[]\n")
  // resolved relative to the including file (sub/)
  write("\{dir}/sub/b.adoc", "B text\n\ninclude::c.adoc[]\n")
  write("\{dir}/sub/c.adoc", "C text\n")
}

///|
async test "includes resolve across files, nested deeper than one round" {
  with_tmp(dir => {
    write_nested_includes(dir)
    let (output, logs) = with_logs(dir, () => {
      @io.convert_file(
        "\{dir}/main.adoc",
        options=safe_options(),
        destination=NoWrite,
      )
    })
    inspect(
      output,
      content=(
        #|<div class="paragraph">
        #|<p>A text</p>
        #|</div>
        #|<div class="paragraph">
        #|<p>B text</p>
        #|</div>
        #|<div class="paragraph">
        #|<p>C text</p>
        #|</div>
      ),
    )
    inspect(logs, content="")
    // load_file resolves parse-time files too
    let doc = @io.load_file("\{dir}/main.adoc", options=safe_options())
    inspect(doc.blocks.length(), content="3")
  })
}

///|
async test "fixpoint exhaustion raises with the unresolved paths" {
  with_tmp(dir => {
    write_nested_includes(dir)
    let text = read_text("\{dir}/main.adoc")
    let run = async fn(max_rounds : Int) -> String {
      let vfs = @io.FsVfs::new()
      let opts = safe_options(base_dir=dir)
      opts.vfs = Some(vfs)
      @io.run_with_files(
        vfs,
        () => @asciidoctor.load(text, options=opts).convert(),
        max_rounds~,
      )
    }
    // main -> a -> sub/b -> sub/c needs 4 runs: the 3rd still misses sub/c.
    let msg = try run(3) catch {
      @io.FixpointExhausted(rounds~, unresolved~) =>
        "rounds=\{rounds} unresolved=\{rel(dir, unresolved.join(","))}"
      e => raise e
    } noraise {
      _ => fail("expected FixpointExhausted")
    }
    inspect(msg, content="rounds=3 unresolved=$TMP/sub/c.adoc")
    let (output, _) = with_logs(dir, () => run(4))
    assert_true(output.contains("<p>C text</p>"))
  })
}

///|
async test "missing include logs include file not found" {
  with_tmp(dir => {
    write("\{dir}/main.adoc", "before\n\ninclude::missing.adoc[]\n\nafter\n")
    let (output, logs) = with_logs(dir, () => {
      @io.convert_file(
        "\{dir}/main.adoc",
        options=safe_options(),
        destination=NoWrite,
      )
    })
    inspect(
      logs,
      content=(
        #|asciidoctor: ERROR: main.adoc: line 3: include file not found: $TMP/missing.adoc
      ),
    )
    assert_true(
      output.contains(
        "Unresolved directive in main.adoc - include::missing.adoc[]",
      ),
    )
  })
}

///|
async test "unreadable include logs include file not readable" {
  with_tmp(dir => {
    write("\{dir}/main.adoc", "include::secret.adoc[]\n")
    write("\{dir}/secret.adoc", "secret\n")
    @fs.chmod("\{dir}/secret.adoc", 0)
    // (e.g. when running as root, permissions are not enforced)
    guard !@fs.can_read("\{dir}/secret.adoc") else { return }
    let (_, logs) = with_logs(dir, () => {
      @io.convert_file(
        "\{dir}/main.adoc",
        options=safe_options(),
        destination=NoWrite,
      )
    })
    inspect(
      logs,
      content=(
        #|asciidoctor: ERROR: main.adoc: line 1: include file not readable: $TMP/secret.adoc
      ),
    )
  })
}

///|
async test "docinfo is discovered at conversion time" {
  with_tmp(dir => {
    write("\{dir}/main.adoc", "= Main\n:docinfo: shared\n\ncontent\n")
    write("\{dir}/docinfo.html", "<meta name=\"x-test\" content=\"docinfo\">\n")
    let options = safe_options(standalone=true)
    let marker = "<meta name=\"x-test\" content=\"docinfo\">"
    let output = @io.convert_file(
      "\{dir}/main.adoc",
      options~,
      destination=NoWrite,
    )
    assert_true(output.contains(marker))
    // load_file only resolves parse-time files...
    let doc = @io.load_file("\{dir}/main.adoc", options~)
    assert_false(doc.convert().contains(marker))
    // ...unless asked to prefetch the conversion-time files as well.
    let doc = @io.load_file(
      "\{dir}/main.adoc",
      options~,
      prefetch_conversion=true,
    )
    assert_true(doc.convert().contains(marker))
  })
}

///|
async test "linkcss and copycss copy the default stylesheet" {
  with_tmp(dir => {
    write("\{dir}/main.adoc", "= Main\n\ncontent\n")
    let options = safe_options(attributes=[
      ("linkcss", Str("")),
      ("copycss", Str("")),
    ])
    let output = @io.convert_file("\{dir}/main.adoc", options~)
    assert_true(
      output.contains("<link rel=\"stylesheet\" href=\"./asciidoctor.css\">"),
    )
    assert_eq(read_text("\{dir}/main.html"), output)
    assert_true(
      read_text("\{dir}/asciidoctor.css") == @core.primary_stylesheet_data,
    )
  })
}

///|
async test "copycss copies a user stylesheet into stylesdir" {
  with_tmp(dir => {
    write("\{dir}/main.adoc", "= Main\n\ncontent\n")
    write("\{dir}/custom.css", "p { color: red; }\n")
    let options = safe_options(
      attributes=[
        ("linkcss", Str("")),
        ("copycss", Str("")),
        ("stylesheet", Str("custom.css")),
        ("stylesdir", Str("css")),
      ],
      base_dir=dir,
    )
    @fs.mkdir("\{dir}/out")
    // without mkdirs the stylesheet directory must exist
    let msg = try
      @io.convert_file("\{dir}/main.adoc", options~, to_dir="\{dir}/out")
    catch {
      @io.IOError(msg) => rel(dir, msg)
      e => raise e
    } noraise {
      _ => fail("expected IOError")
    }
    inspect(
      msg,
      content="target stylesheet directory does not exist: $TMP/out/css (hint: set :mkdirs option)",
    )
    @io.convert_file(
      "\{dir}/main.adoc",
      options~,
      to_dir="\{dir}/out",
      mkdirs=true,
    )
    |> ignore
    inspect(
      read_text("\{dir}/out/css/custom.css"),
      content="p { color: red; }\n",
    )
  })
}

///|
/// Converts `$dir/work/main.adoc` (base dir `$dir/work`) to `destination`;
/// returns "ok" or the security error.
async fn attempt(
  dir : String,
  safe : Int,
  destination : @io.Destination,
  to_dir? : String,
) -> String {
  let options = safe_options(safe~, base_dir="\{dir}/work")
  try
    @io.convert_file(
      "\{dir}/work/main.adoc",
      options~,
      destination~,
      to_dir?,
      mkdirs=true,
    )
  catch {
    @core.SecurityError(msg) => "SecurityError: " + rel(dir, msg)
    e => raise e
  } noraise {
    _ => "ok"
  }
}

///|
async test "safe mode confines explicit destinations to the base dir" {
  with_tmp(dir => {
    write("\{dir}/work/main.adoc", "= Main\n\ncontent\n")
    inspect(
      attempt(dir, @core.SAFE_SAFE, File("\{dir}/escape.html")),
      content="SecurityError: to_dir $TMP/escape.html is outside of jail: $TMP/work (disallowed in safe mode)",
    )
    inspect(
      attempt(dir, @core.SAFE_SAFE, File("../escape.html")),
      content="SecurityError: to_dir ../escape.html refers to location outside jail: $TMP/work (disallowed in safe mode)",
    )
    inspect(
      attempt(dir, @core.SAFE_SAFE, Default, to_dir="../out"),
      content="SecurityError: to_dir ../out refers to location outside jail: $TMP/work (disallowed in safe mode)",
    )
    // the file name under to_dir is jailed to the document's base dir
    inspect(
      attempt(dir, @core.SAFE_SAFE, File("../../escape.html"), to_dir="sub"),
      content="SecurityError: to_dir ../../escape.html refers to location outside jail: $TMP/work (disallowed in safe mode)",
    )
    assert_false(@fs.exists("\{dir}/escape.html"))
    // inside the jail is fine
    inspect(attempt(dir, @core.SAFE_SAFE, File("html/main.html")), content="ok")
    assert_true(@fs.exists("\{dir}/work/html/main.html"))
    // unsafe mode allows writing anywhere
    inspect(
      attempt(dir, @core.SAFE_UNSAFE, File("../escape.html")),
      content="ok",
    )
    assert_true(read_text("\{dir}/escape.html").contains("<p>content</p>"))
  })
}

///|
async test "to_dir with and without mkdirs" {
  with_tmp(dir => {
    write("\{dir}/main.adoc", "= Main\n\ncontent\n")
    let input = "\{dir}/main.adoc"
    let (msg, logs) = with_logs(dir, () => {
      try
        @io.convert_file(
          input,
          options=safe_options(base_dir=dir),
          to_dir="\{dir}/out/nested",
        )
      catch {
        @io.IOError(msg) => rel(dir, msg)
        e => raise e
      } noraise {
        _ => fail("expected IOError")
      }
    })
    inspect(
      msg,
      content="target directory does not exist: $TMP/out/nested (hint: set :mkdirs option)",
    )
    inspect(logs, content="")
    let output = @io.convert_file(
      input,
      options=safe_options(base_dir=dir),
      to_dir="\{dir}/out/nested",
      mkdirs=true,
    )
    assert_eq(read_text("\{dir}/out/nested/main.html"), output)
    // to_dir + a file name with directory segments
    @io.convert_file(
      input,
      options=safe_options(base_dir=dir),
      destination=File("deeper/doc.html"),
      to_dir="\{dir}/out",
      mkdirs=true,
    )
    |> ignore
    assert_true(@fs.exists("\{dir}/out/deeper/doc.html"))
    // the output must not overwrite the input
    let msg = try
      @io.convert_file(
        input,
        options=safe_options(base_dir=dir),
        destination=File(input),
      )
    catch {
      @io.IOError(msg) => rel(dir, msg)
      e => raise e
    } noraise {
      _ => fail("expected IOError")
    }
    inspect(
      msg,
      content="input file and output file cannot be the same: $TMP/main.adoc",
    )
  })
}

///|
async test "a string is written to an explicit file, standalone" {
  with_tmp(dir => {
    let options = safe_options(base_dir=dir)
    // by default a string is only converted
    let output = @io.convert("= Title\n\ncontent\n", options~)
    assert_false(output.contains("<html"))
    let conversion = @io.convert_source(
      Text("= Title\n\ncontent\n"),
      options~,
      destination=File("\{dir}/out/doc.html"),
      mkdirs=true,
    )
    inspect(
      rel(dir, conversion.outfile.unwrap_or("")),
      content="$TMP/out/doc.html",
    )
    inspect(conversion.document.doctitle().unwrap_or(""), content="Title")
    let written = read_text("\{dir}/out/doc.html")
    assert_eq(written, conversion.output)
    assert_true(written.has_prefix("<!DOCTYPE html>"))
    // no file attributes for a string
    assert_true(conversion.document.attr("docfile") is None)
  })
}

///|
async test "a missing converter raises before anything is written" {
  with_tmp(dir => {
    write("\{dir}/main.adoc", "= Main\n:backend: nope\n\ncontent\n")
    let attempt = async fn(destination : @io.Destination) -> String {
      try
        @io.convert_file(
          "\{dir}/main.adoc",
          options=safe_options(safe=@core.SAFE_UNSAFE),
          destination~,
          mkdirs=true,
        )
      catch {
        @core.MissingConverter(_) as e => e.to_string()
        e => raise e
      } noraise {
        _ => "no error"
      }
    }
    let missing = "asciidoctor: FAILED: missing converter for backend 'nope'. Processing aborted."
    inspect(attempt(Default), content=missing)
    inspect(attempt(File("\{dir}/out/main.html")), content=missing)
    inspect(attempt(Stdout), content=missing)
    inspect(attempt(File("/dev/null")), content=missing)
    assert_false(@fs.exists("\{dir}/main.html"))
    // not even the target directory is created
    assert_false(@fs.exists("\{dir}/out"))
    // the backend option, and conversion from a string
    let msg = try
      @io.convert("content", options=@core.Options::new(backend="nope"))
    catch {
      e => e.to_string()
    } noraise {
      _ => "no error"
    }
    inspect(msg, content=missing)
  })
}

///|
async test "a conversion error raises after the target directory is created" {
  with_tmp(dir => {
    // Ruby creates the directory before converting; the manpage converter
    // then fails for a document that is not a man page
    let msg = try
      @io.convert(
        "= Title\n:backend: manpage\n\ntext",
        options=@core.Options::new(safe=@core.SAFE_UNSAFE, base_dir=dir),
        destination=File("\{dir}/man/main.1"),
        mkdirs=true,
      )
    catch {
      @core.ConversionFailed(msg) => msg
      e => raise e
    } noraise {
      _ => "no error"
    }
    inspect(
      msg,
      content="asciidoctor: ERROR: doctype must be set to manpage when using manpage backend",
    )
    assert_true(@fs.exists("\{dir}/man"))
    assert_false(@fs.exists("\{dir}/man/main.1"))
  })
}

///|
async test "file attributes override the user's attributes" {
  with_tmp(dir => {
    write(
      "\{dir}/doc.adoc",
      "{docname}|{docfile}|{docdir}|{docfilesuffix}|{outfile}|{outdir}\n",
    )
    let attributes : Array[(String, @core.AttrVal)] = [
      ("docname", Str("X")),
      ("docfile", Str("Y")),
      ("docdir", Str("Z")),
      ("docfilesuffix", Str(".txt")),
      ("outfile", Str("O")),
      ("outdir", Str("D")),
    ]
    let options = safe_options(attributes~, standalone=false)
    // not written: outfile and outdir keep the user's values
    let output = @io.convert_file(
      "\{dir}/doc.adoc",
      options~,
      destination=NoWrite,
    )
    inspect(
      rel(dir, output),
      content=(
        #|<div class="paragraph">
        #|<p>doc|$TMP/doc.adoc|$TMP|.adoc|O|D</p>
        #|</div>
      ),
    )
    // written: the output location overrides outfile and outdir
    @io.convert_file("\{dir}/doc.adoc", options~) |> ignore
    inspect(
      rel(dir, read_text("\{dir}/doc.html")),
      content=(
        #|<div class="paragraph">
        #|<p>doc|$TMP/doc.adoc|$TMP|.adoc|$TMP/doc.html|$TMP</p>
        #|</div>
      ),
    )
    // load_file sets the same attributes
    let doc = @io.load_file("\{dir}/doc.adoc", options~)
    inspect(doc.attr("docname").unwrap_or(""), content="doc")
  })
}

///|
async test "a man page gets a .so page for each alternate name" {
  with_tmp(dir => {
    write(
      "\{dir}/cmd.adoc",
      "= cmd(8)\n:doctype: manpage\n\n== NAME\n\ncmd, alt-one, alt-two - does things\n\n== SYNOPSIS\n\n*cmd*\n",
    )
    let options = @core.Options::new(backend="manpage", base_dir=dir)
    @io.convert_file("\{dir}/cmd.adoc", options~) |> ignore
    inspect(
      listing(dir),
      content=(
        #|cmd.8 cmd.adoc alt-one.8 alt-two.8
      ),
    )
    inspect(read_text("\{dir}/alt-one.8"), content=".so cmd.8")
    assert_true(read_text("\{dir}/cmd.8").contains(".TH \"CMD\" \"8\""))
    // an explicit target names the redirect
    @io.convert_file(
      "\{dir}/cmd.adoc",
      options~,
      destination=File("\{dir}/man/tool.8"),
      mkdirs=true,
    )
    |> ignore
    inspect(
      listing("\{dir}/man"),
      content=(
        #|tool.8 alt-one.8 alt-two.8
      ),
    )
    inspect(read_text("\{dir}/man/alt-two.8"), content=".so tool.8")
  })
}

///|
async test "timings record every phase" {
  with_tmp(dir => {
    write("\{dir}/main.adoc", "= Main\n\ncontent\n")
    // a clock that advances one second per reading
    let ticks = Ref(0.0)
    let clock = () => {
      ticks.val += 1.0
      ticks.val
    }
    let timings = @core.Timings::new(clock)
    let options = @core.Options::new(base_dir=dir, timings~)
    @io.convert_file("\{dir}/main.adoc", options~) |> ignore
    assert_true(@fs.exists("\{dir}/main.html"))
    // reading the file counts toward the read phase, as in Ruby
    assert_true(timings.read().unwrap_or(0.0) >= 2.0)
    assert_true(timings.parse() is Some(_))
    assert_true(timings.convert() is Some(_))
    assert_true(timings.write() is Some(_))
    // from a string, without writing
    let timings = @core.Timings::new(clock)
    @io.convert("content", options=@core.Options::new(timings~)) |> ignore
    assert_true(timings.read_parse_convert() is Some(_))
    assert_true(timings.write() is None)
    // load_file records read and parse
    let timings = @core.Timings::new(clock)
    @io.load_file("\{dir}/main.adoc", options=@core.Options::new(timings~))
    |> ignore
    assert_true(timings.read() is Some(_))
    assert_true(timings.parse() is Some(_))
    assert_true(timings.convert() is None)
  })
}
