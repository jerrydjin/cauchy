# First navigable citation edges

The reference panel now searches text after an indexed reference's defining label, including the rest of that page and subsequent pages, for its exact kind and number. A result is an observed text-layer mention, not an inferred dependency. Each retained mention must resolve to a region on the original page; unresolved matches are counted separately. The panel jumps to the citation's surrounding region and states when pages have no searchable text.

Smoke test on the local, born-digital Complex Analysis notes:

```sh
Cauchy --probe-mentions /path/to/part_a_a2_complexanalysis_notes.pdf theorem 2.2.13 44
```

Theorem 2.2.13 is introduced on PDF page 44. The probe found three anchored later mentions, on PDF pages 45, 46, and 51, with zero unlocated matches. The three pages were rendered and visually inspected. Page 45 introduces a consequence; page 46 explicitly invokes the theorem inside a proof; page 51 invokes it in another proof. One later page in the document has no searchable text; the search reports that limitation rather than claiming full recall.

An additional visual check found a same-page citation of Probability equation 5.1 beneath its displayed formula, and a Linear Algebra proof that cites Theorem 3.9 across a PDF text-layer line break. The search now includes the former and shows the proof context rather than just the bare theorem number for the latter.

The SHA-256-bound, hand-labelled development slice in `corpus/reference-mentions.ground-truth.json` covers four references across four PDFs: Complex Analysis Theorem 2.2.13 (pages 45, 46, 51), Linear Algebra Theorem 3.9 (page 17), Probability equation 5.1 (same PDF page 40), and Metric Spaces Definition 3.1.1 (no later mention). The built app returned 5 true positives, 0 false positives, 0 false negatives, and 0 unlocated matches. Five scanned pages had no searchable text across these searches; blank pages are included in that count.

This is still a narrow development result, not a generalization estimate or a complete evidence graph. The four cases were inspected while tuning, text matches do not establish logical use, figure links are absent, and the graph is not yet stored in `.cauchyreading`. The index is needed to choose the defining reference; mention search itself uses only local PDF text and geometry and makes no model call.
