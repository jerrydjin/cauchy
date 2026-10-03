# Evidence-first reference indexing: initial result

Date: 2026-09-22  
Document: 77-page technical notes, identified in the corpus by SHA-256  
Labelled slice: 12 visually reviewed pages, 23 introduced references, 4 hard-negative pages

This is a development result on one labelled document, not a general product-quality
claim. The corpus deliberately includes a table of contents, citation-heavy pages,
continuation pages, blank pages, examples, definitions, lemmas, theorems,
propositions, a corollary, and a numbered equation.

## What changed

The original pipeline asked the on-device model both to discover and transcribe
references. The revised pipeline separates responsibilities:

1. Deterministic parsing finds declaration-shaped candidates in the PDF text.
2. The model transcribes and formats candidate bodies.
3. Citation, source-grounding, and formatting checks reject unsupported results.
4. When a strong named declaration is missed or malformed, Cauchy retains lightly
   cleaned PDF text and marks it as a source fallback rather than silently dropping it.
5. Every accepted entry stores a verbatim evidence excerpt and reports whether its
   source occurrence is unique or ambiguous.

## Before and after

| System | Precision | Recall | F1 | False positives | False negatives |
|--------|----------:|-------:|---:|----------------:|----------------:|
| Original production extractor | 88.2% | 65.2% | 75.0% | 2 | 8 |
| Evidence-first hybrid extractor | 100.0% | 100.0% | 100.0% | 0 | 0 |
| All syntactic mentions baseline | 67.6% | 100.0% | 80.7% | 11 | 0 |
| Declaration heuristic baseline | 95.8% | 100.0% | 97.9% | 1 | 0 |

The hybrid correctly abstained on all 4 negative pages and missed no positive page.
Of 23 final references, 19 used accepted model transcriptions and 4 used explicit
source fallbacks. Four citation-like model outputs were rejected. Two accepted
entries had multiple matching source occurrences and remain visibly marked
uncertain for review.

## Latency

The initial evidence-first run averaged 19.6 seconds per model-invoked page and
projected about 25 minutes for the full document at serial on-device inference.
After declaration-focused prompts and citation-only prefiltering were added for
the two-column paper, the complete 12-page slice was replayed on the final build:
23/23 references, 0 false positives, and 4/4 correct abstentions. Of those 23,
17 used accepted model transcriptions and 6 used source fallbacks. All 12 pages
completed without extraction errors. Model-invoked pages averaged 19.8 seconds;
end-to-end mean across all sampled pages including skips was 13.2 seconds,
median was 7.6 seconds, interpolated p95 was 49.0 seconds, and maximum was 89.8
seconds. This mix projects about 17 minutes for all 77 pages, but projection
varies with the density of declarations and device-model generation latency.

## What this does and does not prove

This run proves that the revised implementation exactly matched the 23 labels in
this fixed slice and that its evidence/provenance contract is exercised end to end.
It does not prove perfect quality on arbitrary PDFs. The next research milestone is
to expand the corpus across scans, two-column papers, other disciplines, and held-out
documents without tuning against their labels.

## Subsequent body audit

After adding per-reference model/source comparisons to the local report, another
complete 12-page run still recovered 23/23 labels with no false positives and
4/4 correct abstentions. It accepted 20 model bodies and used three source
fallbacks, illustrating inference variability across runs. Manual inspection
found an accepted equation body ending mid-inequality and an accepted definition
that changed a subscript to an exponent. A separate fallback had previously
continued into the next numbered section; that boundary and the formerly
one-line evidence preview were corrected and tested.

The detection score is therefore not a semantic-fidelity score. Answer retrieval
now injects the exact PDF text excerpt instead of an unverified model body;
formatted transcriptions are an optional reading aid beside the original page.
