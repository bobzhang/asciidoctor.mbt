// Ported from test/paths_test.rb. The port only supports POSIX separators, so
// these are skipped:
// - Web Paths: 'posixifies windows paths'
// - System Paths: 'posixifies windows paths', 'resolves windows paths when
//   file separator is backlash', 'resolves UNC path if target is UNC path'
//   (backslash form), 'File.dirname preserves (posix-style) UNC path root on
//   Windows', 'should return original path if relative path cannot be
//   computed' (Windows-only), the three JRuby 'classloader path' tests, and
//   the drive-letter (C:/, D:/) assertions inside 'treats absolute target
//   outside of jail as relative...', 'warns if start is not contained within
//   jail', 'allows start path to be parent of jail...' and 'relocates target
//   to jail...' (their POSIX assertions are ported).
// `web_path(nil, start)` / `system_path(t, nil)` map to omitting the argument.
// The Ruby resolver's working_dir is Dir.pwd; here it is set explicitly.

///|
let jail = "/home/doctor/docs"

///|
fn sys(
  r : @core.PathResolver,
  target : String?,
  start? : String,
  jail? : String,
) -> (String, String) {
  let (result, msgs) = @core.with_memory_logger(() => {
    try! r.system_path(target, start?, jail?)
  })
  (result, log_lines(msgs))
}

///|
test "Web Paths: target with absolute path" {
  let r = @core.PathResolver::new()
  inspect(r.web_path("/images"), content="/images")
  inspect(r.web_path("/images", start=""), content="/images")
}

///|
test "Web Paths: target with relative path" {
  let r = @core.PathResolver::new()
  inspect(r.web_path("images"), content="images")
  inspect(r.web_path("images", start=""), content="images")
}

///|
test "Web Paths: target with hidden relative path" {
  let r = @core.PathResolver::new()
  inspect(r.web_path(".images"), content=".images")
  inspect(r.web_path(".images", start=""), content=".images")
}

///|
test "Web Paths: target with path relative to current directory" {
  let r = @core.PathResolver::new()
  inspect(r.web_path("./images"), content="./images")
  inspect(r.web_path("./images", start=""), content="./images")
}

///|
test "Web Paths: target with absolute path ignores start path" {
  let r = @core.PathResolver::new()
  inspect(r.web_path("/images", start="foo"), content="/images")
  inspect(r.web_path("/images", start="/foo"), content="/images")
  inspect(r.web_path("/images", start="./foo"), content="/images")
}

///|
test "Web Paths: target with relative path appended to start path" {
  let r = @core.PathResolver::new()
  inspect(r.web_path("images", start="assets"), content="assets/images")
  inspect(r.web_path("images", start="/assets"), content="/assets/images")
  inspect(r.web_path("images", start="./assets"), content="./assets/images")
  inspect(r.web_path("theme.css", start="/"), content="/theme.css")
  inspect(r.web_path("theme.css", start="/css/"), content="/css/theme.css")
}

///|
test "Web Paths: target with path relative to current directory appended to start path" {
  let r = @core.PathResolver::new()
  inspect(r.web_path("./images", start="assets"), content="assets/images")
  inspect(r.web_path("./images", start="/assets"), content="/assets/images")
  inspect(r.web_path("./images", start="./assets"), content="./assets/images")
}

///|
test "Web Paths: target with relative path appended to url start path" {
  let r = @core.PathResolver::new()
  inspect(
    r.web_path("images", start="http://www.example.com/assets"),
    content="http://www.example.com/assets/images",
  )
}

///|
test "Web Paths: normalize target" {
  let r = @core.PathResolver::new()
  inspect(r.web_path("../images/../images"), content="../images")
}

///|
test "Web Paths: append target to start path and normalize" {
  let r = @core.PathResolver::new()
  inspect(
    r.web_path("../images/../images", start="../images"),
    content="../images",
  )
  inspect(r.web_path("../images", start=".."), content="../../images")
}

///|
test "Web Paths: normalize parent directory that follows root" {
  let r = @core.PathResolver::new()
  inspect(r.web_path("/../tiger.png"), content="/tiger.png")
  inspect(r.web_path("/../../tiger.png"), content="/tiger.png")
}

///|
test "Web Paths: uses start when target is empty" {
  let r = @core.PathResolver::new()
  // web_path(nil, start) has no counterpart (target is a String); "" covers both
  inspect(r.web_path("", start="assets/images"), content="assets/images")
}

///|
test "Web Paths: URL encode spaces in path" {
  let r = @core.PathResolver::new()
  inspect(
    r.web_path("lots of images", start="assets and stuff"),
    content="assets%20and%20stuff/lots%20of%20images",
  )
}

///|
test "System Paths: raises security error if jail is not an absolute path" {
  let r = @core.PathResolver::new()
  try r.system_path(Some("images/tiger.png"), start="/etc", jail="foo") catch {
    @core.SecurityError(_) => ()
  } noraise {
    _ => fail("expected SecurityError")
  }
}

///|
test "System Paths: prevents access to paths outside of jail" {
  let r = @core.PathResolver::new()
  debug_inspect(
    sys(
      r,
      Some("../../../../../css"),
      start="\{jail}/assets/stylesheets",
      jail~,
    ),
    content=(
      #|(
      #|  "/home/doctor/docs/css",
      #|  "WARN: path has illegal reference to ancestor of jail; recovering automatically",
      #|)
    ),
  )
  debug_inspect(
    sys(
      r,
      Some("/../../../../../css"),
      start="\{jail}/assets/stylesheets",
      jail~,
    ),
    content=(
      #|(
      #|  "/home/doctor/docs/css",
      #|  "WARN: path is outside of jail; recovering automatically",
      #|)
    ),
  )
  debug_inspect(
    sys(r, Some("../../../css"), start="../../..", jail~),
    content=(
      #|(
      #|  "/home/doctor/docs/css",
      #|  "WARN: path has illegal reference to ancestor of jail; recovering automatically",
      #|)
    ),
  )
}

///|
test "System Paths: throws exception for illegal path access if recover is false" {
  let r = @core.PathResolver::new()
  try
    r.system_path(
      Some("../../../../../css"),
      start="\{jail}/assets/stylesheets",
      jail~,
      recover=false,
    )
  catch {
    @core.SecurityError(_) => ()
  } noraise {
    _ => fail("expected SecurityError")
  }
}

///|
test "System Paths: resolves start path if target is empty" {
  let r = @core.PathResolver::new()
  inspect(
    r.system_path(Some(""), start="\{jail}/assets/stylesheets", jail~),
    content="/home/doctor/docs/assets/stylesheets",
  )
  inspect(
    r.system_path(None, start="\{jail}/assets/stylesheets", jail~),
    content="/home/doctor/docs/assets/stylesheets",
  )
}

///|
test "System Paths: expands parent references in start path if target is empty" {
  let r = @core.PathResolver::new()
  inspect(
    r.system_path(Some(""), start="\{jail}/assets/../stylesheets", jail~),
    content="/home/doctor/docs/stylesheets",
  )
}

///|
test "System Paths: expands parent references in start path if target is not empty" {
  let r = @core.PathResolver::new()
  inspect(
    r.system_path(
      Some("site.css"),
      start="\{jail}/assets/../stylesheets",
      jail~,
    ),
    content="/home/doctor/docs/stylesheets/site.css",
  )
}

///|
test "System Paths: resolves start path if target is dot" {
  let r = @core.PathResolver::new()
  inspect(
    r.system_path(Some("."), start="\{jail}/assets/stylesheets", jail~),
    content="/home/doctor/docs/assets/stylesheets",
  )
  inspect(
    r.system_path(Some("./"), start="\{jail}/assets/stylesheets", jail~),
    content="/home/doctor/docs/assets/stylesheets",
  )
}

///|
test "System Paths: treats absolute target outside of jail as relative when jail is specified" {
  let r = @core.PathResolver::new()
  debug_inspect(
    sys(r, Some("/"), start="\{jail}/assets/stylesheets", jail~),
    content=(
      #|(
      #|  "/home/doctor/docs",
      #|  "WARN: path is outside of jail; recovering automatically",
      #|)
    ),
  )
  debug_inspect(
    sys(r, Some("/foo"), start="\{jail}/assets/stylesheets", jail~),
    content=(
      #|(
      #|  "/home/doctor/docs/foo",
      #|  "WARN: path is outside of jail; recovering automatically",
      #|)
    ),
  )
  debug_inspect(
    sys(r, Some("/../foo"), start="\{jail}/assets/stylesheets", jail~),
    content=(
      #|(
      #|  "/home/doctor/docs/foo",
      #|  "WARN: path is outside of jail; recovering automatically",
      #|)
    ),
  )
}

///|
test "System Paths: allows use of absolute target or start if resolved path is sub-path of jail" {
  let r = @core.PathResolver::new()
  let expected = "/home/doctor/docs/my/path"
  assert_eq(r.system_path(Some("\{jail}/my/path"), start="", jail~), expected)
  assert_eq(r.system_path(Some("\{jail}/my/path"), jail~), expected)
  assert_eq(r.system_path(Some(""), start="\{jail}/my/path", jail~), expected)
  assert_eq(r.system_path(None, start="\{jail}/my/path", jail~), expected)
  assert_eq(r.system_path(Some("path"), start="\{jail}/my", jail~), expected)
  inspect(
    r.system_path(Some("/foo/bar/baz.adoc"), jail="/"),
    content="/foo/bar/baz.adoc",
  )
  inspect(
    r.system_path(Some("baz.adoc"), start="/foo/bar", jail="/"),
    content="/foo/bar/baz.adoc",
  )
  inspect(
    r.system_path(Some("baz.adoc"), start="foo/bar", jail="/"),
    content="/foo/bar/baz.adoc",
  )
}

///|
test "System Paths: uses jail path if start path is empty" {
  let r = @core.PathResolver::new()
  inspect(
    r.system_path(Some("images/tiger.png"), start="", jail~),
    content="/home/doctor/docs/images/tiger.png",
  )
  inspect(
    r.system_path(Some("images/tiger.png"), jail~),
    content="/home/doctor/docs/images/tiger.png",
  )
}

///|
test "System Paths: warns if start is not contained within jail" {
  let r = @core.PathResolver::new()
  debug_inspect(
    sys(r, Some("images/tiger.png"), start="/etc", jail~),
    content=(
      #|(
      #|  "/home/doctor/docs/images/tiger.png",
      #|  "WARN: path is outside of jail; recovering automatically",
      #|)
    ),
  )
  debug_inspect(
    sys(r, Some("."), start="/etc", jail~),
    content=(
      #|(
      #|  "/home/doctor/docs",
      #|  "WARN: path is outside of jail; recovering automatically",
      #|)
    ),
  )
}

///|
test "System Paths: allows start path to be parent of jail if resolved target is inside jail" {
  let r = @core.PathResolver::new()
  inspect(
    r.system_path(Some("foo/path"), start=jail, jail="\{jail}/foo"),
    content="/home/doctor/docs/foo/path",
  )
}

///|
test "System Paths: relocates target to jail if resolved value fails outside of jail" {
  let r = @core.PathResolver::new()
  debug_inspect(
    sys(r, Some("bar/baz.adoc"), start=jail, jail="\{jail}/foo"),
    content=(
      #|(
      #|  "/home/doctor/docs/foo/bar/baz.adoc",
      #|  "WARN: path is outside of jail; recovering automatically",
      #|)
    ),
  )
}

///|
test "System Paths: raises security error if start is not contained within jail and recover is disabled" {
  let r = @core.PathResolver::new()
  for target in ["images/tiger.png", "."] {
    try r.system_path(Some(target), start="/etc", jail~, recover=false) catch {
      @core.SecurityError(_) => ()
    } noraise {
      _ => fail("expected SecurityError for \{target}")
    }
  }
}

///|
test "System Paths: expands parent references in absolute path if jail is not specified" {
  let r = @core.PathResolver::new()
  inspect(
    r.system_path(Some("/usr/share/../../etc/stylesheet.css")),
    content="/etc/stylesheet.css",
  )
}

///|
test "System Paths: resolves absolute directory if jail is not specified" {
  let r = @core.PathResolver::new()
  inspect(
    r.system_path(
      Some("/usr/share/stylesheet.css"),
      start="/home/dallen/docs/assets/stylesheets",
    ),
    content="/usr/share/stylesheet.css",
  )
}

///|
test "System Paths: resolves ancestor directory of start if jail is not specified" {
  let r = @core.PathResolver::new()
  inspect(
    r.system_path(
      Some("../../../../../usr/share/stylesheet.css"),
      start="/home/dallen/docs/assets/stylesheets",
    ),
    content="/usr/share/stylesheet.css",
  )
}

///|
test "System Paths: resolves absolute path if start is absolute and target is relative" {
  let r = @core.PathResolver::new()
  inspect(
    r.system_path(Some("assets/stylesheet.css"), start="/usr/share"),
    content="/usr/share/assets/stylesheet.css",
  )
}

///|
test "System Paths: resolves UNC path if start is absolute and target is relative" {
  let r = @core.PathResolver::new()
  inspect(
    r.system_path(
      Some("assets/stylesheet.css"),
      start="//QA/c$/users/asciidoctor",
    ),
    content="//QA/c$/users/asciidoctor/assets/stylesheet.css",
  )
}

///|
test "System Paths: resolves UNC path if target is posix-style UNC path" {
  let r = @core.PathResolver::new()
  inspect(
    r.system_path(Some("//server/docs/output.html")),
    content="//server/docs/output.html",
  )
}

///|
test "System Paths: resolves relative target relative to current directory if start is empty" {
  let r = @core.PathResolver::new(working_dir="/work/dir")
  inspect(
    r.system_path(Some("images/tiger.png"), start=""),
    content="/work/dir/images/tiger.png",
  )
  inspect(
    r.system_path(Some("images/tiger.png")),
    content="/work/dir/images/tiger.png",
  )
}

///|
test "System Paths: resolves relative hidden target relative to current directory if start is empty" {
  let r = @core.PathResolver::new(working_dir="/work/dir")
  inspect(
    r.system_path(Some(".images/tiger.png"), start=""),
    content="/work/dir/.images/tiger.png",
  )
  inspect(
    r.system_path(Some(".images/tiger.png")),
    content="/work/dir/.images/tiger.png",
  )
}

///|
test "System Paths: resolves and normalizes start when target is empty" {
  let r = @core.PathResolver::new(working_dir="/work/dir")
  inspect(
    r.system_path(Some(""), start="/home/doctor/docs"),
    content="/home/doctor/docs",
  )
  inspect(
    r.system_path(Some(""), start="/home/doctor/./docs"),
    content="/home/doctor/docs",
  )
  inspect(
    r.system_path(None, start="/home/doctor/docs"),
    content="/home/doctor/docs",
  )
  inspect(
    r.system_path(None, start="/home/doctor/./docs"),
    content="/home/doctor/docs",
  )
  inspect(
    r.system_path(None, start="assets/images"),
    content="/work/dir/assets/images",
  )
  debug_inspect(
    sys(r, Some(""), start="../assets/images", jail~).1,
    content=(
      #|"WARN: path has illegal reference to ancestor of jail; recovering automatically"
    ),
  )
}

///|
test "System Paths: should calculate relative path" {
  let r = @core.PathResolver::new()
  let filename = r.system_path(Some("part1/chapter1/section1.adoc"), jail~)
  inspect(filename, content="/home/doctor/docs/part1/chapter1/section1.adoc")
  inspect(
    r.relative_path(filename, jail),
    content="part1/chapter1/section1.adoc",
  )
}

///|
test "System Paths: should resolve relative path to filename outside of base directory" {
  let r = @core.PathResolver::new()
  inspect(
    r.relative_path("/home/shared/partials", "/home/user/docs"),
    content="../../shared/partials",
  )
}

///|
test "System Paths: should resolve relative path relative to base dir in unsafe mode" {
  let doc = @core.new_document(
    Some([]),
    @core.Options::new(base_dir="/base", safe=@core.SAFE_UNSAFE),
  )
  inspect(
    doc.normalize_system_path("tiger.png", start="images"),
    content="/base/images/tiger.png",
  )
}

///|
test "System Paths: should resolve absolute path as absolute in unsafe mode" {
  let doc = @core.new_document(
    Some([]),
    @core.Options::new(base_dir="/base", safe=@core.SAFE_UNSAFE),
  )
  inspect(
    doc.normalize_system_path("tiger.png", start="/etc/images"),
    content="/etc/images/tiger.png",
  )
}

///|
// Not in paths_test.rb: direct checks of the helper methods, with expected
// values taken from running Ruby Asciidoctor's PathResolver.
test "PathResolver helpers: partition_path, expand_path, descends_from" {
  let r = @core.PathResolver::new(working_dir="/w")
  debug_inspect(
    r.partition_path("/a/./b/../c"),
    content=(
      #|(["a", "b", "..", "c"], Some("/"))
    ),
  )
  debug_inspect(
    r.partition_path("./a/b"),
    content=(
      #|(["a", "b"], Some("./"))
    ),
  )
  debug_inspect(
    r.partition_path("a//b/"),
    content=(
      #|(["a", "", "b"], None)
    ),
  )
  debug_inspect(
    r.partition_path("//server/share/x"),
    content=(
      #|(["server", "share", "x"], Some("//"))
    ),
  )
  debug_inspect(
    r.partition_path("./a/b", web=true),
    content=(
      #|(["a", "b"], Some("./"))
    ),
  )
  debug_inspect(
    r.partition_path("/a/b", web=true),
    content=(
      #|(["a", "b"], Some("/"))
    ),
  )
  inspect(r.expand_path("/a/b/../c/./d"), content="/a/c/d")
  inspect(r.expand_path("a/../../b"), content="b")
  inspect(r.expand_path("./a/../b"), content="./b")
  debug_inspect(r.descends_from("/a/b/c", "/a/b"), content="Some(5)")
  debug_inspect(r.descends_from("/a/bc", "/a/b"), content="None")
  debug_inspect(r.descends_from("/a/b", "/"), content="Some(1)")
  debug_inspect(r.descends_from("/a/b", "/a/b"), content="Some(0)")
  inspect(r.relative_path("rel/x", "/a"), content="rel/x")
  inspect(r.relative_path("/a/b", "/a/b"), content="/a/b")
  assert_true(r.is_root("/x"))
  assert_false(r.is_root("x"))
  assert_true(r.is_unc("//x"))
  assert_true(r.is_web_root("/x"))
  assert_true(r.is_absolute("/x"))
  inspect(r.posixify(None), content="")
  inspect(r.posixify(Some("a/b")), content="a/b")
}
