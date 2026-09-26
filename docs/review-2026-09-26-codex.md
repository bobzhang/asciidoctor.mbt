The port has broad parser and conversion coverage, but **output parity currently overstates API, I/O, and failure-handling parity**. The highest-priority issues are the validation gates, safe-mode output paths, fixpoint behavior, and silent conversion failures.

I read `PLAN.md` and `README.mbt.md` first and verified upstream HEAD is `30fb8cd5f7145c57274b04524ceaa99812f830e0`. No files were modified. I ran the existing native binaries without rebuilding: golden replay reproduced **2506/2612 AST, 1705/1819 output, 220 known failures, 108 skipped records**. Those results validate the existing executable, not a fresh build.

**High-priority findings**

1. **Parity failures do not fail validation.**  
   [cmd/golden/main.mbt:423](../cmd/golden/main.mbt:423) collects and prints unexpected failures but exits normally. [scripts/corpus.mbtx](../scripts/corpus.mbtx) similarly prints differences without failing; `run_one` also discards subprocess exit codes. Consequently, [scripts/check.mbtx](../scripts/check.mbtx) can report success despite regressions. Both runners need failure exit statuses and minimum coverage checks.

2. **The checked-in CI cannot replay goldens from a clean checkout.**  
   [.github/workflows/ci.yml](../.github/workflows/ci.yml) never fetches upstream, while [golden/main.mbt:346](../cmd/golden/main.mbt:346) unconditionally resolves `.repos/asciidoctor` and loads its fixtures. `.repos/` is ignored. CI needs an explicit checkout at the pinned commit, or genuinely self-contained fixtures.

3. **Explicit output paths bypass upstream safe-mode confinement.**  
   [io/io.mbt:253](../io/io.mbt:253) resolves `Destination::File` and `to_dir` with `expand_path_from`, then writes directly. Ruby’s [convert.rb](../.repos/asciidoctor/lib/asciidoctor/convert.rb) applies `normalize_system_path(... recover: false)` with a jail for explicit destinations in safe mode. Thus a destination outside the permitted working/base directory can be written where Ruby rejects it. The port already has `normalize_system_path_checked`; the output driver should use equivalent rules.

4. **The I/O fixpoint can return an unfinished result as success.**  
   [run_with_files, io/io.mbt:130](../io/io.mbt:130) returns when `round >= max_rounds`, even with outstanding misses. With an increased include-depth limit, a sufficiently deep dependency chain can therefore produce incomplete output or provisional missing-file warnings. Exhaustion should raise a distinct error containing unresolved paths.

   There are two further correctness limitations:
   - `@io.load_file(...).convert()` discovers only parse-time files during loading. Conversion-time docinfo, stylesheet, or image misses are recorded in the returned `FsVfs`, but no driver fetches them.
   - Each retry re-executes extension callbacks. Captured counters, external effects, or mutable custom converter state are not rolled back. `snapshot_process_state` only snapshots one-time warning keys.

   The advertised “final run is exact” property requires deterministic, replay-safe callbacks and a completed fixpoint; the public API does not enforce either.

5. **Missing converters silently succeed, and facade loading overwrites custom registrations.**  
   [core/document.mbt:1553](../core/document.mbt:1553) installs `NullConverter`, which returns an empty string. Ruby raises `NotImplementedError`. I confirmed that the existing CLI accepts `-b does-not-exist`, emits only a newline, and exits **0**.

   Separately, [asciidoctor.mbt:60](../asciidoctor.mbt:60) calls each built-in `register()` on every load. These registrations overwrite existing factories, so registering a replacement for `html5` before calling the facade does not work. An explicit `Options.converter` remains a workaround.

6. **The regex engine has unbounded resource use.**  
   [regex/vm.mbt:150](../regex/vm.mbt:150) has no instruction budget, stack limit, timeout, or cancellation. Its explicit backtracking stack avoids recursion for ordinary branching, but does not prevent exponential work. Lookarounds and atomic subprograms still recursively call `run`, so deeply nested user-supplied patterns also retain host-stack risk.

   This matters because regex is public and extension macros accept custom regexes. The documented ordinary-document benchmark does not establish adversarial safety. Add bounded execution and adversarial tests before using it on untrusted patterns or documents.

**File-by-file upstream coverage**

“Ported” below means there is a substantial corresponding implementation, not that every behavior is proven equivalent.

| Upstream file(s) | Port and remaining gaps | Priority |
|---|---|---|
| `abstract_node.rb`, `abstract_block.rb` | Broad coverage in [core/node.mbt](../core/node.mbt). Attribute access, roles/options, traversal, titles, captions, numbering and mutation helpers exist. Public mutable fields can bypass invariant-preserving setters. | Medium |
| `block.rb`, `inline.rb`, `list.rb`, `section.rb` | Flattened into `Node`, with section logic in `section.mbt`. This is a workable cycle-breaking design, but every node exposes fields and methods meaningful only for other node kinds. | Medium |
| `table.rb` | Parsing/rendering are substantial, but `new_table_column`, `new_table_cell`, `create_columns`, `assign_column_widths`, `partition_header_footer`, and `reinitialize` are package-private in [core/table.mbt:153](../core/table.mbt:153). External extensions cannot reproduce Ruby’s table-construction API. | Medium |
| `attribute_list.rb` | Functional `parse_attribute_list` and `rekey_attributes` replace the object API. No direct `parse_into` equivalent; Ruby’s reusable parser object is not exposed. | Low |
| `callouts.rb` | Registration, lookup, rewind and list advancement exist. Ruby’s `current_list` inspection is private in [core/callouts.mbt:49](../core/callouts.mbt:49). | Low |
| `document.rb` | Broad attributes/catalog/parse/convert/docinfo coverage. Missing writer and timings integration; clock/timezone behavior differs; unknown backend handling differs. | High/Medium |
| `reader.rb` | Reader and preprocessor share [core/reader.mbt](../core/reader.mbt). Includes, conditions, tags and line selection exist. URI keys can be serviced by a custom VFS, but `FsVfs` supplies no HTTP transport. Encoding failures differ from Ruby. | Medium |
| `parser.rb` | Distributed across `parser_header`, `parser_blocks`, `parser_lists`, `parser_tables`. Most parser entry points are internal, unlike Ruby’s callable class methods. Some Ruby exceptions become aborts. | Medium |
| `substitutors.rb` | Broad substitution pipeline coverage. Server-side highlighting lacks significant upstream preprocessing/options/restoration behavior; see below. | Medium |
| `rx.rb` | Patterns are carried into `core/rx.mbt`; backed by a subset engine, not a general Ruby Regexp implementation. | Medium |
| `helpers.rb`, `path_resolver.rb` | Substantial path, text, encoding and URI helper coverage. Dynamic Ruby loading/reflection is deliberately absent. Filesystem and network responsibilities move to VFS/I/O. | Low/Medium |
| `logging.rb` | Structured logger and memory capture exist. Logging remains process-global; no document-scoped logger option equivalent to Ruby’s load option. | Medium |
| `converter.rb` | Factory registry and backend traits exist. No equivalent catch-all/unregister API or `handles?` capability contract; transform names remain unchecked strings. | Medium |
| `converter/composite.rb` | [CompositeConverter](../core/converter.mbt:100) is a handler map plus one delegate. It does not reproduce Ruby’s ordered converter chain, `converter_for`, `handles?` selection, `composed` hook, or conversion options argument. | Medium |
| `converter/html5.rb` | Substantial implementation, including XHTML mode. Ordinary output coverage is strong; template support is advertised in backend traits despite no template implementation. | Low/Medium |
| `converter/docbook5.rb` | Substantial implementation. AsciiMath-to-MathML is permanently unavailable in [docbook5.mbt:16](../converter/docbook5/docbook5.mbt:16); this is a further optional-library exclusion beyond the documented highlighter exclusions. | Medium |
| `converter/manpage.rb` | Rendering exists. Alternate man-name `.so` files are not written. Missing `mantitle` logs an error and returns empty output instead of raising. | Medium |
| `converter/template.rb` | Absent: template discovery, Tilt/ERB adapters, caches and template options. Deliberately excluded by the plan. | Low, if explicitly documented |
| `extensions.rb` | All eight processor categories exist as typed callbacks. Named group removal, registry reset/introspection, processor lookup and dynamic configuration/DSL semantics are incomplete or absent. | Medium |
| `syntax_highlighter.rb` | Adapter trait exists, but source offsets, stylesheet-writing hooks and full highlight options are absent. | Medium |
| `syntax_highlighter/{highlightjs,prettify,html_pipeline}.rb` | Implemented centrally in `core/converter.mbt`. | Low |
| `syntax_highlighter/{coderay,pygments,rouge}.rb`, `rouge_ext.rb` | Missing-library fallbacks only; actual server-side adapters and Rouge integrations are intentionally absent. | Low, as an explicit exclusion |
| `load.rb`, `convert.rb` | String/line loading plus separate async file APIs. No stream-input/output abstraction; file conversion always returns `String`, whereas Ruby returns `Document` when writing. Output options are split inconsistently between `Options` and driver arguments. | Medium |
| `stylesheets.rb` | Embedded primary CSS and default CSS copying exist. User stylesheet copying and highlighter stylesheet writing are missing. | Medium |
| `writer.rb` | No `Writer`/`VoidWriter` abstraction or `Document#write` equivalent. Custom converters cannot control file output. | Medium |
| `timings.rb` | Absent. CLI accepts `-t`/`--timings` but does nothing. | Medium |
| `cli.rb`, `cli/options.rb`, `cli/invoker.rb` | Common flags exist, but no reusable invoker API; source-root mapping, template/load-path/require flags and several OptionParser forms are missing. | Medium |
| `core_ext.rb`, `core_ext/*`, `version.rb` | Relevant compatibility behavior is folded into helpers/regex rather than monkey patches; tracked upstream version exists. This packaging difference is appropriate. | Low |

**Additional architectural issues**

- **Medium — “Pure core” is an overstatement.**  
  The core reads a clock and mutates global logger, compliance, converter/highlighter registries, extension groups and warning state. See [core/logging.mbt:133](../core/logging.mbt:133), [core/compliance.mbt](../core/compliance.mbt), and [core/document.mbt:1422](../core/document.mbt:1422). Async fixpoint calls can interleave between rounds and restore stale warning state. Prefer an explicit processing context containing configuration, services and registries.

- **Medium — The flattened model permits invalid combinations.**  
  [Node](../core/node.mbt:14) diverges from the planned tagged `NodeKind` payload: `context`, `node_name`, fields and optional private payloads can disagree. For example, direct assignment to `context` bypasses `set_context`; calling `table_data()` on a non-table aborts. Keep the cohesive core package, but tighten mutation and payload invariants before stabilizing the public API.

- **Medium — Error semantics are inconsistent and often unrecoverable.**  
  `create_image_block` aborts for a missing target where Ruby raises `ArgumentError`; parser failures also contain aborts. [Manpage conversion](../converter/manpage/document.mbt:7) instead logs and returns empty output, which need not fail the CLI’s default `Fatal` threshold. [FsVfs::fetch](../io/io.mbt:99) collapses all stat/read failures into “absent,” losing permission and other I/O errors. A typed conversion-error boundary would make embedding substantially safer.

- **Medium — Server-side highlighter support is only a partial contract.**  
  [highlight_source](../core/substitutors.mbt:694) passes an empty options map and applies callout substitution after highlighting. Ruby extracts callouts first, passes line numbering, highlighted lines, CSS/style options and callout metadata, then restores callouts using a possible source-line offset and repairs passthrough placeholders. Implementing a custom lexer against the current trait cannot reproduce that behavior.

- **Medium — UTF-16 search positions can split supplementary characters.**  
  Although VM character matching consumes scalars, [Regex::find_with](../regex/api.mbt:213) advances candidate positions one code unit at a time, and lookbehind does likewise. By inspection, `[^😀]` can fail at the emoji’s leading surrogate and then match its trailing surrogate. UTF-16 offsets are reasonable; allowing matching to begin inside a scalar is a separate correctness defect.

  Also, `compile(flags="i")` or `"x"` silently ignores those flags; only `m` is recognized. Unsupported flags should be rejected. [decode_text](../core/vfs.mbt:119) constructs UTF-16 text from individual units and calls a no-op `fix_surrogates`; malformed input is not validated like Ruby. These need explicit cross-target tests.

- **Medium — Time behavior differs outside the test environment.**  
  [format_epoch](../core/document.mbt:1448) always formats UTC. Ruby normally uses local time unless reproducibility settings apply. Tests pin UTC, concealing this difference. `SOURCE_DATE_EPOCH` is read by the CLI, but library users must set the global hook themselves.

- **Medium — CLI output paths have a second, divergent implementation.**  
  The stdin branch in [cmd/asciidoctor/main.mbt](../cmd/asciidoctor/main.mbt) writes directly, bypassing destination-directory handling and stylesheet copying. Multiple inputs with one explicit output also reuse and truncate that file. Argument handling rejects `--backend=html5` and `--`, silently defaults invalid log levels, and ignores timings/trace flags. I reproduced the `--backend=html5` rejection and no-op timings behavior.

**Test and validation gaps**

Beyond the failing gates above:

- **High:** Golden replay discards parse and conversion messages instead of comparing them: [main.mbt:235](../cmd/golden/main.mbt:235). Warning parity is not established by those totals.
- **Medium:** The shared `MemoryVfs` accumulates per-record files, allowing fixture contamination and order dependence. Malformed JSON records are silently skipped.
- **Medium:** Known failures are keyed by test name plus AST/output category, not individual harvested call or conversion. Another failure within an already-known test can be hidden.
- **Medium:** All **62 invoker records were skipped** in the observed run. `options`, `converter`, and `helpers` golden files contain zero records. Golden filenames are not evidence of API coverage.
- **Medium:** There are no dedicated tests in `io/` or `cmd/asciidoctor/`. Add integration coverage for convergence exhaustion, deferred conversion, extension replay, missing versus unreadable files, destination confinement, CSS copying, stdin, and exit statuses.
- **Medium:** Eight extension scenario tests are useful but do not replace the upstream registry lifecycle and processor-configuration suite.
- **Medium:** The regex oracle samples limited hits/misses and short random strings, skips interpolated patterns, and concentrates on matching. Add adversarial length growth, surrogate-boundary failures, invalid flags, replacement/split behavior and invalid-pattern tests.
- **Low:** Oracle random seeds use Ruby’s process-dependent `String#hash`. Regeneration also depends on the installed Ruby/Unicode versions. Pin those inputs and use a stable seed.
- **Medium:** Corpus checking defaults to embedded output; the standard check does not exercise standalone corpus conversion. Harvesting also ignores upstream process exit status, so incomplete harvests can look successful.

**Publishing concerns**

These are repository observations; I did not build or inspect a publication archive.

- **High:** `moon.mod` declares MIT, but there is no tracked `LICENSE` or upstream attribution notice. Preserve the upstream license/copyright text and audit embedded stylesheet and fixture notices before distributing the port.
- **Medium:** `io`, `cmd/asciidoctor`, and `cmd/golden` explicitly support **native only**. The core is portable; the async integration is not currently the native-plus-wasm integration described in the plan.
- **Medium:** Approximately **11 MiB** of golden fixtures and generated regex tests are tracked. No publication include/exclude policy is declared in [moon.mod](../moon.mod). Inspect the actual archive and deliberately exclude development corpora/tooling where supported.
- **Medium:** `moonbitlang/async@0.22.4` is a module-level dependency even for pure string-conversion consumers. Consider separating native integration and CLI into another module if lightweight library consumption matters.
- **Low:** `repository` is empty; `io/` lacks a checked-in generated interface; compiler installation in CI is unpinned. These weaken release discoverability and reproducibility.
- **Low:** The root facade imports all three converters, while `core` owns HTML stylesheet data and client-highlighter markup. The dependency graph is cycle-free and practical, but the advertised backend-neutral boundary is imperfect.

The immediate release order I recommend is: make validation fail reliably and work from clean CI, correct output-path and fixpoint failures, introduce recoverable conversion errors, then document the precise supported API and intentional exclusions.