# Answer evidence boundary — 2026-09-23

## Question

Can Cauchy tell a reader what evidence an assistant answer had without turning
a model's self-confidence into a false guarantee?

## Contract

Every answer is required to end with exactly one hidden declaration:

- `PDF`: every material claim is declared to follow from supplied PDF text;
- `MIXED`: the answer also uses outside knowledge or inference;
- `INSUFFICIENT`: the supplied text cannot establish a reliable answer.

If the declaration is absent or malformed, Cauchy stores `unverified`; it never
silently upgrades the reply. The control marker is removed from both streaming
and saved prose.

The saved answer also records:

- the selected page plus every retrieved reference/passage page actually sent;
- the number of reference statements and passages supplied;
- the assistant connector and requested model id when Cauchy controls it.

The UI calls this an answer basis and explains that supplied pages are
inspectable inputs, not automatic proof that every generated sentence follows.
Markdown and `.cauchyreading` exports retain the boundary and provenance.
The retrieval set is clipped to the provider's prompt budget before the ask;
pages dropped by that limit are excluded from saved provenance.

## Verification

- valid declarations parse and remain hidden;
- missing and malformed declarations become `unverified`;
- partial streaming markers never flash in the conversation;
- page provenance accepts only the page-labelled blocks Cauchy actually built;
- legacy messages decode with no invented evidence metadata;
- Markdown retains answer basis and supplied pages;
- the complete macOS test suite passes.

## Remaining limitation

The declaration is still produced by the answering model. Cauchy verifies the
marker vocabulary and the provenance of the supplied PDF pages, not semantic
entailment. A future benchmark should label individual claims and measure
whether `PDF`, `MIXED`, and `INSUFFICIENT` declarations are calibrated across
providers before this is presented as stronger than a transparent boundary.
