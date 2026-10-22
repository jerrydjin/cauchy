# Cauchy labelled reference-index corpus

2 documents; 23 labelled pages; 24 introduced references; 0 extraction failures.

| Document | Pages | Labels | Production P / R / F1 | Abstentions | Source fallbacks | Context overflows |
|----------|------:|-------:|------------------------|------------:|-----------------:|------------------:|
| Metric-spaces notes | 12 | 23 | 100.0% / 100.0% / 100.0% | 4/4 | 6 | 0 |
| Materials-discovery paper | 11 | 1 | 100.0% / 100.0% / 100.0% | 10/10 | 1 | 1 |

Micro-averaged over reference instances (not an average of per-document percentages):

| System | Precision | Recall | F1 | TP | FP | FN | Correct abstentions |
|--------|----------:|-------:|---:|---:|---:|---:|--------------------:|
| Cauchy production extractor | 100.0% | 100.0% | 100.0% | 24 | 0 | 0 | 14/14 |
| All syntactic mentions | 31.6% | 100.0% | 48.0% | 24 | 52 | 0 | 10/14 |
| Declaration heuristic | 100.0% | 100.0% | 100.0% | 24 | 0 | 0 | 14/14 |

Accepted model transcriptions: 17; source fallbacks: 7; context-overflow
degradations: 1. End-to-end per-page latency including skipped pages: median
0.4 seconds; interpolated p95 82.4 seconds; maximum 159.5 seconds.

These are development slices inspected and tuned during implementation, not a
held-out estimate of generalization. The long-tail model latency and imperfect
readability of PDF-text equation fallbacks remain product limitations. The local
source PDFs are not redistributed with the labels.
