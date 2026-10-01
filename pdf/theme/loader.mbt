///|
// asciidoctor-pdf 2.3.27's ThemeLoader (lib/asciidoctor/pdf/theme_loader.rb):
// theme files are loaded, the themes they extend first, and their nested
// keys flattened into underscore keys, each value evaluated in order
// (`$variable` references see the keys loaded so far; arithmetic and units
// are resolved; colors normalized).

///|
/// Where the bundled themes live (Ruby's `ThemeLoader::ThemesDir`, the
/// gem's `data/themes`). They are bundled in this package, so this is a
/// virtual directory: `Files` serves the bundled themes from it.
pub let themes_dir : String = "/asciidoctor-pdf/data/themes"

///|
/// Where the bundled fonts live (`ThemeLoader::FontsDir`, the gem's
/// `data/fonts`): the directory `GEM_FONTS_DIR` stands for. Virtual too:
/// the converter maps it to the directory holding the fonts.
pub let fonts_dir : String = "/asciidoctor-pdf/data/fonts"

///|
/// `BaseThemePath`
pub let base_theme_path : String = themes_dir + "/base-theme.yml"

///|
/// The loaded theme (Ruby's `ThemeData`): flattened keys and their values,
/// in the order they were first set. As in Ruby, the directory the theme
/// was loaded from is a key too (`__dir__`, see `Theme::dir`).
pub struct Theme {
  table : Map[String, Value]
}

///|
pub fn Theme::new() -> Theme {
  { table: Map([]), }
}

///|
/// The directory the theme was loaded from (`__dir__`), which relative
/// asset paths resolve against: the bundled themes' when unset.
pub fn Theme::dir(self : Theme) -> String {
  match self.table.get("__dir__") {
    Some(Str(dir)) => dir
    _ => themes_dir
  }
}

///|
pub fn Theme::set_dir(self : Theme, dir : String) -> Unit {
  self.table["__dir__"] = Str(dir)
}

///|
/// The value of a key; None when the key is absent (a key set to nil is
/// `Some(Null)`, as `respond_to?` sees it).
pub fn Theme::get(self : Theme, key : String) -> Value? {
  self.table.get(key)
}

///|
/// The value of a key, nil when absent (`theme[key]`).
#alias("_[_]")
pub fn Theme::at(self : Theme, key : String) -> Value {
  self.table.get(key).unwrap_or(Null)
}

///|
#alias("_[_]=_")
pub fn Theme::set(self : Theme, key : String, value : Value) -> Unit {
  self.table[key] = value
}

///|
pub fn Theme::has(self : Theme, key : String) -> Bool {
  self.table.contains(key)
}

///|
pub fn Theme::copy(self : Theme) -> Theme {
  { table: self.table.copy(), }
}

///|
/// The keys in the order they were first set.
pub fn Theme::keys(self : Theme) -> Array[String] {
  self.table.keys().collect()
}

///|
/// How the loader reads files: an absolute path to its text, or None when
/// there is no such file. The bundled themes are served before it is asked.
pub(all) struct Files {
  read : (String) -> String?
  /// the working directory, for relative theme paths (`Dir.pwd`)
  cwd : String
  /// the home directory, for `~` (`File.expand_path`)
  home : String
}

///|
pub fn Files::new(
  read? : (String) -> String? = _ => None,
  cwd? : String = "/",
  home? : String = "/",
) -> Files {
  { read, cwd, home, }
}

///|
/// A file's text: a bundled theme, else from `read`.
fn Files::read_file(self : Files, path : String) -> String raise ThemeError {
  if dirname(path) == themes_dir {
    match bundled_theme(basename(path)) {
      Some(text) => return text
      None => ()
    }
  }
  match (self.read)(path) {
    Some(text) => text
    None => raise ThemeError("No such file or directory @ rb_sysopen - \{path}")
  }
}

///|
/// The names of the bundled themes (`BundledThemeNames`).
pub fn bundled_theme_names() -> Array[String] {
  bundled_themes.map(t => t.0[:t.0.length() - 10].to_owned())
}

///|
fn bundled_theme(file : String) -> String? {
  for t in bundled_themes {
    if t.0 == file {
      return Some(t.1)
    }
  }
  None
}

// ---------------------------------------------------------------------------
// paths

///|
/// `File.dirname`
fn dirname(path : String) -> String {
  match path.rev_find("/") {
    Some(0) => "/"
    Some(i) => path[:i].to_owned()
    None => "."
  }
}

///|
/// `File.basename`
fn basename(path : String) -> String {
  match path.rev_find("/") {
    Some(i) => path[i + 1:].to_owned()
    None => path
  }
}

///|
/// Normalize `.` and `..` segments of an absolute path.
fn normalize(path : String) -> String {
  let segs : Array[String] = []
  for s in path.split("/") {
    let s = s.to_owned()
    if s == "" || s == "." {
      continue
    } else if s == ".." {
      ignore(segs.pop())
    } else {
      segs.push(s)
    }
  }
  "/" + segs.join("/")
}

///|
/// `File.absolute_path(path, base)`: relative to `base` (itself relative
/// to the working directory), no `~` expansion.
fn absolute_path(files : Files, path : String, base : String) -> String {
  if path.has_prefix("/") {
    return normalize(path)
  }
  let base = if base.has_prefix("/") { base } else { files.cwd + "/" + base }
  normalize(base + "/" + path)
}

///|
/// `File.expand_path(path, base)`: as `absolute_path`, with `~` for the
/// home directory.
fn expand_path(files : Files, path : String, base? : String) -> String {
  if path == "~" || path.has_prefix("~/") {
    return normalize(files.home + path[1:].to_owned())
  }
  let base = match base {
    Some(b) => expand_path(files, b)
    None => files.cwd
  }
  absolute_path(files, path, base)
}

///|
/// `ThemeLoader.resolve_theme_file`: the theme's path and directory. A name
/// ending in `.yml` is a path (relative to `theme_dir`, else the working
/// directory); another is `<name>-theme.yml` in `theme_dir` (default: the
/// bundled themes).
pub fn resolve_theme_file(
  files : Files,
  theme_name : String?,
  theme_dir : String?,
) -> (String, String) {
  match theme_name {
    Some(name) if name.has_suffix(".yml") =>
      match theme_dir {
        Some(dir) => {
          let dir = expand_path(files, dir)
          (absolute_path(files, name, dir), dir)
        }
        None => {
          let path = expand_path(files, name)
          (path, dirname(path))
        }
      }
    _ => {
      let dir = match theme_dir {
        Some(dir) => expand_path(files, dir)
        None => themes_dir
      }
      let name = theme_name.unwrap_or("default")
      (absolute_path(files, dir + "/" + name + "-theme.yml", files.cwd), dir)
    }
  }
}

///|
/// `ThemeLoader.resolve_theme_asset`
pub fn resolve_theme_asset(
  files : Files,
  asset_path : String,
  theme_dir? : String,
) -> String {
  absolute_path(files, asset_path, theme_dir.unwrap_or(themes_dir))
}

// ---------------------------------------------------------------------------
// loading

///|
/// `ThemeLoader.load_base_theme`: the base theme is loaded as it is, with
/// no processing (its keys are already flat).
pub fn load_base_theme(files : Files) -> Theme raise ThemeError {
  let data = safe_load(files.read_file(base_theme_path))
  let theme = Theme::new()
  match data {
    Hash(map, ..) =>
      for k, v in map {
        theme[k] = v
      }
    _ => ()
  }
  theme.set_dir(themes_dir)
  theme
}

///|
/// `ThemeLoader.load_theme`: the named (or `.yml` path) theme, or the
/// default theme; a theme outside the bundled themes gets the defaults of
/// a theme that extends nothing (left-aligned black text in Courier...).
pub fn load_theme(
  files : Files,
  theme_name? : String,
  theme_dir? : String,
) -> Theme raise ThemeError {
  let (theme_path, theme_dir) = resolve_theme_file(files, theme_name, theme_dir)
  if theme_path == base_theme_path {
    return load_base_theme(files)
  }
  let initial = Theme::new()
  initial["base_font_size"] = Int(12)
  let theme = load_file_into(
    files,
    theme_path,
    initial,
    Some(theme_dir),
    Map([]),
  )
  if dirname(theme_path) != themes_dir {
    let default = (key : String, value : Value) => {
      if !theme[key].truthy() {
        theme[key] = value
      }
    }
    default("base_text_align", Str("left"))
    default("base_line_height", Int(1))
    default("base_font_color", Str("000000"))
    let codespan = if theme["codespan_font_family"].truthy() {
      theme["codespan_font_family"]
    } else {
      Str("Courier")
    }
    default("code_font_family", codespan)
    default("conum_font_family", codespan)
    let heading_font_family = theme["heading_font_family"]
    if heading_font_family.truthy() {
      default("abstract_title_font_family", heading_font_family)
      default("sidebar_title_font_family", heading_font_family)
    }
  }
  theme.set_dir(theme_dir)
  theme
}

///|
/// `HexColorEntryRx`:
/// `^(?<k> *\p{Graph}+): +(?!null$)(?<q>["']?)(?<h>#)?(?<v>\h\h\h\h{0,3})\k<q> *(?:#.*)?$`
/// — a line assigning a hex color (3 to 6 hex digits, maybe quoted, maybe
/// with `#`), rewritten as `k: 'v'` when it had `#` or the key ends in
/// `color`, else `k: v`, so YAML reads neither a comment nor a number.
fn protect_hex_color(line : String) -> String {
  let chars : Array[Char] = line.iter().collect()
  let n = chars.length()
  // the key: spaces, then printable non-space characters; the separator is
  // the last `: +` whose remainder matches (the key is greedy)
  let mut i = 0
  while i < n && chars[i] == ' ' {
    i += 1
  }
  let key_start = i
  let is_graph = (c : Char) => {
    c.to_int() > 0x20 &&
    c.to_int() != 0x7F &&
    !(c.to_int() >= 0x80 && c.is_whitespace())
  }
  let mut key_end = key_start
  while key_end < n && is_graph(chars[key_end]) {
    key_end += 1
  }
  // try each `:` inside the graph run, the rightmost first
  let mut colon = key_end - 1
  while colon > key_start {
    if chars[colon] == ':' && colon + 1 < n && chars[colon + 1] == ' ' {
      match match_hex_value(chars, colon + 1) {
        Some((hash, v)) => {
          let k = String::from_array(chars[:colon])
          let quote = hash || k.has_suffix("color")
          return if quote { "\{k}: '\{v}'" } else { "\{k}: \{v}" }
        }
        None => ()
      }
    }
    colon -= 1
  }
  line
}

///|
/// ` +(?!null$)(?<q>["']?)(?<h>#)?(?<v>\h{3,6})\k<q> *(?:#.*)?$` from
/// `start` (the spaces after the colon): whether it had `#`, and the digits.
fn match_hex_value(chars : Array[Char], start : Int) -> (Bool, String)? {
  let n = chars.length()
  let mut i = start
  if i >= n || chars[i] != ' ' {
    return None
  }
  while i < n && chars[i] == ' ' {
    i += 1
  }
  // (?!null$)
  if String::from_array(chars[i:]) == "null" {
    return None
  }
  let is_hex = (c : Char) => {
    is_digit(c) || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')
  }
  // with and without the quote (the quote is optional: `["']?` backtracks)
  let quotes : Array[Char?] = if i < n && (chars[i] == '"' || chars[i] == '\'') {
    [Some(chars[i]), None]
  } else {
    [None]
  }
  for q in quotes {
    let mut j = i + (if q is Some(_) { 1 } else { 0 })
    let hash = j < n && chars[j] == '#'
    let hash_options = if hash { [true, false] } else { [false] }
    for with_hash in hash_options {
      let v_start = j + (if with_hash { 1 } else { 0 })
      // \h{3,6}, greedy, backtracking to 3
      let mut v_end = v_start
      while v_end < n && v_end - v_start < 6 && is_hex(chars[v_end]) {
        v_end += 1
      }
      while v_end - v_start >= 3 {
        let mut k = v_end
        let quote_ok = match q {
          Some(c) =>
            if k < n && chars[k] == c {
              k += 1
              true
            } else {
              false
            }
          None => true
        }
        if quote_ok {
          while k < n && chars[k] == ' ' {
            k += 1
          }
          if k == n || chars[k] == '#' {
            return Some((with_hash, String::from_array(chars[v_start:v_end])))
          }
        }
        v_end -= 1
      }
    }
    j = 0
    ignore(j)
  }
  None
}

///|
/// `ThemeLoader.load_file filename, nil, theme_dir`: a theme file loaded
/// by itself (the themes it extends first), without the defaults
/// `load_theme` adds.
pub fn load_file(
  files : Files,
  filename : String,
  theme_dir? : String,
) -> Theme raise ThemeError {
  load_file_into(files, filename, Theme::new(), theme_dir, Map([]))
}

///|
/// `ThemeLoader.load_file`: load a theme file into `theme` (the themes it
/// extends first), returning the theme data (which extending `base`
/// replaces). `loaded` holds the files loaded so far (`__loaded__`).
fn load_file_into(
  files : Files,
  filename : String,
  theme : Theme,
  theme_dir : String?,
  loaded : Map[String, Bool],
) -> Theme raise ThemeError {
  let text = files.read_file(filename)
  // newline: :universal
  let text = text
    .replace_all(old="\r\n", new="\n")
    .replace_all(old="\r", new="\n")
  let text = if dirname(filename) == themes_dir {
    text
  } else {
    let lines = text
      .split("\n")
      .map(l => protect_hex_color(l.to_owned()))
      .collect()
    lines.join("\n")
  }
  let data = safe_load(text) catch {
    ThemeError(message) => raise ThemeError("\{filename}: \{message}")
  }
  loaded[filename] = true
  let mut theme = theme
  let data = match data {
    Hash(map, ..) => {
      match map.get("extends") {
        Some(extends) => {
          map.remove("extends")
          let paths = match extends {
            Array(items) => items
            Null => []
            other => [other]
          }
          for item in paths {
            let mut path = item.to_ruby_s()
            let force = path.has_suffix(" !important")
            if force {
              path = path[:path.length() - 11].to_owned()
            }
            if path == "base" {
              if !loaded.contains("base") || force {
                loaded["base"] = true
                let merged = theme.copy()
                let base = load_base_theme(files)
                for k, v in base.table {
                  merged[k] = v
                }
                theme = merged
              }
              continue
            }
            let (extend_path, extend_dir) = if bundled_theme_names().contains(
                path,
              ) {
              resolve_theme_file(files, Some(path), Some(themes_dir))
            } else if path.has_prefix("./") {
              resolve_theme_file(files, Some(path), Some(dirname(filename)))
            } else {
              resolve_theme_file(files, Some(path), theme_dir)
            }
            if !loaded.contains(extend_path) || force {
              loaded[extend_path] = true
              theme = load_file_into(
                files,
                extend_path,
                theme,
                Some(extend_dir),
                loaded,
              )
            }
          }
        }
        None => ()
      }
      Some(map)
    }
    _ => None
  }
  match data {
    Some(map) => load_map(map, theme)
    None => ()
  }
  theme
}

///|
/// Warnings met while loading (Ruby logs them): unknown variables,
/// deprecated categories. Cleared by `clear_warnings`.
pub let warnings : Array[String] = []

///|
pub fn clear_warnings() -> Unit {
  warnings.clear()
}

///|
/// `ThemeLoader#load`: process the entries of a (parsed) theme into
/// `theme`, top-level keys normalized.
pub fn load_map(
  map : Map[String, Value],
  theme : Theme,
) -> Unit raise ThemeError {
  for key, val in map {
    process_entry(key, val, theme, normalize_key=true)
  }
}

///|
/// Load theme YAML text into `theme` (or a new theme) without `extends`
/// or the hex color protection (`ThemeLoader.new.load YAML.safe_load text`).
pub fn load_text(text : String, theme? : Theme) -> Theme raise ThemeError {
  let theme = match theme {
    Some(t) => t
    None => Theme::new()
  }
  match safe_load(text) {
    Hash(map, ..) => load_map(map, theme)
    _ => ()
  }
  theme
}

///|
/// `DeprecatedCategoryKeys`
let deprecated_category_keys : Array[(String, String)] = [
  ("blockquote", "quote"),
  ("key", "kbd"),
  ("literal", "codespan"),
  ("outline_list", "list"),
]

///|
fn deprecated_category(key : String) -> String? {
  for entry in deprecated_category_keys {
    if entry.0 == key {
      return Some(entry.1)
    }
  }
  None
}

///|
/// `DeprecatedKeys`
fn deprecated_key(key : String) -> String? {
  if key == "table_caption_side" {
    return Some("table_caption_end")
  }
  let prefixes = [
    "base", "heading", "heading_h1", "heading_h2", "heading_h3", "heading_h4", "heading_h5",
    "heading_h6", "title_page", "abstract", "abstract_title", "admonition_label",
    "sidebar_title", "toc_title",
  ]
  for p in prefixes {
    if key == p + "_align" {
      return Some(p + "_text_align")
    }
  }
  None
}

///|
fn tr_dash(s : String) -> String {
  if s.contains("-") {
    s.replace_all(old="-", new="_")
  } else {
    s
  }
}

///|
/// `ThemeLoader#process_entry`
fn process_entry(
  key : String,
  val : Value,
  data : Theme,
  normalize_key? : Bool = false,
) -> Unit raise ThemeError {
  let key = if normalize_key { tr_dash(key) } else { key }
  if key == "font" {
    match val {
      Hash(map, ..) =>
        for subkey, subval in map {
          if subkey == "catalog" || subkey == "fallbacks" {
            process_entry("font_\{subkey}", subval, data)
          }
        }
      _ => ()
    }
  } else if key == "font_catalog" {
    data[key] = match val {
      Hash(map, ..) => {
        let map = map.copy()
        let merge = map.get("merge").map(v => v.truthy()).unwrap_or(false)
        map.remove("merge")
        let accum : Map[String, Value] = if merge {
          match data[key] {
            Hash(existing, ..) => existing.copy()
            _ => Map([])
          }
        } else {
          Map([])
        }
        for name, styles in map {
          let styles = match styles {
            Str(path) => {
              let m : Map[String, Value] = Map([])
              m["*"] = Str(path)
              Hash(m, symbols=false)
            }
            other => other
          }
          match styles {
            Hash(styles, ..) => {
              let subaccum : Map[String, Value] = Map([])
              for style, path in styles {
                let mut path = match path {
                  Str(p) => p
                  other =>
                    raise ThemeError(
                      "undefined method 'start_with?' for \{other.dump()}",
                    )
                }
                if path.has_prefix("GEM_FONTS_DIR") && path.length() > 13 {
                  path = fonts_dir + path[13:].to_owned()
                }
                let expanded = expand_vars(path, data)
                match style {
                  "*" =>
                    for s in ["normal", "bold", "italic", "bold_italic"] {
                      subaccum[s] = expanded
                    }
                  "regular" => subaccum["normal"] = expanded
                  _ => subaccum[style] = expanded
                }
              }
              accum[name] = Hash(subaccum, symbols=false)
            }
            // not a hash: ignored
            _ => ()
          }
        }
        Hash(accum, symbols=false)
      }
      _ => Null
    }
  } else if key == "font_fallbacks" {
    data[key] = match val {
      Array(items) =>
        Array(items.map(name => expand_vars(name.to_ruby_s(), data)))
      _ => Array([])
    }
  } else if key.has_prefix("admonition_icon_") {
    if val.truthy() {
      let accum : Map[String, Value] = Map([])
      match val {
        Hash(map, ..) =>
          for key2, val2 in map {
            let key2 = tr_dash(key2)
            accum[key2] = if key2.has_suffix("_color") {
              to_color(evaluate(val2, data, math=false))
            } else {
              evaluate(val2, data)
            }
          }
        _ => ()
      }
      data[key] = Hash(accum, symbols=true)
    }
  } else if val is Hash(map, ..) {
    let key = match deprecated_category(key) {
      Some(rekey) => {
        warnings.push(
          "WARN: the \{key.replace_all(old="_", new="-")} theme category is deprecated; use the \{rekey.replace_all(old="_", new="-")} category instead",
        )
        rekey
      }
      None => key
    }
    for subkey, subval in map {
      let sub = if key == "role" { subkey } else { tr_dash(subkey) }
      process_entry("\{key}_\{sub}", subval, data)
    }
  } else if deprecated_key(key) is Some(rekey) {
    data[rekey] = evaluate(val, data, math=false)
  } else if key.has_prefix("role_") && key.has_suffix("_align") {
    // RoleAlignKeyRx: (?:_text)?_align$
    let base = if key.has_suffix("_text_align") {
      key[:key.length() - 11].to_owned()
    } else {
      key[:key.length() - 6].to_owned()
    }
    data[base + "_text_align"] = evaluate(val, data, math=false)
  } else if padding_bottom_hack_keys.contains(key) {
    let val = evaluate(val, data)
    match val {
      Array(items) if items.length() > 0 &&
        items[0].to_f() >= 0.0 &&
        items.get(2).unwrap_or(Null).to_f() <= 0.0 => {
        let items = items.copy()
        while items.length() < 3 {
          items.push(Null)
        }
        items[2] = items[0]
        data[key] = Array(items)
      }
      _ => data[key] = val
    }
  } else if key.has_suffix("_color") {
    match val {
      Array(items) if key == "table_border_color" ||
        (key == "table_grid_color" && items.length() == 2) =>
        data[key] = Array(
          items.map(it => to_color(evaluate(it, data, math=false))),
        )
      _ => data[key] = to_color(evaluate(val, data, math=false))
    }
  } else if key.has_suffix("_content") {
    data[key] = Str(expand_vars(val.to_ruby_s(), data).to_ruby_s())
  } else {
    data[key] = evaluate(val, data)
  }
}

///|
/// `PaddingBottomHackKeys`
let padding_bottom_hack_keys : Array[String] = [
  "example_padding", "quote_padding", "sidebar_padding", "verse_padding",
]

///|
/// `ThemeLoader#evaluate`
fn evaluate(expr : Value, vars : Theme, math? : Bool = true) -> Value {
  match expr {
    Str(s) => {
      let expanded = expand_vars(s, vars)
      if math {
        evaluate_math(expanded)
      } else {
        expanded
      }
    }
    Array(items) => Array(items.map(e => evaluate(e, vars, math~)))
    _ => expr
  }
}

///|
/// `[a-z0-9_-]`
fn is_var_char(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || is_digit(c) || c == '_' || c == '-'
}

///|
/// `LoneVariableRx = /^\$([a-z0-9_-]+)$/`: the variable's name.
fn lone_variable(expr : String) -> String? {
  if expr.length() < 2 || expr[0] != '$' {
    return None
  }
  let name = expr[1:].to_owned()
  if name.iter().all(is_var_char) {
    Some(name)
  } else {
    None
  }
}

///|
/// `ThemeLoader#expand_vars`: a lone `$variable` (or `-$variable`) is
/// replaced by the variable's value itself (a number stays a number);
/// otherwise each `$variable` is replaced by its value's `to_s`.
fn expand_vars(expr : String, vars : Theme) -> Value {
  guard expr.find("$") is Some(idx) else { return Str(expr) }
  if idx == 0 {
    match lone_variable(expr) {
      Some(name) => return resolve_var(vars, expr, name)
      None => ()
    }
  } else if idx == 1 && expr[0] == '-' {
    let negated = expr[1:].to_owned()
    match lone_variable(negated) {
      Some(name) =>
        return match resolve_var(vars, negated, name) {
          Int(i) => Int(-i)
          Float(f) => Float(-f)
          other => Str("-" + other.to_ruby_s())
        }
      None => ()
    }
  }
  // gsub(VariableRx) { resolve_var vars, $&, $1 }
  let sb = StringBuilder()
  let chars : Array[Char] = expr.iter().collect()
  let mut i = 0
  while i < chars.length() {
    if chars[i] == '$' && i + 1 < chars.length() && is_var_char(chars[i + 1]) {
      let mut j = i + 1
      while j < chars.length() && is_var_char(chars[j]) {
        j += 1
      }
      let name = String::from_array(chars[i + 1:j])
      let written = "$" + name
      sb.write_string(resolve_var(vars, written, name).to_ruby_s())
      i = j
    } else {
      sb.write_char(chars[i])
      i += 1
    }
  }
  Str(sb.to_string())
}

///|
/// `ThemeLoader#resolve_var`: the value of the key the variable names
/// (dashes as underscores; a deprecated category or key resolves to its
/// replacement); an unknown variable stays as written.
fn resolve_var(vars : Theme, written : String, name : String) -> Value {
  let name = tr_dash(name)
  if vars.has(name) {
    return vars[name]
  }
  for entry in deprecated_category_keys {
    let (old_key, new_key) = entry
    if name.has_prefix(old_key + "_") {
      let replace = new_key + name[old_key.length():].to_owned()
      if vars.has(replace) {
        return vars[replace]
      }
    }
  }
  match deprecated_key(name) {
    Some(replace) if vars.has(replace) => return vars[replace]
    _ => ()
  }
  warnings.push("WARN: unknown variable reference in PDF theme: \{written}")
  Str(written)
}

///|
/// A number `-?\d+(?:\.\d+)?` starting at `start`: its end.
fn number_after(chars : Array[Char], start : Int) -> Int? {
  let mut i = start
  if i < chars.length() && chars[i] == '-' {
    i += 1
  }
  let digits = i
  while i < chars.length() && is_digit(chars[i]) {
    i += 1
  }
  if i == digits {
    return None
  }
  if i + 1 < chars.length() && chars[i] == '.' && is_digit(chars[i + 1]) {
    i += 1
    while i < chars.length() && is_digit(chars[i]) {
      i += 1
    }
  }
  Some(i)
}

///|
/// One `gsub` pass of `(-?\d+(?:\.\d+)?) +([ops]) +(-?\d+(?:\.\d+)?)`:
/// scan left to right for the leftmost match, replace it with the result
/// (`Float#to_s`), continue after it.
fn apply_ops(expr : String, ops : String) -> String {
  let chars : Array[Char] = expr.iter().collect()
  let n = chars.length()
  let sb = StringBuilder()
  let mut pos = 0
  let mut start = 0
  while start < n {
    // the leftmost match beginning at `start`
    match match_op_at(chars, start, ops) {
      Some((end, left, op, right)) => {
        sb.write_string(String::from_array(chars[pos:start]))
        let a = ruby_string_to_f(left)
        let b = ruby_string_to_f(right)
        let result = match op {
          '*' => a * b
          '/' => a / b
          '^' => @math.pow(a, b)
          '+' => a + b
          _ => a - b
        }
        sb.write_string(ruby_float_to_s(result))
        pos = end
        start = end
      }
      None => start += 1
    }
  }
  sb.write_string(String::from_array(chars[pos:]))
  sb.to_string()
}

///|
/// The operation `(-?\d+(?:\.\d+)?) +([ops]) +(-?\d+(?:\.\d+)?)` matched at
/// `start`, as Onigmo backtracks: the left number greedy (then shorter),
/// one or more spaces, the operator, spaces, the right number greedy.
fn match_op_at(
  chars : Array[Char],
  start : Int,
  ops : String,
) -> (Int, String, Char, String)? {
  let n = chars.length()
  let mut i = start
  if i < n && chars[i] == '-' {
    i += 1
  }
  let digits = i
  while i < n && is_digit(chars[i]) {
    i += 1
  }
  if i == digits {
    return None
  }
  // candidate ends of the left number: with the fraction, then without
  let ends : Array[Int] = []
  if i + 1 < n && chars[i] == '.' && is_digit(chars[i + 1]) {
    let mut j = i + 1
    while j < n && is_digit(chars[j]) {
      j += 1
    }
    ends.push(j)
  }
  ends.push(i)
  for left_end in ends {
    let mut k = left_end
    if k >= n || chars[k] != ' ' {
      continue
    }
    while k < n && chars[k] == ' ' {
      k += 1
    }
    if k >= n || !ops.contains_char(chars[k]) {
      continue
    }
    let op = chars[k]
    k += 1
    if k >= n || chars[k] != ' ' {
      continue
    }
    while k < n && chars[k] == ' ' {
      k += 1
    }
    match number_after(chars, k) {
      Some(right_end) =>
        return Some(
          (
            right_end,
            String::from_array(chars[start:left_end]),
            op,
            String::from_array(chars[k:right_end]),
          ),
        )
      None => ()
    }
  }
  None
}

///|
fn count_chars(s : String, set : String) -> Int {
  let mut n = 0
  for c in s {
    if set.contains_char(c) {
      n += 1
    }
  }
  n
}

///|
/// `ThemeLoader#evaluate_math`: measurements to points, then `*`, `/`,
/// `^`, then `+`, `-` (each repeatedly, left to right, operands and spaced
/// operators only), then an outer `round(...)`, `floor(...)` or
/// `ceil(...)`; a changed expression becomes a number (an Integer when it
/// is whole).
fn evaluate_math(value : Value) -> Value {
  guard value is Str(original) else { return value }
  let mut expr = resolve_measurement_values(original)
  while count_chars(expr, "*/^") > 0 {
    let result = apply_ops(expr, "*/^")
    let unchanged = result == expr
    expr = result
    if unchanged {
      break
    }
  }
  while count_chars(expr, "+-") > 0 {
    let result = apply_ops(expr, "+-")
    let unchanged = result == expr
    expr = result
    if unchanged {
      break
    }
  }
  // PrecisionFuncRx = /^(round|floor|ceil)\(/
  if expr.has_suffix(")") {
    for op in ["round", "floor", "ceil"] {
      if expr.has_prefix(op + "(") {
        let inner = ruby_string_to_f(
          expr[op.length() + 1:expr.length() - 1].to_owned(),
        )
        let rounded = match op {
          // Float#round: half away from zero
          "round" => {
            let a = inner.abs()
            let r = if a - a.floor() >= 0.5 {
              a.floor() + 1.0
            } else {
              a.floor()
            }
            if inner < 0.0 {
              -r
            } else {
              r
            }
          }
          "floor" => inner.floor()
          _ => inner.ceil()
        }
        return Int(float_to_i(rounded))
      }
    }
  }
  if expr == original {
    return value
  }
  let int_val = ruby_string_to_i(expr)
  let flt_val = ruby_string_to_f(expr)
  if int_val.to_double() == flt_val {
    Int(int_val)
  } else {
    Float(flt_val)
  }
}

///|
/// `ThemeLoader#to_color`
pub fn to_color(value : Value) -> Value {
  let value = match value {
    Hex(_) | Transparent | Cmyk(_) => return value
    Array(items) =>
      match items.length() {
        4 => {
          let cmyk = items.map(e => {
            let f = match e {
              Int(i) =>
                if i > 1L {
                  i.to_double()
                } else {
                  i.to_double() * 100.0
                }
              Float(f) => if f > 1.0 { f } else { f * 100.0 }
              other => {
                let s = other.to_ruby_s()
                ruby_string_to_f(
                  if s.has_suffix("%") {
                    s[:s.length() - 1].to_owned()
                  } else {
                    s
                  },
                )
              }
            }
            if f == float_to_i(f).to_double() {
              Int(float_to_i(f))
            } else {
              Float(f)
            }
          })
          let ints = cmyk.map(v => v.to_f())
          if ints.iter().all(x => x == 0.0) {
            return Hex("FFFFFF")
          }
          if ints.iter().all(x => x == 100.0) {
            return Hex("000000")
          }
          return Cmyk(cmyk)
        }
        3 => {
          let sb = StringBuilder()
          for e in items {
            let n = match e {
              Int(i) => i
              Float(f) => float_to_i(f.floor())
              other => ruby_string_to_i(other.to_ruby_s())
            }
            let hex = if n < 0L {
              ".." + (256L + n).to_string(radix=16).to_upper()
            } else {
              n.to_string(radix=16).to_upper()
            }
            if hex.length() < 2 {
              sb.write_char('0')
            }
            sb.write_string(hex)
          }
          return Hex(sb.to_string())
        }
        // a nonsense array: flattened to a string
        _ => items.map(e => e.to_ruby_s()).join("")
      }
    Str(s) =>
      if s == "transparent" {
        return Transparent
      } else if s.length() == 6 {
        return Hex(s.to_upper())
      } else {
        s
      }
    Null => return Null
    // an Integer (usually), coerced to a string
    other => {
      let s = other.to_ruby_s()
      if s.length() == 6 {
        return Hex(s.to_upper())
      }
      s
    }
  }
  let resolved = match value.length() {
    6 => value
    // expand hex shorthand (f00 -> ff0000)
    3 => {
      let sb = StringBuilder()
      for c in value {
        sb.write_char(c)
        sb.write_char(c)
      }
      sb.to_string()
    }
    // truncate or pad with leading zeros (ff -> 0000ff)
    _ => {
      let v = if value.length() > 6 { value[:6].to_owned() } else { value }
      let sb = StringBuilder()
      for _ in 0..<(6 - v.length()) {
        sb.write_char('0')
      }
      sb.write_string(v)
      sb.to_string()
    }
  }
  Hex(resolved.to_upper())
}
