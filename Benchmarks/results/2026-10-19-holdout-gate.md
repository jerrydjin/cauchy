# Holdout gate

Date: 2026-10-19. The paper list is not in this repository. This note has counts and the names of the checks that fail. No application code was changed.

## Counts

The development set in `ids.json` is **11/20** on the main profile. That is the audited recount in `2026-10-19-independent-audit.md`, using only the corrections marked CORRECT through `2b76db8`.

The holdout is 20 other math papers. One primary `math.*` category each, so twenty categories and at most one paper in any primary category. Five papers in each of 2023, 2024, 2025, and 2026. Seventeen calendar months, and at most three papers in any month. Eligibility matches `run.py`: LaTeXML HTML that contains an internal reference. None of the papers is in `ids.json` or in the two edge cases.

Both runs use the grader on the scorecard tip (`score.py`, `ground_truth.py`, `pdf_extract.py`, and `run.py` at `5ec11b1`), including printed-number scoring. Only `cauchy_logic.py` changes.

| Run | Reader port | Main profile |
|---|---|---:|
| Development set | audited main profile | 11/20 |
| Holdout, main's port | `cauchy_logic.py` at `68f3bb4`, before the ports in PRs #11–#15 | 0/20 |
| Holdout, combined port | `cauchy_logic.py` at `5ec11b1` | 3/20 |

The combined port is the scorecard tip. It carries the Python ports of PRs #11–#15 and the later change that indexes an equation whose formula is on the next line (`877ed3e`). Printed-number scoring lives in the shared grader, so it is on for both holdout runs.

The hover profile, which leaves the section locator off, is 0/20 on both ports: every section question misses. The chat profile matches the main profile. The hover-plus-structure profile matches it too: 0/20 on main's port and 3/20 on the combined port. The numbers next to 11/20 are the main profile.

The three combined-port passes all fail on main's port. Nothing passes on main's port.

## Show HN gate

The bar is **16/20** on this holdout, combined port, main profile, under the same pass rule as the 11/20. The measured result is **3/20**. The gate is not met.

## Checks that fail

The pass rule, in order: at least 8 in-scope references, resolution at least 90%, no wrong link, no citation emitted as a local reference, no indexed statement absent from the HTML, and every probed “what is section N about” on the heading page. “First” is the earliest check a failing paper hits. “Blocking” counts every paper that fails that check. A paper can fail more than one.

### Main's port

0 pass, 20 fail.

| Check | First | Blocking |
|---|---:|---:|
| fewer than 8 in-scope references | 1 | 1 |
| resolution under 90% | 9 | 9 |
| wrong link | 4 | 7 |
| citation emitted as a local reference | 5 | 16 |
| indexed statement absent from the HTML | 1 | 9 |
| section question missed the heading page | 0 | 20 |

Of 69 section probes, 11 land on the heading page, 53 return no page, and 5 land on a different page.

### Combined port

3 pass, 17 fail.

| Check | First | Blocking |
|---|---:|---:|
| fewer than 8 in-scope references | 1 | 1 |
| resolution under 90% | 8 | 8 |
| wrong link | 1 | 1 |
| citation emitted as a local reference | 1 | 3 |
| indexed statement absent from the HTML | 2 | 6 |
| section question missed the heading page | 4 | 9 |

Of 69 section probes, 56 land on the heading page, 5 return no page, and 8 land on a different page.

Dropping the section check would leave 7 of 20 passing on the combined port and none on main's port. That is not the pass rule, and it is not the gate.

## What the fix branches special-case

Diffs of PRs #11–#15 against `origin/main`. Nothing under `Cauchy/` branches on an arXiv id, an author, or `arxivId`. The matches below are tests and snapshot fixtures. The ids are from the development set, which is already in `ids.json`.

- PRs #11 and #15, `CauchyTests/AskStructureLocatorTests.swift`. `testTopLevelNumberedTitleIsThatSection`, `testDottedHeadingWithAClosingPeriodIsThatSubsection`, `testDottedHeadingDoesNotSatisfyAnUndottedSectionQuery`, `testNumberedSentenceIsNotASectionHeading`, and `testOutlineNumberedTitleMatchesTheSameSection` use the opening of `2610.11661`: “1. Introduction” and “A Poisson algebra is both an associative algebra and a Lie algebra.”, and the headings “2.1. Generalities.”, “3. Construction theorems”, and “3.1. From BiHom-associative conformal superalgebras.” Some sentences after those headings were written for the test.
- PR #15, `testMathFragmentIsNotASectionHeading`, uses “1 + z7 holds in characteristic 7. Hence the relation is strict.” The audit quotes that line from `2610.15448`, PDF page 11, as “1 + z^7 holds in characteristic 7. Hence”. The test flattens the superscript. The same test also includes synthetic lines (“Section 4 constructs the approximate metric…”, “4. Clique-sum”).
- PR #15, `testUnnumberedOutlineBookmarksAreSectionsInOrder`, uses the outline titles Introduction, Preliminaries, Proof of the main result, and Low homogeneous subspaces. Those are the headings the audit quotes from `2610.15448`. A child bookmark titled “Virasoro notation” is also in the fixture. `testNumberedSiblingKeepsItsNumberBesideIntroduction` uses an unnumbered Introduction beside “1. Preliminaries” and “2. Affine realizations”; that second title was not matched to a development-set paper.
- PR #12, `testCitationBracketSplitAcrossALineIsNotALocalTheorem`, uses “the weak-holomorphy criterion [17, Theorem 3.31(c)] shows that G is analytic.” The audit quotes that sentence from `2610.18041`, PDF page 10. `Snapshots/Fixtures/2610.04096-references.txt` and `Snapshots/RenderCitationHover.swift` are that paper’s bibliography, captioned for a hover on `[BEO23, Conjecture 1.4]`. Production patterns are generic examples (`IK99`, `BO09b`, Smith 2019, `Theorem 3.31(c)`). They are not keyed to an id.
- PR #14, `Snapshots/Fixtures/2610.04096-lemmas.json` and `Snapshots/RenderFindList.swift`, captioned for Cmd-F “Lemma 2” on `2610.04096`. “Zorn” appears as the doc-comment example “Lemma 2.4 (Zorn)” in `LLMReferenceIndexBuilder.swift`. Hamming-distance tests are synthetic. Neither name is one of the twenty papers.
- PR #13, `testLeftMarginEnumeratedStepsAreNotEquations`, uses a synthetic “(1) f ∈ W ⇒ f = 0”. No development-set id or author.

The fixtures can pin a fix to a development paper. They are not a runtime bypass.

## Where the list is

The id list and the per-paper score files are outside the repository. `run.py` accepts `--ids` and can write the scorecard JSON and markdown to other paths, so a private list does not replace `ids.json` or the committed scorecard.
