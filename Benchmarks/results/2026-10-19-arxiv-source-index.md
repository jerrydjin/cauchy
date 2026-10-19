# JERRY-76 step 1: arXiv source index

The reader index can be built from the arXiv e-print (`--latex-source`) and falls back to the PDF heuristics when the id is missing, the submission is PDF-only, the LaTeX is outside the subset, or the source text does not line up with the PDF. The Swift app is unchanged.

`dev_ids_wide.json` is not on main or any remote branch. Wide-60 is the original 20 in `ids.json` plus the 40 papers in `wide_sample.json` (two per math category, years 2021–2026, LaTeXML HTML, excluding `ids.json` including its edge cases). The hidden holdout was not consulted.

Pass rule, unchanged: at least 8 in-scope references, at least 90% resolution, no wrong link, no citation opened as a local reference, no indexed statement absent from the declarations, and every probed section question on the heading page.

## Headline

| Set | Source on | Source off |
| --- | ---: | ---: |
| Original 20 | 14/20 | 15/20 |
| Wide 60 | 25/60 | 28/60 |
| Non-arXiv chapters | — | 0/16 |

On the wide set the source path passes 4 papers the PDF path fails, and fails 7 papers the PDF path passes.

## Original 20, where the two paths disagree

| id | Source on | Source off | What changes |
| --- | --- | --- | --- |
| 2610.14417 | pass, 100% | fail, 95%, 1 false declaration | Source index removes the PDF false declaration |
| 2610.14991 | pass, 96% | fail, 96%, 1 false declaration | Source index removes the PDF false declaration |
| 2610.20976 | fail, 75%, section miss | pass, 91% | Equation (1.3) is a right-margin label on two pages, so it is omitted |
| 2610.18041 | fail, 78% | pass, 97% | Bare equation numbers are not unique on the page, so they are omitted |
| 2610.19840 | fail, 83% | pass, 96% | References to statements that were not placed on a page |
| 2610.04096 | fail, 87% | fail, 87%, 1 false declaration | Same three mentions the detector never sees; source drops the false declaration |
| 2610.19333 | fail, 74%, 8 false | fail, 74%, 7 false | PDF prints (3.3)–(3.10); the HTML tags do not |
| 2610.21864 | fail, 81% | fail, 98%, 4 false | Source drops the false declarations and loses resolution |

Eighteen of the twenty use the LaTeX index. Two fall back (`redefined \section`, cyclic counter) and still pass on the PDF path.

## Failure checks

A paper can fail more than one check.

| Check | Orig on | Orig off | Wide on | Wide off | Non-arXiv off |
| --- | ---: | ---: | ---: | ---: | ---: |
| Pass | 14 | 15 | 25 | 28 | 0 |
| Resolution under 90% | 6 | 2 | 26 | 18 | 14 |
| False declaration | 1 | 5 | 10 | 19 | 0 |
| Section question | 1 | 0 | 13 | 10 | 10 |
| Fewer than 8 in-scope refs | 0 | 0 | 1 | 1 | 2 |
| Wrong link | 0 | 0 | 0 | 0 | 0 |
| Citation opened as a local ref | 0 | 0 | 0 | 0 | 0 |

Wide-60 source fallbacks (17 papers): unrecognised theorem head (5), redefined command (4), source text does not line up (3), and one each of a cyclic counter, multiple mains, an alphabetic counter format, a broken definition, and an undefined theorem environment.

## Non-arXiv

Sixteen chapter slices, source path off. Licenses were read from the opening pages (CC BY, CC BY-SA, CC BY-NC-SA, CC BY-ND, CC BY-NC-ND, GFDL). Areas: algebra, analysis, complex analysis, differential equations, linear algebra, number theory, probability, calculus, discrete mathematics, combinatorics, logic. Declarations are lines that begin with the label; Doty puts the number first; equation numbers end the line. Section pages are numbered outline bookmarks, or a line that is only the section number. Discrete Analysis journal PDFs came back empty, so there is no journal article in the set. Details and the per-item notes are in `Benchmarks/nonarxiv_scorecard/scorecard.json`.

Two slices resolve at least 90% of the hand-checked labels (Lebl's holomorphic-functions chapter, 100% of 15; Keller and Trotter's binomial chapter, 100% of 5). Both still fail, one on the section question and one on the minimum of 8 references. Nine slices resolve under half. forall x Calgary states definitions in prose and has no numbered theorem label. None of the 16 pass the gate.

## Recommendation

Do not port this to Swift yet. The source path is the right idea and it does remove PDF false declarations, including two original-20 failures. It does not clearly beat the PDF heuristics: 14 against 15 on the original 20, and 25 against 28 on the wide 60. The losses are statements that are numbered correctly and then left out because the page match is not unique, so every reference to them fails. The non-arXiv gate is also unmet at 0/16. Keep the flag, and close the page-placement gap before a Swift port.
