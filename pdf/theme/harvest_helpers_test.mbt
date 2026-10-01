///|
/// Replay one loader call recorded from Ruby (see harvest_test.mbt): `kind`
/// is `load` (YAML text, `ThemeLoader#load`), `load_file` (path, theme dir)
/// or `load_theme` (name or path, theme dir); `files` are the theme files it
/// read (virtual paths); `expected` the loaded theme's dump, None when
/// loading failed; `warnings` what it logged.
fn check_case(
  kind : String,
  args : Array[String?],
  files : Array[(String, String)],
  expected : String?,
  warnings : Array[String],
) -> Unit raise {
  let map : Map[String, String] = Map([])
  for f in files {
    map[f.0] = f.1
  }
  let fs = @theme.Files::new(
    read=path => map.get(path),
    cwd="/work",
    home="/home",
  )
  @theme.clear_warnings()
  let arg = (i : Int) => args.get(i).unwrap_or(None)
  let result = try {
    let theme = match kind {
      "load" => @theme.load_text(arg(0).unwrap_or(""))
      "load_file" =>
        match arg(1) {
          Some(dir) => @theme.load_file(fs, arg(0).unwrap_or(""), theme_dir=dir)
          None => @theme.load_file(fs, arg(0).unwrap_or(""))
        }
      _ => @theme.load_theme(fs, theme_name?=arg(0), theme_dir?=arg(1))
    }
    Ok(theme.dump())
  } catch {
    e => Err(e.to_string())
  }
  match (result, expected) {
    (Ok(actual), Some(expected)) =>
      if actual != expected {
        // the differing lines
        let a = actual.split("\n").map(l => l.to_owned()).collect()
        let e = expected.split("\n").map(l => l.to_owned()).collect()
        let diff = []
        for l in e {
          if !a.contains(l) {
            diff.push("- " + l)
          }
        }
        for l in a {
          if !e.contains(l) {
            diff.push("+ " + l)
          }
        }
        if diff.is_empty() {
          diff.push("(same lines, different order)")
        }
        fail("theme differs from Ruby's:\n" + diff.join("\n"))
      }
    (Err(_), None) => ()
    (Ok(actual), None) =>
      fail("Ruby failed to load the theme; loaded:\n\{actual}")
    (Err(e), Some(_)) => fail("Ruby loaded the theme; failed: \{e}")
  }
  assert_eq(@theme.warnings.copy(), warnings)
}
