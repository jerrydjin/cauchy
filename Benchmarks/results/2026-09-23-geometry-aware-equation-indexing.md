# Geometry-aware equation indexing: post-fix result

This is a follow-up to the [untuned two-document baseline](2026-09-22-two-document-holdout-baseline.md), not a new independent holdout. Both PDFs and their labels were fixed before the baseline. We inspected the failures and changed the extractor, so the post-fix figures measure correction on known examples, not expected accuracy on unseen PDFs.

The baseline missed the right-margin labels `(5.1)` and `(6.8)` in Probability and indexed the proof's numbered steps `(1)`, `(2)`, `(3)` as equations in Linear Algebra. PDFKit showed the true labels at about 79% of page width and the proof steps at 27–32%; the original text order alone did not distinguish them. The extractor now uses the original page's geometry alongside text. It also rejects an inline Differential Equations citation at the right edge of a lemma line, preserving the equation label elsewhere on that page.

| Fixed corpus slice | Labelled pages | Introduced references | Source-only TP / FP / FN | Normal on-device TP / FP / FN | Located regions |
|---|---:|---:|---:|---:|---:|
| Probability notes | 8 | 12 | 12 / 0 / 0 | 12 / 0 / 0 | 12 / 12 |
| Linear Algebra notes | 8 | 8 | 8 / 0 / 0 | 8 / 0 / 0 | 8 / 8 |

All five negative pages were correctly empty in both modes. The normal on-device run accepted 17 model transcriptions and used three source fallbacks. Its sampled per-page median was 7.8 seconds; the source-only five-document aggregate was about 0.1 seconds. Timing varies substantially between model runs and is not a device-independent estimate.

We reran source-only indexing on the earlier Metric Spaces, Differential Equations I, and Complex Analysis labels. Together with the two post-fix documents, that is 50 labelled pages, 72 introduced references, 18 correctly empty pages, 72 / 0 / 0 TP / FP / FN, and 72 / 72 located regions. These are now all development examples: each has been inspected during tuning. The materials-discovery paper and image-only control remain separate and are not included in those numbers.

Reference-number accuracy is not transcription fidelity. For example, the accepted on-device rendering of Probability Theorem 6.13 changes the detailed-balance symbols from the PDF text. The PDF source excerpt and original page remain the default preview and answer evidence; AI formatting is explicitly marked as needing verification. Some PDF text layers themselves flatten mathematical layout, so even a verbatim excerpt needs comparison with the page image. The outstanding review queue includes repeated source mentions, mathematical fidelity, scans/OCR, two-column layouts, and an actual reader interaction check.

Local reproducible reports (ignored by Git): `tmp/postfix-model-probability`, `tmp/postfix-model-linear`, `tmp/postfix-v2-probability`, `tmp/postfix-v2-linear`, `tmp/postfix-dev-metric`, `tmp/postfix-v4-differential`, and `tmp/postfix-dev-complex`. The runner now fails if a SHA-256-bound label file is paired with a different PDF or if a page/report fails, so an incomplete run cannot be mistaken for a successful benchmark.
