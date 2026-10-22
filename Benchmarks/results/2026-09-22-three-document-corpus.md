# Cauchy labelled reference-index corpus

3 documents; 33 labelled pages; 30 introduced references; 0 extraction failures.

| Document | Pages | Labels | Production P / R / F1 | Abstentions | Source fallbacks | Context overflows |
|----------|------:|-------:|------------------------|------------:|-----------------:|------------------:|
| Metric-spaces notes | 12 | 23 | 100.0% / 100.0% / 100.0% | 4/4 | 6 | 0 |
| Materials-discovery paper | 11 | 1 | 100.0% / 100.0% / 100.0% | 10/10 | 1 | 1 |
| Differential-equations notes | 10 | 6 | 100.0% / 100.0% / 100.0% | 6/6 | 2 | 0 |

Micro-averaged over reference instances (not an average of per-document percentages):

| System | Precision | Recall | F1 | TP | FP | FN | Correct abstentions |
|--------|----------:|-------:|---:|---:|---:|---:|--------------------:|
| Cauchy production extractor | 100.0% | 100.0% | 100.0% | 30 | 0 | 0 | 20/20 |
| All syntactic mentions | 31.9% | 100.0% | 48.4% | 30 | 64 | 0 | 13/20 |
| Declaration heuristic | 100.0% | 100.0% | 100.0% | 30 | 0 | 0 | 20/20 |

Accepted model transcriptions: 21; source fallbacks: 9; context-overflow
degradations: 1. End-to-end per-page latency including skipped pages: median
0.4 seconds; interpolated p95 45.2 seconds; maximum 159.5 seconds.

These are development slices inspected and tuned during implementation, not a
held-out estimate of generalization. The differential-equations first pass had
one false positive before its diagnosis and fix; see the per-document report.
The long-tail model latency and imperfect readability of PDF-text equation
fallbacks remain product limitations. Source PDFs are not redistributed.
