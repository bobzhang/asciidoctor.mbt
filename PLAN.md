# Asciidoctor → MoonBit port plan

Upstream: `.repos/asciidoctor` (asciidoctor/asciidoctor @ `30fb8cd`, Ruby, ~19.3k lines in `lib/`,
~3,000 minitest cases in `test/`). Target module: `bobzhang/asciidoctor`.

## 0. Decisions (confirmed with user)

| Topic | Decision |
|---|---|
| Module | `bobzhang/asciidoctor` |
| v1 scope | Core (reader/parser/substitutions/model) + HTML5 at byte-exact parity; then DocBook5 and manpage; then extensions API + CLI. Skip Ruby-only syntax highlighters (rouge/pygments/coderay) and Tilt templates; keep highlight.js/prettify (pure HTML output). |
| Regex | Own backtracking regex engine (Onigmo/Ruby-syntax subset) over UTF-16, so the ~100 named regexes in `rx.rb` and ~200 inline `sub/gsub/match` sites can be ported nearly verbatim. Hot paths get hand-written scanners later, verified differentially against the regex. |
| IO | `moonbitlang/async` (native + wasm). Core stays **synchronous and pure**; all file access goes through a `Vfs` interface (see §4). |
| VCS | git; `.repos/` ignored. |

## 1. Why these shapes

* Ruby Asciidoctor is a Ruby-flavoured regex machine: rx.rb has 73 top-level `*Rx` constants plus the
  quote/replacement tables in `asciidoctor.rb`; they use ~60 lookarounds (`(?=`, `(?!`, `(?<!`),
  lazy quantifiers, backrefs (`\1` in section titles/delimiters), `\p{Word}`/`\p{Alpha}`/`\p{Blank}`,
  `\A`/`\z`/`\Z`, and Ruby's `/m` (= dot-all, *not* multiline). `moonbitlang/regexp` is a Pike VM with
  no lookaround and no start offset, so it can't be used.
* MoonBit strings are UTF-16 like JavaScript; Asciidoctor.js (Opal → JS regex over UTF-16) is proof
  this semantic works. Where Ruby counts codepoints (tab expansion, `truncate`, counters) we must count
  scalars explicitly (Codex found: parser.rb:2725, document.rb:1132).
* Ruby's class hierarchy (AbstractNode → AbstractBlock → Document/Section/Block/List/ListItem/Table/Cell,
  Inline) is tightly mutually recursive with Parser/Reader/Substitutors/Converter. Splitting these into
  separate MoonBit packages creates cycles, so the core is **one package split into many files**.

## 2. Package layout

```
moon.mod                      bobzhang/asciidoctor
regex/                        public: backtracking regex engine (Ruby syntax subset, UTF-16)
internal/rb/                  Ruby-compat string helpers (strip/rstrip/chomp/squeeze/split semantics,
                              upcase/downcase, to_i, succ, Integer parsing, CGI escape, uri encode…)
core/  (package "asciidoctor/core" – the engine; many small files)
  attrs.mbt                   AttrValue, AttrKey, Attributes (ordered map) + Ruby-truthiness helpers
  node.mbt                    Node struct (common data) + NodeKind payload enum
  abstract_node.mbt           attr/attr?/set_attr/role/option/image_uri/media_uri/… (abstract_node.rb)
  abstract_block.mbt          blocks/content_model/find_by/xreftext/sections/assign_numeral… (abstract_block.rb)
  document.mbt  section.mbt  block.mbt  list.mbt  table.mbt  inline.mbt  callouts.mbt
  rx.mbt                      every constant from rx.rb, compiled lazily (Regex values)
  reader.mbt  preprocessor_reader.mbt   (reader.rb, incl. include:: / ifdef / tags / lines)
  parser*.mbt                 parser.rb split: header, sections, blocks, lists, tables, attributes
  attribute_list.mbt          attribute_list.rb (already a scanner in Ruby)
  substitutors*.mbt           substitutors.rb split: passthroughs, specialchars, quotes, attributes,
                              replacements, macros, post_replacements, callouts, highlight
  path_resolver.mbt  helpers.mbt  logging.mbt  vfs.mbt  timings.mbt
  converter.mbt               Converter trait, Transform enum, registry, backend traits
  syntax_highlighter.mbt      trait + highlight.js/prettify adapters
  extensions.mbt              typed callback registries (later phase)
converter/html5/              html5.rb (+ stylesheets data embedded as string constants)
converter/docbook5/           docbook5.rb
converter/manpage/            manpage.rb
asciidoctor/ (root pkg)       facade: load/convert/load_file/convert_file, default converter wiring
io/                           moonbitlang/async-backed Vfs + convert_file drivers
cmd/asciidoctor/              CLI (cli/options.rb + invoker.rb), is-main
tests/golden/                 generated fixtures + runner
scripts/                      Ruby harvesting scripts (golden extraction), fixture regeneration
```

Converters sit in their own packages and depend on `core`; `core` only knows the `Converter`
trait, so there is no cycle. The facade registers html5/docbook5/manpage by backend name.

## 3. Data model

* `Node` = one mutable struct with common fields (`id`, `context`, `node_name`, `parent : Node?`,
  `document`, `attributes`, `blocks`, `subs`, `content_model`, `style`, `title`, `caption`,
  `numeral`, `source_location`, …) plus `kind : NodeKind` payload enum:
  `Document(DocumentData) | Section(SectionData) | Block(BlockData) | List | ListItem(ListItemData) |
  Table(TableData) | TableColumn | TableCell(CellData) | Inline(InlineData)`.
  GC handles parent↔child cycles; no arena needed. Identity comparison via `physical_equal`.
* `AttrValue = Str(String) | Int(Int) | True | Nil` — map *absence* ≠ `Nil`. Helpers mirror Ruby:
  `attr(name, default?)` (truthiness), `attr?(name, expected?)` (presence), `to_s` coercion.
  Keys: `AttrKey = Name(String) | Pos(Int)` in an insertion-ordered `Map` (Ruby Hash semantics).
  Symbol-keyed internals (`:attribute_entries`, `:refs`, …) become typed fields.
* Attribute playback: `Document` keeps header attrs snapshot + `attribute_entries` per block and
  replays them during conversion (document.rb:839, abstract_block.rb:75). Implemented in phase 2, not later.
* Converter dispatch: `enum Transform` (`Paragraph`, `Section`, `InlineQuoted`, … , `Custom(String)`),
  `trait Converter { convert(Self, Node, Transform) -> String }`, plus a handler-override map so the
  extension API can replace single transforms (≈ Ruby's `convert_<name>` override / composite converter).
* Ruby nil/false → `Option`/`Bool`; Ruby's "return nil if unchanged" bang methods are rewritten to return
  the new string. `$~`/`$1` become explicit `MatchData` values.

## 4. IO design (moonbitlang/async while keeping the core sync)

Include directives, docinfo, stylesheets and data-URI images are read *during* parsing/conversion,
and which files are needed depends on earlier content (conditionals, attributes). Making the whole
parser async would slow it and infect every API. Instead:

1. `core` defines a synchronous `Vfs` trait: `read(path) -> Bytes?`, `exists`, `is_file`, `is_dir`.
   Default impls: `MemoryVfs` (tests, browser/wasm embedders) and `NoVfs` (secure mode).
2. `io/` provides `async fn convert_file(...)` using a **caching VFS with a fixpoint loop**: run the
   (fast, pure) pipeline; every miss is recorded; asynchronously load all missed paths with
   `@fs.read_file` (recording non-existent ones as absent); rerun until no new misses.
   Rounds ≈ include nesting depth + 1. The final run sees every file it asks for, so output is exact.
3. Output writing (`to_file`, `to_dir`, `mkdirs`, copying stylesheets) happens in `io/` after conversion.

## 5. Regex engine (`regex/`)

* Backtracking matcher compiled from pattern string to a node program; operates on `String` code units
  with absolute offsets: `Regex::match_at(s, pos)`, `Regex::find(s, from)`, `find_all`, `replace(s, fn)`,
  `split`, `MatchData { begin(i), end(i), group(i), named(name), pre, post }`.
* Syntax: literals/escapes (`\n \t \\ \/ \x.. \u....`), `.`, classes incl. ranges, negation, nested
  `\p{…}`/`\s\d\w\h\S\D\W`, POSIX-ish `\p{Alpha} \p{Alnum} \p{Word} \p{Blank} \p{Space}`, anchors
  `^ $ \A \z \Z \b \B \G`(if used), groups `( ) (?: ) (?<name> )`, lookaround `(?= ) (?! ) (?<= ) (?<! )`,
  quantifiers `* + ? {n} {n,} {n,m}` + lazy `?` + possessive (if used), alternation, backrefs `\1`,
  flags `m` (dot-all, Ruby meaning), `i`, `x` (if used).
* Ruby semantics: `^`/`$` are always line anchors; `$` matches before `\n`; unmatched backref fails.
* Surrogate pairs: `.` and classes consume a full code point; `\p{…}` tests the scalar.
* Unicode tables for Alpha/Alnum/Word/Space generated from UCD (script under `scripts/`), as
  compressed range arrays.
* Safety: iterative backtracking with explicit stack (no host-stack overflow on long lines); memoize
  nothing initially, profile later.
* Tests: unit tests per construct + a differential test file generated by running every rx.rb regex
  in Ruby over a corpus of lines (`scripts/regex_oracle.rb` → JSON of `{pattern, input, captures}`).

## 6. Testing strategy

1. **Golden corpus from the Ruby test-suite** (`scripts/harvest.rb`): monkey-patch
   `Asciidoctor.load`/`convert` inside `test/test_helper.rb` run, recording
   `{test_file, test_name, input, options (normalized), output, warnings}` for every call → JSON under
   `tests/golden/`. Pin `SOURCE_DATE_EPOCH`, paths relative to ROOT_DIR, record virtual files read.
   This gives thousands of exact input/output pairs cheaply. Track pass/fail/unsupported per test file.
2. **Real-document corpus**: `docs/**/*.adoc` (100 files, 9.6k lines), README*.adoc, test fixtures;
   Ruby output as golden (embedded + standalone).
3. **Hand-ported unit tests** for non-conversion APIs: Reader, AttributeList, Parser helpers,
   substitution functions, PathResolver, Helpers, document attribute/API tests, logger messages.
4. Regex differential tests (§5).
5. Runner: a `moon test` suite that iterates JSON fixtures (loaded as embedded strings or via async fs on
   native) and reports a diff; `scripts/status.sh` prints a per-feature scoreboard. Snapshot `inspect`
   tests for small units.

## 7. Porting order (vertical slices, each ends green on its golden subset)

| # | Milestone | Ruby sources | Exit criterion |
|---|---|---|---|
| 0 | Scaffold, git, CI script, harvest tooling | – | `moon test` runs; goldens generated |
| 1 | Regex engine + Unicode tables | rx.rb | all rx.rb patterns compile; differential tests pass |
| 2 | rb helpers, logging, AttrValue, Node model, Document attrs & playback | helpers, logging, abstract_node/block, document (attrs) | unit tests |
| 3 | Reader + PreprocessorReader (conditionals, include via Vfs, tags, lines) | reader.rb | reader_test goldens |
| 4 | Substitutors (all subs), AttributeList | substitutors.rb, attribute_list.rb | substitutions_test, attribute_list_test, text_test |
| 5 | Parser: header, sections, paragraphs, delimited blocks, lists, tables, callouts | parser.rb, section/block/list/table.rb | sections/blocks/lists/tables/paragraphs/preamble goldens |
| 6 | HTML5 converter + stylesheet data + highlight.js/prettify | converter/html5.rb, stylesheets.rb | embedded & standalone goldens, docs/ corpus |
| 7 | Facade API (load/convert/*_file), io/ with async Vfs, CLI | asciidoctor.rb, load.rb, convert.rb, cli/* | api_test, options/invoker subset, docs corpus |
| 8 | DocBook5, manpage converters | docbook5.rb, manpage.rb | manpage_test, docbook goldens |
| 9 | Extensions API (typed registries) | extensions.rb | extensions_test subset |
| 10 | Performance: scanners for hot regexes (block attribute line, quotes, list markers), profiling | – | benchmark vs Ruby |

## 8. Known pitfalls checklist

* Ruby `/m` = dot-all; `^`/`$` always per-line; `\Z` allows trailing `\n`.
* UTF-16 offsets vs Ruby char indices (tabs, truncate, counters incl. emoji); never split surrogates.
* Ruby `strip`/`rstrip` strip `\0` and ASCII whitespace only (not Unicode spaces); `split` without limit
  drops trailing empties; `String#to_i` is lenient.
* Truthiness: only `nil`/`false` are false; `""` and `0` are true (e.g. empty-string options enabled).
* CRLF/BOM normalization, trailing blank-line trimming exactly as `Helpers.prepare_source_*`.
* Hash insertion order is significant (attribute output order, footnotes, refs).
* Keep substitution order and passthrough extraction/restoration exactly (substitutors.rb:16, :80).
* Frozen/shared strings: MoonBit strings are immutable – replace `<<`/`sub!` with builders.
* Warnings text and `source_location` must match (tests assert log messages).

## 9. Status log

### 2026-09-26
* Milestones 0–6 done: regex engine (4,929-case Ruby differential oracle passes), Ruby helpers, core model,
  reader/preprocessor, attribute lists, substitutions, parser, HTML5 converter, client-side highlighters
  (highlight.js, prettify, html-pipeline), facade `load`/`convert`.
* Golden harness: `scripts/harvest.sh` (runs upstream suite with `scripts/harvest/harvest.rb`) records
  2,901 documents (source, options, Compliance overrides, files read, AST snapshot, outputs, messages).
  `moon run cmd/golden --target native` replays them.
* Parity: AST 2426/2532, HTML output 1427/1542 (skipped: DocBook/manpage backends, extension registries,
  custom converters). Remaining HTML failures are mostly server-side highlighters (Rouge/CodeRay/Pygments),
  extensions, remote URIs (local HTTP server in the Ruby suite), and tests that mutate the model via API
  between load and convert (need hand-ported tests).
* Ruby quirks reproduced deliberately: list continuation placeholder identity (tracked as per-line marker
  flags in Reader), implicit ordered-list style as Symbol (no `type` attr), `@reftexts` partial map during
  `resolve_id`, Integer/Float distinction in table column widths.

### 2026-09-26 (later)
* DocBook5 and manpage converters ported (in parallel worktrees) and merged; extensions API
  (typed registry + processor helpers) with scenario tests generated against Ruby; `io/` package
  (async caching VFS with fixpoint reruns, `load_file`/`convert_file`), and the `asciidoctor` CLI.
* Parity: AST 2506/2612, output 1699/1819; **0 unexpected failures** — the remaining 226 are listed and
  categorized in `tests/golden/known_failures.txt` (Ruby extension DSL 78, server-side highlighters 91,
  remote URIs 13, API mutation 11, misc 3).
* Real-world check: `scripts/corpus_compare.sh` — all 100 files of the Asciidoctor documentation convert
  byte-identically to Ruby (HTML and warnings).
* Performance (release native): 38k-line document converts in 0.19s CPU vs Ruby 0.58s; wall time is
  dominated by a fixed ~0.36s startup/teardown latency of the `moonbitlang/async` runtime (an empty
  `async fn main` shows the same), worth reporting upstream.
* Tests pass on native, wasm-gc and js.

## 10. Next steps
1. Hand-port API-level tests not expressible as goldens (reader/document/node APIs, API mutation cases).
2. Server-side syntax highlighting adapter interface is in place; a Rouge-compatible lexer set is out of
   scope for now.
3. Profile hot paths (block attribute line, quote regexes) and add scanners where the regex engine
   dominates; add memoization to the regex VM if pathological patterns appear.
4. Report the async-runtime exit latency upstream; consider a sync fast path for stdin/stdout-only CLI use.
