# Untuned two-document holdout: first pass

Before running either extractor, eight fixed PDF pages were visually labelled in
each of two previously unused Oxford lecture-note PDFs. The label files are
`probability-notes.holdout.ground-truth.json` and
`linear-algebra-notes.holdout.ground-truth.json`. They were not part of the
four-document development corpus. The first-pass numbers below are preserved
as a baseline and must not be replaced by post-fix results.

| Document | Labelled pages | References | Source-only TP / FP / FN | Model-backed TP / FP / FN | Source-only page-region coverage |
|----------|---------------:|-----------:|-------------------------:|------------------------------:|---------------------------------:|
| Probability | 8 | 12 | 10 / 0 / 2 | 10 / 0 / 2 | 10/10 accepted |
| Linear Algebra | 8 | 8 | 8 / 3 / 0 | 8 / 3 / 0 | 11/11 accepted |
| **Combined** | **16** | **20** | **18 / 3 / 2** | **18 / 3 / 2** | **21/21 accepted** |

All three negative pages in Probability were correctly empty; Linear Algebra's
contents and proof-only pages were also empty. Exact reference-number accuracy
nonetheless fell from the tuned development result: source-only and model-backed
had the same errors because both use the same deterministic declaration gate.

- Probability page 40: displayed equation (5.1) is right-aligned at the end of a
  long extracted text line and was rejected.
- Probability page 64: displayed equation (6.8) appears before its formula in
  PDFKit's text order and was rejected.
- Linear Algebra page 32: proof substeps (1), (2), and (3) were promoted to
  standalone equation references. These are not numbered displayed equations.

The on-device model did not fix any of these errors. It spent up to 169.2 seconds
on one Probability page and up to 89.3 seconds on one Linear Algebra page;
source-only p95 page time was about 0.1 seconds in both runs. Those timing
figures are single-run observations, not controlled latency estimates.

The page geometry suggests a testable distinction: the two missed printed
equation labels begin at about 78.8% of page width, while the three proof-step
numbers begin between 26.9% and 31.5%. That observation motivates a
geometry-aware declaration gate, but it is not itself proof of a universal
threshold. Keep these pages in the regression set and evaluate further PDFs
after any fix.
