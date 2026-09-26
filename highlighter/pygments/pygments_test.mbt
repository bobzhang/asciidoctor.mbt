// Tests of the Pygments adapter. The expected outputs are those of Ruby
// Asciidoctor with pygments.rb running Python Pygments 2.21 (the same cases
// are compared with Ruby by scripts/cli_parity.mbtx and scripts/corpus.mbtx
// --pygments).

///|
fn convert_with(
  input : String,
  attrs? : Array[(String, String)] = [],
  standalone? : Bool = false,
) -> String raise {
  @pygments.register()
  let attributes : Array[(String, @core.AttrVal)] = [
    ("source-highlighter", Str("pygments")),
  ]
  for a in attrs {
    attributes.push((a.0, Str(a.1)))
  }
  @asciidoctor.convert(
    input,
    options=@core.Options::new(safe=@core.SAFE_SAFE, attributes~, standalone~),
  )
}

///|
/// The contents of the `<head>` element of a standalone document.
fn head_of(html : String) -> String {
  let start = html.find("<head>").unwrap()
  let end = html.find("</head>").unwrap()
  html.unsafe_substring(start~, end=end + "</head>".length())
}

///|
let hello : String =
  #|[source,ruby]
  #|----
  #|puts 'Hello, World!'
  #|----

///|
test "register replaces the unavailable fallback" {
  @pygments.register()
  let doc = @asciidoctor.load(
    hello,
    options=@core.Options::new(attributes=[
      ("source-highlighter", Str("pygments")),
    ]),
  )
  let hl = doc.syntax_highlighter().unwrap()
  inspect(hl.name(), content="pygments")
  assert_true(hl.handles_highlighting())
  // specialcharacters is replaced by the highlight substitution
  inspect(
    doc.blocks[0].subs.map(s => s.name()).join(", "),
    content=(
      #|highlight
    ),
  )
}

///|
test "class mode: token classes and an embedded stylesheet" {
  let html = convert_with(hello)
  inspect(
    html,
    content=(
      #|<div class="listingblock">
      #|<div class="content">
      #|<pre class="pygments highlight"><code data-lang="ruby"><span></span><span class="tok-nb">puts</span><span class="tok-w"> </span><span class="tok-s1">'Hello, World!'</span></code></pre>
      #|</div>
      #|</div>
    ),
  )
  let head = head_of(convert_with(hello, standalone=true))
  assert_true(
    head.contains(
      "<style>\n\{@pygments.read_stylesheet(None)}\n</style>\n</head>",
    ),
  )
}

///|
test "linked stylesheet with linkcss" {
  let head = head_of(
    convert_with(
      hello,
      attrs=[
        ("linkcss", ""),
        ("stylesdir", "css"),
        ("pygments-style", "monokai"),
      ],
      standalone=true,
    ),
  )
  assert_true(
    head.contains(
      "<link rel=\"stylesheet\" href=\"css/pygments-monokai.css\">\n</head>",
    ),
  )
}

///|
test "style mode: inline styles and no stylesheet" {
  let html = convert_with(hello, attrs=[("pygments-css", "style")])
  inspect(
    html,
    content=(
      #|<div class="listingblock">
      #|<div class="content">
      #|<pre class="pygments highlight" style="background: #f8f8f8;"><code data-lang="ruby"><span></span><span style="color: #008000">puts</span><span style="color: #BBB"> </span><span style="color: #BA2121">'Hello, World!'</span></code></pre>
      #|</div>
      #|</div>
    ),
  )
  let head = head_of(
    convert_with(hello, attrs=[("pygments-css", "style")], standalone=true),
  )
  assert_false(head.contains("pre.pygments .tok-"))
}

///|
test "table line numbers with callouts" {
  let html = convert_with(
    (
      #|[source,ruby,linenums,start=9]
      #|----
      #|require 'app' # <1>
      #|
      #|launch_app # <2> <3>
      #|# <4>
      #|----
    ),
  )
  inspect(
    html,
    content=(
      #|<div class="listingblock">
      #|<div class="content">
      #|<pre class="pygments highlight"><code data-lang="ruby"><div class="lineno"><table class="linenotable"><tr><td class="linenos"><div class="linenodiv"><pre><span class="normal"> 9</span>
      #|<span class="normal">10</span>
      #|<span class="normal">11</span>
      #|<span class="normal">12</span></pre></div></td><td class="code"><div><pre><span></span><span class="tok-nb">require</span><span class="tok-w"> </span><span class="tok-s1">'app'</span><span class="tok-w"> </span># <b class="conum">(1)</b>
      #|
      #|<span class="tok-n">launch_app</span><span class="tok-w">  </span># <b class="conum">(2)</b> <b class="conum">(3)</b>
      #|# <b class="conum">(4)</b>
      #|</pre></div></td></tr></table></div></code></pre>
      #|</div>
      #|</div>
    ),
  )
}

///|
test "inline line numbers in both CSS modes" {
  let input =
    #|[source%linenums,ruby]
    #|----
    #|a = 1
    #|b = 2
    #|----
  inspect(
    convert_with(input, attrs=[("pygments-linenums-mode", "inline")]),
    content=(
      #|<div class="listingblock">
      #|<div class="content">
      #|<pre class="pygments highlight"><code data-lang="ruby"><span></span><span class="linenos">1</span><span class="tok-n">a</span><span class="tok-w"> </span><span class="tok-o">=</span><span class="tok-w"> </span><span class="tok-mi">1</span>
      #|<span class="linenos">2</span><span class="tok-n">b</span><span class="tok-w"> </span><span class="tok-o">=</span><span class="tok-w"> </span><span class="tok-mi">2</span></code></pre>
      #|</div>
      #|</div>
    ),
  )
  inspect(
    convert_with(input, attrs=[
      ("pygments-linenums-mode", "inline"),
      ("pygments-css", "style"),
    ]),
    content=(
      #|<div class="listingblock">
      #|<div class="content">
      #|<pre class="pygments highlight" style="background: #f8f8f8;"><code data-lang="ruby"><span></span><span class="linenos">1</span>a<span style="color: #BBB"> </span><span style="color: #666">=</span><span style="color: #BBB"> </span><span style="color: #666">1</span>
      #|<span class="linenos">2</span>b<span style="color: #BBB"> </span><span style="color: #666">=</span><span style="color: #BBB"> </span><span style="color: #666">2</span></code></pre>
      #|</div>
      #|</div>
    ),
  )
}

///|
test "highlighted lines" {
  inspect(
    convert_with(
      (
        #|[source,ruby,highlight=2..3]
        #|----
        #|a
        #|b
        #|c
        #|----
      ),
    ),
    content=(
      #|<div class="listingblock">
      #|<div class="content">
      #|<pre class="pygments highlight"><code data-lang="ruby"><span></span><span class="tok-n">a</span>
      #|<span class="hll"><span class="tok-n">b</span>
      #|</span><span class="hll"><span class="tok-n">c</span>
      #|</span></code></pre>
      #|</div>
      #|</div>
    ),
  )
}

///|
test "unknown or miscased language falls back to plain text" {
  inspect(
    convert_with(
      (
        #|[source,NoSuchLang]
        #|----
        #|x <y> & "z"
        #|----
      ),
    ),
    content=(
      #|<div class="listingblock">
      #|<div class="content">
      #|<pre class="pygments highlight"><code data-lang="NoSuchLang"><span></span>x &lt;y&gt; &amp; "z"</code></pre>
      #|</div>
      #|</div>
    ),
  )
}

///|
test "PHP starts inline unless the mixed option is set" {
  inspect(
    convert_with(
      (
        #|[source,php]
        #|----
        #|echo 1;
        #|----
        #|
        #|[source%mixed,php]
        #|----
        #|echo 1;
        #|----
      ),
    ),
    content=(
      #|<div class="listingblock">
      #|<div class="content">
      #|<pre class="pygments highlight"><code data-lang="php"><span></span><span class="tok-k">echo</span> <span class="tok-mi">1</span><span class="tok-p">;</span></code></pre>
      #|</div>
      #|</div>
      #|<div class="listingblock">
      #|<div class="content">
      #|<pre class="pygments highlight"><code data-lang="php"><span></span><span class="tok-x">echo 1;</span></code></pre>
      #|</div>
      #|</div>
    ),
  )
}

///|
test "adapter API: highlight with options and the returned offset" {
  let doc = @asciidoctor.load(hello)
  let node = doc.blocks[0]
  let hl = @pygments.adapter()
  let marks : @core.CalloutMarks = { 1: [(Nil, "1")] }
  let (html, offset) = hl.highlight(
    node,
    "puts 1\n",
    Some("ruby"),
    @core.HighlightOptions::new(
      callouts=marks,
      number_lines="table",
      start_line_number=1,
    ),
  )
  let offset = offset.unwrap()
  inspect(
    html.unsafe_substring(start=offset - 17, end=offset),
    content=(
      #|<td class="code">
    ),
  )
  // no stylesheet is needed until a block is highlighted in class mode
  let fresh = @pygments.adapter()
  assert_false(fresh.has_docinfo("head"))
  assert_true(hl.has_docinfo("head"))
  assert_false(hl.has_docinfo("footer"))
  assert_true(hl.writes_stylesheet(doc))
  inspect(
    hl.write_stylesheet(doc).map(f => f.0).join(", "),
    content=(
      #|pygments-default.css
    ),
  )
  let (_, offset) = hl.highlight(
    node,
    "puts 1\n",
    Some("ruby"),
    @core.HighlightOptions::new(number_lines="table", start_line_number=1),
  )
  assert_true(offset is None)
}

///|
test "stylesheet" {
  inspect(@pygments.stylesheet_basename(None), content="pygments-default.css")
  inspect(
    @pygments.stylesheet_basename(Some("monokai")),
    content="pygments-monokai.css",
  )
  let css = @pygments.read_stylesheet(None)
  // starts at the first rule for pre.pygments (Python emits rules for pre
  // and the line numbers before it)
  inspect(
    css.split("\n").take(3).map(l => l.to_owned()).collect().join("\n"),
    content=(
      #|pre.pygments .hll { background-color: #ffffcc }
      #|pre.pygments { background: #f8f8f8; }
      #|pre.pygments .tok-c { color: #3D7B7B; font-style: italic } /* Comment */
    ),
  )
  assert_false(css.has_suffix("\n"))
  // an unknown style falls back to the default one
  let html = convert_with(
    hello,
    attrs=[("pygments-style", "nope")],
    standalone=true,
  )
  assert_true(html.contains(css))
}
