# Figure-caption evidence: first development slice

The source is *Scaling deep learning for materials discovery*, Nature 624,
80–85 (2023), DOI 10.1038/s41586-023-06735-9, bound to the SHA-256 in
`corpus/materials-figures.ground-truth.json`. The PDF is kept outside the
repository. We rendered and visually checked the ten labelled pages before
scoring, including the three multipanel figures and citation-only pages.

The first source-only run over the 10-page labelled slice returned Figure 1
on PDF page 2, Figure 2 on page 3, and Figure 3 on page 5: 3 true positives,
0 false positives, 0 false negatives, and 3/3 resolvable caption-label page
regions. It made no model calls. The all-syntactic-mentions baseline had
47 false positives because it promoted panel citations to figure definitions.
The production route produced the same 3/0/0 result and correctly skipped
model inference on every figure-only page.
With the main 11-page materials labels updated to include these captions and
the existing displayed equation (1), the same source-only path found all
four introduced objects with 0 false positives, 0 misses, and 4/4 anchors.

The separately labelled later-mention slice includes same-page citations,
panel suffixes, and paired plural citations such as “Figs. 1 and 2” and
“Figures 1e and 3a,b”. The direct search and the one-pass portable graph
each found 15/15 expected occurrences with 0 false positives, 0 misses,
and 0 unresolved page regions. These are printed text matches, not claims of
scientific dependency.

This is a development example: the paper informed the caption and plural
pattern rules. The figures' plotted values, image regions, and full captions
are *not* verified or extracted; Cauchy stores the printed caption heading
and opens the original page for human inspection. The result is not an
independent estimate of precision or recall on other papers.

The wrapped Figure 2.5 heading in the Complex Analysis notes was checked
separately: its first sentence spans two PDF text lines. The source-only
index now retains both lines verbatim, yielding the complete printed title
without absorbing the following Example 2.4.5. The updated 12-page Complex
Analysis slice returned 24/0/0 introduced references with 24/24 label anchors;
this is an inspected development corpus, not independent validation.

The full macOS unit suite passed after this change: 133 tests, 0 failures.

Reproduce with the built app and this local PDF using
`--benchmark-indexing PDF --ground-truth Benchmarks/corpus/materials-figures.ground-truth.json --source-only`.
For citation edges, run `Benchmarks/evaluate_mentions.py` with
`--labels Benchmarks/corpus/materials-figure-mentions.ground-truth.json`
and repeat with `--graph`.
