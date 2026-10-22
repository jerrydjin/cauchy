# Evidence-first reference indexing: two-column research paper

Date: 2026-09-22  
Document: *Scaling deep learning for materials discovery*, Nature 624, 80–85 (2023)  
DOI: 10.1038/s41586-023-06735-9  
Labelled slice: all 11 PDF pages, 1 introduced reference, 10 hard-negative pages

This is a development result on one sparse, citation-heavy paper. It is useful as
an abstention and failure-recovery test, not as a general product-quality claim.
The paper contains two-column text, four dense figures, a numbered bibliography,
chemical formulae, inline mathematics, and one displayed equation numbered (1).

## Blind first run

The page labels were fixed before the extractor was run. The original hybrid
pipeline rejected all citation and bibliography false positives, but missed the
one true equation:

| System | Precision | Recall | F1 | False positives | False negatives |
|--------|----------:|-------:|---:|----------------:|----------------:|
| Hybrid extractor before this corpus fix | 100.0% | 0.0% | 0.0% | 0 | 1 |
| All syntactic mentions baseline | 2.4% | 100.0% | 4.7% | 41 | 0 |
| Declaration heuristic before this corpus fix | 0.0% | 0.0% | 0.0% | 10 | 1 |

The first run also spent 73.7 seconds and 27.1 seconds asking the local model to
interpret bibliography-only pages, then spent 190.7 seconds on the equation page.
This exposed both a recall defect and a costly routing defect.

## Final run

The corrected declaration guard recognizes an equation number placed on its own
line only when a preceding display contains strong mathematical operators. It
rejects citation years and ordinary “see equation” mentions. The same guard now
skips model inference on citation-only pages, and the on-device prompt is bounded
to context around source-backed declarations. If the model exceeds its context
window, Cauchy retains an explicitly labelled source fallback with verbatim
evidence instead of losing the reference.

| System | Precision | Recall | F1 | False positives | False negatives |
|--------|----------:|-------:|---:|----------------:|----------------:|
| Evidence-first hybrid extractor | 100.0% | 100.0% | 100.0% | 0 | 0 |
| All syntactic mentions baseline | 2.4% | 100.0% | 4.7% | 41 | 0 |
| Declaration heuristic | 100.0% | 100.0% | 100.0% | 0 | 0 |

The production extractor correctly abstained on all 10 negative pages and retained
equation (1) as an exact-source fallback. Seven pages contained no syntactic
reference mention, and three citation-only pages were rejected before model
inference.

## Latency and degradation

Ten pages completed in 0.2–1.3 seconds. The single model-invoked page took 159.5
seconds, exceeded the on-device model context during generation, and degraded to
the source fallback. End-to-end mean latency over all 11 pages was 14.9 seconds;
median was 0.4 seconds, interpolated p95 was 80.4 seconds, and maximum was 159.5
seconds. The benchmark now reports this context overflow in its failure atlas;
the perfect extraction score must not be read as perfect model behaviour.

## What this does and does not prove

This run proves that Cauchy can distinguish one real numbered equation from 41
syntactic distractors in this fixed paper, preserve inspectable evidence, and
complete the page even when local formatting fails. It does not prove that the
equation text layer is pleasant to read, that other two-column papers behave the
same way, or that the current on-device latency is acceptable. Those remain corpus
and product-quality questions.
