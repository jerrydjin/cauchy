# JERRY-76 step 1: arXiv source index

The reader index can be built from the arXiv e-print (`--latex-source`) and falls back to the PDF heuristics when the id is missing, the submission is PDF-only, the LaTeX is outside the subset, or the source text does not line up with the PDF. The Swift app is unchanged.

`dev_ids_wide.json` is not on main or any remote branch. Wide-60 is the original 20 in `ids.json` plus the 40 papers in `wide_sample.json`. The hidden holdout was not consulted.

Pass rule for the arXiv sets, unchanged: at least 8 in-scope references, at least 90% resolution, no wrong link, no citation opened as a local reference, no indexed statement absent from the declarations, and every probed section question on the heading page.

## Headline

| Set | Source on | Source off |
| --- | ---: | ---: |
| Original 20 | 16/20 | 15/20 |
| Wide 60 | 30/60 | 29/60 |
| Non-arXiv, full gate | — | 1/16 |
| Non-arXiv, resolution of printed refs | — | 13/14 |

On the wide set the source path passes 3 papers the PDF path fails, and fails 2 the PDF path passes. Wrong links and citation-as-local-ref stay at 0 on every set.

The non-arXiv full gate is the wrong summary for a chapter slice. Scored on printed theorem, lemma, definition, and equation spans alone, 13 of the 14 slices that have any such span resolve at least 90%. Two slices have none (examples or prose only), so that check does not apply. The one slice under 90% is Doty, at 0/2.

## Page placement

A repeated number is placed from the source item's own text (the statement after the heading, or the formula on the lines beside an equation tag) and from source order against neighbours that are already placed. A number that still names two pages is left out.

That is what moved 2610.18041 (78% to 100%) and 2610.19840 (83% to 96%) onto a pass. 2610.20976 is still a source-path fail at 89.7%, with a section question off the heading page, and a PDF-path pass at 91%.

## Where the arXiv paths disagree

| id | Source on | Source off | What changes |
| --- | --- | --- | --- |
| 2610.14417 | pass, 100% | fail, 95%, 1 false declaration | Source index removes the PDF false declaration |
| 2610.14991 | pass, 96% | fail, 96%, 1 false declaration | Source index removes the PDF false declaration |
| 2501.00275 | pass, 94% | fail, 94%, 2 false declarations | Source index removes the PDF false declarations |
| 2610.20976 | fail, 90%, section miss | pass, 91% | One equation number is still not placed, and a section question misses |
| 2610.22719 | fail, 96%, section miss | pass, 96% | The source outline and the PDF outline disagree on a heading page |

## Failure checks

A paper can fail more than one check.

| Check | Orig on | Orig off | Wide on | Wide off | Non-arXiv full gate |
| --- | ---: | ---: | ---: | ---: | ---: |
| Pass | 16 | 15 | 30 | 29 | 1 |
| Resolution under 90% | 4 | 2 | 19 | 17 | 12 |
| False declaration | 1 | 5 | 10 | 19 | 0 |
| Section question | 1 | 0 | 13 | 10 | 10 |
| Fewer than 8 in-scope refs | 0 | 0 | 1 | 1 | 2 |
| Wrong link | 0 | 0 | 0 | 0 | 0 |
| Citation opened as a local ref | 0 | 0 | 0 | 0 | 0 |

Wide-60 source fallbacks (17 papers): redefined `\section` (3), source text does not line up (3), a theorem head wrapped in `\protect` (3), and one each of a cyclic counter, an empty head, multiple main files, an alphabetic counter, a head outside the subset, a broken environment definition, a redefined `\subsubsection`, and an undefined theorem environment.

The PDF-path change (line-start headings, below) did not move the original 20 with the source path off. It moved the wide set from 28/60 to 29/60.

## Non-arXiv: the 0/16, before any PDF-path change

Resolution here is printed spans of the form "Theorem 1.2" or "(1.2)", one count per occurrence. A declaration the page never prints in that form is not a missed reference. The minimum of 8 applies only when there are at least 8 such spans. The section question applies only when the slice has a numbered heading.

**(a) The full gate does not apply — 8 slices.** Printed resolution was already at least 90%, or there was nothing to resolve. The gate failed on a section question with no numbered sections, on the minimum of 8, or because an unprinted "section N" was counted as a reference.

| Slice | Printed resolution | What does not apply |
| --- | --- | --- |
| Lebl, sequences | 34/34 | The 89% full-gate rate is 4 unprinted section mentions. The section question does apply, and it misses: "2.1" is on its own line and the title is on the next. |
| Lebl, holomorphic functions | 15/15 | No numbered section in the slice. |
| Lebl, first-order equations | 18/18 | Figure captions and slope-field ticks had been counted as sections. After that correction the section questions pass and the full gate passes. |
| Treil, bases | 18/18 | Section questions pass. The 48% full-gate rate is 21 unprinted section mentions. |
| Keller and Trotter, binomial coefficients | 5/5 | Fewer than 8 refs, and no numbered section. |
| Open Logic, sets | 46/46 | Section questions pass. The 83% full-gate rate is 12 unprinted section mentions. |
| Levin, counting | none | Examples only. Resolution and the minimum of 8 do not apply. |
| forall x Calgary | none | Definitions are prose. Resolution and the minimum of 8 do not apply. Section questions pass. |

**(b) Genuinely low resolution — 4 slices.** At least 8 printed refs, and the slice has numbered sections. These are the only slices the PDF reader was changed for.

| Slice | Before | Cause |
| --- | --- | --- |
| Nicholson, linear systems | 1/17 | `Theorem 1.1.1` is alone on the line. The statement is the next line. |
| Kuttler, determinants | 54/64 | `Lemma 3.33` and `Theorem 3.35` are alone on the line. |
| Grinstead and Snell, probability | 2/12 | `Theorem 1.1 The probabilities...` runs the statement on with no period. |
| MCS, number theory | 65/93 | Theorems were indexed. A dotted tag such as `(9.1)` is alone on the line, and the formula above it uses glyphs rather than `=`. |

**(c) Both — 4 slices.** Printed resolution was low, and the slice also has no numbered section or fewer than 8 printed refs. The reader was not aimed at these. The same line-start rule happens to cover three of them, because the heading shape is the one group (b) needed.

| Slice | Before | Why the test is a poor fit |
| --- | --- | --- |
| Doty, permutation groups | 0/2 | Labels are number-first (`6.1 Definition.`). Only two spans are printed as "Theorem N". No numbered sections. Not changed. |
| Judson, groups | 0/8 | No numbered sections. `Theorem 4.9 Every cyclic group is abelian.` has no period. |
| Crisman, division | 0/17 | No numbered sections. `Theorem 2.1.1` is alone on the line. |
| Guichard, derivatives | 0/1 | One printed theorem (`THEOREM 4.3.1` on its own line). The minimum of 8 does not apply. |

## What changed in the PDF path

Two general rules, with synthetic fixtures only:

- A line-start label is a declaration when the line ends and the next line does not start with a lowercase word, or when the same line continues with a capital. `Theorem 1.1 shows` and `Lemma 2.2, so` stay mentions.
- A dotted equation number that is the whole line is a declaration when the previous line is a short formula. A long sentence above the tag is not.

After that, the four group (b) slices resolve at 17/17, 64/64, 12/12, and 88/89. Judson, Crisman, and Guichard move to 100% of their printed spans as a side effect. Doty stays at 0/2.

## Expected labels that were too strict

- A comma after the number is a mention. MCS "Lemma 9.1.2.2, so ..." cites a clause of Lemma 9.1.2. It is not a declaration numbered 9.1.2.2.
- A line that is only a decimal, followed by another decimal, is a slope-field tick.
- A figure caption is not a section. Lebl's first-order chapter had "5.0" / "Figure 1.8..." and "10.0" / "Figure 1.12..." in the expected sections. Removing them is why that slice now passes the full gate.
- A bookmark whose first word is lowercase is the rest of a sentence. Kuttler's "33.7 and the only nonzero term..." was one. The real section questions in that chapter still miss (3.1 is predicted two pages late).

## Recommendation

Do not port this to Swift yet. The source path now leads, 16/20 against 15/20 and 30/60 against 29/60, after the page-placement change. One paper on each set is not a clear margin, and 2610.20976 still passes only on the PDF path. The non-arXiv full gate remains a bad fit for a chapter: most of the old 0/16 was the test. On the resolution check that does apply, the line-start fix covers the fair failures. The leftover textbook gap is number-first labels and headings whose number and title sit on different lines.
