# Complex-analysis notes: appendix-number holdout failure and development fix

Date: 2026-09-22  
Document: 114-page complex-analysis lecture notes, identified by SHA-256 in the corpus  
Labelled slice: 12 visually reviewed pages, 23 introduced references, 3 negative pages

The labels were frozen before the first run. They include numbered definitions,
theorems, lemmas, examples, remarks, a corollary, a displayed equation, and a
letter-prefixed appendix remark. Citations, figure numbers, unnumbered displays,
and the appendices divider were excluded. The local PDF is not redistributed.

## Untuned first pass

| System | Precision | Recall | F1 | TP | FP | FN | Abstentions |
|--------|----------:|-------:|---:|---:|---:|---:|------------:|
| Cauchy production extractor | 100.0% | 95.7% | 97.8% | 22 | 0 | 1 | 3/3 |
| All syntactic mentions | 78.6% | 95.7% | 86.3% | 22 | 6 | 1 | 2/3 |

Page 112 was a false negative: `Remark A.0.5` was visible in the source PDF
and extractable text, but the reference detector accepted only digit-prefixed
numbers, so the page was skipped before model inference. The eight processed
pages took a mean of 12.9 seconds; end-to-end p95 was 23.7 seconds, maximum
33.6 seconds. One accepted reference on each of pages 26 and 67 had multiple
matching source occurrences and was marked uncertain for review.

## After diagnosis

The detector now recognizes dotted appendix labels such as `A.0.5`, while the
declaration guard still excludes prose citations such as `Theorem A.0.1`.
Regression tests cover detection and the citation/declaration distinction.

| System | Precision | Recall | F1 | TP | FP | FN | Abstentions |
|--------|----------:|-------:|---:|---:|---:|---:|------------:|
| Cauchy production extractor | 100.0% | 100.0% | 100.0% | 23 | 0 | 0 | 3/3 |
| All syntactic mentions | 76.7% | 100.0% | 86.8% | 23 | 7 | 0 | 2/3 |

Fifteen entries used accepted model transcriptions and eight retained source
fallbacks. All 12 pages completed; one page exceeded the model context and
degraded to a source-backed definition. The appendix remark was recovered by
the source fallback after four model results failed validation. The repeated
source occurrences on pages 26 and 67 remain marked uncertain. The rerun's
mean was 29.0 seconds/page including skipped pages, interpolated p95 101.2
seconds, and maximum 115.0 seconds. The on-device model's latency is variable;
the projected 55-minute full-book time is an extrapolation from this small
sample, not a measured whole-book run.

Because the first-pass failure informed a code change, the perfect rerun is a
development result, not a held-out generalization estimate. The untuned score
is preserved above.
