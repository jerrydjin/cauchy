# Figure captions: independent first-pass holdout

The predeclared holdout is an 81-page differential-equations lecture PDF,
bound by SHA-256 in `corpus/differential-equations-figures.holdout.ground-truth.json`.
We visually checked PDF pages 7 and 30–38, labelling eight figure captions
on six pages and four figure-negative pages before running the indexer.
The document was used in earlier equation/theorem development, but these
figure labels were not used to tune figure detection. It is therefore a
holdout for this particular feature, not for the entire reference index.

The first source-only run found all 8/8 figures, with 0 figure false positives
and 0 misses. All eight caption labels had resolvable page regions. It also
extracted five equations outside the figure scoring scope; one first-run
failure-atlas note described ambiguity in two equation matches on page 32,
not a figure error. The benchmark now explicitly reports `evaluatedKinds`
and scopes its failure atlas accordingly, without changing the extractor or
the predeclared labels.
The one-pass graph built all eight figure nodes without an error; none had a
later numbered text-layer citation in this PDF.
After this baseline, inspecting another corpus PDF exposed a wrapped caption
title; Cauchy now retains a clearly continuing lowercase line before the
first sentence ends. That fidelity change does not alter these figure labels
or the first-pass detection result.

This slice checks a second caption style (`Figure 2.1:`), a citation before
the caption, and two pages containing two figures each. It does not test
many citation-only figure negatives, scanned captions, full visual regions,
or interpretation of the plotted data. Those remain open requirements.
