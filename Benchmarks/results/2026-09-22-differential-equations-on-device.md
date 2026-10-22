# Differential-equations notes: first-pass failure and development fix

Date: 2026-09-22  
Document: 81-page differential-equations lecture notes, identified by SHA-256 in the corpus  
Labelled slice: 10 visually reviewed pages, 6 introduced references, 6 hard-negative pages

The frozen labels span bibliography years, an example, a lemma with a numbered
integral, a theorem, phase-portrait figures, two numbered PDE equations, and
unnumbered mathematics. The local PDF is not redistributed.

## Untuned first pass

| System | Precision | Recall | F1 | TP | FP | FN | Abstentions |
|--------|----------:|-------:|---:|---:|---:|---:|------------:|
| Cauchy production extractor | 85.7% | 100.0% | 92.3% | 6 | 1 | 0 | 6/6 |
| All syntactic mentions | 33.3% | 100.0% | 50.0% | 6 | 12 | 0 | 4/6 |

The false positive was equation 1.1 on page 15. It was merely an IVP citation
at the end of a lemma sentence; mathematical notation elsewhere in that line
made a permissive trailing-label heuristic mistake it for a display equation.

## After diagnosis

The general trailing-label rule now requires compact mathematical content
immediately before the label, while still supporting equations whose number
starts a line or occupies a line by itself. A regression test pins the
end-of-lemma citation case.

| System | Precision | Recall | F1 | TP | FP | FN | Abstentions |
|--------|----------:|-------:|---:|---:|---:|---:|------------:|
| Cauchy production extractor | 100.0% | 100.0% | 100.0% | 6 | 0 | 0 | 6/6 |
| All syntactic mentions | 33.3% | 100.0% | 50.0% | 6 | 12 | 0 | 4/6 |

Four entries used accepted model transcriptions and two used explicit source
fallbacks. All 10 pages completed without extraction errors; six pages avoided
model inference. End-to-end median latency was 0.1 seconds, interpolated p95
7.9 seconds, and maximum 8.7 seconds on this slice.

Because this document informed a code change, its improved score is a development
result, not a held-out estimate. The untuned first-pass failure remains above so
the iteration is auditable.
