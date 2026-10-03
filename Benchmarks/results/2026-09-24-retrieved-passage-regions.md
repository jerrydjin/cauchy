# Retrieved passage regions: first real-PDF probe

The source is the 114-page *Complex Analysis* notes bound by SHA-256 in
`corpus/complex-analysis.ground-truth.json`. The PDF remains outside the repo.
This checks whether the production lexical index can locate the text it sends
to Ask on the original page; it does **not** check answer correctness.

With the freshly built app, `--probe-retrieval PDF 'holomorphic function
derivative'` returned five passages. All five had a unique text-layer span
that PDFKit re-resolved to a normalized page region: pages 11, 10, 5, 107,
and 11, in ranking order. Pages 10 and 11 were rendered and visually inspected:
the page-10 region contains Definition 1.1.1 and the page-11 regions cover
the derivative discussion and Definition 1.1.4. The page regions enclose the
retrieved chunks, which can span multiple paragraphs; they are not yet
claim-specific highlights. The other three regions were text-layer checked
but not visually inspected in this probe.

The indexer refuses a location when a chunk's source text is missing or
non-unique on the page. An ask also drops the location if the prompt budget
truncates the passage. This is a single development query on a born-digital
mathematics PDF, not an estimate of region coverage across the corpus.
