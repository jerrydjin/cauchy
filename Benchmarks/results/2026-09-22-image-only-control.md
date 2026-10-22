# Image-only PDF control: unsupported without OCR

Date: 2026-09-22  
Source: one visually labelled complex-analysis page rendered as a raster image
and wrapped in a one-page PDF with no extractable text layer. The fixture stays
local; neither the source page nor the raster PDF is redistributed.

The page visibly introduces Example 1.2.1, Theorem 1.2.2, displayed equation
1.2.1, and Remark 1.2.3. The same page in its original born-digital PDF was
recovered 4/4. In the image-only control, Cauchy skipped the page as empty text:
0 true positives, 0 false positives, 4 false negatives, and 0% recall. This
is a known unsupported input, not an abstention success. The four-document
development score does not include this control.

The existing macOS Vision accurate-text-recognition path was probed from the
built Cauchy app, but this macOS beta returned a compute-operation error before
producing text. Forcing CPU execution did not resolve it. Vision's fast mode
did run on both a 1400-pixel and a higher-resolution raster control. It found
several printed labels but severely corrupted ordinary words and mathematical
notation, so its output cannot serve as exact source evidence. A direct
on-device image-model probe of the higher-resolution page returned three
incorrect labels and missed the displayed equation. These are diagnostic
single-page observations, not OCR or vision benchmarks across a corpus.

The app reports an explicit no-searchable-text limitation for a wholly
image-only PDF instead of caching a successful empty reference index. Neither
fast OCR nor image-model guesses enter the trusted production index. Mixed
text/image documents still need a page-level, region-anchored fallback and a
human-labelled accuracy benchmark before that policy changes.

Follow-up (2026-09-23): that prerequisite is now implemented as a deliberately
limited navigation fallback. The preserved post-change measurements and trust
boundary are in `2026-09-23-ocr-candidate-holdout.md`; the numbers above remain
the pre-change baseline.
