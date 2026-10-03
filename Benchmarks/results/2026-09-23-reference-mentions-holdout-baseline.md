# First independent later-mention check

The labels in `corpus/reference-mentions.holdout.ground-truth.json` were written before the mention finder was run on this reference. The local Differential Equations I PDF visibly introduces Theorem 1.4 on PDF page 20. The same page later says “Proof of Theorem 1.4”; page 25 refers to modifying its proof. Both source pages were rendered and visually inspected before running the app probe. A literal PDF text search found no other later occurrence of that reference string.

First built-app run: 2 true positives, 0 false positives, 0 false negatives; both returned citations had resolvable page regions, and the search encountered no pages without searchable text. The defining theorem heading was not returned as a later mention.

This is one reference in one born-digital mathematics PDF, not a corpus-level quality estimate. The four-case development set is reported separately in `2026-09-23-later-mentions-probe.md`. Preserve this first result if the finder is later tuned on Theorem 1.4 or this document.
