# PDF backend: architecture guidance (Codex review, 2026-09-29)

_Read-only review by Codex CLI (reasoning effort high) of .repos/asciidoctor-pdf at 7ea543b and office.mbt at 2bfc336. Paths starting with `office.mbt/` refer to github.com/moonbitlang/office.mbt._

**Recommendation: preserve asciidoctor-pdf’s cursor-based layout semantics in a small compatibility layer that records pagelayout’s page IR.** Reuse and extend pagelayout’s measurement, graphics, and PDF emission; do not initially translate the converter into its existing `paginate.Block` tree.

The main work is reproducing text measurement and layout decisions, not writing PDF objects. A successful small-document spike will demonstrate the rendering path, but will not yet validate pagination compatibility.

This is a read-only source review; I modified no files and ran no builds or tests. References below use the checked-out asciidoctor-pdf commit `7ea543b` and office.mbt commit `2bfc336`. I read [README.mbt.md](../README.mbt.md), [PLAN.md](../PLAN.md), and the [page-layout design record](office.mbt/docs/page-layout-engine.md).

**1. Actual dependency surface and coverage**

“Covered” below means useful implementation exists, not that Ruby parity is established.

| Capability actually used by asciidoctor-pdf | Existing support | Recommended owner and work |
|---|---|---|
| **Formatted text flow and bounded text boxes:** mixed fonts/sizes/colors, justification, indentation, vertical alignment, remaining fragments after overflow | `paragraph.layout_paragraph` handles styled text and alignment, but lays out an entire paragraph. It has no equivalent rich-fragment continuation contract. | Extend pagelayout with bounded rich-text layout returning consumed content, remainder, line metrics, and fragment geometry. Port `typeset_formatted_text`, `fill_formatted_text_box`, and their spacing semantics onto it. |
| **Fragment callbacks:** inline images, destinations, backgrounds/borders, alignment, position capture | Positioned text/rect/image/link IR provides some output primitives; fragment identities, inline objects, baseline shifts, and decoration semantics are missing. | Pagelayout supplies fragment geometry and typed inline objects. Converter maps Ruby callbacks to typed effects. Avoid storing arbitrary converter callbacks in the final IR. |
| **Measurement:** `width_of`, `height_of_formatted`, text-box dry rendering, font-size fitting | Basic advance measurement and full-paragraph height exist. Prawn-compatible measurements do not. | Extend `fonts`, `linebreak`, and rich-text layout. Measurement and drawing must consume the same resolved layout. |
| **`dry_run`, `with_dry_run`, `arrange_block`:** retry at page top, keep together when possible, relax oversized unbreakable blocks, calculate multipage extent | `paginate` has paragraph keeps and widow control, but no nested transactional layout or arbitrary-block extent. | New pagelayout flow session with fork/checkpoint/probe support. Converter owns the precise retry policy and semantic-state rollback. |
| **Bounding boxes, padding, indentation, page-width spans, columns** | Page coordinates and paragraph indents exist. Existing paginator accepts one `SectionProps`; no nested frame/column API. | Add frame stacks and column-aware continuation to pagelayout flow. Preserve indentation across page changes. |
| **Prawn `float`** | Absolute positioning allows overlays, but no scoped cursor/page restoration. | Flow-session operation that restores the current page and cursor while retaining drawing. This is separate from image wrapping. |
| **Image floats with text wrapping** | Not supplied by current paginator. | Bounded text plus continuation and exclusion/frame geometry in pagelayout; converter reproduces `init_float_box` and `ink_paragraph_in_float_box` policy. |
| **Page creation hooks, running headers/footers, stamps** | `PageFurniture` supports default/first/even variants and page-number/count fields. It lacks section-aware running content and arbitrary per-page layout context. | Converter builds page context; pagelayout supports background/body/foreground layers and final furniture placement. Cache repeated decoration layouts. |
| **Multipage block backgrounds and borders** | Rectangles exist, but no block extent or continuation-border semantics. | Pagelayout returns per-page/per-column fragments. Converter selects first/middle/last decoration rules. Add rounded paths, stroke styles, and clipping to IR/emitter. |
| **TOC, index, page-number references** | No equivalent document-layout orchestration. pdflite’s own TOC facilities serve a different input/layout model. | Converter owns reservation, section/index records, and final-page resolution. Engine supplies measurement and stable page handles. |
| **Outlines, named destinations, links, page labels** | pdflite has bookmark/destination/annotation/page-label machinery. Pagelayout’s PDF adapter does not connect these facilities. | Extend document IR and `pagelayout/pdf`; resolve logical destinations to final PDF page objects during emission. Converter owns titles, hierarchy, naming, and numbering. |
| **PNG/JPEG, inline images, image links** | PDF emitter embeds PNG/JPEG. Inline image participation in line metrics is missing. | Reuse embedding; add inline-image layout, intrinsic-size service, link annotations, and compatible error handling. |
| **SVG images** | `pagelayout/svg` emits SVG; it is not an SVG image parser/renderer. PDF image embedding accepts PNG/JPEG. | A substantial separate SVG-input component is required: parse/style/size SVG and lower it to vector display items or PDF forms. |
| **PDF covers, imported pages, PDF backgrounds** | pdflite has document merging and stamping/XObject facilities; no pagelayout integration. | Add imported-page/form resources and page insertion/replacement operations. Converter implements cover/background selection and page-number effects. |
| **Tables:** width calculation, repeated headers, spans, cell styling, vertical alignment, AsciiDoc cells | `table` supplies grids/autofit, spans, borders, shading, and repeated headers. Cells contain paragraphs, not arbitrary nested blocks. | Extend table measurement/content interfaces; add Prawn-compatible sizing policy, row-span behavior, vertical alignment, page-fragment borders, and nested converter content. |
| **Font catalog, fallback chains, icon fonts** | Bundled metrics/outlines and one CJK fallback exist. Arbitrary catalogs and ordered style-aware fallback chains do not. | Inject a font provider into measurement and emission. Converter resolves theme catalog paths and icon-name mappings. |
| **Text transforms and optional hyphenation** | Existing Ruby-compatible string helpers are useful; no full PDF-specific implementation. | Converter owns transformation, whitespace, entity, and hyphenation preprocessing; engine owns the resulting break opportunities and glyph placement. |
| **Graphics and PDF document settings** | pdflite is substantially richer than pagelayout’s RGB rectangular IR. | Extend adapter/IR for CMYK, transparency, paths, dashes, transforms, and clipping. Converter owns metadata, initial zoom, page modes, and print settings. |

The strongest sources for this boundary are [Prawn extensions](../.repos/asciidoctor-pdf/lib/asciidoctor/pdf/ext/prawn/extensions.rb:403), [formatted text extensions](../.repos/asciidoctor-pdf/lib/asciidoctor/pdf/ext/prawn/formatted_text/box.rb), [converter orchestration](../.repos/asciidoctor-pdf/lib/asciidoctor/pdf/converter.rb:164), and pagelayout’s current [IR](office.mbt/pagelayout/pkg.generated.mbti), [paragraph API](office.mbt/pagelayout/paragraph/pkg.generated.mbti), and [pagination API](office.mbt/pagelayout/paginate/pkg.generated.mbti).

Four findings deserve immediate attention:

- **PDF links currently disappear.** `render_pdf` explicitly handles `Link(_) => ()`. This is an adapter gap, despite links existing in IR. [Source](office.mbt/pagelayout/pdf/render.mbt:278)
- **The PDF emitter does not honor arbitrary advances inside a run.** `emit_run` and `emit_run_composite` emit `Tj`; meanwhile paragraph justification modifies individual space advances. Consequently, the measured layout and painted glyph positions can disagree. Implement `TJ` adjustments or equivalent positioning before relying on justified-text comparisons. [Emitter](office.mbt/pagelayout/pdf/render.mbt:18), [justification](office.mbt/pagelayout/paragraph/layout.mbt:148)
- **Table rows are currently atomic.** `place_table` explicitly allows a too-tall row to overflow an empty page. Its comments are more precise than the higher-level API documentation. [Source](office.mbt/pagelayout/paginate/paginate.mbt:294)
- **The design document is partly historical.** Current code includes first/even furniture variants and bundled Latin outlines. Do not plan these as wholly missing features. The font registry still needs replacement for Asciidoctor fonts. [Furniture](office.mbt/pagelayout/paginate/paginate.mbt:377), [outline registry](office.mbt/pagelayout/fontoutlines/data_registry.mbt)

**2. Architecture: imperative compatibility over declarative output**

I recommend a **stateful flow controller with deterministic, reusable layout results**, terminating in declarative page IR.

A direct block-tree translation would force you to invent declarative equivalents for the hardest upstream behaviors simultaneously. The existing `Block` enum has only paragraph, table, image, and page break. Adding an `unbreakable` flag would not reproduce `arrange_block`.

Ruby’s [dry-run implementation](../.repos/asciidoctor-pdf/lib/asciidoctor/pdf/ext/prawn/extensions.rb:970) distinguishes:

- Fitting from the current cursor versus an empty page.
- Moving a block because no meaningful content fit on the first page.
- Keeping captions with actual content.
- Relaxing keep-together when a block exceeds a page.
- Nested measurements under a single-page constraint.
- Trailing empty-page removal.
- Column-aware extents.

Preserve that control flow initially. Do not port Prawn’s PDF object mutation or Ruby `Marshal` cloning; those are implementation mechanisms you can replace.

The ownership boundary should be:

| Layer | Owns |
|---|---|
| PDF converter | AsciiDoc traversal, attribute playback, theme cascade, formatted-markup interpretation, block policies, TOC/index/footnote rules, section metadata |
| Pagelayout | Resolved font measurement, line breaking, bounded text, frames/columns, flow state, geometry, transactional display lists |
| Pagelayout PDF adapter | Page-coordinate conversion, fonts/images/forms, annotations, navigation metadata, content operators |
| Pdflite | PDF objects, resources, embedding/subsetting, serialization |

**Proposed interfaces**

These are interface sketches, not existing APIs or compile-tested declarations:

```text
fonts:
  FontCatalog::register(face_id, bytes, face_index?)
  FontCatalog::resolve(family, style, fallbacks) -> ResolvedFontSet
  FontCatalog::measure(text, font_set, size, policy) -> MeasuredText

richtext:
  Inline = Text | Image | Anchor
  Fragment = { id, inline, style, decoration, link }
  layout_text_box(fragments, frame, policy) -> TextBoxLayout

  TextBoxLayout = {
    lines,
    placed_fragments,
    remainder,
    occupied_height,
    last_baseline,
    nothing_printed,
    everything_printed
  }

flow:
  FlowSession::push_frame(frame)
  FlowSession::pop_frame()
  FlowSession::advance_page(page_spec)
  FlowSession::advance_column()
  FlowSession::fork() -> FlowSession
  FlowSession::probe(layout_operation) -> LayoutProbe
  FlowSession::commit(probe)
  FlowSession::with_saved_position(operation)
  FlowSession::place(layout, layer)

  LayoutProbe = {
    start_position,
    end_position,
    extent_fragments,
    first_content_position,
    overflow,
    display_list
  }

document IR:
  Destination { name, page_id, x, y, fit }
  LinkTarget = Uri | NamedDestination
  OutlineEntry { title, destination, children, open }
  PageContext { physical_number, label, side, section_state, kind }
```

I would add `pagelayout/flow` and a rich-text package rather than exposing the current private `PageCursor` as-is. Existing `paginate()` can remain the convenient DOCX-oriented API and later reuse the same machinery.

Important contracts:

1. **Use stable page IDs.** Array indices are unsuitable identities when covers, reserved TOC pages, and imported pages can change numbering.
2. **Keep engine coordinates y-down.** Translate Ruby cursor conventions in one converter adapter. Keep the PDF coordinate flip solely in emission.
3. **Separate layout from painting.** A probe records layout without registering live destinations, emitting duplicate warnings, or consuming footnote/index state.
4. **Rollback semantic state explicitly.** Ruby’s `push_scratch`/`pop_scratch` saves document attributes and catalogs. Engine checkpoints alone cannot do this. Use converter-owned transaction state and commit-only effects. [Source](../.repos/asciidoctor-pdf/lib/asciidoctor/pdf/converter.rb:5399)
5. **Parameterize compatibility behavior.** Prawn line metrics and breaking rules must not silently replace DOCX defaults.

Three special cases become straightforward under this design:

**Block backgrounds:** lay out content into a temporary display list, collect its page/column extents, and insert backgrounds before content in each affected page layer. Match `theme_fill_and_stroke_block`’s continuation treatment, rather than drawing one enclosing rectangle. [Source](../.repos/asciidoctor-pdf/lib/asciidoctor/pdf/converter.rb:4592)

**TOC:** reproduce Ruby’s reservation strategy. `allocate_toc` measures before body layout; `ink_toc_level` reserves the width of `'0' * toc-max-pagenum-digits`, whose default is three. Final rendering revisits those pages and fills actual numbers and leaders. Thus ordinary parity does **not** require iterative whole-document pagination. Add overflow detection; make any expanded-reservation retry an explicit policy. [Source](../.repos/asciidoctor-pdf/lib/asciidoctor/pdf/converter.rb:3975)

**Running content:** collect section transitions during committed body layout, then render furniture after page count and labels are known. Port the distinctions in `SectionInfoByPage` and `ink_running_content`, including physical versus virtual recto/verso, start offsets, disabled pages, and section/chapter attributes. [Section map](../.repos/asciidoctor-pdf/lib/asciidoctor/pdf/section_info_by_page.rb), [running content](../.repos/asciidoctor-pdf/lib/asciidoctor/pdf/converter.rb:3621)

**3. Theming and YAML**

Implement theme loading in the PDF module, independently testable without laying out a page.

The pipeline should be:

```text
asset resolution → YAML syntax → ordered theme evaluation
                 → normalized theme values → typed layout styles
```

Port [ThemeLoader](../.repos/asciidoctor-pdf/lib/asciidoctor/pdf/theme_loader.rb) behavior rather than implementing a generic recursive configuration merge:

- **Ordered inheritance:** `extends` accepts one or multiple entries; later processing overwrites earlier values.
- **Duplicate-load suppression and `!important`:** the same parent is normally loaded once, but can be forced again.
- **Path distinctions:** bundled names, `./` paths relative to the declaring theme, and paths resolved against the theme directory have different rules.
- **Special base theme:** `base-theme.yml` is loaded as already-normalized flat data. A custom theme does not automatically inherit all base-theme values.
- **Key normalization:** nested keys become flattened underscore keys, with special handling for role names and deprecated keys.
- **Evaluation order:** `$variable` refers to values available at that point. Do not replace this with unordered or forward-reference evaluation.
- **Typed substitutions:** a lone variable can preserve a number, array, or normalized color; interpolation behaves differently.
- **Font catalogs:** replacement is the default; `merge: true` opts into merging. Support scalar family declarations, `*`, and `regular` → `normal`.
- **Content values:** `_content` values expand variables but do not undergo ordinary math evaluation.
- **Colors:** preserve RGB, CMYK, transparent, and null distinctly. Pagelayout’s current RGB-only `Color` is insufficient.
- **External-theme preprocessing:** Ruby protects certain hexadecimal-looking scalars before YAML parsing, including values that YAML might otherwise treat as numbers or comments.

The math evaluator is a compatibility language: measurement conversion, spaced arithmetic operators, `^`, and outer `round`/`floor`/`ceil` processing. Relative units and percentages remain unresolved in some cases until the converter knows the font or available width. A conventional expression evaluator with “better” precedence or extra syntax can produce different results. Port the observed semantics and test them directly.

**A MoonBit YAML parser already exists.** I found no YAML package in the current `moonbitlang/x` repository listing. `moonbit-community/yaml` advertises a JSON-convertible YAML subset, ported from yaml-rust2; the published documentation exposes parsing and event APIs. Use it as the first candidate, with a compatibility qualification step. [moonbitlang/x](https://github.com/moonbitlang/x), [YAML package](https://mooncakes.io/docs/moonbit-community/yaml), [parser repository](https://github.com/moonbit-community/yaml.mbt)

Before adopting it, run all bundled themes and theme fixtures through both loaders. Explicitly test mapping order, aliases, merge keys, block scalars, quoting, duplicate keys, nulls, and Psych’s scalar resolution. An event-level adapter may be preferable if the high-level representation loses required ordering or scalar information.

Precompiled default themes are useful for bootstrapping and small binaries, but full user-theme support needs runtime YAML parsing. Keep the dependency in an optional theme-loading package if useful.

**4. Fonts and line-break compatibility**

**Exact font programs are the first prerequisite.** The default Ruby theme uses Noto Serif and M+ 1mn. Its fallback theme adds M+ 1p Fallback and Noto Emoji. Pagelayout maps unknown families to Carlito and uses Noto Sans SC as its single fallback. That changes glyph widths, line heights, coverage, and page breaks immediately. [Ruby default theme](../.repos/asciidoctor-pdf/data/themes/default-theme.yml), [fallback theme](../.repos/asciidoctor-pdf/data/themes/default-with-font-fallbacks-theme.yml), [current family mapping](office.mbt/pagelayout/fonts/family_map.mbt)

Required changes, in order:

1. **Introduce an injectable font catalog.** Resolve actual bytes and style faces once, and pass the same face identity to layout and PDF embedding. Family-name remapping during emission must not select another font.
2. **Reproduce ordered fallback.** Ruby tests glyph coverage in the effective style, then walks theme fallbacks. The default theme does not enable fallback automatically. Match missing-glyph behavior and warnings; unconditional CJK fallback would violate that behavior. [Fallback implementation](../.repos/asciidoctor-pdf/lib/asciidoctor/pdf/ext/prawn/formatted_text/box.rb:35)
3. **Add kerning to measurement and emission together.** Current `FaceMetrics` has advances and cmap, but no kerning data; `linebreak.measure` sums character advances. Pdflite has AFM kerning support, but that does not supply TrueType pair kerning to pagelayout. [Metrics](office.mbt/pagelayout/fonts/font_metrics.mbt), [measurement](office.mbt/pagelayout/linebreak/measure.mbt)
4. **Match vertical metrics and rounding.** Audit the pinned Prawn/TTFunk choice of metrics, normalization to PDF units, and rounding. Port `calc_line_metrics`, initial/final gaps, mixed-font maxima, baseline shifts, and sub/superscript sizing. Do not substitute `LineSpacing::Multiple` without differential tests.
5. **Match breaking behavior.** Existing greedy breaking is useful, but Prawn’s fragment tokenization, word-join handling, discretionary hyphens, zero-width spaces, preserved code indentation, and oversized-token handling differ. Asciidoctor’s CJK processing is attribute-dependent; current pagelayout applies its own CJK rules generally. [Ruby line wrapping](../.repos/asciidoctor-pdf/lib/asciidoctor/pdf/ext/prawn/formatted_text/line_wrap.rb), [current breaker](office.mbt/pagelayout/linebreak/breaker.mbt)

**Ligatures are not a missing Prawn-parity requirement.** Prawn’s own description of 2.4 states that it renders individual code points and lacks contextual substitution and automatic ligatures. Enabling advanced shaping by default could move you away from the oracle. Keep a future shaping mode separate from compatibility mode. [Prawn’s text-layout limitation](https://github.com/prawnpdf/prawn/issues/1295)

Explicit ligature code points, supplementary-plane emoji, combining characters, and `.notdef` still require tests. Start emoji parity with Ruby’s monochrome Noto Emoji asset; color emoji is a separate feature.

**Subsetting is substantially reusable.** Pdflite already has TrueType subset construction, composite glyph support, and embedding paths. Preserve glyph IDs initially; compact glyph renumbering is a file-size optimization, not a layout prerequisite. Test extraction independently of appearance, especially ToUnicode for supplementary characters. [Subset implementation](office.mbt/pdflite/pdf_truetype_subset_font.mbt), [pagelayout embedding](office.mbt/pagelayout/pdf/emit.mbt)

**OTF/CFF needs a separate compatibility milestone.** Ruby has OTF fixtures. The reviewed subset path is explicitly `glyf`/`loca` TrueType; existing PDF font-reading support does not establish arbitrary CFF embedding/subsetting support. Treat TTF, TrueType-flavored OTF, CFF OTF, and collections as separate capabilities. [Ruby font specs](../.repos/asciidoctor-pdf/spec/font_spec.rb:185)

Finally, port text transforms at the converter layer. Ruby “smallcaps” uses Unicode character substitution and normalization, not an OpenType small-caps feature. [TextTransformer](../.repos/asciidoctor-pdf/lib/asciidoctor/pdf/text_transformer.rb)

**5. Parity and golden harvesting**

Use a **vector of acceptance metrics**, not one aggregate score that lets missing links or shifted pages disappear into a visual average.

| Dimension | Proposed acceptance criterion for a supported fixture |
|---|---|
| Page geometry | Exact page count; page boxes within 0.01 pt |
| Content | Exact per-page normalized text; zero missing or surplus text |
| Line breaking | Same line membership and page assignment |
| Typography | Same selected faces/styles/sizes; baseline/origin and advance errors within a defined tolerance |
| Navigation | Exact target names, outline hierarchy, labels, link destinations; rectangles within tolerance |
| Graphics | Expected images/rules/backgrounds present with matching geometry and colors |
| Appearance | Raster comparison using a pinned renderer, plus reviewable difference images |
| Diagnostics | Expected warnings/errors, severity, and source locations |
| Determinism | Same inputs produce identical output within a fixed MoonBit target/toolchain |

For text geometry, start with **0.25 pt maximum position error** as an investigation threshold, and tighten controlled primitive fixtures toward **0.05 pt**. These are proposed engineering thresholds, not measured achievable results. Require exact line/page decisions even when positions are within tolerance: a tiny width error near a boundary can create an entire extra page.

Use `pdftotext` for content and bbox extraction, but do not rely on its reading order alone for tables and columns. Compare both content multisets and region-aware sequences. Report unmatched text and denominators explicitly.

Office already has an excellent starting harness: [pagelayout_fidelity.py](office.mbt/scripts/pagelayout_fidelity.py). Reuse its page count, recall/precision, alignment coverage, width ratios, same-page fraction, and separate x/y drift. Add maximum and percentile errors; medians can hide one disastrous block.

For raster tests, render both PDFs with the same pinned Poppler version and DPI. Retain strict differences plus a narrowly defined antialiasing-tolerant view. Avoid full-page similarity scores dominated by white space. Calibrate thresholds using repeated oracle renders before establishing gates.

**Harvesting approach**

Extend the pattern in [scripts/harvest/harvest.rb](../scripts/harvest/harvest.rb), but intercept PDF production rather than treating `Document#convert` as a string-output boundary.

1. Add an RSpec wrapper assigning stable `spec file + example + conversion ordinal` IDs.
2. Capture calls through `to_pdf` and `to_pdf_file`, plus direct conversion/render paths used by API specs.
3. Capture both original helper arguments and effective conversion options. Helpers mutate options, construct themes, and disable footers by default. [Helpers](../.repos/asciidoctor-pdf/spec/spec_helper/helpers.rb:228)
4. Capture final bytes from memory streams or render/write boundaries. Do not force an early render for `analyze: :document` cases that mutate the converter afterward.
5. Capture binary assets: source/includes, YAML inheritance files, fonts, SVG dependencies, images, imported PDFs, and requested-but-missing paths.
6. Save normalized semantic observations alongside reference PDFs: pages, text, geometry, links, destinations, outline, labels, and diagnostics.
7. Pin Ruby, Asciidoctor, every rendering gem, fonts, time, locale, and raster tools. Preserve path normalization and per-record isolation.
8. Keep explicit counts for supported, unsupported, API-only, failed, and harvested cases; fail on unexpected upstream failures or disappearing records.

Do **not** compare raw PDF text-operation segmentation. Ruby may emit several `TJ` chunks where MoonBit emits another equivalent sequence.

The upstream `TextInspector` is useful for existing assertions, but unsuitable as the only cross-emitter geometry oracle: its `show_text_with_positioning` discards numeric kerning adjustments when estimating width, and it is tailored to the operator patterns Ruby emits. Extend extraction to interpret text matrices, graphics transforms, spacing, and forms correctly. [Inspector](../.repos/asciidoctor-pdf/spec/spec_helper/inspectors/text.rb)

Harvest three kinds of tests separately:

- **Conversion fixtures:** paragraphs, lists, tables, pages, TOC, images, navigation.
- **Pure compatibility fixtures:** normalized themes, formatted parser trees, transformed fragments, text transforms.
- **Hand-ported behavior tests:** converter subclassing, direct Prawn calls, model mutation, custom callbacks, CLI/network scenarios.

For formatted text, port the small [parser.treetop grammar](../.repos/asciidoctor-pdf/lib/asciidoctor/pdf/formatted_text/parser.treetop) with a scanner/recursive parser. Porting the generated 1,100-line parser or Treetop runtime is unnecessary. Preserve its accepted syntax and formatter fallback/error behavior.

**6. Packaging and binary output**

Use a **separate published PDF module**, for example `bobzhang/asciidoctor-pdf`, with its own CLI. An optional package inside the existing module does not fully meet the requirement to keep PDF dependencies out of that module’s dependency graph.

Suggested shape:

```text
bobzhang/asciidoctor
  core + existing converters + existing facade

bobzhang/asciidoctor-pdf
  converter
  theme
  theme/yaml
  fonts/default
  fonts/fallbacks
  io
  cmd/asciidoctor-pdf
```

The PDF module depends on `asciidoctor/core` and selected pagelayout packages. Core never imports PDF.

There is an immediate interface issue: [Converter.convert](../core/converter.mbt) returns `String`, [ConvertResult.output](../io/convert.mbt:40) is `String`, and stdout writing applies text newline handling.

For the initial PDF module, expose a dedicated bytes API:

```text
render_pdf(document, theme, assets) -> PdfResult
PdfResult = { bytes, page_model, diagnostics }
```

Keep PDF inline conversion compatible with the core substitution machinery, but return final PDF bytes through this dedicated result. Ensure `backend=pdf` traits are active during parsing/substitution.

Later, introduce a dependency-free core output abstraction such as `Text(String) | Binary(Bytes)` or a separate binary writer interface. Preserve the current public string APIs for existing backends. Never transport PDF through UTF-8 strings or the current text stdout path.

Pagelayout’s [module manifest](office.mbt/pagelayout/moon.mod) currently includes pdflite, docx2html, async, and other dependencies. Separate three costs:

- Module resolution/download.
- Packages actually compiled and linked.
- Data initialized at runtime.

Package isolation helps linking, but strict dependency isolation requires splitting the DOCX frontend/CLI into another module. This is worthwhile for a reusable layout engine, though it need not block the PDF prototype.

**Font bundles are the main immediate size risk.** Current `load_faces()` and `load_outlines()` walk complete registries; calling one lookup can initialize all bundled faces. Merely making decompression lazy does not remove linked font blobs.

Make the generic font provider independent of bundles. Supply exact Asciidoctor default fonts separately; make CJK/emoji packs opt-in or externally supplied. Verify how assets are delivered by `moonx` before assuming adjacent font files will be available.

The project already records Pygments growing the wasm CLI from roughly **1.3 MB to 11.2 MB**, with increased startup time. Treat that as a documented baseline, not a new measurement. [PLAN.md](../PLAN.md)

Measure release wasm size, compressed distribution size, cold startup, peak memory, and representative render time for:

- Existing CLI.
- PDF CLI with default Latin fonts.
- PDF CLI with CJK/emoji.
- PDF CLI with optional highlighting.

The existing CLI should acquire no PDF/font code.

**7. Ordered milestones and top risks**

| Milestone | Deliverable | Exit criteria |
|---|---|---|
| **0. Oracle and scope** | Pinned Ruby stack; PDF/semantic harvesting; capability ledger | Repeated oracle runs are stable; fixture counts are guarded; every excluded scenario has a reason |
| **1. Rendering contract** | Bytes API, injectable fonts, advance-correct PDF text, links, primitive geometry | Controlled runs render and extract correctly; requested advances match PDF positions; native/wasm observations agree |
| **2. Theme and inline semantics** | Theme loader, formatted parser/transform, default font catalog | Bundled themes and selected theme/fragment goldens match Ruby before pagination is involved |
| **3. Text layout** | Prawn-compatible metrics, kerning, breaking, bounded text/remainder, inline objects | Primitive text fixtures match line boundaries, metrics, overflow, and warnings |
| **4. Flow compatibility** | Frames, cursor state, nested probes, keeps, extents, page transitions | `arrange_block_spec` scenarios pass, including oversized unbreakable blocks, caption pinning, and multipage decoration |
| **5. Basic document parity** | Headings, paragraphs, lists, code, quotes, examples, sidebars, admonitions | Spike fixtures and corresponding supported spec subsets pass page/text/geometry gates |
| **6. Tables** | Compatible widths, spans, repeated headers, vertical alignment, nested AsciiDoc cells | Supported `table_spec` subset passes; oversized cells follow declared Ruby-compatible truncation/diagnostics |
| **7. Document navigation** | TOC, outlines, destinations, labels, xrefs, footnotes, running content, columns/index | Long articles/books match page count, page assignment, navigation, and recto/verso behavior |
| **8. Media and advanced fonts** | SVG input, PDF imports, image floats, icons, fallback packs, OTF coverage | Each format has explicit supported/unsupported status and semantic/raster goldens |
| **9. Release** | Separate package/CLI, reproducible assets, budgets and corpus gates | No new PDF dependencies in core; native/wasm checks pass; published package works through `moonx` |

Two scope controls will save substantial work:

- Ruby’s table cells do **not** support content taller than a page; its custom cell implementations truncate and diagnose. General cell splitting is an enhancement, not a prerequisite for parity. [AsciiDoc cell](../.repos/asciidoctor-pdf/lib/asciidoctor/pdf/ext/prawn-table/cell/asciidoc.rb), [text cell](../.repos/asciidoctor-pdf/lib/asciidoctor/pdf/ext/prawn-table/cell/text.rb)
- Ruby footnotes are emitted as chapter/document note groups, with optional bottom alignment, rather than requiring a general per-page footnote solver. [ink_footnotes](../.repos/asciidoctor-pdf/lib/asciidoctor/pdf/converter.rb:3329)

The highest risks, in priority order, are:

1. **Text metrics and rounding:** small errors compound into different line and page breaks.
2. **Repeated-layout side effects:** scratch runs and VFS reruns can duplicate warnings, destinations, counters, or footnotes.
3. **Measurement/emission disagreement:** the current advance-handling gap is a concrete example.
4. **Table sizing and nested content:** paragraph-only cells do not cover the upstream model.
5. **SVG scope:** SVG output support provides little of the SVG-input implementation required.
6. **Theme/YAML edge semantics:** ordering, inheritance, color coercion, and relative units affect the whole document.
7. **Binary size and eager resources:** broad font registries and optional highlighters can dominate wasm startup and memory.

For the current spike, the most valuable next evidence is an exact-font, justified multipage fixture with a near-boundary heading, a split decorated block, and a link. That will test the architecture’s critical contracts before broader feature work builds on them.