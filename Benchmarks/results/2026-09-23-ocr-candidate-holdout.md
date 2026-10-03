# Region-anchored OCR candidates: first holdout and production acceptance

Date: 2026-09-23  
Scope: local Vision fast OCR on Complex Analysis notes, evaluated only as a
numbered-reference navigation fallback. This is not a transcription-quality
claim and is not included in the born-digital corpus aggregate.

## Fixed policy

Cauchy accepts only a named numbered declaration heading or a standalone
parenthesized equation label observed in the right margin. It makes two narrow
punctuation repairs inside a dotted heading number: a comma between digits and
whitespace after a dot. It does not guess letters or digits, reconstruct prose,
or use an image-language model.

The fallback also covers scans whose nominal text layer is only a page number
or short watermark. It does not replace short but exactly grounded declaration
text, and it stays off for substantive searchable pages.

Every accepted candidate retains the raw OCR line, confidence, and normalized
page region. The Reference panel marks it **OCR candidate · verify on page** and
shows the page crop. OCR entries have no answer-grounding body, are never sent
to Ask, and make the optional portable evidence bundle ineligible for export.
The ordinary reading session still exports.

## Development slice

The detector was developed against six local image-only controls: foreword
page 5, page 12 at two raster resolutions, pages 18 and 26, and a worked-residue
negative on page 91. Human labels contained 15 positive references. Result:

| TP | FP | FN | Precision | Recall |
|---:|---:|---:|----------:|-------:|
| 11 | 0 | 4 | 100.0% | 73.3% |

Both negative controls stayed empty. Page-region overlay review on page 12 put
the three accepted boxes on the printed Example 1.2.1, Theorem 1.2.2, and
equation (1.2.1).

## Predeclared holdout

Before running OCR, pages 35, 44, 55, 67, 79, 103, and 112 were labelled from
the original 114-page notes. The set contained 12 positive references and one
negative page. No detector rule was changed after seeing these results.

| TP | FP | FN | Precision | Recall | Negative pages clean |
|---:|---:|---:|----------:|-------:|---------------------:|
| 11 | 0 | 1 | 100.0% | 91.7% | 1 / 1 |

The sole miss was Definition 2.1.1 on page 35. The result is one document
family, so it establishes a useful first holdout rather than general OCR
quality.

## Production-path acceptance

The built app was run through `--benchmark-indexing` on the SHA-256-bound
one-page image-only page-12 fixture using
`corpus/complex-analysis-image-only-dev.ground-truth.json`. This exercises the
same single-page path as the reader and invoked no language model.

| TP | FP | FN | Precision | Recall | F1 | Anchored regions | Time |
|---:|---:|---:|----------:|-------:|---:|-----------------:|-----:|
| 3 | 0 | 1 | 100.0% | 75.0% | 85.7% | 3 / 3 | 0.6 s |

The miss was Remark 1.2.3. This acceptance result proves that an image-only
page can now yield inspectable navigation candidates without model inference;
it does not justify treating the OCR transcript as source evidence.

## Remaining boundary

- Test scans, photographs, rotations, multiple columns, lower DPI, and
  non-English documents before broadening the detector.
- Keep accurate-mode Vision disabled on this macOS beta: it returned a compute
  operation error in the control probe, while fast mode completed.
- Measure word/symbol transcription separately if Cauchy ever proposes using
  OCR beyond labels. Current policy intentionally forbids that use.
