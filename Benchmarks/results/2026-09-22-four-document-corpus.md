# Four-document development corpus

The updated corpus combines the final runs of four local PDFs: mathematics
lecture notes in metric spaces, differential equations, and complex analysis,
plus a materials-discovery research paper. It has 45 visually labelled pages,
53 introduced references, and 23 pages with no introduced reference.

| Document | Pages | Labels | Production P / R / F1 | Abstentions | Source fallbacks | Context overflows |
|----------|------:|-------:|------------------------|------------:|-----------------:|------------------:|
| Metric-spaces notes | 12 | 23 | 100.0% / 100.0% / 100.0% | 4/4 | 6 | 0 |
| Materials-discovery paper | 11 | 1 | 100.0% / 100.0% / 100.0% | 10/10 | 1 | 1 |
| Differential-equations notes | 10 | 6 | 100.0% / 100.0% / 100.0% | 6/6 | 2 | 0 |
| Complex-analysis notes | 12 | 23 | 100.0% / 100.0% / 100.0% | 3/3 | 8 | 1 |

Micro-averaged production precision, recall, and F1 are each 100.0%: 53 true
positives, no false positives or false negatives, and 23/23 correct negative
pages. The all-syntactic-mentions baseline has 53 true positives and 71 false
positives (42.7% precision); the declaration heuristic alone also gets 53/53
with no false positives on this slice. The production index contains 36 accepted
model transcriptions and 17 explicit source fallbacks. Two pages exceeded the
model context. Across the four runs, median page latency including skips was
1.3 seconds, interpolated p95 89.9 seconds, and maximum 159.5 seconds.

This is an iteratively inspected and tuned development corpus, not a held-out
estimate or a claim about arbitrary technical PDFs. The first-pass failures
and subsequent fixes are reported in the per-document reports. In particular,
perfect reference-number detection here does not establish that every model
transcription is semantically faithful to its source. A subsequent body audit
found an accepted equation truncated mid-inequality and a definition with
changed notation. Cauchy now uses the retained PDF excerpt, not the model
transcription, as answer context; the model version remains an optional reading
aid. The corpus also does not settle OCR and scanned-document performance.
