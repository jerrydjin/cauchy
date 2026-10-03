# Source-only reference indexing: three-document development comparison

The `--source-only` benchmark runs Cauchy's existing page prefilters and
source-backed declaration fallbacks without calling a language model. It does
not change the reader's production indexing mode. These are the same fixed,
iteratively tuned labels used in the model-backed development runs.

| Document | Labelled pages | Introduced references | Source-only TP / FP / FN | Negative pages | Exact page regions |
|----------|---------------:|----------------------:|------------------------:|---------------:|-------------------:|
| Metric Spaces notes | 12 | 23 | 23 / 0 / 0 | 4/4 | 23/23 |
| Differential Equations I notes | 10 | 6 | 6 / 0 / 0 | 6/6 | 6/6 |
| Complex Analysis notes | 12 | 23 | 23 / 0 / 0 | 3/3 | 23/23 |
| **Combined** | **34** | **52** | **52 / 0 / 0** | **13/13** | **52/52** |

Median page time was 0.1 seconds, interpolated p95 was 0.2 seconds, and maximum
was 0.2 seconds on this machine. The model-backed development run had the same
reference-number accuracy on these three documents but spent up to 94.5 seconds
on a single Complex Analysis page in a fresh check (8.2 seconds on an earlier
run). Model timing is variable; this is not a controlled speedup estimate.

Six accepted references had multiple matching text occurrences (two in each
document). They remain marked as ambiguous; a resolved visual region is a
candidate location, not proof that the chosen occurrence is the defining one.
The source-only bodies are lightly cleaned PDF text, so notation can still be
awkward or incomplete even when the label and location are correct. Answer
retrieval uses the retained verbatim PDF excerpt, not the cleaned body.

This comparison supports testing a fast source-first reader path. It does not
justify replacing the current default yet: these labels were used while tuning
the heuristic, the two-column materials paper was not included in this run,
and scanned PDFs currently have insufficient text for this path. A held-out
corpus and reader-level inspection are needed before claiming generality.
