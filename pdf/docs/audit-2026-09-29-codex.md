# PDF spike: independent audit (Codex CLI, reasoning effort xhigh, 2026-09-29)

The saved PDFs show excellent text and pagination agreement, but the reported numbers overstate what was verified. I also found a PDF structure defect that the metrics miss. **No files were modified.**

**Metric audit**

Line references below refer to [pdf_compare.mbtx](../../scripts/pdf_compare.mbtx).

| Metric | Assessment |
|---|---|
| Recall / precision | Correct multiset intersection, including duplicate counts ([202–221](../../scripts/pdf_compare.mbtx:202)). Ignores order, page, styling and visibility. Correctly catches extra text through precision, but empty inputs return `1`. |
| Reading-order alignment | Myers LCS appears correct; a faithful translation passed 3,969 small sequence comparisons against independent dynamic programming. It measures Poppler’s extracted order, with ambiguous matching of repeated words. `aligned` divides by Ruby’s word count, so inserted words do not reduce it ([225–295](../../scripts/pdf_compare.mbtx:225), [365–368](../../scripts/pdf_compare.mbtx:365)). |
| “Lines” | **Does preserve nonempty line boundaries**: it does not flatten the entire page. However, it removes indentation, repeated ASCII spaces and blank lines, then compares an **unordered per-page multiset**. Reordered lines and changed blank-line spacing can score perfectly; extra lines have no direct penalty. Ordinary word rewrapping is detected ([138–165](../../scripts/pdf_compare.mbtx:138), [335–369](../../scripts/pdf_compare.mbtx:335)). |
| Same-page | Numerator is same-page LCS matches; denominator is **all Ruby words**, not just aligned words. That conservatively penalizes missing/unmatched text, although repeated-word alignment remains ambiguous ([310–320](../../scripts/pdf_compare.mbtx:310), [368](../../scripts/pdf_compare.mbtx:368)). |
| “±1pt” | Only same-page aligned words enter its denominator. Missing, unmatched and wrong-page words disappear. It checks `xMin` and `yMax`, not the whole box; **height differences ≥0.1pt force `dy=0`**. Thus an arbitrarily displaced word can pass vertically if its box height differs. Those artificial zeros also bias median `dy` ([130–131](../../scripts/pdf_compare.mbtx:130), [316–376](../../scripts/pdf_compare.mbtx:316)). |
| Pixel difference | Correctly counts grayscale differences **strictly greater than 64**, divided by every page pixel. At 60 dpi, one pixel spans 1.2pt. Color differences, faint borders, subpixel shifts and differences ≤64 vanish; white margins dilute the result ([406–422](../../scripts/pdf_compare.mbtx:406), [535–539](../../scripts/pdf_compare.mbtx:535)). |
| Pages / failures | Page counts are displayed, **never enforced**. Pixel comparison iterates only Ruby pages, ignoring extra spike pages; no Ruby rasters produces a perfect-looking `0%`. Filename matching also mishandles differing zero-padding, e.g. 9 versus 10 pages. Conversion failures print to the console but **vanish from the HTML summary**. Poppler exit codes are ignored; failed extraction can yield empty data/NaNs ([434–443](../../scripts/pdf_compare.mbtx:434), [529–570](../../scripts/pdf_compare.mbtx:529)). |

Successful-run diagnostics are also lost: converter stdout is discarded ([522–525](../../scripts/pdf_compare.mbtx:522)), including unsupported blocks reported as `DROPPED` by [convert.mbt:118](../../pdf/convert.mbt:118).

**Independent measurements**

I reran `pdftotext -layout`, `-bbox` and `-bbox-layout`; inspected `pdfinfo -box`, `pdffonts`, destinations and PDF objects with strict-mode `pypdf`; and rendered every sampler/features page through `pdftoppm` into memory. Qpdf was unavailable.

| Measurement | Sampler | Features |
|---|---:|---:|
| Pages, Ruby / spike | 4 / 4 | 3 / 3 |
| Words, each engine | 755 | 845 |
| Fresh `-layout` text | Byte-identical | Byte-identical |
| Ordered bbox line text | Identical | Identical |
| Words exempted from vertical checking | 71/755, **9.40%** | 12/845, **1.42%** |
| 60-dpi gray, >64: mean / worst page | 0.0104% / 0.0238% | 0.0182% / 0.0450% |
| **300-dpi gray, same >64 threshold** | **0.3887% / 0.6212%** | **0.6295% / 1.2477%** |

The published 60-dpi numbers reproduce. Their apparent near-zero difference is strongly resolution/threshold dependent. At 300 dpi with threshold 16, mean full-page differences are 1.004% and 1.595%. These include antialiasing and small spacing differences, so they are not equivalent to percentages of incorrect content.

The exempted boxes differ vertically by up to 2.34pt/1.89pt. **This is not evidence of displaced baselines:** inspecting all 28/12 matching monospace text runs found baseline differences below 0.000005pt. The script needs a real baseline comparison instead of silently assigning zero error.

Checking both Pro Git cases also exposed rounding: three-decimal formatting ([180–183](../../scripts/pdf_compare.mbtx:180)) turns imperfect results into `1`.

- **ch02:** aligned/same-page is 11,626/11,627 = **99.9914%**.
- **ch03:** recall **99.9795%**, precision **99.9897%**. On page 22, `(` moves to the next line and joins `iss91v2),`; 898/900 normalized lines match. This is a real line-break difference, not missing prose.

The additional PDF checks found:

- **Fonts:** all embedded. Sampler has 6 Ruby versus 5 spike font resources; features 4 versus 3. Both use Noto Serif and M+; names differ, e.g. `7c98a2+mplus1mn-regular` versus `DAAAAA+M+1mn`. Both actually subset glyph programs, although `pdffonts` reports Ruby `sub=no`. Spike’s simple WinAnsi fonts lack `/ToUnicode`; its composite Noto Serif has it. Extraction succeeds here, but Unicode coverage remains unproven.
- **Page geometry:** all seven checked pages have identical effective A4 boxes, 595.28 × 841.89pt, rotation zero. Ruby explicitly writes all five boxes; spike writes MediaBox and relies on defaults.
- **Links:** sampler has 6 annotations in each PDF, features 16. Page, subtype and targets match, including footnote round trips. Maximum rectangle-coordinate differences are **0.3675pt / 0.3780pt**.
- **Outlines:** titles, hierarchy and resolved destinations match: 10 entries / 3 entries. Sampler’s two parent branches are expanded in Ruby and collapsed in spike (`/Count +1` versus `-1`).
- **Named destinations:** counts match, 13 / 3, but Ruby’s `__anchor-top` becomes `__top`. More seriously, **sampler’s destination keys are sorted by length before bytes**, violating lexical ordering required by the [PDF reference, §3.8.5](https://opensource.adobe.com/dc-acrobat-sdk-docs/pdfstandards/pdfreference1.6.pdf#page=156). The cause is [render.mbt:468–469](office.mbt/pagelayout/pdf/render.mbt:468) using [Bytes.compare](moonbitlang/core/builtin/bytes.mbt:392), which compares lengths first. Poppler successfully resolves these destinations; failure in another viewer is a risk, not something demonstrated here.
- **Document information:** titles and sampler author match. Spike omits Creator, CreationDate, ModDate and Ruby’s initial `/OpenAction`; Producer differs appropriately. PDF versions are 1.4 versus 1.7. Effective page labels match.

**For the 49-document baseline**

1. Emit exactly **49 result records**, including `oracle_failed`, `spike_failed`, `both_failed`, timeout, invalid PDF and measurement failure. Preserve commands, versions, input/output hashes and both output streams.
2. Separate outcomes into unsupported block/inline feature, missing/extra text, extraction/tokenization difference, reading-order change, line-wrap change, missing/extra/blank pages, geometry, visual styling/assets, and navigation/metadata defects. Capture `DROPPED` with source location.
3. Publish exact counts and denominators alongside percentages. Add symmetric ordered text/line comparison, code indentation checks, page-boundary tokens, and explicit empty-document handling.
4. Measure actual baselines and box extents; report unavailable measurements separately. Include overall placement coverage, conditional accuracy, p95/max errors and worst pages.
5. Use 150/300-dpi RGB comparisons, several thresholds, full-page **and content-region** denominators, and diff images. Compare the union of page numbers; fail explicitly on missing pages.
6. Validate fonts/Unicode, annotations, destination resolution **and name-tree ordering**, outline state, page boxes and metadata separately. Add deliberate mutations—deleted text, reordered lines, shifted code, extra blank page, removed link—to verify that each metric detects its intended failure.

**Verdict:** the numbers credibly demonstrate very strong text/layout agreement on these saved examples. They do **not** establish near-perfect PDF parity, and the current summary is unsuitable as a 49-document acceptance gate until failure accounting, vertical coverage and structural validation are fixed.

---

## Follow-up (2026-09-29)

What was done about each finding. The comparison script's header is the authoritative definition of the metrics and gate.

| Audit item | Status |
|---|---|
| Failures vanish; one record per input | **Fixed.** Every input yields one record with status `ok`, `oracle_failed`, `spike_failed`, `both_failed`, `timeout`, `invalid_pdf` or `measurement_failed`, the commands, tool versions, input and output SHA-256, and both engines' stdout/stderr, in the HTML and in `summary.json`. Poppler and pdf-inspect exit codes are checked. |
| `DROPPED` lost; unsupported content silent | **Fixed.** The converter reports `UNSUPPORTED <kind> <what> at <file>:<line>` on stderr (blocks, inline images, index terms, AsciiDoc table cells, unembeddable images, toc/book/icons/highlighter); the script captures and counts them. |
| Rounding to `1`; missing denominators | **Fixed.** Exact `n/m` everywhere; percentages are truncated, so only n = m shows 100%. |
| Unordered line multiset; indentation, blank-line and extra-line blind spots | **Fixed** (except blank lines). Per-page ordered LCS over the union of pages; missing, extra and reordered lines all count; leading indentation of matched lines must agree within one column. Blank lines are still ignored. |
| Page counts not enforced; Ruby-only raster pages; zero padding | **Fixed.** Page counts gate; raster compares the union of pages (a missing page counts as fully different); page files are matched by number. |
| Empty inputs return 1 | **Fixed.** Empty documents are reported as such and compare as equal only when both are empty. |
| `dy = 0` when box heights differ | **Fixed.** Baselines come from the text operators themselves (pdf-inspect), matched to each word; unmeasured words lower coverage, reported with p50/p95/max and worst pages. |
| 60 dpi grey, one threshold, full-page denominator | **Fixed.** 150 dpi RGB, thresholds 16/64/128, full-page and content-region denominators, flat (fill) differences for faint colours, per-page difference images. |
| Structure: fonts, boxes, links, outline, destinations, name-tree order, labels, info | **Checked** per document by pdf-inspect (pdflite). |
| Name tree sorted by length first | **Fixed** in pagelayout (lexical byte order). |
| Simple fonts lack `/ToUnicode` | **Fixed** in pagelayout. |
| Outline collapsed (`/Count -1`) | **Fixed**: open state follows `outlinelevels`; the outline root always has `/Count`. |
| `__anchor-top` vs `__top`; Creator, dates, `/OpenAction`, page boxes | **Fixed** (also page labels, PageMode, DisplayDocTitle, PostScript font names, non-ASCII destination names). PDF version (1.7 vs 1.4) and Producer still differ, by design. |
| Mutation self-test | **Done**: `--self-test` corrupts a good spike PDF seven ways (deleted text, reordered lines, shifted block, dropped graphics, extra page, removed link, name-tree order) and checks each is flagged, that the identity comparison passes, and that two oracle renders are pixel-identical. |
| Ambiguous repeated-word alignment | **Remains.** Word alignment is still an LCS of word texts. |

With the stricter gate, the built-in cases give: sampler and features **pass**; Pro Git ch02 fails on unsupported index terms (missing `__indexterm-N` destinations), one word out of reading order, and `mplus1mn-italic` used only by the spike (italic monospace in table captions); ch03 additionally has the known line-break difference (898/900 lines). The 49-document baseline: 25 pass, 24 fail, all 49 with status `ok` (see the gallery for categories).